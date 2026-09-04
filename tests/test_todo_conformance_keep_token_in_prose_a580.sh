#!/usr/bin/env bash
# NO `# roadmap:` header, deliberately: this is a DEFECT-FIX test, not a roadmap RED spec.
# (Its failures always count, and a roadmap header would also CANCEL the machine-readable
# negative case below -- verify-negative-cases.py reports such a file as a ROADMAP-SHADOWED
# DECLARATION and never executes it.)
#
# THE DEFECT (TODO id:a580, found by the independent review of the 2026-09-03 note-minting
# pass). `id:60eb` correctly stopped a MANDATORY `-- detail:` pointer from pushing an item
# over the title budget, by routing both the shape rule and the grammar rule through one
# `strip_chrome`. But that stripper applied `LENGTH_MUST_KEEP_RE` GLOBALLY (`//g`) to the
# title. The step 5 it replaced stripped only LEADING bracket groups, so a keep-token quoted
# in mid-PROSE still counted as title text. Under a global strip it stops counting -- and
# `BLOCKED on` alone buys an over-long title 10 free characters.
#
# This is the direction that HIDES violations, which is why it is pinned even though the
# class is WARN-only and there were ZERO live false negatives on either ledger at the time.
#
# WHY A FIXTURE HERE IS EASY TO GET WRONG, recorded because it was got wrong twice before
# this file existed: the false-negative band is NARROW. The stolen token has to be exactly
# what carries the title across 200, so for a 10-char token the band is roughly 201-210. A
# fixture at 222 chars is over budget BOTH ways and is reported either way -- vacuous, and
# indistinguishable from a real pass. So this file ASSERTS ITS OWN SIZING first (cases (0a)
# and (0b)), the way tests/test_shape_regrowth_below_baseline_cf64.sh asserts its trap is
# armed before relying on it. If a fixture ever drifts out of the band the file says so
# LOUDLY instead of passing for the wrong reason.
#
# THE FIX being pinned: the keep-token strip is ANCHORED -- global at/after the detail
# pointer (where the id:0d7c shrinker parks relocated lane/gate tokens, which is what id:60eb
# case (g) requires), plus a LEADING and a TRAILING run. Everything between those runs is
# prose and is counted. `id:60eb` is NOT reverted: cases (2) and (3) below re-pin the two
# properties that fix bought.
#
# fails-against: the id:60eb global `//g` keep-token strip, which is what shipped before this
#   item -- a keep-token sitting in mid-title PROSE was subtracted from the measurement, so a
#   genuinely over-budget title in the ~201-210 band reported nothing at all.
# fails-against-mutation: sed -i 's|^_chrome_edge_strip() {$|_chrome_edge_strip() { sed -E "s/${LENGTH_MUST_KEEP_RE}//g" <<<"$1"; return 0;|' relay/scripts/todo-conformance.sh
# fails-against-assertion: (1a) prose quoting the BLOCKED-on lexeme mid-title is NOT counted
# NOTE on that spelling: the declared substring is matched against this file's SOURCE line as
# well as against the FAIL line the run emits, so the message deliberately carries no shell
# escape (a `\`` in the source is a bare backtick in the output, and the two would not match).
#
# Hermetic: fixture ledger in a mktemp -d, all three ratchet baselines pointed at absent
# files, no ~/.claude, no live ledger, no network.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF="${TODO_CONFORMANCE_OVERRIDE:-$ROOT/relay/scripts/todo-conformance.sh}"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$CONF" ]] || fail "sanity: todo-conformance.sh must exist and be executable at $CONF"

TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

# HERMETICITY (id:e350): the fixture uses the real ledger basename, so without these the
# committed baselines would decide this test's verdict.
export SHAPE_BASELINE="$TMP/absent-shape-baseline.txt"
export LENGTH_BASELINE="$TMP/absent-length-baseline.txt"
export STATE_CLAIM_BASELINE="$TMP/absent-state-claim-baseline.txt"

MAX=200          # LEDGER_ITEM_TITLE_MAX's shipped default

# The keep-token vocabulary is READ OUT OF THE SCRIPT, never transcribed: a hand-copied
# second spelling is the id:4983 drift this whole cluster is about, and it would also let
# the arming assertions below go quietly stale.
eval "$(grep -m1 '^LENGTH_MUST_KEEP_RE=' "$CONF")"
[[ -n "${LENGTH_MUST_KEEP_RE:-}" ]] \
  || fail "sanity: could not read LENGTH_MUST_KEEP_RE out of $CONF"

# global_strip <text> -- what the PRE-a580 stripper did. Computed here, from the script's own
# regex, so the arming assertions measure the OLD behaviour independently of the code under
# test (the mutation must not be able to make its own trap look armed).
global_strip() { sed -E "s/${LENGTH_MUST_KEEP_RE}//g" <<<"$1"; }
trim() { sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' <<<"$1"; }

FILLER='the quick brown fox jumps over the lazy dog and keeps running past the fence '

# prose <total> <token> -- <total> characters of filler prose with <token> planted in the
# MIDDLE (never at either edge, which is where a token is legitimately chrome).
prose() {
  local total="$1" tok="$2" f="" lt
  while (( ${#f} < total + 80 )); do f+="$FILLER"; done
  lt=$(( (total - ${#tok} - 2) / 2 ))
  printf '%s %s %s' "${f:0:lt}" "$tok" "${f:lt:total - ${#tok} - 2 - lt}"
}

# The four token families the review measured, each sized INTO the band. The margin a fixture
# can have is bounded by the token's own length: it needs `MAX < len` and `len - stolen <=
# MAX`, so a 6-char token affords 3 chars of slack on each side and no more.
P_BLOCKED="$(prose 205 'BLOCKED on')"
P_LANE="$(prose 203 '[HARD]')"
P_GLYPH="$(prose 203 '🚧 🚧 🚧 🚧 🚧 🚧')"
P_GATED="$(prose 206 'gated-on:abcd')"

# --- (0) THE TRAP IS ARMED ------------------------------------------------------------
# Straddle, both halves. Without (0a) the fixture might be under budget even unstripped and
# prove nothing; without (0b) it might be over budget even AFTER the old global strip, in
# which case the old code reported it too and the file is vacuous.
arm() { # <label> <prose>
  local label="$1" p="$2" raw stripped
  raw=${#p}
  stripped="$(trim "$(global_strip "$p")")"
  (( raw > MAX )) \
    || fail "(0a) fixture $label is $raw chars, not over the $MAX budget -- it would not be reported by ANY version and pins nothing"
  (( ${#stripped} <= MAX )) \
    || fail "(0b) fixture $label measures ${#stripped} chars even after the OLD global strip, still over $MAX -- the old code reported it too, so this fixture is VACUOUS (it must land in the false-negative band)"
  echo "      $label: $raw chars raw, ${#stripped} after the old global strip (budget $MAX)"
}
arm BLOCKED "$P_BLOCKED"
arm LANE    "$P_LANE"
arm GLYPH   "$P_GLYPH"
arm GATED   "$P_GATED"
pass "(0) all four fixtures sit INSIDE the false-negative band: over budget as written, under it after the old global strip"

# --- fixture ledger -------------------------------------------------------------------
# `bb05` is the live shape the fix must NOT break: a SHORT title, then the mandatory pointer,
# then the run of lane/gate tokens the id:0d7c shrinker parks after it. Both live `BLOCKED on`
# titles in this repo's TODO.md are exactly that shape and are LEGITIMATE strips.
# `bb06` is id:60eb's own property, re-pinned here: a required pointer alone never pushes a
# short title over budget.
SHORT='A title that sits comfortably inside the two-hundred character budget on its own merits and gains nothing at all except the one mandatory detail pointer token the format obliges it to carry'
PARKED='`@manual` 🚧 BLOCKED on [ROUTINE] [HARD]'

T="$TMP/TODO.md"
{
  echo '# TODO'
  echo
  echo '## Current'
  echo
  echo "- [ ] $P_BLOCKED <!-- id:bb01 -->"
  echo "- [ ] $P_LANE <!-- id:bb02 -->"
  echo "- [ ] $P_GLYPH <!-- id:bb03 -->"
  echo "- [ ] $P_GATED <!-- id:bb04 -->"
  echo "- [ ] $SHORT -- detail: \`docs/ledger-notes/bb05.md\` $PARKED <!-- id:bb05 -->"
  echo "- [ ] $SHORT -- detail: \`docs/ledger-notes/bb06.md\` <!-- id:bb06 -->"
} >"$T"

out="$(bash "$CONF" "$T" 2>/dev/null || true)"
flagged() { grep -q "^grammar-item-title-long.*<!-- id:$1 -->" <<<"$out"; }

# --- (1) NO UNDER-REPORTING: prose counts even when it quotes a keep-token --------------
flagged bb01 || fail "(1a) prose quoting the BLOCKED-on lexeme mid-title is NOT counted -- a global keep-token strip is subtracting real title text, which HIDES an over-budget line"
flagged bb02 || fail "(1b) prose quoting a lane tag mid-title is NOT counted -- the same global-strip hole"
flagged bb03 || fail "(1c) prose quoting the gate glyph mid-title is NOT counted -- the same global-strip hole"
flagged bb04 || fail "(1d) prose quoting a bare gate edge mid-title is NOT counted -- the same global-strip hole"
pass "(1) a keep-token inside genuinely-long title PROSE is still counted, all four token families"

# --- (2) id:60eb IS NOT REVERTED: chrome after the title still does not count -----------
flagged bb05 && fail "(2a) the run of lane/gate tokens the shrinker parks AFTER the detail pointer was counted as title text -- id:60eb case (g) is reverted"
pass "(2a) tokens parked at/after the detail pointer are still chrome, not title"
flagged bb06 && fail "(2b) a required detail pointer pushed a short title over budget -- id:60eb's own fix is reverted"
pass "(2b) a required detail pointer still does not push a short title over budget"

# --- (3) THE STRIP IS ANCHORED, asserted structurally ----------------------------------
# A behavioural test alone cannot see a stripper that happens to agree on today's fixtures,
# and this is the one property the whole item is about.
grep -q '^_chrome_edge_strip()' "$CONF" \
  || fail "(3) strip_chrome carries no anchored edge helper -- the keep-token strip is global again"
pass "(3) the keep-token strip is anchored (leading run, trailing run, at/after the pointer)"

echo "ALL PASS: $(basename "$0")"
