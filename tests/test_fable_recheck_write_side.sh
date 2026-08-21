#!/usr/bin/env bash
# roadmap:6856 — relay-loop.js write side of the durable Fable-recheck queue (id:e030):
# a strong checkpoint produced by REAL Fable must mark the recheck consumed for ANY
# strong verdict (handoff/review/hard), not only review — the current conjunct
#   isFableRecheck = SESSION_IS_FABLE && unit.verdict === 'review'
# makes a Fable-produced HANDOFF record fable_rechecked = false, queuing a pointless
# Fable-rechecks-Fable review unit on the next pool round (observed: dotclaude-skills
# run relay-20260701-234115 — empty window, strong_model already claude-fable-5).
# Additionally the elevation reason hardcodes "Opus stood in for Fable" regardless of
# the recorded strong_model, so the dispatch reason was factually wrong.
#
# Sibling of id:a42e (classify-repo.sh read-side standin gate); this is the WRITE side.
# Static-grep structure test (house idiom: test_fable_standin_marker.sh).
# RED until the write-side fix lands.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JS="$ROOT/relay/scripts/relay-loop.js"

pass=0; fail=0
ok() { echo "  PASS: $1"; pass=$((pass+1)); }
fail_msg() { echo "  FAIL: $1"; fail=$((fail+1)); }

[[ -f "$JS" ]] || { echo "FAIL: relay-loop.js not found"; exit 1; }

echo "Test 1: isFableRecheck covers ANY strong unit (no verdict === 'review' conjunct)"
line="$(grep -n 'isFableRecheck *=' "$JS" | head -1)"
if [[ -z "$line" ]]; then
  fail_msg "isFableRecheck assignment not found (renamed? update this spec)"
elif grep -q "verdict === 'review'" < <(grep 'isFableRecheck *=' "$JS") ; then
  fail_msg "isFableRecheck still conjoined with verdict === 'review' — a Fable HANDOFF queues a bogus self-recheck: $line"
else
  ok "isFableRecheck no longer restricted to review units"
fi

echo "Test 2: recheck-elevation reason does not hardcode 'Opus stood in for Fable'"
if grep -q 'Opus stood in for Fable' "$JS"; then
  fail_msg "hardcoded 'Opus stood in for Fable' reason survives — wrong when strong_model is a Fable model (derive wording from the recorded strong_model / neutral phrasing)"
else
  ok "no hardcoded Opus-standin reason literal"
fi

# id:087b RELOCATION — the two id:e030 branches used to be prose inside relay-loop.js's LLM
# integrator prompt; they are now EXECUTED CODE in relay/scripts/integrate.sh step 10b, which
# relay-loop.js dispatches as one mechanical hop. Same two invariants, new home — and the
# `isFableRecheck` decision (Test 1) still lives in relay-loop.js, which passes it through as
# --fable-recheck, so both files are checked below.
INTEG="$ROOT/relay/scripts/integrate.sh"
[[ -f "$INTEG" ]] || { echo "FAIL: integrate.sh not found"; exit 1; }

echo "Test 3 (regression guard): consume side still writes a dated watermark"
if grep -q 'do NOT set false' "$INTEG"; then
  ok "the --fable-recheck branch still writes a dated fable_rechecked (consume side intact)"
else
  fail_msg "consume-side 'do NOT set false' instruction lost (id:e030 consume semantics)"
fi

echo "Test 4 (regression guard): the standin (non-Fable strong) branch still queues false"
if grep -q 'fable_rechecked = false' "$INTEG"; then
  ok "non-Fable strong checkpoint still records fable_rechecked = false (queue side intact)"
else
  fail_msg "queue-side 'fable_rechecked = false' instruction lost (id:e030 queue semantics)"
fi

echo "Test 5 (id:087b): relay-loop.js passes the isFableRecheck decision through to integrate.sh"
if grep -q "push('--fable-recheck')" "$JS"; then
  ok "relay-loop.js forwards --fable-recheck to the mechanical integrator"
else
  fail_msg "relay-loop.js computes isFableRecheck but never forwards it — the consume side can never fire"
fi

echo "Test 6 (id:e030 masking bug): an EXECUTE checkpoint must not touch the three keys"
if grep -q 'verdict" != "execute"' "$INTEG"; then
  ok "integrate.sh gates the durable-queue write on a non-execute (STRONG) verdict"
else
  fail_msg "integrate.sh does not gate the durable-queue write on a STRONG verdict — an executor checkpoint could clear a pending Fable recheck (id:e030)"
fi

echo ""
echo "Results: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
