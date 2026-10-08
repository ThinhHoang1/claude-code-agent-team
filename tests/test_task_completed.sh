#!/usr/bin/env bash
# TaskCompleted gate: [GATE] tasks cannot close while BOARD.md has open blockers.
. "$(dirname "$0")/lib.sh"
HOOK="$HOOKS/task-completed-gate.sh"
echo "task-completed-gate"

repo="$SANDBOX/repo"
mkdir -p "$repo/.claude/team"
use_board() { cp "$FIXTURES/boards/$1" "$repo/.claude/team/BOARD.md"; }

use_board open-blockers.md
run_hook "$HOOK" "$(payload task-completed-gate-subject.json)"
assert_rc 2 "blocks a [GATE] task while blockers are open"
assert_err_contains 'B-1' "lists the first open blocker"
assert_err_contains 'B-2' "lists the second open blocker"
case "$ERR" in *B-0*) fail "does not list closed items" "stderr mentions B-0" ;; *) pass "does not list closed items" ;; esac
case "$ERR" in *D-1*) fail "does not list decisions" "stderr mentions D-1" ;; *) pass "does not list decisions" ;; esac

run_hook "$HOOK" "$(payload task-completed-gate-description.json)"
assert_rc 2 "[GATE] in the description is enforced too"

run_hook "$HOOK" "$(payload task-completed-untagged.json)"
assert_rc 0 "untagged tasks complete even with open blockers"

run_hook "$HOOK" "$(payload task-completed-legacy-title.json)"
assert_rc 2 "old task_title payloads are still recognised as [GATE]"

use_board no-blockers.md
run_hook "$HOOK" "$(payload task-completed-gate-subject.json)"
assert_rc 0 "allows a [GATE] task when the Blockers section is empty"

use_board only-placeholders.md
run_hook "$HOOK" "$(payload task-completed-gate-subject.json)"
assert_rc 0 "ignores placeholders and items inside HTML comments"

use_board resolved-checkboxes.md
run_hook "$HOOK" "$(payload task-completed-gate-subject.json)"
assert_rc 0 "ignores checked boxes and lines inside code fences"

use_board one-open-among-resolved.md
run_hook "$HOOK" "$(payload task-completed-gate-subject.json)"
assert_rc 2 "finds one open '*' item among resolved ones under '## Blockers (open)'"
assert_err_contains 'B-3' "names the remaining blocker"

# Board location: CLAUDE_PROJECT_DIR wins over the payload cwd.
other="$SANDBOX/other"
mkdir -p "$other/.claude/team"
cp "$FIXTURES/boards/no-blockers.md" "$other/.claude/team/BOARD.md"
use_board open-blockers.md
CLAUDE_PROJECT_DIR="$other" run_hook "$HOOK" "$(payload task-completed-gate-subject.json)"
assert_rc 0 "reads the board under CLAUDE_PROJECT_DIR when it is set"

AGENT_TEAM_BOARD="$repo/.claude/team/BOARD.md" CLAUDE_PROJECT_DIR="$other" \
  run_hook "$HOOK" "$(payload task-completed-gate-subject.json)"
assert_rc 2 "AGENT_TEAM_BOARD overrides the board location"

rm -f "$repo/.claude/team/BOARD.md"
run_hook "$HOOK" "$(payload task-completed-gate-subject.json)"
assert_rc 0 "no board file: fails open"

run_hook "$HOOK" "$(cat "$FIXTURES/payloads/malformed.txt")"
assert_rc 0 "malformed input fails open"

summary
