#!/usr/bin/env bash
# TaskCreated gate: every task must say how "done" will be verified.
#
# Blocks (exit 2) a TaskCreate whose description has no definition-of-done
# line, e.g.
#     DONE: `npm test` passes and the checkout E2E case is green
#     - DONE: reviewer can reproduce the fix with the steps in the report
#
# Claude Code deletes the task and returns stderr to the agent as the reason.
#
# Input (stdin, JSON): task_id, task_subject, task_description (may be absent),
# teammate_name (may be absent). Older builds sent task_title instead of
# task_subject; both are accepted.
#
# Env:
#   AGENT_TEAM_DONE_MARKER   keyword to require (default: DONE)
#   AGENT_TEAM_TASK_GATE=off disable this gate
set -uo pipefail

[ "${AGENT_TEAM_TASK_GATE:-on}" = "off" ] && exit 0

if ! command -v jq >/dev/null 2>&1; then
  echo "task-created-gate: jq is required but not installed; gate not enforced" >&2
  exit 1 # non-blocking error: visible in the transcript, task still created
fi

payload="$(cat)"
jq -e 'type == "object"' >/dev/null 2>&1 <<<"$payload" || exit 0 # malformed input: fail open

marker="${AGENT_TEAM_DONE_MARKER:-DONE}"
subject="$(jq -r '.task_subject // .task_title // ""' <<<"$payload")"
desc="$(jq -r '.task_description // ""' <<<"$payload")"

# A line that starts with the marker (optionally as a list item) followed by
# non-empty text. "DONE:" alone does not count.
if grep -Eq "^[[:space:]]*([-*][[:space:]]+)?${marker}:[[:space:]]*[^[:space:]]" <<<"$desc"; then
  exit 0
fi

cat >&2 <<EOF
Task "${subject}" was rejected: its description has no "${marker}:" line.
Every task must state how completion will be verified. Add a line such as:
  ${marker}: <a concrete check someone else can run, e.g. a test or E2E case name>
See .claude/team/PROTOCOL.md, section "Handing off work".
EOF
exit 2
