#!/usr/bin/env bash
# roadmap:85d3 — REVIEW_ME.md archiver: extend archive-closed.sh to a 3rd ledger.
#
# archive-closed.sh archives closed top-level `- [x]` items from TODO.md + ROADMAP.md.
# This spec adds REVIEW_ME.md as a third source, draining closed `[x]` blocks into a
# REVIEW_ME.archive.md sibling. REVIEW_ME items are NOT cross-ledger twins, so a
# REVIEW_ME `[x]` block is archived on its own state (no open-twin protection). The
# `# Human review queue` H1 header + its `<!-- budget: … -->` marker are NEVER moved.
# A closed item's whole block moves — including column-0 prose + `>` blockquote body.
# Idempotent; a second run is a clean no-op.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/relay/scripts/archive-closed.sh"

pass() { printf 'PASS: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*"; exit 1; }

[[ -f "$SCRIPT" ]] || fail "archive-closed.sh missing at $SCRIPT"

tmpd="$(mktemp -d)"; trap 'rm -rf "$tmpd"' EXIT
repo="$tmpd/repo"; mkdir -p "$repo"

# Minimal TODO/ROADMAP so the existing ledgers are quiet, plus a REVIEW_ME with a
# closed item (with column-0 prose + blockquote body) and an open item.
cat > "$repo/TODO.md" <<'EOF'
# TODO

## Current
- [ ] only open here
EOF
cat > "$repo/ROADMAP.md" <<'EOF'
# Roadmap

## Items
- [ ] only open here
EOF
cat > "$repo/REVIEW_ME.md" <<'EOF'
# Human review queue <!-- budget: 15 min -->

- [x] **Resolved review with a body** <!-- id:1111 -->
This is a column-0 prose line describing the resolution.
> a blockquote line of evidence, also at column 0
- [ ] **Still-open review box** <!-- id:2222 -->
  indented context for the open box
EOF

HOME="$tmpd" bash "$SCRIPT" "$repo" 2>/dev/null || fail "archive-closed exited non-zero"

arch="$repo/REVIEW_ME.archive.md"
rm_md="$repo/REVIEW_ME.md"

# ── Closed block + its prose/blockquote moved to the archive ──
[[ -f "$arch" ]]                                       || fail "REVIEW_ME.archive.md not created"
grep -q 'Resolved review with a body' "$arch"          || fail "closed review header not archived"
grep -q 'column-0 prose line' "$arch"                  || fail "column-0 prose not archived (stranded)"
grep -q 'blockquote line of evidence' "$arch"          || fail "blockquote not archived (stranded)"
grep -q '<!-- id:1111 -->' "$arch"                     || fail "id token not preserved in archive"

# ── Nothing from the closed block left behind in REVIEW_ME.md ──
grep -q 'Resolved review with a body' "$rm_md"         && fail "closed review header left in REVIEW_ME.md"
grep -q 'column-0 prose line' "$rm_md"                 && fail "column-0 prose stranded in REVIEW_ME.md"
grep -q 'blockquote line of evidence' "$rm_md"         && fail "blockquote stranded in REVIEW_ME.md"

# ── Open box + the H1 header + budget marker preserved ──
grep -q 'Still-open review box' "$rm_md"               || fail "open review box wrongly removed"
grep -q 'indented context for the open box' "$rm_md"   || fail "open box body wrongly removed"
grep -q '# Human review queue' "$rm_md"                || fail "H1 header wrongly moved/pruned"
grep -q 'budget: 15 min' "$rm_md"                      || fail "budget marker wrongly moved/pruned"
grep -q 'Still-open review box' "$arch"                && fail "open box wrongly archived"
grep -q 'Human review queue' "$arch"                   && fail "H1 header wrongly moved into archive"
pass "REVIEW_ME closed block (with prose+blockquote) archived; open box + header preserved"

# ── Idempotent: a second run archives nothing new (no duplicate) ──
HOME="$tmpd" bash "$SCRIPT" "$repo" 2>/dev/null || fail "second run exited non-zero"
n=$(grep -c 'Resolved review with a body' "$arch")
[[ "$n" -eq 1 ]] || fail "second run duplicated the archived entry (count=$n)"
pass "second run is idempotent (no duplicate)"

echo "ok"
