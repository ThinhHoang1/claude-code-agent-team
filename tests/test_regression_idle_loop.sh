#!/usr/bin/env bash
# Regression: the TeammateIdle gate must never trap a teammate that reports.
#
# Each scenario is driven twice, once through the LEGACY logic shape
# (tests/legacy/teammate-idle-gate.legacy.sh) and once through the fixed hook,
# with identical inputs. When a hook blocks, the simulation does what Claude
# Code does: it appends the hook's stderr to the teammate's transcript as
# "TeammateIdle hook feedback", and the teammate responds.
. "$(dirname "$0")/lib.sh"
FIXED="$HOOKS/teammate-idle-gate.sh"
echo "regression: TeammateIdle infinite loop"

ROUNDS=5

# ---------------------------------------------------------------------------
# Scenario A — in-process teammate that reports EVERY turn.
#   transcript_path in the payload is the lead's session file; the teammate's
#   SendMessage calls live in <session>/subagents/agent-<id>.jsonl.
# ---------------------------------------------------------------------------
scenario_in_process() { # <hook> <workdir>  -> BLOCKS, TRACE, LEAD, MATE
  local hook="$1" dir="$2" round
  mkdir -p "$dir/repo"
  in_process_layout "$dir" lead qa aqa-0001
  LEAD="$dir/lead.jsonl"
  MATE="$dir/lead/subagents/agent-aqa-0001.jsonl"
  local p
  p="$(jq -nc --arg tp "$LEAD" --arg cwd "$dir/repo" \
    '{session_id:"lead",transcript_path:$tp,cwd:$cwd,hook_event_name:"TeammateIdle",teammate_name:"qa",team_name:"session-lead"}')"

  # The lead spawns qa and sends it one extra instruction (the lead's own SendMessage).
  t_prompt "$LEAD" "Ship the retry feature with the team."
  t_tool "$LEAD" Agent '{"name":"qa","subagent_type":"qa"}'
  t_send "$LEAD" qa "Also check the refund path."
  t_text "$LEAD" "Waiting for qa."

  # Round 0: qa does the work and reports.
  t_received "$MATE" team-lead "Run the checkout E2E case and report."
  t_tool "$MATE" Bash '{"command":"npm run e2e -- checkout"}'
  t_send "$MATE" team-lead "Conclusion: PASS. Evidence: 12/12."
  t_text "$MATE" "Reported."
  run_hook "$hook" "$p"
  BLOCKS=0
  TRACE="$RC"

  round=1
  while [ "$round" -le "$ROUNDS" ]; do
    # The lead's file grows: it receives qa's message and acknowledges it.
    t_received "$LEAD" qa "Conclusion: PASS."
    t_text "$LEAD" "Noted."
    if [ "$RC" = 2 ]; then
      BLOCKS=$((BLOCKS + 1))
      # Claude Code feeds the block back; qa complies by reporting again.
      t_hook_feedback "$MATE" "$ERR"
      t_send "$MATE" team-lead "Report (again): PASS, 12/12."
      t_text "$MATE" "Report sent."
    else
      # qa gets more work from a peer and reports it.
      t_received "$MATE" developer "Fix pushed, please re-run the failing case."
      t_tool "$MATE" Bash '{"command":"npm run e2e -- checkout"}'
      t_send "$MATE" team-lead "Re-run: PASS."
      t_text "$MATE" "Reported."
    fi
    run_hook "$hook" "$p"
    TRACE="$TRACE $RC"
    round=$((round + 1))
  done
  [ "$RC" = 2 ] && BLOCKS=$((BLOCKS + 1))
}

export LEGACY_STATE_DIR="$SANDBOX/legacy-state-a"
scenario_in_process "$LEGACY_HOOK" "$SANDBOX/a-legacy"
legacy_blocks=$BLOCKS legacy_trace=$TRACE
mate_reports="$(count_sendmessage "$MATE")"
lead_total="$(count_sendmessage "$LEAD")"
window_start=$(($(cat "$LEGACY_STATE_DIR/lead") + 1))
lead_window="$(count_sendmessage "$LEAD" "$window_start")"

echo "  scenario A  legacy exit codes per idle: $legacy_trace"
assert_eq "$ROUNDS" "$legacy_blocks" "A/legacy: blocks on every idle after round 0 ($ROUNDS of $ROUNDS)"
assert_eq "$((ROUNDS + 1))" "$mate_reports" "A/legacy: ...although the teammate called SendMessage in every turn"
assert_eq "1" "$lead_total" "A/legacy: the lead's file holds only the LEAD's SendMessage"
assert_eq "0" "$lead_window" "A/legacy: the counting window over the lead's file sees 0 SendMessage"

scenario_in_process "$FIXED" "$SANDBOX/a-fixed"
echo "  scenario A  fixed  exit codes per idle: $TRACE"
assert_eq "0" "$BLOCKS" "A/fixed: never blocks a teammate that reports every turn"

# ---------------------------------------------------------------------------
# Scenario B — a genuinely silent turn, then the teammate complies.
#   The fixed hook must block once and release as soon as the continuation
#   calls SendMessage. The legacy shape keeps blocking after compliance.
# ---------------------------------------------------------------------------
scenario_block_then_comply() { # <hook> <workdir>  -> TRACE
  local hook="$1" dir="$2" i p
  mkdir -p "$dir/repo"
  in_process_layout "$dir" lead qa aqa-0001
  LEAD="$dir/lead.jsonl"
  MATE="$dir/lead/subagents/agent-aqa-0001.jsonl"
  p="$(jq -nc --arg tp "$LEAD" --arg cwd "$dir/repo" \
    '{session_id:"lead",transcript_path:$tp,cwd:$cwd,hook_event_name:"TeammateIdle",teammate_name:"qa"}')"
  t_prompt "$LEAD" "Ship the retry feature with the team."
  t_tool "$LEAD" Agent '{"name":"qa","subagent_type":"qa"}'
  t_text "$LEAD" "Waiting for qa."

  t_received "$MATE" team-lead "Run the checkout E2E case and report."
  t_tool "$MATE" Bash '{"command":"npm run e2e -- checkout"}'
  t_text "$MATE" "All 12 cases pass." # forgot to SendMessage
  run_hook "$hook" "$p"
  TRACE="$RC"
  i=1
  while [ "$RC" = 2 ] && [ "$i" -le "$ROUNDS" ]; do
    t_received "$LEAD" qa "(idle)"
    t_hook_feedback "$MATE" "$ERR"
    t_send "$MATE" team-lead "Conclusion: PASS, 12/12."
    t_text "$MATE" "Report sent."
    run_hook "$hook" "$p"
    TRACE="$TRACE $RC"
    i=$((i + 1))
  done
}

export LEGACY_STATE_DIR="$SANDBOX/legacy-state-b"
scenario_block_then_comply "$LEGACY_HOOK" "$SANDBOX/b-legacy"
echo "  scenario B  legacy exit codes per idle: $TRACE"
assert_eq "2 2 2 2 2 2" "$TRACE" "B/legacy: still blocking after $ROUNDS compliant reports (the loop)"

scenario_block_then_comply "$FIXED" "$SANDBOX/b-fixed"
echo "  scenario B  fixed  exit codes per idle: $TRACE"
assert_eq "2 0" "$TRACE" "B/fixed: blocks the silent turn once, releases after the turn that called SendMessage"

# ---------------------------------------------------------------------------
# Scenario C — defects 2 and 3 alone, on the teammate's OWN file.
#   The report is already counted; the hook is evaluated again after the
#   transcript grew by non-assistant lines only. The legacy window starts
#   AFTER the report, so it judges an empty "turn" as silent; from then on its
#   self-release (saved line count == current line count) can never match,
#   because every feedback line grows the file.
# ---------------------------------------------------------------------------
scenario_reevaluated() { # <hook> <workdir>  -> TRACE
  local hook="$1" dir="$2" i p f
  mkdir -p "$dir/repo"
  f="$dir/own.jsonl"
  : >"$f"
  p="$(jq -nc --arg tp "$f" --arg cwd "$dir/repo" \
    '{session_id:"own",transcript_path:$tp,cwd:$cwd,hook_event_name:"TeammateIdle",teammate_name:"qa"}')"
  t_received "$f" team-lead "Run the checkout E2E case and report."
  t_tool "$f" Bash '{"command":"npm run e2e -- checkout"}'
  t_send "$f" team-lead "Conclusion: PASS, 12/12."
  t_text "$f" "Reported."
  run_hook "$hook" "$p"
  TRACE="$RC"
  t_attachment "$f" queued_command # file grows, no new assistant output
  run_hook "$hook" "$p"
  TRACE="$TRACE $RC"
  i=1
  while [ "$RC" = 2 ] && [ "$i" -le 3 ]; do
    t_hook_feedback "$f" "$ERR"
    t_text "$f" "I already sent my report above."
    run_hook "$hook" "$p"
    TRACE="$TRACE $RC"
    i=$((i + 1))
  done
}

export LEGACY_STATE_DIR="$SANDBOX/legacy-state-c"
scenario_reevaluated "$LEGACY_HOOK" "$SANDBOX/c-legacy"
echo "  scenario C  legacy exit codes per idle: $TRACE"
assert_eq "0 2 2 2 2" "$TRACE" "C/legacy: re-evaluation after a counted report blocks, and never self-releases"

scenario_reevaluated "$FIXED" "$SANDBOX/c-fixed"
echo "  scenario C  fixed  exit codes per idle: $TRACE"
assert_eq "0 0" "$TRACE" "C/fixed: re-evaluation still sees the report (window starts at the turn's first line)"

summary
