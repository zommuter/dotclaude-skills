#!/usr/bin/env bash
# TODO id:179e — Narrow `hard` lease scope + document the invariant.
# NOT a ROADMAP item (TODO-id feature) — no `# roadmap:` header, so failures always count.
# The hard lease guards code/worktree integration ONLY; ledger-only writes are protected by
# flock + atomic scoped commit + orphan-scan --cross-ledger, NOT the lease. The invariant is
# documented in claim.sh (mechanism SSOT) and the dispatch-safety reference doc.
# Static doc-contract check (mirrors the other static relay tests).
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CLAIM="$SRC_DIR/relay/scripts/claim.sh"
DOC="$SRC_DIR/relay/references/resource-claims.md"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$CLAIM" ]] || fail "claim.sh not found at $CLAIM"
[[ -f "$DOC" ]]   || fail "resource-claims.md not found at $DOC"

# (1) claim.sh header documents the scope invariant keyed to id:179e.
grep -q "SCOPE INVARIANT" "$CLAIM" || fail "claim.sh header missing the SCOPE INVARIANT block"
grep -q "id:179e" "$CLAIM" || fail "claim.sh scope invariant not tagged id:179e"
grep -qi "guards CODE/WORKTREE integration ONLY" "$CLAIM" \
  || fail "claim.sh does not state the hard lease guards code/worktree integration only"
grep -qi "LEDGER-ONLY writes" "$CLAIM" \
  || fail "claim.sh does not state ledger-only writes are exempt from the lease"
grep -q -- "--cross-ledger" "$CLAIM" \
  || fail "claim.sh does not cite the orphan-scan --cross-ledger backstop for ledger writes"
pass "id:179e: claim.sh header documents the hard-lease scope invariant (code/worktree only)"

# (2) The help output actually surfaces the invariant (the help sed range includes it).
help_out="$(bash "$CLAIM" --help)"
grep -qi "guards CODE/WORKTREE integration ONLY" <<<"$help_out" \
  || fail "claim.sh --help does not surface the scope invariant (sed range too narrow)"
pass "id:179e: claim.sh --help surfaces the scope invariant"

# (3) The dispatch-safety reference doc documents the same split with the three safety layers.
grep -q "id:179e" "$DOC" || fail "resource-claims.md does not document the id:179e invariant"
grep -qi "guards CODE/WORKTREE integration ONLY" "$DOC" \
  || fail "resource-claims.md does not state the hard lease guards code/worktree only"
for layer in "flock" "atomic scoped commit" "cross-ledger"; do
  grep -qi "$layer" "$DOC" || fail "resource-claims.md missing safety layer: $layer"
done
grep -q "id:148b" "$DOC" || fail "resource-claims.md does not cite id:148b (atomic commit)"
grep -q "id:debf" "$DOC" || fail "resource-claims.md does not cite id:debf (no git add -A)"
grep -q "id:c144" "$DOC" || fail "resource-claims.md does not cite id:c144 (lease exemption)"
pass "id:179e: resource-claims.md documents the split + the three ledger-write safety layers"

echo "ALL PASS: hard-lease scope narrowed + invariant documented (id:179e)"
