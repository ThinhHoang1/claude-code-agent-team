#!/usr/bin/env bash
# install.sh: copies the kit, never clobbers without --force, never touches BOARD.md.
. "$(dirname "$0")/lib.sh"
INSTALL="$KIT_ROOT/install.sh"
run_install() { ${HOOK_SHELL:+"$HOOK_SHELL"} "$INSTALL" "$@"; }
echo "install.sh"

kit_files() { (cd "$KIT_ROOT" && ls CLAUDE.md .claude/settings.json .claude/agents/*.md .claude/team/*.md .claude/hooks/*.sh); }
expected="$(kit_files | wc -l | tr -d ' ')"

dst="$SANDBOX/target"
mkdir -p "$dst"

out="$(run_install --dry-run "$dst" 2>&1)"; RC=$?
assert_rc 0 "dry run exits 0"
[ -z "$(ls -A "$dst")" ] && pass "dry run writes nothing" || fail "dry run writes nothing"

out="$(run_install "$dst" 2>&1)"; RC=$?
assert_rc 0 "fresh install exits 0"
missing=0
for f in $(kit_files); do [ -f "$dst/$f" ] || missing=$((missing + 1)); done
assert_eq 0 "$missing" "fresh install copies all $expected kit files"
assert_eq "$expected" "$(printf '%s\n' "$out" | grep -c '^  add ')" "fresh install reports every file as add"
nonexec=0
for f in "$dst"/.claude/hooks/*.sh; do [ -x "$f" ] || nonexec=$((nonexec + 1)); done
assert_eq 0 "$nonexec" "installed hooks are executable"
[ ! -e "$dst/README.md" ] && [ ! -e "$dst/tests" ] && [ ! -e "$dst/install.sh" ] &&
  pass "repo-only files (README, tests, installer) are not installed" ||
  fail "repo-only files (README, tests, installer) are not installed"

out="$(run_install "$dst" 2>&1)"; RC=$?
assert_rc 0 "re-install exits 0"
assert_eq "$expected" "$(printf '%s\n' "$out" | grep -c '^  unchanged ')" "re-install reports every file unchanged"

printf '# My project\n' >"$dst/CLAUDE.md"
printf '{"env":{"FOO":"1"}}\n' >"$dst/.claude/settings.json"
printf -- '- [me] B-9 · real blocker\n' >>"$dst/.claude/team/BOARD.md"
board_before="$(cat "$dst/.claude/team/BOARD.md")"

out="$(run_install "$dst" 2>&1)"; RC=$?
assert_rc 0 "install over local changes exits 0"
printf '%s\n' "$out" | grep -q '^  skip  *CLAUDE.md' && pass "reports CLAUDE.md as skipped" || fail "reports CLAUDE.md as skipped" "$out"
printf '%s\n' "$out" | grep -q '^  skip  *.claude/settings.json' && pass "reports settings.json as skipped" || fail "reports settings.json as skipped" "$out"
printf '%s\n' "$out" | grep -q 'settings.json: copy the "env" and "hooks" blocks' && pass "prints a merge hint for settings.json" || fail "prints a merge hint for settings.json"
assert_eq "# My project" "$(cat "$dst/CLAUDE.md")" "without --force, an existing CLAUDE.md is untouched"
printf '%s\n' "$out" | grep -q '^  keep  *.claude/team/BOARD.md' && pass "reports BOARD.md as kept" || fail "reports BOARD.md as kept" "$out"

out="$(run_install --dry-run --force "$dst" 2>&1)"; RC=$?
printf '%s\n' "$out" | grep -q '^  overwrite  *CLAUDE.md' && pass "--dry-run --force lists what would be overwritten" || fail "--dry-run --force lists what would be overwritten" "$out"
assert_eq "# My project" "$(cat "$dst/CLAUDE.md")" "--dry-run --force changes nothing"

out="$(run_install --force "$dst" 2>&1)"; RC=$?
assert_rc 0 "--force exits 0"
cmp -s "$KIT_ROOT/CLAUDE.md" "$dst/CLAUDE.md" && pass "--force overwrites CLAUDE.md" || fail "--force overwrites CLAUDE.md"
cmp -s "$KIT_ROOT/.claude/settings.json" "$dst/.claude/settings.json" && pass "--force overwrites settings.json" || fail "--force overwrites settings.json"
assert_eq "$board_before" "$(cat "$dst/.claude/team/BOARD.md")" "--force never overwrites BOARD.md (project data)"

run_install "$SANDBOX/does-not-exist" >/dev/null 2>&1; RC=$?
[ "$RC" -ne 0 ] && pass "missing target is an error" || fail "missing target is an error"
run_install >/dev/null 2>&1; RC=$?
[ "$RC" -ne 0 ] && pass "no target is an error" || fail "no target is an error"
run_install "$KIT_ROOT" >/dev/null 2>&1; RC=$?
[ "$RC" -ne 0 ] && pass "refuses to install into the kit itself" || fail "refuses to install into the kit itself"

# The installed gates work from the target repository.
run_hook "$dst/.claude/hooks/task-created-gate.sh" '{"task_subject":"x","task_description":"no definition"}'
assert_rc 2 "installed TaskCreated gate runs from the target"

summary
