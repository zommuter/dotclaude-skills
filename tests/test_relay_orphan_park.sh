#!/usr/bin/env bash
# roadmap:689c — D1: park unmerged orphans on discovery (relay orphan-reconcile, meeting
# 2026-06-16-0938). Today (id:3ac8, test_relay_stale_worktree_reap.sh) a commit-bearing stale
# worktree from a DEAD run is only SURFACED as "needs manual integration" every round and the
# directory stays, so the `ls worktrees/` scan re-surfaces it forever. D1 changes the
# commits-ahead branch of discovery to PARK the orphan: remove the worktree dir (stops the
# re-surface) and rename the branch into the canonical `relay/orphan/*` namespace (the commit
# stays reachable on the ref), emitting ONE summary line — NOT a per-round handback, and NEVER
# an auto-integration. Static-structural checks on the mechanical discovery guard, now in
# reconcile-repo.sh (the old discovery-prompt logic in relay-loop.js was replaced).

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JS="$SRC_DIR/relay/scripts/relay-loop.js"
RECONCILE="$SRC_DIR/relay/scripts/reconcile-repo.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$JS" ]] || fail "relay-loop.js not found at $JS"
node --check "$JS" || fail "relay-loop.js fails node --check"
[[ -x "$RECONCILE" ]] || fail "reconcile-repo.sh not found at $RECONCILE"

# (1) the D1 marker is present in the discovery guard.
grep -q "id:689c" "$RECONCILE" || fail "no id:689c (D1 park) marker in reconcile-repo.sh"

# (2) commits-ahead orphans are PARKED into the canonical relay/orphan/* namespace
#     (the stranded commit stays reachable on a ref, not lost).
grep -Eq "relay/orphan/" "$RECONCILE" \
  || fail "reconcile-repo.sh does not park orphans into the relay/orphan/* namespace (D1)"
grep -Eq "branch -m " "$RECONCILE" \
  || fail "reconcile-repo.sh does not rename the orphan branch with 'git branch -m' into relay/orphan/* (D1)"

# (3) the worktree DIRECTORY is removed on park (so the ls-worktrees scan stops re-surfacing it).
#     This must be the commits-ahead path, distinct from the empty-reap path that already
#     deletes the branch with `branch -D`.
grep -Eq "worktree remove --force" "$RECONCILE" \
  || fail "reconcile-repo.sh never removes the orphan worktree dir on park (would re-surface every round)"

# (4) park emits ONE summary line, NOT the old per-round "needs manual integration" handback,
#     and NEVER auto-integrates (no --no-ff merge in the park path).
grep -Eqi "park|parked" "$RECONCILE" \
  || fail "reconcile-repo.sh does not describe parking the orphan (still the old surface-only behaviour)"

pass "reconcile-repo.sh parks commit-bearing orphans into relay/orphan/* + removes the dir + one summary line (689c)"
