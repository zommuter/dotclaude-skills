#!/usr/bin/env bash
# roadmap:ebfb — relay-loop.js wires the claim registry into the dispatch path (cluster
# step 4): work children ACQUIRE the cross-session repo lease before working, the
# integrator RELEASES it (run-scoped), and RELAY_STATUS projects live claims via peek.
# Static checks (live dispatch is the id:1ad7 pilot).

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JS="$SRC_DIR/relay/scripts/relay-loop.js"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$JS" ]] || fail "relay-loop.js not found"
command -v node >/dev/null && { node --check "$JS" || fail "relay-loop.js is not valid JS"; }

# (1) Work child acquires the lease FIRST, keyed by repo + runId, and stops on refusal.
grep -q 'claim.sh acquire ${unit.repo} --run ${state.runId}' "$JS" \
  || fail "unitPrompt does not acquire the repo lease (claim.sh acquire <repo> --run <runId>)"
grep -qi "claimed by another relay run" "$JS" \
  || fail "unitPrompt does not stop+handback when the lease is held by another run"
pass "work child acquires the cross-session lease first (id:ebfb)"

# (2) Integrator releases the lease, run-scoped (safe for claimed-elsewhere handbacks).
grep -q 'claim.sh release ${unit.repo} --run ${state.runId}' "$JS" \
  || fail "integrator does not release the lease run-scoped (claim.sh release <repo> --run <runId>)"
pass "integrator releases the lease run-scoped (id:ebfb)"

# (3) RELAY_STATUS projects live claims via peek.
grep -q "claim.sh peek" "$JS" || fail "writeRelayStatus does not project live claims via claim.sh peek"
grep -q "Claims (live)" "$JS" || fail "RELAY_STATUS has no '## Claims (live)' projection section"
pass "RELAY_STATUS projects live claims via peek (id:ebfb)"

# (4) Flock'd single-writer for shared state (id:ebfb step 2): integrator writes relay.toml
# via relay-state-write.sh toml-set; writeRelayStatus writes RELAY_STATUS via status-write.
grep -q "relay-state-write.sh toml-set" "$JS" || fail "integrator does not write relay.toml via the flock'd toml-set helper"
grep -q "relay-state-write.sh status-write" "$JS" || fail "writeRelayStatus does not write via the flock'd status-write helper"
pass "shared state written via the flock'd single-writer (id:ebfb step 2)"

# (5) Skipped rollup (id:be62): discovery reports skipped; RELAY_STATUS has the section.
grep -q "## Skipped (this round)" "$JS" || fail "RELAY_STATUS missing the '## Skipped (this round)' rollup (id:be62)"
grep -qi "excluded-by-config" "$JS" || fail "discovery does not categorize excluded-by-config repos (id:be62)"
pass "skipped-repos rollup present (id:be62)"

echo "ALL PASS: claim wired into dispatch + single-writer + skipped rollup (id:ebfb/be62)"
