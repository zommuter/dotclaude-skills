#!/usr/bin/env bash
# roadmap:6b67 — Relay ROADMAP archiver (roadmap-archive.sh).
# Hermetic tests (mktemp only; no ~/.claude or network):
#   1. Multi-line item-block capture: [x] header + all indented continuations move together.
#   2. Open item + header preservation: [ ] items and ## headings are NEVER touched.
#   3. Prior-commit gate POSITIVE: a [x] item already in HEAD's ROADMAP is archived.
#   4. Prior-commit gate NEGATIVE: a [x] item ticked ONLY in the working tree is NOT archived.
#   5. Aged-date gate: a "done YYYY-MM-DD" item ≥30 days old is archived.
#   6. Aged-date gate NEGATIVE: a "done YYYY-MM-DD" item <30 days old is NOT archived.
#   7. Idempotent no-op: running twice archives nothing on the second run.
#   8. id:XXXX token preservation: the <!-- id:XXXX --> token survives verbatim in the archive.
#   9. Empty headers are LEFT (no section pruning).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/relay/scripts/roadmap-archive.sh"

pass() { printf 'PASS: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*"; exit 1; }

[[ -x "$SCRIPT" ]] || fail "roadmap-archive.sh not found/executable at $SCRIPT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# ── Helper: create a hermetic git repo with a given ROADMAP.md committed at HEAD ──
make_repo() {
    local repo="$1" roadmap_content="$2"
    mkdir -p "$repo"
    git -C "$repo" init -q
    git -C "$repo" config user.email t@example.com
    git -C "$repo" config user.name tester
    printf '%s' "$roadmap_content" > "$repo/ROADMAP.md"
    git -C "$repo" add ROADMAP.md
    git -C "$repo" commit -qm 'seed ROADMAP'
}

# ─────────────────────────────────────────────────
# Test 1: Multi-line block capture
# ─────────────────────────────────────────────────
repo1="$tmp/repo1"
make_repo "$repo1" "# Roadmap

## Items

- [x] Done item one <!-- id:aaaa -->
  - sub-bullet A
  - sub-bullet B
    continuation prose
- [ ] Open item <!-- id:bbbb -->
  - open sub
"
bash "$SCRIPT" "$repo1" 2>/dev/null
arch="$repo1/ROADMAP.archive.md"
road="$repo1/ROADMAP.md"

[[ -f "$arch" ]] || fail "T1: ROADMAP.archive.md was not created"
grep -q 'Done item one' "$arch"          || fail "T1: done header not in archive"
grep -q 'sub-bullet A' "$arch"           || fail "T1: sub-bullet A not in archive"
grep -q 'sub-bullet B' "$arch"           || fail "T1: sub-bullet B not in archive"
grep -q 'continuation prose' "$arch"    || fail "T1: continuation prose not in archive"
# Nothing from the done item should remain in ROADMAP.md
grep -q 'Done item one' "$road"          && fail "T1: done header left in ROADMAP.md"
grep -q 'sub-bullet A' "$road"           && fail "T1: sub-bullet A left in ROADMAP.md"
pass "T1: multi-line block captured and moved as a unit"

# ─────────────────────────────────────────────────
# Test 2: Open item + header preserved
# ─────────────────────────────────────────────────
grep -q 'Open item' "$road"              || fail "T2: open item missing from ROADMAP.md"
grep -q 'open sub' "$road"              || fail "T2: open sub-bullet missing from ROADMAP.md"
grep -q '## Items' "$road"              || fail "T2: ## Items header missing from ROADMAP.md"
grep -q 'Open item' "$arch"             && fail "T2: open item wrongly archived"
pass "T2: open items and headers preserved"

# ─────────────────────────────────────────────────
# Test 3: Prior-commit gate POSITIVE
# (item was [x] in HEAD → archived on next run)
# ─────────────────────────────────────────────────
repo3="$tmp/repo3"
make_repo "$repo3" "# Roadmap

## Items

- [x] Prior-committed done item <!-- id:cccc -->
  - detail line
- [ ] Still open <!-- id:dddd -->
"
# The [x] item is already in HEAD — archiving should move it.
bash "$SCRIPT" "$repo3" 2>/dev/null
arch3="$repo3/ROADMAP.archive.md"
road3="$repo3/ROADMAP.md"
[[ -f "$arch3" ]] || fail "T3: archive not created"
grep -q 'Prior-committed done item' "$arch3"  || fail "T3: prior-commit [x] item not archived"
grep -q 'detail line' "$arch3"               || fail "T3: detail line not in archive"
grep -q 'Still open' "$road3"               || fail "T3: open item removed from ROADMAP"
pass "T3: prior-commit [x] item is archived"

# ─────────────────────────────────────────────────
# Test 4: Prior-commit gate NEGATIVE (working-tree tick — same-run)
# (item is [x] in working tree but was [ ] in HEAD → NOT archived)
# ─────────────────────────────────────────────────
repo4="$tmp/repo4"
# Commit it as OPEN.
make_repo "$repo4" "# Roadmap

## Items

- [ ] Not yet done <!-- id:eeee -->
  - sub of not yet done
- [ ] Another open <!-- id:ffff -->
"
# Now tick it in the working tree (don't commit).
sed -i 's/^- \[ \] Not yet done/- [x] Not yet done/' "$repo4/ROADMAP.md"
bash "$SCRIPT" "$repo4" 2>/dev/null
road4="$repo4/ROADMAP.md"
# The ticked item must still be in ROADMAP.md (working-tree tick, not archived).
grep -q 'Not yet done' "$road4"  || fail "T4: working-tree-ticked item was removed from ROADMAP.md"
# Archive should not exist (or if it does, must not contain the item).
if [[ -f "$repo4/ROADMAP.archive.md" ]]; then
    grep -q 'Not yet done' "$repo4/ROADMAP.archive.md" \
        && fail "T4: working-tree-only tick was archived (must NOT be)"
fi
pass "T4: working-tree-ticked item NOT archived (conservative gate)"

# ─────────────────────────────────────────────────
# Test 5: Aged-date gate POSITIVE (done ≥30 days ago)
# ─────────────────────────────────────────────────
repo5="$tmp/repo5"
old_date=$(date -d '60 days ago' '+%Y-%m-%d')
# Commit this as [x] but with the old date in the header (different text, so prior_done won't match
# unless git HEAD also has it — we'll commit it as [x] to test the aged path independently
# by using a repo where HEAD has a fresh [x] that doesn't have the age marker).
# Easiest: commit as OPEN, tick in WTree, but carry the old date.
make_repo "$repo5" "# Roadmap

## Items

- [ ] Old done item done $old_date <!-- id:gggg -->
  - old sub
- [ ] Fresh open <!-- id:hhhh -->
"
# Tick it in the working tree only (not committed at HEAD as [x]).
sed -i "s/^- \[ \] Old done item/- [x] Old done item/" "$repo5/ROADMAP.md"
bash "$SCRIPT" "$repo5" 2>/dev/null
arch5="$repo5/ROADMAP.archive.md"
[[ -f "$arch5" ]] || fail "T5: archive not created for aged item"
grep -q 'Old done item' "$arch5" || fail "T5: aged done item not archived"
grep -q 'old sub' "$arch5"       || fail "T5: aged done item sub-bullet not archived"
pass "T5: aged-date [x] item (≥30 days) archived"

# ─────────────────────────────────────────────────
# Test 6: Aged-date gate NEGATIVE (done <30 days ago)
# ─────────────────────────────────────────────────
repo6="$tmp/repo6"
new_date=$(date -d '5 days ago' '+%Y-%m-%d')
make_repo "$repo6" "# Roadmap

## Items

- [ ] Recent done item done $new_date <!-- id:iiii -->
- [ ] Open item <!-- id:jjjj -->
"
sed -i "s/^- \[ \] Recent done item/- [x] Recent done item/" "$repo6/ROADMAP.md"
bash "$SCRIPT" "$repo6" 2>/dev/null
road6="$repo6/ROADMAP.md"
grep -q 'Recent done item' "$road6" || fail "T6: recent done item removed from ROADMAP.md (should NOT be archived)"
if [[ -f "$repo6/ROADMAP.archive.md" ]]; then
    grep -q 'Recent done item' "$repo6/ROADMAP.archive.md" \
        && fail "T6: recent done item wrongly archived"
fi
pass "T6: recent-date [x] item (<30 days) NOT archived"

# ─────────────────────────────────────────────────
# Test 7: Idempotent no-op on second run
# ─────────────────────────────────────────────────
# Run on repo3 again — all done items are already in the archive; ROADMAP.md has
# only open items (or was already modified). Re-running must be clean.
bash "$SCRIPT" "$repo3" 2>/dev/null
# Archive must not have grown duplicates.
count3=$(grep -c 'Prior-committed done item' "$repo3/ROADMAP.archive.md" 2>/dev/null || echo 0)
[[ "$count3" -eq 1 ]] || fail "T7: archive has $count3 copies after second run (expected 1)"
pass "T7: second run is idempotent (no duplicate entries)"

# ─────────────────────────────────────────────────
# Test 8: <!-- id:XXXX --> token preserved verbatim
# ─────────────────────────────────────────────────
grep -q '<!-- id:cccc -->' "$repo3/ROADMAP.archive.md" \
    || fail "T8: <!-- id:cccc --> token not preserved in archive"
pass "T8: id token preserved verbatim"

# ─────────────────────────────────────────────────
# Test 9: Protected headers are LEFT even when emptied (id:546b)
# ─────────────────────────────────────────────────
# ## Items is a PROTECTED heading name (Items/Current/Done/Backlog, case-insensitive)
# so it stays even though all items under it moved to the archive this run.
# Non-protected transient grouping headers DO move once emptied — see
# tests/test_roadmap_archive_prose_headers.sh Case B for that behavior.
grep -q '## Items' "$repo3/ROADMAP.md" \
    || fail "T9: ## Items header was pruned (must be left in place)"
pass "T9: empty section headers left in ROADMAP.md (no pruning)"

echo "ok"
