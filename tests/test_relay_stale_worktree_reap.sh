#!/usr/bin/env bash
# roadmap:3ac8 — discovery must distinguish a STALE worktree left by a dead run (no fresh
# claim) from a genuinely in-flight one (fresh claim), instead of treating any foreign-runId
# worktree's existence as "in-flight elsewhere" (which falsely starved the pool of 14 repos
# on 2026-06-15). Stale + empty → reap & classify; stale + commits → surface as handback.
# Static-structural checks: the once-only claim.sh peek stays in the relay-loop.js prelude
# (builds the live-claims set), and the actual reap/park decision is now mechanical in
# reconcile-repo.sh, which receives that set via --live-claims instead of peeking itself.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JS="$SRC_DIR/relay/scripts/relay-loop.js"
RECONCILE="$SRC_DIR/relay/scripts/reconcile-repo.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$JS" ]] || fail "relay-loop.js not found at $JS"
node --check "$JS" || fail "relay-loop.js fails node --check"
[[ -x "$RECONCILE" ]] || fail "reconcile-repo.sh not found at $RECONCILE"

# (1) the prelude consults LIVE claims (claim.sh peek), ONCE, to build the live-claims set —
#     and reconcile-repo.sh receives that set via --live-claims rather than peeking itself
#     (peeking per-repo would N× the cost, the id:9ed4 sharding rationale).
grep -q "claim.sh peek" "$JS" || fail "prelude does not consult claim.sh peek (can't tell live from dead)"
grep -q -- "--live-claims" "$RECONCILE" || fail "reconcile-repo.sh does not accept --live-claims (still peeking itself?)"

# (2) the id:3ac8 marker + the 'absence of a live claim → stale' reasoning is present in the
#     mechanical reconciler.
grep -q "3ac8" "$RECONCILE" || fail "no 3ac8 marker in reconcile-repo.sh"
grep -q "is_live_claimed" "$RECONCILE" || fail "reconcile-repo.sh does not key the stale case on is_live_claimed (live_claims membership)"

# (3) empty stale worktree (ancestor of main) is REAPED and the repo classified normally.
grep -q "merge-base --is-ancestor" "$RECONCILE" || fail "reconcile-repo.sh does not test ancestor-of-main (empty) before reaping"
grep -Eq "worktree remove --force" "$RECONCILE" || fail "reconcile-repo.sh never reaps an empty stale worktree"

# (4) commit-bearing stale worktree is NEVER reaped — parked (id:689c) and surfaced, not lost.
grep -Eqi "park|parked" "$RECONCILE" \
  || fail "reconcile-repo.sh does not park a commit-bearing stale worktree (data-loss risk)"
grep -q "relay/orphan/" "$RECONCILE" \
  || fail "reconcile-repo.sh does not surface the parked commit via the relay/orphan/* ref"

# (5) the live-claim case still surfaces as in-flight-elsewhere (id:ebfb behaviour preserved).
grep -q "in-flight elsewhere" "$RECONCILE" || fail "live-claim case no longer surfaces as in-flight elsewhere"

pass "reconcile-repo.sh reaps empty stale worktrees, parks commit-bearing ones, preserves live-claim in-flight (3ac8)"
