#!/usr/bin/env bash
# roadmap:5b12 — Tick-ownership inversion (seam of id:ae08): execute/hard executors no
# longer tick their own ROADMAP.md checkbox; the driver/integrator ticks from worked_ids.
# Asserts BOTH surfaces the acceptance names — the executor CONTRACT TEXT and the INTEGRATE
# PATH in relay-loop.js — plus the v11->v12 contract bump and the CLAUDE.md pointer match.
# relay-loop.js is a Workflow script (not directly runnable here), so its half is structural
# greps, exactly as tests/test_relay_worked_ids.sh does; the mechanical tick helper itself is
# exercised end-to-end in tests/test_roadmap_tick.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACT="$ROOT/relay/references/executor-contract.md"
CLAUDEMD="$ROOT/CLAUDE.md"
JS="$ROOT/relay/scripts/relay-loop.js"
TICK="$ROOT/relay/scripts/roadmap-tick.sh"

pass=0 fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); return 0; }
bad() { echo "BAD: $*"; fail=$((fail+1)); return 0; }

for f in "$CONTRACT" "$CLAUDEMD" "$JS" "$TICK"; do
  [[ -f "$f" ]] || { echo "FAIL: missing $f"; exit 1; }
done

# ── Contract version bumped past v11 -> v12 (id:5b12), and the two markers agree ──
# NOTE: the contract has since bumped further (v12 -> v13, id:5eeb); this test only
# asserts the v11->v12 tick-ownership marker never regresses and that CLAUDE.md's
# pointer still agrees with whatever marker the contract currently carries — it does
# not pin an exact version number, so later bumps don't require touching this test.
contract_marker="$(grep -oE 'relay-executor contract v[0-9]+' "$CONTRACT" | awk 'NR==1')"
pointer_marker="$(grep -oE 'relay-executor contract v[0-9]+' "$CLAUDEMD" | awk 'NR==1')"
[[ -n "$contract_marker" ]] || bad "no 'relay-executor contract vN' marker found in contract"
contract_v="$(printf '%s' "$contract_marker" | tr -dc '0-9')"
[[ -n "$contract_v" && "$contract_v" -ge 12 ]] || bad "contract marker has not reached v12 (id:5b12)"
grep -q 'relay-executor contract v11' "$CONTRACT" && bad "stale v11 marker still present in contract"
[[ "$contract_marker" == "$pointer_marker" ]] \
  || bad "CLAUDE.md '## Relay contract' pointer ($pointer_marker) disagrees with the contract marker ($contract_marker)"
ok "contract bumped to $contract_marker and CLAUDE.md pointer matches"

# ── CONTRACT TEXT: executors report worked_ids and no longer tick; the driver ticks ──
grep -q 'Driver ticks, not you' "$CONTRACT" || bad "contract does not state driver-ticks inversion"
grep -qi 'DO NOT tick' "$CONTRACT" || bad "contract does not tell executors not to tick"
grep -q 'roadmap-tick.sh' "$CONTRACT" || bad "contract does not name the driver tick helper"
grep -q 'id:5b12' "$CONTRACT" || bad "contract does not carry the id:5b12 provenance marker"
ok "contract text: executors report worked_ids, do not tick; driver ticks (id:5b12)"

# ── INTEGRATE PATH: the integrator ticks from workedIds via roadmap-tick.sh, gated exec/hard ──
# id:087b RELOCATION — the driver-side tick moved out of relay-loop.js's LLM integrator prompt
# into relay/scripts/integrate.sh (step 4b), which relay-loop.js dispatches as one mechanical
# hop. All FOUR properties are preserved and now executed rather than instructed: the step
# exists, it calls roadmap-tick.sh, it passes the repo path and the worked ids, and it is
# gated to execute/hard (review/handoff self-tick in their own worktree). relay-loop.js is
# still checked for the half it owns — passing workedIds through to the script.
INTEG="$ROOT/relay/scripts/integrate.sh"
[[ -x "$INTEG" ]] || bad "integrate.sh not found/executable"
grep -q 'DRIVER-SIDE ROADMAP TICK (id:5b12' "$INTEG" || bad "integrate path has no driver-tick step"
grep -q 'ROADMAP_TICK' "$INTEG" || bad "integrate path does not call roadmap-tick.sh"
grep -q 'roadmap-tick.sh' "$INTEG" || bad "integrate path does not resolve roadmap-tick.sh"
grep -qF '"$ROADMAP_TICK" "$path" "$ids"' "$INTEG" || bad "integrate tick does not pass the repo path + worked ids to roadmap-tick.sh"
grep -qF "workedIds.join(',')" "$JS" || bad "relay-loop.js does not pass workedIds to the integrator"
grep -qF "integrateArgs.push('--ids'" "$JS" || bad "relay-loop.js does not forward --ids to integrate.sh — the tick would have nothing to tick"
# gated to execute/hard: review/handoff self-tick in their own worktree, not driver-ticked.
grep -qE '^\s*execute\|hard\)' "$INTEG" \
  || bad "driver-tick is not gated to execute/hard units"
ok "integrate path ticks from workedIds via roadmap-tick.sh, gated to execute/hard"

# ── HARD prompt no longer instructs a self-tick (it now defers to the driver) ──
grep -q 'checkbox yourself (executor-contract v12' "$JS" \
  || bad "hard child prompt still tells the child to tick its own checkbox"
ok "hard child prompt defers ticking to the driver (v12)"

# ── The tick helper is executable ──
[[ -x "$TICK" ]] || bad "roadmap-tick.sh is not executable"
ok "roadmap-tick.sh present and executable"

echo "test_relay_driver_ticks: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
