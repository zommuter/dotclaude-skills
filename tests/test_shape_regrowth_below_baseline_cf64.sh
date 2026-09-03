#!/usr/bin/env bash
# roadmap:cf64
#
# The id:718c shape, MOVED here from tests/test_shape_prose_regrowth_baseline_2d17.sh on
# 2026-09-03 when the owner accepted the split (option 3), and AMENDED the same day when
# id:2654 landed and the owner ruled option 1. It is GREEN now; it was a RED SPEC between
# those two rulings. The "WHY THIS IS RED" section below is kept as the record of why the
# bare snapshot design could not satisfy it -- read it as history, not as current state.
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
# AMENDED 2026-09-03, exactly as this paragraph required: the deliberate regen is inserted
# between state 1 and state 2, and the detector is asserted to FIRE at the shrunk state
# (case 1) and to go QUIET after the regen (case 3). No assertion was relaxed -- the file
# gained four cases and kept every original one, which is what distinguishes an amendment
# from the id:0b70 vacuous-check class.
#
# WHAT THE GREEN NOW MEANS, stated plainly so nobody reads it as more than it is: the id:718c
# shape is caught by a LOOP THAT REQUIRES A HUMAN ACT -- detector reports, person regenerates,
# regrowth then fires. It is NOT caught automatically. The loop fails open through inaction,
# which is the accepted weakness of regen-plus-detect over self-tightening; the owner weighed
# that on 2026-09-02 and chose this path knowingly.
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

# ── state 1: Bravo SHRINKS. Must stay clean -- and this is the observation the loop needs.
ledger "$BRAVO_SHRUNK"
out_shrunk="$("$CONF" --strict "$LEDGER" 2>/dev/null)"; rc_shrunk=$?
(( rc_shrunk == 0 )) \
  && pass "(0) the SHRINK is clean under --strict" \
  || fail "(0) the SHRUNK state failed --strict (rc=$rc_shrunk) -- a shrink must never be a violation:"$'\n'"$out_shrunk"

# ── state 1b: THE DETECTOR MUST FIRE HERE. This is the amendment (owner ruled option 1,
#    2026-09-03) and it is what makes the regen below a mechanism rather than a hope.
#    Without this assertion the regen is unmotivated and the test would be pinning
#    "someone remembered", which is not a guarantee.
out_stale="$("$CONF" --baseline-staleness "$LEDGER" 2>/dev/null)"
grep -qE "^shape-baseline-stale[[:space:]]+bbb2" <<<"$out_stale" \
  && pass "(1) id:2654's detector REPORTS the shrunk item's floor as stale" \
  || fail "(1) --baseline-staleness did NOT report bbb2 after the shrink -- the snapshot has gone silently loose, which is the whole failure this loop exists to close. Output was:"$'\n'"$out_stale"

"$CONF" --baseline-staleness --strict "$LEDGER" >/dev/null 2>&1 && stale_rc=0 || stale_rc=$?
(( stale_rc != 0 )) \
  && pass "(2) --baseline-staleness --strict exits non-zero while stale, so a caller CAN gate on it" \
  || fail "(2) --baseline-staleness --strict exited 0 while the floor was stale"

# ── state 1c: the DELIBERATE REGEN. This is the human act the ratified design requires --
#    the detector names it, a person performs it. Nothing here happens automatically, and
#    that asymmetry is the accepted weakness of the regen-plus-detect design over
#    self-tightening (owner weighed it 2026-09-02 and chose this path).
"$CONF" --regen-shape-baseline "$LEDGER" > "$BASE.new" 2>/dev/null \
  || fail "(3) regen failed at the point the detector asked for it"
mv -- "$BASE.new" "$BASE"

grep -qE "^shape-baseline-stale[[:space:]]+bbb2" <<<"$("$CONF" --baseline-staleness "$LEDGER" 2>/dev/null)" \
  && fail "(3) the detector STILL reports bbb2 as stale after a regen -- the remedy it names does not work" \
  || pass "(3) after the regen the detector is quiet -- the remedy it names actually clears it"

# ── state 2: Bravo REGROWS to LESS than it was ORIGINALLY baselined at (29 < 76). Under the
#    bare snapshot design this was forgiven. After the detector+regen loop it fires.
#
#    PRECISELY WHAT FIRES, because the obvious guess is wrong: the regen did not record
#    bbb2 at a floor of 0. At the shrunk state its residue is BELOW the 8-char slack, so
#    `--regen-shape-baseline` emits NO ROW for it at all. The regrowth is therefore caught
#    as `shape-new` (an id absent from the baseline), not as `shape-regrowth`. Both are
#    ERRORs and both are distinguishable from the grandfathered standing set, so the
#    guarantee holds -- but the mechanism is baseline ABSENCE, not a tightened floor.
#    Asserted below by class, so a future change that alters which of the two fires will
#    show up here rather than passing silently.
ledger "$BRAVO_REGROWN"
out_re="$("$CONF" --strict "$LEDGER" 2>/dev/null)"; rc_re=$?
cls_b="$(class_of "$out_re" bbb2)"
cls_a="$(class_of "$out_re" aaa1)"

(( rc_re != 0 )) \
  && pass "(4) a regrowth BELOW the ORIGINAL floor now FAILS --strict, after detector+regen" \
  || fail "(4) regrowth below the original floor did NOT fail --strict (rc=$rc_re) -- the floor went stale and forgave it. This is the id:718c shape. Output was:"$'\n'"$out_re"

# The mechanism pin the comment above promises. Both `shape-new` and `shape-regrowth` are
# ERRORs and either satisfies the GUARANTEE, so a bare "is an error" check would hide a
# change in WHICH one fires. Today it is `shape-new` (baseline absence, because the shrunk
# residue fell under the 8-char slack and so was never recorded). If the slack or the regen
# emission changes, this flips to `shape-regrowth` -- still correct, but a different
# mechanism, and that is worth failing on so a human confirms it rather than discovering it
# later. Widen this pin deliberately; do not delete it.
case "$cls_b" in
  shape-new) pass "(5a) the firing mechanism is baseline ABSENCE ('shape-new'), as documented" ;;
  shape-regrowth) fail "(5a) the mechanism CHANGED to 'shape-regrowth' -- the guarantee still holds, but the comment above and the note now describe the wrong mechanism. Confirm intended, then update both and re-pin." ;;
  *) fail "(5a) unexpected class '$cls_b' -- expected shape-new (or shape-regrowth after a deliberate change)" ;;
esac

[[ -n "$cls_b" && "$cls_b" != "$cls_a" ]] \
  && pass "(5) the regrowth class '$cls_b' is DISTINGUISHABLE from the untouched '$cls_a'" \
  || fail "(5) regrown reports '$cls_b' against untouched '$cls_a' -- a forgiven regrowth is indistinguishable from a standing finding"

echo "ALL PASS"
