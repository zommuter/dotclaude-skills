#!/usr/bin/env bash
# No roadmap header -- this is a defect-fix spec for TODO id:2ee1, filed directly into the
# design ledger from meeting note `docs/meeting-notes/2026-09-01-2226-ledger-line-shrink-format.md`
# (the `--fabled` closing pass, forced amendment 1). Failures always count.
#
# id:2ee1 -- `relay/scripts/ledger-slice.sh` (id:e68f) is how every dispatched relay child gets
# its work spec: it extracts the dispatched item's own block and hands the child that slice.
# The ratified ledger line-shrink (D3) MOVES an item's prose body out of the ledger line into a
# per-id detail file at `docs/ledger-notes/<id>.md`, leaving a slim head line plus a pointer.
# The slicer does not follow that pointer, so post-shrink a child receives a well-formed,
# non-empty, honest-byte-count slice that is MISSING its acceptance criteria -- verbatim the
# id:b015 failure the slicer's own header describes ("nothing failed: the child simply worked a
# spec missing its acceptance criteria").
#
# Contract asserted here:
#   A. An item whose body was relocated gets a slice CONTAINING the acceptance criteria from
#      the detail file -- equivalent in content to the pre-shrink slice (checked against a
#      pre-shrink fixture of the same item, not just against a hard-coded string).
#   B. An item with NO pointer behaves EXACTLY as today: its Dispatched-item section is the
#      fixture block verbatim, with no inlined section and no notes-dir mention anywhere in the
#      slice. This is the common case and the regression guard.
#   C. A pointer naming a MISSING detail file fails LOUDLY -- non-zero exit plus stderr naming
#      the path -- and never silently emits a short slice. Under-delivering loudly is safe;
#      silently is the whole defect class (id:4347 no-silent-swallow).
#   D. The reported `slice-bytes:` accounts for the inlined content: it equals the written
#      file's real size AND is at least the detail file's own size (the downstream prompt-size
#      gate, relay/scripts/prompt-size-gate.mjs, keys on that number).
#   E. The multi-id path (`--ids`, the review form) inlines too, including for a TODO-only id
#      that owns no ROADMAP line.
#
# fails-against: the defect and its fix land in the SAME commit as this spec, so there is no
# ancestor tree to check out; both negative cases below are mutations of the shipped script.
# Case 1 neuters the missing-file guard so a dangling pointer degrades to a silently short
# slice (the pre-fix behaviour for that shape) -- it fires exactly the C rc assertion, since
# the stderr line is still printed. Case 2 neuters the inlining itself, which is the pre-fix
# behaviour outright: it fires four assertions -- D2 (byte count), A (single-id content) and
# both E assertions -- of which the LAST is the TODO-only multi-id one, so that is what is
# declared, per the runner's last-fired rule.
# fails-against-mutation: sed -i '/id:2ee1 MISSING-GUARD/s/exit 7/return 0/' relay/scripts/ledger-slice.sh
# fails-against-assertion: case C: a pointer to a MISSING detail file must fail LOUDLY
# fails-against-mutation: sed -i '/id:2ee1 INLINE/s/^/#/' relay/scripts/ledger-slice.sh
# fails-against-assertion: case E: the --ids slice must inline a TODO-ONLY item's detail file
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SLICE="$ROOT/relay/scripts/ledger-slice.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0
report() { echo "FAIL: $1"; fail=1; }

# ---------------------------------------------------------------------------
# Fixtures. Two repos of the SAME items: `post` has aa01's body relocated behind a
# pointer, `pre` has it inline. Contract A is "the post-shrink slice is equivalent in
# content to the pre-shrink slice", so the criteria text is taken FROM the pre-shrink
# fixture rather than asserted as a literal in two places.
# ---------------------------------------------------------------------------
CRITERIA='ACCEPTANCE: the child must run `make test` green and tick the ROADMAP checkbox before handing back.'
# Padding so the detail file is comfortably larger than a pointer-less slice; contract D2
# compares the reported byte count against it.
PAD="$(for i in $(seq 1 40); do echo "  - relocated rationale line $i: this prose used to sit on the ledger head line."; done)"

post="$tmp/post"; pre="$tmp/pre"
mkdir -p "$post/docs/ledger-notes" "$pre"

# aa01 -- body relocated behind a pointer (the post-shrink shape).
# aa02 -- NO pointer, body inline (the regression guard; must not change).
# aa03 -- pointer to a detail file that does not exist (the loud-failure case).
cat > "$post/ROADMAP.md" <<'EOF'
# ROADMAP

## Current

- [ ] [ROUTINE] **Pointered item** -- detail: `docs/ledger-notes/aa01.md` <!-- id:aa01 -->
- [ ] [ROUTINE] **Plain item** <!-- id:aa02 -->
  - acceptance: the plain item keeps its inline body, indented and all
  ACCEPTANCE-PLAIN: a column-0 continuation paragraph that must survive verbatim (id:b015)
- [ ] [ROUTINE] **Dangling pointer item** -- detail: `docs/ledger-notes/aa03.md` <!-- id:aa03 -->
EOF

cat > "$post/TODO.md" <<'EOF'
# TODO

## Current

- [ ] [ROUTINE] **Pointered item** -- detail: `docs/ledger-notes/aa01.md` <!-- id:aa01 -->
- [ ] [ROUTINE] **Plain item** <!-- id:aa02 -->
- [ ] [ROUTINE] **TODO-only pointered item** -- detail: `docs/ledger-notes/aa04.md` <!-- id:aa04 -->
EOF

{
  echo "# id:aa01"
  echo
  echo "## From ROADMAP"
  echo
  echo "$CRITERIA"
  echo
  echo "$PAD"
} > "$post/docs/ledger-notes/aa01.md"

{
  echo "# id:aa04"
  echo
  echo "## From TODO"
  echo
  echo "ACCEPTANCE-AA04: the TODO-only item's relocated criteria must reach the child too."
} > "$post/docs/ledger-notes/aa04.md"

# The pre-shrink twin of aa01: same item, body still on/under the ledger line.
{
  echo "# ROADMAP"
  echo
  echo "## Current"
  echo
  echo "- [ ] [ROUTINE] **Pointered item** <!-- id:aa01 -->"
  echo
  echo "$CRITERIA"
} > "$pre/ROADMAP.md"
{
  echo "# TODO"
  echo
  echo "## Current"
  echo
  echo "- [ ] [ROUTINE] **Pointered item** <!-- id:aa01 -->"
} > "$pre/TODO.md"

run_slice() { # <repo> <out> <selector-flag> <selector-value>
  local repo="$1" out="$2" flag="$3" val="$4"
  set +e
  HOME="$tmp" RELAY_SLICE_DIR="$tmp/cache" \
    "$SLICE" --repo fixture --path "$repo" "$flag" "$val" --out "$out" \
    > "$tmp/out.txt" 2> "$tmp/err.txt"
  local rc=$?
  set -e
  return $rc
}

# ---------------------------------------------------------------------------
# (D) byte accounting FIRST, so it is never the last-fired assertion when the
#     content assertion (A) also fires. See the fails-against block above.
# ---------------------------------------------------------------------------
rc=0; run_slice "$post" "$tmp/slice-aa01.md" --id aa01 || rc=$?
if (( rc != 0 )); then
  report "case A/D: ledger-slice.sh exited $rc on a pointered item -- $(head -3 "$tmp/err.txt" | tr '\n' ' ')"
else
  reported="$(awk '/^slice-bytes: /{sub(/^slice-bytes: /, ""); print; exit}' "$tmp/out.txt")"
  actual="$(wc -c < "$tmp/slice-aa01.md" | tr -d '[:space:]')"
  detail_bytes="$(wc -c < "$post/docs/ledger-notes/aa01.md" | tr -d '[:space:]')"
  [[ "$reported" == "$actual" ]] \
    || report "case D1: reported slice-bytes ($reported) must equal the written slice's real size ($actual)"
  if [[ -n "$reported" ]] && (( reported < detail_bytes )); then
    report "case D2: reported slice-bytes ($reported) is below the inlined detail file's own size ($detail_bytes) -- the byte count does not account for the inlined content, so the prompt-size gate reads low"
  fi

  # (A) the defect itself: the relocated acceptance criteria must be IN the slice.
  # Equivalence is checked against the pre-shrink slice of the same item, so the
  # assertion is "same content as before the shrink", not a hand-copied literal.
  rc2=0; run_slice "$pre" "$tmp/slice-pre.md" --id aa01 || rc2=$?
  if (( rc2 != 0 )); then
    report "case A: could not slice the PRE-shrink fixture (rc=$rc2) -- the equivalence baseline is unusable"
  else
    grep -qF -- "$CRITERIA" "$tmp/slice-aa01.md" \
      || report "case A: the slice must contain the acceptance criteria relocated into docs/ledger-notes/aa01.md"
    grep -qF -- "$CRITERIA" "$tmp/slice-pre.md" \
      || report "case A: sanity -- the PRE-shrink slice does not carry the criteria either, so the fixture proves nothing"
  fi
fi

# ---------------------------------------------------------------------------
# (B) regression guard: an item with NO pointer must behave exactly as today.
# ---------------------------------------------------------------------------
rc=0; run_slice "$post" "$tmp/slice-aa02.md" --id aa02 || rc=$?
if (( rc != 0 )); then
  report "case B: ledger-slice.sh exited $rc on a pointer-less item -- $(head -3 "$tmp/err.txt" | tr '\n' ' ')"
else
  # Everything between the two section headings, with leading blank lines dropped
  # (command substitution already drops the trailing ones).
  got="$(awk '/^## Dispatched item \(ROADMAP\.md\)$/{f=1;next} /^## Typed edges$/{f=0} f' "$tmp/slice-aa02.md" \
          | sed -e '/./,$!d')"
  want="$(cat <<'EOF'
- [ ] [ROUTINE] **Plain item** <!-- id:aa02 -->
  - acceptance: the plain item keeps its inline body, indented and all
  ACCEPTANCE-PLAIN: a column-0 continuation paragraph that must survive verbatim (id:b015)
EOF
)"
  [[ "$got" == "$want" ]] \
    || report "case B: a pointer-less item's Dispatched-item section changed. got:<<<$got>>> want:<<<$want>>>"
  grep -q 'ledger-notes' "$tmp/slice-aa02.md" \
    && report "case B: a pointer-less item's slice must not mention the detail-notes tree at all"
fi

# ---------------------------------------------------------------------------
# (C) a pointer to a MISSING detail file must fail LOUDLY, never emit a short slice.
# ---------------------------------------------------------------------------
rm -- "$tmp/out.txt" "$tmp/err.txt" 2>/dev/null || true
rc=0; run_slice "$post" "$tmp/slice-aa03.md" --id aa03 || rc=$?
grep -q 'docs/ledger-notes/aa03.md' "$tmp/err.txt" \
  || report "case C: stderr must NAME the missing detail file (got: $(head -2 "$tmp/err.txt" | tr '\n' ' '))"
(( rc != 0 )) \
  || report "case C: a pointer to a MISSING detail file must fail LOUDLY (non-zero exit); got rc=0 and a slice the child would read as a complete spec"

# ---------------------------------------------------------------------------
# (E) the multi-id (review) path inlines too, including for a TODO-only id.
# ---------------------------------------------------------------------------
rc=0; run_slice "$post" "$tmp/slice-multi.md" --ids aa01,aa02,aa04 || rc=$?
if (( rc != 0 )); then
  report "case E: ledger-slice.sh exited $rc on the multi-id path -- $(head -3 "$tmp/err.txt" | tr '\n' ' ')"
else
  grep -qF -- "$CRITERIA" "$tmp/slice-multi.md" \
    || report "case E: the --ids slice must inline a dispatched item's detail file"
  grep -qF -- 'ACCEPTANCE-AA04' "$tmp/slice-multi.md" \
    || report "case E: the --ids slice must inline a TODO-ONLY item's detail file (it owns no ROADMAP line but is still worked)"
fi

if (( fail )); then
  exit 1
fi
echo "PASS: ledger-slice.sh inlines the pointed-to docs/ledger-notes/<id>.md detail file, unchanged without a pointer, loud on a missing one (id:2ee1)"
