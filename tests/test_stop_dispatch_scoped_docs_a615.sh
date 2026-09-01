#!/usr/bin/env bash
# id:a615 — companion to test_dispatch_bound_a615.sh (the behavioural half).
#
# No `# roadmap:` header on purpose: a615 is a TODO-ledger defect fix with no ROADMAP item, so
# its failures always count.
#
# Two things this pins that the harness cannot:
#   (A) the REAL stop-sentinel.sh under the new call pattern — it is now invoked at the round
#       prelude AND at every subsequent dispatch decision, so its countdown unit is DISPATCH
#       DECISIONS. A repeated consume must stay harmless (id:cd94), and a failing/unreadable
#       read must leave the sentinel on disk so the stop RE-FIRES rather than being eaten.
#   (B) the DOCS. The item's own words: "Also fix the docs in the same change, or the next
#       operator trusts a graceful stop that cannot fire." relay/SKILL.md described --once as
#       "dispatch exactly ONE round" and Stop mode as draining "the already-dispatched wave" —
#       both true-but-misleading once a round can chain.
#
# Hermetic: mktemp sentinel + log paths, no ~/.config or ~/.claude touch, no network.
# fails-against: rev 3d5ade32bb8f -- the tree as it stood immediately before the commit that
#   added this test, i.e. the pre-fix relay/SKILL.md, relay/scripts/relay-loop.js, relay/scripts/stop-request.sh (+1 more). Derived + verified by tests/verify-negative-cases.py.
# fails-against-rev: 3d5ade32bb8f -- relay/SKILL.md relay/scripts/relay-loop.js relay/scripts/stop-request.sh relay/scripts/stop-sentinel.sh
# fails-against-assertion: relay/SKILL.md still describes Stop mode as draining 'the already-dispatched wave' — that assumes a wave boundary a chaining round does not have (id:a615)

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SENTINEL_SH="$ROOT/relay/scripts/stop-sentinel.sh"
STOP_REQUEST_SH="$ROOT/relay/scripts/stop-request.sh"
SKILL="$ROOT/relay/SKILL.md"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SENTINEL_SH" ]] || fail "relay/scripts/stop-sentinel.sh missing or not executable"
[[ -f "$SKILL" ]] || fail "relay/SKILL.md not found"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
STOPFILE="$TMP/STOP"
LOGFILE="$TMP/consume.log"
check() { RELAY_STOP_SENTINEL_LOG="$LOGFILE" "$SENTINEL_SH" check --path "$STOPFILE"; }

# ── (A1) STOPPING TWICE IS HARMLESS ──────────────────────────────────────────────────────────
# Two lanes can reach their dispatch decisions back-to-back after a stop was written. The second
# check must be a clean no-op: exit 0, stopRequested:false, no error, exactly ONE consume logged.
: > "$STOPFILE"
first="$(check)"; rc1=$?
second="$(check)"; rc2=$?
[[ $rc1 -eq 0 && $rc2 -eq 0 ]] || fail "a repeated stop check exited nonzero (rc1=$rc1 rc2=$rc2) — stopping twice must be harmless"
grep -q '"stopRequested":true' <<<"$first" || fail "first check after a written sentinel did not report a stop: $first"
grep -q '"stopRequested":false' <<<"$second" || fail "SECOND check re-reported a stop ($second) — the sentinel was not consumed, so a stop could fire twice"
consumes="$(grep -c 'consumed STOP sentinel' "$LOGFILE" 2>/dev/null || echo 0)"
[[ "$consumes" == "1" ]] || fail "expected exactly ONE logged consume across two checks, got $consumes"
pass "stopping twice is harmless: one consume, one log line, second check is a clean no-op"

# ── (A2) THE CONSUME STAYS LOGGED ────────────────────────────────────────────────────────────
grep -qE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}.*consumed STOP sentinel' "$LOGFILE" \
  || fail "the consume is not logged with a timestamp — id:cd94 requires the consume stay observable"
pass "the consume stays logged (timestamped line in the consume log)"

# ── (A3) THE COUNTDOWN IS PER CHECK, i.e. PER DISPATCH DECISION ──────────────────────────────
# `/relay stop --after 3` must now mean "three more dispatch decisions", not "three more rounds"
# (a round is unbounded in dispatches, which is the whole defect). Three successive dispatch-
# decision checks must walk 3->2->1 and the FOURTH must fire.
printf '3' > "$STOPFILE"
for expected in 2 1 0; do
  out="$(check)"
  grep -q '"stopRequested":false' <<<"$out" || fail "countdown fired early at remaining=$expected: $out"
  if [[ "$expected" != "0" ]]; then
    [[ "$(cat "$STOPFILE")" == "$expected" ]] || fail "countdown did not decrement to $expected (file holds '$(cat "$STOPFILE")')"
  fi
done
out="$(check)"
grep -q '"stopRequested":true' <<<"$out" || fail "countdown of 3 did not fire on the 4th dispatch-decision check: $out"
[[ ! -e "$STOPFILE" ]] || fail "a fired countdown left the sentinel on disk"
pass "--after N counts DISPATCH DECISIONS: 3 -> 2 -> 1 -> 0 -> fire, one tick per check"

# ── (A4) FAIL DIRECTION: an unreadable sentinel must SURVIVE, never be eaten ─────────────────
# id:cd94's ordering property (log+emit, remove LAST) is what makes a failed read re-fire at the
# NEXT dispatch decision instead of silently vanishing. Assert the removal is genuinely last.
awk '/^echo .\{"stopRequested":true\}./{seen=1} /^rm -- /{ if (seen) ok=1 } END{exit ok?0:1}' "$SENTINEL_SH" \
  || fail "stop-sentinel.sh no longer emits the decision BEFORE removing the file — a failure after the rm would eat the stop silently (id:cd94)"
pass "the sentinel removal is still the LAST act of a consume — a failed read leaves it to re-fire"

# ── (B1) SKILL.md no longer promises a round-boundary stop ──────────────────────────────────
grep -q 'already-dispatched wave' "$SKILL" \
  && fail "relay/SKILL.md still describes Stop mode as draining 'the already-dispatched wave' — that assumes a wave boundary a chaining round does not have (id:a615)"
grep -qi 'dispatch exactly ONE round' "$SKILL" \
  && fail "relay/SKILL.md still describes --once as 'dispatch exactly ONE round' — a round is unbounded in dispatches (id:a615)"
pass "the two misleading SKILL.md claims named by id:a615 are gone"

# ── (B2) SKILL.md states the corrected, dispatch-scoped semantics ────────────────────────────
grep -qi 'DISPATCH DECISION' "$SKILL" \
  || fail "relay/SKILL.md never says the sentinel is checked at every DISPATCH DECISION (id:a615)"
grep -qi 'dispatch decisions remaining before stop' "$SKILL" \
  || fail "relay/SKILL.md knobs table still describes the sentinel's content in ROUNDS, not dispatch decisions (id:a615)"
grep -qi 'DISPATCH-scoped, not round-scoped' "$SKILL" \
  || fail "relay/SKILL.md does not state that --once/--after are dispatch-scoped (id:a615)"
grep -q 'relay-20260822-154630-17003' "$SKILL" \
  || fail "relay/SKILL.md does not cite the observed run — the correction must carry its evidence so the next operator can check it (id:a615)"
pass "SKILL.md documents the dispatch-scoped sentinel + caps, with the observed run as evidence"

# ── (B3) stop-request.sh's own --after help no longer says 'rounds' ──────────────────────────
if [[ -f "$STOP_REQUEST_SH" ]]; then
  grep -qE '^#   --after N .*more rounds' "$STOP_REQUEST_SH" \
    && fail "stop-request.sh --after help still says 'N more rounds' — it counts dispatch decisions (id:a615)"
  grep -qi 'DISPATCH DECISIONS' "$STOP_REQUEST_SH" \
    || fail "stop-request.sh does not state that --after N counts dispatch decisions (id:a615)"
  pass "stop-request.sh's --after help states the dispatch-decision unit"
fi

echo "ALL PASS: id:a615 sentinel semantics under per-dispatch checking + the doc corrections"
