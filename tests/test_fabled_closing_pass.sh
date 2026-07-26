#!/usr/bin/env bash
# roadmap:7e87 — /meeting --fabled opt-in closing Fable-5 subagent pass.
# Structural contract check (grep-based, like test_meeting_plan_mode_gate.sh): pins the
# v1 closing-pass flow documented in meeting/SKILL.md so it can't silently regress.
# Design: docs/meeting-notes/2026-07-20-2304-fabled-meeting-flow-and-unknown-switch-guard.md (D3).
# Unifies the inbound id:8df5 (routed:5c06 from loderite).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$ROOT/meeting/SKILL.md"
MANIFEST="$ROOT/relay/scripts/known-flags-meeting.tsv"
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$SKILL" ]]    || fail "SKILL.md not found at $SKILL"
[[ -f "$MANIFEST" ]] || fail "known-flags-meeting.tsv not found at $MANIFEST"

# ── (7681 coupling) --fabled is registered in the meeting known-flags manifest ────────────
# Without this the arg-guard (id:7681) would warn on a correct --fabled invocation.
grep -qE '^--fabled[[:space:]]' "$MANIFEST" \
  || fail "7e87: --fabled is not registered in known-flags-meeting.tsv (arg-guard would warn on it)"
pass "7e87: --fabled registered in the meeting known-flags manifest"

# ── SKILL.md documents the closing Fable pass and cites the item id ───────────────────────
grep -q '7e87' "$SKILL" || fail "7e87: SKILL.md does not cite id:7e87"
grep -qiE 'fabled' "$SKILL" || fail "7e87: SKILL.md does not mention the --fabled flag"

# Extract the closing-pass block. It is a discrete End-of-meeting sub-step keyed on '--fabled'
# closing pass; bounded by the next numbered end-of-meeting step (1. Call `ExitPlanMode`).
blk="$(awk '/[Ff]abled closing pass|[Cc]losing Fable pass/{f=1} f{print} /^1\. Call `ExitPlanMode`/{if(f)exit}' "$SKILL")"
[[ -n "$blk" ]] || fail "7e87: could not locate a '--fabled closing pass' step in SKILL.md End-of-meeting steps"

# 1. opt-in: only runs when --fabled was passed.
grep -qiE 'only.*--fabled|--fabled was passed|if `?--fabled`?|opt-in' <<<"$blk" \
  || fail "7e87: closing pass is not gated on --fabled being passed (must be opt-in, never default)"
pass "7e87: closing pass is opt-in (only when --fabled passed)"

# 2. availability via the tested probe helper (NIH: reuse probe-fable.sh, don't re-derive).
grep -q 'probe-fable.sh' <<<"$blk" \
  || fail "7e87: closing pass does not reuse probe-fable.sh for Fable availability (must not re-derive the probe)"
pass "7e87: closing pass reuses probe-fable.sh for availability"

# 3. LOUD degrade if Fable unavailable — the EXACT recorded string, and it goes in the note.
grep -qF 'Fable unavailable — `--fabled` pass skipped' <<<"$blk" \
  || fail "7e87: closing pass does not record the LOUD-degrade string 'Fable unavailable — \`--fabled\` pass skipped'"
grep -qiE 'never silent|not silent|LOUD' <<<"$blk" \
  || fail "7e87: closing pass degrade is not marked LOUD/never-silent (silent degrade re-creates id:7681, D3)"
pass "7e87: LOUD degrade recorded in the note (never silent)"

# 4. digest built AT CLOSING TIME, including the ratified decisions VERBATIM.
grep -qiE 'digest' <<<"$blk" || fail "7e87: closing pass does not build a repo-state digest"
grep -qiE 'closing time|at closing' <<<"$blk" || fail "7e87: digest is not built AT CLOSING TIME (D3)"
grep -qiE 'ratified decisions verbatim|ratified.*verbatim' <<<"$blk" \
  || fail "7e87: digest does not include the ratified decisions VERBATIM (D3)"
pass "7e87: closing-time digest includes ratified decisions verbatim"

# 5. ONE Fable-5 subagent (Task tool, model override), subagent-NOT-driver, design-critique framing.
grep -qE 'claude-fable-5' <<<"$blk" || fail "7e87: closing pass does not pin the subagent to model claude-fable-5"
grep -qiE 'one .*subagent|single .*subagent|ONE closing' <<<"$blk" \
  || fail "7e87: closing pass does not run exactly ONE closing subagent pass"
grep -qiE 'subagent.*not.*driver|not.*driver|advisory' <<<"$blk" \
  || fail "7e87: closing pass does not keep Fable as subagent-not-driver / advisory"
grep -qiE 'design.critique|design critique' <<<"$blk" \
  || fail "7e87: closing pass does not use the design-critique framing (sidesteps the reasoning_extraction refusal, id:aa68)"
pass "7e87: ONE Fable-5 subagent, design-critique framing, subagent-not-driver"

# 6. Findings ADVISORY only, never a gate; owner ratifies amendments via the closure-gate flow.
grep -qiE 'advisory|never a gate|not a gate' <<<"$blk" \
  || fail "7e87: findings are not marked advisory-only / never-a-gate (feedback-fable-optional-not-gate)"
grep -qiE 'amend|closure gate|re-?open' <<<"$blk" \
  || fail "7e87: closing-pass findings do not feed the closure-gate amendment flow (owner ratifies)"
pass "7e87: findings advisory-only; owner ratifies amendments via the closure gate"

# 7. Pre-registered COUNTABLE trigger for escalating to per-decision / multi-pass (id:8df5).
grep -qiE '≥ ?2|>= ?2|two .*findings|2 .*findings' <<<"$blk" \
  || fail "7e87: no pre-registered countable trigger (≥2 findings forcing an amendment) for per-decision/multi-pass escalation"
grep -qiE 'reopen|amend.*ratif|force.*amend' <<<"$blk" \
  || fail "7e87: escalation trigger does not key on findings that FORCE reopening/amending a ratified decision"
grep -qiE 'hardening.only|hardening.*not count|do not count' <<<"$blk" \
  || fail "7e87: escalation trigger does not exclude hardening-only findings (the metric must discriminate, D3)"
grep -q '8df5' <<<"$blk" || fail "7e87: closing pass does not cite the unified id:8df5 (per-decision + multi-pass gate)"
pass "7e87: pre-registered ≥2-forced-amendments trigger gates per-decision/multi-pass (unifies 8df5)"

echo "ALL PASS: id:7e87 /meeting --fabled closing Fable pass"
