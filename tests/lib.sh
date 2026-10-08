#!/usr/bin/env bash
# Shared helpers for the hook tests. Plain bash + jq, works on bash 3.2+.
# Sourced by tests/test_*.sh; each test file runs in its own process.

set -u

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
HOOKS="$KIT_ROOT/.claude/hooks"
FIXTURES="$TESTS_DIR/fixtures"
LEGACY_HOOK="$TESTS_DIR/legacy/teammate-idle-gate.legacy.sh"

PASSED=0
FAILED=0

# Every test file gets a private sandbox, removed on exit.
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/agent-team-tests.XXXXXX")"
trap 'rm -rf "$SANDBOX"' EXIT

# Keep the developer's environment from leaking into hook decisions.
unset CLAUDE_PROJECT_DIR AGENT_TEAM_IDLE_GATE AGENT_TEAM_TASK_GATE \
  AGENT_TEAM_IDLE_MAX_NUDGES AGENT_TEAM_STATE_DIR AGENT_TEAM_BOARD \
  AGENT_TEAM_DONE_MARKER 2>/dev/null || true

# ------------------------------------------------------------------ running

# run_hook <hook-path> <payload-string>  -> sets RC, ERR
run_hook() {
  local hook="$1" payload="$2" errf="$SANDBOX/.stderr"
  # HOOK_SHELL lets tests/run.sh force an old bash (e.g. macOS /bin/bash 3.2).
  printf '%s' "$payload" | ${HOOK_SHELL:+"$HOOK_SHELL"} "$hook" >/dev/null 2>"$errf"
  RC=$?
  ERR="$(cat "$errf")"
}

# payload <fixture-name> [dir]  -> prints the payload with __DIR__ replaced
payload() {
  local dir="${2:-$SANDBOX}"
  sed "s|__DIR__|$dir|g" "$FIXTURES/payloads/$1"
}

# ------------------------------------------------------------------ asserts

pass() { PASSED=$((PASSED + 1)); printf '  ok    %s\n' "$1"; }
fail() { FAILED=$((FAILED + 1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }

assert_rc() { # <expected> <name>
  if [ "$RC" = "$1" ]; then pass "$2"; else fail "$2" "expected exit $1, got $RC; stderr: ${ERR:0:300}"; fi
}

assert_err_contains() { # <needle> <name>
  case "$ERR" in
    *"$1"*) pass "$2" ;;
    *) fail "$2" "stderr does not contain '$1': ${ERR:0:300}" ;;
  esac
}

assert_eq() { # <expected> <actual> <name>
  if [ "$1" = "$2" ]; then pass "$3"; else fail "$3" "expected '$1', got '$2'"; fi
}

summary() {
  printf '  -- %d passed, %d failed\n' "$PASSED" "$FAILED"
  [ "$FAILED" -eq 0 ]
}

# ------------------------------------------------------------------ transcripts
# Builders append one JSONL entry shaped like Claude Code's transcript lines.

# Ids come from a global counter. (Not $(...): a subshell would not keep it.)
_n=0
_id() { _n=$((_n + 1)); ID="$(printf '%s-%04d' "$1" "$_n")"; }

t_received() { # <file> <from> <text>  — a message the agent receives (starts a turn)
  _id u
  jq -nc --arg u "$ID" --arg from "$2" --arg t "$3" \
    '{type:"user",uuid:$u,message:{role:"user",content:("<teammate-message teammate_id=\"" + $from + "\">" + $t + "</teammate-message>")}}' >>"$1"
}

t_prompt() { # <file> <text>  — a human prompt in the lead session
  _id u
  jq -nc --arg u "$ID" --arg t "$2" '{type:"user",uuid:$u,message:{role:"user",content:$t}}' >>"$1"
}

t_tool() { # <file> <tool-name> [input-json]  — tool_use + tool_result pair
  local input="${3:-}" tid aid uid
  [ -n "$input" ] || input='{}'
  _id tu; tid="$ID"
  _id a; aid="$ID"
  _id u; uid="$ID"
  jq -nc --arg u "$aid" --arg id "$tid" --arg name "$2" --argjson input "$input" \
    '{type:"assistant",uuid:$u,message:{role:"assistant",content:[{type:"tool_use",id:$id,name:$name,input:$input}]}}' >>"$1"
  jq -nc --arg u "$uid" --arg id "$tid" \
    '{type:"user",uuid:$u,message:{role:"user",content:[{type:"tool_result",tool_use_id:$id,content:"ok"}]}}' >>"$1"
}

t_send() { # <file> <to> <text>
  t_tool "$1" SendMessage "$(jq -nc --arg to "$2" --arg m "$3" '{to:$to,message:$m}')"
}

t_text() { # <file> <text>  — assistant prose (the end of a turn)
  _id a
  jq -nc --arg u "$ID" --arg t "$2" \
    '{type:"assistant",uuid:$u,message:{role:"assistant",content:[{type:"text",text:$t}]}}' >>"$1"
}

t_attachment() { # <file> <kind>
  _id x
  jq -nc --arg u "$ID" --arg k "$2" '{type:"attachment",uuid:$u,attachment:{type:$k}}' >>"$1"
}

t_hook_feedback() { # <file> <stderr-of-the-hook>  — how Claude Code injects exit-2 feedback
  _id u
  jq -nc --arg u "$ID" --arg e "$2" \
    '{type:"user",uuid:$u,message:{role:"user",content:("TeammateIdle hook feedback:\n[\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/teammate-idle-gate.sh]: " + $e)}}' >>"$1"
}

count_sendmessage() { # <file> [from-line]  — the old gate's counting method
  tail -n +"${2:-1}" "$1" | jq -R 'fromjson? // empty' |
    jq -s '[.. | objects | select(.type? == "tool_use" and .name? == "SendMessage")] | length'
}

# in_process_layout <dir> <session> <teammate-name> <agent-id>
#   Creates <dir>/<session>.jsonl (lead) and the teammate's own transcript at
#   <dir>/<session>/subagents/agent-<agent-id>.jsonl plus its .meta.json,
#   which is how Claude Code stores in-process teammates.
in_process_layout() {
  local dir="$1" session="$2" name="$3" aid="$4"
  mkdir -p "$dir/$session/subagents"
  : >"$dir/$session.jsonl"
  : >"$dir/$session/subagents/agent-$aid.jsonl"
  jq -nc --arg n "$name" '{agentType:$n,name:$n,taskKind:"in_process_teammate"}' \
    >"$dir/$session/subagents/agent-$aid.meta.json"
}
