#!/usr/bin/env bash
# TaskCompleted gate: a sign-off task cannot close while blockers are open.
#
# Blocks (exit 2) completing a task tagged [GATE] (in its subject or
# description) while the "## Blockers" section of .claude/team/BOARD.md still
# lists an open item. Untagged tasks are never blocked.
#
# Open item  = a top-level list item ("- " or "* ") inside "## Blockers".
# Not open   = placeholders written in italics ("- _none_"), checked boxes
#              ("- [x] ..."), anything inside <!-- comments --> or ``` fences.
# Resolve a blocker by moving it to "## Closed".
#
# Input (stdin, JSON): task_id, task_subject, task_description (may be absent),
# teammate_name (may be absent). Older builds sent task_title; accepted too.
#
# Env:
#   AGENT_TEAM_BOARD         path to the board (default: .claude/team/BOARD.md)
#   AGENT_TEAM_TASK_GATE=off disable this gate
set -uo pipefail

[ "${AGENT_TEAM_TASK_GATE:-on}" = "off" ] && exit 0

if ! command -v jq >/dev/null 2>&1; then
  echo "task-completed-gate: jq is required but not installed; gate not enforced" >&2
  exit 1
fi

payload="$(cat)"
jq -e 'type == "object"' >/dev/null 2>&1 <<<"$payload" || exit 0 # malformed input: fail open

subject="$(jq -r '.task_subject // .task_title // ""' <<<"$payload")"
desc="$(jq -r '.task_description // ""' <<<"$payload")"

case "${subject}${desc}" in
  *'[GATE]'*) ;;
  *) exit 0 ;;
esac

root="${CLAUDE_PROJECT_DIR:-$(jq -r '.cwd // "."' <<<"$payload")}"
board="${AGENT_TEAM_BOARD:-$root/.claude/team/BOARD.md}"
if [ ! -f "$board" ]; then
  echo "task-completed-gate: no board at $board; [GATE] not enforced" >&2
  exit 0
fi

blockers="$(awk '
  /^[[:space:]]*<!--/    { in_comment = 1 }
  in_comment             { if ($0 ~ /-->/) in_comment = 0; next }
  /^[[:space:]]*```/     { in_fence = !in_fence; next }
  in_fence               { next }
  /^##[[:space:]]/       { in_blockers = ($0 ~ /^##[[:space:]]+[Bb]lockers([[:space:]]|$)/); next }
  !in_blockers           { next }
  /^[-*][[:space:]]+_/   { next }   # placeholder: "- _none_"
  /^[-*][[:space:]]+\[[xX]\]/ { next } # checked box
  /^[-*][[:space:]]+/    { print }
' "$board")"

[ -z "$blockers" ] && exit 0

{
  echo "Cannot complete [GATE] task \"${subject}\": ${board#"$root"/} still lists open blockers:"
  echo "$blockers"
  echo "Resolve each one and move it from \"## Blockers\" to \"## Closed\", then complete the task again."
} >&2
exit 2
