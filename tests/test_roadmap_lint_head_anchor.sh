#!/usr/bin/env bash
# roadmap:be0e
# Spec for id:be0e — roadmap-lint.sh must anchor lane-grammar validation to the
# FIRST bracket after the checkbox (the head lane tag) and ignore later bracket
# mentions in the body, per relay human ruling 2026-07-19 (leAIrn2learn id:c3f5).
#
# Concrete, currently-reproducible manifestation on THIS repo's own ROADMAP.md:
# an item whose head tag is markdown-bold-wrapped (`**[ROUTINE] Title**` — the
# actual style used by this repo's own be0e/050b entries) trips a spurious
# TAG-NOT-FIRST WARN, because the position check compares the text immediately
# after the checkbox against the tag LITERALLY, and `**` (the bold wrapper
# touching the tag) is not whitespace — so a genuinely-first lane tag is
# misreported as "not first". The lane-grammar check must anchor to the FIRST
# BRACKET after the checkbox, tolerating markdown emphasis wrapping it, not to
# the first raw byte.
#
# RED until roadmap-lint.sh's TAG-NOT-FIRST position check tolerates markdown
# emphasis (`**`/`_`) directly wrapping the leading lane tag.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LINT="$ROOT/relay/scripts/roadmap-lint.sh"
[[ -x "$LINT" ]] || { echo "roadmap-lint.sh not found/executable (RED): $LINT"; exit 1; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# --- (1) markdown-bold-wrapped leading tag → must NOT trip TAG-NOT-FIRST -------------------
cat > "$tmp/roadmap_bold.md" <<'EOF'
# Roadmap
## Items
- [ ] **[ROUTINE] a bold-wrapped leading tag** <!-- id:b01d -->
EOF
out_bold="$("$LINT" "$tmp/roadmap_bold.md" 2>&1 || true)"
"$LINT" "$tmp/roadmap_bold.md" >/dev/null 2>&1 \
  || { echo "id:be0e FAIL: a markdown-bold-wrapped leading [ROUTINE] tag must lint clean (got: $out_bold)"; exit 1; }
grep -qF 'TAG-NOT-FIRST' <<<"$out_bold" \
  && { echo "id:be0e FAIL: a genuinely-first (bold-wrapped) lane tag must NOT trip TAG-NOT-FIRST (false positive):
$out_bold"; exit 1; }

# --- (2) bold-wrapped leading tag PLUS a body bracket mention → still clean, no error/warn --
cat > "$tmp/roadmap_bold_body.md" <<'EOF'
# Roadmap
## Items
- [ ] **[ROUTINE] fix the parser** (re-laned `[INPUT — decision]`→`[ROUTINE]` this session) <!-- id:c0de -->
EOF
out_bb="$("$LINT" "$tmp/roadmap_bold_body.md" 2>&1 || true)"
"$LINT" "$tmp/roadmap_bold_body.md" >/dev/null 2>&1 \
  || { echo "id:be0e FAIL: a bold-wrapped leading tag with a body bracket mention must lint clean (got: $out_bb)"; exit 1; }
grep -qiE 'conflict|multiple lane|TAG-NOT-FIRST' <<<"$out_bb" \
  && { echo "id:be0e FAIL: a body bracket mention must be ignored, not flagged as a conflict/TAG-NOT-FIRST:
$out_bb"; exit 1; }

# --- (3) genuinely out-of-order (title precedes tag, no markdown) → must STILL warn --------
# Regression guard: the markdown tolerance must not swallow the genuine tag-not-first case.
cat > "$tmp/roadmap_realprose.md" <<'EOF'
# Roadmap
## Items
- [ ] title precedes the tag [ROUTINE] <!-- id:aa10 -->
EOF
out_real="$("$LINT" "$tmp/roadmap_realprose.md" 2>&1 || true)"
grep -qF 'TAG-NOT-FIRST' <<<"$out_real" \
  || { echo "id:be0e FAIL: a genuinely out-of-order tag (prose before it, no markdown) must still trip TAG-NOT-FIRST (regression):
$out_real"; exit 1; }

echo "PASS test_roadmap_lint_head_anchor"
