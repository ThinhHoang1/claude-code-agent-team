#!/usr/bin/env bash
# TaskCreated gate: a task needs a "DONE:" line in its description.
. "$(dirname "$0")/lib.sh"
HOOK="$HOOKS/task-created-gate.sh"
echo "task-created-gate"

run_hook "$HOOK" "$(payload task-created-with-done.json)"
assert_rc 0 "accepts a description with a DONE: line"

run_hook "$HOOK" "$(payload task-created-bullet-done.json)"
assert_rc 0 "accepts DONE: written as a list item inside a HANDOFF block"

run_hook "$HOOK" "$(payload task-created-missing-done.json)"
assert_rc 2 "rejects a description without a DONE: line"
assert_err_contains 'Fix the login bug' "rejection names the task subject"
assert_err_contains 'DONE:' "rejection says which line is missing"

run_hook "$HOOK" "$(payload task-created-no-description.json)"
assert_rc 2 "rejects a task with no description at all"

run_hook "$HOOK" "$(payload task-created-empty-done.json)"
assert_rc 2 "rejects an empty DONE: line"

run_hook "$HOOK" "$(payload task-created-legacy-title.json)"
assert_rc 2 "still judges payloads that use the old task_title field"
assert_err_contains 'Old-style payload' "reads the subject from task_title when task_subject is absent"

AGENT_TEAM_DONE_MARKER=ACCEPTANCE run_hook "$HOOK" "$(payload task-created-with-done.json)"
assert_rc 2 "custom marker: DONE: no longer satisfies AGENT_TEAM_DONE_MARKER=ACCEPTANCE"

AGENT_TEAM_DONE_MARKER=ACCEPTANCE run_hook "$HOOK" \
  '{"task_subject":"x","task_description":"ACCEPTANCE: the report lists every case"}'
assert_rc 0 "custom marker: ACCEPTANCE: line accepted"

AGENT_TEAM_TASK_GATE=off run_hook "$HOOK" "$(payload task-created-missing-done.json)"
assert_rc 0 "AGENT_TEAM_TASK_GATE=off disables the gate"

run_hook "$HOOK" "$(cat "$FIXTURES/payloads/malformed.txt")"
assert_rc 0 "malformed input fails open"

summary
