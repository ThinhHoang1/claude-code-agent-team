#!/usr/bin/env bash
# Install the agent-team kit into a target repository.
#
#   ./install.sh [--dry-run] [--force] <target-repo>
#
# Copies CLAUDE.md, .claude/settings.json, .claude/agents/*, .claude/team/*
# and .claude/hooks/* into <target-repo>. Existing files are never clobbered:
# a file that already exists with different content is skipped and reported.
#   --force    overwrite those files instead (BOARD.md is still kept: it is
#              your project's decision log, not kit code)
#   --dry-run  print what would happen, change nothing
set -euo pipefail

usage() {
  sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
}

force=0
dry=0
target=""
while [ $# -gt 0 ]; do
  case "$1" in
    --force) force=1 ;;
    --dry-run) dry=1 ;;
    -h | --help) usage; exit 0 ;;
    -*) echo "install.sh: unknown option: $1" >&2; usage >&2; exit 64 ;;
    *)
      if [ -n "$target" ]; then echo "install.sh: one target only" >&2; exit 64; fi
      target="$1"
      ;;
  esac
  shift
done

if [ -z "$target" ]; then usage >&2; exit 64; fi
if [ ! -d "$target" ]; then echo "install.sh: target is not a directory: $target" >&2; exit 66; fi

kit="$(cd "$(dirname "$0")" && pwd)"
target="$(cd "$target" && pwd)"
if [ "$kit" = "$target" ]; then echo "install.sh: target is the kit itself" >&2; exit 64; fi

files=(CLAUDE.md .claude/settings.json)
for f in "$kit"/.claude/agents/*.md "$kit"/.claude/team/*.md "$kit"/.claude/hooks/*.sh; do
  files+=("${f#"$kit"/}")
done

# Seeded once, never overwritten: it holds the project's decisions and blockers.
seed_only=".claude/team/BOARD.md"

added=0 overwritten=0 unchanged=0 kept=0
conflicts=()

[ "$dry" = 1 ] && echo "Dry run: nothing will be written."
echo "Installing into $target"

for rel in "${files[@]}"; do
  src="$kit/$rel"
  dst="$target/$rel"
  if [ ! -e "$dst" ]; then
    action="add"
  elif cmp -s "$src" "$dst"; then
    action="unchanged"
  elif [ "$rel" = "$seed_only" ]; then
    action="keep"
  elif [ "$force" = 1 ]; then
    action="overwrite"
  else
    action="skip"
  fi

  suffix=""
  case "$action" in
    add) added=$((added + 1)) ;;
    overwrite) overwritten=$((overwritten + 1)) ;;
    unchanged) unchanged=$((unchanged + 1)) ;;
    keep) kept=$((kept + 1)); suffix="  (project data, never overwritten)" ;;
    skip) conflicts+=("$rel"); suffix="  (exists and differs; --force would overwrite it)" ;;
  esac
  printf '  %-10s %s%s\n' "$action" "$rel" "$suffix"

  if [ "$dry" = 0 ] && { [ "$action" = add ] || [ "$action" = overwrite ]; }; then
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    case "$rel" in *.sh) chmod +x "$dst" ;; esac
  fi
done

echo
echo "added $added, overwritten $overwritten, unchanged $unchanged, kept $kept, skipped ${#conflicts[@]}"

if [ "${#conflicts[@]}" -gt 0 ]; then
  echo
  echo "These files already exist with different content and were left alone:"
  for rel in "${conflicts[@]}"; do echo "  $rel"; done
  echo "Re-run with --force to overwrite them, or merge by hand:"
  for rel in "${conflicts[@]}"; do
    case "$rel" in
      .claude/settings.json)
        echo "  - settings.json: copy the \"env\" and \"hooks\" blocks from $kit/.claude/settings.json" ;;
      CLAUDE.md)
        echo "  - CLAUDE.md: append the lead playbook:  cat $kit/CLAUDE.md >> CLAUDE.md" ;;
    esac
  done
fi

if ! command -v jq >/dev/null 2>&1; then
  echo
  echo "WARNING: jq is not installed. The hooks need it; without it they report an error and enforce nothing." >&2
fi

if [ "$dry" = 0 ]; then
  echo
  echo "Next: open the target in Claude Code and fill in the \"Project map\" section of CLAUDE.md."
fi
