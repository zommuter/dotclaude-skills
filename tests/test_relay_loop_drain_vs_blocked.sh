#!/usr/bin/env bash
# roadmap:4ca8 — a suppressed/surfaced repo must not count as "backlog drained". DISTINCT root
# from id:1735 (that TODO's "stale discovery snapshot" hypothesis is FALSIFIED — discovery was
# fresh and correct). Run relay-20260717-100452-13146: reconcile-repo.sh:192 (id:1f53 orphan
# suppress-redispatch) correctly refused to re-dispatch loderite because id:4c02's partial work
# was parked, and add_surfaced surfaced the REPO -> discover-repo.sh skips classify ->
# actionable.length === 0 -> runRound returns {actionable:0} -> 2 dry rounds -> "backlog
# drained" while 8 open [ROUTINE] items sat there. classifyDrainBacklog saw the entry but had no
# bucket for "suppressed re-dispatch" (logged a bare "1 other"), and stopReason was never set on
# the drain exit (RELAY_STATUS §Stop reason stayed "none").
#
# Fix: (1) the dry-round predicate must distinguish "no work" (isDryRound) from "work exists but
# is BLOCKED" (isBlockedRound) — a round with >=1 surfaced/suppressed repo stops IMMEDIATELY with
# stopReason "blocked-pending-human", not via the generic 2-dry-round drain path. (2) a
# `suppressed` bucket in classifyDrainBacklog, matching reconcile-repo.sh's reason string
# verbatim, surfaced as loudly as `gated` (with a /relay reconcile pointer). (3) stopReason is
# ALWAYS set on the drain exit ("drained", never left null).
#
# The pure logic lives in relay/scripts/drain.mjs (isBlockedRound/isDryRound/classifyDrainBacklog)
# so it is node-unit-testable; relay-loop.js carries byte-equivalent inline copies (the Workflow
# sandbox cannot `import` — no filesystem/require).
#
# HONEST COVERAGE LIMIT (same as id:f980/id:365b/id:1735 precedent): relay-loop.js is a Workflow
# module that cannot be imported or executed in this harness (id:2ec4). The pure-helper tests
# below cover the real predicate/bucketing LOGIC. The structural greps only pin that
# relay-loop.js WIRES the fixed shape (isBlockedRound checked before isDryRound, stopReason set
# on both exits, the suppressed bucket exists) — they do not prove a live multi-round pool run
# actually stops at the right round with the right reason, which is unreachable from this harness.
#
# Scope note (deliberately NOT specced here): the whole-repo blast radius of id:1f53's
# suppression (one parked orphan stalling a repo's other unrelated open items) is a SEPARATE
# design question — this item does not touch reconcile-repo.sh's suppression behaviour at all.
#
# Hermetic: node-only, no git, no network, no ~/.claude writes.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HELPER="$SRC_DIR/relay/scripts/drain.mjs"
JS="$SRC_DIR/relay/scripts/relay-loop.js"
RECONCILE="$SRC_DIR/relay/scripts/reconcile-repo.sh"
pass=0 fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); return 0; }
bad() { echo "BAD: $*"; fail=$((fail+1)); return 0; }
command -v node >/dev/null 2>&1 || { echo "FAIL: node not found"; exit 1; }
[[ -f "$HELPER" ]] || { echo "FAIL: drain.mjs missing"; exit 1; }
[[ -f "$RECONCILE" ]] || { echo "FAIL: reconcile-repo.sh missing"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# ── Case 4 (reconcile-repo.sh suppression is item-bound — GREEN guard, pins the verbatim string
#    case 1 below depends on; NOT a spec change, id:1f53 stays untouched) ─────────────────────
grep -q 'suppressed re-dispatch' "$RECONCILE" || bad "reconcile-repo.sh no longer emits the verbatim 'suppressed re-dispatch' reason (case 1's string would go stale)"
grep -qE 'suppressed re-dispatch: \$why' "$RECONCILE" || bad "reconcile-repo.sh suppression reason is not item-bound (\$why names the parked id)"

cat > "$TMP/drive.mjs" <<NODE
import { classifyDrainBacklog, isBlockedRound, isDryRound } from 'file://$HELPER'
const out = []

// ── Case 1: classifyDrainBacklog buckets the VERBATIM observed suppression reason ─────────────
const suppressionReason = "suppressed re-dispatch: parked partial work for id:4c02 still OPEN on relay/orphan/relay-20260717-100452-13146-execute — manual /relay reconcile; cost hint: relay-burn.sh --run relay-20260717-103246-17312"
const c = classifyDrainBacklog([{ repo: 'loderite', reason: suppressionReason }])
out.push('suppressed_bucket=' + c.suppressed.join('|'))
out.push('not_in_other=' + (c.other.includes('loderite') ? '0' : '1'))
out.push('summary_names_reconcile=' + (/\\/relay reconcile/.test(c.summary) ? '1' : '0'))
out.push('summary_names_repo=' + (c.summary.includes('loderite') ? '1' : '0'))

// A gated [HARD] reason still buckets separately (control — suppressed doesn't swallow gated).
const c2 = classifyDrainBacklog([
  { repo: 'loderite', reason: suppressionReason },
  { repo: 'other-repo', reason: 'HARD backlog is gated — needs a /meeting to unblock (items: id:abcd [HARD — meeting])' },
])
out.push('mixed_suppressed=' + c2.suppressed.join('|'))
out.push('mixed_gated=' + c2.gated.join('|'))

// ── Case 2: a blocked round is NOT a dry round ────────────────────────────────────────────────
out.push('blocked_when_surfaced=' + isBlockedRound({ actionable: 0, produced: 0, surfaced: 1 }))
out.push('dry_when_surfaced=' + isDryRound({ actionable: 0, produced: 0, surfaced: 1 }))
out.push('blocked_when_empty=' + isBlockedRound({ actionable: 0, produced: 0, surfaced: 0 }))
out.push('dry_when_empty=' + isDryRound({ actionable: 0, produced: 0, surfaced: 0 }))
// A round with real substantive progress is neither blocked nor dry, regardless of surfaced.
out.push('blocked_when_progress=' + isBlockedRound({ substantive: 1, surfaced: 1 }))
out.push('dry_when_progress=' + isDryRound({ substantive: 1, surfaced: 0 }))
// Undefined/missing fields must not crash (conservative: treated as 0).
out.push('dry_when_undefined=' + isDryRound({}))
out.push('blocked_when_undefined=' + isBlockedRound(undefined))

console.log(out.join('\n'))
NODE

node "$TMP/drive.mjs" > "$TMP/res" 2>"$TMP/err" || { echo "FAIL: driver errored:"; cat "$TMP/err"; exit 1; }
get() { grep -E "^$1=" "$TMP/res" | head -1 | cut -d= -f2-; }

[[ "$(get suppressed_bucket)" == "loderite" ]] && ok "classifyDrainBacklog buckets the verbatim suppression reason as 'suppressed', not 'other'" || bad "suppression should bucket as suppressed: $(get suppressed_bucket)"
[[ "$(get not_in_other)" == "1" ]] && ok "the suppressed repo does NOT also land in 'other'" || bad "suppressed repo leaked into other"
[[ "$(get summary_names_reconcile)" == "1" ]] && ok "the wind-down summary points at /relay reconcile for suppressed repos" || bad "summary missing /relay reconcile pointer"
[[ "$(get summary_names_repo)" == "1" ]] && ok "the wind-down summary NAMES the suppressed repo" || bad "summary does not name the suppressed repo"
[[ "$(get mixed_suppressed)" == "loderite" && "$(get mixed_gated)" == "other-repo" ]] && ok "suppressed and gated reasons bucket independently (no cross-contamination)" || bad "mixed bucketing wrong: suppressed=$(get mixed_suppressed) gated=$(get mixed_gated)"

[[ "$(get blocked_when_surfaced)" == "true" ]] && ok "a round with 0 substantive + surfaced>0 IS a blocked round" || bad "blocked round not detected"
[[ "$(get dry_when_surfaced)" == "false" ]] && ok "a blocked round (surfaced>0) is NOT a dry round" || bad "blocked round wrongly counted as dry — the id:4ca8 bug"
[[ "$(get blocked_when_empty)" == "false" ]] && ok "a genuinely empty round (surfaced=0) is NOT a blocked round" || bad "empty round wrongly flagged blocked"
[[ "$(get dry_when_empty)" == "true" ]] && ok "a genuinely empty round (surfaced=0) IS a dry round" || bad "empty round should be dry"
[[ "$(get blocked_when_progress)" == "false" ]] && ok "a round with real substantive progress is never 'blocked' even if surfaced>0" || bad "progress round wrongly flagged blocked"
[[ "$(get dry_when_progress)" == "false" ]] && ok "a round with real substantive progress is never 'dry'" || bad "progress round wrongly flagged dry"
[[ "$(get dry_when_undefined)" == "true" ]] && ok "isDryRound tolerates a missing surfaced/substantive field (defaults to 0)" || bad "isDryRound crashed/misbehaved on {}"
[[ "$(get blocked_when_undefined)" == "false" ]] && ok "isBlockedRound tolerates an undefined round object" || bad "isBlockedRound crashed/misbehaved on undefined"

# ── Case 3 (structural backstop): the drain exit ALWAYS sets stopReason; the new blocked-round
#    exit sets a DISTINCT stopReason (never conflated with a genuine drain). ────────────────────
grep -q "isBlockedRound(r)" "$JS" || bad "relay-loop.js does not check isBlockedRound(r) before the dry-round path"
grep -q "stopReason = 'blocked-pending-human'" "$JS" || bad "relay-loop.js does not set stopReason='blocked-pending-human' on a blocked-round stop"
grep -q "stopReason = stopReason || 'drained'" "$JS" || bad "relay-loop.js drain exit does not always set stopReason (still nullable)"
grep -q "function classifyDrainBacklog" "$JS" || bad "relay-loop.js missing the inline classifyDrainBacklog helper"
grep -q "buckets.suppressed" "$JS" || bad "relay-loop.js inline classifyDrainBacklog copy missing the suppressed bucket"
# Ordering: isBlockedRound must be checked BEFORE isDryRound (a surfaced>0 round must never
# reach the dry-counter increment at all — see the "id:4ca8 — now gated on isDryRound" note).
blocked_line=$(grep -n "if (isBlockedRound(r))" "$JS" | head -1 | cut -d: -f1)
dry_line=$(grep -n "if (isDryRound(r))" "$JS" | head -1 | cut -d: -f1)
if [[ -n "$blocked_line" && -n "$dry_line" && "$blocked_line" -lt "$dry_line" ]]; then
  ok "isBlockedRound(r) is checked BEFORE isDryRound(r) in the outer loop"
else
  bad "isBlockedRound must precede isDryRound (blocked_line=$blocked_line dry_line=$dry_line)"
fi

echo "test_relay_loop_drain_vs_blocked: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
