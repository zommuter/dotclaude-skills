#!/usr/bin/env bash
# Defect-fix test (no roadmap item — failures always count).
# roadmap-lint.sh DOCTRINE rules (user task id:baf1, part 3): each past LLM triage
# becomes a mechanical LOUD rule so these never silently accumulate again.
#
#   3(a) DECOMPOSED-CONTAINER (id:8504): an OPEN `- [ ]` item whose body says
#        DECOMPOSED (into seams) must NOT carry a dispatchable/meeting lane — it must
#        be TICKED or marked `@container`. LOUD always; nonzero only under --strict.
#   3(b) DECIDED-LEFT-OPEN (id:dafa): an OPEN item carrying DEFERRED / SUPERSEDED /
#        "decided <YYYY-MM-DD>" is a decided item left open. LOUD always; nonzero
#        only under --strict.
#
# Both must FAIL LOUD (stderr) and NEVER silently filter; items under a parked
# (Deferred/Gated/…) heading are exempt.
#
# Hermetic: temp ROADMAP fixtures; no ~/.claude, no network.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LINT="$ROOT/relay/scripts/roadmap-lint.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$LINT" ]] || fail "roadmap-lint.sh not found/executable at $LINT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Every item is grammar-valid (lane + id) so the ONLY thing under test is the two
# doctrine rules, never a confounding grammar violation.
R="$tmp/ROADMAP.md"
cat >"$R" <<'MD'
# Roadmap

## Items

- [ ] [HARD — meeting] DECOMPOSED into seams id:aaaa, id:bbbb <!-- id:c001 -->
- [ ] [HARD — meeting] DECOMPOSED into seams but properly marked @container <!-- id:c002 -->
- [x] [HARD — meeting] DECOMPOSED into seams and correctly ticked <!-- id:c003 -->
- [ ] [HARD — meeting] DEFERRED (decided 2026-06-17): a parked-in-active-section thing <!-- id:c004 -->
- [ ] [ROUTINE] SUPERSEDED by a newer plan <!-- id:c005 -->
- [ ] [ROUTINE] the plan was decided 2026-07-01 but never closed <!-- id:c006 -->
- [ ] [ROUTINE] a perfectly clean active item with no markers <!-- id:c007 -->

## Deferred

- [ ] [HARD — meeting] DEFERRED thing legitimately parked under a Deferred heading <!-- id:c008 -->
MD

# --- default (no --strict): doctrine rules are LOUD but report-only (exit 0) -----
set +e
out_default="$(bash "$LINT" "$R" 2>"$tmp/err")"; rc_default=$?
set -e
[[ $rc_default -eq 0 ]] || fail "default run must exit 0 (doctrine rules are WARN-only), got $rc_default (err: $(cat "$tmp/err"))"

# LOUD: the two violating classes are surfaced on stderr, never silently filtered.
grep -q 'DECOMPOSED-CONTAINER: open item id:c001' "$tmp/err" \
  || fail "3(a) did not LOUD-report the DECOMPOSED container c001 (err: $(cat "$tmp/err"))"
grep -q 'DECIDED-LEFT-OPEN: open item id:c004' "$tmp/err" \
  || fail "3(b) did not LOUD-report the DEFERRED item c004 (err: $(cat "$tmp/err"))"
grep -q 'DECIDED-LEFT-OPEN: open item id:c005' "$tmp/err" \
  || fail "3(b) did not LOUD-report the SUPERSEDED item c005 (err: $(cat "$tmp/err"))"
grep -q 'DECIDED-LEFT-OPEN: open item id:c006' "$tmp/err" \
  || fail "3(b) did not LOUD-report the 'decided <date>' item c006 (err: $(cat "$tmp/err"))"

# Default run is WARN (report-only), NOT ERROR.
grep -q 'WARN — DECOMPOSED-CONTAINER' "$tmp/err" \
  || fail "default DECOMPOSED report should be WARN-labelled (err: $(cat "$tmp/err"))"

# The container id reported is the item's OWN token (c001), not a seam id (aaaa/bbbb).
! grep -q 'DECOMPOSED-CONTAINER: open item id:aaaa' "$tmp/err" \
  || fail "3(a) mis-named the container by a seam id instead of its own token (err: $(cat "$tmp/err"))"

# (c) @container item and the ticked item do NOT fire; the clean item does NOT fire.
! grep -q 'id:c002' "$tmp/err" || fail "an @container-marked parent fired 3(a) (err: $(cat "$tmp/err"))"
! grep -q 'id:c003' "$tmp/err" || fail "a TICKED [x] item was linted (err: $(cat "$tmp/err"))"
! grep -q 'id:c007' "$tmp/err" || fail "a clean active item fired a doctrine rule (err: $(cat "$tmp/err"))"

# (d) an item under a parked Deferred heading is EXEMPT (never fires).
! grep -q 'id:c008' "$tmp/err" \
  || fail "an item under a parked Deferred heading fired a doctrine rule (err: $(cat "$tmp/err"))"

# --- --strict: the two rules become HARD violations (nonzero exit) ---------------
set +e
out_strict="$(bash "$LINT" --strict "$R" 2>"$tmp/err2")"; rc_strict=$?
set -e
[[ $rc_strict -ne 0 ]] || fail "--strict must exit nonzero when doctrine rules fire, got 0 (err: $(cat "$tmp/err2"))"
grep -q 'ERROR — DECOMPOSED-CONTAINER' "$tmp/err2" \
  || fail "--strict DECOMPOSED report should be ERROR-labelled (err: $(cat "$tmp/err2"))"
grep -q 'ERROR — DECIDED-LEFT-OPEN' "$tmp/err2" \
  || fail "--strict DECIDED report should be ERROR-labelled (err: $(cat "$tmp/err2"))"

# --strict order-independent: `--strict` accepted after the path too.
set +e
bash "$LINT" "$R" --strict >/dev/null 2>&1; rc_strict2=$?
set -e
[[ $rc_strict2 -ne 0 ]] || fail "--strict after the path arg should still escalate to nonzero"

pass "roadmap-lint doctrine rules 3(a)/3(b) fire LOUD on DECOMPOSED-container + decided-left-open, exempt ticked/@container/parked items, WARN-by-default and nonzero under --strict (baf1: 8504/dafa)"
