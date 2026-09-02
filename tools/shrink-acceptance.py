#!/usr/bin/env python3
"""shrink-acceptance.py -- the ACCEPTANCE GATE for the ledger line-shrink (id:0d7c).

Answers one question: did a shrink preserve everything that matters?  It takes a
BEFORE ledger tree and an AFTER ledger tree and refuses (non-zero exit) unless both
of the two independent checks below pass.  Nothing here writes; nothing here needs
the shrinker to exist -- it is a pure before/after comparator, testable from fixtures.

Ratified by `docs/meeting-notes/2026-09-01-2226-ledger-line-shrink-format.md`
decision D2, **as amended by that note's post-closure "Amendment session"**.

================================================================================
CHECK 1 -- EXACT id-SET DIFF, PER LEDGER   (the amendment's addition)
================================================================================
For each ledger file, the SET of anchored `<!-- id:XXXX -->` markers present BEFORE
must EQUAL the set present AFTER.  Same for `<!-- routed:XXXX -->`.

This is a SET comparison, never a count.  loderite ran a real shrink on 2026-09-01
and it SILENTLY DROPPED FOUR IDS (89f9, a5b6, ba07, ed26): all four sat on INDENTED
lines carrying their own id, the parser anchors its item regex at column 0, so each
read as a CONTINUATION of the preceding top-level item and was relocated wholesale --
carrying its id marker off the ledger.  Open-item COUNTS were unchanged and their
round-trip guard passed green.  The body survived in the note file; the ADDRESS did
not, so `md-merge update-ids` could no longer reach those items and `orphan-scan`
could not see them.

A detail file at `docs/ledger-notes/<id>.md` is NOT an address.  An id counts as
present only if the LEDGER LINE still carries the anchor.  When a marker is missing
we report whether a detail file exists, purely to say "body survived, address did
not" -- it never excuses the drop.

Per-ledger, not global: an id migrating from TODO.md to ROADMAP.md is a failure even
though the union is unchanged.

================================================================================
CHECK 2 -- DIRECTIONAL VERDICT CHECK   (D2 as amended by the closing pass)
================================================================================
The repo's own detectors are RUN over BEFORE and AFTER (never re-implemented -- the
keep-in-sync-by-hand cache is the defect D2 exists to kill) and their verdicts are
compared with a ONE-WAY predicate.  Strict equality is wrong twice over: it fails by
construction on `classify-repo.sh`'s `roadmap_bytes`/`todo_bytes`/`review_me_bytes`
(which MUST change), and it fires when a spurious substring hit correctly disappears,
which is the shrink working.

Every detector observation is normalised to a record with one of four polarities:

  DISPATCH   an item is actionable / dispatchable (classify-repo's `*_ids` lists).
             LOSS is FATAL -- a shrink may never remove work from the dispatch set.
             GAIN must be ATTRIBUTED (below); attributed gains are IMPROVEMENTS.

  VIOLATION  a lint/grammar/consistency complaint (roadmap-lint, todo-conformance,
             orphan-scan --cross-ledger).  Polarity is inverted: a GAIN is FATAL
             (the shrink broke the grammar -- e.g. dropped a lane tag, so
             MISSING-CLASS-TAG now fires); a LOSS is an improvement.

  GATE       a typed `gated-on:` edge resolved by resolve-gates.sh.  LOSS is FATAL
             with NO attribution excuse: a typed edge is an address, and a detail
             file cannot host one (resolve-gates reads ledgers only).  A GAIN is a
             WARNING.

  NOISE      byte/size fields.  Reported, never fatal.  Enumerated in NOISE_FIELDS.

PRESENCE, NEVER OCCURRENCE COUNT.  Every comparison above is set membership on
(signal, item), because a correct shrink legitimately reduces how many TIMES a marker
appears.  When a keep-set marker occurred more than once on an item line, the shrinker
re-appends it once; detectors test substring PRESENCE, so one occurrence is exactly as
dispatchable as three.  Measured on a real `--apply` of this repo's ledgers, the
lane-tag token count fell 618 -> 562 with zero presence-loss.  A count-equality check
would have called that a 56-token loss on a shrink that lost nothing -- a false red
that would get the gate baselined away on day one.

WHAT THIS GATE DOES NOT JUDGE.  Line LENGTH is not its business.  The shrinker
deliberately refuses to touch a block carrying another item's `<!-- id:XXXX -->` (the
loderite silent-orphan guard), refuses when there is no safe cut point, and skips
closed `[x]` items, so a correct AFTER file still contains plenty of long lines.  Those
are correct refusals.  Budget enforcement is the D4 ratchet's job in
`relay/scripts/todo-conformance.sh`, not this file's.  A barely-changed ledger (the
head-split tool moves ROADMAP.md by only ~7%, whose bloat lives in continuation lines)
must pass cleanly here, and does: identical trees produce zero findings.

ATTRIBUTION (how "spurious hit removed" is distinguished from "gate lost").
A gained DISPATCH id means some dispatch-suppressing marker stopped matching that
item's line.  We identify the suspects mechanically -- markers from the registry
present on the item's BEFORE ledger line and absent from its AFTER ledger line --
and require, for each suspect:
  * it is not NEVER_RELOCATABLE (an id/routed anchor, a typed gate edge, a lane tag);
  * its literal text is present in the item's AFTER detail file.
That is the proof the token was BODY PROSE that got relocated, rather than a
head-line control marker that got destroyed.  A gain with NO suspect at all is FATAL
("unexplained"), and a suspect whose text is nowhere in the detail file is FATAL
("destroyed, not relocated").  A marker discovered by the registry grep but carrying
no declared polarity is treated conservatively as dispatch-suppressing AND is named
in the report as an undeclared-polarity gap.

STATED GAP -- count-only fields.  classify-repo emits several counters with no
accompanying id list (`open_mechanical`, `open_human_lane`, `surfaced_open`,
`gate_blocked`, ...).  A DECREASE in one of those cannot be attributed to an item, so
it is reported as a WARNING, not a refusal.  This is a smaller hole than it looks:
the marker losses that would drive such a decrease (@manual, @owner-verify,
⚠ SURFACED, 🚧, blocked-on) also make the item DISPATCHABLE, which surfaces as a
gained DISPATCH id and goes through attribution.  It is stated rather than hidden.

================================================================================
CHECK 3 -- MARKER-REGISTRY CROSS-CHECK   (D2(c))
================================================================================
The detectors (and the lane SSOT) are GREPPED for the marker shapes they actually
match, and every discovered marker is tested against the shrinker's keep-list.  Any
marker a detector reads that no keep pattern covers is reported.  This catches marker
classes today's corpus does not exercise -- which an end-to-end round trip
STRUCTURALLY cannot, because it certifies the corpus, not the rule.

Advisory by default (the fallback keep-list is a REFERENCE, not the live shrinker's);
`--strict-markers` makes gaps fatal.

================================================================================
DETECTORS DECLARED OUT OF SCOPE -- an honest stated gap beats a silent one
================================================================================
See OUT_OF_SCOPE below.  Every entry is a detector this harness deliberately does NOT
run because it is not a pure function of the ledger files (it reads git, worktrees,
other repos or the network), so its verdict is not reproducible from a fixture pair
and a difference between BEFORE and AFTER could not be attributed to the shrink.
Their MARKERS are still cross-checked in check 3 -- being unrunnable here does not
make the markers they read droppable.

Usage:
    shrink-acceptance.py --before <dir> --after <dir> [options]

Exit codes:  0 = safe to land   1 = REFUSE   2 = usage/config error
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# --------------------------------------------------------------------------- #
# Ledger surface                                                              #
# --------------------------------------------------------------------------- #

LEDGER_FILES = [
    "TODO.md",
    "ROADMAP.md",
    "REVIEW_ME.md",
    "TODO.archive.md",
    "ROADMAP.archive.md",
    "REVIEW_ME.archive.md",
]

ID_MARKER_RE = re.compile(r"<!--\s*id:([0-9a-fA-F]{4})\s*-->")
ROUTED_MARKER_RE = re.compile(r"<!--\s*routed:([0-9a-fA-F]{4})\s*-->")

DEFAULT_NOTES_DIR = "docs/ledger-notes"

# --------------------------------------------------------------------------- #
# Detector registry -- RUNNABLE, pure functions of the ledger files            #
# --------------------------------------------------------------------------- #
# Each entry: name, argv builder (root -> list), parser (stdout, stderr, rc -> records).
# A record is (polarity, signal, key).  Polarities: dispatch | violation | gate.
#
# Verified 2026-09-02 against a bare (NON-git) fixture directory: all five run to
# completion with no git repo present, which is what makes the harness hermetic.

POLARITY_DISPATCH = "dispatch"
POLARITY_VIOLATION = "violation"
POLARITY_GATE = "gate"

# classify-repo.sh fields that MUST change and are therefore never compared.
NOISE_FIELDS = {
    "roadmap_bytes",
    "todo_bytes",
    "review_me_bytes",
    "roadmap_archive_bytes",
    "todo_archive_bytes",
    "bytes",
}

# classify-repo.sh JSON keys whose value is a list of ids that are DISPATCHABLE.
CLASSIFY_DISPATCH_ID_FIELDS = ("actionable_routine_ids", "open_hard_pool_ids")

# Free-text/derived classify fields: reported, never compared for fatality.
CLASSIFY_INFO_FIELDS = ("verdict", "reason", "priority_rank", "ambiguous", "intensive")


def _classify_argv(root: str) -> list:
    return [
        os.path.join(REPO_ROOT, "relay", "scripts", "classify-repo.sh"),
        "--repo",
        "shrink-acceptance",
        "--path",
        root,
    ]


def _classify_parse(out: str, err: str, rc: int):
    records = set()
    counts = {}
    info = {}
    payload = None
    for line in out.splitlines():
        line = line.strip()
        if line.startswith("{"):
            try:
                payload = json.loads(line)
            except ValueError:
                continue
    if payload is None:
        raise DetectorError("classify-repo.sh emitted no JSON object")
    for field in CLASSIFY_DISPATCH_ID_FIELDS:
        for item_id in payload.get(field) or []:
            key = item_id or "<no id>"
            records.add((POLARITY_DISPATCH, field, key))
    for key, value in payload.items():
        if key in NOISE_FIELDS or key.endswith("_bytes"):
            continue
        if key in CLASSIFY_INFO_FIELDS:
            info[key] = value
        elif isinstance(value, int) and not isinstance(value, bool):
            counts[key] = value
    return records, counts, info


ROADMAP_LINT_WARN_RE = re.compile(
    r"^roadmap-lint:\s*\S+\s*[-—–]+\s*([A-Z][A-Z0-9-]*):"
)
ROADMAP_LINT_ITEM_RE = re.compile(r"\bitem\s+(?:id:)?(<no id>|[0-9a-fA-F]{4})\b")
ROADMAP_LINT_REPORT_RE = re.compile(r"^  - \[(<no id>|[0-9a-fA-F]{4})\]\s+(.*)$")


def _roadmap_lint_argv(root: str) -> list:
    return [os.path.join(REPO_ROOT, "relay", "scripts", "roadmap-lint.sh"), root]


def _roadmap_lint_parse(out: str, err: str, rc: int):
    records = set()
    for line in (out + "\n" + err).splitlines():
        m = ROADMAP_LINT_WARN_RE.match(line)
        if m:
            item = ROADMAP_LINT_ITEM_RE.search(line)
            key = item.group(1) if item else "<no id>"
            records.add((POLARITY_VIOLATION, "roadmap-lint:" + m.group(1), key))
            continue
        m = ROADMAP_LINT_REPORT_RE.match(line)
        if m:
            key = m.group(1)
            for chunk in m.group(2).split(";"):
                chunk = " ".join(chunk.split())
                if chunk:
                    records.add((POLARITY_VIOLATION, "roadmap-lint/" + chunk, key))
    return records, {}, {}


def _todo_conformance_argv(root: str) -> list:
    return [
        os.path.join(REPO_ROOT, "relay", "scripts", "todo-conformance.sh"),
        os.path.join(root, "TODO.md"),
    ]


def normalise_signal(rule: str) -> str:
    """Strip a rule token's trailing parenthetical qualifier (id:75c8).

    A signal is an IDENTITY, so it must not carry a MEASUREMENT.  `todo-conformance.sh`
    spells its length rules `length-grandfathered (1367 chars > budget 500, within
    baseline 3004)`: the parenthetical moves on every run in which the item shrank at
    all, so a shrink that merely made a line shorter reported the old signal LOST and a
    new one GAINED -- for the same rule, on the same item, both non-blocking REPORT
    lines.  MEASURED on the live gate run of 2026-09-02: 42 of 43 fatals were exactly
    this (37 `length-unshrinkable` + 5 `length-grandfathered`), while that same
    detector's real findings fell 669 -> 75, an improvement the gate could not see.
    The false red is the more dangerous half -- it is how a gate gets baselined away on
    day one.

    The rule is deliberately blunt: keep the leading token, drop every qualifier.  The
    two stable qualifiers this collapses (`decided-left-open (baselined id:cb3e)`,
    `dep-prose-untyped (id:3ef7)`) lose no signal the gate acts on, because polarity and
    item are carried separately and a genuine budget REGRESSION changes the leading
    token itself (`length-grandfathered` -> `length-over-budget`).  Narrowing this to
    "parentheticals containing a number" would keep an id-bearing qualifier and drop a
    measurement, which is a distinction no output format promises to preserve.
    """
    return rule.split("(", 1)[0].strip()


# todo-conformance rules this gate counts but never treats as a violation (id:75c8).
#
# This file's own contract says it: "WHAT THIS GATE DOES NOT JUDGE. Line LENGTH is not
# its business ... Budget enforcement is the D4 ratchet's job in todo-conformance.sh."
# The implementation contradicted that by recording every length finding as a VIOLATION,
# so a line that shrank from 4376 to 1974 chars -- correct, wanted, the whole point --
# flipped from `length-grandfathered` to `length-unshrinkable` and was reported as "the
# shrink broke the ledger grammar". MEASURED on the live run of 2026-09-02: 19 of the
# 20 remaining fatals were this, and ALL 19 items had shrunk, none by less than 20%.
#
# Scoped to the two rules todo-conformance DECLARES non-blocking in its own header
# ("`length-unshrinkable` WARN -- reported, NEVER blocking"; `length-grandfathered` WARN).
# `length-over-budget` and `length-regrowth` are its ERRORs and stay FATAL here, so a
# shrink that pushed a line past its baseline is still refused. Deliberately not "every
# rule starting with length-": the ratchet's two error rules are the ones that would
# catch this tool damaging a ledger, and waiving them to make a run pass is precisely
# the day-one erosion the ratifying meeting warned about.
TODO_CONFORMANCE_NONBLOCKING = frozenset(
    ("length-unshrinkable", "length-grandfathered")
)

# id:b048 -- the ledger LINE GRAMMAR family is non-blocking here too, and unlike the
# `length-` family above it IS matched by prefix. The asymmetry is deliberate and rests
# on a fact about each family, not on convenience: `length-` contains two ERROR rules
# (`length-over-budget`, `length-regrowth`) that must stay fatal, so it can only be
# waived rule-by-rule; `grammar-` is WARN-ONLY BY CONSTRUCTION -- todo-conformance.sh
# adds every grammar class to `findings` and never to `strict_findings`, so there is no
# grammar rule that could become fatal for a prefix match to swallow by accident.
#
# WHY THIS EXISTS AT ALL: the grammar check reports 382 findings on TODO.md and 532 on
# ROADMAP.md today (almost everything is non-conforming, which is the point of filing
# id:b048). Without this, every one of them would parse as a POLARITY_VIOLATION and this
# gate -- the id:5f34 loss-attribution gate -- would go red for reasons that have nothing
# to do with whether a shrink damaged anything. That would disarm the one instrument the
# shrink programme relies on, which is the id:0b70 vacuous-check failure inverted.
#
# If a grammar rule is ever promoted to an ERROR, this prefix must become an enumeration.
TODO_CONFORMANCE_NONBLOCKING_PREFIXES = ("grammar-",)


def _todo_conformance_parse(out: str, err: str, rc: int):
    records = set()
    counts = {}
    for line in out.splitlines():
        parts = line.split("\t")
        if len(parts) < 3:
            continue
        rule, _lineno, text = parts[0], parts[1], "\t".join(parts[2:])
        rule = normalise_signal(rule)
        if rule in TODO_CONFORMANCE_NONBLOCKING or rule.startswith(
            TODO_CONFORMANCE_NONBLOCKING_PREFIXES
        ):
            counts[rule] = counts.get(rule, 0) + 1
            continue
        m = ID_MARKER_RE.search(text)
        key = m.group(1) if m else "<no id>"
        records.add((POLARITY_VIOLATION, "todo-conformance:" + rule, key))
    return records, counts, {}


def _resolve_gates_argv(root: str) -> list:
    return [os.path.join(REPO_ROOT, "relay", "scripts", "resolve-gates.sh"), root]


def _resolve_gates_parse(out: str, err: str, rc: int):
    records = set()
    for line in out.splitlines():
        parts = line.split("\t")
        if len(parts) < 2:
            continue
        own_id, block = parts[0].strip(), parts[1].strip()
        dangling = parts[2].strip() if len(parts) > 2 else ""
        if block == "1":
            records.add((POLARITY_GATE, "resolve-gates:blocked", own_id))
        if dangling:
            records.add((POLARITY_GATE, "resolve-gates:dangling", own_id))
    return records, {}, {}


ORPHAN_XLEDGER_RE = re.compile(r"^id:([0-9a-fA-F]{4})\b")


def _orphan_cross_argv(root: str) -> list:
    return [os.path.join(REPO_ROOT, "meeting", "orphan-scan.sh"), "--cross-ledger", root]


def _orphan_cross_parse(out: str, err: str, rc: int):
    records = set()
    for line in out.splitlines():
        m = ORPHAN_XLEDGER_RE.match(line.strip())
        if m:
            records.add((POLARITY_VIOLATION, "orphan-scan:cross-ledger", m.group(1)))
    return records, {}, {}


DETECTOR_REGISTRY = [
    {
        "name": "classify-repo",
        "path": "relay/scripts/classify-repo.sh",
        "argv": _classify_argv,
        "parse": _classify_parse,
        "reads": "ROADMAP.md, TODO.md, REVIEW_ME.md and their archives",
    },
    {
        "name": "roadmap-lint",
        "path": "relay/scripts/roadmap-lint.sh",
        "argv": _roadmap_lint_argv,
        "parse": _roadmap_lint_parse,
        "reads": "ROADMAP.md (+ TODO twin lookup)",
    },
    {
        "name": "todo-conformance",
        "path": "relay/scripts/todo-conformance.sh",
        "argv": _todo_conformance_argv,
        "parse": _todo_conformance_parse,
        "reads": "TODO.md",
        "requires": "TODO.md",
    },
    {
        "name": "resolve-gates",
        "path": "relay/scripts/resolve-gates.sh",
        "argv": _resolve_gates_argv,
        "parse": _resolve_gates_parse,
        "reads": "ROADMAP.md union TODO.md union both archives",
    },
    {
        "name": "orphan-scan--cross-ledger",
        "path": "meeting/orphan-scan.sh",
        "argv": _orphan_cross_argv,
        "parse": _orphan_cross_parse,
        "reads": "TODO.md + ROADMAP.md checkbox states",
    },
]

# --------------------------------------------------------------------------- #
# DECLARED OUT OF SCOPE -- not pure functions of the ledger                    #
# --------------------------------------------------------------------------- #
OUT_OF_SCOPE = [
    (
        "relay/scripts/gather-human-backlog.sh",
        "probes git worktrees and per-repo git state (warn_nested_worktrees, push "
        "commands); its output is not reproducible from a ledger pair",
    ),
    (
        "relay/scripts/unpromoted-scan.sh",
        "reads git history/blame to age items",
    ),
    (
        "meeting/orphan-scan.sh (--reverse / default staleness mode)",
        "ages TODO lines by `git blame` author-time; only --cross-ledger is pure and "
        "that mode IS in the registry above",
    ),
    (
        "relay/scripts/classify-verdict.sh + relay/scripts/gather-repo-state.sh",
        "consume whole-repo git state (commits, branches, dirtiness), not ledgers",
    ),
    (
        "relay/scripts/discover-repo.sh / discover-chunk.sh / reconcile-repo.sh",
        "run live git fetch / ff-merge / worktree reap with side effects",
    ),
    (
        "relay/scripts/scan-routed.sh",
        "cross-repo: resolves inbox twins against OTHER repositories",
    ),
    (
        "relay/scripts/gaming-scan.sh, run-anomaly-scan.sh, stranded-branch-scan.sh",
        "audit git history and run state, not ledger content",
    ),
    (
        "hooks/pre-commit-lane-vocab.sh",
        "operates on a STAGED git diff, so it has no meaning for a fixture pair "
        "(the meeting note records why it cannot fire on relocated prose anyway: it "
        "matches only a CHECKBOX line's leftmost lane bracket, and detail files "
        "contain no checkbox lines)",
    ),
    (
        "relay/scripts/prompt-size-gate.mjs / ledger-slice.sh",
        "byte-budget and slicing consumers, not preservation detectors; their "
        "post-shrink correctness is separately specified by id:f3d2 and id:2ee1",
    ),
]

# Not runnable here, but their MARKERS still bind the keep-list.
MARKER_SOURCES = [
    ("relay/scripts/classify-repo.sh", "detector"),
    ("relay/scripts/roadmap-lint.sh", "detector"),
    ("relay/scripts/todo-conformance.sh", "detector"),
    ("relay/scripts/resolve-gates.sh", "detector"),
    ("relay/scripts/lib-typed-edges.sh", "detector"),
    ("relay/scripts/gather-human-backlog.sh", "detector"),
    ("meeting/orphan-scan.sh", "detector"),
    # The lane / marker VOCABULARY SSOT. Not runnable, but a marker defined here binds
    # the keep-list just as hard: some are read by prose contracts (review.md's
    # gaming-check) rather than by a script, and relocating one destroys the receipt
    # with no detector anywhere to notice.
    ("relay/references/hard-lanes.md", "vocabulary"),
]

# --------------------------------------------------------------------------- #
# Marker registry: shapes to hunt for in detector sources                      #
# --------------------------------------------------------------------------- #
# `@` must not be preceded by an identifier char, which kills email addresses and
# `$@`.  Everything else is a literal shape.
#
# The `[-—–]` classes below are DELIBERATE and load-bearing: the lane-tag delimiter is
# mid-migration from an em dash to a spaced hyphen, and both spellings are live in the
# corpus and in the detectors.  A registry that reads only one spelling would report the
# other half of the lane vocabulary as absent.  Match both when reading; emit neither.
MARKER_SHAPE_RES = [
    re.compile(r"(?<![A-Za-z0-9_.\-])@[a-z][a-z0-9-]*"),
    re.compile(r"\U0001F6A7"),  # the gate glyph classify-repo.sh matches bare
    re.compile(r"⚠\s?SURFACED"),
    re.compile(r"BLOCKED on|Blocked on|blocked on"),
    re.compile(r"\[(?:ROUTINE|MECHANICAL)\]"),
    re.compile(r"\[HARD(?:\s*[-—–]\s*[a-z ]+)?\]"),
    re.compile(r"\[INPUT\s*[-—–]\s*[a-z ]+\]"),
    re.compile(r"\[INTENSIVE\s*[-—–]\s*[a-z-]+\]"),
    re.compile(r"<!--\s*id:"),
    re.compile(r"<!--\s*routed:"),
    re.compile(r"gated-on:"),
    re.compile(r"children-of:"),
]

# `@`-shaped tokens that are not ledger markers.
MARKER_DENYLIST = {
    "@anthropic-ai",
    "@claude",
    "@zommuter",
    "@googlemail",
    "@example",
    "@import",
    "@media",
    "@param",
    "@returns",
    "@see",
    "@type",
}

# Hand-declared policy for the markers we understand.  Anything the grep discovers
# that is ABSENT here is treated conservatively (dispatch-suppressing) and NAMED in
# the report as an undeclared-polarity gap.
#   suppresses_dispatch -- its presence can keep an item out of the dispatch set, so
#                          its disappearance is what an attributed gain must explain.
#   never_relocatable   -- an ADDRESS or a routing control surface; no detail-file
#                          copy can ever excuse its loss.
MARKER_POLICY = {
    "@manual": {"suppresses_dispatch": True, "never_relocatable": False},
    "@owner-verify": {"suppresses_dispatch": True, "never_relocatable": False},
    "@owner-gated": {"suppresses_dispatch": True, "never_relocatable": False},
    "@container": {"suppresses_dispatch": True, "never_relocatable": False},
    "@wire": {"suppresses_dispatch": False, "never_relocatable": False},
    "@needs-auth": {"suppresses_dispatch": False, "never_relocatable": False},
    "@owner-answered": {"suppresses_dispatch": False, "never_relocatable": False},
    "@manually": {"suppresses_dispatch": True, "never_relocatable": False},
    "\U0001F6A7": {"suppresses_dispatch": True, "never_relocatable": False},
    "BLOCKED on": {"suppresses_dispatch": True, "never_relocatable": False},
    "blocked on": {"suppresses_dispatch": True, "never_relocatable": False},
    "Blocked on": {"suppresses_dispatch": True, "never_relocatable": False},
    "⚠ SURFACED": {"suppresses_dispatch": True, "never_relocatable": False},
    "gated-on:": {"suppresses_dispatch": True, "never_relocatable": True},
    "<!-- id:": {"suppresses_dispatch": False, "never_relocatable": True},
    "<!-- routed:": {"suppresses_dispatch": False, "never_relocatable": True},
    "children-of:": {"suppresses_dispatch": False, "never_relocatable": True},
    "[ROUTINE]": {"suppresses_dispatch": False, "never_relocatable": True},
    "[MECHANICAL]": {"suppresses_dispatch": False, "never_relocatable": True},
    # A close-gate receipt, not a dispatch gate: the owner-only marker that lets a
    # user-visible item be bump-closed (id:8089). No runnable detector reads it -- the
    # review gaming-check greps for it -- so relocating it destroys the receipt with
    # nothing left to notice.
    "@owner-accepted": {"suppresses_dispatch": False, "never_relocatable": False},
}

# Any lane-tag-shaped marker: a lane routes dispatch, so it is a control surface that a
# detail file can never host. Declared as a RULE rather than by enumerating twelve
# spellings across three dash characters -- enumerating is how a lane goes missing.
LANE_TAG_SHAPE_RE = re.compile(r"^\[(?:ROUTINE|MECHANICAL|HARD|INPUT|INTENSIVE)\b")


def marker_policy(marker):
    """Declared policy, else the lane-tag rule, else None (undeclared)."""
    if marker in MARKER_POLICY:
        return MARKER_POLICY[marker]
    if LANE_TAG_SHAPE_RE.match(marker):
        return {"suppresses_dispatch": True, "never_relocatable": True}
    return None

# Some markers only ever appear in a fuller form on a real ledger line; the keep-list
# is tested against these samples too before a gap is reported.
MARKER_SAMPLE_SUFFIX = {
    "@owner-answered": ":2026-01-01",
    "gated-on:": "aa01",
    "<!-- id:": "aa01 -->",
    "<!-- routed:": "aa01 -->",
    "children-of:": "aa01",
}

# --------------------------------------------------------------------------- #
# Keep-list                                                                    #
# --------------------------------------------------------------------------- #
# The REFERENCE keep-list, transcribed from loderite's
# `tools/extract-roadmap-notes.mjs::MUST_KEEP_PATTERNS` (read 2026-09-02).  Used only
# when no live keep-list is supplied or discovered; the report always says which
# source was used, and marker gaps stay ADVISORY against the reference.
REFERENCE_KEEP_PATTERNS = [
    r"<!--\s*id:[0-9a-f]{4}\s*-->",
    r"<!--\s*routed:[0-9a-f]{4}\s*-->",
    r"\[(?:ROUTINE|HARD|MECHANICAL)\]",
    r"(?i)\[(?:HARD|INPUT)\s*[-—–]\s*[a-z ]+\]",
    r"<!--\s*gated-on:[^>]*-->",
    r"gated-on:[0-9a-f]{4}",
    r"\U0001F6A7",
    r"`?@manual`?",
    r"`?@owner-gated`?",
    r"`?@container`?",
    r"`?@owner-answered:[0-9-]+`?",
    r"BLOCKED on",
]

KEEPLIST_NAME_RE = re.compile(
    r"^\s*(?:MUST_KEEP_PATTERNS|KEEP_PATTERNS)\s*[:=]", re.MULTILINE
)


class DetectorError(Exception):
    pass


def import_keep_list(path):
    """Import the shrinker and read its live keep-list.

    Textual extraction is not good enough: the live list is built as
    `[re.compile(...), ...] + _LANE_PATTERNS`, so a source scrape of the bracket span
    silently misses every lane pattern and would then report all twelve lane tags as
    keep-list GAPS -- a manufactured false failure of exactly the kind this gate exists
    to avoid.  Importing reads what the shrinker will actually apply.
    """
    import importlib.util

    spec = importlib.util.spec_from_file_location("_shrinker_under_test", path)
    if spec is None or spec.loader is None:
        return []
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    for name in ("MUST_KEEP_PATTERNS", "KEEP_PATTERNS"):
        pats = getattr(mod, name, None)
        if not pats:
            continue
        out = []
        for p in pats:
            out.append(p.pattern if hasattr(p, "pattern") else str(p))
        return out
    return []


def load_keep_list(explicit, shrinker):
    """Return (patterns, source_label, is_reference)."""
    if explicit:
        pats = []
        with open(explicit, encoding="utf-8", errors="replace") as fh:
            for raw in fh:
                raw = raw.strip()
                if raw and not raw.startswith("#"):
                    pats.append(raw)
        return pats, explicit, False
    if shrinker and os.path.isfile(shrinker):
        pats = []
        if shrinker.endswith(".py"):
            try:
                pats = import_keep_list(shrinker)
            except Exception as exc:  # noqa: BLE001 -- an unimportable shrinker must not
                sys.stderr.write(                 # crash the gate; we fall back and SAY so.
                    "shrink-acceptance: could not import %s (%s); falling back to a "
                    "source scrape, which can under-report the keep-list\n" % (shrinker, exc)
                )
        if not pats:
            pats = extract_keep_patterns_from_source(shrinker)
        if pats:
            return pats, shrinker, False
    return (
        REFERENCE_KEEP_PATTERNS,
        "built-in REFERENCE list (loderite extract-roadmap-notes.mjs MUST_KEEP_PATTERNS)",
        True,
    )


def extract_keep_patterns_from_source(path):
    """Pull the raw-string members of a MUST_KEEP_PATTERNS / KEEP_PATTERNS list."""
    with open(path, encoding="utf-8", errors="replace") as fh:
        text = fh.read()
    m = KEEPLIST_NAME_RE.search(text)
    if not m:
        return []
    tail = text[m.end():]
    depth = 0
    body = []
    for ch in tail:
        if ch == "[":
            depth += 1
            if depth == 1:
                continue
        elif ch == "]":
            depth -= 1
            if depth == 0:
                break
        if depth >= 1:
            body.append(ch)
    blob = "".join(body)
    pats = []
    for lit in re.finditer(r"""(?:r|rb|br)?(?P<q>'''|\"\"\"|'|")(?P<body>.*?)(?P=q)""", blob, re.S):
        val = lit.group("body")
        if val:
            pats.append(val)
    return pats


# --------------------------------------------------------------------------- #
# Check 1 -- id set diff                                                       #
# --------------------------------------------------------------------------- #

def collect_markers(root):
    """{ledger filename: {'id': set, 'routed': set}} for files present on disk."""
    out = {}
    for name in LEDGER_FILES:
        path = os.path.join(root, name)
        if not os.path.isfile(path):
            continue
        with open(path, encoding="utf-8", errors="replace") as fh:
            text = fh.read()
        out[name] = {
            "id": set(m.group(1).lower() for m in ID_MARKER_RE.finditer(text)),
            "routed": set(m.group(1).lower() for m in ROUTED_MARKER_RE.finditer(text)),
        }
    return out


def find_in_notes(root, notes_dir, kind, token):
    """Detail files under `notes_dir` that carry `<!-- kind:token -->`."""
    base = os.path.join(root, notes_dir)
    if not os.path.isdir(base):
        return []
    needle = re.compile(r"<!--\s*%s:%s\s*-->" % (kind, re.escape(token)), re.IGNORECASE)
    hits = []
    for dirpath, _dirnames, filenames in os.walk(base):
        for name in sorted(filenames):
            path = os.path.join(dirpath, name)
            try:
                with open(path, encoding="utf-8", errors="replace") as fh:
                    if needle.search(fh.read()):
                        hits.append(os.path.relpath(path, root))
            except OSError:
                continue
    return sorted(hits)


def check_id_sets(before_root, after_root, notes_dir, findings):
    before = collect_markers(before_root)
    after = collect_markers(after_root)
    lines = []
    for name in LEDGER_FILES:
        b, a = before.get(name), after.get(name)
        if b is None and a is None:
            continue
        if b is None:
            findings.append(
                ("FATAL", "id-set", "%s exists AFTER but not BEFORE -- the ledger set changed" % name)
            )
            continue
        if a is None:
            findings.append(
                ("FATAL", "id-set", "%s exists BEFORE but not AFTER -- the whole ledger vanished" % name)
            )
            continue
        for kind in ("id", "routed"):
            dropped = sorted(b[kind] - a[kind])
            added = sorted(a[kind] - b[kind])
            for tok in dropped:
                # Where did the body go?  loderite's four orphans were relocated into the
                # PARENT item's note file, not into one named after themselves, so this
                # scans the whole notes tree rather than probing <tok>.md.
                homes = find_in_notes(after_root, notes_dir, kind, tok)
                if homes:
                    note = (" -- the marker now sits in %s, so the BODY survived and the "
                            "ADDRESS did not; a detail file is not an address"
                            % ", ".join(homes[:3]))
                else:
                    note = (" -- and it is nowhere in %s either: destroyed outright"
                            % notes_dir)
                findings.append(  # id:0d7c ORPHAN-FATAL
                    ("FATAL", "id-set",
                     "ORPHANED %s:%s -- present in %s BEFORE, absent AFTER%s"
                     % (kind, tok, name, note))
                )
            for tok in added:
                findings.append(
                    ("FATAL", "id-set",
                     "UNEXPECTED %s:%s -- absent from %s BEFORE, present AFTER; a shrink "
                     "relocates prose, it never mints or moves an address" % (kind, tok, name))
                )
            lines.append(
                "  %-22s %-7s before=%-4d after=%-4d dropped=%-3d added=%d"
                % (name, kind, len(b[kind]), len(a[kind]), len(dropped), len(added))
            )
    return lines


# --------------------------------------------------------------------------- #
# Check 2 -- directional verdicts                                              #
# --------------------------------------------------------------------------- #

def run_detector(det, root, timeout):
    if "requires" in det and not os.path.isfile(os.path.join(root, det["requires"])):
        return None, "%s absent" % det["requires"]
    script = os.path.join(REPO_ROOT, det["path"])
    if not os.path.isfile(script):
        return None, "detector not found at %s" % det["path"]
    env = dict(os.environ)
    env["LC_ALL"] = "C.UTF-8"
    try:
        proc = subprocess.run(
            det["argv"](root),
            capture_output=True,
            text=True,
            timeout=timeout,
            env=env,
            cwd=root,
        )
    except subprocess.TimeoutExpired:
        return None, "timed out after %ss" % timeout
    except OSError as exc:
        return None, "could not execute: %s" % exc
    try:
        return det["parse"](proc.stdout, proc.stderr, proc.returncode), None
    except DetectorError as exc:
        return None, str(exc)


# find_item_line search order (id:5f34 fix): ROADMAP first then TODO, matching this
# function's own docstring. LEDGER_FILES itself lists TODO.md before ROADMAP.md (it is
# ordered for collect_markers' report, not for this lookup), so iterating it directly
# silently returned the TODO.md twin's line whenever an item lived in both -- the twin
# is deliberately a SHORTER line with no lane/state prose, so attribution read the wrong
# line and any lexeme that only ever appears on the ROADMAP line was invisible.
FIND_ITEM_LINE_ORDER = (
    "ROADMAP.md", "TODO.md", "REVIEW_ME.md",
    "ROADMAP.archive.md", "TODO.archive.md", "REVIEW_ME.archive.md",
)


def find_item_line(root, item_id):
    """The ledger line carrying `<!-- id:XXXX -->`, ROADMAP first then TODO."""
    needle = re.compile(r"<!--\s*id:%s\s*-->" % re.escape(item_id), re.IGNORECASE)
    for name in FIND_ITEM_LINE_ORDER:
        path = os.path.join(root, name)
        if not os.path.isfile(path):
            continue
        with open(path, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                if needle.search(line):
                    return line.rstrip("\n")
    return None


def read_detail_file(root, notes_dir, item_id):
    path = os.path.join(root, notes_dir, item_id + ".md")
    if not os.path.isfile(path):
        return None
    with open(path, encoding="utf-8", errors="replace") as fh:
        return fh.read()


def attribute_dispatch_gain(item_id, before_root, after_root, notes_dir, markers):
    """Return (ok, message).  ok=True means an ACCEPTABLE 'spurious hit removed'."""
    # id:0d7c ATTRIBUTION
    before_line = find_item_line(before_root, item_id)
    after_line = find_item_line(after_root, item_id)
    if before_line is None:
        return False, ("id:%s became dispatchable but carries no ledger line BEFORE -- "
                       "the gain cannot be attributed to prose relocation" % item_id)
    if after_line is None:
        return False, ("id:%s became dispatchable but has no ledger line AFTER" % item_id)

    suspects = []
    for marker in markers:
        pol = marker_policy(marker)
        suppresses = True if pol is None else pol["suppresses_dispatch"]
        if not suppresses:
            continue
        if marker in before_line and marker not in after_line:
            suspects.append(marker)
    if not suspects:
        return False, (
            "id:%s became dispatchable but NO dispatch-suppressing marker left its "
            "ledger line -- unexplained verdict movement, refusing" % item_id
        )
    detail = read_detail_file(after_root, notes_dir, item_id)
    for marker in suspects:
        pol = marker_policy(marker)
        undeclared = pol is None
        if pol is not None and pol["never_relocatable"]:
            return False, (
                "id:%s became dispatchable because %r left its ledger line; that marker "
                "is an ADDRESS / control surface and may never be relocated" % (item_id, marker)
            )
        if detail is None:
            return False, (
                "id:%s became dispatchable because %r left its ledger line, and no "
                "detail file %s/%s.md exists -- the marker was DESTROYED, not relocated"
                % (item_id, marker, notes_dir, item_id)
            )
        if marker not in detail:
            return False, (
                "id:%s became dispatchable because %r left its ledger line, but %r is "
                "not present in %s/%s.md either -- DESTROYED, not relocated"
                % (item_id, marker, marker, notes_dir, item_id)
            )
        if undeclared:
            return True, (
                "id:%s dispatchable after a relocated %r (marker has NO declared "
                "polarity -- treated conservatively; see the undeclared-polarity gap)"
                % (item_id, marker)
            )
    return True, (
        "id:%s became dispatchable because %s stopped false-matching; the text is "
        "present in %s/%s.md, so it was body prose, not a control marker"
        % (item_id, ", ".join(repr(s) for s in suspects), notes_dir, item_id)
    )


# --------------------------------------------------------------------------- #
# Violation-loss attribution (id:5f34)                                        #
# --------------------------------------------------------------------------- #
# Mirrors attribute_dispatch_gain() in the other direction: a VIOLATION loss is
# scored as an improvement UNCONDITIONALLY today, which is right for a spurious
# substring hit disappearing and exactly wrong for a detector that went BLIND --
# the two are indistinguishable from the record alone. MEASURED 2026-09-02 on
# the wave-1 shrink: 40 of 54 `decided-left-open` losses were the triggering
# RESOLVED/SUPERSEDED/DONE/CLOSED/DEFERRED lexeme relocating VERBATIM into the
# item's detail note, not the state claim actually going away.
#
# Scoped to the terminal-word vocabulary lib-state-claim.sh's DECIDED-LEFT-OPEN
# rule actually matches -- that is the concrete class that was measured blind,
# and it is the shape that file's own doctrine already teaches
# (state_claim_direction_i / ii). The boundary is NOT bare `\b`: a hyphen-joined
# compound ("fail-CLOSED") is excluded the same way lib-state-claim.sh excludes
# it, so a design-property phrase never counts as a self-assertion.
VIOLATION_LEXEME_RES = [
    re.compile(r"(?<![A-Za-z0-9_-])(RESOLVED|SUPERSEDED|DONE|CLOSED|DEFERRED)(?![A-Za-z0-9_-])"),
    re.compile(r"[Dd]ecided[ \t]+[0-9]{4}-[0-9]{2}-[0-9]{2}"),
    re.compile(r"closed[ \t]+[0-9]{4}-[0-9]{2}-[0-9]{2}"),
]


def attribute_violation_loss(item_id, before_root, after_root, notes_dir):
    """Return (ok, message).  ok=True means an ACCEPTABLE genuine improvement
    (the triggering lexeme is gone from everywhere); ok=False means the
    detector went BLIND (the lexeme merely relocated into the detail note)."""
    # id:5f34 ATTRIBUTION (mirrors attribute_dispatch_gain, opposite direction)
    before_line = find_item_line(before_root, item_id)
    after_line = find_item_line(after_root, item_id) or ""
    if before_line is None:
        return True, (
            "id:%s lost a violation but carries no BEFORE ledger line -- cannot "
            "attribute, treating conservatively as an improvement" % item_id
        )
    suspects = []
    for rx in VIOLATION_LEXEME_RES:
        for m in rx.finditer(before_line):
            lexeme = m.group(0)
            if lexeme not in after_line and lexeme not in suspects:
                suspects.append(lexeme)
    if not suspects:
        return True, (
            "id:%s: violation no longer fires and no known terminal-word lexeme "
            "left the ledger line -- treating as a genuine improvement" % item_id
        )
    detail = read_detail_file(after_root, notes_dir, item_id)
    for lexeme in suspects:
        if detail is not None and lexeme in detail:
            return False, (
                "id:%s: violation LOST but %r still appears verbatim in %s/%s.md -- "
                "the detector went BLIND, the item is still decided-and-left-open, "
                "it just cannot see it any more" % (item_id, lexeme, notes_dir, item_id)
            )
    return True, (
        "id:%s: violation lost and %s genuinely gone from both the ledger line and "
        "any detail file -- a real improvement"
        % (item_id, ", ".join(repr(s) for s in suspects))
    )


def check_detectors(before_root, after_root, notes_dir, markers, findings, timeout):
    lines = []
    improvements = []
    for det in DETECTOR_REGISTRY:
        b, b_err = run_detector(det, before_root, timeout)
        a, a_err = run_detector(det, after_root, timeout)
        if b_err or a_err:
            if b_err and a_err and b_err == a_err:
                lines.append("  %-26s SKIPPED (%s, both sides)" % (det["name"], b_err))
                continue
            findings.append(
                ("FATAL", "detector",
                 "%s ran differently on the two sides (before: %s / after: %s) -- the "
                 "comparison is not trustworthy" % (det["name"], b_err or "ok", a_err or "ok"))
            )
            continue
        if b is None or a is None:
            # A detector that returned no result AND no error is unverifiable, not clean.
            # Fail CLOSED: an acceptance gate that cannot compare must refuse, never crash
            # on the unpack and never wave the merge through. Same doctrine as
            # integrate.sh's isolation base -- an unverifiable gate blocks.
            findings.append(
                ("FATAL", "detector",
                 "%s returned no result and no error on the %s side, so the comparison "
                 "is unverifiable -- refusing rather than assuming it is clean"
                 % (det["name"], "before" if b is None else "after"))
            )
            continue
        b_rec, b_counts, b_info = b
        a_rec, a_counts, a_info = a

        # PRESENCE per (signal, item), never occurrence counts. A correct shrink
        # legitimately reduces how many TIMES a marker appears on a line -- when a
        # keep-set marker occurred more than once, the shrinker re-appends it ONCE, and
        # detectors test substring PRESENCE, so one occurrence is exactly as dispatchable
        # as three. Measured on a real --apply of this repo's ledgers: the lane-tag token
        # count fell 618 -> 562 with zero presence-loss. A count-equality check would
        # report a 56-occurrence "loss" on a shrink that lost nothing, which is the class
        # of false red that gets a gate baselined away on day one.
        for key in sorted(b_rec | a_rec):
            polarity, signal, item = key
            was, now = key in b_rec, key in a_rec
            if was == now:
                continue
            if polarity == POLARITY_DISPATCH:
                if was and not now:
                    findings.append(
                        ("FATAL", "verdict",
                         "%s: DISPATCHABILITY LOST -- %s no longer lists id:%s. "
                         "A shrink may never remove work from the dispatch set."
                         % (det["name"], signal, item))
                    )
                else:
                    ok, msg = attribute_dispatch_gain(
                        item, before_root, after_root, notes_dir, markers
                    )
                    if ok:
                        improvements.append("%s: %s" % (det["name"], msg))
                    else:
                        findings.append(("FATAL", "verdict", "%s: %s" % (det["name"], msg)))
            elif polarity == POLARITY_VIOLATION:
                if now and not was:
                    findings.append(
                        ("FATAL", "verdict",
                         "%s: NEW VIOLATION -- %s now fires for %s. The shrink "
                         "broke the ledger grammar." % (det["name"], signal, item))
                    )
                else:
                    ok, msg = attribute_violation_loss(
                        item, before_root, after_root, notes_dir
                    )
                    if ok:
                        improvements.append("%s: %s" % (det["name"], msg))
                    else:
                        findings.append(("FATAL", "verdict", "%s: %s" % (det["name"], msg)))
            elif polarity == POLARITY_GATE:
                if was and not now:
                    findings.append(
                        ("FATAL", "verdict",
                         "%s: GATE LOST -- %s no longer resolves for id:%s. A "
                         "typed gate edge is an address; a detail file cannot host one."
                         % (det["name"], signal, item))
                    )
                else:
                    findings.append(
                        ("WARN", "verdict",
                         "%s: new gate %s for id:%s -- conservative direction, "
                         "not a refusal" % (det["name"], signal, item))
                    )

        for key in sorted(set(b_counts) | set(a_counts)):
            bv, av = b_counts.get(key), a_counts.get(key)
            if bv == av:
                continue
            findings.append(
                ("WARN", "verdict",
                 "%s: count-only field %s moved %s -> %s. No id accompanies this field, so "
                 "the change cannot be attributed to an item (stated gap); the marker losses "
                 "that would drive it also surface as dispatch gains, which ARE attributed."
                 % (det["name"], key, bv, av))
            )
        for key in sorted(set(b_info) | set(a_info)):
            bv, av = b_info.get(key), a_info.get(key)
            if bv != av:
                lines.append("  %-26s %s: %r -> %r (derived, informational)"
                             % (det["name"], key, bv, av))
        lines.append(
            "  %-26s presence-records before=%d after=%d"
            % (det["name"], len(b_rec), len(a_rec))
        )
    return lines, improvements


# --------------------------------------------------------------------------- #
# Check 3 -- marker registry vs keep-list                                      #
# --------------------------------------------------------------------------- #

def grep_markers():
    """{marker literal: sorted list of 'path:line' sightings}."""
    found = {}
    for rel, _kind in MARKER_SOURCES:
        path = os.path.join(REPO_ROOT, rel)
        if not os.path.isfile(path):
            continue
        strip_comments = os.path.splitext(rel)[1] in (".sh", ".py", ".mjs", ".js")
        with open(path, encoding="utf-8", errors="replace") as fh:
            for lineno, line in enumerate(fh, 1):
                if strip_comments and line.lstrip().startswith("#"):
                    continue
                for rx in MARKER_SHAPE_RES:
                    for m in rx.finditer(line):
                        lit = m.group(0)
                        if lit in MARKER_DENYLIST:
                            continue
                        found.setdefault(lit, []).append("%s:%d" % (rel, lineno))
    return {k: sorted(set(v)) for k, v in found.items()}


def check_keep_list(markers, keep_patterns, keep_source, strict, findings):
    compiled = []
    for pat in keep_patterns:
        try:
            compiled.append((pat, re.compile(pat)))
        except re.error as exc:
            findings.append(("FATAL", "marker", "keep-list pattern %r does not compile: %s" % (pat, exc)))
    gaps = []
    covered = []
    for marker in sorted(markers):
        samples = [marker, "`%s`" % marker]
        suffix = MARKER_SAMPLE_SUFFIX.get(marker)
        if suffix:
            samples.append(marker + suffix)
            samples.append("`%s%s`" % (marker, suffix))
        hit = None
        for pat, rx in compiled:
            if any(rx.search(s) for s in samples):
                hit = pat
                break
        if hit:
            covered.append((marker, hit))
        else:
            gaps.append(marker)
    vocab_only = {rel for rel, kind in MARKER_SOURCES if kind == "vocabulary"}
    for marker in gaps:
        sightings = markers[marker]
        kinds = {s.rsplit(":", 1)[0] for s in sightings}
        where = ("the marker VOCABULARY SSOT only, not any runnable detector -- it is "
                 "enforced by a prose contract, so nothing mechanical would notice its loss"
                 if kinds <= vocab_only else "a runnable detector")
        level = "FATAL" if strict else "WARN"
        findings.append(
            (level, "marker",
             "KEEP-LIST GAP: %r is read by %s (%s) but no keep pattern in %s covers it -- "
             "a shrink may relocate it off the ledger line and nothing here or in a corpus "
             "round trip would notice"
             % (marker, where, ", ".join(sightings[:4]), keep_source))
        )
    undeclared = [m for m in sorted(markers) if marker_policy(m) is None]
    for marker in undeclared:
        findings.append(
            ("WARN", "marker",
             "UNDECLARED POLARITY: %r was discovered by the registry grep (%s) but has no "
             "entry in MARKER_POLICY; it is treated conservatively as dispatch-suppressing "
             "and relocatable" % (marker, ", ".join(markers[marker][:2])))
        )
    return covered, gaps, undeclared


# --------------------------------------------------------------------------- #
# main                                                                         #
# --------------------------------------------------------------------------- #

def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Acceptance gate for the ledger line-shrink (id:0d7c).",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument("--before", required=True, help="ledger tree BEFORE the shrink")
    ap.add_argument("--after", required=True, help="ledger tree AFTER the shrink")
    ap.add_argument("--notes-dir", default=DEFAULT_NOTES_DIR,
                    help="relocated-detail directory, relative to the tree root "
                         "(default: %s)" % DEFAULT_NOTES_DIR)
    ap.add_argument("--keep-list", help="file of keep-list regexes, one per line")
    ap.add_argument("--shrinker", default=os.path.join(REPO_ROOT, "tools", "ledger-shrink.py"),
                    help="shrinker source to lift MUST_KEEP_PATTERNS/KEEP_PATTERNS from")
    ap.add_argument("--strict-markers", action="store_true",
                    help="make keep-list gaps FATAL (default: advisory)")
    ap.add_argument("--skip-detectors", action="store_true",
                    help="run check 1 and check 3 only")
    ap.add_argument("--timeout", type=int, default=180)
    ap.add_argument("--quiet", action="store_true", help="findings only")
    args = ap.parse_args(argv)

    for label, root in (("--before", args.before), ("--after", args.after)):
        if not os.path.isdir(root):
            sys.stderr.write("shrink-acceptance: %s is not a directory: %s\n" % (label, root))
            return 2

    findings = []
    out = []

    out.append("shrink-acceptance -- ledger line-shrink gate (id:0d7c)")
    out.append("  before: %s" % os.path.abspath(args.before))
    out.append("  after:  %s" % os.path.abspath(args.after))
    out.append("")

    out.append("CHECK 1 -- exact id-SET diff, per ledger")
    out.extend(check_id_sets(args.before, args.after, args.notes_dir, findings))
    out.append("")

    out.append("CHECK 2 -- directional verdict check")
    improvements = []
    if args.skip_detectors:
        out.append("  SKIPPED (--skip-detectors)")
    else:
        markers = grep_markers()
        det_lines, improvements = check_detectors(
            args.before, args.after, args.notes_dir, markers, findings, args.timeout
        )
        out.extend(det_lines)
        out.append("  detector registry (runnable, pure functions of the ledger):")
        for det in DETECTOR_REGISTRY:
            out.append("    - %s (%s) reads %s" % (det["name"], det["path"], det["reads"]))
        out.append("  DECLARED OUT OF SCOPE (not pure functions of the ledger):")
        for path, why in OUT_OF_SCOPE:
            out.append("    - %s: %s" % (path, why))
    out.append("")

    out.append("CHECK 3 -- marker registry vs keep-list")
    keep_patterns, keep_source, is_reference = load_keep_list(args.keep_list, args.shrinker)
    strict = args.strict_markers
    out.append("  keep-list source: %s%s" % (keep_source, " [REFERENCE]" if is_reference else ""))
    markers = grep_markers()
    covered, gaps, undeclared = check_keep_list(markers, keep_patterns, keep_source, strict, findings)
    out.append("  markers discovered: %d   covered: %d   GAPS: %d   undeclared-polarity: %d"
               % (len(markers), len(covered), len(gaps), len(undeclared)))
    for marker in sorted(markers):
        state = "GAP    " if marker in gaps else "covered"
        out.append("    %-7s %-22s %s" % (state, marker, ", ".join(markers[marker][:3])))
    out.append("")

    if improvements:
        out.append("IMPROVEMENTS (verdict moved the ALLOWED way -- spurious hit removed)")
        for msg in improvements:
            out.append("  + %s" % msg)
        out.append("")

    fatal = [f for f in findings if f[0] == "FATAL"]
    warn = [f for f in findings if f[0] == "WARN"]
    out.append("FINDINGS: %d fatal, %d warning" % (len(fatal), len(warn)))
    for level, check, msg in findings:
        out.append("  %-5s [%s] %s" % (level, check, msg))
    out.append("")
    if fatal:
        out.append("VERDICT: REFUSE -- the shrink did not preserve everything that matters.")
    else:
        out.append("VERDICT: SAFE TO LAND.")

    if args.quiet:
        sys.stdout.write("\n".join(l for l in out if l.startswith(("  FATAL", "  WARN", "VERDICT"))) + "\n")
    else:
        sys.stdout.write("\n".join(out) + "\n")
    return 1 if fatal else 0


if __name__ == "__main__":
    sys.exit(main())
