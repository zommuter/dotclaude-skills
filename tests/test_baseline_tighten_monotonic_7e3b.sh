#!/usr/bin/env bash
# No roadmap header -- this is a defect-fix spec for TODO id:7e3b, filed against
# `relay/scripts/todo-conformance.sh`. Failures always count.
#
# id:7e3b -- `--regen-length-baseline` documented itself as "a regen TIGHTENS the ratchet
# (every line re-baselines at its current, smaller length)". It does not. It is a RECAPTURE:
# it writes whatever each line measures now, in BOTH directions. Measured on this repo on
# 2026-09-10, a blanket regen of the committed length baseline turned 50 rows into 61,
# forgave 36,513 fresh chars, and RAISED two existing ceilings (`2b7a` 750 -> 10,190,
# `3770` 2,209 -> 2,536). A grandfathering row has no expiry, so a raise is permanent.
#
# The fix is a second, row-scoped mode, `--tighten-length-baseline` / `--tighten-shape-baseline`,
# whose contract this file pins:
#   (a) SHRANK      -- the floor is LOWERED to the current value.
#   (b) GREW        -- REFUSED loudly, non-zero, naming id, old, new and delta; the row is
#                      left at its OLD value and never raised.
#   (c) UNCHANGED   -- no-op, and the row survives byte-identical.
#   (d) NO ROW      -- REFUSED to mint by default; `--allow-new` is the explicit opt-in and
#                      prints every row it creates.
#   (e) exit status discriminates: 0 when nothing was refused, 1 when anything was.
#   (f) rows for another repo or another ledger PASS THROUGH untouched -- the whole-file
#       recapture truncated them, which is why its printed remedy needed a two-command dance.
#   (g) the same contract holds for the SHAPE family, not just LENGTH.
#
# fails-against: the defect and its fix land in the same commit as this spec, so there is no
# ancestor revision to check out; the negative case is a mutation of the shipped script. It
# turns the monotonic comparison `_cur < BL_LEN` into `_cur != BL_LEN`, which is precisely
# the recapture semantics being repaired -- a grown line then writes its NEW, larger value
# and no refusal fires. Case (a) still passes against it (a shrink is also `!=`).
#
# WHICH assertion fires was PREDICTED WRONG and corrected by `make verify-negatives` itself,
# which is the whole reason that runner exists. The first guess was case (b)'s exit-status
# check; the runner reported "red at the WRONG assertion", because the mutation leaves case
# (d)'s REFUSE-new standing and that alone still drives the exit non-zero. The first assertion
# the mutation actually reaches is (b)'s REFUSE-raise line, declared below. `fail()` exits, so
# it is also the last FAIL line. The mutation touches only a relative path under its cwd.
# fails-against-mutation: sed -i 's/if (( _cur < BL_LEN )); then/if (( _cur != BL_LEN )); then/' relay/scripts/todo-conformance.sh
# fails-against-assertion: (b) GREW: no REFUSE-raise line for bbbb
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF="$ROOT/relay/scripts/todo-conformance.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$CONF" ]] || fail "setup: todo-conformance.sh not found at $CONF"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export TODO_CONFORMANCE_LOG="$TMP/conformance.log"

# mkline <4-hex id> <total chars> -- one conforming top-level checkbox line of EXACTLY that
# many characters, so every assertion below is about a number the test itself chose.
mkline() {
  python3 - "$1" "$2" <<'PY'
import sys
tok, n = sys.argv[1], int(sys.argv[2])
head = f"- [ ] [ROUTINE] **T{tok}** <!-- id:{tok} --> "
assert n >= len(head), (n, len(head))
print(head + "x" * (n - len(head)))
PY
}

# ------------------------------------------------------------------ the fixture ledger
# aaaa/bbbb/cccc start OVER the 500-char budget, so the first capture gives each a row.
# dddd starts UNDER it and therefore has no row -- it is case (d)'s new item.
LEDGER="$TMP/TODO.md"
write_ledger() { # <aaaa len> <bbbb len> <cccc len> <dddd len>
  { mkline aaaa "$1"; mkline bbbb "$2"; mkline cccc "$3"; mkline dddd "$4"; } > "$LEDGER"
}
write_ledger 900 600 700 300

BL="$TMP/head-length-baseline.txt"
LENGTH_BASELINE="$BL" bash "$CONF" --regen-length-baseline "$LEDGER" > "$BL" 2>"$TMP/regen.err" \
  || fail "setup: --regen-length-baseline failed: $(head -1 < <(cat "$TMP/regen.err"))"
for tok in aaaa bbbb cccc; do
  grep -qP "\t$tok\t" "$BL" || fail "setup: the first capture wrote no row for $tok -- the fixture never reaches the mode under test"
done
grep -qP "\tdddd\t" "$BL" && fail "setup: dddd was under budget and must NOT have a row; the (d) case cannot fire"
# The repo key this fixture resolves to (id:4839 dimension b). Taken from the capture rather
# than assumed, so a fixture that lands inside a git checkout still keys its own rows.
FIXREPO="$(cut -f1 < <(grep -m1 -P '\taaaa\t' "$BL"))"
[[ -n "$FIXREPO" ]] || fail "setup: could not read the fixture's repo key from the capture"

# (f)'s guards: one row for a ledger this run will not be given, and one for another repo.
# Both must survive verbatim. Captured BEFORE any tighten run so every later diff sees them.
printf 'someotherrepo\tTODO.md\taaaa\t123\n' >> "$BL"
printf 'no-repo\tROADMAP.md\tffff\t777\n'    >> "$BL"
FOREIGN_ROWS="$(grep -cP '^(someotherrepo\t|no-repo\tROADMAP\.md\t)' "$BL")"
[[ "$FOREIGN_ROWS" -eq 2 ]] || fail "setup: expected 2 pass-through guard rows, found $FOREIGN_ROWS"

BL_ORIG="$TMP/baseline.orig"; cp "$BL" "$BL_ORIG"

# Now move the ledger: aaaa SHRINKS, bbbb GROWS, cccc is UNCHANGED, dddd grows past the
# budget with no row of its own.
write_ledger 550 1200 700 700

run_tighten() { # <outfile> <errfile> [extra flags...] -> echoes the exit status
  local out="$1" err="$2"; shift 2
  local rc=0
  LENGTH_BASELINE="$BL" SHAPE_BASELINE="$TMP/shape-prose-baseline.txt" \
    bash "$CONF" --tighten-length-baseline "$@" "$LEDGER" >"$out" 2>"$err" || rc=$?
  echo "$rc"
}

# ── DRY REPORT ────────────────────────────────────────────────────────────────────────────
rc="$(run_tighten "$TMP/dry.out" "$TMP/dry.err")"
report="$(cat "$TMP/dry.out")"

# (a) SHRANK -> tightens.
grep -qE '^length-baseline-tighten[[:space:]]+aaaa[[:space:]].*900 -> current 550' <<<"$report" \
  && pass "(a) SHRANK: the floor is reported LOWERED 900 -> 550" \
  || fail "(a) SHRANK: no tighten line naming 900 -> 550 for aaaa. report:
$report"

# (b) GREW -> refuses loudly and non-zero, naming id, old, new, delta.
[[ "$rc" -ne 0 ]] \
  && pass "(b) GREW: the run exits non-zero (rc=$rc)" \
  || fail "(b) GREW: the run must exit non-zero when a raise is refused, got rc=$rc. report:
$report"
grep -qE '^length-baseline-REFUSE-raise[[:space:]]+bbbb[[:space:]]' <<<"$report" \
  && pass "(b) GREW: a REFUSE-raise line names bbbb" \
  || fail "(b) GREW: no REFUSE-raise line for bbbb. report:
$report"
grep -qE 'REFUSE-raise[[:space:]]+bbbb.*baselined 600, current 1200 \(\+600' <<<"$report" \
  && pass "(b) GREW: the refusal names old 600, new 1200 and the +600 delta" \
  || fail "(b) GREW: the refusal does not name old, new and delta. report:
$report"

# (c) UNCHANGED -> no finding at all for cccc.
grep -qE '^[a-z-]+[[:space:]]+cccc[[:space:]]' <<<"$report" \
  && fail "(c) UNCHANGED: cccc must produce NO finding, but the report keys a line to it. report:
$report" \
  || pass "(c) UNCHANGED: cccc produces no finding"

# (d) NO ROW -> refuses to mint by default.
grep -qE '^length-baseline-REFUSE-new[[:space:]]+dddd[[:space:]].*--allow-new' <<<"$report" \
  && pass "(d) NO ROW: minting dddd is REFUSED and the opt-in flag is named" \
  || fail "(d) NO ROW: dddd was not refused, or the refusal does not name --allow-new. report:
$report"

# The dry run writes nothing at all.
cmp -s "$BL" "$BL_ORIG" \
  && pass "(dry) the report mode wrote nothing to the baseline file" \
  || fail "(dry) the dry report MODIFIED the baseline file -- it must be a pure read"

# ── EMIT ──────────────────────────────────────────────────────────────────────────────────
rc="$(run_tighten "$TMP/emit.out" "$TMP/emit.err" --emit-baseline)"
emitted="$TMP/emit.out"

[[ "$rc" -ne 0 ]] \
  && pass "(e) --emit-baseline still exits non-zero while a refusal stands (rc=$rc)" \
  || fail "(e) --emit-baseline swallowed the refusal: rc=$rc"

row_of() { { grep -P "^$FIXREPO\t$2\t$1\t" "$3" || true; } | tail -1 | cut -f4; }
[[ "$(row_of aaaa TODO.md "$emitted")" == "550" ]] \
  && pass "(a) SHRANK: the emitted row for aaaa is 550" \
  || fail "(a) SHRANK: emitted row for aaaa is '$(row_of aaaa TODO.md "$emitted")', expected 550"
[[ "$(row_of bbbb TODO.md "$emitted")" == "600" ]] \
  && pass "(b) GREW: the emitted row for bbbb stays at its OLD 600, never raised to 1200" \
  || fail "(b) GREW: the emitted row for bbbb is '$(row_of bbbb TODO.md "$emitted")' -- a refused raise must leave the old floor standing"
[[ "$(row_of cccc TODO.md "$emitted")" == "700" ]] \
  && pass "(c) UNCHANGED: the emitted row for cccc is untouched at 700" \
  || fail "(c) UNCHANGED: the emitted row for cccc is '$(row_of cccc TODO.md "$emitted")', expected 700"
[[ -z "$(row_of dddd TODO.md "$emitted")" ]] \
  && pass "(d) NO ROW: no row was minted for dddd without --allow-new" \
  || fail "(d) NO ROW: a row for dddd was minted at '$(row_of dddd TODO.md "$emitted")' without --allow-new"

# (f) pass-through: the other repo's row and the other ledger's row survive verbatim.
grep -qxF "$(printf 'someotherrepo\tTODO.md\taaaa\t123')" "$emitted" \
  && pass "(f) another repo's row passed through verbatim" \
  || fail "(f) the row for someotherrepo was lost or rewritten. emitted:
$(cat "$emitted")"
grep -qxF "$(printf 'no-repo\tROADMAP.md\tffff\t777')" "$emitted" \
  && pass "(f) another ledger's row passed through verbatim (no truncation)" \
  || fail "(f) the ROADMAP.md row was lost -- this mode must not truncate ledgers it was not given. emitted:
$(cat "$emitted")"
grep -q '^# ' "$emitted" \
  && pass "(f) the baseline file's comment header survives the rewrite" \
  || fail "(f) the emitted file carries no comment lines -- the header was dropped"

# ── (d) THE OPT-IN ────────────────────────────────────────────────────────────────────────
rc="$(run_tighten "$TMP/new.out" "$TMP/new.err" --emit-baseline --allow-new)"
[[ "$(row_of dddd TODO.md "$TMP/new.out")" == "700" ]] \
  && pass "(d) --allow-new mints the missing row at its current 700" \
  || fail "(d) --allow-new did not mint a row for dddd (got '$(row_of dddd TODO.md "$TMP/new.out")')"
grep -qE '^length-baseline-MINT[[:space:]]+dddd[[:space:]]' "$TMP/new.err" \
  && pass "(d) --allow-new PRINTS every row it creates" \
  || fail "(d) --allow-new created a row silently. stderr:
$(cat "$TMP/new.err")"
[[ "$(row_of bbbb TODO.md "$TMP/new.out")" == "600" ]] \
  && pass "(d) --allow-new does not weaken the raise refusal (bbbb still 600)" \
  || fail "(d) --allow-new also raised bbbb to '$(row_of bbbb TODO.md "$TMP/new.out")'"

# ── (e) THE EXIT STATUS DISCRIMINATES ─────────────────────────────────────────────────────
# Same baseline, but a ledger where the ONLY movement is a shrink. If this also exited 1 the
# status would carry no information and every assertion above about rc would be vacuous.
write_ledger 550 600 700 300
rc="$(run_tighten "$TMP/clean.out" "$TMP/clean.err")"
[[ "$rc" -eq 0 ]] \
  && pass "(e) a run with nothing refused exits 0 -- the status discriminates" \
  || fail "(e) a shrink-only run exited $rc; the exit status carries no information. report:
$(cat "$TMP/clean.out")
stderr: $(cat "$TMP/clean.err")"

# ── (h) --only: THE ONE-ID FORM the item's note asks for ──────────────────────────────────
# Put the ledger back in its moved state and tighten ONLY aaaa. bbbb's grown line must not be
# judged at all, so the run is clean, and every other row survives byte-identical.
write_ledger 550 1200 700 700
rc="$(run_tighten "$TMP/only.out" "$TMP/only.err" --emit-baseline --only aaaa)"
[[ "$rc" -eq 0 ]] \
  && pass "(h) --only aaaa: the unselected grown row is not judged, so the run is clean" \
  || fail "(h) --only aaaa exited $rc; rows outside the selection must not be judged. stderr:
$(cat "$TMP/only.err")"
[[ "$(row_of aaaa TODO.md "$TMP/only.out")" == "550" ]] \
  && pass "(h) --only aaaa: the selected row is tightened" \
  || fail "(h) --only aaaa did not tighten aaaa (got '$(row_of aaaa TODO.md "$TMP/only.out")')"
for tok in bbbb cccc; do
  [[ "$(row_of "$tok" TODO.md "$TMP/only.out")" == "$(row_of "$tok" TODO.md "$BL_ORIG")" ]] \
    || fail "(h) --only aaaa moved the row for $tok"
done
pass "(h) --only aaaa: every unselected row survives byte-identical"
rc="$(run_tighten "$TMP/typo.out" "$TMP/typo.err" --only 9999)"
[[ "$rc" -ne 0 ]] && grep -qE '^length-baseline-REFUSE-unknown[[:space:]]+9999[[:space:]]' "$TMP/typo.out" \
  && pass "(h) --only with an id that matches nothing is REFUSED, not a silent clean run" \
  || fail "(h) --only 9999 exited $rc with no REFUSE-unknown line -- a typo'd id would read as success. report:
$(cat "$TMP/typo.out")"

# ── (g) THE SHAPE FAMILY ──────────────────────────────────────────────────────────────────
# The same contract, on the other ratchet. Prose residue, not raw length.
SHAPE_LEDGER="$TMP/shape/TODO.md"; mkdir -p "$TMP/shape"
SBL="$TMP/shape-prose-baseline.txt"
{
  echo "- [ ] [ROUTINE] **Title one** this is a long stretch of loose prose that is nobody's title and counts as shape residue <!-- id:1111 -->"
  echo "- [ ] [ROUTINE] **Title two** another long stretch of loose prose that also counts as shape residue for this fixture <!-- id:2222 -->"
} > "$SHAPE_LEDGER"
SHAPE_BASELINE="$SBL" bash "$CONF" --regen-shape-baseline "$SHAPE_LEDGER" > "$SBL" 2>"$TMP/sregen.err" \
  || fail "(g) setup: --regen-shape-baseline failed: $(head -1 < <(cat "$TMP/sregen.err"))"
grep -qP '\t1111\t' "$SBL" && grep -qP '\t2222\t' "$SBL" \
  || fail "(g) setup: the shape capture wrote no rows -- the shape case cannot fire. baseline:
$(cat "$SBL")"
S1_BEFORE="$(row_of 1111 TODO.md "$SBL")"
# 1111 shrinks to a bare title; 2222 grows.
{
  echo "- [ ] [ROUTINE] **Title one** <!-- id:1111 -->"
  echo "- [ ] [ROUTINE] **Title two** another long stretch of loose prose that also counts as shape residue for this fixture, now with a good deal more of it bolted on the end <!-- id:2222 -->"
} > "$SHAPE_LEDGER"
srco=0
SHAPE_BASELINE="$SBL" bash "$CONF" --tighten-shape-baseline --emit-baseline "$SHAPE_LEDGER" \
  >"$TMP/shape.out" 2>"$TMP/shape.err" || srco=$?
S1_AFTER="$(row_of 1111 TODO.md "$TMP/shape.out")"
[[ -n "$S1_BEFORE" && -n "$S1_AFTER" && "$S1_AFTER" -lt "$S1_BEFORE" ]] \
  && pass "(g) SHAPE: the shrunk item's floor is lowered ($S1_BEFORE -> $S1_AFTER)" \
  || fail "(g) SHAPE: floor for 1111 went '$S1_BEFORE' -> '$S1_AFTER', expected a decrease"
[[ "$(row_of 2222 TODO.md "$TMP/shape.out")" == "$(row_of 2222 TODO.md "$SBL")" ]] \
  && pass "(g) SHAPE: the grown item's floor is left standing, not raised" \
  || fail "(g) SHAPE: floor for 2222 moved from '$(row_of 2222 TODO.md "$SBL")' to '$(row_of 2222 TODO.md "$TMP/shape.out")'"
[[ "$srco" -ne 0 ]] \
  && pass "(g) SHAPE: the run exits non-zero on the refused raise (rc=$srco)" \
  || fail "(g) SHAPE: the run exited 0 despite a refused raise. stderr:
$(cat "$TMP/shape.err")"

# ── THE DOCSTRING THAT MADE THE BLANKET REGEN LOOK SAFE ───────────────────────────────────
# A comment asserting a property the code does not have is the derived-doc-drift class, and
# this exact sentence is what made the 2026-09-10 recapture look like a tightening.
grep -qF 'A regen TIGHTENS the ratchet' "$CONF" \
  && fail "the false docstring 'A regen TIGHTENS the ratchet' is still in todo-conformance.sh" \
  || pass "the false 'a regen TIGHTENS the ratchet' claim is gone from the docstring"

echo "PASS: todo-conformance.sh --tighten-{length,shape}-baseline is row-scoped and MONOTONIC -- it lowers a floor, refuses to raise one, refuses to mint a row for a new item, exits non-zero on any refusal, and passes other repos'/ledgers' rows through untouched (id:7e3b)"
