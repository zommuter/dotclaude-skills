#!/usr/bin/env bash
# roadmap:8679
#
# RED SPEC (authored by relay handoff C3, not implemented here).
#
# WHY THIS ITEM GETS A TEST AT ALL, since it is a MEASUREMENT item and the obvious
# reading is that a measurement cannot be a test. It is testable because the item's own
# `Tests:` line does not ask for the number -- it asks for "a committed counting script
# both the promote pass and any future ruling call, so the population cannot drift again
# unobserved". A script has behaviour, and behaviour is specifiable. The half that is NOT
# testable is the reconciliation itself: no assertion can establish WHY the three figures
# on record (11 ruled and owner-marked UNVERIFIED, 21 measured 2026-09-01, 10 measured
# 2026-09-02 post-shrink) differ. That is prose, it belongs in the item's note and in
# `docs/meeting-notes/2026-09-01-2226-ledger-line-shrink-format.md`, and this file does
# not fake it. See the handoff report.
#
# So what is pinned here is the COUNTING RULE and its DRIFT-OBSERVABILITY, on hermetic
# fixtures -- never on the live ledger, whose content is exactly what the item says has
# already drifted three times. Every case is a shape that could plausibly account for a
# gap of ten between two honest counts, which is what makes the fixture a reconciliation
# instrument rather than a tautology.
#
# LOAD-BEARING CONTEXT: loderite MEASURED four ids (89f9, a5b6, ba07, ed26) silently
# orphaned by exactly this shape -- body relocated, address lost, counts unchanged,
# round-trip green. A count is not enough; the tool must ENUMERATE, so a population that
# changes is visible as WHICH ids changed, not as a number that happens to match.
#
# TWO SPEC CHOICES MADE HERE THAT THE ITEM DOES NOT SETTLE, flagged rather than hidden:
#   * case (D): a typed edge (`routed:` / `gated-on:`) is NOT the line's OWN anchor, so an
#     indented line carrying only one is NOT in the population. "Carrying their own
#     `<!-- id:XXXX -->`" is read strictly.
#   * case (F): an indented line inside a fenced code block is a SAMPLE, not a ledger
#     line, so it is NOT in the population.
# Both are plausible sources of a 21-vs-11 gap. If the owner rules otherwise, the fix is
# to change the fixture's expectation and say so -- not to widen the assertion.
#
# Hermetic: mktemp ledgers in a throwaway git repo, no ~/.claude, no live ledger.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/lib/hermetic-git-env.sh"

# The counting script. Path is injectable so renaming it costs one line here, not a
# rewrite; the DEFAULT is the spec's proposal.
COUNTER="${INDENTED_ID_COUNTER:-$ROOT/tools/count-indented-ids.sh}"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf -- "$TMP"' EXIT

FIX="$TMP/repo"
mkdir -p "$FIX"
git -C "$FIX" init -q -b main
git -C "$FIX" config user.email t@e.st
git -C "$FIX" config user.name t

# Cases A..G. Exactly THREE lines belong to the population: a1a1, a2a2, a3a3.
cat > "$FIX/TODO.md" <<'MD'
# TODO

## Current

- [ ] [ROUTINE] a top-level open item -- case B, NOT in the population <!-- id:b0b0 -->
  - [ ] an indented open item with its own anchor -- case A, IN <!-- id:a1a1 -->
  - [ ] an indented item with no anchor at all -- case C, NOT in
  - [ ] an indented item whose only marker is a typed edge -- case D, NOT in <!-- gated-on:b0b0 -->
  - [ ] a second indented item whose only marker is a routed edge -- case D, NOT in <!-- routed:b0b0 -->
  - [x] an indented CLOSED item with its own anchor -- case E, IN <!-- id:a2a2 -->
    - [ ] a DOUBLY indented item with its own anchor -- case A again, IN <!-- id:a3a3 -->

## Notes

An example of the shape, which is a code sample and not a ledger line:

```markdown
  - [ ] an indented item inside a fence -- case F, NOT in <!-- id:f0f0 -->
```

- [x] a top-level closed item -- case G, NOT in the population <!-- id:c0c0 -->
MD

git -C "$FIX" add -A
git -C "$FIX" commit -qm "fixture ledger"
SHA="$(git -C "$FIX" rev-parse HEAD)"

[[ -x "$COUNTER" ]] \
  || fail "(0) no committed counting script at $COUNTER -- the item's own Tests line asks for one precisely so the population cannot drift unobserved again; 11 / 21 / 10 are three honest counts of three different populations and nothing today can say which rule produced which"

out="$("$COUNTER" "$FIX/TODO.md" 2>"$TMP/err")"; rc=$?
[[ $rc -eq 0 ]] || fail "(0) the counter exited $rc on a well-formed ledger: $(cat "$TMP/err")"

# ── (1) THE POPULATION IS ENUMERATED, not just counted. A bare number cannot show WHICH
#    ids left, which is the exact failure mode the four silently-orphaned ids demonstrate.
ids="$(grep -oE '\b[0-9a-f]{4}\b' <<<"$out" | sort -u | tr '\n' ' ')"
want="a1a1 a2a2 a3a3 "
[[ "$ids" == "$want" ]] \
  && pass "(1) the population is ENUMERATED and is exactly {a1a1 a2a2 a3a3}" \
  || fail "(1) enumerated population is '$ids', want '$want' -- differences: B/G (top-level) must be OUT, C (no anchor) OUT, D (typed edge only) OUT, F (inside a fence) OUT, A/E (indented, own anchor, open or closed) IN. Full output:"$'\n'"$out"

# ── (2) THE COUNT AGREES WITH THE ENUMERATION, and is stated as a count rather than left
#    to be inferred by counting listed lines. A tool whose headline number and listing can
#    disagree reproduces the original defect in miniature. The label vocabulary is kept
#    deliberately loose (count / total / population); what is pinned is that the number is
#    LABELLED, so it cannot be confused with a hex id that happens to contain the digit.
grep -qiE '(count|total|population)[^0-9]{0,16}3([^0-9]|$)' <<<"$out" \
  && pass "(2) the output states a labelled count of 3, agreeing with the enumeration" \
  || fail "(2) the output states no labelled count of 3 though 3 ids are in the population -- headline number and listing must agree, and 11 / 21 / 10 are three unlabelled numbers nobody can now reconcile:"$'\n'"$out"

# ── (3) THE COUNTING RULE IS STATED. "The reconciliation must state the counting rule and
#    the AS-OF commit, not just a number" -- a number with no rule is precisely what
#    produced 11 vs 21 vs 10.
grep -qiE 'rule|counts?:|criteri' <<<"$out" \
  && pass "(3) the output STATES its counting rule" \
  || fail "(3) the output states no counting rule -- three figures are on record and none of them says what it counted:"$'\n'"$out"

# ── (4) THE AS-OF COMMIT IS NAMED. The shrink itself moved the population, so a count
#    without a commit is not reproducible even in principle.
grep -qF "${SHA:0:7}" <<<"$out" \
  && pass "(4) the output names the AS-OF commit ${SHA:0:7}" \
  || fail "(4) the output does not name the as-of commit (${SHA:0:7}); the shrink moved this population, so a bare number is not reproducible:"$'\n'"$out"

# ── (5) DRIFT IS OBSERVABLE. Adding one qualifying line moves the population by exactly
#    that id -- the property the whole item exists to establish.
cp "$FIX/TODO.md" "$TMP/before.md"
printf '  - [ ] a newly added indented item with its own anchor <!-- id:a4a4 -->\n' >> "$FIX/TODO.md"
git -C "$FIX" add -A
git -C "$FIX" commit -qm "drift by one"
out2="$("$COUNTER" "$FIX/TODO.md" 2>/dev/null)"
ids2="$(grep -oE '\b[0-9a-f]{4}\b' <<<"$out2" | sort -u | tr '\n' ' ')"
[[ "$ids2" == "a1a1 a2a2 a3a3 a4a4 " ]] \
  && pass "(5) adding one qualifying line adds exactly that id to the population" \
  || fail "(5) after adding a4a4 the population is '$ids2', want 'a1a1 a2a2 a3a3 a4a4 ' -- drift must be attributable to an id, not visible only as a count"

# ── (6) DETERMINISTIC. Two runs over identical input give identical output modulo the
#    as-of commit; a counter that is not reproducible cannot settle a disagreement.
out3="$("$COUNTER" "$FIX/TODO.md" 2>/dev/null)"
[[ "$out3" == "$out2" ]] \
  && pass "(6) repeated runs over identical input are byte-identical" \
  || fail "(6) two runs over identical input differ -- a non-reproducible counter cannot reconcile anything"

echo "ALL PASS"
