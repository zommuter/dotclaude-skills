#!/usr/bin/env bash
# roadmap:8123
# RED SPEC for id:8123 — chain-end classifier RE-ASK replaces the chainDepth===K forced-review
# trigger, and the two false-premise sites are corrected.
#
# The starvation is STRUCTURAL and TOTAL, not contention: classify-verdict.sh's cascade is a
# strict elif chain — `actionable_routine > 0` -> execute (rank 1), only `elif
# substantive_unaudited` -> review (rank 2). So `review` is UNREACHABLE while a single
# actionable [ROUTINE] item is open. There is no aging term and no forced-review path.
#
# TWO CONTRACTS, and they pull against each other on purpose (meeting A1's recorded ambiguity):
#   (A) a chain ending BELOW K — mid-chain handback, contract_met:false, quota-stop — must
#       still yield a review; and
#   (B) `review` must NOT become UNCONDITIONALLY reachable, which would restore the 1:1
#       apex-review-per-execute cost the meeting explicitly rejected.
# A fix satisfying only (A) is the failure mode this file exists to catch. The intended shape
# is a "chain ended" FACT in the state JSON, under which review outranks execute — the
# classifier stays the sole verdict authority.
#
# Assertions 1-3 are REAL behavioural fixtures against classify-verdict.sh (hermetic, no git,
# no network). Assertions 4-6 are source-shape over relay-loop.js, which cannot be run
# hermetically (Workflow sandbox, no API) — same honest limitation as
# tests/test_rechain_depth_cc90.sh.
#
# NOTE for the implementer: `chainDepth` does NOT exist in this repo today (verified
# 2026-07-31 — `grep -rn chainDepth relay/` is empty). Today's mechanism is the BOOLEAN
# `unit.rechained` at relay-loop.js:2445. `chainDepth` is id:cc90's own unshipped deliverable;
# the meeting note's "chainDepth === 1 today" phrasing is loose. That strengthens the
# conclusion (executes cannot chain at all) but do not code against a counter that is absent.
#
# TRIANGULATION (id:108e): six assertions over four concerns (reachability-under-fact,
# non-reachability-without-fact, classifier purity, false-premise correction), three of them
# behavioural with DISTINCT chain-end causes.
#
# RED until the cascade takes a chain-end fact. roadmap:8123 unticked => EXPECTED-RED.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CV="$ROOT/relay/scripts/classify-verdict.sh"
JS="$ROOT/relay/scripts/relay-loop.js"
[[ -x "$CV" ]] || { echo "FAIL: classify-verdict.sh not found/executable at $CV"; exit 1; }
[[ -f "$JS" ]] || { echo "FAIL: relay-loop.js not found at $JS"; exit 1; }

fail() { echo "FAIL: $*"; exit 1; }
pass() { echo "PASS: $*"; }

verdict_of() { bash "$CV" | python3 -c 'import json,sys; print(json.load(sys.stdin)["verdict"])'; }

# A repo with open [ROUTINE] work AND unaudited commits — i.e. the state every chain leaves
# behind. Only the chain-end fact differs between the three fixtures below.
state() {
  # $1 = the chain-end fact fragment (may be empty)
  printf '{"hasRoutine":true,"actionable_routine_open":18,"substantive_unaudited":true,"open_hard_pool":0,"dirty":false,"diverged":false%s}' "$1"
}

# 1-3. Contract (A): a chain ending BELOW K, by three DISTINCT causes, still yields a review.
#      The field name is the implementer's to choose; this spec accepts any of the obvious
#      spellings so it constrains BEHAVIOUR, not vocabulary.
try_chain_end() {
  local reason="$1" v
  for key in chain_ended chainEnded chain_end chain_end_reason; do
    case "$key" in
      chain_end_reason) frag=",\"$key\":\"$reason\"" ;;
      *)                frag=",\"$key\":true,\"chain_end_reason\":\"$reason\"" ;;
    esac
    v="$(state "$frag" | verdict_of)"
    [[ "$v" == "review" ]] && { echo "$key"; return 0; }
  done
  return 1
}

for cause in handback contract-not-met quota-stop; do
  if key="$(try_chain_end "$cause")"; then
    pass "(chain-end/$cause) a chain ending below K yields review (via '$key')"
  else
    fail "($cause) a chain ending below K with 18 open [ROUTINE] items still classifies as 'execute' — the chain-end fact does not make review reachable, so unaudited work accumulates exactly as it did for the 16-checkpoint incident (id:8123 contract A)"
  fi
done

# 4. Contract (B): WITHOUT a chain-end fact the cascade is byte-equivalent to today's —
#    review must NOT be unconditionally reachable, or every cheap Sonnet execute buys an
#    apex review (the 1:1 cost the meeting rejected).
v_plain="$(state "" | verdict_of)"
[[ "$v_plain" == "execute" ]] \
  || fail "(B) with NO chain-end fact, an 18-item repo classifies as '$v_plain' instead of 'execute' — review became unconditionally reachable, restoring the 1:1 apex-per-execute cost the meeting rejected (id:8123 contract B)"
pass "(B) review is not unconditionally reachable — plain state still classifies execute"

# 5. The classifier stays the sole verdict authority and stays PURE: the loop supplies the
#    FACT, it must not emit a review unit directly, bypassing classify-verdict.sh.
grep -Eq 'SIDE-EFFECT-FREE' "$CV" \
  || fail "(5) classify-verdict.sh lost its SIDE-EFFECT-FREE contract line — the re-ask must not make the classifier impure (id:8123)"
grep -Eqi 'chain.?end' "$JS" \
  || fail "(5) relay-loop.js never mentions a chain end — the loop must supply the chain-ended FACT to the classifier (id:8123)"
pass "(5) classifier stays pure and the loop supplies the chain-end fact"

# 6. Both FALSE-PREMISE sites are corrected in the same change. The relay-loop.js comment
#    "the execute's own commits are reviewed next pool" (:2441) is untrue — a single
#    execute's commits are never reviewed today — and must not survive verbatim.
if grep -q "own commits are reviewed next pool" "$JS"; then
  fail "(6) relay-loop.js still asserts \"the execute's own commits are reviewed next pool\" — that premise is FALSE and the meeting required it corrected in the same change (id:8123)"
fi
pass "(6) the relay-loop.js false-premise comment is corrected"

# 7. The engine still parses and lints clean.
node --check "$JS" >/dev/null 2>&1 || fail "(7) node --check failed on relay-loop.js after the 8123 edit"
LINT="$ROOT/relay/scripts/lint-workflow-templates.mjs"
[[ -f "$LINT" ]] || fail "(7) lint-workflow-templates.mjs not found; cannot verify template safety"
if ! out="$(node "$LINT" "$JS" 2>&1)"; then
  fail "(7) relay-loop.js has a template-literal violation after the 8123 edit:
$out"
fi
pass "(7) relay-loop.js parses and lints clean"

echo "PASS test_chain_end_reask_8123"
