#!/usr/bin/env bash
# Defect-fix test (TODO id:d35a, not a ROADMAP item — no `# roadmap:` header; this
# file's failures always count).
#
# roadmap-lint.sh rule 3(g) PARKED-POOL-LANE (owner ruling 2026-08-27): a
# `### Visibility-only — human lane, NOT dispatchable` ROADMAP section was
# DISPATCHED to the relay pool because none of its words are in
# ROADMAP_PARKED_HEADING_WORDS, killing two Sonnet executors. The owner ruled TWO
# things; this test covers ruling (2) ONLY: `[ROUTINE]` (or `[HARD]`) must
# never appear on an item under an ALREADY-RECOGNIZED parked/human-lane heading —
# that combination is invalid on its face, a GRAMMAR violation (nonzero
# unconditionally, never gated behind --strict), not a judgement call.
#
# Ruling (1) — a SECTION must never be the mechanism, and
# ROADMAP_PARKED_HEADING_WORDS must NOT be widened — is explicitly NOT this test's
# concern; the last section below independently demonstrates the boundary that
# ruling draws (the loderite heading itself stays unrecognized, on purpose).
#
# Hermetic: temp ROADMAP/TODO fixtures; no ~/.claude, no network.
# fails-against: rev 7a8d0944ac1e -- the tree as it stood immediately before the commit that
#   added this test, i.e. the pre-fix relay/scripts/roadmap-lint.sh. Derived + verified by tests/verify-negative-cases.py.
# fails-against-rev: 7a8d0944ac1e -- relay/scripts/roadmap-lint.sh
# fails-against-assertion: lint must exit nonzero — [ROUTINE]/[HARD] under a parked heading are unconditional grammar violations (out:

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LINT="$ROOT/relay/scripts/roadmap-lint.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$LINT" ]] || fail "roadmap-lint.sh not found/executable at $LINT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# TODO.md twins for every id, so the unrelated NO-ACCEPTANCE-NO-TWIN doctrine rule
# (id:213a, WARN-only) never pollutes stderr / this test's greps — this file's
# concern is 3(g) alone.
cat >"$tmp/TODO.md" <<'MD'
# TODO
- [ ] twin stub <!-- id:a001 -->
- [ ] twin stub <!-- id:a002 -->
- [ ] twin stub <!-- id:a003 -->
- [ ] twin stub <!-- id:a004 -->
- [ ] twin stub <!-- id:a005 -->
- [ ] twin stub <!-- id:a006 -->
- [ ] twin stub <!-- id:a007 -->
- [ ] twin stub <!-- id:a008 -->
- [ ] twin stub <!-- id:a009 -->
- [ ] twin stub <!-- id:a00a -->
- [ ] twin stub <!-- id:a00b -->
- [ ] twin stub <!-- id:a00c -->
- [ ] twin stub <!-- id:a00d -->
- [ ] twin stub <!-- id:a00e -->
- [ ] twin stub <!-- id:a00f -->
- [ ] twin stub <!-- id:a010 -->
MD

R="$tmp/ROADMAP.md"
cat >"$R" <<'MD'
# Roadmap

## Items

- [ ] [ROUTINE] a perfectly clean active item, unrelated to this test <!-- id:a00c -->

## Gated / deferred

- [ ] [ROUTINE] a pool-executable lane wrongly left under a parked heading <!-- id:a001 -->
- [ ] [HARD] another pool-executable lane under the same parked heading <!-- id:a002 -->
- [ ] [INPUT - meeting] a human lane under a parked heading — legitimate <!-- id:a003 -->
- [ ] [INPUT - access] a human lane under a parked heading — legitimate <!-- id:a004 -->
- [ ] [MECHANICAL] pool-inert and human-inert — legitimate under a parked heading <!-- id:a005 -->
- [x] [ROUTINE] a CLOSED pool-executable item under a parked heading — never linted <!-- id:a006 -->
- [ ] [INPUT - access] human primary lane; prose mentions `[HARD - pool]` historically <!-- id:a00d -->
- [ ] [INPUT - meeting] human primary lane; was `[ROUTINE]`-tagged there historically <!-- id:a00e -->
- [ ] [INTENSIVE - local-llm] [HARD] resource-first composed run — still a violation <!-- id:a00f -->
- [ ] [HARD] [INTENSIVE - disk-io] lane-first composed run — still a violation <!-- id:a010 -->

## Deferred

- [ ] [INPUT - meeting] triage note one <!-- id:a007 -->
- [ ] [INPUT - meeting] triage note two <!-- id:a008 -->
- [ ] [INPUT - meeting] triage note three <!-- id:a009 -->
- [ ] [HARD] an appended executable item, north-star bare HARD — DOES trip the rule <!-- id:a00a -->
- [ ] [ROUTINE] an appended executable item that DOES trip the rule <!-- id:a00b -->
MD

set +e
out="$(bash "$LINT" "$R" 2>"$tmp/err")"; rc=$?
set -e

echo "$out" > "$tmp/out"

[[ $rc -ne 0 ]] || fail "lint must exit nonzero — [ROUTINE]/[HARD] under a parked heading are unconditional grammar violations (out: $out; err: $(cat "$tmp/err"))"

# --- violations fire, UNCONDITIONALLY (no --strict passed at all) ---------------
grep -q 'PARKED-POOL-LANE: open item id:a001' "$tmp/err" \
  || fail "[ROUTINE] under a parked heading did not fire 3(g) (err: $(cat "$tmp/err"))"
grep -q 'PARKED-POOL-LANE: open item id:a002' "$tmp/err" \
  || fail "[HARD] under a parked heading did not fire 3(g) (err: $(cat "$tmp/err"))"
grep -q 'PARKED-POOL-LANE: open item id:a00b' "$tmp/err" \
  || fail "the appended [ROUTINE] item after the [INPUT - meeting] chain did not fire 3(g) (err: $(cat "$tmp/err"))"

# The violation is reported to stdout too (the script's existing convention).
grep -q 'id:a001' "$tmp/out" || fail "3(g) violation for id:a001 missing from stdout report"
grep -q 'id:a002' "$tmp/out" || fail "3(g) violation for id:a002 missing from stdout report"

# --- ERROR label, not WARN — this is GRAMMAR, never gated behind --strict -------
grep -q 'ERROR — PARKED-POOL-LANE' "$tmp/err" \
  || fail "3(g) must report as ERROR (unconditional), not WARN (err: $(cat "$tmp/err"))"

# --- legitimate human lanes under the SAME parked heading stay silent -----------
! grep -q 'id:a003' "$tmp/err" || fail "[INPUT - meeting] under a parked heading wrongly fired 3(g) (err: $(cat "$tmp/err"))"
! grep -q 'id:a004' "$tmp/err" || fail "[INPUT - access] under a parked heading wrongly fired 3(g) (err: $(cat "$tmp/err"))"
! grep -q 'id:a005' "$tmp/err" || fail "[MECHANICAL] under a parked heading wrongly fired 3(g) (err: $(cat "$tmp/err"))"

# --- a CLOSED item is never linted, even with a pool-executable lane ------------
! grep -q 'id:a006' "$tmp/err" || fail "a CLOSED [x] pool-executable item under a parked heading wrongly fired 3(g) (err: $(cat "$tmp/err"))"

# --- unchanged behaviour: [ROUTINE] under an ACTIVE heading is fine as always ---
! grep -q 'id:a00c' "$tmp/err" || fail "[ROUTINE] under an ACTIVE heading wrongly fired 3(g) (err: $(cat "$tmp/err"))"

# --- real-world shape: 3 legitimate [INPUT - meeting] items, then an appended ---
# chain — only the appended EXECUTABLE ones fire, the meeting notes stay silent.
! grep -q 'id:a007' "$tmp/err" || fail "[INPUT - meeting] note one wrongly fired 3(g) (err: $(cat "$tmp/err"))"
! grep -q 'id:a008' "$tmp/err" || fail "[INPUT - meeting] note two wrongly fired 3(g) (err: $(cat "$tmp/err"))"
! grep -q 'id:a009' "$tmp/err" || fail "[INPUT - meeting] note three wrongly fired 3(g) (err: $(cat "$tmp/err"))"

# id:a00a carries the north-star BARE `[HARD]` tag. It IS in scope: id:4f02 makes
# `[HARD]` the 1:1 rename of `[HARD - pool]` (same disposition), `lane-convert.sh`
# auto-applies that rename with no human input, and the pre-commit lane ratchet
# BLOCKS the legacy spelling from new commits — so bare `[HARD]` is simply the
# current spelling of the pool-executable lane. Omitting it would have left the
# rule missing loderite dd4d S1/S4/S5, three of the five items in its own origin
# incident.
grep -q 'PARKED-POOL-LANE: open item id:a00a' "$tmp/err" \
  || fail "bare [HARD] under a parked heading did not fire 3(g) (err: $(cat "$tmp/err"))"

# --- ANCHORING: 3(g) reads the item's LEADING lane run, never the raw line ------
# Regression for a defect found by the 2026-08-27 fleet sweep: the first version
# matched $pool_lane_re against the whole line, so a BACKTICK'D audit-trail mention
# of a pool tag fired an ERROR on an item whose live primary lane is human. Three
# real false positives fleet-wide (loderite affd + 1e21, toesnail 8807).
! grep -q 'id:a00d' "$tmp/err" \
  || fail "[INPUT - access] item with a backtick'd [HARD - pool] prose mention wrongly fired 3(g) (err: $(cat "$tmp/err"))"
! grep -q 'id:a00e' "$tmp/err" \
  || fail "[INPUT - meeting] item with a backtick'd [ROUTINE] prose mention wrongly fired 3(g) (err: $(cat "$tmp/err"))"

# ...but a composed run still fires in BOTH orders. `[INTENSIVE - <res>]` is not a
# lane (it is the orthogonal resource axis) and is absent from all_lane_tags, so a
# resource-FIRST item would stop leading_lane_run dead and silently escape unless
# the resource brackets are stripped first. Relying on lane-first authoring
# convention is exactly the class id:d35a is about.
grep -q 'PARKED-POOL-LANE: open item id:a00f' "$tmp/err" \
  || fail "resource-first [INTENSIVE - local-llm] [HARD] under a parked heading did not fire 3(g) (err: $(cat "$tmp/err"))"
grep -q 'PARKED-POOL-LANE: open item id:a010' "$tmp/err" \
  || fail "lane-first [HARD] [INTENSIVE - disk-io] under a parked heading did not fire 3(g) (err: $(cat "$tmp/err"))"

pass "3(g) PARKED-POOL-LANE: [ROUTINE]/[HARD]/legacy [HARD - pool] under a parked heading are unconditional violations; human lanes + [MECHANICAL] + closed items + active-heading items stay silent (id:d35a)"

# =================================================================================
# Independent re-derivation against the ORIGINAL incident shape (ruling (1) check).
#
# The loderite heading was `### Visibility-only — human lane, NOT dispatchable` —
# NONE of its words ("visibility-only", "human", "lane", "not", "dispatchable")
# match ROADMAP_PARKED_HEADING_WORDS (gated|deferred|done|icebox|archive|parked),
# so it is NOT recognized as an exempt heading by the current (deliberately
# unwidened, per ruling 1) vocabulary. An item under it is therefore linted as an
# ORDINARY ACTIVE item — and a well-formed `[ROUTINE] ... <!-- id --> `item passes
# the ordinary grammar cleanly. This is NOT a gap in 3(g); it is the exact boundary
# ruling (1) draws (a SECTION must never be the mechanism) and is why 3(g) exists
# as a SEPARATE, orthogonal check rather than a fix bundled into the heading
# vocabulary. Report this direction honestly: 3(g) does NOT and CANNOT catch this
# shape without ruling (1) being violated.
# =================================================================================
cat >"$tmp/TODO2.md" <<'MD'
# TODO
- [ ] twin stub <!-- id:b001 -->
MD
R2="$tmp/ROADMAP2.md"
cat >"$R2" <<'MD'
# Roadmap

### Visibility-only — human lane, NOT dispatchable

- [ ] [ROUTINE] the exact loderite incident shape, verbatim heading <!-- id:b001 -->
MD

set +e
out2="$(bash "$LINT" "$R2" 2>"$tmp/err2")"; rc2=$?
set -e

[[ $rc2 -eq 0 ]] \
  || fail "UNEXPECTED: the unrecognized loderite heading now fails the lint some other way — investigate before assuming 3(g) covers it (out: $out2; err: $(cat "$tmp/err2"))"
! grep -q 'PARKED-POOL-LANE' "$tmp/err2" \
  || fail "UNEXPECTED: 3(g) fired on a heading that ROADMAP_PARKED_HEADING_WORDS does NOT recognize as exempt — this would mean 3(g) is silently reaching outside exempt sections, which ruling (1) forbids"

pass "independent re-derivation: the verbatim loderite heading stays UNRECOGNIZED (ruling 1, untouched) and 3(g) correctly does not fire there — this failure direction is NOT covered by 3(g) and is explicitly out of scope for it"
