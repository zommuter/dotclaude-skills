#!/usr/bin/env bash
# roadmap:546b — ROADMAP archiver: capture column-0 prose/blockquote bodies +
#                move emptied transient grouping headers into the archive.
#
# Bug 1: roadmap-archive.sh only treats blank/indented lines as an item's
#        continuation, so a column-0 prose paragraph or `>` blockquote in a
#        [x] item's body is stranded when the item is archived. Fix: capture
#        the block up to the next top-level bullet OR heading (as archive-closed.sh does).
# Bug 2 (BOTH roadmap-archive.sh AND archive-closed.sh): a grouping header emptied
#        by this run should MOVE into the archive with its block. Protected (never
#        moved even when emptied): the H1 title, and buckets named exactly
#        Items/Current/Done/Backlog. An already-empty header on arrival is left.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RM_SCRIPT="$ROOT/relay/scripts/roadmap-archive.sh"
AC_SCRIPT="$ROOT/relay/scripts/archive-closed.sh"

pass() { printf 'PASS: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*"; exit 1; }

[[ -x "$RM_SCRIPT" ]] || fail "roadmap-archive.sh not executable at $RM_SCRIPT"
[[ -f "$AC_SCRIPT" ]] || fail "archive-closed.sh missing at $AC_SCRIPT"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

make_repo() {  # repo, roadmap_content — commits ROADMAP at HEAD (prior-commit gate)
  local repo="$1" content="$2"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email t@example.com
  git -C "$repo" config user.name tester
  printf '%s' "$content" > "$repo/ROADMAP.md"
  git -C "$repo" add ROADMAP.md
  git -C "$repo" commit -qm seed
}

# ─────────────────────────────────────────────────────────────────
# Case A (roadmap-archive.sh): column-0 prose + blockquote captured
# ─────────────────────────────────────────────────────────────────
rA="$tmp/repoA"
make_repo "$rA" "# Roadmap

## Items

- [x] Done item with a col-0 body <!-- id:aaaa -->
This prose is at column 0 and belongs to the item.
> a blockquote line, also at column 0
- [ ] Open item stays <!-- id:bbbb -->
"
bash "$RM_SCRIPT" "$rA" 2>/dev/null
archA="$rA/ROADMAP.archive.md"; roadA="$rA/ROADMAP.md"
[[ -f "$archA" ]] || fail "A: archive not created"
grep -q 'Done item with a col-0 body' "$archA" || fail "A: done header not archived"
grep -q 'This prose is at column 0' "$archA"   || fail "A: column-0 prose not archived (Bug 1)"
grep -q 'a blockquote line' "$archA"           || fail "A: blockquote not archived (Bug 1)"
grep -q 'This prose is at column 0' "$roadA"    && fail "A: column-0 prose stranded in ROADMAP.md (Bug 1)"
grep -q 'a blockquote line' "$roadA"            && fail "A: blockquote stranded in ROADMAP.md (Bug 1)"
grep -q 'Open item stays' "$roadA"             || fail "A: open item wrongly removed"
pass "A: column-0 prose + blockquote captured with the item (roadmap-archive.sh)"

# ─────────────────────────────────────────────────────────────────
# Case B: non-protected transient header MOVES to archive when emptied;
#         protected ## Items header STAYS; already-empty header left.
# ─────────────────────────────────────────────────────────────────
rB="$tmp/repoB"
make_repo "$rB" "# Roadmap

## Items

- [x] Only item under Items <!-- id:cccc -->

## batch 2020-01-01 (transient grouping)

- [x] Only item under the transient header <!-- id:dddd -->

## Already empty on arrival
"
bash "$RM_SCRIPT" "$rB" 2>/dev/null
archB="$rB/ROADMAP.archive.md"; roadB="$rB/ROADMAP.md"
# Protected Items header stays even though its only item archived.
grep -q '## Items' "$roadB"                        || fail "B: protected ## Items header wrongly moved"
# Non-protected transient header moved to archive, gone from ROADMAP.
grep -q 'batch 2020-01-01' "$roadB"                && fail "B: emptied transient header left in ROADMAP.md"
grep -q 'batch 2020-01-01' "$archB"                || fail "B: emptied transient header not moved to archive"
# Already-empty-on-arrival header is left in place (nothing archived under it).
grep -q '## Already empty on arrival' "$roadB"     || fail "B: already-empty header wrongly removed"
grep -q 'Already empty on arrival' "$archB"        && fail "B: already-empty header wrongly moved to archive"
pass "B: emptied transient header moves; protected + already-empty headers stay (roadmap-archive.sh)"

# ─────────────────────────────────────────────────────────────────
# Case C (archive-closed.sh): same emptied-transient-header-move behavior
# ─────────────────────────────────────────────────────────────────
rC="$tmp/repoC"; mkdir -p "$rC"
cat > "$rC/TODO.md" <<'EOF'
# TODO

## Current
- [ ] keep todo quiet
EOF
cat > "$rC/ROADMAP.md" <<'EOF'
# Roadmap

## Items
- [ ] a live open item

## sprint 42 (transient)
- [x] the only, now-closed item <!-- id:eeee -->
EOF
HOME="$tmp" bash "$AC_SCRIPT" "$rC" 2>/dev/null || fail "C: archive-closed exited non-zero"
roadC="$rC/ROADMAP.md"; archC="$rC/ROADMAP.archive.md"
grep -q '## Items' "$roadC"                 || fail "C: protected ## Items header wrongly moved"
grep -q 'sprint 42' "$roadC"                && fail "C: emptied transient header left in ROADMAP.md (archive-closed.sh)"
grep -q 'sprint 42' "$archC"                || fail "C: emptied transient header not moved to archive (archive-closed.sh)"
pass "C: emptied transient header moves; protected header stays (archive-closed.sh)"

echo "ok"
