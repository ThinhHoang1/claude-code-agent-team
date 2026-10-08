#!/usr/bin/env bash
# LEGACY LOGIC — DO NOT INSTALL. Used only by tests/test_regression_idle_loop.sh.
#
# A minimal re-implementation of the original TeammateIdle gate's logic shape,
# kept so the regression test can prove the infinite loop and prove the fix.
# Its three defects, in the order they bite:
#   1. It counts SendMessage calls in payload.transcript_path, which for
#      in-process teammates is the LEAD's session file, not the teammate's.
#   2. Its counting window starts at the line count recorded at the END of the
#      previous evaluation (tail -n +prev+1), not at the START of the judged
#      turn.
#   3. Its self-release compares the line count saved when it blocked with the
#      current line count. The file grows every turn, so they never match.
set -euo pipefail
payload="$(cat)"
tp="$(jq -r '.transcript_path // ""' <<<"$payload")"
[ -n "$tp" ] && [ -f "$tp" ] || exit 0

state="${LEGACY_STATE_DIR:?LEGACY_STATE_DIR must be set}"
mkdir -p "$state"
key="$state/$(basename "$tp" .jsonl)"

total="$(wc -l <"$tp" | tr -d ' ')"
prev=0
[ -f "$key" ] && prev="$(cat "$key")"

# self-release: "if nothing changed since I blocked, let it go"
if [ -f "$key.blocked" ] && [ "$(cat "$key.blocked")" = "$total" ]; then
  printf '%s' "$total" >"$key"
  rm -f "$key.blocked"
  exit 0
fi

sent="$(tail -n +$((prev + 1)) "$tp" |
  jq -R 'fromjson? // empty' |
  jq -s '[.. | objects | select(.type? == "tool_use" and .name? == "SendMessage")] | length')"

if [ "${sent:-0}" -eq 0 ] && [ "$total" -gt "$prev" ]; then
  printf '%s' "$total" >"$key.blocked"
  printf '%s' "$total" >"$key"
  echo "legacy gate: no SendMessage in this turn" >&2
  exit 2
fi

printf '%s' "$total" >"$key"
exit 0
