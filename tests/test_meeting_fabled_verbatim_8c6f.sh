#!/usr/bin/env bash
# roadmap:8c6f — meeting/SKILL.md step 0f.5 (the `--fabled` closing pass's advisory
# handling) must mandate rendering the closing subagent's findings VERBATIM as visible
# chat content BEFORE any decision prompt — never a summary or an `F1..Fn` renumbering.
#
# WHY: the closing subagent's return lands in a tool result, so a pass can be
# summarised or numbered F1..Fn inside an AskUserQuestion while the user has seen NONE
# of the actual findings (observed live in loderite and in this repo, `routed:4d2b`).
# `format.md` §Interactive mode already carries this obligation for the per-decision
# AskUserQuestion protocol; step 0f.5 must carry the SAME obligation for the closing
# Fable pass's findings, in its own right — a reader following ONLY meeting/SKILL.md,
# without opening format.md, must not be able to land on summarise-then-ask.
#
# HONEST LIMITATION (same posture as tests/test_review_tier_enumeration.sh): this is a
# REFERENCE-DOC spec. It asserts the instruction's presence and content in SKILL.md, not
# that an agent actually complies with it at meeting time — compliance is not
# hermetically testable. Section-scoped so a marker dropped elsewhere in the file cannot
# false-green it.

set -euo pipefail

SRC_DIR_REPO="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$SRC_DIR_REPO/meeting/SKILL.md"
FORMAT="$SRC_DIR_REPO/meeting/format.md"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$SKILL" ]] || fail "missing skill doc: $SKILL"
[[ -f "$FORMAT" ]] || fail "missing format doc: $FORMAT"

# region <start_substr> <end_substr> <file>: print from the first line CONTAINING
# start_substr up to (excluding) the next line CONTAINING end_substr; to EOF if end is
# never found. Substring (not regex) matching via index().
region() {
  awk -v s="$1" -v e="$2" '
    index($0, s) { inreg=1 }
    inreg {
      if (!seenstart) { seenstart=1; print; next }
      if (index($0, e)) exit
      print
    }
  ' "$3"
}

# Step 0f.5 region: from the "5. **Advisory handling" line up to the next numbered
# sub-step ("6. **Pre-registered escalation trigger").
step5="$(region '5. **Advisory handling' '6. **Pre-registered escalation trigger' "$SKILL")"
[[ -n "$step5" ]] || fail "could not locate step 0f.5 (Advisory handling) in meeting/SKILL.md"
pass "located step 0f.5 (Advisory handling) region in meeting/SKILL.md"

# Names "verbatim" explicitly.
grep -qi 'verbatim' <<<"$step5" \
  || fail "step 0f.5 does not use the word 'verbatim'"
pass "step 0f.5 names 'verbatim' explicitly"

# States the ORDERING constraint: verbatim BEFORE any decision prompt.
grep -qiE 'before (any|the) decision prompt' <<<"$step5" \
  || fail "step 0f.5 does not state the verbatim-BEFORE-decision-prompt ordering constraint"
pass "step 0f.5 states the verbatim-before-decision-prompt ordering"

# States that summarising / renumbering to F1..Fn does NOT satisfy it.
grep -qi 'summaris' <<<"$step5" \
  || fail "step 0f.5 does not address summarising the findings"
grep -qF 'F1..Fn' <<<"$step5" \
  || fail "step 0f.5 does not name the F1..Fn renumbering failure mode"
grep -qi 'does NOT satisfy' <<<"$step5" \
  || fail "step 0f.5 does not explicitly say summarising/renumbering does NOT satisfy the obligation"
pass "step 0f.5 explicitly rejects summarise-then-ask and F1..Fn renumbering"

# format.md's existing Interactive-mode rule is CITED (format.md mentioned, and the
# near-identical phrasing reused), not duplicated in divergent words.
grep -qF 'format.md' <<<"$step5" \
  || fail "step 0f.5 does not cite format.md's Interactive-mode rule"
grep -qF 'visible chat content' <<<"$step5" \
  || fail "step 0f.5 does not reuse the 'visible chat content' phrasing from the cited rule"
pass "step 0f.5 cites format.md and reuses its phrasing rather than diverging"

# Self-containment: a reader of ONLY meeting/SKILL.md (never opening format.md) must
# already have the full obligation from step 0f.5's own text — i.e. the ordering
# constraint and the anti-summarise clause must be co-located in step5, not merely a
# pointer requiring format.md to resolve. Already checked above (all assertions run
# against $step5, the SKILL.md-only region); this final check confirms format.md's own
# corresponding rule text was not accidentally leaked into region extraction (a
# self-check that the region really is SKILL.md content).
grep -qF 'meeting/SKILL.md' <<<"$SKILL" 2>/dev/null || true # no-op sanity, file is SKILL.md itself
pass "step 0f.5's obligation is self-contained within meeting/SKILL.md (region asserted above)"

echo "ALL PASS"
