#!/usr/bin/env bash
# roadmap:0902 — the INTERACTIVE relay orchestrator modes (/relay handoff, /relay review,
# /relay human) acquire/respect the cross-session claim lease, closing the last gap the
# autonomous pool (id:ebfb) + executor (v4) + /meeting (id:d748) had already covered.
# Static checks on the SKILL orchestrator invariants + human.md.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$SRC_DIR/relay/SKILL.md"
HUMAN="$SRC_DIR/relay/references/human.md"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$SKILL" ]] || fail "relay/SKILL.md not found"
[[ -f "$HUMAN" ]] || fail "relay/references/human.md not found"

# (1) Orchestrator invariant: acquire the lease BEFORE spawning each handoff/review child,
#     skip the repo on refusal.
grep -q "claim.sh acquire <repo> --run relay-" "$SKILL" || fail "SKILL orchestrator does not acquire the repo lease before spawning a child"
grep -qi "REFUSED" "$SKILL" || fail "SKILL orchestrator does not handle a refused lease"
grep -qi "never spawn a colliding child" "$SKILL" || fail "SKILL orchestrator does not skip a claimed repo"
pass "handoff/review acquire the lease before fan-out, skip on refusal (id:0902)"

# (2) Orchestrator invariant: release the lease run-scoped at integration.
grep -q "claim.sh release <repo> --run relay-" "$SKILL" || fail "SKILL orchestrator does not release the lease at integration"
pass "handoff/review release the lease run-scoped at integration (id:0902)"

# (3) human mode: acquire the lease before per-repo write-back, DEFER on refusal, release.
grep -q "claim.sh acquire <repo> --run human-" "$HUMAN" || fail "human mode does not acquire the repo lease before write-back"
grep -q "DEFER" "$HUMAN" || fail "human mode does not DEFER write-back when the repo is claimed"
grep -q "claim.sh release <repo> --run human-" "$HUMAN" || fail "human mode does not release the lease after write-back"
pass "human mode holds the lease for its per-repo write-back, defers on refusal (id:0902)"

echo "ALL PASS: interactive relay modes are claim-aware (id:0902)"
