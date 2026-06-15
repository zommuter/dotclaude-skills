#!/usr/bin/env bash
# roadmap:bc9d — relay-loop.js integrator: per-repo serialization, cross-repo concurrency.
# The single global integrationChain made every repo's ~1-2 min Sonnet integrate agent wait
# behind every other's, so checkpoints landed ~1-2 min apart no matter how wide the dispatch
# (the pool LOOKED 1-wide though work agents ran concurrently). This pins the fix: integration
# serializes PER REPO (preserving review->execute ordering into one main checkout) but runs
# concurrently across DISTINCT repos (distinct remotes don't conflict; git-lock-push.sh still
# flocks per-repo). Static checks only — live integration throughput is the id:1ad7 pilot.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JS="$SRC_DIR/relay/scripts/relay-loop.js"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$JS" ]] || fail "relay-loop.js not found at $JS"

# (1) No single global integrationChain serializing ALL repos (the bottleneck).
if grep -qE "^(let|const|var) +integrationChain *=" "$JS"; then
  fail "single global integrationChain still present — should be a per-repo map (integrationChains)"
fi
pass "no single global integrationChain"

# (2) Per-repo chain map exists and enqueueIntegration is keyed by repo.
grep -q "integrationChains" "$JS" || fail "missing per-repo chain map integrationChains"
grep -qE "function enqueueIntegration\( *repo *," "$JS" || fail "enqueueIntegration not keyed by repo"
grep -qE "enqueueIntegration\(unit\.repo," "$JS" || fail "call site does not pass unit.repo as the chain key"
pass "enqueueIntegration is per-repo (keyed by unit.repo)"

# (3) The map keys by repo so distinct repos get independent chains (concurrent).
grep -qE "integrationChains\.get\( *repo *\)" "$JS" || fail "per-repo chain not looked up by repo key"
grep -qE "integrationChains\.set\( *repo *," "$JS" || fail "per-repo chain not stored by repo key"
pass "distinct repos get independent integration chains"

# (4) Graceful drain awaits ALL per-repo chains before the round returns.
grep -qE "Promise\.all\(\[\.\.\.integrationChains\.values\(\)\]\)" "$JS" \
  || fail "drain does not await all per-repo integration chains"
pass "drain awaits all per-repo chains"

# (5) Still NOT a bare parallel() over the integration step (same-repo must serialize).
if grep -E "parallel\(.*[Ii]ntegrat" "$JS" | grep -qv "^\s*//"; then
  fail "integration wrapped in parallel() — same-repo ordering would race"
fi
pass "integration not wrapped in parallel() (same-repo stays ordered)"

echo "ALL PASS: per-repo integrator (id:bc9d)"
