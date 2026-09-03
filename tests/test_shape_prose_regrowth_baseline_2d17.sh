#!/usr/bin/env bash
# roadmap:2d17
#
# THE SATURATION HALF of id:2d17. The other half moved out -- see the split note below.
#
# `shape-prose` SATURATED: with ~114 findings standing, a rule that reports finding 115 in
# the SAME WORDS as findings 1..114, and escalates none of them, regulates nothing. A count
# assertion would not capture it either -- in the founding fixture the count went 3 -> 2 -> 3,
# ending exactly where it started.
#
# The fix under test: split the one class into three, and escalate only the two that carry
# information the baseline did not already have.
#
#     shape-new           no baseline entry      ERROR, fails --strict
#     shape-regrowth      residue >  baselined   ERROR, fails --strict
#     shape-grandfathered residue <= baselined   WARN, always reported
#
# A baseline may GRANDFATHER, never SILENCE: every assertion below that touches the standing
# set checks it is still reported, not merely that it stopped failing.
#
# ── THE SPLIT, 2026-09-03 (owner ruled: accept the split, option 3) ───────────────────────
#
# This file used to also pin the id:718c shape -- shrink, then REGROW TO LESS than the
# baselined value (4,367 -> 222 -> 1,316). That case is NOT satisfiable by the mechanism the
# owner ratified for this item on 2026-09-02 ("MANDATORY REGEN plus a STALENESS DETECTOR;
# self-tightening was NOT chosen"), and the conflict is structural, not an implementation
# gap:
#
#   * baselined 76, shrunk to 0, regrown to 29 -> `29 <= 76` -> shape-grandfathered WARN.
#     Only a baseline TIGHTENED to the observed 0 makes it an ERROR, and tightening on
#     observation IS self-tightening.
#   * making `current < baselined` blocking does not rescue it: that fires at the SHRINK,
#     breaking "improving an item never breaks the ratchet" (case 0 below). Blocking-on-stale
#     and clean-on-shrink are mutually exclusive.
#
# So that case now lives in `tests/test_shape_regrowth_below_baseline_cf64.sh` (id:cf64),
# gated on the id:2654 staleness detector. It was MOVED, not weakened -- do not re-add a
# below-baseline regrowth case here, and do not "fix" cf64 by relaxing its assertion.
#
# Hermetic: mktemp ledgers, own baseline path, no ~/.claude, no live ledger, no network.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF="${TODO_CONFORMANCE_OVERRIDE:-$ROOT/relay/scripts/todo-conformance.sh}"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$CONF" ]] || fail "sanity: todo-conformance.sh not executable at $CONF"

TMP="$(mktemp -d)"; trap 'rm -rf -- "$TMP"' EXIT

# Injected so this test can never touch a committed baseline. The FORMAT is deliberately
# never asserted -- the baseline is only ever captured through the tool's own regen path.
BASE="$TMP/shape-baseline.txt"
export SHAPE_BASELINE="$BASE"

ALPHA='- [ ] [ROUTINE] **Alpha item** -- standing prose that has been here since forever and is plainly prose. -- detail: `docs/ledger-notes/aaa1.md` <!-- id:aaa1 -->'
CHARLIE='- [ ] [ROUTINE] **Charlie item** -- more standing prose of the same kind, untouched throughout. -- detail: `docs/ledger-notes/ccc3.md` <!-- id:ccc3 -->'
CHARLIE_WORSE='- [ ] [ROUTINE] **Charlie item** -- more standing prose of the same kind, untouched throughout, and now considerably expanded with additional narration. -- detail: `docs/ledger-notes/ccc3.md` <!-- id:ccc3 -->'
BRAVO_BIG='- [ ] [ROUTINE] **Bravo item** -- the one that shrinks, with a great deal of standing prose attached to it right now. -- detail: `docs/ledger-notes/bbb2.md` <!-- id:bbb2 -->'
BRAVO_SHRUNK='- [ ] [ROUTINE] **Bravo item** -- detail: `docs/ledger-notes/bbb2.md` <!-- id:bbb2 -->'
DELTA_NEW='- [ ] [ROUTINE] **Delta item** -- finding one hundred and fifteen, minted after the baseline was taken. -- detail: `docs/ledger-notes/ddd4.md` <!-- id:ddd4 -->'

# The states share ONE basename on purpose: every baseline mechanism here keys on the ledger
# BASENAME (todo-conformance.sh's LENGTH_LEDGER_KEY), so differently-named fixture files
# would key to different baselines and every assertion would pass for the wrong reason.
LEDGER="$TMP/TODO.md"

ledger() { # <bravo-line> <charlie-line> [extra]
  { echo '# TODO'; echo; echo '## Current'; echo
    echo "$ALPHA"; echo "$1"; echo "$2"
    [[ -n "${3:-}" ]] && echo "$3"
  } > "$LEDGER"
}

# class_of <output> <id> -> the finding CLASS token for that item ("" if none). Everything
# up to the first space; the parenthesised detail carries a moving measurement.
class_of() { awk -F'\t' -v id="$2" '$3 ~ ("id:" id) { sub(/ .*/, "", $1); print $1; exit }' <<<"$1"; }

# ── (8) the capture path. FIRST, not last: every assertion below depends on it, so if it is
#    missing the others would fail for a reason that is not the behaviour under test.
ledger "$BRAVO_BIG" "$CHARLIE"
before_hash="$(md5sum < "$LEDGER")"
regen_rc=0
"$CONF" --regen-shape-baseline "$LEDGER" > "$BASE" 2>"$TMP/regen.err" || regen_rc=$?
(( regen_rc == 0 )) \
  && pass "(8) --regen-shape-baseline captured a snapshot" \
  || fail "(8) --regen-shape-baseline is not implemented (rc=$regen_rc): $(head -1 "$TMP/regen.err")"

[[ "$(md5sum < "$LEDGER")" == "$before_hash" ]] \
  && pass "(8) the capture WROTE NOTHING -- it prints to stdout, exactly as --regen-length-baseline does" \
  || fail "(8) --regen-shape-baseline MUTATED the ledger; a reader must never write"

grep -q 'bbb2' "$BASE" \
  && pass "(8) the baseline actually contains the prose-carrying item" \
  || fail "(8) the baseline captured no row for bbb2 -- the fixture never armed"

# ── (0) a SHRINK is clean. Improving an item may never break the ratchet -- this is the
#    assertion that makes a blocking staleness detector impossible here (see the split note).
ledger "$BRAVO_SHRUNK" "$CHARLIE"
out_shrunk="$("$CONF" --strict "$LEDGER" 2>"$TMP/shrunk.err")"; rc_shrunk=$?
(( rc_shrunk == 0 )) \
  && pass "(0) a SHRINK is clean under --strict" \
  || fail "(0) the SHRUNK state failed --strict (rc=$rc_shrunk) -- a shrink must never be a violation:"$'\n'"$out_shrunk"

[[ -z "$(class_of "$out_shrunk" bbb2)" ]] \
  && pass "(0) the shrunk item reports no shape finding at all" \
  || fail "(0) the shrunk item still reports '$(class_of "$out_shrunk" bbb2)' -- the fixture does not shrink"

# ── (1) FINDING 115: an item that did not exist when the baseline was taken. This is the
#    saturation itself -- the standing set must not be able to bury it.
ledger "$BRAVO_SHRUNK" "$CHARLIE" "$DELTA_NEW"
out_new="$("$CONF" --strict "$LEDGER" 2>"$TMP/new.err")"; rc_new=$?
cls_d="$(class_of "$out_new" ddd4)"
cls_a="$(class_of "$out_new" aaa1)"
cls_c="$(class_of "$out_new" ccc3)"

(( rc_new != 0 )) \
  && pass "(1) a NEWLY-ADDED prose item FAILS --strict -- finding 115 is surfaceable" \
  || fail "(1) a NEWLY-ADDED prose item did NOT fail --strict (rc=$rc_new) -- still buried in the standing set:"$'\n'"$out_new"

[[ -n "$cls_a" && -n "$cls_c" ]] \
  && pass "(2) the STANDING SET is still REPORTED (alpha='$cls_a' charlie='$cls_c') -- a baseline may grandfather, never silence" \
  || fail "(2) the standing set stopped being reported (alpha='$cls_a' charlie='$cls_c')"

[[ -n "$cls_d" && "$cls_d" != "$cls_a" ]] \
  && pass "(3) the new item's class '$cls_d' is DISTINGUISHABLE from the grandfathered '$cls_a'" \
  || fail "(3) new item reports '$cls_d' against grandfathered '$cls_a' -- indistinguishable is the saturation this item exists to fix"

# ── (4) REGROWTH ABOVE the baselined value. A snapshot baseline CAN catch this one, which is
#    precisely why it stays here while the below-baseline case moved to cf64.
ledger "$BRAVO_SHRUNK" "$CHARLIE_WORSE"
out_worse="$("$CONF" --strict "$LEDGER" 2>"$TMP/worse.err")"; rc_worse=$?
cls_cw="$(class_of "$out_worse" ccc3)"
cls_aw="$(class_of "$out_worse" aaa1)"

(( rc_worse != 0 )) \
  && pass "(4) an item grown ABOVE its baseline FAILS --strict" \
  || fail "(4) an item grown above its baseline did NOT fail --strict (rc=$rc_worse):"$'\n'"$out_worse"

[[ -n "$cls_cw" && "$cls_cw" != "$cls_aw" ]] \
  && pass "(5) the regrowth class '$cls_cw' is DISTINGUISHABLE from the untouched '$cls_aw'" \
  || fail "(5) regrown reports '$cls_cw' against untouched '$cls_aw' -- indistinguishable"

# ── (6) fixture guard: the worsened line must genuinely exceed the baselined value, or
#    assertion (4) would pass for the wrong reason.
[[ ${#CHARLIE_WORSE} -gt ${#CHARLIE} ]] \
  && pass "(6) the trap is armed: the worsened line is longer than the baselined one" \
  || fail "(6) fixture broken: the worsened line is not longer than the baselined one"

# ── (7) INERT WITHOUT A BASELINE. A repo that never captured one must be unaffected, and the
#    checker must SAY SO rather than pass silently -- a saturation fix that quietly does
#    nothing is the failure class this item exists to close.
ledger "$BRAVO_BIG" "$CHARLIE"
SHAPE_BASELINE="$TMP/does-not-exist.txt" out_inert="$("$CONF" --strict "$LEDGER" 2>"$TMP/inert.err")"
inert_rc=$?
grep -qi 'shape ratchet INERT' "$TMP/inert.err" \
  && pass "(7) with no baseline the ratchet announces itself INERT on stderr" \
  || fail "(7) no INERT announcement with a missing baseline -- silent-inert is exactly the failure this item closes. stderr was:"$'\n'"$(cat "$TMP/inert.err")"

[[ "$(class_of "$out_inert" aaa1)" == "shape-prose" ]] \
  && pass "(7) with no baseline the class is unchanged legacy 'shape-prose'" \
  || fail "(7) inert mode changed the class to '$(class_of "$out_inert" aaa1)' -- repos without a baseline must be untouched"

(( inert_rc == 0 )) \
  && pass "(7) inert mode does not escalate -- id:8524's blanket promotion stays a separate act" \
  || fail "(7) inert mode failed --strict (rc=$inert_rc) -- it must behave exactly as before this item"

echo "ALL PASS"
