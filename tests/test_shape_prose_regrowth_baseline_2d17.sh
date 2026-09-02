#!/usr/bin/env bash
# roadmap:2d17
#
# RED SPEC (authored by relay handoff C3, not implemented here).
#
# `shape-prose` SATURATES. Measured on this fixture with the SHIPPED checker, the
# id:718c shape reproduces byte-for-byte:
#
#     Bravo residue   76 chars  ->  0 chars (shrunk)  ->  29 chars (regrown)
#
# and at every one of those three states `todo-conformance.sh --strict` exits 0 and the
# regrown Bravo's finding line is TEXTUALLY INDISTINGUISHABLE in class from the two
# standing findings beside it. That is the whole defect: with ~114 findings standing, a
# rule that reports finding 115 in the same words as findings 1..114, and escalates
# none of them, regulates nothing. A count assertion would not capture it either --
# the count goes 3 -> 2 -> 3, ending exactly where it started.
#
# THE DESIGN CONSTRAINT THIS FILE PINS, and it is the reason the obvious fix is wrong:
# the baseline MUST NOT be ID-KEYED. `relay/scripts/lib-state-claim.sh:157` documents
# that the id-keyed id:cb3e baseline "silently RE-GRANDFATHERS ... There is no expiry",
# so an id-keyed exemption forgives Bravo forever the moment it is captured.
#
# AND IT PINS ONE STEP FURTHER, deliberately. Case (3) is constructed so that Bravo
# regrows to 29 while its baselined value is 76: 29 < 76. A LENGTH-keyed baseline that
# is a static SNAPSHOT -- which is what the id:0d7c length ratchet actually is, by its
# own documented "KNOWN WEAKNESS: a line listed at 9,000 chars stays forgiven at 9,000
# chars until this file is regenerated" -- ALSO forgives it. So does an id-keyed one.
# Only a baseline that TIGHTENS on the observed shrink reports it. That is the true
# id:718c shape (4,367 -> 222 -> 1,316 chars, and 1,316 < 4,367): the incident the item
# was filed for is NOT caught by a snapshot. The item's acceptance says "key the
# baseline on the VALUE and permit change only toward the goal, per the ratchet in
# id:0d7c"; those two halves point at different mechanisms, and this file encodes the
# first (monotonic) rather than the second (snapshot). See the handoff report.
#
# MECHANISM-NEUTRAL BY CONSTRUCTION: the checker is invoked at the SHRUNK state before
# the REGROWN state, with the same baseline path both times, so an implementation that
# tightens on observation gets its observation. Nothing here dictates the file format --
# the baseline is captured through the tool's own regen path, never hand-written.
#
# Hermetic: mktemp ledgers, own baseline path, no ~/.claude, no live ledger, no network.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF="${TODO_CONFORMANCE_OVERRIDE:-$ROOT/relay/scripts/todo-conformance.sh}"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }
info() { echo "info: $*"; }

[[ -x "$CONF" ]] || fail "sanity: todo-conformance.sh not executable at $CONF"

TMP="$(mktemp -d)"; trap 'rm -rf -- "$TMP"' EXIT

# The baseline the implementation is expected to read. Path is injected so this test can
# never touch a committed one; the FORMAT is deliberately not asserted anywhere.
BASE="$TMP/shape-baseline.txt"
export SHAPE_BASELINE="$BASE"

ALPHA='- [ ] [ROUTINE] **Alpha item** -- standing prose that has been here since forever and is plainly prose. -- detail: `docs/ledger-notes/aaa1.md` <!-- id:aaa1 -->'
CHARLIE='- [ ] [ROUTINE] **Charlie item** -- more standing prose of the same kind, untouched throughout. -- detail: `docs/ledger-notes/ccc3.md` <!-- id:ccc3 -->'
BRAVO_BIG='- [ ] [ROUTINE] **Bravo item** -- the one that shrinks and regrows, with a great deal of standing prose attached to it right now. -- detail: `docs/ledger-notes/bbb2.md` <!-- id:bbb2 -->'
BRAVO_SHRUNK='- [ ] [ROUTINE] **Bravo item** -- detail: `docs/ledger-notes/bbb2.md` <!-- id:bbb2 -->'
BRAVO_REGROWN='- [ ] [ROUTINE] **Bravo item** -- regrown prose, shorter than before. -- detail: `docs/ledger-notes/bbb2.md` <!-- id:bbb2 -->'
DELTA_NEW='- [ ] [ROUTINE] **Delta item** -- finding one hundred and fifteen, minted after the baseline was taken. -- detail: `docs/ledger-notes/ddd4.md` <!-- id:ddd4 -->'

ledger() { # <path> <bravo-line> [extra line]
  { echo '# TODO'; echo; echo '## Current'; echo
    echo "$ALPHA"; echo "$2"; echo "$CHARLIE"
    [[ -n "${3:-}" ]] && echo "$3"
  } > "$1"
}

# The three states share ONE basename on purpose: every baseline mechanism in this repo
# keys on the ledger BASENAME (see todo-conformance.sh's LENGTH_LEDGER_KEY), so three
# differently-named fixture files would silently key to three different baselines and
# every assertion below would pass for the wrong reason.
LEDGER="$TMP/TODO.md"

# class_of <output> <id> -> the finding CLASS token reported for that item ("" if none).
# The class token is everything up to the first space; the parenthesised detail carries a
# moving measurement and is deliberately not compared.
class_of() { awk -F'\t' -v id="$2" '$3 ~ ("id:" id) { sub(/ .*/, "", $1); print $1; exit }' <<<"$1"; }

# ── state 0: the standing set. Capture the baseline HERE, with Bravo at its full 76 chars,
#    which is what arms the trap: any exemption recorded now must not survive the shrink.
ledger "$LEDGER" "$BRAVO_BIG"
regen_rc=0
"$CONF" --regen-shape-baseline "$LEDGER" > "$BASE" 2>"$TMP/regen.err" || regen_rc=$?
if (( regen_rc != 0 )); then
  info "no --regen-shape-baseline yet (rc=$regen_rc): $(head -1 "$TMP/regen.err")"
  info "continuing with an EMPTY baseline -- the assertions below are about behaviour, not the flag"
  : > "$BASE"
fi

# ── state 1: Bravo SHRINKS. A shrink may never break the ratchet, and it is the
#    observation an implementation needs in order to tighten. Run it, and require it clean.
ledger "$LEDGER" "$BRAVO_SHRUNK"
out_shrunk="$("$CONF" --strict "$LEDGER" 2>"$TMP/shrunk.err")"; rc_shrunk=$?
if (( rc_shrunk == 0 )); then
  pass "(0) a SHRINK is clean under --strict -- improving an item never breaks the ratchet"
else
  fail "(0) the SHRUNK state failed --strict (rc=$rc_shrunk) -- a shrink must never be a violation:"$'\n'"$out_shrunk"
fi
[[ -z "$(class_of "$out_shrunk" bbb2)" ]] \
  && pass "(0) the shrunk Bravo reports no shape finding at all" \
  || fail "(0) the shrunk Bravo still reports '$(class_of "$out_shrunk" bbb2)' -- the fixture does not shrink"

# ── state 2: Bravo REGROWS, to 29 chars -- LESS than the 76 it was baselined at. This is
#    the id:718c shape and the core of the item.
ledger "$LEDGER" "$BRAVO_REGROWN"
out_re="$("$CONF" --strict "$LEDGER" 2>"$TMP/re.err")"; rc_re=$?

(( rc_re != 0 )) \
  && pass "(1) a REGROWN item fails --strict while the standing set stands" \
  || fail "(1) a REGROWN item did NOT fail --strict (rc=$rc_re) -- shape-prose is saturated: finding 115 is unreportable. Output was:"$'\n'"$out_re"

cls_b="$(class_of "$out_re" bbb2)"
cls_a="$(class_of "$out_re" aaa1)"
cls_c="$(class_of "$out_re" ccc3)"

[[ -n "$cls_b" ]] \
  && pass "(2) the regrown item is reported at all (class '$cls_b')" \
  || fail "(2) the regrown item produced NO finding -- it regrew below its baselined value and was forgiven"

[[ -n "$cls_a" && -n "$cls_c" ]] \
  && pass "(3) the STANDING SET is unchanged -- both untouched items are still reported" \
  || fail "(3) the standing set stopped being reported (alpha='$cls_a' charlie='$cls_c') -- a baseline may grandfather, never silence"

[[ "$cls_b" != "$cls_a" && "$cls_b" != "$cls_c" ]] \
  && pass "(4) the regrowth is DISTINGUISHABLE from the standing set ('$cls_b' vs '$cls_a')" \
  || fail "(4) the regrown item reports the SAME class '$cls_b' as the standing set -- indistinguishable is exactly the saturation this item exists to fix"

# ── (5) NOT ID-KEYED, and not a static snapshot either. Proven from the fixture's own
#    numbers rather than from the baseline file's format, which this test never reads.
#    29 < 76, so both an id-keyed exemption and a snapshot-value exemption forgive Bravo;
#    only a baseline that tightened on state 1 reports it. Assertion (2) already carries
#    the verdict -- this restates WHY it is the discriminator, and guards the fixture.
[[ "$BRAVO_REGROWN" != "$BRAVO_BIG" && ${#BRAVO_REGROWN} -lt ${#BRAVO_BIG} ]] \
  && pass "(5) the trap is armed: the regrown line is SHORTER than the baselined one, so only a monotonic (not snapshot, not id-keyed) baseline can fire" \
  || fail "(5) fixture broken: the regrown line is not shorter than the baselined one"

# ── (6) finding 115: an item that did not exist when the baseline was taken.
ledger "$LEDGER" "$BRAVO_SHRUNK" "$DELTA_NEW"
out_new="$("$CONF" --strict "$LEDGER" 2>"$TMP/new.err")"; rc_new=$?
cls_d="$(class_of "$out_new" ddd4)"
(( rc_new != 0 )) \
  && pass "(6) a NEWLY-ADDED prose item fails --strict -- finding 115 is surfaceable" \
  || fail "(6) a NEWLY-ADDED prose item did NOT fail --strict (rc=$rc_new) -- a new violation is still buried in the standing set:"$'\n'"$out_new"
[[ -n "$cls_d" && "$cls_d" != "$cls_a" ]] \
  && pass "(7) the new item's class '$cls_d' differs from the grandfathered class '$cls_a'" \
  || fail "(7) the new item reports class '$cls_d' against grandfathered '$cls_a' -- a new id must not enter the set silently"

# ── (8) the capture path itself. Last, because it is the ENABLING mechanism, not the
#    behaviour: if it is missing, the failures above are the ones worth reading first.
(( regen_rc == 0 )) \
  && pass "(8) --regen-shape-baseline captures a snapshot without writing the baseline itself" \
  || fail "(8) --regen-shape-baseline is not implemented (rc=$regen_rc); a baseline must be capturable by a DELIBERATE, SEPARATE act, exactly as --regen-length-baseline is"

echo "ALL PASS"
