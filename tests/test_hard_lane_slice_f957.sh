#!/usr/bin/env bash
# roadmap:f957 — the HARD lane must be sliceable.
#
# THE DEFECT: `dispatchItemFor` -> `namedItemsFor` reads `actionable_routine_ids` EXCLUSIVELY.
# A `hard` unit fires precisely when a repo has NO actionable [ROUTINE] work, so that array is
# empty BY CONSTRUCTION -- no item is named, the verdict is not `review`, and the no-item branch
# of `sliceLedgerForUnit` fired every time. The unit was then sized on the WHOLE ledgers, which
# for loderite (ROADMAP 834,162 B + TODO 825,755 B) is an automatic prompt-size refusal. It
# handed back 3x in ONE run (2026-09-09, run relay-20260909-091623-10249) and archiving cannot
# help because that ledger's bulk is OPEN, not closed. `review` derives its own set via
# --since-last-review and `execute` names a routine id, so `hard` was the ONE verdict that could
# never produce a slice.
#
# WHY --ids AND NOT --id <first>: the hard lane's contract is that the CHILD surveys the open
# [HARD] items and picks one it can finish (the handoff-C5 sizing rule). Slicing on a single id
# would silently convert that into named-item dispatch and delete the choice the lane exists
# around. The CSV keeps the whole survey at a fraction of the size.
#
# Hermetic: mktemp -d fixture, bash + coreutils, no network, never touches ~/.claude.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JS="$ROOT/relay/scripts/relay-loop.js"
SLICE="$ROOT/relay/scripts/ledger-slice.sh"

pass=0; fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); }
bad() { echo "FAIL: $*"; fail=$((fail+1)); }

# ── (a) WIRING: the hard verdict must reach hardPoolIdsFor and emit --ids ──────────────────
# Structural, deliberately: the Workflow sandbox cannot import, so this repo pins wiring with a
# structural test (the same convention as the apex-gate/round-plan inline copies).
if grep -q "unit.verdict === 'hard') ? hardPoolIdsFor(unit)" "$JS"; then
  ok "(a) hard verdict derives slice ids from hardPoolIdsFor"
else
  bad "(a) hard verdict does NOT reach hardPoolIdsFor -- the lane is unsliceable again"
fi

if grep -q -- '--ids \${hardIds.join' "$JS"; then
  ok "(a) the hard set is passed as the --ids CSV"
else
  bad "(a) the hard set is not passed as --ids -- a single --id would delete the child's survey"
fi

# ── (b) FAIL-OPEN: an empty hard list must still take the no-slice branch ──────────────────
# `hardIds.length > 0` is what makes an empty classifier list fall through to the historical
# unsliced dispatch. A slice may only ever be ADDED, never made a dispatch precondition.
if grep -q 'const useHardSet = hardIds.length > 0' "$JS"; then
  ok "(b) empty hard-id list falls through to the unsliced brief (fail-open preserved)"
else
  bad "(b) fail-open guard missing -- an empty list could suppress a dispatch"
fi

# The no-item branch must still be reachable, i.e. it tests the hard set alongside the other
# sources. Matched as a PREFIX, deliberately: id:a060 added a FOURTH source (the handoff lane's
# un-promoted set), so pinning the closing paren pinned "exactly three sources" -- a shape this
# test never meant to assert, and one that turns any future lane gaining a slice into a red
# here. What must hold is that the bail still requires !useHardSet; extra `&& !useXSet` terms
# after it are additional lanes being sliced, never the hard lane losing its slice.
if grep -q 'if (!item && !useReviewSet && !useHardSet' "$JS"; then
  ok "(b) the no-slice branch accounts for the hard id source"
else
  bad "(b) the no-slice branch was not updated for the hard set"
fi

# ── (c) BEHAVIOUR: --ids over a many-item ledger must be materially smaller ────────────────
# The property the whole fix depends on. Uses the real slicer against a fixture whose ledger is
# padded so a whole-ledger read is large, with a handful of [HARD] items scattered through it.
command -v git >/dev/null 2>&1 || { echo "SKIP: git unavailable"; exit 0; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
R="$TMP/repo"; mkdir -p "$R"
git -C "$R" init -q .
{
  echo "# ROADMAP"
  for i in $(seq 1 400); do
    printf -- '- [x] closed filler item %s with a good deal of prose to make the ledger large <!-- id:%04x -->\n' "$i" "$((0x1000 + i))"
  done
  echo "- [ ] [HARD] first hard item <!-- id:aa01 -->"
  echo "- [ ] [HARD] second hard item <!-- id:aa02 -->"
  echo "- [ ] [HARD] third hard item <!-- id:aa03 -->"
} > "$R/ROADMAP.md"
printf '# TODO\n' > "$R/TODO.md"

whole=$(wc -c < "$R/ROADMAP.md")
# --out is MANDATORY here: without it ledger-slice.sh mints a path under the REAL
# ~/.cache/relay/slices/, which is a write outside the fixture and a hermeticity breach.
out="$("$SLICE" --repo fixture --path "$R" --ids aa01,aa02,aa03 --out "$TMP/slice.md" 2>/dev/null)" || out=""
p="$(printf '%s\n' "$out" | tail -1)"
if [ -n "$p" ] && [ -f "${p/#\~/$HOME}" ]; then
  sliced=$(wc -c < "${p/#\~/$HOME}")
  if [ "$sliced" -lt "$((whole / 4))" ]; then
    ok "(c) --ids slice is materially smaller than the whole ledger ($sliced B vs $whole B)"
  else
    bad "(c) --ids slice is not materially smaller ($sliced B vs $whole B) -- the fix buys nothing"
  fi
  # All three items must be present: the survey must survive slicing.
  miss=0
  for id in aa01 aa02 aa03; do grep -q "$id" "${p/#\~/$HOME}" || miss=$((miss+1)); done
  if [ "$miss" -eq 0 ]; then
    ok "(c) all three hard items survive the slice -- the child's survey is intact"
  else
    bad "(c) $miss of 3 hard items missing from the slice -- the survey was truncated"
  fi
else
  bad "(c) ledger-slice.sh --ids produced no usable slice path for the fixture"
fi

echo "---- $pass ok, $fail failed ----"
[ "$fail" -eq 0 ] || exit 1
