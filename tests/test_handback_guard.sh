#!/usr/bin/env bash
# roadmap:1432 — loud handback tracking + WHOLE-DISPATCH re-dispatch-loop suppression.
# handback-followup.py (id:3801) durably gates ITEM-level handbacks, but a whole-dispatch
# "no executor-actionable work / classifier verdict wrong" handback (route=none, no
# handback_item) produced no durable action → the repo was re-dispatched the same bogus verdict
# every round (it-infra ×5 in one run). This tests the two defense-in-depth pieces:
#   (a) dispatch-level suppression via a negative cache keyed on (repo,verdict,work_sig-at-handback)
#       that suppresses re-dispatch while work_sig is unchanged and clears on genuine churn;
#   (b) the >=2× repeat-handback ALERT surfacing.
# The logic lives in a pure helper (relay/scripts/handback-guard.mjs) so it is node-unit-testable;
# relay-loop.js carries byte-equivalent inline copies (structural asserts pin the wiring).
# Hermetic: node-only, no git, no network.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HELPER="$SRC_DIR/relay/scripts/handback-guard.mjs"
JS="$SRC_DIR/relay/scripts/relay-loop.js"
pass=0 fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); return 0; }
bad() { echo "BAD: $*"; fail=$((fail+1)); return 0; }
command -v node >/dev/null 2>&1 || { echo "FAIL: node not found"; exit 1; }
[[ -f "$HELPER" ]] || { echo "FAIL: handback-guard.mjs missing"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/drive.mjs" <<NODE
import { recordNoWorkHandback, applyNoWorkSuppression, trackHandback, handbackAlerts } from 'file://$HELPER'
const out = []

// --- (a) dispatch-level suppression ------------------------------------------------
// A route=none no-work handback stamps the negative cache with the work_sig at handback time.
const neg = {}
recordNoWorkHandback(neg, 'it-infra', 'execute', 'SIGA')

// SAME sig next round → SUPPRESSED (do NOT re-dispatch the bogus verdict).
{
  const { kept, suppressed } = applyNoWorkSuppression([{ repo: 'it-infra', verdict: 'execute', work_sig: 'SIGA' }], neg, 'run1')
  out.push('samesig_kept=' + kept.length)
  out.push('samesig_suppressed=' + suppressed.length)
  if (suppressed.length) out.push('samesig_reason_has_id=' + (suppressed[0].reason.includes('id:1432') ? '1' : '0'))
}

// After a SUPPRESSION, the entry PERSISTS (still SIGA) → still suppressed on a further round.
{
  const { kept, suppressed } = applyNoWorkSuppression([{ repo: 'it-infra', verdict: 'execute', work_sig: 'SIGA' }], neg, 'run1')
  out.push('persist_kept=' + kept.length)
  out.push('persist_suppressed=' + suppressed.length)
}

// work_sig CHANGES (genuine churn) → entry CLEARS → re-dispatch allowed.
{
  const { kept, suppressed } = applyNoWorkSuppression([{ repo: 'it-infra', verdict: 'execute', work_sig: 'SIGB' }], neg, 'run1')
  out.push('changedsig_kept=' + kept.length)
  out.push('changedsig_suppressed=' + suppressed.length)
  out.push('changedsig_entry_cleared=' + (neg['it-infra:execute'] === undefined ? '1' : '0'))
}

// A DIFFERENT verdict for the same repo is NOT suppressed by an execute handback.
{
  const n2 = {}
  recordNoWorkHandback(n2, 'it-infra', 'execute', 'SIGA')
  const { kept, suppressed } = applyNoWorkSuppression([{ repo: 'it-infra', verdict: 'review', work_sig: 'SIGA' }], n2, 'run1')
  out.push('otherverdict_kept=' + kept.length)
  out.push('otherverdict_suppressed=' + suppressed.length)
}

// Injected units are EXEMPT even when a matching negative-cache entry exists.
{
  const n3 = {}
  recordNoWorkHandback(n3, 'it-infra', 'execute', 'SIGA')
  const { kept, suppressed } = applyNoWorkSuppression([{ repo: 'it-infra', verdict: 'execute', work_sig: 'SIGA', injected: true }], n3, 'run1')
  out.push('injected_kept=' + kept.length)
  out.push('injected_suppressed=' + suppressed.length)
}

// --- (b) repeat-handback ALERT -----------------------------------------------------
const tr = {}
trackHandback(tr, 'it-infra', 'execute', 'no executor-actionable work')          // count 1
out.push('after1_alerts=' + handbackAlerts(tr, 2).length)                          // below threshold
trackHandback(tr, 'it-infra', 'execute', 'still no work — classifier verdict wrong') // count 2
const a = handbackAlerts(tr, 2)
out.push('after2_alerts=' + a.length)
if (a.length) {
  out.push('alert_repo=' + a[0].repo)
  out.push('alert_verdict=' + a[0].verdict)
  out.push('alert_count=' + a[0].count)
  out.push('alert_has_lastreason=' + (a[0].lastReason.length > 0 ? '1' : '0'))
}
// A single handback of a DIFFERENT repo stays below the alert threshold.
trackHandback(tr, 'other-repo', 'review', 'one-off')
out.push('mixed_alerts=' + handbackAlerts(tr, 2).length)  // still only it-infra:execute

console.log(out.join('\n'))
NODE

node "$TMP/drive.mjs" > "$TMP/res" 2>"$TMP/err" || { echo "FAIL: driver errored:"; cat "$TMP/err"; exit 1; }
get() { grep -E "^$1=" "$TMP/res" | head -1 | cut -d= -f2-; }

# (a) suppression
[[ "$(get samesig_kept)" == "0" && "$(get samesig_suppressed)" == "1" ]] && ok "same work_sig ⇒ no-work verdict SUPPRESSED (not re-dispatched)" || bad "same-sig should suppress"
[[ "$(get samesig_reason_has_id)" == "1" ]] && ok "suppression reason cites id:1432" || bad "suppression reason missing id:1432"
[[ "$(get persist_kept)" == "0" && "$(get persist_suppressed)" == "1" ]] && ok "negative cache PERSISTS across rounds (still suppressed)" || bad "cache should persist while sig unchanged"
[[ "$(get changedsig_kept)" == "1" && "$(get changedsig_suppressed)" == "0" ]] && ok "changed work_sig (genuine churn) ⇒ re-dispatch ALLOWED" || bad "changed sig should re-dispatch"
[[ "$(get changedsig_entry_cleared)" == "1" ]] && ok "changed sig CLEARS the negative-cache entry" || bad "changed sig should clear the entry"
[[ "$(get otherverdict_kept)" == "1" && "$(get otherverdict_suppressed)" == "0" ]] && ok "a different verdict for the same repo is NOT suppressed" || bad "other verdict wrongly suppressed"
[[ "$(get injected_kept)" == "1" && "$(get injected_suppressed)" == "0" ]] && ok "injected units are EXEMPT from suppression" || bad "injected unit wrongly suppressed"

# (b) alerts
[[ "$(get after1_alerts)" == "0" ]] && ok "1 handback is below the >=2 alert threshold" || bad "single handback should not alert"
[[ "$(get after2_alerts)" == "1" ]] && ok "2 handbacks (same repo+verdict) raise an ALERT" || bad "2× handback should alert"
[[ "$(get alert_repo)" == "it-infra" && "$(get alert_verdict)" == "execute" && "$(get alert_count)" == "2" ]] && ok "alert carries repo+verdict+count" || bad "alert fields wrong"
[[ "$(get alert_has_lastreason)" == "1" ]] && ok "alert carries the last handback reason" || bad "alert missing last reason"
[[ "$(get mixed_alerts)" == "1" ]] && ok "a one-off handback of another repo stays below threshold" || bad "one-off wrongly alerted"

# --- Structural: relay-loop.js wires the inline copies (it cannot import in the sandbox) ---
grep -q "noWorkNegCache" "$JS" || bad "relay-loop.js missing the noWorkNegCache persistent object"
grep -q "handbackTracker" "$JS" || bad "relay-loop.js missing the handbackTracker persistent object"
grep -q "applyNoWorkSuppression" "$JS" || bad "relay-loop.js does not apply the no-work suppression filter"
grep -q "recordNoWorkHandback" "$JS" || bad "relay-loop.js does not record no-work handbacks"
grep -q "trackHandback" "$JS" || bad "relay-loop.js does not track handbacks for the repeat alert"
grep -q "id:1432" "$JS" || bad "relay-loop.js no-work suppression not tagged id:1432"
# The suppression must be keyed on work_sig (stable across the pool's own checkpoint churn),
# NOT the discover-sig which the empty-integrate checkpoint trivially bumps.
grep -q "unit.work_sig" "$JS" || bad "relay-loop.js does not stamp the negative cache with work_sig"
# The repeat alert must be surfaced in RELAY_STATUS + the exit summary.
grep -q "handbackAlertsList" "$JS" || bad "relay-loop.js does not surface handback alerts into the status snapshot"
grep -q "Repeat-handback ALERT" "$JS" || bad "relay-loop.js RELAY_STATUS missing the repeat-handback ALERT section"
grep -q "repeatHandbacks" "$JS" || bad "relay-loop.js exit summary does not include repeatHandbacks"
# The recording must only fire for route=none / no-durable-action handbacks (item-level goes to id:3801).
grep -q "report.route === 'none'" "$JS" || bad "relay-loop.js does not gate no-work recording on route=none"

echo "test_handback_guard: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
