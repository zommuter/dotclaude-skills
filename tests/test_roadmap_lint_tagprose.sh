#!/usr/bin/env bash
# roadmap:297b
# Spec for the case (c)/(d) lint checks (id:297b; meeting 2026-06-30-1523 DP2/DP3).
#
# roadmap-lint.sh must LOUDLY ERROR (nonzero exit + a stderr message) on:
#   (c) id:244b — a tag/prose lane DISAGREEMENT: the item's lane bracket says one thing
#       while its own prose claims another lane ("re-laned to pool, runs under --intensive").
#       The TAG is authority; a tag/prose disagreement must fail loud (never be read as a
#       silent "gated" no-op that an empty run then misreads as "done").
#   (d) c5e9/fd30 — a FREE-TYPED [INTENSIVE — <resource>] on a non-derivable item (a disk
#       `rm`, a /meeting decision item). INTENSIVE must be DERIVABLE, not free-typed.
#
# These are LOUD-FAIL cases, NOT verdicts: assert exit-code + stderr severity, never a
# verdict label (mixing assert-verdict with assert-loud-fail is itself a swallowed-warning
# regression — DP3). Verdict-layer cases (a/b/h) live in tests/test_classify_verdict.sh
# (# roadmap:85df). RED until roadmap-lint.sh grows the case-c and case-d checks.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LINT="$ROOT/relay/scripts/roadmap-lint.sh"
[[ -x "$LINT" ]] || { echo "roadmap-lint.sh not found/executable (RED): $LINT"; exit 1; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# --- Case (c) tag/prose disagreement → loud ERROR -----------------------------------------
cat > "$tmp/roadmap_c.md" <<'EOF'
# Roadmap
## Items
- [ ] [HARD — decision gate] benchmark thing — actually re-laned to `[HARD — pool]`, runs under --intensive now <!-- id:1111 -->
EOF
if "$LINT" "$tmp/roadmap_c.md" 2>"$tmp/err_c"; then
  echo "case c: tag/prose lane disagreement must ERROR (nonzero exit)"; exit 1
fi
grep -qiE 'tag.*prose|prose.*lane|disagree|contradic|conflict' "$tmp/err_c" \
  || { echo "case c: stderr must name the tag/prose disagreement (got: $(cat "$tmp/err_c"))"; exit 1; }

# --- Case (d) lane-less INTENSIVE → loud ERROR -----------------------------------------------
# RECONCILE (id:9062, meeting 2026-06-30-2238): the old case-d example used
# [HARD — meeting] [INTENSIVE], which is now ACCEPTED as advisory on human lanes.
# Repointed to a genuinely LANE-LESS [INTENSIVE] (no [ROUTINE]/[HARD] tag), which still
# exercises the real reject path: the item has no recognised class tag, so the
# missing-class-tag grammar fires — not a case-d intensive-specific check. The
# reject message names the missing lane, not INTENSIVE specifically.
cat > "$tmp/roadmap_d.md" <<'EOF'
# Roadmap
## Items
- [ ] [INTENSIVE — local-llm] do something GPU-heavy with no lane tag at all <!-- id:2222 -->
EOF
"$LINT" "$tmp/roadmap_d.md" > "$tmp/out_d" 2>"$tmp/err_d" && {
  echo "case d: lane-less [INTENSIVE] (no recognised class tag) must ERROR (nonzero exit)"; exit 1
}
# The missing-class-tag violation goes to stdout (via the report buffer); grep stdout.
grep -qiE 'class|lane|tag|recognized' "$tmp/out_d" \
  || { echo "case d: stdout must describe missing class/lane tag (got: $(cat "$tmp/out_d"))"; exit 1; }

# --- No false positives: a clean ROADMAP still lints OK -----------------------------------
cat > "$tmp/roadmap_ok.md" <<'EOF'
# Roadmap
## Items
- [ ] [ROUTINE] a normal executor item <!-- id:3333 -->
- [ ] [HARD — pool] a normal pool item <!-- id:4444 -->
EOF
"$LINT" "$tmp/roadmap_ok.md" 2>"$tmp/err_ok" \
  || { echo "clean roadmap must pass lint (got: $(cat "$tmp/err_ok"))"; exit 1; }

echo "PASS test_roadmap_lint_tagprose"
