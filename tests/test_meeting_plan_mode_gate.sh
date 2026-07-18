#!/usr/bin/env bash
# Specs TODO id:fc0f (conditional plan mode) + id:af5a (end-of-meeting closure gate).
# (No `# roadmap:XXXX` header — these are TODO/design ids, not ROADMAP queue items; this test
#  must end GREEN, it is not expected-red. Grep-based contract check, like the sibling
#  test_meeting_c1_executor_contract.sh — pins the spec prose so the gate can't silently regress.)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$ROOT/meeting/SKILL.md"
FMT="$ROOT/meeting/format.md"
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$SKILL" ]] || fail "SKILL.md not found at $SKILL"
[[ -f "$FMT" ]]   || fail "format.md not found at $FMT"

# ── (fc0f) format.md carries the Plan-mode gate: model-conditional EnterPlanMode ──────────
grep -qiE 'Plan-mode gate' "$FMT" \
  || fail "fc0f: format.md missing a 'Plan-mode gate' section"
# the gate must key on the model class and SKIP for opus/fable, USE for sonnet/haiku.
gate="$(awk '/Plan-mode gate/{f=1} f{print} /Fable inline-prose protocol/{if(f)exit}' "$FMT")"
grep -qiE 'claude-opus-\*|Opus-class' <<<"$gate" || fail "fc0f: plan-mode gate does not name the Opus class"
grep -qiE 'claude-fable-\*|Fable-class' <<<"$gate" || fail "fc0f: plan-mode gate does not name the Fable class"
grep -qiE 'claude-sonnet-\*|Sonnet-class' <<<"$gate" || fail "fc0f: plan-mode gate does not name the Sonnet class"
grep -qiE 'SKIP plan mode|SKIP `?EnterPlanMode' <<<"$gate" || fail "fc0f: gate does not SKIP plan mode for the strong tier"
grep -qiE 'USE plan mode|as the SKILL.md steps specify' <<<"$gate" || fail "fc0f: gate does not USE plan mode for Sonnet/Haiku"
grep -qiE 'opusplan' <<<"$gate" || fail "fc0f: gate does not explain the /opusplan tier-switch rationale"
grep -q 'fc0f' <<<"$gate" || fail "fc0f: gate does not cite id:fc0f"
pass "fc0f: format.md Plan-mode gate skips Opus/Fable, uses Sonnet/Haiku, cites /opusplan + fc0f"

# ── (fc0f) SKILL.md EnterPlanMode/ExitPlanMode steps are gated, not unconditional ─────────
# subject-mode step 3 must reference the plan-mode gate + both branches (not a bare 'Call EnterPlanMode').
# (SKILL.md has several numbered lists, so target the step-3 line that mentions the gate directly.)
seg3="$(grep -E '^3\. ' "$SKILL" | grep -i 'Plan-mode gate' | head -1)"
[[ -n "$seg3" ]] || fail "fc0f: no step-3 line references the plan-mode gate (subject-mode step 3 not gated)"
grep -qiE 'Opus/Fable|SKIP' <<<"$seg3" || fail "fc0f: subject-mode step 3 has no Opus/Fable skip branch"
grep -qiE 'Sonnet/Haiku' <<<"$seg3" || fail "fc0f: subject-mode step 3 has no Sonnet/Haiku use branch"

# end-of-meeting ExitPlanMode must be conditional ("only if you entered plan mode").
grep -qiE 'ExitPlanMode.*only if you entered plan mode|only if you entered plan mode' "$SKILL" \
  || fail "fc0f: end-of-meeting ExitPlanMode is not made conditional on having entered plan mode"

# the old ABSOLUTE assertion must be gone (it was the false 'post-ExitPlanMode tier IS Sonnet').
grep -qF 'post-`ExitPlanMode` tier IS Sonnet' "$SKILL" \
  && fail "fc0f: the stale absolute 'post-ExitPlanMode tier IS Sonnet' assertion is still present"
pass "fc0f: SKILL.md gates step-3 EnterPlanMode + conditional ExitPlanMode; stale tier assertion removed"

# ── (af5a) end-of-meeting closure gate exists before the durable writes ───────────────────
grep -q 'af5a' "$SKILL" || fail "af5a: SKILL.md has no closure gate citing id:af5a"
clo="$(awk '/Closure gate \(id:af5a/{f=1} f{print} /^1\. Call `ExitPlanMode`/{if(f)exit}' "$SKILL")"
[[ -n "$clo" ]] || fail "af5a: could not extract the closure-gate block"
grep -qiE 'wrap up' <<<"$clo" || fail "af5a: closure gate lacks a 'wrap up' option"
grep -qiE 'amend a decision' <<<"$clo" || fail "af5a: closure gate lacks an 'amend a decision' option"
grep -qiE 'add an agenda item' <<<"$clo" || fail "af5a: closure gate lacks an 'add an agenda item' option"
# amendment must APPEND/supersede, never silently rewrite (decision-provenance).
grep -qiE 'supersed|APPEND' <<<"$clo" || fail "af5a: amendment path does not append a superseding entry"
grep -qiE 'never silently rewrite|not.*rewrite' <<<"$clo" || fail "af5a: amendment path does not forbid silent rewrite of a ratified decision"
# Fable-class must use inline prose, not AskUserQuestion.
grep -qiE 'Fable' <<<"$clo" || fail "af5a: closure gate does not handle the Fable inline-prose harness"
grep -qiE 'run this FIRST|before step 1|before ANY durable write' <<<"$clo" \
  || fail "af5a: closure gate does not run BEFORE the durable end-of-meeting writes"
pass "af5a: closure gate offers wrap/amend/add, appends (never rewrites), handles Fable, runs first"

echo "ALL PASS: id:fc0f plan-mode gate + id:af5a closure gate"
