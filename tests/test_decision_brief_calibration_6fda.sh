#!/usr/bin/env bash
# Defect-fix / new-feature spec for id:6fda. No `# roadmap:` header (id:6fda lives only in
# TODO.md), so these failures always count.
#
# THE GUARD THIS PINS, and the incident behind it.
#
# `leading_lane_run` (relay/scripts/lib-lane-anchor.sh) reads its vocabulary from the
# caller-supplied global array `all_lane_tags`. SOURCING the library does NOT populate that
# array -- only a successful `lane_vocab_scrape <doc>` call does. A probe that sources and
# forgets the scrape therefore answers "no lane" for EVERY line on earth and reports a
# clean, confident zero. That was hit live on 2026-09-11 while building this skill.
#
# An unpopulated probe is an UNREACHED FIXTURE, not a negative control, and the correct
# response to one is a REFUSAL, not a degraded answer: a wrong count looks like an answer,
# whereas a refusal does not. So `docket.sh` runs controls with known answers before
# emitting any row or any count, and exits 3 having emitted NOTHING countable if any fails.
#
# The controls are deliberately of BOTH polarities. A probe that says "yes" to everything
# passes every positive control and is exactly as broken as one that says "no" to
# everything -- so this file asserts a positive control, a negative control, AND the
# refusal path, because any one of the three alone is satisfiable by a broken probe.
#
# The classifier controls (c) matter separately from the probe controls: the first
# implementation of `primary_decision_lane` took the run's first token with `${run%% *}`,
# which splits INSIDE `[INPUT - meeting]` because a lane tag contains spaces. That version
# passed every non-emptiness control and still suppressed all 158 candidates on this repo.
# Non-emptiness is not enough; the control must assert the exact parsed value.
#
# HERMETIC: temp HOME and temp roots under `mktemp -d`; reads this repo's scripts read-only
# and touches no ~/.claude, no ~/.cache/relay, no network.
#
# fails-against-mutation: sed -i 's|LANES_DOC="${DECISION_BRIEF_LANES_DOC:-$RELAY_SCRIPTS/../references/hard-lanes.md}"|LANES_DOC="$RELAY_SCRIPTS/../references/hard-lanes.md"|' decision-brief/docket.sh
# fails-against-assertion: (b2) a refused scan still emitted ROW/COVERAGE records
#   The mutation drops the lane-vocabulary override, so the gate can no longer be shown a
#   broken probe and never refuses. Several assertions fire; this names the LAST, which is
#   also the one that matters most -- a gate that refuses but still prints a count has
#   prevented nothing.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/decision-brief/docket.sh"

fails=0
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }

[[ -x "$SCRIPT" ]] || { echo "FAIL: docket.sh not found or not executable at $SCRIPT"; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/home"

run_calibrate() {  # run_calibrate [lanes-doc-override]
  local doc="${1:-$ROOT/relay/references/hard-lanes.md}"
  HOME="$tmp/home" \
  DECISION_BRIEF_RELAY_SCRIPTS="$ROOT/relay/scripts" \
  DECISION_BRIEF_LANES_DOC="$doc" \
    bash "$SCRIPT" calibrate 2>"$tmp/err.txt"
}

# --- (a) the POSITIVE case: with the real vocabulary the gate passes ------------------
# Without this, a gate that refused unconditionally would satisfy (b) and (c) and be
# useless. This is the control on the controls.
out="$(run_calibrate)"; rc=$?
if [[ $rc -ne 0 ]]; then
  fail "(a) calibration refused against the REAL lane vocabulary (exit $rc): $out"
elif [[ "$(printf '%s' "$out" | cut -f1)" != "CALIBRATION" || "$(printf '%s' "$out" | cut -f2)" != "ok" ]]; then
  fail "(a) calibration against the real vocabulary did not report ok: $out"
else
  pass "(a) the gate passes against the real lane vocabulary"
fi

if ! grep -q 'controls=' <<<"$out"; then
  fail "(a) the ok line does not report how many controls ran -- an unfalsifiable ok"
else
  pass "(a) the ok line names the control count ($(grep -o 'controls=[0-9/]*' <<<"$out"))"
fi

# --- (b) the REFUSAL: an unreadable vocabulary must refuse, not degrade ---------------
out="$(run_calibrate "$tmp/no-such-lanes-doc.md")"; rc=$?
if [[ $rc -ne 3 ]]; then
  fail "(b) an unreadable lane vocabulary did NOT produce the calibration refusal (exit $rc, expected 3)"
else
  pass "(b) an unreadable lane vocabulary exits 3"
fi

if ! grep -q '^CALIBRATION.*FAILED' <<<"$out"; then
  fail "(b) the refusal did not emit a CALIBRATION FAILED record: $out"
else
  pass "(b) the refusal is emitted as a machine-readable CALIBRATION FAILED record"
fi

if ! grep -qi 'refus' "$tmp/err.txt"; then
  fail "(b) the refusal was silent on stderr -- it must be LOUD, not just a nonzero exit"
else
  pass "(b) the refusal is loud on stderr"
fi

# --- (b2) a refusal must emit NO countable output ------------------------------------
# This is the whole point: the failure mode being prevented is a confident wrong COUNT,
# so a gate that refuses but still prints rows or coverage has not prevented anything.
mkdir -p "$tmp/cfg" "$tmp/src/demo"
cat > "$tmp/src/demo/TODO.md" <<'EOF'
# TODO

## Current
- [ ] [INPUT - decision] **A real decision item** <!-- id:aaaa -->
EOF
cat > "$tmp/cfg/relay.toml" <<EOF
[repos.demo]
classification = "own"
path = "$tmp/src/demo"
EOF

scan_out="$(HOME="$tmp/home" SRC_DIR="$tmp/src" RELAY_TOML="$tmp/cfg/relay.toml" \
  DECISION_BRIEF_RELAY_SCRIPTS="$ROOT/relay/scripts" \
  DECISION_BRIEF_LANES_DOC="$tmp/no-such-lanes-doc.md" \
  bash "$SCRIPT" scan 2>/dev/null)"
scan_rc=$?

if [[ $scan_rc -ne 3 ]]; then
  fail "(b2) scan with a broken probe exited $scan_rc, expected the refusal 3"
else
  pass "(b2) scan refuses rather than scanning with a probe it cannot trust"
fi

if grep -qE '^(ROW|COVERAGE)' <<<"$scan_out"; then
  fail "(b2) a refused scan still emitted ROW/COVERAGE records -- it reported a count it could not trust"
else
  pass "(b2) a refused scan emits no ROW and no COVERAGE record"
fi

# --- (c) the classifier controls are real, not non-emptiness checks -------------------
# Driven through the documented CLI rather than by sourcing internals, so the assertion
# pins BEHAVIOUR and survives a refactor. The fixture's lane tag CONTAINS SPACES, which is
# the shape that defeated the first implementation.
cat > "$tmp/src/demo/TODO.md" <<'EOF'
# TODO

## Current
- [ ] [INPUT - meeting] **A lane tag that contains spaces** <!-- id:aaaa -->
- [ ] [ROUTINE] **Not the owner's decision** <!-- id:bbbb -->
EOF

ok_out="$(HOME="$tmp/home" SRC_DIR="$tmp/src" RELAY_TOML="$tmp/cfg/relay.toml" \
  DECISION_BRIEF_RELAY_SCRIPTS="$ROOT/relay/scripts" \
  bash "$SCRIPT" scan 2>/dev/null)"

lane="$(awk -F'\t' '$1=="ROW" && $5=="aaaa" { print $6; exit }' <<<"$ok_out")"
if [[ "$lane" != '[INPUT - meeting]' ]]; then
  fail "(c) a lane tag containing spaces parsed as '$lane', expected '[INPUT - meeting]' -- the classifier splits inside the tag"
else
  pass "(c) a lane tag containing spaces parses to its exact canonical value"
fi

if awk -F'\t' '$1=="ROW" && $5=="bbbb" { found=1 } END { exit !found }' <<<"$ok_out"; then
  fail "(c) a [ROUTINE] item was docketed as an owner decision -- the classifier says yes to everything"
else
  pass "(c) the classifier also says NO: a [ROUTINE] item is not an owner decision"
fi

echo
if [[ $fails -eq 0 ]]; then
  echo "ALL PASS: decision-brief calibration gate (id:6fda)"
  exit 0
fi
echo "$fails assertion(s) failed"
exit 1
