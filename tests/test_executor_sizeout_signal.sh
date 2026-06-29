#!/usr/bin/env bash
# roadmap:08c0 — structured executor size-out signal.
#
# GAP (observed truncocraft, relay-ckpt-20260629-1325 — routed:9a50): when a cheap
# executor sizes out a [ROUTINE] item as too-large-to-land-green it currently only has
# the SOFT notes (`friction:` commit line / `BLOCKED:` RELAY_LOG line). The integrator's
# durable handback follow-up (handback-followup.py, id:3801) reads ONLY the STRUCTURED
# return fields (contract_met / handback_item / route / proposed_split) — it never parses
# the soft notes — so the sized-out item stays a plain open [ROUTINE] and the next
# discovery round re-dispatches the same un-doable item to another executor.
#
# The integrator GATE already works: handback-followup.py re-tags a [ROUTINE] parent to
# the classifier-excluded [HARD — decision gate] (proven by test_handback_followup.sh),
# and relay-loop.js calls it for ANY handback regardless of verdict. The missing half is
# UPSTREAM: the executor must be TOLD to EMIT the structured size-out handback for a
# [ROUTINE] item. This test pins that contract change.
#
# NOTE: a new [ROUTINE — oversized] tag is the WRONG fix — the classifier's dispatch
# matcher (`^- \[ \].*\[ROUTINE\]`) and the HARD-lane exclude filter would BOTH still let
# it through, so the spin would continue. The contract must reuse the existing gate.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACT="$ROOT/relay/references/executor-contract.md"
LOOP="$ROOT/relay/scripts/relay-loop.js"

fail=0
ok()  { echo "  ok  $1"; }
bad() { echo "  FAIL $1"; fail=1; }

echo "== executor-contract.md documents the structured size-out signal =="
# The contract names a size-out / oversized rule for [ROUTINE] items.
if grep -qiE 'size[ -]?out|too large to land|oversized' "$CONTRACT"; then
  ok "size-out rule present"
else
  bad "no size-out / oversized rule in executor-contract.md"
fi
# It must require the STRUCTURED handback (contract_met=false), not just the soft notes.
if grep -qiE 'contract_met[ =]*false' "$CONTRACT"; then
  ok "requires contract_met=false (structured handback)"
else
  bad "size-out rule does not require contract_met=false"
fi
# It must name the structured fields the integrator actually reads.
if grep -qF 'handback_item' "$CONTRACT" && grep -qiE 'hard-split|decision-gate' "$CONTRACT"; then
  ok "names handback_item + route (hard-split/decision-gate)"
else
  bad "size-out rule does not name handback_item + route"
fi
# It must state WHY the soft notes are insufficient (the re-dispatch spin it prevents).
if grep -qiE 'soft note|friction.*not (enough|sufficient)|not sufficient|re-?dispatch' "$CONTRACT"; then
  ok "explains soft notes insufficient / re-dispatch spin"
else
  bad "size-out rule does not explain why soft notes are insufficient"
fi
# It must point at the durable gate (id:3801) so the executor trusts the integrator gates it.
if grep -qF 'id:3801' "$CONTRACT"; then
  ok "points at the durable handback gate (id:3801)"
else
  bad "size-out rule does not reference the id:3801 gate"
fi

echo "== contract version bumped past v5 (in-flight executors must learn the new obligation) =="
ver="$(grep -oE 'relay-executor contract v[0-9]+' "$CONTRACT" | grep -oE 'v[0-9]+' | head -1 | tr -d v)"
if [ -n "$ver" ] && [ "$ver" -ge 6 ] 2>/dev/null; then
  ok "contract version v$ver (>= v6)"
else
  bad "contract version not bumped (got v${ver:-?}, need >= v6)"
fi

echo "== relay-loop.js EXECUTE-verdict prompt covers ROUTINE size-out =="
# The size-out discipline today lives ONLY in the 'hard'-verdict prompt; the
# 'execute'-verdict prompt (the line matching `unit.verdict === 'execute' ?`) just says
# "never start an item you cannot finish" with no size-out → structured-handback wiring.
# Assert the EXECUTE-verdict segment itself references the size-out handback, so a Sonnet
# executor hands back instead of committing a no-op checkpoint that leaves the [ROUTINE]
# re-dispatchable. (Scope to that segment — grepping the whole file would match the
# 'hard'-verdict prompt and pass trivially.)
exec_seg="$(grep -nE "unit\.verdict === 'execute' \?" "$LOOP" | grep -i routine | head -1)"
if [ -n "$exec_seg" ] && grep -qiE 'size[ -]?out|too large to land|hand ?back' <<<"$exec_seg"; then
  ok "execute-verdict prompt wires ROUTINE size-out → handback"
else
  bad "relay-loop.js execute-verdict prompt does not cover ROUTINE size-out → handback"
fi

[ "$fail" = 0 ] && echo "PASS" || echo "FAILED"
exit "$fail"
