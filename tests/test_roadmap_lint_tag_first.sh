#!/usr/bin/env bash
# roadmap:ad8a
# Spec for the TAG-FIRST-AMONG-TRAILING-TAGS lint rule (id:ad8a; the "A" floor of the
# d259 A→C decision).
#
# INVARIANT (relied on by id:4da4/id:0d58 PRIMARY-LANE anchoring): an item's genuine
# capability lane is the FIRST recognized lane-tag on the line. classify-repo.sh anchors
# on the raw first-position lane-tag (`min()` over LANE_TAGS, NO backtick strip);
# gather-repo-state.sh's roadmap_primary_lane anchors on the first lane-tag AFTER
# stripping backtick-quoted spans (id:1bbd). These two readers AGREE only when the
# genuine (bare) lane tag is literally the first lane-tag substring — i.e. no prose/
# history bracket-token (typically a backtick'd lane mention) appears BEFORE it. When a
# backtick'd/prose lane bracket precedes the genuine tag, classify-repo mis-anchors on it
# while gather anchors on the genuine one — a silent split-brain the lint must surface.
#
# THE RULE: for an OPEN `- [ ]` item, compute
#   raw_first    = first recognized lane-tag WITHOUT stripping backticks  (classify-repo's view)
#   genuine_first= first recognized lane-tag AFTER stripping backticks    (gather's roadmap_primary_lane)
# and FLAG the item when genuine_first exists but raw_first != genuine_first (a prose/
# backtick'd lane bracket sits ahead of the genuine lane tag). A legitimately-first lane
# with a LATER prose bracket is COMPLIANT (raw_first still == genuine_first) — no over-flag.
#
# SEVERITY: severity-agnostic here (handoff recommends WARN as observe-first default;
# the current ROADMAP.md/TODO.md are clean of this violation so a hard ERROR is also
# safe). This test pins BEHAVIOUR via the lint's OUTPUT contract — it asserts a
# tag-first-SPECIFIC diagnostic is (or isn't) surfaced, NOT an exit code — so the
# executor may wire it as WARN (report-only, exit 0) or ERROR (nonzero exit) freely.
#
# The diagnostic must be distinguishable from the existing case-c "tag/prose lane
# conflict / multiple lane brackets" message (id:297b) — case-c fires on a *count* of
# lane brackets and today mis-fires on BOTH shapes below (it counts backtick'd mentions);
# the tag-first rule fires on *order*. Its message must name the ordering/anchoring
# (first / precede / anchor / leading / primary-lane), which case-c's never does.
#
# RED until roadmap-lint.sh grows the tag-first check: today the violation fixture is
# only ever flagged by case-c's "conflict" message (no ordering diagnostic), so the
# tag-first assertion below fails.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LINT="$ROOT/relay/scripts/roadmap-lint.sh"
[[ -x "$LINT" ]] || { echo "roadmap-lint.sh not found/executable (RED): $LINT"; exit 1; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# A tag-first-SPECIFIC diagnostic: names the ordering/anchoring, never just "conflict".
# Deliberately disjoint from case-c's wording ("tag/prose lane conflict … multiple lane
# brackets found") so this test isolates the NEW rule.
TAGFIRST_RE='first|precede|anchor|leading|out-?of-?order|ahead of|primary[ -]lane'

run() { # <fixture-line> -> combined stdout+stderr in $tmp/out (exit code ignored)
  printf '# Roadmap\n## Items\n%s\n' "$1" > "$tmp/r.md"
  "$LINT" "$tmp/r.md" > "$tmp/out" 2>&1 || true
}

# --- (a) VIOLATION: backtick'd prose lane BEFORE the genuine lane tag ----------------------
# Raw-first lane (classify-repo, no strip) = `[ROUTINE]` (it is first); genuine-first
# (gather, strip) = [HARD — pool]. Disagreement → classify-repo mis-anchors → FLAG.
run '- [ ] `[ROUTINE]` (that classification was rejected on handback) — the real work is [HARD — pool] follow-up <!-- id:1111 -->'
grep -qiE "$TAGFIRST_RE" "$tmp/out" \
  || { echo "case (a): a prose lane bracket BEFORE the genuine lane tag must be flagged with a tag-first/ordering diagnostic (got: $(cat "$tmp/out"))"; exit 1; }

# --- (b) COMPLIANT: plain tag-first item --------------------------------------------------
run '- [ ] [ROUTINE] a normal executor item with the lane tag first <!-- id:2222 -->'
grep -qiE "$TAGFIRST_RE" "$tmp/out" \
  && { echo "case (b): a plain tag-first item must NOT trip the tag-first rule (got: $(cat "$tmp/out"))"; exit 1; }

# --- (c) COMPLIANT: genuine lane FIRST, a backtick'd lane mention LATER --------------------
# The id:0d58/fb7f/c3f5 real-world shape: a [HARD — pool] item whose handback history
# quotes a backtick'd `[ROUTINE]` far to the right. The genuine lane IS first (raw_first
# == genuine_first == [HARD — pool]), so the tag-first rule must NOT fire — guards against
# a naive "any line with >1 lane bracket" implementation.
run '- [ ] [HARD — pool] leAIrn2learn thing whose handback history later quotes `[ROUTINE]` as the rejected verdict <!-- id:3333 -->'
grep -qiE "$TAGFIRST_RE" "$tmp/out" \
  && { echo "case (c): a genuinely-tag-first item with a LATER backtick'd lane mention must NOT trip the tag-first rule (got: $(cat "$tmp/out"))"; exit 1; }

echo "PASS test_roadmap_lint_tag_first"
