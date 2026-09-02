#!/usr/bin/env bash
# roadmap:4983 -- ONE lane grammar, read by every consumer instead of hand-mirrored.
#
# WHY (2026-09-02): the lane vocabulary is enumerated by hand in at least three places --
# `relay/scripts/classify-repo.sh` (the LANE_TAGS tuple + the id:4da4 primary-lane
# anchoring rule), `relay/references/hard-lanes.md` (the DECLARED single source of truth,
# which says in its own second paragraph that its consumers "MUST agree on its marker
# set"), and `tools/ledger-shrink.py` (a PRIVATE regex reimplementation, `_LANE_PATTERNS`).
# In one session the shrinker's lane handling was rebuilt three times off that private
# copy: round 1 promoted every body lane token and moved three OPEN items out of human
# lanes into pool-carrying ones; round 2 promoted "when unambiguous" and INVENTED lanes;
# round 3 relocated everything and left items lane-less. The rule that finally worked is
# pure INVARIANCE against classify-repo's anchoring -- so the shrinker's correctness is
# DEFINED by agreement with a grammar it does not read. An enumeration is exactly the
# thing that goes stale; the fix is ONE source serving both the actor and the checker.
#
# This test is the SPEC for that: a PARITY test. It derives the lane-token set from the
# declared SSOT and asserts each consumer recognises EXACTLY that set -- no declared token
# a consumer misses, and no token a consumer recognises that the SSOT never declared.
#
# Asserts (the python body exits at the FIRST failure, so exactly one FAIL line fires):
#   (a) the SSOT doc yields a non-empty lane set (the extraction itself is not vacuous);
#   (b) classify-repo.sh's LANE_TAGS recognises every SSOT-declared lane, both dash
#       spellings (the fleet is mid-migration from the em dash to the ASCII hyphen and
#       BOTH are live -- neither may be normalised away in passing);
#   (c) classify-repo.sh's LANE_TAGS recognises nothing the SSOT does not declare;
#   (d) ledger-shrink.py's _LANE_PATTERNS recognises every SSOT-declared lane, both dash
#       spellings;
#   (e) ledger-shrink.py's _LANE_PATTERNS recognises nothing the SSOT does not declare;
#   (f) the two consumers agree on the PRIMARY lane of a line (the id:4da4 anchoring rule
#       `_first_lane` claims in its own docstring to mirror) -- the consequence of (e),
#       asserted directly so a fix cannot satisfy the set check and still diverge here.
#
# `[INTENSIVE - <resource>]` is deliberately NOT in the expected set: the SSOT states it
# is an ORTHOGONAL resource modifier and that one must "never use [INTENSIVE - ...] in
# place of a lane tag". A consumer that treats it as a lane can anchor on it.
#
# Hermetic: reads three tracked files, writes nothing, no ~/.claude, no network.
#
# This file contains NO em dash or en dash character. Where one is needed to build a
# fixture it is constructed from a `\uXXXX` escape -- the same convention
# `tools/ledger-shrink.py`'s `_DASH` comment documents.
#
# fails-against: the divergence this pins is present at HEAD, so the file is RED today and
#   is an EXPECTED-RED roadmap spec, not a defect-fix regression test. Its negative case is
#   therefore stated as prose rather than as a machine-runnable `-rev`/`-mutation` case:
#   `verify-negative-cases.py` verifies GREEN-NOW then RED-THERE, and a roadmap spec is
#   red NOW by construction. The negative case a future runner should use once the fix
#   lands: revert `tools/ledger-shrink.py` to the revision named in the item, whose
#   `_LANE_PATTERNS` alternation admits `INTENSIVE` and any `[HARD|INPUT <dash> WORD]`
#   the SSOT never declared; assertion (e) below must be the line that fires.

set -euo pipefail

SRC_DIR_REPO="$(cd "$(dirname "$0")/.." && pwd)"
export SSOT_DOC="$SRC_DIR_REPO/relay/references/hard-lanes.md"
export CLASSIFY_SH="$SRC_DIR_REPO/relay/scripts/classify-repo.sh"
export SHRINK_PY="$SRC_DIR_REPO/tools/ledger-shrink.py"

for f in "$SSOT_DOC" "$CLASSIFY_SH" "$SHRINK_PY"; do
  [[ -f "$f" ]] || { echo "FAIL: mirror file missing at $f"; exit 1; }
done

python3 - <<'PY'
import importlib.util
import os
import re
import sys

# Built from escapes so this source file itself carries no em dash / en dash (fleet style
# rule); same construction as tools/ledger-shrink.py's `_DASH`.
EM = "\u2014"
DASHES = ("-", EM)
DASH_CLASS = "[-" + "\u2013" + EM + "]"

failures = []


def die(msg):
    print("FAIL: " + msg)
    sys.exit(1)


# ---------------------------------------------------------------- the declared SSOT ----
# Extraction approach reused from tests/test_hard_lane_buckets.sh: match the lane marker
# in the doc by a two-delimiter alternation, never by a literal delimiter byte (pinning
# the byte is the fault id:71d6 removed from the readers). Widened from that test's
# membership check to an EXTRACTION, because parity needs the set, not a spot check.
doc = open(os.environ["SSOT_DOC"], encoding="utf-8").read()
BARE_RE = re.compile(r"\[(ROUTINE|HARD|INPUT|MECHANICAL|INTENSIVE)\]")
DASH_RE = re.compile(r"\[(HARD|INPUT|INTENSIVE)\s*" + DASH_CLASS + r"\s*([A-Za-z0-9 _./-]+)\]")

ssot = set()
for m in BARE_RE.finditer(doc):
    ssot.add((m.group(1), ""))
for m in DASH_RE.finditer(doc):
    ssot.add((m.group(1), m.group(2).strip()))

# The resource axis is NOT a lane -- the SSOT says so in its own words. Dropping it here
# is the ONE editorial judgement in this extraction, and it is the SSOT's judgement.
ssot = {t for t in ssot if t[0] != "INTENSIVE"}

if len(ssot) < 5:
    die("(a) SSOT lane extraction is vacuous: %d lanes found in hard-lanes.md" % len(ssot))


def spellings(lane):
    cls, sub = lane
    if not sub:
        return ["[" + cls + "]"]
    return ["[" + cls + " " + d + " " + sub + "]" for d in DASHES]


EXPECTED = []
for lane in sorted(ssot):
    EXPECTED.extend(spellings(lane))

# Tokens the SSOT does NOT declare as lanes. Each is a real observed failure class, not a
# strawman: the two INTENSIVE forms are the orthogonal resource axis the SSOT forbids
# using as a lane, and the two invented lane names are round 2's "invented lanes".
UNDECLARED = ["[INTENSIVE]", "[HARD - kitchen]", "[INPUT - kitchen]"]
UNDECLARED += ["[INTENSIVE " + d + " local-llm]" for d in DASHES]
UNDECLARED += ["[HARD " + EM + " kitchen]"]

# ------------------------------------------------- mirror 1: classify-repo.sh LANE_TAGS -
# The tuple lives inside a python heredoc in a bash file, so it is lifted out by source
# text and evaluated. That IS the enumeration under test.
csrc = open(os.environ["CLASSIFY_SH"], encoding="utf-8").read()
mg = re.search(r"^HUMAN_GATES = \((.*?)^\)$", csrc, re.S | re.M)
ml = re.search(r"^LANE_TAGS = (.+)$", csrc, re.M)
if not mg or not ml:
    die("could not lift HUMAN_GATES/LANE_TAGS out of classify-repo.sh -- the mirror moved")
ns = {"HUMAN_GATES": eval("(" + mg.group(1) + ")")}
LANE_TAGS = eval(ml.group(1), {"__builtins__": {}}, ns)
classify_set = set(LANE_TAGS)


def classify_recognises(tok):
    # classify-repo matches LANE_TAGS by exact substring; for a whole token that is
    # membership.
    return tok in classify_set


# --------------------------------------------- mirror 2: ledger-shrink.py _LANE_PATTERNS
spec = importlib.util.spec_from_file_location("ledger_shrink_under_test", os.environ["SHRINK_PY"])
shrink = importlib.util.module_from_spec(spec)
spec.loader.exec_module(shrink)
LANE_PATTERNS = getattr(shrink, "_LANE_PATTERNS", None)
if not LANE_PATTERNS:
    die("tools/ledger-shrink.py exposes no _LANE_PATTERNS -- the mirror moved")


def shrink_recognises(tok):
    return any(rx.fullmatch(tok) for rx in LANE_PATTERNS)


# ------------------------------------------------------------------------- the parity ---
missed = [t for t in EXPECTED if not classify_recognises(t)]
if missed:
    die("(b) classify-repo LANE_TAGS misses SSOT-declared lane spellings: %r" % (missed,))

extra = [t for t in UNDECLARED if classify_recognises(t)]
if extra:
    die("(c) classify-repo LANE_TAGS recognises undeclared lane tokens: %r" % (extra,))

missed = [t for t in EXPECTED if not shrink_recognises(t)]
if missed:
    die("(d) ledger-shrink _LANE_PATTERNS misses SSOT-declared lane spellings: %r" % (missed,))

extra = [t for t in UNDECLARED if shrink_recognises(t)]
if extra:
    die("(e) ledger-shrink _LANE_PATTERNS recognises undeclared lane tokens: %r" % (extra,))

# (f) the id:4da4 PRIMARY-LANE anchoring rule, asserted BEHAVIOURALLY on whole lines.
# `_first_lane`'s own docstring says it mirrors classify-repo.sh's
# `min([(ln.find(t), t) for t in LANE_TAGS ...])`. Set parity is necessary but not
# sufficient for that: the two must pick the SAME token on the same line.
first_lane = getattr(shrink, "_first_lane", None)
if first_lane is None:
    die("tools/ledger-shrink.py exposes no _first_lane -- the anchoring mirror moved")


def classify_primary(ln):
    found = [(ln.find(t), t) for t in LANE_TAGS if ln.find(t) >= 0]
    return min(found)[1] if found else ""


LINES = [
    "- [ ] [INTENSIVE - local-llm] [HARD] rebuild the index <!-- id:0001 -->",
    "- [ ] [INTENSIVE " + EM + " local-llm] [HARD " + EM + " pool] rebuild <!-- id:0002 -->",
    "- [ ] [ROUTINE] plain routine item <!-- id:0003 -->",
    "- [ ] [INPUT - author] owner writes the prose <!-- id:0004 -->",
    "- [ ] [MECHANICAL] [INTENSIVE - local-llm] daemon run <!-- id:0005 -->",
    "- [ ] [HARD - decision gate] owner decides <!-- id:0006 -->",
    "- [ ] no lane at all on this line <!-- id:0007 -->",
]
for ln in LINES:
    got = first_lane(ln)
    got = got[1] if got else ""
    want = classify_primary(ln)
    if got != want:
        die("(f) primary-lane anchoring diverges: shrink=%r classify=%r on %r" % (got, want, ln))

print("PASS: the lane grammar is recognised identically by hard-lanes.md (SSOT), "
      "classify-repo.sh LANE_TAGS and ledger-shrink.py _LANE_PATTERNS, in both dash "
      "spellings, and both anchor the same primary lane (roadmap:4983)")
PY
