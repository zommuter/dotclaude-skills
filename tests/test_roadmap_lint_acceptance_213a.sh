#!/usr/bin/env bash
# roadmap:213a
# roadmap-lint.sh: NO-ACCEPTANCE-NO-TWIN doctrine rule (id:213a).
#
# Defect: the lint's grammar was exactly two clauses (recognized lane tag + 4-hex
# id) plus the two doctrine WARN rules — none of them inspects the item BODY. So a
# bare one-liner with no Acceptance/Tests/Done-check clause and no TODO.md twin
# passes lint and lands in the dispatchable lane with nothing telling an executor
# what "done" means (evidence: loderite's id:3801-minted seams 182c/6258/f0ec were
# exactly this shape).
#
# Clause: an OPEN item with NO Acceptance/Tests/Done-check clause in its own body
# AND no mirrored twin occurrence in TODO.md/TODO.archive.md is structurally
# un-workable → flag it. ALL LANES (twin-check alone discriminates on real data,
# owner 2026-07-26). Same WARN-by-default / ERROR-under---strict shape as the
# existing doctrine rules (3a/3b) — this is a past-triage pattern mechanized, not
# a positive-grammar clause that always fails.
#
# False-positive guard: a QUALIFIED heading like `**Done-check (when built)**`
# (the real shape of id:89bb/8a5c in this repo's own ROADMAP.md) must still count
# as a present clause — a naive `\*\*Done-check\*\*` exact-match regex misses it.
#
# Hermetic: temp ROADMAP + TODO fixtures; no ~/.claude, no network.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LINT="$ROOT/relay/scripts/roadmap-lint.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$LINT" ]] || fail "roadmap-lint.sh not found/executable at $LINT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

R="$tmp/ROADMAP.md"
cat >"$R" <<'MD'
# Roadmap

## Items

- [ ] [ROUTINE] a bare one-liner with no body clause and no TODO twin <!-- id:e001 -->
- [ ] [ROUTINE] a bare one-liner but WITH a TODO twin elsewhere <!-- id:e002 -->
  - **Context**: promoted from TODO `routed:e002`, no Acceptance/Tests/Done-check here.
- [ ] [ROUTINE] a properly speced item <!-- id:e003 -->
  - **Acceptance**: what "done" means.
  - **Tests**: `tests/test_e003.sh`
  - **Done-check**: `tests/run-tests.sh tests/test_e003.sh`
- [ ] [ROUTINE] a speced item using QUALIFIED headings (id:89bb/8a5c shape) <!-- id:e004 -->
  - **Acceptance (draft)**: still being refined.
  - **Done-check (when built)**: `tests/run-tests.sh tests/test_e004.sh`
- [x] [ROUTINE] a ticked bare one-liner, never linted at all <!-- id:e005 -->

## Deferred

- [ ] [INPUT — meeting] a bare one-liner parked under a Deferred heading <!-- id:e006 -->
MD

cat >"$tmp/TODO.md" <<'MD'
# TODO

- [ ] some design-ledger mirror of the e002 item <!-- id:e002 -->
MD

# --- default (no --strict): the new rule is LOUD but report-only (exit 0) -------
set +e
out_default="$(bash "$LINT" "$R" 2>"$tmp/err")"; rc_default=$?
set -e
[[ $rc_default -eq 0 ]] || fail "default run must exit 0 (new rule is WARN-only), got $rc_default (err: $(cat "$tmp/err"))"

grep -q 'NO-ACCEPTANCE-NO-TWIN: open item id:e001' "$tmp/err" \
  || fail "did not LOUD-report the untwinned/unspeced item e001 (err: $(cat "$tmp/err"))"
grep -q 'WARN — NO-ACCEPTANCE-NO-TWIN' "$tmp/err" \
  || fail "default report should be WARN-labelled (err: $(cat "$tmp/err"))"

# A TODO twin exempts an otherwise-bare item.
! grep -q 'NO-ACCEPTANCE-NO-TWIN: open item id:e002' "$tmp/err" \
  || fail "an item with a TODO.md twin fired NO-ACCEPTANCE-NO-TWIN (err: $(cat "$tmp/err"))"

# A properly-speced item (exact heading names) does not fire.
! grep -q 'id:e003' "$tmp/err" \
  || fail "a properly speced item fired NO-ACCEPTANCE-NO-TWIN (err: $(cat "$tmp/err"))"

# A QUALIFIED heading (id:89bb/8a5c false-positive-guard shape) must still count
# as a present clause — must NOT fire.
! grep -q 'id:e004' "$tmp/err" \
  || fail "a qualified '**Done-check (when built)**' heading false-positived NO-ACCEPTANCE-NO-TWIN (err: $(cat "$tmp/err"))"

# A ticked item is never linted at all.
! grep -q 'id:e005' "$tmp/err" \
  || fail "a ticked [x] item fired NO-ACCEPTANCE-NO-TWIN (err: $(cat "$tmp/err"))"

# An item under a parked Deferred heading is exempt.
! grep -q 'id:e006' "$tmp/err" \
  || fail "an item under a parked Deferred heading fired NO-ACCEPTANCE-NO-TWIN (err: $(cat "$tmp/err"))"

# --- --strict: the rule becomes a HARD violation (nonzero exit) -----------------
set +e
out_strict="$(bash "$LINT" --strict "$R" 2>"$tmp/err2")"; rc_strict=$?
set -e
[[ $rc_strict -ne 0 ]] || fail "--strict must exit nonzero when NO-ACCEPTANCE-NO-TWIN fires, got 0 (err: $(cat "$tmp/err2"))"
grep -q 'ERROR — NO-ACCEPTANCE-NO-TWIN' "$tmp/err2" \
  || fail "--strict report should be ERROR-labelled (err: $(cat "$tmp/err2"))"

pass "roadmap-lint NO-ACCEPTANCE-NO-TWIN doctrine rule (id:213a) flags a bare unspeced+untwinned item, tolerates qualified Acceptance/Tests/Done-check headings, respects TODO twins + ticked/parked exemptions, WARN-by-default and nonzero under --strict"
