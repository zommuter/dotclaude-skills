#!/usr/bin/env bash
# roadmap:1781
# Spec for id:1781 — roadmap-lint.sh must validate ONLY the LEADING lane bracket(s)
# per line and IGNORE lane-bracket mentions that appear in trailing audit-trail prose.
#
# Surfaced by leAIrn2learn (id:c3f5): an item whose HEAD tag is a correct single lane
# but whose BODY cites a prior `[HARD — …]`/`[ROUTINE]` transition in *non-backticked*
# audit-trail prose currently trips the case-c "multiple lane brackets" LOUD-reject
# (roadmap-lint.sh:350). The existing backtick-strip (line 328) only rescues
# `[HARD]`-in-backticks; a bare mention like "(was [HARD — pool] before, re-laned to
# [ROUTINE])" still false-positives.
#
# Fix contract: the lane tag(s) are the CONTIGUOUS run of lane brackets at the very
# start of the item text (immediately after `- [ ] `). A lane bracket that appears
# AFTER any prose word is trailing audit-trail prose and must NOT count toward the
# multiple-lane-brackets conflict. Two contiguous LEADING lane tags is still a genuine
# conflict and must still ERROR (do not weaken case-c / test_roadmap_lint_tagprose).
#
# RED until roadmap-lint.sh restricts the conflict check to the leading bracket run.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LINT="$ROOT/relay/scripts/roadmap-lint.sh"
[[ -x "$LINT" ]] || { echo "roadmap-lint.sh not found/executable (RED): $LINT"; exit 1; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# --- (1) trailing-prose lane mention → must PASS (the id:1781 false-positive) ---------
cat > "$tmp/roadmap_trailing.md" <<'EOF'
# Roadmap
## Items
- [ ] [ROUTINE] fix the parser (was [HARD — pool] before 2026-07-01, re-laned to [ROUTINE]) <!-- id:abcd -->
EOF
if ! "$LINT" "$tmp/roadmap_trailing.md" 2>"$tmp/err_t"; then
  echo "id:1781 FAIL: a correct leading [ROUTINE] tag with a lane bracket in TRAILING prose must PASS (got: $(cat "$tmp/err_t"))"
  exit 1
fi

# --- (2) genuine two-contiguous-LEADING-tag conflict → must still ERROR ----------------
cat > "$tmp/roadmap_conflict.md" <<'EOF'
# Roadmap
## Items
- [ ] [HARD — pool] [ROUTINE] two contiguous leading lane tags on one item <!-- id:1111 -->
EOF
if "$LINT" "$tmp/roadmap_conflict.md" 2>"$tmp/err_c"; then
  echo "id:1781 FAIL: two contiguous LEADING lane tags must still ERROR (regression of case-c)"; exit 1
fi
grep -qiE 'conflict|multiple lane|disagree|prose' "$tmp/err_c" \
  || { echo "id:1781 FAIL: conflict stderr must name the multiple-lane conflict (got: $(cat "$tmp/err_c"))"; exit 1; }

# --- (3) clean single-tag item → still PASS (no false positive) ------------------------
cat > "$tmp/roadmap_ok.md" <<'EOF'
# Roadmap
## Items
- [ ] [ROUTINE] a normal executor item <!-- id:3333 -->
EOF
"$LINT" "$tmp/roadmap_ok.md" 2>"$tmp/err_ok" \
  || { echo "id:1781 FAIL: clean single-tag item must pass (got: $(cat "$tmp/err_ok"))"; exit 1; }

echo "PASS test_roadmap_lint_trailing_lane_prose"
