#!/usr/bin/env bash
# roadmap:49e0
# roadmap-lint.sh DOCTRINE rule 3(d) DEAD-GATE (id:49e0).
#
# A `<!-- gated-on:XXXX -->` marker whose target is NOT a dispatchable ROADMAP item
# reads as "waiting" but means "never": the gated item is deliberately unpickable, so
# it sits in the execution queue looking *scheduled* while nothing can ever clear it.
# THREE real instances surfaced on 2026-07-31 (a955→87f5, 8123→1a34, f6d5→8ba1), each
# caught only by a human noticing.
#
# The rule: for every `<!-- gated-on:CSV -->` on an OPEN, ACTIVE-section, top-level
# ROADMAP item, every target token must EXIST as a checkbox item in ROADMAP.md itself.
# A target that lives only in TODO.md (never promoted), only in TODO.archive.md
# (retired — the gate is permanent), or nowhere at all is a LOUD finding naming BOTH
# ids. A target that is an open OR ticked ROADMAP checkbox is a clean pass — a ticked
# target means the gate is satisfied, not dead.
#
# Tiering follows the existing doctrine rules 3(a)/3(b)/3(c): WARN + report-only by
# default (exit 0), ERROR + nonzero under --strict. No third tier is invented.
#
# Hermetic: temp ROADMAP/TODO fixtures in mktemp -d; no ~/.claude, no network.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LINT="$ROOT/relay/scripts/roadmap-lint.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$LINT" ]] || fail "roadmap-lint.sh not found/executable at $LINT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# ---------------------------------------------------------------------------
# Part 1 — the ROADMAP item's literal acceptance fixture:
#   a gated-on pointing at (i) a TODO-only id, (ii) a retired/archived id, and
#   (iii) a valid open ROADMAP item ⇒ EXACTLY two loud findings and one pass.
# ---------------------------------------------------------------------------
acc="$tmp/acc"
mkdir -p "$acc"

cat >"$acc/TODO.md" <<'MD'
# TODO
- [ ] the TODO-only target, never promoted to ROADMAP <!-- id:d001 -->
- [ ] twin stub <!-- id:9a01 -->
- [ ] twin stub <!-- id:9a02 -->
- [ ] twin stub <!-- id:9a03 -->
- [ ] twin stub <!-- id:d003 -->
MD

cat >"$acc/TODO.archive.md" <<'MD'
# TODO archive
- [x] **[SUPERSEDED 2026-07-24 — retired, NOT built]** the archived target <!-- id:d002 -->
MD

cat >"$acc/ROADMAP.md" <<'MD'
# Roadmap

## Items

- [ ] [ROUTINE] gated on a TODO-only id <!-- gated-on:d001 --> <!-- id:9a01 -->
- [ ] [ROUTINE] gated on a retired/archived id <!-- gated-on:d002 --> <!-- id:9a02 -->
- [ ] [ROUTINE] gated on a valid open ROADMAP item <!-- gated-on:d003 --> <!-- id:9a03 -->
- [ ] [ROUTINE] the valid open gate target itself <!-- id:d003 -->
MD

set +e
bash "$LINT" "$acc/ROADMAP.md" >"$acc/out" 2>"$acc/err"; rc_acc=$?
set -e

[[ $rc_acc -eq 0 ]] || fail "acceptance fixture: default run must exit 0 (DEAD-GATE is WARN-only), got $rc_acc (err: $(cat "$acc/err"))"

n_findings="$(grep -c 'DEAD-GATE' "$acc/err" || true)"
[[ "$n_findings" -eq 2 ]] \
  || fail "acceptance: expected EXACTLY 2 DEAD-GATE findings, got $n_findings (err: $(cat "$acc/err"))"

# Both ids named in each finding — actionable without a lookup.
grep -q 'DEAD-GATE.*id:9a01.*d001' "$acc/err" \
  || fail "acceptance (i): the TODO-only case must name BOTH the gated id 9a01 and its target d001 (err: $(cat "$acc/err"))"
grep -q 'DEAD-GATE.*id:9a02.*d002' "$acc/err" \
  || fail "acceptance (ii): the retired case must name BOTH the gated id 9a02 and its target d002 (err: $(cat "$acc/err"))"
! grep -q 'DEAD-GATE.*id:9a03' "$acc/err" \
  || fail "acceptance (iii): a gate on a valid open ROADMAP item must PASS (err: $(cat "$acc/err"))"

# The two classes are distinguishable — a missing target and a retired one need
# different remedies (promote it vs drop/re-target the marker).
grep -qi 'DEAD-GATE.*id:9a01.*TODO.md' "$acc/err" \
  || fail "acceptance (i): the finding should say the target lives only in TODO.md (err: $(cat "$acc/err"))"
grep -qiE 'DEAD-GATE.*id:9a02.*(archive|retired)' "$acc/err" \
  || fail "acceptance (ii): the finding should say the target is archived/retired (err: $(cat "$acc/err"))"

# ---------------------------------------------------------------------------
# Part 2 — the surrounding contract: which shapes fire and which must not.
# ---------------------------------------------------------------------------
b="$tmp/b"
mkdir -p "$b"

cat >"$b/TODO.md" <<'MD'
# TODO
- [ ] TODO-only target <!-- id:d001 -->
- [ ] twin stub <!-- id:e001 -->
- [ ] twin stub <!-- id:e002 -->
- [ ] twin stub <!-- id:e003 -->
- [ ] twin stub <!-- id:e004 -->
- [ ] twin stub <!-- id:e005 -->
- [ ] twin stub <!-- id:e006 -->
- [ ] twin stub <!-- id:e007 -->
- [ ] twin stub <!-- id:e008 -->
- [ ] twin stub <!-- id:d003 -->
- [ ] twin stub <!-- id:d004 -->
MD

cat >"$b/TODO.archive.md" <<'MD'
# TODO archive
- [x] retired target <!-- id:d002 -->
MD

cat >"$b/ROADMAP.md" <<'MD'
# Roadmap

## Items

- [ ] [ROUTINE] gated on a TODO-only id <!-- gated-on:d001 --> <!-- id:e001 -->
- [x] [ROUTINE] CLOSED item gated on a TODO-only id — moot, never linted <!-- gated-on:d001 --> <!-- id:e002 -->
- [ ] [ROUTINE] gated on a TICKED ROADMAP item — gate SATISFIED, a clean pass <!-- gated-on:d004 --> <!-- id:e003 -->
- [ ] [ROUTINE] gated on an id that exists nowhere at all <!-- gated-on:d0ff --> <!-- id:e004 -->
- [ ] [ROUTINE] CSV gate — one good target, one archived <!-- gated-on:d003,d002 --> <!-- id:e005 -->
- [ ] [ROUTINE] a prose mention of gated-on:d001 in backticks `gated-on:d001` is NOT an edge <!-- id:e006 -->
- [ ] [ROUTINE] the valid open gate target itself <!-- id:d003 -->
- [x] [ROUTINE] a ticked ROADMAP gate target <!-- id:d004 -->

## Deferred

- [ ] [INPUT — meeting] parked item gated on a TODO-only id — section-exempt <!-- gated-on:d001 --> <!-- id:e007 -->
MD

set +e
bash "$LINT" "$b/ROADMAP.md" >"$b/out" 2>"$b/err"; rc_b=$?
set -e
[[ $rc_b -eq 0 ]] || fail "part 2: default run must exit 0, got $rc_b (err: $(cat "$b/err"))"

grep -q 'WARN — DEAD-GATE' "$b/err" \
  || fail "the default-run DEAD-GATE report must be WARN-labelled (err: $(cat "$b/err"))"

grep -q 'DEAD-GATE.*id:e001' "$b/err" || fail "e001 (TODO-only target) must fire (err: $(cat "$b/err"))"
grep -q 'DEAD-GATE.*id:e004.*d0ff' "$b/err" || fail "e004 (target exists nowhere) must fire and name d0ff (err: $(cat "$b/err"))"
grep -q 'DEAD-GATE.*id:e005.*d002' "$b/err" || fail "e005 (CSV gate with an archived member) must fire naming d002 (err: $(cat "$b/err"))"
if grep -q 'd003' < <(grep 'DEAD-GATE.*id:e005' "$b/err") ; then
  fail "e005 must name ONLY the dead target d002, not the healthy d003 (err: $(cat "$b/err"))"
fi

! grep -q 'DEAD-GATE.*id:e002' "$b/err" || fail "a CLOSED [x] item must never be dead-gate linted (err: $(cat "$b/err"))"
! grep -q 'DEAD-GATE.*id:e003' "$b/err" || fail "a gate on a TICKED ROADMAP target is satisfied, not dead (err: $(cat "$b/err"))"
! grep -q 'DEAD-GATE.*id:e006' "$b/err" || fail "a backticked prose 'gated-on:' mention is not a typed edge (id:4da4/0d58) (err: $(cat "$b/err"))"
! grep -q 'DEAD-GATE.*id:e007' "$b/err" || fail "an item under a parked Deferred heading is section-exempt (err: $(cat "$b/err"))"

# --- --strict escalates DEAD-GATE to ERROR + nonzero, like every doctrine rule ---
set +e
bash "$LINT" --strict "$b/ROADMAP.md" >/dev/null 2>"$b/err2"; rc_bs=$?
set -e
[[ $rc_bs -ne 0 ]] || fail "--strict must exit nonzero when DEAD-GATE fires"
grep -q 'ERROR — DEAD-GATE' "$b/err2" \
  || fail "--strict DEAD-GATE report must be ERROR-labelled (err: $(cat "$b/err2"))"

# --- a ROADMAP with no gated-on markers at all is a clean no-op -----------------
c="$tmp/c"; mkdir -p "$c"
cat >"$c/TODO.md" <<'MD'
# TODO
- [ ] twin stub <!-- id:f001 -->
MD
cat >"$c/ROADMAP.md" <<'MD'
# Roadmap

## Items

- [ ] [ROUTINE] an ungated item <!-- id:f001 -->
MD
set +e
bash "$LINT" "$c/ROADMAP.md" >/dev/null 2>"$c/err"; rc_c=$?
set -e
[[ $rc_c -eq 0 ]] || fail "an ungated ROADMAP must stay a clean zero-exit no-op, got $rc_c"
! grep -q 'DEAD-GATE' "$c/err" || fail "DEAD-GATE fired on a ROADMAP with no gates (err: $(cat "$c/err"))"

pass "roadmap-lint 3(d) DEAD-GATE: a gated-on target that is not a ROADMAP checkbox (TODO-only / archived-retired / absent) fires LOUD naming both ids; ticked + open ROADMAP targets pass; closed/parked/backticked shapes exempt; WARN by default, ERROR under --strict (id:49e0)"
