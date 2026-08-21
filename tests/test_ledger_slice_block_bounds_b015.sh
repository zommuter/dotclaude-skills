#!/usr/bin/env bash
# roadmap:b015 — ledger-slice.sh must bound an item's block by the next CHECKBOX or HEADING,
# not by the first unindented line, and must stamp the owning section heading.
#
# The defect (blast-radius review 2026-08-21): the block was extended only while the next line
# matched `^[[:space:]]+`, so ANY column-0 continuation belonging to the item — a prose
# acceptance paragraph, an un-indented sub-bullet, a fenced code block — was silently dropped.
# The slice stayed well-formed and non-empty, `slice-bytes` stayed honest, the prompt-size gate
# passed, and the child worked a spec missing its acceptance criteria: WRONG WORK, not a crash.
# It also omitted the item's owning SECTION HEADING, so parked/exempt-section context (id:356f)
# was invisible to the child.
#
# Hermetic: mktemp -d fixture, bash + coreutils only, no network, never touches ~/.claude.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SLICE="$ROOT/relay/scripts/ledger-slice.sh"

pass=0; fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); }
bad() { echo "BAD: $*"; fail=$((fail+1)); }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
R="$TMP/repo"; mkdir -p "$R"

# ── Fixture: one item carrying column-0 prose, an un-indented bullet and a fenced block,
#    IMMEDIATELY followed by an adjacent item; then a second section. ────────────────────────
cat >"$R/ROADMAP.md" <<'FIXTURE'
# ROADMAP

## Parked (exempt per id:356f)

- [ ] [ROUTINE] **ITEM ONE** — the dispatched item <!-- id:1111 -->
  - **Tests**: `tests/test_one.sh` (currently RED)

COL0_PROSE_MARKER — this acceptance paragraph is written at column 0 and belongs to id:1111.

- COL0_BULLET_MARKER an un-indented sub-bullet that is not a checkbox

```bash
FENCE_MARKER
# not a heading: inside a fence
- [ ] FENCE_FAKE_ITEM this looks like a checkbox but is fenced sample text
```

Trailing column-0 line TAIL_MARKER still belonging to id:1111.

- [ ] [ROUTINE] **ITEM TWO** — NEXT_ITEM_MARKER, adjacent to item one <!-- id:2222 -->
  - **Tests**: `tests/test_two.sh`

## Another section

- [ ] [ROUTINE] **ITEM THREE** — THIRD_MARKER <!-- id:3333 -->
FIXTURE

printf '# TODO\n\n## Current\n\n' > "$R/TODO.md"

[[ -x "$SLICE" ]] || { echo "BAD: $SLICE missing/not executable"; exit 1; }

slice_one() { # <id> <outfile> -> prints stdout
  "$SLICE" --repo repo --path "$R" --id "$1" --out "$2"
}

# ── (1) Column-0 continuation is INCLUDED ───────────────────────────────────────────────────
O1="$TMP/one.md"
out1="$(slice_one 1111 "$O1")"

for m in COL0_PROSE_MARKER COL0_BULLET_MARKER TAIL_MARKER; do
  grep -q "$m" "$O1" \
    && ok "slice keeps column-0 continuation ($m)" \
    || bad "id:b015: slice DROPS column-0 continuation ($m) — the child works a truncated spec"
done

# ── (2) A fenced block is never split mid-fence ─────────────────────────────────────────────
grep -q 'FENCE_MARKER' "$O1" \
  && ok "slice keeps the item's fenced code block" \
  || bad "id:b015: slice drops the item's fenced code block (FENCE_MARKER absent)"
grep -q 'FENCE_FAKE_ITEM' "$O1" \
  && ok "a checkbox-looking line INSIDE a fence does not terminate the block" \
  || bad "id:b015: a fenced sample checkbox line truncated the block (FENCE_FAKE_ITEM absent)"
fences=$(grep -c '^[[:space:]]*```' "$O1" || true)
if (( fences % 2 == 0 && fences >= 2 )); then
  ok "fence delimiters are balanced in the slice ($fences)"
else
  bad "id:b015: slice splits a fenced block mid-fence ($fences fence delimiters, expected an even count >= 2)"
fi

# ── (3) The owning section HEADING is stamped into the slice ────────────────────────────────
grep -q 'Parked (exempt per id:356f)' "$O1" \
  && ok "slice stamps the item's owning section heading" \
  || bad "id:b015: slice omits the owning section heading — parked/exempt context (id:356f) invisible to the child"

# ── (4) The block must NOT bleed into the adjacent next item ────────────────────────────────
grep -q 'NEXT_ITEM_MARKER' "$O1" \
  && bad "id:b015: item one's block BLEEDS into the adjacent item two (NEXT_ITEM_MARKER present)" \
  || ok "block stops at the adjacent item's checkbox line"
grep -q 'THIRD_MARKER' "$O1" \
  && bad "id:b015: item one's block ran past a heading into a later section (THIRD_MARKER present)" \
  || ok "block stops at the next heading"

# ── (5) The adjacent item slices correctly too (boundary from the other side) ───────────────
O2="$TMP/two.md"
slice_one 2222 "$O2" >/dev/null
grep -q 'NEXT_ITEM_MARKER' "$O2" \
  && ok "the adjacent item slices its own line" \
  || bad "id:b015: slicing id:2222 lost its own line"
grep -q 'COL0_PROSE_MARKER' "$O2" \
  && bad "id:b015: slicing id:2222 pulled in the PREVIOUS item's column-0 prose" \
  || ok "the adjacent item does not absorb the previous item's continuation"
grep -q 'Parked (exempt per id:356f)' "$O2" \
  && ok "adjacent item carries the same owning section heading" \
  || bad "id:b015: adjacent item's owning heading missing"

# ── (6) Heading capture tracks the CURRENT section, not the first one ───────────────────────
O3="$TMP/three.md"
slice_one 3333 "$O3" >/dev/null
grep -q 'Another section' "$O3" \
  && ok "an item in a later section is stamped with THAT section's heading" \
  || bad "id:b015: heading stamp is not the item's own section"
grep -q 'Parked (exempt per id:356f)' "$O3" \
  && bad "id:b015: item three stamped with the WRONG (earlier) section heading" \
  || ok "heading stamp is not a stale earlier heading"

# ── (7) The id:35b7 stdout contract survives: measured slice-bytes first, path LAST ─────────
first="$(head -1 <<<"$out1")"
last_line="$(printf '%s\n' "$out1" | grep -v '^[[:space:]]*$' | tail -1)"
real=$(wc -c < "$O1" | tr -d '[:space:]')
if [[ "$first" == "slice-bytes: $real" ]]; then
  ok "slice-bytes is MEASURED on the written file (${real} B)"
else
  bad "id:b015: slice-bytes line is '$first', expected 'slice-bytes: $real' (measured with wc -c)"
fi
if [[ "$last_line" == "$O1" ]]; then
  ok "the slice PATH is still the last non-empty stdout line"
else
  bad "id:b015: last stdout line is '$last_line', expected the slice path $O1"
fi

echo "---"
echo "summary: $pass ok, $fail bad"
[[ "$fail" -eq 0 ]] || exit 1
echo "ALL PASS: ledger-slice.sh bounds blocks by checkbox/heading and stamps the section (id:b015)"
