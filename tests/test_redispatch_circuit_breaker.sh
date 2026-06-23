#!/usr/bin/env bash
# roadmap:365b — re-dispatch circuit breaker (mechanism 2, deterministic JS backstop). Even
# if the discover-shard's recurring-audit gate (mechanism 1) slips, this catches ANY dispatch
# spin: the SAME (repo, verdict) unit dispatched >3× in one pool run with an UNCHANGED work_sig
# (no substantive change) is suppressed. The breaker logic lives in a pure helper
# (relay/scripts/redispatch-guard.mjs) so it is node-unit-testable; relay-loop.js carries a
# byte-identical inline copy (a structural assertion below pins that it is wired).
# Hermetic: node-only, no git, no network.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HELPER="$SRC_DIR/relay/scripts/redispatch-guard.mjs"
JS="$SRC_DIR/relay/scripts/relay-loop.js"
pass=0 fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); return 0; }
bad() { echo "BAD: $*"; fail=$((fail+1)); return 0; }
command -v node >/dev/null 2>&1 || { echo "FAIL: node not found"; exit 1; }
[[ -f "$HELPER" ]] || { echo "FAIL: redispatch-guard.mjs missing"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# Drive the pure helper through node; print one assertion result per line as key=value.
cat > "$TMP/drive.mjs" <<NODE
import { applyRedispatchGuard } from 'file://$HELPER'

const guard = {}
const mk = (sig, extra = {}) => ({ repo: 'foo', verdict: 'hard', work_sig: sig, ...extra })
const out = []

// Same (repo,verdict,work_sig) seen 4×: dispatch on 1,2,3; suppressed on the 4th.
for (let i = 1; i <= 4; i++) {
  const { kept, suppressed } = applyRedispatchGuard([mk('AAAA')], guard, 'run1')
  out.push('round' + i + '_kept=' + kept.length)
  out.push('round' + i + '_suppressed=' + suppressed.length)
  if (i === 4 && suppressed.length) out.push('reason_has_id=' + (suppressed[0].reason.includes('id:365b') ? '1' : '0'))
}

// A work_sig CHANGE resets the counter → dispatches again.
{
  const { kept, suppressed } = applyRedispatchGuard([mk('BBBB')], guard, 'run1')
  out.push('afterchange_kept=' + kept.length)
  out.push('afterchange_suppressed=' + suppressed.length)
}

// Injected units are EXEMPT even past the threshold.
const ig = {}
let injKept = 0
for (let i = 1; i <= 5; i++) {
  const { kept } = applyRedispatchGuard([mk('CCCC', { injected: true })], ig, 'run1')
  injKept += kept.length
}
out.push('injected_kept_total=' + injKept)

console.log(out.join('\n'))
NODE

node "$TMP/drive.mjs" > "$TMP/res" 2>"$TMP/err" || { echo "FAIL: driver errored:"; cat "$TMP/err"; exit 1; }
get() { grep -E "^$1=" "$TMP/res" | head -1 | cut -d= -f2; }

[[ "$(get round1_kept)" == "1" && "$(get round1_suppressed)" == "0" ]] && ok "round 1 dispatches" || bad "round 1 should dispatch"
[[ "$(get round3_kept)" == "1" && "$(get round3_suppressed)" == "0" ]] && ok "round 3 dispatches (not more than thrice = 3 allowed)" || bad "round 3 should still dispatch"
[[ "$(get round4_kept)" == "0" && "$(get round4_suppressed)" == "1" ]] && ok "round 4 SUPPRESSED (count would reach 4)" || bad "round 4 should be suppressed"
[[ "$(get reason_has_id)" == "1" ]] && ok "suppression reason cites id:365b" || bad "suppression reason missing id:365b"
[[ "$(get afterchange_kept)" == "1" && "$(get afterchange_suppressed)" == "0" ]] && ok "a work_sig change RESETS the breaker" || bad "work_sig change did not reset the counter"
[[ "$(get injected_kept_total)" == "5" ]] && ok "injected units are EXEMPT (never suppressed)" || bad "injected unit was suppressed (must be exempt)"

# Structural: relay-loop.js wires the breaker inline (it cannot import in the Workflow sandbox).
grep -q "redispatchGuard" "$JS" || bad "relay-loop.js missing the redispatchGuard persistent object"
grep -q "id:365b" "$JS" || bad "relay-loop.js circuit breaker not tagged id:365b"
grep -q "work_sig" "$JS" || bad "relay-loop.js does not key the breaker on work_sig"
grep -q "relay:recurring-audit" "$JS" || bad "relay-loop.js shard prose missing the recurring-audit marker clause (mechanism 1)"
grep -q "substantive_unaudited" "$JS" || bad "relay-loop.js missing substantive_unaudited handling (mechanism 1)"
[[ "$pass" -gt 0 ]] && grep -q "redispatchGuard" "$JS" && ok "relay-loop.js wires the inline circuit breaker (redispatchGuard, id:365b)" || true

echo "test_redispatch_circuit_breaker: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
