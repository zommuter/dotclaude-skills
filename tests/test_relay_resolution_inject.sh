#!/usr/bin/env bash
# roadmap:fb75 — when an interactive resolver (/relay human §5, and the /meeting REVIEW_ME
# write-back, id:15d5) ticks a box that UNBLOCKS pool work, it pushes that now-unblocked
# item to the running pool via `inject.sh add <repo> --item <id>` (reusing id:baf1) so the
# pool prioritizes it at its NEXT round instead of waiting for normal re-discovery.
# Latency lever, push-not-watch: the resolver knows exactly what it unblocked.
# Static checks on human.md (the resolver contract) — RED until the contract is added.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HUMAN="$SRC_DIR/relay/references/human.md"
INJECT="$SRC_DIR/relay/scripts/inject.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$HUMAN" ]] || fail "relay/references/human.md not found"
[[ -x "$INJECT" ]] || fail "relay/scripts/inject.sh not found/executable (id:baf1 prerequisite)"

# (1) The resolver write-back path references inject.sh as the low-latency hand-off.
grep -q "inject.sh add" "$HUMAN" \
  || fail "human.md write-back does not call 'inject.sh add' to push unblocked work to the pool"

# (2) It is explicitly conditioned on the resolution UNBLOCKING pool work (not every tick) —
#     a blind inject on every box toggle would churn discovery; the trigger is "unblocks".
grep -qi "unblock" "$HUMAN" \
  || fail "human.md does not condition the inject on the resolution UNBLOCKING work"

# (3) The injected unit carries the specific item id (--item), so the pool works exactly the
#     unblocked ROADMAP item, not a blind re-classification of the repo.
grep -Eq "inject.sh add[^\n]*--item" "$HUMAN" \
  || fail "human.md inject call does not pass --item <id> (must target the unblocked item)"

# (4) It is tied to the same single-id-two-views id reuse (no fresh token minted for the
#     already-tracked unblocked item).
grep -qi "same id\|reuse.*id\|single-id" "$HUMAN" \
  || fail "human.md does not state the injected item REUSES the existing id (no duplicate mint)"

pass "resolution->inject.sh add pushes the unblocked item to the pool, conditioned on unblock, --item-scoped, id-reusing (fb75)"
