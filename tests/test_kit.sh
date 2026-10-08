#!/usr/bin/env bash
# Static checks on the kit itself: settings wiring, agent frontmatter, templates.
. "$(dirname "$0")/lib.sh"
echo "kit"

S="$KIT_ROOT/.claude/settings.json"
jq -e . "$S" >/dev/null 2>&1 && pass "settings.json is valid JSON" || fail "settings.json is valid JSON"
assert_eq "1" "$(jq -r '.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS' "$S")" "settings.json enables agent teams"
for ev in TaskCreated TaskCompleted TeammateIdle; do
  cmd="$(jq -r --arg e "$ev" '.hooks[$e][0].hooks[0].command // ""' "$S")"
  script="${cmd##*/}"
  if [ -n "$script" ] && [ -x "$HOOKS/$script" ]; then pass "$ev is wired to an executable hook ($script)"
  else fail "$ev is wired to an executable hook" "command: $cmd"; fi
done

for f in "$KIT_ROOT"/.claude/agents/*.md; do
  base="$(basename "$f" .md)"
  name="$(awk -F': ' '/^name:/{print $2; exit}' "$f")"
  tools="$(awk -F': ' '/^tools:/{print $2; exit}' "$f")"
  desc="$(awk -F': ' '/^description:/{print $2; exit}' "$f")"
  if [ "$name" = "$base" ] && [ -n "$desc" ] && case "$tools" in *SendMessage*TaskUpdate*) true ;; *) false ;; esac; then
    pass "agent $base: name matches file, has description, can SendMessage and TaskUpdate"
  else
    fail "agent $base: frontmatter" "name=$name tools=$tools"
  fi
done
assert_eq 8 "$(ls "$KIT_ROOT"/.claude/agents/*.md | wc -l | tr -d ' ')" "eight role agents"

lead_agents="$(awk -F'Agent\\(' '/^tools:/{split($2,a,")"); print a[1]; exit}' "$KIT_ROOT/.claude/agents/tech-lead.md" | tr -d ' ' | tr ',' '\n' | sort | tr '\n' ' ')"
others="$(cd "$KIT_ROOT/.claude/agents" && ls *.md | sed 's/\.md$//' | grep -v '^tech-lead$' | sort | tr '\n' ' ')"
assert_eq "$others" "$lead_agents" "tech-lead may spawn exactly the other seven roles"

# The shipped BOARD.md template must not block a [GATE] task.
repo="$SANDBOX/repo"
mkdir -p "$repo/.claude/team"
cp "$KIT_ROOT/.claude/team/BOARD.md" "$repo/.claude/team/BOARD.md"
run_hook "$HOOKS/task-completed-gate.sh" "$(jq -nc --arg cwd "$repo" '{cwd:$cwd,task_subject:"[GATE] sign-off"}')"
assert_rc 0 "the empty BOARD.md template has no open blockers"

# The HANDOFF template in PROTOCOL.md satisfies the TaskCreated gate.
handoff="$(awk '/^### HANDOFF$/{f=1} f{print} f&&/^- BLOCKING/{exit}' "$KIT_ROOT/.claude/team/PROTOCOL.md")"
run_hook "$HOOKS/task-created-gate.sh" "$(jq -nc --arg d "$handoff" '{task_subject:"x",task_description:$d}')"
assert_rc 0 "a task described with the PROTOCOL.md HANDOFF template passes the TaskCreated gate"

summary
