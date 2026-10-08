#!/usr/bin/env bash
# TeammateIdle gate: a teammate must report before it goes idle.
#
# Blocks (exit 2) a teammate from going idle when its current turn contains no
# SendMessage call, so finished work does not vanish into a transcript nobody
# reads. Claude Code feeds stderr back to the teammate, which keeps working.
#
# What counts as "the current turn"
#   Everything after the last message the teammate RECEIVED (a user entry with
#   text content: the spawn prompt, a message from the lead or a teammate).
#   Tool results and hook feedback ("TeammateIdle hook feedback: ...") do not
#   start a new turn, so a continuation forced by this gate is judged together
#   with the turn that was blocked. The anchor is found by content, never by a
#   stored line count, so it cannot drift as the transcript grows.
#
# Which transcript
#   For in-process teammates, transcript_path in the payload is the LEAD's
#   session file; the teammate's own calls live in
#   <session>/subagents/agent-<id>.jsonl. Resolution order:
#     1. agent_transcript_path, if the payload has it
#     2. <session>/subagents/agent-<agent_id>.jsonl, if agent_id is present
#     3. <session>/subagents/*.meta.json whose name (or agentType) equals
#        teammate_name; newest match wins
#     4. transcript_path itself, but only when no subagents/ folder sits next
#        to it (split-pane teammates run as their own session)
#   If none resolves, the gate fails open: it never judges the wrong file.
#
# Release rules (the gate can never loop)
#   - pass when the turn has a SendMessage call
#   - pass when the turn has no assistant output at all (nothing to judge)
#   - nudge at most AGENT_TEAM_IDLE_MAX_NUDGES times per turn (default 1);
#     counted from this gate's own feedback in the transcript and, as a
#     backstop, from a small state file keyed by the turn's anchor. State can
#     only make the gate more lenient, never stricter.
#
# Env:
#   AGENT_TEAM_IDLE_GATE=off        disable this gate
#   AGENT_TEAM_IDLE_MAX_NUDGES=N    nudges per turn before releasing (default 1)
#   AGENT_TEAM_STATE_DIR=path       state dir (default .claude/hooks/.state)
set -uo pipefail

MARKER='[teammate-idle-gate]'

[ "${AGENT_TEAM_IDLE_GATE:-on}" = "off" ] && exit 0

if ! command -v jq >/dev/null 2>&1; then
  echo "teammate-idle-gate: jq is required but not installed; gate not enforced" >&2
  exit 1
fi

payload="$(cat)"
jq -e 'type == "object"' >/dev/null 2>&1 <<<"$payload" || exit 0 # malformed input: fail open

field() { jq -r --arg k "$1" '.[$k] // "" | tostring' <<<"$payload"; }
tp="$(field transcript_path)"
atp="$(field agent_transcript_path)"
aid="$(field agent_id)"
name="$(field teammate_name)"
root="${CLAUDE_PROJECT_DIR:-$(field cwd)}"
root="${root:-.}"

note() { echo "teammate-idle-gate: $*" >&2; } # exit-0 stderr goes to the debug log only

# ---------------------------------------------------------------- transcript
transcript=""
subdir="${tp%.jsonl}/subagents"
if [ -n "$atp" ] && [ -f "$atp" ]; then
  transcript="$atp"
elif [ -n "$aid" ] && [ -f "$subdir/agent-$aid.jsonl" ]; then
  transcript="$subdir/agent-$aid.jsonl"
elif [ -n "$name" ] && [ -d "$subdir" ]; then
  # newest first; meta files are small JSON objects written by Claude Code
  while IFS= read -r meta; do
    if jq -e --arg n "$name" '.name == $n or .agentType == $n' "$meta" >/dev/null 2>&1; then
      candidate="${meta%.meta.json}.jsonl"
      if [ -f "$candidate" ]; then transcript="$candidate"; break; fi
    fi
  done < <(ls -t "$subdir"/*.meta.json 2>/dev/null)
elif [ -n "$tp" ] && [ -f "$tp" ] && [ ! -d "$subdir" ]; then
  transcript="$tp"
fi

if [ -z "$transcript" ]; then
  note "could not locate the transcript of teammate '${name:-?}'; not judging"
  exit 0
fi

# ---------------------------------------------------------------- judge turn
# One pass over the transcript. Malformed or half-written lines are skipped.
# Output: "<anchor-id> <assistant-entries> <sendmessage-calls> <own-nudges>"
verdict="$(jq -R 'fromjson? // empty' "$transcript" 2>/dev/null | jq -rs --arg marker "$MARKER" '
  def content_text:
    if (.message.content | type) == "string" then .message.content
    else ([.message.content[]? | select(.type == "text") | .text] | join("\n")) end;
  def received_text:
    .type == "user"
    and ((.isMeta // false) | not)
    and ((.isCompactSummary // false) | not)
    and ((.message.content | type) == "string"
         or ((.message.content | type) == "array"
             and ([.message.content[]? | select(.type == "tool_result")] | length) == 0));
  [ to_entries[] | .key as $i | .value as $e
    | if ($e | received_text) then
        ($e | content_text) as $t
        | if ($t | contains($marker)) then {i: $i, k: "nudge"}
          elif ($t | test("^[A-Za-z]+ hook feedback:")) then {i: $i, k: "feedback"}
          else {i: $i, k: "received", id: ($e.uuid // "line-\($i)")} end
      elif $e.type == "assistant" then
        {i: $i, k: "assistant",
         sent: ([$e.message.content[]? | select(.type == "tool_use" and .name == "SendMessage")] | length)}
      else empty end
  ] as $ev
  | ([$ev[] | select(.k == "received")] | last) as $anchor
  | [$ev[] | select(.i > ($anchor.i // -1))] as $turn
  | "\($anchor.id // "start") \([$turn[] | select(.k == "assistant")] | length) \([$turn[] | select(.k == "assistant") | .sent] | add // 0) \([$turn[] | select(.k == "nudge")] | length)"
')"

read -r anchor worked sent nudges <<<"$verdict"
if [ -z "${anchor:-}" ]; then
  note "could not parse $transcript; not judging"
  exit 0
fi

[ "$worked" -gt 0 ] || exit 0 # no new assistant output: nothing to judge
[ "$sent" -gt 0 ] && exit 0   # reported this turn

# ---------------------------------------------------------------- release valve
max="${AGENT_TEAM_IDLE_MAX_NUDGES:-1}"
case "$max" in '' | *[!0-9]*) max=1 ;; esac

state_dir="${AGENT_TEAM_STATE_DIR:-$root/.claude/hooks/.state}"
state_file="$state_dir/idle-$(printf '%s' "$(basename "$transcript" .jsonl)" | tr -c 'A-Za-z0-9_.-' '_')"
recorded=0
if [ -f "$state_file" ]; then
  read -r s_anchor s_count <"$state_file" || true
  if [ "${s_anchor:-}" = "$anchor" ]; then recorded="${s_count:-0}"; fi
fi
case "$recorded" in '' | *[!0-9]*) recorded=0 ;; esac

done_nudges="$nudges"
[ "$recorded" -gt "$done_nudges" ] && done_nudges="$recorded"
if [ "$done_nudges" -ge "$max" ]; then
  note "teammate '${name:-?}' already nudged $done_nudges time(s) this turn; releasing"
  exit 0
fi

if mkdir -p "$state_dir" 2>/dev/null; then
  [ -f "$state_dir/.gitignore" ] || printf '*\n' >"$state_dir/.gitignore" 2>/dev/null
  printf '%s %s\n' "$anchor" "$((done_nudges + 1))" >"$state_file" 2>/dev/null
fi

cat >&2 <<EOF
$MARKER You are about to go idle, but this turn has no SendMessage call.
Your final text is not a report: the lead (or whoever assigned the work) may never see it.
Before you stop:
  1. SendMessage a report to the lead or the assigner: conclusion, evidence, handoffs, next step.
  2. TaskUpdate the status of the task you worked on.
See .claude/team/PROTOCOL.md, section "Reporting". This gate asks once per turn.
EOF
exit 2
