#!/usr/bin/env bash
# roadmap:2654
#
# THE BASELINE STALENESS DETECTOR. Both ratchets in todo-conformance.sh read a COMMITTED
# SNAPSHOT that only a deliberate regen moves -- `relay/head-length-baseline.txt` (id:0d7c)
# and `relay/shape-prose-baseline.txt` (id:2d17). A snapshot's failure mode is SILENT
# LOOSENESS: an item shrinks, the recorded floor stays at the old larger value, and a later
# regrowth back up to that floor is `*-grandfathered` WARN rather than a `*-regrowth` ERROR.
# Measured on the fleet: loderite's id:718c went 4,367 -> 222 -> 1,316 chars in one afternoon
# and nothing fired.
#
# The owner ratified (2026-09-02) MANDATORY REGEN plus a READ-ONLY STALENESS DETECTOR, and
# explicitly REJECTED self-tightening: a reader must not have a write side effect (tree dirt
# feeds the id:aa93 deferral), it would need a flock, and there is no concept of an
# AUTHORITATIVE invocation because this checker runs constantly against fixtures, worktrees
# and hermetic tests where a tightening run would poison the real baseline.
#
# ── WHY THE DETECTOR IS A SEPARATE MODE, WHICH IS WHAT CASE (1) PINS ──────────────────────
#
# `current < baselined` is true EXACTLY WHEN AN ITEM HAS BEEN IMPROVED. A shrink IS the stale
# state. Both dead ends in docs/ledger-notes/cf64.md were re-verified empirically before this
# file was written, by folding a staleness pass into the ordinary report:
#
#   * ESCALATING it broke tests/test_todo_conformance_length_ratchet_0d7c.sh case (b)
#     ("a baselined over-budget line that got SHORTER must not fail --strict", rc=1) and
#     tests/test_shape_prose_regrowth_baseline_2d17.sh case (0) ("a SHRINK is clean under
#     --strict", rc=1).
#   * A NON-escalating WARN LINE survived 0d7c but still broke 2d17 case (0), whose assertion
#     is stricter than the exit code: "the shrunk item reports no shape finding at all". A
#     WARN line keyed to that item IS a finding.
#
# So the detector cannot live in the ordinary report at any severity. It is an explicit,
# separate invocation whose output is the whole report -- the mech-currency.sh (id:0384)
# posture: detect a stale snapshot, name the remedy, never apply it. Case (1) below pins the
# constraint that forced this shape; if it ever goes red, the detector has leaked into the
# lint stream and 0d7c/2d17 are about to break too.
#
# HERMETICITY (id:e350): BOTH $SHAPE_BASELINE and $LENGTH_BASELINE are exported to fixture
# paths under this test's own mktemp -d. Four tests were fixed for reading the live committed
# baselines; this file must never be the fifth.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF="${TODO_CONFORMANCE_OVERRIDE:-$ROOT/relay/scripts/todo-conformance.sh}"

fail=0
pass()   { echo "PASS: $*"; }
report() { echo "FAIL: $*"; fail=1; }

[[ -x "$CONF" ]] || { echo "FAIL: sanity: todo-conformance.sh not executable at $CONF"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf -- "$TMP"' EXIT

# BOTH baselines under our own tmp, never the committed ones.
export LENGTH_BASELINE="$TMP/length-baseline.txt"
export SHAPE_BASELINE="$TMP/shape-baseline.txt"

LEDGER="$TMP/TODO.md"

# Neutral filler, 60 chars per repeat -- deliberately avoids the state-claim terminal words
# and dependency prose so no OTHER rule of this linter fires and muddies the exit codes.
filler() {
  local i
  for ((i = 0; i < $1; i++)); do
    printf 'padding prose about ledger head lines, segment %02d here; ' "$i"
  done
}
item() { # <id> <filler-repeats> -> an over-budget, cuttable, prose-carrying head line
  printf -- '- [ ] [ROUTINE] **Title for %s** %s<!-- id:%s -->\n' "$1" "$(filler "$2")" "$1"
}

ALPHA="$(item aaa1 12)"          # never touched -- stays exactly AT its baseline
BRAVO_BIG="$(item bbb2 12)"      # the one that shrinks
BRAVO_SHRUNK='- [ ] [ROUTINE] **Title for bbb2** -- detail: `docs/ledger-notes/bbb2.md` <!-- id:bbb2 -->'
BRAVO_GROWN="$(item bbb2 16)"    # ABOVE its baseline -- the existing *-regrowth rule's job
CHARLIE="$(item ccc3 12)"        # never touched
DELTA="$(item ddd4 12)"          # removed later, to make an orphaned baseline row

ledger() { # <bravo-line> [omit-delta]
  { echo '# TODO'; echo
    echo '## Current'; echo
    echo "$ALPHA"; echo "$1"; echo "$CHARLIE"
    [[ "${2:-}" == omit-delta ]] || echo "$DELTA"
  } > "$LEDGER"
}

capture() { # regenerate BOTH baselines from the ledger's current state
  "$CONF" --regen-length-baseline "$LEDGER" > "$LENGTH_BASELINE" 2>"$TMP/regen.err" \
    || { report "(setup) --regen-length-baseline failed: $(head -1 "$TMP/regen.err")"; return 1; }
  "$CONF" --regen-shape-baseline "$LEDGER" > "$SHAPE_BASELINE" 2>>"$TMP/regen.err" \
    || { report "(setup) --regen-shape-baseline failed: $(head -1 "$TMP/regen.err")"; return 1; }
  return 0
}

detect() { # <extra flags...> -> stdout in $out, stderr in $err, exit in $rc
  set +e
  out="$("$CONF" --baseline-staleness "$@" "$LEDGER" 2>"$TMP/detect.err")"
  rc=$?
  set -e
  err="$(cat "$TMP/detect.err")"
}
# row <output> <class> <id> -> the whole finding row, "" if absent
row() { awk -F'\t' -v c="$2" -v i="$3" '$1 == c && $2 == i { print; exit }' <<<"$1"; }

# ── (setup) arm the trap: capture with Bravo at full size. ────────────────────────────────
ledger "$BRAVO_BIG"
capture || { echo "FAIL: fixture could not be armed"; exit 1; }
grep -q 'bbb2' "$LENGTH_BASELINE" && grep -q 'bbb2' "$SHAPE_BASELINE" \
  && pass "(setup) both baselines carry a row for the item that is about to shrink" \
  || report "(setup) a baseline captured no row for bbb2 -- the fixture never armed"

# ── (0) NEGATIVE CONTROL, first: before anything moves, the detector must report NOTHING.
#    A detector that always fires proves as little as one that never does.
detect
[[ -z "$(row "$out" length-baseline-stale bbb2)" && -z "$(row "$out" shape-baseline-stale bbb2)" ]] \
  && grep -q 'baseline-staleness: current' <<<"$out" \
  && pass "(0) NEGATIVE CONTROL: at capture time nothing is stale and the detector says so" \
  || report "(0) the detector fired on a freshly captured baseline -- it cannot distinguish stale from current. out:
$out"

# ── (1) THE CONSTRAINT. Shrink Bravo. The ORDINARY lint stream must be byte-for-byte
#    unaffected: rc 0 under --strict, and NO finding keyed to the shrunk item. This is the
#    assertion that makes an in-report staleness class impossible; see the header.
ledger "$BRAVO_SHRUNK"
set +e
ord="$("$CONF" --strict "$LEDGER" 2>"$TMP/ord.err")"; ord_rc=$?
set -e
(( ord_rc == 0 )) \
  && pass "(1) a SHRINK still passes --strict -- improving an item never breaks the ratchet" \
  || report "(1) the SHRUNK state failed --strict (rc=$ord_rc) -- the detector has leaked into the ordinary report. out:
$ord"
[[ -z "$(awk -F'\t' '$3 ~ /id:bbb2/ { print $1; exit }' <<<"$ord")" ]] \
  && pass "(1) the shrunk item reports NO finding at all in the ordinary stream" \
  || report "(1) the shrunk item reports '$(awk -F'\t' '$3 ~ /id:bbb2/ { print $1; exit }' <<<"$ord")' in the ordinary stream -- 2d17 case (0) pins that it must report nothing"

# ── (2) ...and the detector FIRES on that same shrink, in BOTH families.
detect
len_len=${#BRAVO_SHRUNK} ; base_len=${#BRAVO_BIG}
r_len="$(row "$out" length-baseline-stale bbb2)"
r_shape="$(row "$out" shape-baseline-stale bbb2)"
[[ -n "$r_len" ]] \
  && pass "(2) the LENGTH baseline is reported stale for the shrunk item" \
  || report "(2) no length-baseline-stale row for bbb2 after a shrink. out:
$out"
[[ -n "$r_shape" ]] \
  && pass "(2) the SHAPE baseline is reported stale for the shrunk item -- id:2d17 reuses this pattern, it does not invent a second one" \
  || report "(2) no shape-baseline-stale row for bbb2 -- the detector covers only one of the two ratchets. out:
$out"

# ── (3) the per-entry SLACK is named, with the real arithmetic, not just the condition.
grep -q "current $len_len < baselined $base_len" <<<"$r_len" \
  && grep -q "$((base_len - len_len))" <<<"$r_len" \
  && pass "(3) the length row names current ($len_len), baselined ($base_len) and the per-entry slack ($((base_len - len_len)) chars)" \
  || report "(3) the length row does not name current/baselined/slack. row was:
$r_len"

# ── (4) the TOTAL slack is named, so the SIZE of the hole is visible, not just its existence.
grep -qE '# baseline-staleness: STALE .* chars of total slack' <<<"$out" \
  && pass "(4) the summary names the total slack across all stale entries" \
  || report "(4) no total-slack summary line. out:
$out"

# ── (5) THE REMEDY, named as a runnable command -- the mech-currency.sh contract. A detector
#    that states a condition without its remedy makes the reader guess.
grep -q -- '--regen-length-baseline' <<<"$out" && grep -q -- '--regen-shape-baseline' <<<"$out" \
  && pass "(5) both regen commands are named as the remedy" \
  || report "(5) the output does not name the regen command(s). out:
$out"

# ── (6) IT WRITES NOTHING. The whole reason self-tightening was rejected.
led_hash="$(md5sum < "$LEDGER")"; lb_hash="$(md5sum < "$LENGTH_BASELINE")"; sb_hash="$(md5sum < "$SHAPE_BASELINE")"
detect
[[ "$(md5sum < "$LEDGER")" == "$led_hash" \
   && "$(md5sum < "$LENGTH_BASELINE")" == "$lb_hash" \
   && "$(md5sum < "$SHAPE_BASELINE")" == "$sb_hash" ]] \
  && pass "(6) the detector mutated neither the ledger nor either baseline -- a reader has no write side effect" \
  || report "(6) the detector WROTE something (ledger or baseline changed) -- self-tightening was rejected, not implemented"

# ── (7) REPORT-ONLY by default; a gate only on explicit opt-in.
(( rc == 0 )) \
  && pass "(7) bare --baseline-staleness exits 0 even when stale -- report-only, it can never block" \
  || report "(7) bare --baseline-staleness exited $rc on a stale baseline -- it must not block"
detect --strict
(( rc != 0 )) \
  && pass "(7) --baseline-staleness --strict exits nonzero when stale -- available as a gate, on explicit opt-in only" \
  || report "(7) --baseline-staleness --strict exited 0 on a stale baseline -- the opt-in gate does not gate"

# ── (8) an entry sitting exactly AT its baseline is NOT stale.
detect
[[ -z "$(row "$out" length-baseline-stale aaa1)" && -z "$(row "$out" shape-baseline-stale aaa1)" ]] \
  && pass "(8) an untouched item at its baseline is not reported" \
  || report "(8) an untouched item at its baseline was reported stale -- every line would be a finding. out:
$out"

# ── (9) an entry ABOVE its baseline is left to the EXISTING *-regrowth rule, not duplicated
#    here. The detector answers one question: has the floor gone LOOSER than reality.
ledger "$BRAVO_GROWN"
detect
[[ -z "$(row "$out" length-baseline-stale bbb2)" && -z "$(row "$out" shape-baseline-stale bbb2)" ]] \
  && pass "(9) an item grown ABOVE its baseline is not a staleness finding" \
  || report "(9) a grown item was reported as stale -- current < baselined is the whole predicate. out:
$out"
set +e
grown="$("$CONF" --strict "$LEDGER" 2>/dev/null)"; grown_rc=$?
set -e
(( grown_rc != 0 )) && grep -q '^length-regrowth' <<<"$grown" \
  && pass "(9) the existing length-regrowth ERROR still owns that case, undisturbed" \
  || report "(9) the pre-existing regrowth escalation stopped firing (rc=$grown_rc) -- this item must not disturb it. out:
$grown"

# ── (10) THE DONE-CHECK from the item: regenerating clears the report.
ledger "$BRAVO_SHRUNK"
detect
[[ -n "$(row "$out" length-baseline-stale bbb2)" ]] || report "(10) precondition: the shrink is not reported stale"
capture || true
detect
[[ -z "$(row "$out" length-baseline-stale bbb2)" && -z "$(row "$out" shape-baseline-stale bbb2)" ]] \
  && grep -q 'baseline-staleness: current' <<<"$out" \
  && pass "(10) DONE-CHECK: regenerating the baselines clears the report" \
  || report "(10) the report survived a regeneration -- the remedy it names does not work. out:
$out"

# ── (11) an ORPHANED baseline row: the id is gone from the ledger. The floor forgives a line
#    that is not there, and would grandfather it at the old value the moment the id returns.
ledger "$BRAVO_SHRUNK" omit-delta
detect
[[ -n "$(row "$out" length-baseline-orphan ddd4)" && -n "$(row "$out" shape-baseline-orphan ddd4)" ]] \
  && pass "(11) a baselined id absent from the ledger is reported as an orphaned floor" \
  || report "(11) an orphaned baseline row was not reported. out:
$out"

# ── (12) SCOPE: `*.archive.md` is out of scope for both ratchets (id:2065), so it is out of
#    scope here too -- a detector wider than the rule it audits reports unfixable findings.
cp "$LEDGER" "$TMP/TODO.archive.md"
set +e
arch="$("$CONF" --baseline-staleness "$TMP/TODO.archive.md" 2>/dev/null)"; arch_rc=$?
set -e
(( arch_rc == 0 )) && ! grep -qE '^(length|shape)-baseline-' <<<"$arch" \
  && pass "(12) *.archive.md yields no staleness finding (id:2065)" \
  || report "(12) an archive file produced staleness findings (rc=$arch_rc). out:
$arch"

# ── (13) NO BASELINE: nothing to check, said LOUDLY on stderr. A checker that silently
#    verifies nothing is the id:4347 no-silent-swallow class.
ledger "$BRAVO_SHRUNK"
set +e
LENGTH_BASELINE="$TMP/nope-length.txt" SHAPE_BASELINE="$TMP/nope-shape.txt" \
  "$CONF" --baseline-staleness "$LEDGER" > "$TMP/inert.out" 2> "$TMP/inert.err"
inert_rc=$?
set -e
(( inert_rc == 0 )) \
  && grep -qi 'no length baseline' "$TMP/inert.err" \
  && grep -qi 'no shape baseline' "$TMP/inert.err" \
  && pass "(13) with no baselines the detector announces both as INERT on stderr and exits 0" \
  || report "(13) a missing baseline was not announced loudly (rc=$inert_rc). stderr:
$(cat "$TMP/inert.err")"

if (( fail )); then
  exit 1
fi
echo "PASS: todo-conformance.sh --baseline-staleness detects a floor that has gone looser than reality for BOTH ratchets, names per-entry and total slack plus the regen remedy, writes nothing, and never makes a shrink fail (id:2654)"
