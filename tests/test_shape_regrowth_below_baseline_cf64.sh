#!/usr/bin/env bash
# roadmap:cf64
#
# RED SPEC. The id:718c shape, MOVED here from tests/test_shape_prose_regrowth_baseline_2d17.sh
# on 2026-09-03 when the owner accepted the split (option 3).
#
# THE SHAPE, and it is the incident id:2d17 was originally filed for:
#
#     id:718c went 4,367 -> 222 -> 1,316 chars in one afternoon,
#     while shape-prose was already firing on that exact line and could not report it.
#
# The regrowth (1,316) is SMALLER than the baselined value (4,367). So:
#
#   * an ID-KEYED baseline forgives it -- the id is in the set, forever (the id:cb3e trap;
#     lib-state-claim.sh:157 documents that it "silently RE-GRANDFATHERS ... no expiry");
#   * a SNAPSHOT baseline forgives it too -- `1316 <= 4367` is within the recorded floor.
#     head-length-baseline.txt discloses this in its own words: "a line listed at 9,000
#     chars stays forgiven at 9,000 chars until this file is regenerated".
#
# Only a baseline whose floor has been TIGHTENED to the observed shrink reports it.
#
# ── WHY THIS IS RED, AND WHY THAT IS CORRECT ─────────────────────────────────────────────
#
# id:2d17 shipped the SNAPSHOT design, which the owner ratified 2026-09-02 ("MANDATORY REGEN
# plus a STALENESS DETECTOR; self-tightening was NOT chosen"). By construction it cannot pass
# this file. That is not a defect in id:2d17's implementation -- it is the boundary of the
# ratified mechanism, and this file exists to keep that boundary VISIBLE rather than letting
# it sit as an unstated gap inside a green suite.
#
# THE TWO DEAD ENDS, recorded so they are not re-proposed:
#
#   1. Make `current < baselined` a BLOCKING finding. It fires at the SHRINK (state 1 below),
#      breaking id:2d17's case (0) "improving an item never breaks the ratchet". Blocking-on-
#      stale and clean-on-shrink are mutually exclusive.
#   2. Make it a WARN. Then it does not fail --strict, and case (1) below still fails.
#
# THE ROUTE THAT WORKS: id:2654's read-only staleness detector reports that the floor has
# gone looser than reality, a human regenerates, and the regrowth is then caught. That is a
# weaker guarantee than self-tightening -- it fails open through inaction -- and the owner
# weighed exactly that and chose it anyway. Hence `gated-on:2654`.
#
# WHEN id:2654 LANDS, this file is expected to be AMENDED, not merely turned green: insert
# the deliberate regen between state 1 and state 2 and assert the detector FIRES at state 2.
# Turning it green by relaxing the assertion instead would be the id:0b70 vacuous-check class.
#
# Hermetic: mktemp ledgers, own baseline path, no ~/.claude, no live ledger, no network.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF="${TODO_CONFORMANCE_OVERRIDE:-$ROOT/relay/scripts/todo-conformance.sh}"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$CONF" ]] || fail "sanity: todo-conformance.sh not executable at $CONF"

TMP="$(mktemp -d)"; trap 'rm -rf -- "$TMP"' EXIT

BASE="$TMP/shape-baseline.txt"
export SHAPE_BASELINE="$BASE"

ALPHA='- [ ] [ROUTINE] **Alpha item** -- standing prose that has been here since forever and is plainly prose. -- detail: `docs/ledger-notes/aaa1.md` <!-- id:aaa1 -->'
CHARLIE='- [ ] [ROUTINE] **Charlie item** -- more standing prose of the same kind, untouched throughout. -- detail: `docs/ledger-notes/ccc3.md` <!-- id:ccc3 -->'
BRAVO_BIG='- [ ] [ROUTINE] **Bravo item** -- the one that shrinks and regrows, with a great deal of standing prose attached to it right now. -- detail: `docs/ledger-notes/bbb2.md` <!-- id:bbb2 -->'
BRAVO_SHRUNK='- [ ] [ROUTINE] **Bravo item** -- detail: `docs/ledger-notes/bbb2.md` <!-- id:bbb2 -->'
BRAVO_REGROWN='- [ ] [ROUTINE] **Bravo item** -- regrown prose, shorter than before. -- detail: `docs/ledger-notes/bbb2.md` <!-- id:bbb2 -->'

LEDGER="$TMP/TODO.md"
ledger() { # <bravo-line>
  { echo '# TODO'; echo; echo '## Current'; echo
    echo "$ALPHA"; echo "$1"; echo "$CHARLIE"
  } > "$LEDGER"
}
class_of() { awk -F'\t' -v id="$2" '$3 ~ ("id:" id) { sub(/ .*/, "", $1); print $1; exit }' <<<"$1"; }

# ── fixture guard FIRST: the whole discriminator is that the regrown line is SHORTER than
#    the baselined one. If that ever stops being true the file proves nothing.
[[ "$BRAVO_REGROWN" != "$BRAVO_BIG" && ${#BRAVO_REGROWN} -lt ${#BRAVO_BIG} ]] \
  && pass "(fixture) the regrown line is SHORTER than the baselined one -- only a TIGHTENED floor can fire" \
  || fail "(fixture) broken: the regrown line is not shorter than the baselined one"

# ── state 0: capture with Bravo at full size. This arms the trap: the floor recorded now
#    must not survive the shrink that follows.
ledger "$BRAVO_BIG"
regen_rc=0
"$CONF" --regen-shape-baseline "$LEDGER" > "$BASE" 2>"$TMP/regen.err" || regen_rc=$?
(( regen_rc == 0 )) \
  || fail "(setup) --regen-shape-baseline failed (rc=$regen_rc): $(head -1 "$TMP/regen.err")"

# ── state 1: Bravo SHRINKS. Must stay clean -- and this is the observation a tightening
#    implementation needs. The checker is deliberately RUN here, not skipped.
ledger "$BRAVO_SHRUNK"
out_shrunk="$("$CONF" --strict "$LEDGER" 2>/dev/null)"; rc_shrunk=$?
(( rc_shrunk == 0 )) \
  && pass "(0) the SHRINK is clean under --strict" \
  || fail "(0) the SHRUNK state failed --strict (rc=$rc_shrunk) -- a shrink must never be a violation:"$'\n'"$out_shrunk"

# ── state 2: Bravo REGROWS to LESS than it was baselined at. The id:718c shape.
ledger "$BRAVO_REGROWN"
out_re="$("$CONF" --strict "$LEDGER" 2>/dev/null)"; rc_re=$?
cls_b="$(class_of "$out_re" bbb2)"
cls_a="$(class_of "$out_re" aaa1)"

(( rc_re != 0 )) \
  && pass "(1) a regrowth BELOW the baselined value FAILS --strict" \
  || fail "(1) regrowth below the baselined value did NOT fail --strict (rc=$rc_re) -- the floor went stale and forgave it. This is the id:718c shape. Output was:"$'\n'"$out_re"

[[ -n "$cls_b" && "$cls_b" != "$cls_a" ]] \
  && pass "(2) the regrowth class '$cls_b' is DISTINGUISHABLE from the untouched '$cls_a'" \
  || fail "(2) regrown reports '$cls_b' against untouched '$cls_a' -- a forgiven regrowth is indistinguishable from a standing finding"

echo "ALL PASS"
