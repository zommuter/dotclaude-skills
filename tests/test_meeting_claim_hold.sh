#!/usr/bin/env bash
# roadmap:d748 — /meeting holds its shared-ledger WRITE-BACK behind the relay claim while a
# pool is live (cluster step 6); read/think + the meeting note are never blocked. Static
# checks on the meeting SKILL contract.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MD="$SRC_DIR/meeting/SKILL.md"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$MD" ]] || fail "meeting/SKILL.md not found"

# (1) A claim-hold step exists, gating the ledger write-back, keyed to id:d748.
grep -q "Relay-pool claim hold (id:d748" "$MD" || fail "meeting SKILL has no relay-pool claim-hold step (id:d748)"
pass "claim-hold step present (id:d748)"

# (2) It acquires + releases the repo claim with a meeting-scoped run id and --mode meeting.
grep -q "claim.sh acquire <root-basename> --run meeting-" "$MD" || fail "claim-hold does not acquire the repo claim (meeting-scoped run id)"
grep -q -- "--mode meeting" "$MD" || fail "claim-hold does not use --mode meeting"
grep -q "claim.sh release <root-basename> --run meeting-" "$MD" || fail "claim-hold does not release the claim after the write-back"
pass "acquires + releases the repo claim (meeting-scoped, --mode meeting)"

# (3) Only the WRITE-BACK is gated — read/think + the note are never blocked.
grep -qi "NEVER blocked" "$MD" || fail "claim-hold does not state read/think is never blocked"
grep -qi "only this shared-ledger WRITE-BACK is gated" "$MD" || fail "claim-hold does not scope the gate to the write-back"
pass "read/think + meeting note never blocked — only the ledger write-back"

# (4) On refusal it DEFERS (does not force a write under a live pool claim).
grep -q "DEFER" "$MD" || fail "claim-hold does not DEFER on refusal"
grep -qi "Never force a shared-ledger write under a live pool claim" "$MD" || fail "claim-hold does not forbid forcing the write under a live claim"
pass "defers the write-back when the pool holds the claim (never forces)"

# (5) Relay-managed repos only (skip when no ROADMAP.md).
grep -q "Skip entirely in non-relay repos (no ROADMAP.md" "$MD" || fail "claim-hold not scoped to relay-managed repos"
pass "scoped to relay-managed repos (ROADMAP.md present)"

echo "ALL PASS: /meeting holds ledger write-back behind the relay claim (id:d748)"
