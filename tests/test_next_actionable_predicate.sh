#!/usr/bin/env bash
# roadmap:9014 — /relay next routes 1/2a must key on executor-ACTIONABLE open items,
# not bare open-checkbox counts: a ROADMAP whose only open boxes are @manual/human-lane
# (or 🚧/BLOCKED) is EFFECTIVELY DRAINED and must take the unpromoted-scan/handoff
# route, never read as "needs human / idle" (the truncocraft 35-item miss, 2026-06-30).
#
# The loop-classifier half already shipped and is behavior-locked
# (classify-repo.sh actionable_routine_open/roadmap_actionable_open;
# classify-verdict.sh execute/handoff gating; test_classify_verdict_humanlane.sh).
# This test is the WORDING DRIFT-GUARD for the /relay next doc predicate in
# relay/SKILL.md — weak by design (behavior is locked elsewhere), it only pins that
# the routes name the same predicate + authority instead of re-defining their own.
#
# RED until the SKILL.md route-1/2a rewording lands.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$ROOT/relay/SKILL.md"

pass=0; fail=0
ok() { echo "  PASS: $1"; pass=$((pass+1)); }
fail_msg() { echo "  FAIL: $1"; fail=$((fail+1)); }

[[ -f "$SKILL" ]] || { echo "FAIL: relay/SKILL.md not found"; exit 1; }

# Isolate the Next-mode section (## Next mode … until the next ## heading).
next_section="$(awk '/^## Next mode/{f=1} f && /^## /{if (c++) exit} f' "$SKILL")"
[[ -n "$next_section" ]] || { echo "FAIL: '## Next mode' section not found"; exit 1; }

echo "Test 1: route 1 keys on executor-ACTIONABLE [ROUTINE] items"
if grep -qi 'executor-actionable' <<<"$next_section"; then
  ok "next mode names executor-actionable"
else
  fail_msg "next mode never says 'executor-actionable' — routes still key on bare open counts"
fi

echo "Test 2: the drained predicate treats @manual/human-lane-only as effectively drained"
if grep -q '@manual' <<<"$next_section" && grep -qi 'effectively.drained' <<<"$next_section"; then
  ok "@manual/human-lane-only named as effectively drained"
else
  fail_msg "route 2a does not name the @manual/human-lane-only effectively-drained case (id:9014 gap)"
fi

echo "Test 3: the predicate authority is named (single-source, no prose re-definition)"
if grep -q 'actionable_routine_open' <<<"$next_section" || grep -q 'classify-repo.sh' <<<"$next_section"; then
  ok "authority (classify-repo.sh / actionable_routine_open) cited"
else
  fail_msg "routes re-define the predicate in prose without citing the classifier authority"
fi

echo "Test 4: anti-guess discipline retained (never auto-promote with a guessed lane)"
if grep -qi 'never auto-promote' <<<"$next_section"; then
  ok "anti-guess wording still present"
else
  fail_msg "the 'never auto-promote with a guessed lane' discipline was lost in the rewording"
fi

echo ""
echo "Results: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
