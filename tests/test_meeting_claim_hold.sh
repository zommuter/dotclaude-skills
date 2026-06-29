#!/usr/bin/env bash
# roadmap:d748 (UPDATED for TODO id:c144) — /meeting's shared-ledger WRITE-BACK is no longer
# DEFERRED behind the relay hard lease. Per meeting D2 (2026-06-17-0953) the hard lease guards
# CODE/WORKTREE integration only; a ledger-only write is safe under a live pool via flock +
# atomic commit (id:148b) + orphan-scan --cross-ledger. Step 2a now PEEKS-AND-WARNS, then
# PROCEEDS (id:c144), instead of acquiring the lease and deferring. Static checks on the SKILL.
#
# id:c144 is a TODO-id feature (not a ROADMAP item); the original d748 roadmap header is kept
# for provenance but the assertions track the c144 supersession.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MD="$SRC_DIR/meeting/SKILL.md"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$MD" ]] || fail "meeting/SKILL.md not found"

# (1) Step 2a is now the peek-and-warn step keyed to id:c144 (supersedes the d748 hold).
grep -q "Relay-pool peek-and-warn (id:c144" "$MD" \
  || fail "meeting SKILL step 2a is not the id:c144 peek-and-warn step"
pass "step 2a is the id:c144 peek-and-warn (supersedes the d748 DEFER hold)"

# (2) It states the hard lease guards code/worktree integration only — NOT ledger writes.
grep -qi "hard\` lease guards CODE/WORKTREE integration only" "$MD" \
  || fail "step 2a does not state the hard lease guards code/worktree integration only"
pass "step 2a narrows the hard lease to code/worktree integration (ledger writes exempt)"

# (3) It PEEKS (advisory) and PROCEEDS — it does NOT acquire-to-block and does NOT DEFER.
grep -q "claim.sh peek" "$MD" || fail "step 2a does not peek for a live pool holder"
grep -qi "peeks and warns, then proceeds\|peek and warn, then proceed\|peeks-and-warns" "$MD" \
  || fail "step 2a does not proceed after warning (it must not block/defer the ledger write)"
# The ledger write-back must NOT acquire the meeting lease as a blocking gate anymore.
if grep -q "Acquire: .*claim.sh acquire <root-basename> --run meeting-" "$MD"; then
  fail "step 2a still acquires the meeting lease as a blocking gate (c144 removes this for ledger writes)"
fi
pass "step 2a peeks-and-warns then proceeds (no blocking acquire/DEFER for the ledger write)"

# (4) Read/think + the meeting note remain never blocked.
grep -qi "NEVER blocked" "$MD" || fail "step 2a does not state read/think is never blocked"
pass "read/think + meeting note never blocked"

# (5) The 2b/2e writes commit atomically via md-merge --commit (id:148b scoop-window close).
grep -q -- "--commit" "$MD" || fail "step 2 ledger writes do not use md-merge --commit (id:148b)"
grep -q "id:148b" "$MD" || fail "step 2a/2b does not cite the atomic-commit scoop-window close (id:148b)"
pass "ledger writes commit atomically via md-merge --commit (id:148b)"

# (6) Relay-managed repos only (skip when no ROADMAP.md).
grep -q "Skip entirely in non-relay repos (no ROADMAP.md" "$MD" \
  || fail "step 2a not scoped to relay-managed repos"
pass "scoped to relay-managed repos (ROADMAP.md present)"

echo "ALL PASS: /meeting ledger write-back is peek-and-warn, not lease-deferred (id:c144)"
