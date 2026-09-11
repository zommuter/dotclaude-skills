#!/usr/bin/env bash
# Defect-fix / new-feature spec for id:6fda (`decision-brief`). id:6fda lives only in
# TODO.md, so per CLAUDE.md "Testing" this file carries NO `# roadmap:` header and its
# failures always count.
#
# WHAT THIS PINS, and why each assertion exists rather than being a coverage ritual:
#
# (a) The docket resolves an item's lane with the ANCHORED probe, so a lane tag quoted in
#     an item's TRAILING prose is not read as that item's lane. Measured 2026-09-11, a
#     bare grep for `[MECHANICAL]` reported 9 items against a true count of 3. The
#     collector this skill delegates to (gather-human-backlog.sh) matches lane tags with
#     an UNANCHORED awk `match()` and does not know `[ROUTINE]` at all, so it OFFERS such
#     an item as a decision candidate -- this layer is what drops it.
#
# (b) BOTH dash spellings read. The em-dash migration window is open, so a delimiter-blind
#     reader silently drops every un-migrated ledger line.
#
# (c) The two DECORATION shapes the corpus actually uses still resolve: a lane inside the
#     title's bold run, and a lane behind a `[HIGH PRIORITY]` flag bracket. Measured on
#     dotclaude-skills the same day, requiring a bare leading bracket dropped 13 real
#     items -- an error in the opposite direction from (a) and just as wrong.
#
# (d) `@owner-answered` items are suppressed by default. That marker is how an answered
#     decision avoids being re-asked, and re-asking a settled question is the incident
#     that produced it (hard-lanes.md: "the tenth repetition of re-asking an already
#     decided question").
#
# (e) `blocks_n` counts a declared `gated-on:` dependant. THIS IS A REGRESSION PIN, not a
#     feature check: the first implementation split the edge CSV with
#     `printf '%s' "$gated" | tr ',' '\n'`, and with no trailing newline `read` drops the
#     FINAL token -- which for a single-token payload like `gated-on:aaaa` is the ONLY
#     token. Measured on this repo's own ledgers, 43 edge-bearing lines collapsed to 7
#     surviving keys and EVERY row reported "blocks nothing". The failure is silent and
#     reads as a legitimate flat ranking, which is exactly why it needs a test.
#
# (f) The COVERAGE footer is present, because "a clean pass is never 'no decisions
#     pending'" is a stated non-negotiable and it is carried by these lines.
#
# HERMETIC: a temp HOME, a temp $SRC_DIR, a temp $RELAY_TOML and a crafted fixture repo
# under `mktemp -d`. It never reads or writes ~/.claude, ~/.cache/relay, the real
# relay.toml, or the network. The only thing it touches outside the temp tree is this
# repo's own scripts, read-only, via DECISION_BRIEF_RELAY_SCRIPTS.
#
# fails-against-mutation: sed -i "s|printf '%s\\\\n' \"\$gated\"|printf '%s' \"\$gated\"|" decision-brief/docket.sh
# fails-against-assertion: (e) gated_on_edges_indexed is 0 while
#   NOTE: the mutation fires TWO assertions (blocks_n, then the edge-index size) from a
#   non-exiting accumulator, so this declaration names the LAST one, per the repo's rule.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/decision-brief/docket.sh"

fails=0
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }

[[ -x "$SCRIPT" ]] || { echo "FAIL: docket.sh not found or not executable at $SCRIPT"; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/home" "$tmp/cfg" "$tmp/src/demo/docs/ledger-notes"

# The fixture uses a LITERAL em dash on the bbbb line on purpose: it is the spelling the
# un-migrated corpus still carries, and (b) exists to prove the reader accepts it. Emission
# is a separate matter and is asserted below to be the spaced-hyphen form.
cat > "$tmp/src/demo/TODO.md" <<'EOF'
# TODO

## Current
- [ ] [INPUT - decision] **Plain hyphen decision item** -- detail: `docs/ledger-notes/aaaa.md` <!-- id:aaaa -->
- [ ] [INPUT — decision] **Em dash decision item** <!-- id:bbbb -->
- [ ] **[INPUT - meeting]** Bold wrapped meeting item <!-- id:cccc -->
- [ ] [ROUTINE] **Routine item whose tail merely discusses the [INPUT - decision] lane** <!-- id:dddd -->
- [ ] [HIGH PRIORITY] [INPUT - decision] **Flag prefixed decision** <!-- id:eeee -->
- [ ] [INPUT - decision] **Already answered item** @owner-answered:2026-09-01 <!-- answer-src:docs/ledger-notes/aaaa.md --> <!-- id:ffff -->
- [ ] [ROUTINE] **A dependant gated on aaaa** <!-- gated-on:aaaa --> <!-- id:1111 -->

## Done
EOF

printf '# Ledger note aaaa\n' > "$tmp/src/demo/docs/ledger-notes/aaaa.md"

cat > "$tmp/cfg/relay.toml" <<EOF
[repos.demo]
classification = "own"
path = "$tmp/src/demo"
EOF

run_docket() {
  HOME="$tmp/home" \
  SRC_DIR="$tmp/src" \
  RELAY_TOML="$tmp/cfg/relay.toml" \
  DECISION_BRIEF_RELAY_SCRIPTS="$ROOT/relay/scripts" \
    bash "$SCRIPT" scan "$@" 2>"$tmp/stderr.txt"
}

out="$tmp/out.tsv"
run_docket > "$out"
rc=$?

if [[ $rc -ne 0 ]]; then
  echo "FAIL: docket.sh scan exited $rc on the fixture"
  sed 's/^/  stderr: /' "$tmp/stderr.txt"
  exit 1
fi

# Helpers that read the TSV by FIELD, never by substring: a substring grep over this file
# would match an id inside another row's summary text.
row_field() {  # row_field <id> <field-number>
  awk -F'\t' -v want="$1" -v n="$2" '$1=="ROW" && $5==want { print $n; exit }' "$out"
}
is_docketed() { awk -F'\t' -v want="$1" '$1=="ROW" && $5==want { found=1 } END { exit !found }' "$out"; }
suppress_reason() {
  awk -F'\t' -v want="$1" '$1=="SUPPRESSED" && $3==want { print $4; exit }' "$out"
}
coverage() { awk -F'\t' -v k="$1" '$1=="COVERAGE" && $2==k { print $3; exit }' "$out"; }

# --- calibration must have run and passed before anything was counted ----------------
if [[ "$(head -1 "$out" | cut -f1)" != "CALIBRATION" ]]; then
  fail "the first output line is not CALIBRATION (got '$(head -1 "$out" | cut -f1)')"
elif [[ "$(head -1 "$out" | cut -f2)" != "ok" ]]; then
  fail "calibration did not pass on the fixture: $(head -1 "$out" | cut -f3)"
else
  pass "calibration ran first and passed"
fi

# --- (a) the anchored lane: a trailing-prose mention is NOT a lane -------------------
if is_docketed dddd; then
  fail "(a) dddd is [ROUTINE] with a trailing [INPUT - decision] mention but was docketed -- the anchored probe is not anchored"
elif [[ "$(suppress_reason dddd)" != "not-a-decision-lane" ]]; then
  fail "(a) dddd suppressed with reason '$(suppress_reason dddd)', expected 'not-a-decision-lane'"
else
  pass "(a) a trailing-prose lane mention is suppressed with a named reason, not docketed"
fi

# --- (b) both dash spellings read, and emission is the spaced hyphen -----------------
if ! is_docketed aaaa; then
  fail "(b) the spaced-hyphen [INPUT - decision] item aaaa was not docketed"
elif ! is_docketed bbbb; then
  fail "(b) the em-dash [INPUT - decision] item bbbb was not docketed -- the reader is delimiter-blind"
else
  pass "(b) both dash spellings of a lane tag are read"
fi

emitted_lane="$(row_field bbbb 6)"
if [[ "$emitted_lane" != '[INPUT - decision]' ]]; then
  fail "(b) the em-dash item's lane was EMITTED as '$emitted_lane', expected the spaced-hyphen '[INPUT - decision]'"
else
  pass "(b) an em-dash lane is emitted in the canonical spaced-hyphen form"
fi

# --- (c) the two decoration shapes still resolve --------------------------------------
if ! is_docketed cccc; then
  fail "(c) cccc carries its lane inside the title's bold run and was not docketed"
elif [[ "$(row_field cccc 6)" != '[INPUT - meeting]' ]]; then
  fail "(c) cccc resolved to lane '$(row_field cccc 6)', expected '[INPUT - meeting]'"
else
  pass "(c) a lane tag inside the title's bold run resolves"
fi

if ! is_docketed eeee; then
  fail "(c) eeee carries its lane behind a [HIGH PRIORITY] flag and was not docketed"
else
  pass "(c) a lane tag behind a non-lane bracket flag resolves"
fi

# --- (d) an already-answered decision is not re-asked ---------------------------------
if is_docketed ffff; then
  fail "(d) ffff carries @owner-answered but was docketed -- a settled question would be re-asked"
elif [[ "$(suppress_reason ffff)" != "owner-answered" ]]; then
  fail "(d) ffff suppressed with reason '$(suppress_reason ffff)', expected 'owner-answered'"
else
  pass "(d) an @owner-answered item is suppressed by default"
fi

inc="$tmp/out-inc.tsv"
run_docket --include-answered > "$inc"
if ! awk -F'\t' '$1=="ROW" && $5=="ffff" { found=1 } END { exit !found }' "$inc"; then
  fail "(d) --include-answered did not bring the @owner-answered item back"
else
  pass "(d) --include-answered brings it back when the owner asks to revisit"
fi

# --- (e) declared gated-on dependants are counted (dropped-final-token regression) ----
blocks_n="$(row_field aaaa 7)"
blocks_ids="$(row_field aaaa 8)"
if [[ "$blocks_n" != "1" ]]; then
  fail "(e) blocks_n for aaaa is '$blocks_n', expected '1'"
elif [[ "$blocks_ids" != "1111" ]]; then
  fail "(e) blocks_ids for aaaa is '$blocks_ids', expected '1111'"
else
  pass "(e) a single-token gated-on payload is counted (final token not dropped)"
fi

if [[ "$(coverage gated_on_edges_indexed)" == "0" ]]; then
  fail "(e) gated_on_edges_indexed is 0 while the fixture declares a gated-on edge"
else
  pass "(e) the edge index size is reported and non-zero"
fi

# --- (f) the honest coverage footer ---------------------------------------------------
missing=""
for key in repos_scanned candidates docketed suppressed_lane_mention \
           suppressed_owner_answered gated_on_edges_indexed ranking scope; do
  [[ -n "$(coverage "$key")" ]] || missing="$missing $key"
done
if [[ -n "$missing" ]]; then
  fail "(f) the COVERAGE footer is missing keys:$missing"
else
  pass "(f) the COVERAGE footer reports scope, counts and the ranking caveat"
fi

if [[ "$(coverage repos_scanned)" != "1" ]]; then
  fail "(f) repos_scanned is '$(coverage repos_scanned)', expected '1' from the fixture relay.toml"
else
  pass "(f) repo enumeration went through relay.toml, not a glob"
fi

# --- the script must not have written anything into the fixture repo ------------------
if [[ -n "$(find "$tmp/src/demo" -newer "$tmp/cfg/relay.toml" -type f 2>/dev/null)" ]]; then
  fail "scan modified a file in the fixture repo -- the collector must be read-only"
else
  pass "scan wrote nothing into the scanned repo"
fi

echo
if [[ $fails -eq 0 ]]; then
  echo "ALL PASS: decision-brief docket (id:6fda)"
  exit 0
fi
echo "$fails assertion(s) failed"
exit 1
