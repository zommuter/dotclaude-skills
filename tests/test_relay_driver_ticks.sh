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

# ── Contract version bumped v11 -> v12, and the two markers agree ──
grep -q 'relay-executor contract v12' "$CONTRACT" || bad "contract marker is not v12"
grep -q 'relay-executor contract v11' "$CONTRACT" && bad "stale v11 marker still present in contract"
grep -q '## Relay contract <!-- relay-executor contract v12 -->' "$CLAUDEMD" \
  || bad "CLAUDE.md '## Relay contract' pointer is not v12"
ok "contract bumped to v12 and CLAUDE.md pointer matches"

# ── CONTRACT TEXT: executors report worked_ids and no longer tick; the driver ticks ──
grep -q 'Driver ticks, not you' "$CONTRACT" || bad "contract does not state driver-ticks inversion"
grep -qi 'DO NOT tick' "$CONTRACT" || bad "contract does not tell executors not to tick"
grep -q 'roadmap-tick.sh' "$CONTRACT" || bad "contract does not name the driver tick helper"
grep -q 'id:5b12' "$CONTRACT" || bad "contract does not carry the id:5b12 provenance marker"
ok "contract text: executors report worked_ids, do not tick; driver ticks (id:5b12)"

# ── INTEGRATE PATH: the integrator ticks from workedIds via roadmap-tick.sh, gated exec/hard ──
grep -q 'DRIVER-SIDE ROADMAP TICK (id:5b12' "$JS" || bad "integrate path has no driver-tick step"
grep -q 'roadmap-tick.sh' "$JS" || bad "integrate path does not call roadmap-tick.sh"
grep -qF 'roadmap-tick.sh ${unit.path}' "$JS" || bad "integrate tick does not pass unit.path to roadmap-tick.sh"
grep -qF "workedIds.join(',')" "$JS" || bad "integrate tick does not pass workedIds to roadmap-tick.sh"
# gated to execute/hard: review/handoff self-tick in their own worktree, not driver-ticked.
grep -q "(unit.verdict === 'execute' || unit.verdict === 'hard')" "$JS" \
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
