#!/usr/bin/env bash
# roadmap:cb3e — Committed fixture snapshot for the WARN→ERROR boundary (gated on
# id:5533's shared state-claim predicate; meeting D3/A1, REPLACES the refuted
# git-blame dating).
#
# Mechanism: a checked-in baseline file (relay/state-claim-baseline.txt) captures
# the ids that were ALREADY tripping lib-state-claim.sh's state_claim_violation()
# at rule-land time. roadmap-lint.sh / todo-conformance.sh check an offending
# item's id against that baseline (state_claim_in_baseline): a BASELINED id stays
# WARN forever, even under --strict; a "new" id (absent from the baseline)
# escalates to ERROR under --strict, exactly as id:5533 already wired.
#
# Acceptance fixture (the item's own spec): an item whose line is rewritten
# WHOLESALE (as meeting/md-merge.py does — it replaces WHOLE LINES by id token,
# the mandated edit path for /meeting write-back, /relay human, and todo-update)
# STAYS in the WARN tier. Membership is by ID, not by line text — this is
# precisely what killed the earlier git-blame author-time approach, which dates
# the last EDIT rather than the item's creation.
#
# Hermetic: fixture ledgers + a fixture baseline file in mktemp -d, never ~/.claude
# and never the real checked-in relay/state-claim-baseline.txt.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$ROOT/relay/scripts/lib-state-claim.sh"
LINT="$ROOT/relay/scripts/roadmap-lint.sh"
TODOC="$ROOT/relay/scripts/todo-conformance.sh"
REAL_BASELINE="$ROOT/relay/state-claim-baseline.txt"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$REAL_BASELINE" ]] || fail "checked-in baseline file not found at $REAL_BASELINE"
pass "committed baseline snapshot exists at relay/state-claim-baseline.txt"

grep -qi 'stale baseline' "$REAL_BASELINE" \
  || fail "baseline file does not document the known weakness (a stale baseline silently re-grandfathers)"
pass "baseline file documents its known weakness in its own header"

grep -q 'state_claim_in_baseline' "$LIB" || fail "lib-state-claim.sh has no state_claim_in_baseline function"
bash -n "$LIB" || fail "lib-state-claim.sh fails bash -n"
pass "lib-state-claim.sh exposes state_claim_in_baseline"

grep -q 'STATE_CLAIM_BASELINE' "$LINT" || fail "roadmap-lint.sh does not wire the baseline"
grep -q 'STATE_CLAIM_BASELINE' "$TODOC" || fail "todo-conformance.sh does not wire the baseline"
pass "both linters wire the baseline"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# --- fixture baseline: only id:b001 is "already open at rule-land time" ---------
BL="$tmp/baseline.txt"
cat >"$BL" <<'TXT'
# fixture baseline
b001
TXT

# --- direct engine test: membership is by id only --------------------------------
source "$LIB"
state_claim_in_baseline "b001" "$BL" || fail "b001 should be found in the fixture baseline"
! state_claim_in_baseline "b002" "$BL" || fail "b002 should NOT be found in the fixture baseline"
! state_claim_in_baseline "" "$BL" || fail "an empty id must never match"
! state_claim_in_baseline "b001" "$tmp/does-not-exist.txt" || fail "a missing baseline file must fail OPEN (not baselined), never silently grandfather everything"
pass "state_claim_in_baseline: presence check is exact, empty-id-safe, missing-file-safe"

# --- roadmap-lint.sh: baselined id stays WARN under --strict, non-exit ----------
R="$tmp/ROADMAP.md"
cat >"$R" <<'MD'
# Roadmap

## Items

- [ ] [ROUTINE] baselined item — RESOLVED 2026-07-19 <!-- id:b001 -->
- [ ] [ROUTINE] a brand new item — RESOLVED 2026-07-19 <!-- id:b002 -->
MD

set +e
out="$(STATE_CLAIM_BASELINE="$BL" bash "$LINT" --strict "$R" 2>"$tmp/err")"; rc=$?
set -e
grep -q 'id:b001' "$tmp/err" || fail "baselined item id:b001 must still be REPORTED (never silently dropped): $(cat "$tmp/err")"
grep -q 'WARN (baselined id:cb3e)' "$tmp/err" || fail "baselined item id:b001 must be labelled WARN even under --strict: $(cat "$tmp/err")"
grep -q 'id:b002' "$tmp/err" || fail "new item id:b002 must be reported: $(cat "$tmp/err")"
[[ $rc -ne 0 ]] || fail "a NEW (non-baselined) violation under --strict must still fail the run (rc=$rc)"
pass "roadmap-lint.sh --strict: baselined id:b001 stays WARN (non-failing), new id:b002 still fails the run"

# Without --strict, only b002's baseline status shouldn't matter — both report, exit 0.
set +e
out2="$(STATE_CLAIM_BASELINE="$BL" bash "$LINT" "$R" 2>"$tmp/err2")"; rc2=$?
set -e
[[ $rc2 -eq 0 ]] || fail "non-strict run must exit 0 regardless of baseline; got $rc2"
pass "roadmap-lint.sh non-strict: exits 0 with or without baseline hits"

# --- acceptance fixture: a WHOLESALE line rewrite (md-merge.py's edit path) -----
# keeps the SAME id but completely different prose/wording. Membership is by id,
# so the rewritten line must STILL be baselined (WARN, not ERROR) under --strict.
R2="$tmp/ROADMAP_rewritten.md"
cat >"$R2" <<'MD'
# Roadmap

## Items

- [ ] [ROUTINE] a totally different sentence, fully reworded by md-merge — SUPERSEDED by something else entirely <!-- id:b001 -->
MD
set +e
STATE_CLAIM_BASELINE="$BL" bash "$LINT" --strict "$R2" >/dev/null 2>"$tmp/err3"; rc3=$?
set -e
[[ $rc3 -eq 0 ]] || fail "a wholesale line rewrite of a baselined id must stay non-failing under --strict (rc=$rc3): $(cat "$tmp/err3")"
grep -q 'WARN (baselined id:cb3e)' "$tmp/err3" || fail "rewritten baselined line must still report as WARN: $(cat "$tmp/err3")"
pass "id-only baseline membership survives a wholesale line rewrite (md-merge.py edit path)"

# --- todo-conformance.sh: same baseline, same verdict ---------------------------
T="$tmp/TODO.md"
cat >"$T" <<'MD'
# TODO

## Current
- [ ] baselined item — RESOLVED 2026-07-19 <!-- id:b001 -->
- [ ] a brand new item — RESOLVED 2026-07-19 <!-- id:b002 -->
MD

tout="$(STATE_CLAIM_BASELINE="$BL" bash "$TODOC" "$T" 2>/dev/null)"
grep -qP 'baselined id:cb3e.*id:b001' <<<"$tout" \
  || fail "todo-conformance.sh must report id:b001 as baselined:
$tout"
grep -qP '^decided-left-open\t\d+\t.*id:b002' <<<"$tout" \
  || fail "todo-conformance.sh must report id:b002 as a plain (non-baselined) finding:
$tout"
pass "todo-conformance.sh reports baselined vs new state-claim findings distinctly"

set +e
STATE_CLAIM_BASELINE="$BL" bash "$TODOC" --strict "$T" >/dev/null 2>/dev/null; trc=$?
set -e
[[ $trc -ne 0 ]] || fail "todo-conformance.sh --strict must still fail when a NEW (non-baselined) violation is present (id:b002)"
pass "todo-conformance.sh --strict fails on the new violation despite the baselined one being present"

# Baseline-only ledger (drop id:b002) must pass --strict cleanly.
T2="$tmp/TODO_only_baselined.md"
cat >"$T2" <<'MD'
# TODO

## Current
- [ ] baselined item — RESOLVED 2026-07-19 <!-- id:b001 -->
MD
set +e
STATE_CLAIM_BASELINE="$BL" bash "$TODOC" --strict "$T2" >/dev/null 2>/dev/null; trc2=$?
set -e
[[ $trc2 -eq 0 ]] || fail "todo-conformance.sh --strict must exit 0 when the only state-claim hit is baselined (rc=$trc2)"
pass "todo-conformance.sh --strict: an all-baselined ledger is non-failing"

echo "ALL PASS: id:cb3e WARN→ERROR boundary baseline"
