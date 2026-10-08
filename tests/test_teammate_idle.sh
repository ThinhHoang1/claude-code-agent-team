#!/usr/bin/env bash
# TeammateIdle gate: a teammate must SendMessage before it goes idle.
. "$(dirname "$0")/lib.sh"
HOOK="$HOOKS/teammate-idle-gate.sh"
echo "teammate-idle-gate"

T="$FIXTURES/transcripts"
proj="$SANDBOX/projects/demo"
repo="$SANDBOX/repo"
mkdir -p "$proj" "$repo"
state="$repo/.claude/hooks/.state"

fresh() { rm -rf "$state"; }
own() { fresh; cp "$T/$1" "$proj/own.jsonl"; }        # split-pane style: transcript_path is the teammate's own
qa_file="$proj/lead/subagents/agent-aqa-0001.jsonl"
in_process() {                                          # <qa transcript> <lead transcript>
  fresh
  rm -rf "$proj/lead" "$proj/lead.jsonl"
  in_process_layout "$proj" lead qa aqa-0001
  in_process_layout "$proj" lead developer adev-0002
  cp "$T/$1" "$qa_file"
  cp "$T/$2" "$proj/lead.jsonl"
  cp "$T/turn-with-report.jsonl" "$proj/lead/subagents/agent-adev-0002.jsonl"
}

# --- judging the turn (teammate's own session file) -------------------------
own turn-with-report.jsonl
run_hook "$HOOK" "$(payload idle-own-session.json)"
assert_rc 0 "passes a turn that called SendMessage"

own turn-silent.jsonl
run_hook "$HOOK" "$(payload idle-own-session.json)"
assert_rc 2 "blocks a turn with no SendMessage"
assert_err_contains '[teammate-idle-gate]' "block message carries the gate marker"
assert_err_contains 'SendMessage a report' "block message says what to do"

own report-in-earlier-turn-only.jsonl
run_hook "$HOOK" "$(payload idle-own-session.json)"
assert_rc 2 "a report from an EARLIER turn does not cover the current one"

own blocked-then-reported.jsonl
run_hook "$HOOK" "$(payload idle-own-session.json)"
assert_rc 0 "releases once the continuation after a block calls SendMessage"

own blocked-then-silent.jsonl
run_hook "$HOOK" "$(payload idle-own-session.json)"
assert_rc 0 "never blocks twice for the same turn (no loop), even if still silent"

own blocked-then-silent.jsonl
AGENT_TEAM_IDLE_MAX_NUDGES=2 run_hook "$HOOK" "$(payload idle-own-session.json)"
assert_rc 2 "AGENT_TEAM_IDLE_MAX_NUDGES=2 allows a second nudge"

own turn-silent.jsonl
AGENT_TEAM_IDLE_MAX_NUDGES=0 run_hook "$HOOK" "$(payload idle-own-session.json)"
assert_rc 0 "AGENT_TEAM_IDLE_MAX_NUDGES=0 never blocks"

own received-no-work-yet.jsonl
run_hook "$HOOK" "$(payload idle-own-session.json)"
assert_rc 0 "no assistant output since the last received message: nothing to judge"

own other-hook-feedback-reported-earlier.jsonl
run_hook "$HOOK" "$(payload idle-own-session.json)"
assert_rc 0 "another hook's feedback does not start a new turn (earlier report still counts)"

own other-hook-feedback-silent.jsonl
run_hook "$HOOK" "$(payload idle-own-session.json)"
assert_rc 2 "another hook's feedback does not use up this gate's nudge"

own meta-entry-is-not-a-turn.jsonl
run_hook "$HOOK" "$(payload idle-own-session.json)"
assert_rc 0 "isMeta user entries do not start a new turn"

own garbage-lines-with-report.jsonl
run_hook "$HOOK" "$(payload idle-own-session.json)"
assert_rc 0 "skips malformed and half-written lines (report found)"

own garbage-lines-silent.jsonl
run_hook "$HOOK" "$(payload idle-own-session.json)"
assert_rc 2 "skips malformed and half-written lines (silence found)"

# --- finding the right transcript (in-process teammates) --------------------
in_process turn-silent.jsonl lead-latest-turn-sends.jsonl
run_hook "$HOOK" "$(payload idle-in-process-by-name.json)"
assert_rc 2 "in-process: judges the teammate's file, not the lead's (lead sent, teammate did not)"

in_process turn-with-report.jsonl lead-latest-turn-silent.jsonl
run_hook "$HOOK" "$(payload idle-in-process-by-name.json)"
assert_rc 0 "in-process: judges the teammate's file, not the lead's (teammate sent, lead did not)"

in_process turn-silent.jsonl lead-latest-turn-sends.jsonl
run_hook "$HOOK" "$(payload idle-in-process-by-agent-id.json)"
assert_rc 2 "in-process: resolves the teammate by agent_id (silent)"

in_process turn-with-report.jsonl lead-latest-turn-silent.jsonl
run_hook "$HOOK" "$(payload idle-in-process-by-agent-id.json)"
assert_rc 0 "in-process: resolves the teammate by agent_id (reported)"

in_process turn-with-report.jsonl lead-latest-turn-silent.jsonl
run_hook "$HOOK" "$(payload idle-agent-transcript-path.json)"
assert_rc 0 "agent_transcript_path wins when present (reported)"

in_process turn-silent.jsonl lead-latest-turn-sends.jsonl
run_hook "$HOOK" "$(payload idle-agent-transcript-path.json)"
assert_rc 2 "agent_transcript_path wins when present (silent)"

in_process turn-silent.jsonl lead-latest-turn-silent.jsonl
run_hook "$HOOK" "$(payload idle-in-process-unknown.json)"
assert_rc 0 "in-process: an unresolvable teammate fails open instead of judging the lead's file"
assert_err_contains 'could not locate' "explains why it did not judge (debug log)"

# A teammate respawned under the same name: the newest transcript wins.
in_process turn-with-report.jsonl lead-latest-turn-silent.jsonl
touch -t 202001010000 "$proj/lead/subagents/agent-aqa-0001.meta.json"
jq -nc '{agentType:"qa",name:"qa"}' >"$proj/lead/subagents/agent-aqa-0003.meta.json"
cp "$T/turn-silent.jsonl" "$proj/lead/subagents/agent-aqa-0003.jsonl"
run_hook "$HOOK" "$(payload idle-in-process-by-name.json)"
assert_rc 2 "same teammate name twice: judges the newest transcript"

# --- release valve backstop (state) -----------------------------------------
# If a future Claude Code stops echoing hook stderr into the transcript, the
# gate cannot see its own nudge. The state file still releases the turn.
own turn-silent.jsonl
run_hook "$HOOK" "$(payload idle-own-session.json)"
assert_rc 2 "backstop: first silent idle is blocked"
t_text "$proj/own.jsonl" "Still nothing to report."   # continuation, feedback line NOT recorded
run_hook "$HOOK" "$(payload idle-own-session.json)"
assert_rc 0 "backstop: second idle of the same turn is released by the state file"
t_received "$proj/own.jsonl" team-lead "New task: check the refund path."
t_tool "$proj/own.jsonl" Bash '{"command":"npm run e2e"}'
t_text "$proj/own.jsonl" "Refund path checked."
run_hook "$HOOK" "$(payload idle-own-session.json)"
assert_rc 2 "backstop: a NEW turn is judged afresh (state is keyed by the turn anchor)"
[ -f "$state/.gitignore" ] && pass "state dir is git-ignored automatically" || fail "state dir is git-ignored automatically"

own turn-with-report.jsonl
mkdir -p "$state"
printf 'u-100 9\n' >"$state/idle-own"
run_hook "$HOOK" "$(payload idle-own-session.json)"
assert_rc 0 "state never overrides a real report"

own turn-silent.jsonl
mkdir -p "$state"
printf 'u-100 1\n' >"$state/idle-own"
run_hook "$HOOK" "$(payload idle-own-session.json)"
assert_rc 0 "state recording a nudge for this same turn releases it"

own turn-silent.jsonl
mkdir -p "$state"
printf 'some-other-anchor 9\n' >"$state/idle-own"
run_hook "$HOOK" "$(payload idle-own-session.json)"
assert_rc 2 "state for a different turn is ignored"

own turn-silent.jsonl
mkdir -p "$state"
printf 'garbage\n' >"$state/idle-own"
run_hook "$HOOK" "$(payload idle-own-session.json)"
assert_rc 2 "corrupt state is ignored"

own turn-silent.jsonl
AGENT_TEAM_STATE_DIR="$SANDBOX/custom-state" run_hook "$HOOK" "$(payload idle-own-session.json)"
[ -f "$SANDBOX/custom-state/idle-own" ] && pass "AGENT_TEAM_STATE_DIR relocates state" || fail "AGENT_TEAM_STATE_DIR relocates state"

# --- fail-open paths ---------------------------------------------------------
own turn-silent.jsonl
AGENT_TEAM_IDLE_GATE=off run_hook "$HOOK" "$(payload idle-own-session.json)"
assert_rc 0 "AGENT_TEAM_IDLE_GATE=off disables the gate"

run_hook "$HOOK" "$(cat "$FIXTURES/payloads/malformed.txt")"
assert_rc 0 "malformed payload fails open"

rm -f "$proj/own.jsonl"
run_hook "$HOOK" "$(payload idle-own-session.json)"
assert_rc 0 "missing transcript fails open"

: >"$proj/own.jsonl"
run_hook "$HOOK" "$(payload idle-own-session.json)"
assert_rc 0 "empty transcript: nothing to judge"

summary
