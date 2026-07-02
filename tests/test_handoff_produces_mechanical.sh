#!/usr/bin/env bash
# roadmap:9c88 — M1: handoff.md C2 must PRODUCE the [MECHANICAL] tag + author the recipe.
#
# WHY (meeting amendment 2026-07-02, the `[MECHANICAL]` producer gap): slice-A A1 shipped
# the CONSUMER half only — the classifier RECOGNIZES `[MECHANICAL]`→the pool-inert
# `mechanical` verdict, but `handoff.md` C2 still only ever tags `[ROUTINE]`/`[HARD — *]`,
# so the tag is routed but never PRODUCED and nothing feeds the daemon (A3). M1 teaches the
# handoff C2 contract prose to (i) recognize compute-only / no-LLM / benchmark-or-pilot work
# and tag it `[MECHANICAL]`, and (ii) AUTHOR the A2 recipe (recipe-manifest.md schema,
# id:64d3) into `~/.config/relay/recipes/pending/` — the producer link to A3.
#
# This is a STRUCTURAL (grep-style) test, like tests/test_hard_lane_buckets.sh: it asserts
# the CONTRACT PROSE documents the two producer instructions. It goes green when the prose
# lands in relay/references/handoff.md. RED until then.
#
# NOTE: handoff.md already uses the word "mechanical" in unrelated contexts ("mechanical
# filer", "mechanical transform"), so this test greps for the BRACKETED `[MECHANICAL]` tag
# token — never the bare word — to avoid a false green.
set -euo pipefail

SRC_DIR_REPO="$(cd "$(dirname "$0")/.." && pwd)"
HANDOFF="$SRC_DIR_REPO/relay/references/handoff.md"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$HANDOFF" ]] || fail "handoff.md missing at $HANDOFF"

# --- (1) C2 documents tagging compute-only/no-LLM work as the [MECHANICAL] tag ----
grep -qF '[MECHANICAL]' "$HANDOFF" \
  || fail "(1) handoff.md does not mention the [MECHANICAL] capability tag — C2 must PRODUCE it (M1 producer gap)"
pass "(1) handoff.md names the [MECHANICAL] tag"

# --- (2) C2 documents AUTHORING an A2 recipe into the pending/ drop-dir -----------
# The producer link: an authored recipe in ~/.config/relay/recipes/pending/, referencing
# the recipe-manifest.md schema (id:64d3).
grep -qE 'recipes/pending' "$HANDOFF" \
  || fail "(2) handoff.md does not document authoring a recipe into recipes/pending/ (A2 producer link)"
grep -qiE 'recipe-manifest|recipe manifest|recipe schema|A2 recipe|64d3' "$HANDOFF" \
  || fail "(2) handoff.md does not reference the recipe-manifest schema (id:64d3) for the authored recipe"
pass "(2) handoff.md documents authoring an A2 recipe into recipes/pending/ (recipe-manifest schema)"

# --- (3) the [MECHANICAL]-tagging + recipe-authoring live in the C2 roadmap region -
# Guard against the tokens landing only in an unrelated section: both must appear at or
# after the C2 checkpoint marker (the roadmap-writing checkpoint C2 owns tagging).
c2_line="$(grep -nF '**C2 — roadmap.**' "$HANDOFF" | head -1 | cut -d: -f1 || true)"
[[ -n "$c2_line" ]] || fail "(3) could not locate the '**C2 — roadmap.**' checkpoint marker in handoff.md"
tail -n "+$c2_line" "$HANDOFF" | grep -qF '[MECHANICAL]' \
  || fail "(3) the [MECHANICAL]-tagging instruction is not at/after the C2 checkpoint (must live in C2's producer prose)"
pass "(3) the [MECHANICAL] producer instruction lives at/after the C2 checkpoint"

echo "ALL PASS: handoff C2 produces [MECHANICAL] + authors the recipe (id:9c88)"
