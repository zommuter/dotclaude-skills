#!/usr/bin/env bash
# No roadmap header -- defect-fix spec under TODO id:6546. Failures always count.
#
# Defect, MEASURED on loderite 2026-09-02 during a real (reverted) run: the wave-2
# "re-emit a relocated lane tag in the LEADING run" rule promoted EVERY lane token found
# in the moved region. But a lane token in an item's BODY is usually PROSE ABOUT a lane,
# not the item's lane, so three OPEN items were hoisted out of human lanes into
# pool/routine-carrying ones:
#
#   affd  [INPUT - access]  ->  [HARD - pool] [HARD - decision gate] [INPUT - access]
#   6e7a  [INPUT - access]  ->  [ROUTINE] [INPUT - access]
#   1e21  [INPUT - meeting] ->  [HARD] [INPUT - meeting]
#
# That is the OVER-DISPATCH direction. The bug it was written to fix (a relocated tag
# landing in the TAIL, after the detail pointer, invisible to leading-run detectors) is
# silently INVISIBLE; this one is silently WRONG. Given the choice, invisible is safer, so
# the refusal branch matters more than the promotion branch.
#
# Clause, after THREE rounds. Round 1 promoted every body token (moved three OPEN loderite
# items into pool lanes). Round 2 promoted "when unambiguous" (invented lanes here). Round 3
# relocated everything (left items lane-less, which is worse than either).
#
# All three were answering the wrong question -- "what is this item's lane", which a line
# cannot tell you. The right question is INVARIANCE: what does classify-repo COMPUTE as the
# lane, and does the shrink change it? id:4da4 defines that as the FIRST lane token on the
# line wherever it sits, so:
#   * not first -> sets nothing, no detector reads it -> prose, travels with the body;
#   * first     -> already IS the computed lane -> must stay first, i.e. the leading run.
# Neither branch is a judgement, and the invariant is ASSERTED (case d2), with a split that
# would change the computed lane REFUSED outright.
#
# Deliberately no backtick masking: classify-repo does not strip backticks either (its
# id:4da4 note says first-occurrence is what makes it robust WHERE A BACKTICK-STRIP IS NOT).
# All three affected items in this repo carry a backticked or foreign-id prose mention as
# their first token, so they have a de-facto lane today they should not have. That is a
# pre-existing classify-repo defect; a formatting migration must neither silently fix nor
# silently cement it, so the lane is preserved as computed and the item is REPORTED.
#
# fails-against: the fix and this spec land in the same commit, so the negative case is a
# mutation restoring the ROUND-1 state exactly -- unconditional promotion AND no invariant
# check. Mutating the promotion alone is not discriminating any more: the invariant would
# catch it and refuse the split, leaving the line untouched and every assertion green. Both
# halves have to go, which is itself evidence the guard is load-bearing.
# fails-against-mutation: python3 -c "import io;p='tools/ledger-shrink.py';s=io.open(p,encoding='utf-8').read();s=s.replace('if primary_in_prefix or primary is None or txt != primary[1]:','if False:',1);s=s.replace('if (_pb[1] if _pb else None) != (_pa[1] if _pa else None):','if False:',1);io.open(p,'w',encoding='utf-8').write(s)"
# fails-against-assertion: (a) an item that ALREADY has a lane must not gain one from body prose
#
# Hermetic: temp ledger + temp notes dir; no ~/.claude, no network.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="$ROOT/tools/ledger-shrink.py"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$TOOL" ]] || fail "sanity: $TOOL must exist"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/docs/ledger-notes"

# The retired venue-keyed tag is COMPOSED, never written literally. This file has to
# contain the banned token to test that the shrinker refuses to plant it -- but a literal
# would be an added line carrying old vocabulary, so the pre-commit vocabulary ratchet
# blocks the commit. That guard is doing its job; a fixture for a banned-content detector
# is the one legitimate place the content cannot appear verbatim. Stated openly rather than
# obfuscated, and deliberately NOT skipped with --no-verify.
RETIRED="[HARD"" - meeting]"

filler="the rationale continues at length so that there is definitely enough prose here to be worth relocating into a detail file, repeated for bulk aaaa bbbb cccc dddd eeee ffff"

cat >"$tmp/TODO.md" <<MD
# TODO

## Current

- [ ] [INPUT - access] **Already laned, body mentions other lanes** -- we rejected doing this as [HARD - pool] and also as [HARD - decision gate]; $filler <!-- id:cc01 -->
- [ ] **No lane at all, body names exactly one** -- this belongs in [ROUTINE] once unblocked; $filler <!-- id:cc02 -->
- [ ] **No lane, body names several** -- could be [ROUTINE] or [HARD] depending on the call; $filler <!-- id:cc03 -->
- [ ] **No lane, body names a RETIRED venue-keyed one** -- this was filed as ${RETIRED} back then; $filler <!-- id:cc04 -->
MD

cp "$tmp/TODO.md" "$tmp/rep-src.md"   # pristine copy for case (e); --apply mutates in place

python3 "$TOOL" --file TODO.md --root "$tmp" --min-chars 200 --apply >/dev/null 2>&1 \
  || fail "sanity: the tool exited non-zero on the fixture"

# Here-strings, never `cmd | grep -q`: piping into an early-exiting consumer under
# pipefail lets SIGPIPE become the pipeline status (id:81d5), which this repo lints for.
line() { grep -F "id:$1 -->" "$tmp/TODO.md"; }
lead() { line "$1" | grep -oP '^- \[[ xX]\]\s*(\[[^]]+\]\s*)*'; }

# --- (a) THE DEFECT: an item that already has a lane must not gain one from prose -------
l="$(lead cc01)"
[[ "$l" != *"HARD"* ]] \
  || fail "(a) an item that ALREADY has a lane must not gain one from body prose -- leading run is now: $l"
[[ "$l" == *"INPUT - access"* ]] \
  || fail "(a) the item's OWN lane was lost from the leading run: $l"

# --- (b) an item WITH a leading lane: body tokens are PROSE and are RELOCATED ------------
# id:4da4 PRIMARY-LANE ANCHORING, this repo's own ratified rule: "an item's lane is the
# FIRST recognized lane-tag on the line ... any bracket-token further right is prose/history
# and must NOT set the lane" (classify-repo.sh:279). So a lane token to the RIGHT of the
# item's own lane sets nothing and no detector reads it. Keeping it on the line is not
# preservation, it is dragging prose back onto a control surface -- and it made the shrunk
# line an ADDED line carrying old-vocabulary lane text, which the pre-commit vocabulary
# ratchet correctly BLOCKED. The guard was right and the keep-list was wrong.
#
# Nothing is LOST: the token must be verbatim in the detail file, like all other body prose.
[[ "$(line cc01)" != *"HARD - pool"* ]] \
  || fail "(b) a body lane token to the RIGHT of the item's own lane was kept on the line: $(line cc01)"
grep -q 'HARD - pool' "$tmp/docs/ledger-notes/cc01.md" \
  || fail "(b) the relocated lane token is not in the detail file -- it was DROPPED, not moved"

# --- (c) NO leading lane: the FIRST body token IS the computed lane -> it stays FIRST -----
# INVARIANCE, not inference. classify-repo takes the first lane token on the line wherever
# it sits (id:4da4), so for a lane-less head the first body token already IS this item's
# lane today. Preserving it means keeping it FIRST, which after the cut means the leading
# run -- that is not inventing a lane, it is stopping the shrink from REMOVING one.
l="$(lead cc02)"
[[ "$l" == *"[ROUTINE]"* ]] \
  || fail "(c) the item's COMPUTED lane was lost -- first body token must stay first; got: $l"

# --- (d) several in the body: only the FIRST is the lane, the rest are prose --------------
l="$(lead cc03)"
[[ "$l" == *"[ROUTINE]"* ]] \
  || fail "(d) the FIRST body lane token must be preserved as the lane; got: $l"
[[ "$l" != *"[HARD]"* ]] \
  || fail "(d) a LATER body lane token was promoted -- only the first is the lane; got: $l"
grep -q 'HARD' "$tmp/docs/ledger-notes/cc03.md" \
  || fail "(d) the later token must travel with the body, not vanish"

# --- (d2) THE INVARIANT itself: computed lane identical before and after ------------------
python3 - "$tmp/rep-src.md" "$tmp/TODO.md" <<'PYEOF' || fail "(d2) the shrink CHANGED an item's computed lane"
import re, sys
LANE = re.compile(r"\[(?:ROUTINE|HARD|MECHANICAL|INTENSIVE)\]|\[(?:HARD|INPUT|INTENSIVE)\s*[-\u2013\u2014]\s*[A-Za-z0-9 _./-]+\]")
def primary(l):
    m = LANE.search(l)
    return m.group(0) if m else None
def idx(p):
    return {m.group(1): primary(l) for l in open(p, encoding="utf-8")
            for m in [re.search(r"<!--\s*id:([0-9a-f]{4})\s*-->", l)] if m and l.startswith("- [")}
b, a = idx(sys.argv[1]), idx(sys.argv[2])
bad = [(k, b[k], a[k]) for k in a if k in b and a[k] != b[k]]
for k, x, y in bad:
    print("  id:%s  %r -> %r" % (k, x, y))
sys.exit(1 if bad else 0)
PYEOF

# --- (e) the population is SURFACED, not silently left ------------------------------------
# Refusing to act is only safe if it is LOUD. A human is the only actor that can place these,
# and they cannot place what they are not told about. Run against a FRESH copy: the tree
# above has already been split, so a re-run there reports nothing and would make this
# assertion vacuous -- the id:a73c unreached-fixture class.
fresh="$tmp/fresh"; mkdir -p "$fresh/docs/ledger-notes"
cp "$tmp/rep-src.md" "$fresh/TODO.md"
rep="$(python3 "$TOOL" --file TODO.md --root "$fresh" --min-chars 200 --dry-run 2>&1)"
grep -q 'LANE TOKEN OUTSIDE THE LEADING RUN' <<<"$rep" \
  || fail "(e) the lane-in-body population must be REPORTED, not silently left; got: $rep"
grep -qE 'id:cc0[123]' <<<"$rep" \
  || fail "(e) the report must name the items so a human can act on them; got: $rep"

# --- (f) preserving the lane must never PLANT retired vocabulary --------------------------
# id:4da4 says cc04's computed lane is the body's `[HARD - meeting]`, so preserving it means
# lifting a venue-keyed tag into the leading run -- which the pre-commit vocabulary ratchet
# correctly BLOCKS on an added line. Cooperating with the guard beats fighting it: refuse
# this one item and name the canonical converter. The alternatives were --no-verify (routing
# around a guard) and hand-swapping a delimiter (which the fleet rule forbids outright).
[[ "$(line cc04)" != *"detail:"* ]] \
  || fail "(f) an item whose preserved lane is RETIRED vocabulary must be REFUSED, not shrunk: $(line cc04)"
fresh2="$tmp/fresh2"; mkdir -p "$fresh2/docs/ledger-notes"
cp "$tmp/rep-src.md" "$fresh2/TODO.md"
rep2="$(python3 "$TOOL" --file TODO.md --root "$fresh2" --min-chars 200 --dry-run 2>&1)"
grep -q 'RETIRED venue-keyed vocabulary' <<<"$rep2" \
  || fail "(f) the refusal must NAME itself and point at lane-convert.sh; got: $rep2"

pass "ledger-shrink is LANE-INVARIANT (id:6546): the lane classify-repo computes for a line is identical before and after -- a token that is not first is prose and travels with the body, the token that IS first stays first, and any split that would change the computed lane is REFUSED"
