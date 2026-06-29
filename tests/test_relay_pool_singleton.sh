#!/usr/bin/env bash
# TODO id:11c6 — relay front-door autonomous-pool singleton guard.
# NOT a ROADMAP item (TODO-id feature) — no `# roadmap:` header, so failures always count.
# Before launching the bare no-arg autonomous pool, the front door acquires a
# `pool:autonomous` claim via the EXISTING claim.sh (compose, no new machinery); a 2nd
# autonomous pool is refused and the holder named (peek). Directed/scoped/--afk runs EXEMPT.
# Source: docs/meeting-notes/2026-06-18-1829-insights-findings-triage.md (item 2, a1).
#
# Two parts: (A) static contract on relay/SKILL.md; (B) behavioral check that claim.sh
# actually enforces the pool:autonomous singleton (hermetic, CLAIM_BASE override).
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$SRC_DIR/relay/SKILL.md"
CLAIM="$SRC_DIR/relay/scripts/claim.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$SKILL" ]] || fail "relay/SKILL.md not found"
[[ -x "$CLAIM" ]] || fail "claim.sh not found/executable"

# ── Part A: static contract on the front-door guard ───────────────────────────
grep -q "Autonomous-pool singleton guard (id:11c6" "$SKILL" \
  || fail "id:11c6: SKILL.md has no autonomous-pool singleton guard step"
pass "id:11c6: singleton-guard step present in the front door"

# Composes the EXISTING claim.sh with a pool:autonomous key (no new machinery).
grep -q "claim.sh acquire pool:autonomous" "$SKILL" \
  || fail "id:11c6: guard does not acquire the pool:autonomous claim via claim.sh"
grep -q "claim.sh release pool:autonomous" "$SKILL" \
  || fail "id:11c6: guard does not release the pool:autonomous claim"
pass "id:11c6: guard composes claim.sh (acquire+release pool:autonomous)"

# On refusal: do NOT launch a duplicate, and name the holder via peek.
grep -qi "not launching a duplicate" "$SKILL" \
  || fail "id:11c6: guard does not refuse a 2nd autonomous pool"
grep -q "claim.sh peek" "$SKILL" \
  || fail "id:11c6: guard does not peek to name the holder"
pass "id:11c6: 2nd autonomous pool refused; holder named via peek"

# EXEMPT: directed/scoped/--afk runs are never guarded (legitimate multi-clauding).
grep -qi "EXEMPT" "$SKILL" || fail "id:11c6: guard does not mark directed/scoped/--afk EXEMPT"
grep -q -- "--afk" "$SKILL" || fail "id:11c6: --afk not named as an exempt run"
grep -qi "directed" "$SKILL" || fail "id:11c6: directed runs not named as exempt"
grep -qi "scoped" "$SKILL" || fail "id:11c6: scoped runs not named as exempt"
pass "id:11c6: directed/scoped/--afk runs are EXEMPT (no false-positive on multi-clauding)"

# ── Part B: behavioral — claim.sh enforces the singleton (hermetic) ───────────
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export CLAIM_BASE="$tmp/relay"
export CLAIM_LOG="$tmp/claim.log"

# First autonomous pool acquires the singleton.
"$CLAIM" acquire pool:autonomous --run relay-pool-AAAA --mode autonomous >/dev/null \
  || fail "id:11c6: first pool:autonomous acquire should succeed"
pass "id:11c6: first autonomous pool acquires the singleton"

# peek names the holder.
"$CLAIM" peek | grep -q '"key":"pool:autonomous"' \
  || fail "id:11c6: peek does not surface the live pool:autonomous claim (holder name)"
"$CLAIM" peek | grep -q 'relay-pool-AAAA' \
  || fail "id:11c6: peek does not name the holder run id"
pass "id:11c6: peek names the live autonomous-pool holder"

# A SECOND autonomous pool (different run) is refused.
if "$CLAIM" acquire pool:autonomous --run relay-pool-BBBB --mode autonomous >/dev/null 2>&1; then
  fail "id:11c6: a 2nd concurrent autonomous pool was NOT refused (singleton violated)"
fi
pass "id:11c6: a 2nd concurrent autonomous pool is refused"

# After release, a new pool may acquire (fail-open / not wedged).
"$CLAIM" release pool:autonomous --run relay-pool-AAAA
"$CLAIM" acquire pool:autonomous --run relay-pool-CCCC --mode autonomous >/dev/null \
  || fail "id:11c6: after release a fresh autonomous pool should acquire (guard wedged)"
pass "id:11c6: after release the singleton is reclaimable (never wedged)"

echo "ALL PASS: relay front-door autonomous-pool singleton guard (id:11c6)"
