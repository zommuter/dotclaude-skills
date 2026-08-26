#!/usr/bin/env bash
# roadmap:7354 (TODO id:7354)
#
# WHY: on run relay-20260826-122101-7415, RELAY_STATUS.md's
# "## Repeat-handback ALERTs (id:1432 — >=2x this run, a bug signal)" printed `_(none)_` while
# the SAME file's Blocked section listed lean4btc TWICE (worktrees `...-hard-repo-0` and
# `...-hard-repo-1`, both reason "integrate.sh produced no merged= line") and it-infra TWICE
# (identical prompt-size-gate reason). On the section's own >=2x threshold both should have
# alerted.
#
# ROOT CAUSE (confirmed against the code, NOT the item's worktree-suffix hypothesis): trackHandback()
# keys on `${repo}:${verdict}` (relay-loop.js:trackHandback / handback-guard.mjs:trackHandback) —
# `verdict` is the unit's classifier verdict (e.g. "hard"/"execute"), which does NOT change between
# retries. worktreePathFor()/branchFor() thread `unit.attempt` into the WORKTREE PATH and BRANCH
# NAME only (relay-loop.js ~2757-2758, `unitKey` ~2749) — never into the tracker key. So the
# worktree-suffix hypothesis is REFUTED: two handbacks with the same (repo, verdict) DO share one
# tracker key regardless of `-0`/`-1` worktree naming.
#
# The REAL bug: relay-loop.js has 11 distinct `state.handbacks.push(` call sites (one per handback
# class: null-report/context-death, child contract_met=false, sibling-branch, landed-unfinished,
# integrate "no merged= line" (result.deferred), durable-followup-failure, INTENSIVE fail-closed,
# stranded-dispatch, oversize/prompt-size-gate, provision-worktree-failed, integrator-threw) — but
# BEFORE this fix only ONE of them (the child contract_met=false site) called `trackHandback()`.
# Confirmed via `git show HEAD~:...` before the fix: 11 push sites, 1 trackHandback call. Both
# reasons observed in the live run — "integrate.sh produced no merged= line" (the result.deferred
# site) and the prompt-size-gate reason — are handback classes whose push site NEVER called
# trackHandback, so their counts never left 0/1 and handbackAlerts(tracker, 2) never saw them.
# This is exactly the built-but-unreferenced shape flagged by [[relay-builtgreen-but-unreferenced]]:
# handbackAlerts()/handbackTracker were fully implemented and rendered into RELAY_STATUS.md, but
# only wired to 1 of the 11 producers.
#
# THE FIX: relay-loop.js now calls `trackHandback(handbackTracker, unit.repo, unit.verdict, <reason>)`
# immediately after EVERY `state.handbacks.push(` call site (11 push sites, 11 trackHandback calls).
# trackHandback()/handbackAlerts() themselves are UNCHANGED (still byte-equivalent to
# handback-guard.mjs) — only the wiring (how many places call them) changed.
#
# KEY CHOICE: kept `(repo, verdict)`, NOT `(repo, reason)`. Justification: `reason` strings embed
# volatile detail (byte counts, truncated integrator stdout, timestamps) that legitimately differs
# between two occurrences of the SAME underlying failure — keying on it would systematically
# UNDER-count, the same failure shape as the bug this item reports, just moved into the reason
# string instead of the worktree suffix. `(repo, verdict)` is coarser and more robust to that
# volatility. KNOWN MISS: if id:907e re-classifies a repo to a DIFFERENT verdict between handbacks
# (e.g. execute -> hard) for the same underlying blocker, the two handbacks land under different
# keys and neither reaches the threshold. That gap is real but is NOT the bug reported here (both
# observed repos handed back under the SAME verdict both times) and is out of this item's scope.
#
# Hermetic: node-only, drives the actual pure functions from handback-guard.mjs (which
# trackHandback/handbackAlerts in relay-loop.js are byte-equivalent inline copies of) plus
# structural greps on relay-loop.js. No git, no network, no ~/.claude writes.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HELPER="$SRC_DIR/relay/scripts/handback-guard.mjs"
JS="$SRC_DIR/relay/scripts/relay-loop.js"
pass=0 fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); return 0; }
bad() { echo "BAD: $*"; fail=$((fail+1)); return 0; }
command -v node >/dev/null 2>&1 || { echo "FAIL: node not found"; exit 1; }
[[ -f "$HELPER" ]] || { echo "FAIL: handback-guard.mjs missing"; exit 1; }
[[ -f "$JS" ]] || { echo "FAIL: relay-loop.js missing"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/drive.mjs" <<NODE
import { trackHandback, handbackAlerts } from 'file://$HELPER'
const out = []

// ── (1) POSITIVE — the observed shape, reproduced: lean4btc hands back twice, same verdict
//     ('hard'), same reason class, but TWO DIFFERENT per-attempt worktree suffixes (the item's
//     own hypothesis). trackHandback() is never given the worktree path at all — only
//     (tracker, repo, verdict, reason) — so the suffix cannot leak into the key either way.
{
  const tracker = {}
  const reason = 'integrate.sh produced no merged= line (unparseable integrator output): ...'
  const worktreeSuffixes = ['~/.cache/relay/worktrees/lean4btc/run1-hard-repo-0', '~/.cache/relay/worktrees/lean4btc/run1-hard-repo-1']
  for (const wt of worktreeSuffixes) {
    // simulates: state.handbacks.push({repo, reason, worktreePath: wt}); trackHandback(tracker, repo, verdict, reason)
    trackHandback(tracker, 'lean4btc', 'hard', reason + ' (worktree ' + wt + ')')
  }
  const alerts = handbackAlerts(tracker, 2)
  out.push('fixed_alert_count=' + alerts.length)
  out.push('fixed_alert_repo=' + (alerts[0] ? alerts[0].repo : ''))
  out.push('fixed_alert_verdict=' + (alerts[0] ? alerts[0].verdict : ''))
  out.push('fixed_alert_hb_count=' + (alerts[0] ? alerts[0].count : 0))
}

// ── (2) it-infra: same shape, prompt-size-gate reason, verdict 'execute'.
{
  const tracker = {}
  trackHandback(tracker, 'it-infra', 'execute', 'prompt-size gate (id:4f9b/id:b018): NOT dispatched — ~41000 tok over budget')
  trackHandback(tracker, 'it-infra', 'execute', 'prompt-size gate (id:4f9b/id:b018): NOT dispatched — ~41500 tok over budget')
  const alerts = handbackAlerts(tracker, 2)
  out.push('itinfra_alert_count=' + alerts.length)
  out.push('itinfra_alert_count_field=' + (alerts[0] ? alerts[0].count : 0))
}

// ── (3) NEGATIVE CONTROL — the UNFIXED shape: two real handbacks are pushed (state.handbacks
//     would carry 2 entries), but — as in the pre-fix relay-loop.js, where the
//     "integrate.sh produced no merged= line" push site never called trackHandback() at all —
//     only the FIRST of the two calls trackHandback. This is exactly what the pre-fix code did:
//     11 push sites, 1 trackHandback call, so any handback NOT from that one site (which is what
//     both observed repos hit) never reaches the tracker.
{
  const tracker = {}
  trackHandback(tracker, 'lean4btc', 'hard', 'integrate.sh produced no merged= line (attempt 0)')
  // the second handback's push site is UNWIRED in the pre-fix code — no trackHandback call here.
  const alerts = handbackAlerts(tracker, 2)
  out.push('unfixed_alert_count=' + alerts.length)
}

console.log(out.join('\n'))
NODE

node "$TMP/drive.mjs" > "$TMP/res" 2>"$TMP/err" || { echo "FAIL: driver errored:"; cat "$TMP/err"; exit 1; }
get() { head -1 < <(grep -E "^$1=" "$TMP/res") | cut -d= -f2- ; }

[[ "$(get fixed_alert_count)" == "1" ]] && ok "lean4btc: 2 handbacks (same repo+verdict, different worktree suffixes) -> exactly 1 ALERT entry" || bad "expected 1 alert entry, got $(get fixed_alert_count)"
[[ "$(get fixed_alert_repo)" == "lean4btc" && "$(get fixed_alert_verdict)" == "hard" ]] && ok "alert names repo=lean4btc verdict=hard" || bad "alert repo/verdict wrong"
[[ "$(get fixed_alert_hb_count)" == "2" ]] && ok "alert carries handback count=2" || bad "alert count should be 2, got $(get fixed_alert_hb_count)"
[[ "$(get itinfra_alert_count)" == "1" && "$(get itinfra_alert_count_field)" == "2" ]] && ok "it-infra: 2 prompt-size-gate handbacks -> 1 ALERT with count=2" || bad "it-infra alert wrong"

# The negative control MUST fail to alert — this is what the unfixed relay-loop.js actually did.
if [[ "$(get unfixed_alert_count)" == "0" ]]; then
  ok "NEGATIVE CONTROL confirmed: with only 1 of 2 real handbacks wired to trackHandback() (the pre-fix shape), handbackAlerts(tracker,2) returns 0 entries — this is the exact bug: 2 real Blocked-section handbacks, 0 ALERTs"
else
  bad "negative control should have produced 0 alerts (reproducing the bug) but got $(get unfixed_alert_count) — the fixture no longer reproduces the reported failure"
fi

# ── Structural: EVERY state.handbacks.push( site in relay-loop.js must be paired with a
#     trackHandback(handbackTracker, ...) call — this is the actual fix (wiring, not the key).
push_sites=$(grep -c "state\.handbacks\.push(" "$JS" || true)
track_calls=$(grep -c "trackHandback(handbackTracker," "$JS" || true)
echo "push_sites=$push_sites track_calls=$track_calls"
[[ "$push_sites" -ge 10 ]] && ok "relay-loop.js has >=10 state.handbacks.push( sites ($push_sites found)" || bad "expected >=10 push sites, found $push_sites"
[[ "$track_calls" -eq "$push_sites" ]] && ok "every state.handbacks.push( site has a matching trackHandback(handbackTracker, ...) call ($track_calls == $push_sites)" || bad "trackHandback call count ($track_calls) does not match push-site count ($push_sites) — some handback class is still unwired"

# Baseline sanity: BEFORE the id:7354 fix, this repo's history had 11 push sites but only 1
# trackHandback call (the exact under-wiring this test guards against regressing to).
prefix_push=$(git -C "$SRC_DIR" show HEAD:relay/scripts/relay-loop.js 2>/dev/null | grep -c "state\.handbacks\.push(" || true)
prefix_track=$(git -C "$SRC_DIR" show HEAD:relay/scripts/relay-loop.js 2>/dev/null | grep -c "trackHandback(handbackTracker," || true)
if [[ -n "$prefix_push" && "$prefix_push" -gt 0 ]]; then
  echo "pre-fix HEAD had push_sites=$prefix_push track_calls=$prefix_track (informational; HEAD may already include this fix once committed)"
fi

echo "test_repeat_handback_wiring_7354: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
