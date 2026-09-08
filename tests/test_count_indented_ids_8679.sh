#!/usr/bin/env bash
# roadmap:8679
#
# THE ITEM (id:8679). Three figures for ONE population were on record and none was
# reproducible: 11 (the 2026-09-01 ruling, owner-marked UNVERIFIED), 21 (measured the same
# day), 10 (measured 2026-09-02). Each came from a different ad-hoc grep against a different
# tree, so they were never comparable -- and a promote pass sized off the wrong one silently
# skips real items, which is the shape that orphaned four ids in a peer repo.
#
# `tools/count-indented-ids.py` is the committed counting rule that replaces those greps.
# This file pins the four discriminations that every ad-hoc grep got wrong, plus the
# historical reproduction that makes the reconciliation checkable rather than asserted.
#
# Cases A-F are hermetic (mktemp fixtures only, no live ledger, no network). Case G reads
# THIS repo's own git history through `--rev`, because the whole point of the item is that a
# count is meaningless without its as-of commit; it SKIPS loudly, naming the reason, if the
# two revisions are absent (shallow clone).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COUNT="$ROOT/tools/count-indented-ids.py"

rc=0
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; rc=1; }

[[ -f "$COUNT" ]] || { echo "FAIL: setup: count-indented-ids.py not found at $COUNT"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf -- "$TMP"' EXIT

# `--root` is only used to resolve the file path and the revision, so a bare directory is a
# complete fixture. json output keeps the assertions on structured fields, not on formatting.
jq_get() {  # $1 = json, $2 = python expression over `d`
  printf '%s' "$1" | python3 -c "import json,sys; d=json.load(sys.stdin); print($2)"
}

run() {  # $1 = fixture body -> echoes the json report
  printf '%s\n' "$1" > "$TMP/TODO.md"
  python3 "$COUNT" --root "$TMP" --file TODO.md --json
}

# ---------------------------------------------------------------- (A) checkbox sub-item
OUT="$(run '- [ ] a top-level item <!-- id:aaaa -->
  - [ ] an indented CHECKBOX sub-item with its own anchor <!-- id:bbbb -->')"
got="$(jq_get "$OUT" 'd["totals"]["addressable"], d["totals"]["addressable_checkbox"]' | tr '\n' ' ')"
[[ "$got" == "1 1 " ]] \
  && pass "(A) an indented checkbox sub-item counts as addressable AND as checkbox" \
  || fail "(A) indented checkbox sub-item miscounted: addressable/checkbox = $got, want 1 1"

# ---------------------------------------------------------------- (B) non-checkbox line
# A bolded sub-heading with an anchor is addressable but has NOTHING TO PROMOTE. Collapsing
# this distinction is exactly how 11 and 21 came to name the same population.
OUT="$(run '- [ ] a top-level item <!-- id:aaaa -->
  - **A bolded sub-heading carrying an anchor** <!-- id:cccc -->')"
got="$(jq_get "$OUT" 'd["totals"]["addressable"], d["totals"]["addressable_checkbox"]' | tr '\n' ' ')"
[[ "$got" == "1 0 " ]] \
  && pass "(B) an indented NON-checkbox anchored line is addressable but not promotable" \
  || fail "(B) non-checkbox line miscounted: addressable/checkbox = $got, want 1 0"

# ---------------------------------------------------------------- (C) backticked = prose
# id:2964's mask half. An item ABOUT marker syntax quotes an anchor; that is a mention, not
# an address, and counting it inflates the population with lines no promote pass can move.
OUT="$(run '- [ ] a top-level item <!-- id:aaaa -->
  - prose explaining that the anchor is spelled `<!-- id:dddd -->` and nothing else')"
got="$(jq_get "$OUT" 'd["totals"]["indented_anchored"]')"
[[ "$got" == "0" ]] \
  && pass "(C) an anchor QUOTED inside an inline-code span is not counted" \
  || fail "(C) backticked anchor was counted: indented_anchored = $got, want 0"

# ---------------------------------------------------------------- (D) multi-marker line
# id:6059: md-merge.py and lib-typed-edges.sh both REFUSE a multi-marker line -- it resolves
# to nothing. Such a line carries no id OF ITS OWN, so it must never swell `addressable`.
OUT="$(run '- [ ] a top-level item <!-- id:aaaa -->
  - a reconciliation line naming several items <!-- id:eeee --> <!-- id:ffff -->')"
got="$(jq_get "$OUT" 'd["totals"]["addressable"], d["totals"]["unaddressable"]' | tr '\n' ' ')"
[[ "$got" == "0 1 " ]] \
  && pass "(D) a line with two anchors is unaddressable, never addressable" \
  || fail "(D) multi-marker line miscounted: addressable/unaddressable = $got, want 0 1"

# ---------------------------------------------------------------- (E) top-level excluded
OUT="$(run '- [ ] a top-level item <!-- id:aaaa -->')"
got="$(jq_get "$OUT" 'd["totals"]["indented_anchored"]')"
[[ "$got" == "0" ]] \
  && pass "(E) a column-0 item line is a different population and is excluded" \
  || fail "(E) top-level item was counted: indented_anchored = $got, want 0"

# ---------------------------------------------------------------- (F) fenced block
OUT="$(run '- [ ] a top-level item <!-- id:aaaa -->

```
  - [ ] documentation OF the grammar, not an instance of it <!-- id:9999 -->
```')"
got="$(jq_get "$OUT" 'd["totals"]["indented_anchored"]')"
[[ "$got" == "0" ]] \
  && pass "(F) an anchored line inside a fenced block is documentation, not an instance" \
  || fail "(F) fenced-block line was counted: indented_anchored = $got, want 0"

# ---------------------------------------------------------------- (G) the reconciliation
# THE POINT OF THE ITEM: one committed command reproduces all three recorded figures from
# named commits. 21 = 19 addressable + 2 unaddressable at c63c7f20 (2026-09-01 23:38, the
# state the meeting note measured); 11 = the checkbox subset of those 19, which is exactly
# what e6e3ff70 promoted to column 0 minutes later; 10 = 8 + 2, the untouched remainder,
# which every shrink wave since has left invariant.
REVS_OK=1
for r in c63c7f20 e6e3ff70; do
  git -C "$ROOT" cat-file -e "$r^{commit}" 2>/dev/null || REVS_OK=0
done
if [[ "$REVS_OK" == "0" ]]; then
  echo "SKIP: (G) reconciliation replay -- revisions c63c7f20/e6e3ff70 absent from this" \
       "checkout (shallow clone?); the hermetic cases A-F still bound the rule"
else
  OUT="$(python3 "$COUNT" --root "$ROOT" --file TODO.md --rev c63c7f20 --json)"
  got="$(jq_get "$OUT" 'd["totals"]["addressable"], d["totals"]["addressable_checkbox"], d["totals"]["indented_anchored"]' | tr '\n' ' ')"
  [[ "$got" == "19 11 21 " ]] \
    && pass "(G1) c63c7f20 reproduces 21 anchored, of which 11 are the promotable checkboxes" \
    || fail "(G1) c63c7f20 gave addressable/checkbox/anchored = $got, want 19 11 21"

  OUT="$(python3 "$COUNT" --root "$ROOT" --file TODO.md --rev e6e3ff70 --json)"
  got="$(jq_get "$OUT" 'd["totals"]["addressable"], d["totals"]["addressable_checkbox"], d["totals"]["indented_anchored"]' | tr '\n' ' ')"
  [[ "$got" == "8 0 10 " ]] \
    && pass "(G2) e6e3ff70 reproduces 10 anchored with the 11 checkboxes promoted away" \
    || fail "(G2) e6e3ff70 gave addressable/checkbox/anchored = $got, want 8 0 10"
fi

# ---------------------------------------------------------------- (H) the anti-drift gate
# A counting rule nobody can assert against drifts back into ad-hoc greps. `--expect` is the
# gate a promote pass or a future ruling calls; it must be LOUD (exit 2), not advisory.
printf '%s\n' '- [ ] top <!-- id:aaaa -->
  - [ ] one indented sub-item <!-- id:bbbb -->' > "$TMP/TODO.md"
python3 "$COUNT" --root "$TMP" --file TODO.md --expect 1 >/dev/null 2>&1
[[ $? -eq 0 ]] \
  && pass "(H1) --expect exits 0 when the population matches" \
  || fail "(H1) --expect 1 did not exit 0 on a matching population"
python3 "$COUNT" --root "$TMP" --file TODO.md --expect 2 >/dev/null 2>&1
[[ $? -eq 2 ]] \
  && pass "(H2) --expect exits 2 (loud) on drift" \
  || fail "(H2) --expect 2 did not exit 2 on a mismatching population"

exit "$rc"
