#!/usr/bin/env bash
# Run every test file. Usage: tests/run.sh [path-to-bash]
# Pass /bin/bash on macOS to check bash 3.2 compatibility.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
shell="${1:-bash}"
command -v jq >/dev/null 2>&1 || { echo "jq is required to run the tests" >&2; exit 2; }
echo "shell: $("$shell" -c 'echo "bash $BASH_VERSION"')   jq: $(jq --version)"
export HOOK_SHELL="$shell" # hooks run under the same shell as the tests
status=0
for t in "$here"/test_*.sh; do
  echo
  "$shell" "$t" || status=1
done
echo
if [ "$status" -eq 0 ]; then echo "ALL TESTS PASSED"; else echo "SOME TESTS FAILED"; fi
exit "$status"
