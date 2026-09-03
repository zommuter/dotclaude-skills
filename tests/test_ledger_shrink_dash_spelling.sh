#!/usr/bin/env bash
# Defect-fix test -- NO `# roadmap:` header on purpose, so its failures ALWAYS count.
#
# THREE changes are pinned here, so THREE declarations. The independent review (2026-09-03)
# found that only change (1) was declared, so the runner would never have re-verified (2) or
# (3) again -- it confirmed both are live by mutating them BY HAND. A hand-verified assertion
# is one nobody re-runs; declaring it is what makes the guarantee survive its author.
# fails-against-mutation: sed -i 's|_SEP_RE = re.compile(r" " + _DASH + r"{1,2} ")|_SEP_RE = re.compile(r" -- ")|' tools/ledger-shrink.py
# fails-against-assertion: (1) the em-dash-separated item was NOT shrunk
# fails-against-mutation: python3 -c "p='tools/ledger-shrink.py';s=open(p).read();L=[l for l in s.split(chr(10)) if 're.finditer' in l and 'text' in l and '<!--' not in l and chr(96) not in l];assert len(L)==1,L;s=s.replace(L[0],'    for m in []:',1);open(p,'w').write(s)"
# fails-against-assertion: (2) the cut landed inside a bracket group
# fails-against-mutation: sed -i 's|return None, None, "no-net-shrink"|pass|' tools/ledger-shrink.py
# fails-against-assertion: (3) a no-net-shrink split was applied
#   The mutation restores the ASCII-only separator, which is the pre-fix spelling. The
#   fixture line then offers find_cut no bold run, no ASCII ` -- ` and no sentence boundary,
#   so it falls through to the anchor last-resort, leaves 0 residue and refuses with
#   `too-little-to-move` -- nothing shrinks, which is assertion (1). The declared text is the
#   FAIL branch's wording and occurs exactly once in the body; the PASS branch reads
#   "(1) the em-dash-separated item SHRANK", a different string. `fail()` exits, so the first
#   line-leading FAIL: is also the last.
#
# THE DEFECT (measured 2026-09-03 on the live TODO.md).
#
# `find_cut()`'s no-bold-run fallback looked for the separator ` -- ` in ASCII ONLY, while
# the module's own `_DASH` constant already declares that the fleet is mid-migration off the
# em/en dash and that the detectors match BOTH spellings when reading. Of the 63 open
# TODO.md items carrying no detail pointer, 42 offered find_cut NO candidate at all: no bold
# run, no ASCII ` -- `, and no sentence boundary either, because their only periods sit
# inside filenames (`SKILL.md documents`, `archive-done.sh`). 39 of those 42 have a spaced em
# dash exactly where the title ends. The ASCII-only rule therefore refused precisely the
# population it was most needed for -- historical `[INBOUND routed:...]` prose written before
# the dash ban -- and reported it as "under 25 chars would move", which is true and
# completely misleading.
#
# TWO GUARDS SHIP WITH THAT WIDENING, and they are the reason it is safe:
#
#   (b) BRACKET RUNS ARE PROTECTED SPANS. A lane tag CONTAINS the separator the fallback
#       cuts on. Measured on `id:2884`: its body says `... -> valid [HARD <dash> <lane>]`
#       with no backticks, and the first spaced dash on the line sits between `[HARD` and
#       `<lane>]`. Cutting there leaves an unbalanced `[HARD` on the head and carries the
#       rest of the tag into the note -- a mangled control surface, strictly worse than the
#       long line. No cut ever wants to land inside a bracket group.
#
#   (c) THE HEAD MUST ACTUALLY SHRINK. `MIN_MOVED_CHARS` measures what LEAVES and says
#       nothing about what the split COSTS. The pointer is ~45 chars, so a 40-char move makes
#       the line LONGER. Both outcomes were produced against the live ledger before this
#       guard: `id:625a` went 349 -> 355 and `id:cb1c` 356 -> 356, each buying an indirection
#       for no byte win.
#
# Hermetic: mktemp only, no live ledger, no network.
#
# NOTE ON THE FIXTURE SPELLING: this file contains no literal em dash (fleet style rule);
# the character is built with a `\u` escape, exactly as tools/ledger-shrink.py builds `_DASH`.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHRINK="$ROOT/tools/ledger-shrink.py"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$SHRINK" ]] || fail "sanity: ledger-shrink.py not found at $SHRINK"

EM=$'—'

TMP="$(mktemp -d)"; trap 'rm -rf -- "$TMP"' EXIT
mkdir -p "$TMP/docs/ledger-notes"

# (a) no bold run, no ASCII ` -- `, no sentence boundary -- ONLY a spaced em dash.
A_TITLE='Session-HANDOFF skill for a long context session, carrying mounted-drive state and in-flight background jobs across a handover boundary without re-deriving any of it'
A_BODY='mechanism to write a structured session-state handoff covering in-flight background jobs, mounted-drive state, pending owner decisions and the scan-next lists, so that a fresh session resumes from the record instead of re-reading the whole tree, which is what makes a handover cheap enough to be worth taking at all'
A_LINE="- [ ] [ROUTINE] ${A_TITLE} ${EM} ${A_BODY} <!-- id:ab12 -->"

# (b) the FIRST spaced dash on the line sits INSIDE an unbackticked lane tag.
B_HEAD='Mechanical fix batch from the instruction-file audit, covering the lane tags in templates and handoff and the relay skill, every one of which must become a valid [INPUT'
B_TAIL="token before the ratchet will accept the line, and the rest of this body is what should actually move off the head, comfortably past the floor the splitter enforces before it cuts anything at all, so the only question this fixture asks is WHERE the cut lands, given that the earliest separator on the line is one the tool must decline"
B_LINE="- [ ] [ROUTINE] ${B_HEAD} ${EM} meeting] ${B_TAIL} <!-- id:ab13 -->"

# (c) the move is over the residue floor but UNDER the pointer's own cost.
C_TITLE='A single-clause title long enough to blow the five hundred character budget on its own, padded with clauses that carry no separator of any kind, no bold run anywhere, and no full stop that any sentence rule could ever anchor on, so the only cut point the tool can possibly find is the one spaced dash near the very end of this line, whose residue is over the twenty-five character floor and yet smaller than the pointer that would replace it'
C_LINE="- [ ] [ROUTINE] ${C_TITLE} ${EM} a short trailing clause here <!-- id:ab14 -->"

{ echo '# TODO'; echo; echo '## Current'; echo
  echo "$A_LINE"; echo "$B_LINE"; echo "$C_LINE"; } > "$TMP/TODO.md"

for v in A B C; do
  eval "len=\${#${v}_LINE}"
  (( len >= 500 )) || fail "fixture sanity: ${v}_LINE is $len chars, under the 500 budget"
done

python3 "$SHRINK" --file TODO.md --root "$TMP" --apply >"$TMP/out" 2>&1 \
  || fail "sanity: ledger-shrink exited non-zero; output: $(cat "$TMP/out")"

a_new="$(grep -F 'id:ab12' "$TMP/TODO.md")"
b_new="$(grep -F 'id:ab13' "$TMP/TODO.md")"
c_new="$(grep -F 'id:ab14' "$TMP/TODO.md")"

# --- (1) the em-dash item shrinks at all -------------------------------------------------
if [[ "$a_new" == *'docs/ledger-notes/ab12.md'* && ${#a_new} -lt ${#A_LINE} ]]; then
  pass "(1) the em-dash-separated item SHRANK (${#A_LINE} -> ${#a_new}) and carries its pointer"
else
  fail "(1) the em-dash-separated item was NOT shrunk (${#A_LINE} -> ${#a_new}): $a_new"
fi

# The cut must be the dash, so the head keeps the title and NOT the body.
[[ "$a_new" == *"$A_TITLE"* ]] \
  || fail "(1b) the head lost its title, so the cut was not at the separator: $a_new"
[[ "$a_new" != *'mechanism to write a structured'* ]] \
  || fail "(1c) the body stayed on the head line: $a_new"
[[ -f "$TMP/docs/ledger-notes/ab12.md" ]] \
  || fail "(1d) no note file was written for ab12"
grep -qF 'mechanism to write a structured' "$TMP/docs/ledger-notes/ab12.md" \
  || fail "(1e) the note does not contain the relocated body verbatim"
grep -qF -- "$EM" "$TMP/docs/ledger-notes/ab12.md" \
  || fail "(1f) the separator itself did not travel with the body (prose was rewritten)"
pass "(1b-f) title kept on the head, body verbatim in the note, separator travelled with it"

# --- (2) a cut never lands inside a bracket group ----------------------------------------
opens="${b_new//[!\[]/}"; closes="${b_new//[!\]]/}"
[[ ${#opens} -eq ${#closes} ]] \
  || fail "(2) the cut landed inside a bracket group -- head brackets unbalanced: $b_new"
[[ "$b_new" == *"[INPUT ${EM} meeting]"* ]] \
  || fail "(2b) the lane tag mentioned in the body was split apart: $b_new"
pass "(2) the bracketed lane tag survived intact; the cut moved past it"

# --- (3) a split that would not shrink the head is REFUSED -------------------------------
[[ "$c_new" == "$C_LINE" ]] \
  || fail "(3) a no-net-shrink split was applied: $c_new"
[[ ! -f "$TMP/docs/ledger-notes/ab14.md" ]] \
  || fail "(3b) a note was written for a refused item"
grep -q 'no-net-shrink\|the head would not shrink' "$TMP/out" \
  || fail "(3c) the refusal was not reported as no-net-shrink: $(cat "$TMP/out")"
pass "(3) the pointer-costs-more-than-it-saves split was refused and reported"

echo "OK: ledger-shrink dash-spelling fallback, bracket protection and net-shrink guard"
