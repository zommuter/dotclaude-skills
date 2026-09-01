#!/usr/bin/env bash
# id:a615 — the three OUTSIDE controls on a pool run (STOP sentinel, --once, --after N) must be
# DISPATCH-scoped, not round-scoped.
#
# No `# roadmap:` header on purpose: a615 is a TODO-ledger defect fix with no ROADMAP item, so
# per tests/README convention (see run-tests.sh EXPECTED-RED semantics) its failures always count.
#
# THE DEFECT (observed live 2026-08-22, run relay-20260822-154630-17003): the id:8123 chain-end
# classifier re-ask and the review->execute re-chain push follow-on units into the SAME round's
# queue without returning to discover-prelude, where the sentinel was read. That run made 14
# dispatches ALL stamped round=1, four of them after the operator's stop was already on disk —
# so a round-boundary check never fired, and `--once` / `--after N` (pure outer-loop ROUND caps)
# would have permitted every one of them. Only TaskStop bounded such a run.
#
# These are BEHAVIOURAL tests, not greps: tests/fixtures/dispatch-bound-harness.mjs EXECUTES
# relay-loop.js in a stubbed Workflow sandbox pinned to MAX_ROUNDS=1, with children that always
# report open [ROUTINE] work and a chain-end re-ask that always answers `review` — i.e. exactly
# the chaining shape above. Every dispatch it counts happened inside ONE round.
# fails-against: rev 3d5ade32bb8f -- the tree as it stood immediately before the commit that
#   added this test, i.e. the pre-fix relay/SKILL.md, relay/scripts/relay-loop.js, relay/scripts/stop-request.sh (+1 more). Derived + verified by tests/verify-negative-cases.py.
# fails-against-rev: 3d5ade32bb8f -- relay/SKILL.md relay/scripts/relay-loop.js relay/scripts/stop-request.sh relay/scripts/stop-sentinel.sh
# fails-against-assertion: unit(s); the discovered wave was 3, so the id:a615 wave dispatch budget did not bound the chain (a round cap alone would have allowed

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JS="$ROOT/relay/scripts/relay-loop.js"
HARNESS="$ROOT/tests/fixtures/dispatch-bound-harness.mjs"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

command -v node >/dev/null 2>&1 || { echo "SKIP: node not available"; exit 0; }
[[ -f "$JS" ]] || fail "relay-loop.js not found at $JS"
[[ -f "$HARNESS" ]] || fail "dispatch-bound harness not found at $HARNESS"
node --check "$JS" || fail "relay-loop.js fails node --check"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# run <mode> [K] -> writes the harness JSON to $TMP/out.json; echoes nothing.
run() {
  node "$HARNESS" "$JS" "$@" > "$TMP/out.json" 2> "$TMP/err.txt"
  return $?
}
field() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$TMP/out.json" "$1"; }

# ── (1) The defect shape is REAL and reproducible: one round, many dispatches ────────────────
# Without a bound, a single round chains far past its discovered wave (3 units). If this ever
# stops being true the rest of this file is testing nothing, so assert it first.
run unbounded || fail "harness threw in 'unbounded' mode:
$(cat "$TMP/err.txt")"
[[ "$(field preludeCalls)" == "1" ]] || fail "unbounded: expected exactly ONE round (one discover-prelude call), got $(field preludeCalls)"
UNBOUNDED_DISPATCHES="$(field dispatches)"
(( UNBOUNDED_DISPATCHES >= 14 )) \
  || fail "unbounded: a chaining round dispatched only $UNBOUNDED_DISPATCHES unit(s) — the harness no longer reproduces the >=14-dispatches-under-round-1 shape this item is about"
pass "chaining round reproduces the defect shape: $UNBOUNDED_DISPATCHES dispatches, all under ONE round (run relay-20260822-154630-17003 saw 14)"

# ── (2) --once BOUNDS THE SAME CHAINING ROUND to the wave discovery produced ─────────────────
# This is the whole point: --once used to be an outer-loop ROUND cap, and would have permitted
# every one of the $UNBOUNDED_DISPATCHES dispatches above. It must now mean "a bounded amount
# of work, once" = the 3 units discovery produced.
run once || fail "harness threw in 'once' mode:
$(cat "$TMP/err.txt")"
[[ "$(field preludeCalls)" == "1" ]] || fail "--once: expected exactly ONE round, got $(field preludeCalls)"
ONCE_DISPATCHES="$(field dispatches)"
[[ "$ONCE_DISPATCHES" == "3" ]] \
  || fail "--once dispatched $ONCE_DISPATCHES unit(s); the discovered wave was 3, so the id:a615 wave dispatch budget did not bound the chain (a round cap alone would have allowed $UNBOUNDED_DISPATCHES)"
pass "--once bounds a CHAINING round to its discovered wave: 3 dispatches, not $UNBOUNDED_DISPATCHES"

# ── (3) The STOP sentinel is CONSUMED MID-CHAIN and actually bounds the run ──────────────────
# The sentinel fires at the Kth dispatch-decision stop-check (K=2 and K=3), i.e. INSIDE the
# round, never at a round boundary the chain would never reach.
for K in 2 3; do
  run stop-at "$K" || fail "harness threw in 'stop-at $K' mode:
$(cat "$TMP/err.txt")"
  D="$(field dispatches)"
  (( D < UNBOUNDED_DISPATCHES )) \
    || fail "stop-at $K: $D dispatches — the mid-round STOP sentinel did not bound the chain (unbounded was $UNBOUNDED_DISPATCHES)"
  (( D > 0 )) || fail "stop-at $K: the stop must DRAIN what is in flight, not prevent the round from starting at all"
  pass "STOP sentinel consumed MID-CHAIN at stop-check #$K bounds the round to $D dispatches (unbounded: $UNBOUNDED_DISPATCHES)"
done

# ── (4) A FAILED / UNREADABLE sentinel read must NEVER wedge the pool (id:cd94 fail-safe) ────
# Two failure shapes: the mechanical hop THROWS, and it returns an unparseable body. Both must
# fail toward CONTINUING — same dispatch count as unbounded, no throw, no hang.
for MODE in stop-flaky stop-garbage; do
  run "$MODE" || fail "$MODE: the loop propagated a stop-check failure instead of continuing:
$(cat "$TMP/err.txt")"
  [[ "$(field threw)" == "" ]] || fail "$MODE: relay-loop.js threw — a flaky sentinel read must never wedge the pool: $(field threw)"
  [[ "$(field thunkThrew)" == "False" ]] || fail "$MODE: a dispatch lane threw on a failed stop check"
  D="$(field dispatches)"
  [[ "$D" == "$UNBOUNDED_DISPATCHES" ]] \
    || fail "$MODE: $D dispatches vs $UNBOUNDED_DISPATCHES unbounded — a failed sentinel read must fail toward CONTINUING (never toward a stop and never toward a hang)"
  pass "$MODE: failed sentinel read fails toward continuing ($D dispatches, no throw) — id:cd94 property preserved"
done

# ── (5) Stopping TWICE is harmless (idempotent) ──────────────────────────────────────────────
# The sentinel reports true on every check. The run must stop cleanly exactly once — no throw,
# no repeated consume storm, and the in-flight wave still drains.
run stop-twice || fail "harness threw in 'stop-twice' mode:
$(cat "$TMP/err.txt")"
[[ "$(field threw)" == "" ]] || fail "stop-twice: relay-loop.js threw — a repeated stop must be a no-op"
D="$(field dispatches)"
(( D > 0 && D < UNBOUNDED_DISPATCHES )) \
  || fail "stop-twice: $D dispatches — a repeated stop must still drain the wave and still bound the chain"
CHECKS="$(field stopChecks)"
(( CHECKS <= 3 )) \
  || fail "stop-twice: $CHECKS stop-checks — once the stop has fired the gate must short-circuit, not re-consume in a loop"
pass "stopping twice is harmless: clean stop after $D dispatch(es), $CHECKS stop-check(s), no throw"

# ── (6) Wiring, not just built: the gate is REFERENCED from the dispatch paths ───────────────
# "built + tested + green" is not "wired" in this file (id:5367/2062). Assert the call sites.
grep -q "dispatchGateBlock('lane')" "$JS" || fail "the lane dispatch loop does not call dispatchGateBlock('lane') — the bound is unwired"
grep -q "dispatchGateBlock('intensive')" "$JS" || fail "the [INTENSIVE] serial phase does not call dispatchGateBlock('intensive') — the operator stop cannot reach it"
grep -q "stop-sentinel.sh check" "$JS" || fail "relay-loop.js never invokes stop-sentinel.sh — the per-dispatch check must reuse the ONE sentinel actor, not reimplement it"
pass "dispatchGateBlock is wired into BOTH dispatch paths and reuses stop-sentinel.sh"

echo "ALL PASS: id:a615 dispatch-scoped bound — sentinel consumed mid-chain, --once bounds a chaining round, fail-safe preserved"
