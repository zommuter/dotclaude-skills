#!/usr/bin/env bash
# No roadmap header -- this is a defect-fix spec for TODO id:0d7c, filed from meeting note
# `docs/meeting-notes/2026-09-01-2226-ledger-line-shrink-format.md` (the ratified format plus
# its post-closure Amendment session). Failures always count.
#
# id:0d7c -- `tools/ledger-shrink.py` moves an over-long ledger item's PROSE BODY off the head
# line into `docs/ledger-notes/<id>.md`. The head line is a CONTROL SURFACE, not prose:
# `classify-repo.sh` matches gate markers as UNANCHORED SUBSTRINGS over the whole raw line, the
# lane tag routes dispatch, and the `<!-- id:XXXX -->` anchor is what makes the item addressable.
# A marker that moves becomes invisible to dispatch -- the id:d35a silent-no-op class.
#
# Contract asserted here:
#   A. DRY RUN is the default and writes nothing at all.
#   B. Every keep-set marker sitting AFTER the cut point survives on the head line: the lane
#      tag (which the loderite reference preserves only by POSITION, not by rule), the id
#      anchor, `<!-- routed:XXXX -->` (59 of these sit after the cut point in this repo's two
#      ledgers, and `append.sh inbox-done` anchors its twin-check on that exact form), the
#      typed and bare `gated-on:` edges, the construction-sign glyph, `@manual`, `@wire`,
#      `@owner-verify`, `@needs-auth`, `@container`, `@owner-gated`, `@owner-answered:` and
#      both spellings of the blocked lexeme.
#   C. The relocated prose is BYTE-IDENTICAL to what left the ledger line.
#   D. An item whose block carries ANOTHER item's `<!-- id:XXXX -->` is REFUSED outright.
#      loderite measured four ids (89f9, a5b6, ba07, ed26) silently orphaned exactly this way:
#      the body survived in the note file, the ADDRESS did not, and nothing failed loudly.
#   E. An item with NO bold run still shrinks, via the fallback cut point. Measured on this
#      repo: 150 of 674 TODO items and 43 of 127 ROADMAP items have no bold run, so without a
#      fallback the ratified ratchet would demand a cut the tool refuses to make.
#   F. Re-running is idempotent: ledger and note files byte-identical, nothing appended twice.
#   G. Detail files use the LOGICAL ledger name (`## From TODO`), never the physical path,
#      and contain no em dash or en dash anywhere.
#
# fails-against: the tool and this spec land in the SAME commit, so there is no ancestor tree
# to check out; both negative cases are mutations of the shipped tool.
# Case 1 removes the lane patterns from the keep-set, which is precisely the gap in the
# loderite reference (it preserves the lane tag only by position); it fires exactly the case B
# lane assertion, because the fixture deliberately places the lane bracket AFTER the cut point.
# Case 2 neuters the foreign-id refusal, which is the loderite silent-orphan behaviour outright;
# it fires exactly the case D assertion, which is a single combined check for that reason.
# fails-against-mutation: sed -i 's/ + _LANE_PATTERNS  # KEEP-LANE//' tools/ledger-shrink.py
# fails-against-assertion: case B: the LANE TAG must survive on the head line
# fails-against-mutation: sed -i '/FOREIGN-ID-GUARD/s/if foreign:/if False:/' tools/ledger-shrink.py
# fails-against-assertion: case D: an item whose block carries ANOTHER item's id marker
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHRINK="$ROOT/tools/ledger-shrink.py"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0
report() { echo "FAIL: $1"; fail=1; }

repo="$tmp/repo"
mkdir -p "$repo"

# ---------------------------------------------------------------------------
# Fixture. bb01's keep-set markers all sit AFTER the cut point (the end of the first bold
# run) on purpose: that is the only arrangement under which "keep by rule" and "keep by
# position" give different answers.
# ---------------------------------------------------------------------------
BB01_PREFIX='- [ ] **Keep-set survivor item**'
BB01_REST=' [HARD - pool] this prose is what must move, and it is comfortably longer than the forty-character floor the splitter enforces before it will cut anything at all. gated-on:cc10 and a typed edge <!-- gated-on:cc11 --> plus 🚧 and `@manual` and @wire and @owner-verify and @needs-auth and @container and @owner-gated and @owner-answered:2026-08-14 and BLOCKED on the other thing and blocked on the lowercase thing. <!-- routed:dd20 --> <!-- id:bb01 -->'

BB04_PREFIX='- [ ] [ROUTINE] A plain title carrying no bold run at all'
BB04_REST=' -- and then a body of prose that is long enough to be worth relocating, which is the whole point of the fallback cut point for the one hundred and ninety three bold-less items measured across the two ledgers. <!-- id:bb04 -->'

{
  echo '# TODO'
  echo
  echo '## Current'
  echo
  echo "${BB01_PREFIX}${BB01_REST}"
  echo "- [ ] **Foreign id block item** carries a sub-annotation with an id of its own, and this head line is padded well past the candidate threshold so that only the refusal rule can keep it from being split. <!-- id:bb02 -->"
  echo "  - **A sub annotation** that cannot be promoted and must never be relocated <!-- id:bb03 -->"
  echo "${BB04_PREFIX}${BB04_REST}"
  echo '- [ ] [ROUTINE] **Short item** left alone <!-- id:bb05 -->'
  echo '- [x] **Closed item** with a body long enough to be a candidate were it open, padded here so the open-only rule is what excludes it rather than its length. <!-- id:bb06 -->'
} > "$repo/TODO.md"

cp "$repo/TODO.md" "$tmp/TODO.orig"

run() { # <args...>  -> stdout in $tmp/out.txt, stderr in $tmp/err.txt
  set +e
  python3 "$SHRINK" --root "$repo" "$@" > "$tmp/out.txt" 2> "$tmp/err.txt"
  local rc=$?
  set -e
  return $rc
}

# ---------------------------------------------------------------------------
# (A) dry run is the default and writes nothing.
# ---------------------------------------------------------------------------
rc=0; run --file TODO.md --min-chars 200 || rc=$?
if (( rc != 0 )); then
  report "case A: the default (dry-run) invocation exited $rc -- $(head -3 "$tmp/err.txt" | tr '\n' ' ')"
fi
cmp -s "$repo/TODO.md" "$tmp/TODO.orig" \
  || report "case A: the default invocation MUTATED the ledger; nothing may be written without --apply"
[[ -d "$repo/docs/ledger-notes" ]] \
  && report "case A: the default invocation created docs/ledger-notes/; a dry run writes nothing"
grep -q 'dry run' "$tmp/out.txt" \
  || report "case A: a dry run must say so on stdout (got: $(tail -2 "$tmp/out.txt" | tr '\n' ' '))"

# ---------------------------------------------------------------------------
# Apply.
# ---------------------------------------------------------------------------
rc=0; run --file TODO.md --min-chars 200 --apply || rc=$?
if (( rc != 0 )); then
  report "case B/C: --apply exited $rc -- $(head -3 "$tmp/err.txt" | tr '\n' ' ')"
fi

bb01_head="$(grep -F -- 'Keep-set survivor item' "$repo/TODO.md" || true)"

# (B) every keep-set marker that sat AFTER the cut point must still be on the head line.
# The lane tag is asserted on its own: it is the marker the reference implementation keeps
# only by position, so it is the one a keep-by-rule regression drops first.
case "$bb01_head" in
  *'[HARD - pool]'*) : ;;
  *) report "case B: the LANE TAG must survive on the head line by RULE, not by position -- got: ${bb01_head:0:160}" ;;
esac
for marker in '<!-- id:bb01 -->' '<!-- routed:dd20 -->' 'gated-on:cc10' '<!-- gated-on:cc11 -->' \
              '🚧' '@manual' '@wire' '@owner-verify' '@needs-auth' '@container' \
              '@owner-gated' '@owner-answered:2026-08-14' 'BLOCKED on' 'blocked on'; do
  case "$bb01_head" in
    *"$marker"*) : ;;
    *) report "case B: keep-set marker '$marker' was relocated off the head line; detectors grep the LINE" ;;
  esac
done
if [[ -n "$bb01_head" ]] && (( ${#bb01_head} >= ${#BB01_PREFIX} + ${#BB01_REST} )); then
  report "case B: the head line did not get shorter (${#bb01_head} chars); nothing was actually relocated"
fi
case "$bb01_head" in
  *'docs/ledger-notes/bb01.md'*) : ;;
  *) report "case B: the slimmed head must carry a pointer to docs/ledger-notes/bb01.md" ;;
esac

# (C) the relocated prose is byte-identical to what left the line.
note="$repo/docs/ledger-notes/bb01.md"
if [[ ! -f "$note" ]]; then
  report "case C: no detail file was written at docs/ledger-notes/bb01.md"
else
  expected="$(printf '%s' "$BB01_REST" | sed -e 's/^ *//' -e 's/ *$//')"
  grep -qF -- "$expected" "$note" \
    || report "case C: the relocated prose is not BYTE-IDENTICAL to the text that left the ledger line"
  # (G) provenance is the LOGICAL ledger, never the physical path (which goes stale the
  # moment archive-done.sh moves the line into TODO.archive.md).
  grep -qx -- '## From TODO' "$note" \
    || report "case G: the detail file must be sectioned by LOGICAL ledger ('## From TODO'), not by physical path"
fi

# (G) no em dash or en dash anywhere in generated output.
if grep -rlP '[\x{2013}\x{2014}]' "$repo/docs/ledger-notes" >/dev/null 2>&1; then
  report "case G: generated detail files contain an em dash or en dash (hard style ban)"
fi
if grep -qP '[\x{2013}\x{2014}]' <<<"$bb01_head"; then
  report "case G: the generated pointer/head line contains an em dash or en dash (hard style ban)"
fi

# ---------------------------------------------------------------------------
# (D) foreign id marker in the block => REFUSE. One combined assertion on purpose: the
# ledger line must be untouched AND no detail file may exist for it.
# ---------------------------------------------------------------------------
bb02_now="$(grep -F -- 'Foreign id block item' "$repo/TODO.md" || true)"
bb02_was="$(grep -F -- 'Foreign id block item' "$tmp/TODO.orig" || true)"
if [[ "$bb02_now" != "$bb02_was" || -f "$repo/docs/ledger-notes/bb02.md" ]]; then
  report "case D: an item whose block carries ANOTHER item's id marker must be REFUSED and left byte-identical (loderite silently orphaned 4 ids this way); line changed=$([[ "$bb02_now" != "$bb02_was" ]] && echo yes || echo no), note written=$([[ -f "$repo/docs/ledger-notes/bb02.md" ]] && echo yes || echo no)"
fi
grep -F -- '<!-- id:bb03 -->' "$repo/TODO.md" >/dev/null \
  || report "case D2: the sub-annotation's own id marker left the ledger; that id is now unaddressable"

# ---------------------------------------------------------------------------
# (E) fallback cut point for an item with no bold run.
# ---------------------------------------------------------------------------
bb04_head="$(grep -F -- 'A plain title carrying no bold run' "$repo/TODO.md" || true)"
case "$bb04_head" in
  *'docs/ledger-notes/bb04.md'*) : ;;
  *) report "case E: an item with NO bold run must still shrink via the fallback cut point -- got: ${bb04_head:0:160}" ;;
esac
case "$bb04_head" in
  *'[ROUTINE]'*'<!-- id:bb04 -->'*) : ;;
  *) report "case E: the fallback split must keep the lane tag and the id anchor on the line" ;;
esac

# Short and closed items are untouched.
grep -qF -- '- [ ] [ROUTINE] **Short item** left alone <!-- id:bb05 -->' "$repo/TODO.md" \
  || report "case E2: an under-budget item must be left byte-identical"
grep -qF -- '<!-- id:bb06 -->' "$repo/TODO.md" \
  || report "case E3: a CLOSED item must be left alone (its body belongs to the archiver)"

# ---------------------------------------------------------------------------
# (F) idempotence.
# ---------------------------------------------------------------------------
cp "$repo/TODO.md" "$tmp/TODO.after1"
cp "$note" "$tmp/note.after1" 2>/dev/null || true
rc=0; run --file TODO.md --min-chars 200 --apply || rc=$?
(( rc == 0 )) || report "case F: the second --apply exited $rc"
cmp -s "$repo/TODO.md" "$tmp/TODO.after1" \
  || report "case F: a second --apply changed the ledger; the pointer guard is not idempotent"
if [[ -f "$tmp/note.after1" ]]; then
  cmp -s "$note" "$tmp/note.after1" \
    || report "case F: a second --apply appended to the detail file again; the body was duplicated"
fi
grep -q 'items to shrink       : 0' "$tmp/out.txt" \
  || report "case F: the second run must report 0 items to shrink (got: $(grep 'items to shrink' "$tmp/out.txt" || echo none))"

if (( fail )); then
  exit 1
fi
echo "PASS: ledger-shrink.py slims over-long head lines, keeps every gate/lane/id/routed marker on the LINE, refuses foreign-id blocks, falls back without a bold run, and is idempotent (id:0d7c)"
