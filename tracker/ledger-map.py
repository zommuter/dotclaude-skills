#!/usr/bin/env python3
"""tracker/ledger-map.py — the reference bespoke-markdown -> intermediate-JSON mapper.

TODO id:2bb1 (children-of:4a5c), meeting
`docs/meeting-notes/2026-08-10-0906-tracker-substrate-replacing-markdown-ledgers.md` D2.

This is the *durable artifact* of the tracker pilot: the mapping from this fleet's
bespoke ledger grammar onto a tool-independent item model. It survives any tool
outcome (Plane / Vikunja / git-bug / none). `tracker/SCHEMA.md` is the prose contract,
`tracker/schema/ledger-intermediate.schema.json` is the machine-readable one, and this
file is the executable one. All three must agree; `validate` cross-checks the last two.

Scope boundary: this maps ONE repo tree per `import` call and validates a whole
document. The fleet driver (relay.toml own-set, pinned SHAs, tombstones, upserts,
recurring cadence) is a SEPARATE gated item — id:94ce. Adapters are id:90f2. Repo-entity
verdict derivation is id:c17d; this file emits the repo entity with `verdict: null`.

Subcommands
-----------
  import <repo-name> <repo-dir> [...]   read ledgers, print an intermediate JSON document
  merge <doc.json>...                   merge per-repo documents into one fleet document
  validate <doc.json>                   invariants + schema cross-check; loud, non-zero on failure
  render-status <doc.json>              project each item back to its per-view checkbox states

Stdlib only (repo convention: no venv, no deps).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from typing import NoReturn

# THE single declared copy of the contract-surface version for every *python* consumer
# (id:8c7f). `tracker/repo-entity.py` and `tracker/adapters/adapter_common.py` derive
# theirs from the JSON Schema's `const`, which `schema_cross_check()` pins to this
# literal — so there are two declared copies (this one and the schema's), cross-checked,
# instead of the four uncross-checked ones that let a value-space change ship unversioned.
# `tracker/fleet-import.sh` scrapes the assignment below by regex, so it must stay a plain
# literal — and no line ABOVE it may imitate that spelling, or the scrape reads the
# imitation instead (this comment used to, and did).
#
# 1.1.0 (id:8c7f): `repos[].verdict`'s VALUE SPACE was replaced under 1.0.0 — three of the
# five documented values (relay-poolable / needs-feedback / design-drained) moved to the
# new `board_column` — with no `enum` keyword to catch it. A changed value space is
# semantically NON-additive even when no key is added or removed, so it takes a minor
# bump, and both value spaces are now `enum`-declared and validated.
SCHEMA_VERSION = "1.1.0"

# ---- repo-entity value spaces (schema `$defs/repo`) ----------------------------------
# Mirrors of tracker/repo-entity.py's enums, which quote relay/scripts/classify-verdict.sh
# and relay/scripts/control-board.sh. Held here too so `validate` can check a document's
# repo entities and cross-check the schema, which previously read ONLY `$defs.item`.
VERDICT_ENUM = [
    "blocked", "execute", "review", "hard", "handoff",
    "human", "mechanical", "idle", "AMBIGUOUS",
]
BOARD_COLUMN_ENUM = [
    "blocked", "relay-poolable", "needs-feedback", "design-drained", "unclassified",
]
# Values that WERE in `verdict`'s documented space under 1.0.0 and are now `board_column`
# values. Named, not merely absent, so a 1.0.0-era document fails with the migration in
# the error text instead of a bare "not in enum".
RETIRED_VERDICTS = {"relay-poolable", "needs-feedback", "design-drained"}

REPO_REQUIRED = ["repo", "path", "verdict", "labels"]
# The full declared property set of `$defs/repo`. Cross-checked as a SET, so adding or
# removing a repo property without touching this list is a loud drift (`head_sha` was
# load-bearing in tracker/fleet-state.py while undeclared in the schema entirely).
REPO_PROPERTIES = [
    "repo", "path", "head_sha", "verdict", "labels", "ledger_files",
    "board_column", "board_label", "verdict_reason", "counts",
    "verdict_source", "verdict_generated_at",
]

# Files that must NOT re-introduce a hardcoded copy of the version constant; they derive
# it from the schema (or, for the shell driver, scrape it from this file).
VERSION_DERIVED_FILES = [
    os.path.join("tracker", "repo-entity.py"),
    os.path.join("tracker", "adapters", "adapter_common.py"),
    os.path.join("tracker", "fleet-import.sh"),
]
RE_VERSION_LITERAL = re.compile(r"[\"']([0-9]+\.[0-9]+\.[0-9]+)[\"']")
RE_VERSION_CONTEXT = re.compile(r"schema[_ ]?version", re.IGNORECASE)

# A plain constant, NOT `__doc__`: `python3 -OO` strips docstrings, so deriving the
# argparse description from `__doc__` made every subcommand die with
# `AttributeError: 'NoneType' object has no attribute 'split'` before parsing a single
# argument. The fleet driver (id:94ce) and the adapters (id:90f2) shell out to this
# file, so it must not depend on docstrings surviving interpreter optimisation.
CLI_SUMMARY = ("tracker/ledger-map.py — the reference bespoke-markdown -> "
               "intermediate-JSON mapper.")

HERE = os.path.dirname(os.path.abspath(__file__))
SCHEMA_PATH = os.path.join(HERE, "schema", "ledger-intermediate.schema.json")

# --------------------------------------------------------------------------- #
# Grammar constants — kept deliberately in ONE place so SCHEMA.md, the JSON
# Schema and this mapper can be cross-checked against each other.
# --------------------------------------------------------------------------- #

STATUS_ENUM = ["open", "done", "absent"]
DERIVED_STATUS_ENUM = ["backlog", "queued", "done", "needs-decision"]
LANE_ENUM = ["routine", "hard", "input", "mechanical", "untagged"]
INPUT_KIND_ENUM = ["meeting", "decision", "access", "author", "user", "unresolved-hands"]
ASSIGNEE_ENUM = ["executor", "apex", "human", "daemon"]
KIND_ENUM = ["ledger_item", "review_box"]
LINK_KIND_ENUM = ["routed", "settles", "decided-in"]

# Anchored markers only — a bare/backticked mention in prose is NEVER a marker.
# Same anchoring discipline as relay/scripts/lib-anchored-id.sh (id:521f/3add) and
# relay/scripts/lib-typed-edges.sh (id:46f6); re-implemented here rather than shelled
# out to, because this is a pure-python producer and the regexes ARE the contract.
RE_CHECKBOX = re.compile(r"^(?P<indent>[ \t]*)- \[(?P<box>[ xX])\] (?P<text>.*)$")
RE_HEADING = re.compile(r"^(?P<hashes>#{1,6}) +(?P<title>.*?)\s*$")
RE_OWN_ID = re.compile(r"<!--\s*id:([0-9a-fA-F]{4})\s*-->")
RE_OWN_ROADMAP_REF = re.compile(r"<!--\s*roadmap:([0-9a-fA-F]{4})\s*-->")
RE_ROUTED = re.compile(r"<!--\s*routed:([0-9a-fA-F]{4})\s*-->")
RE_CHILDREN = re.compile(r"<!--\s*children:([0-9a-f,]+)\s*-->")
RE_CHILDREN_OF = re.compile(r"<!--\s*children-of:([0-9a-f,]+)\s*-->")
RE_GATED_ON = re.compile(r"<!--\s*gated-on:([0-9a-f,]+)\s*-->")
RE_SETTLES = re.compile(r"<!--\s*settles:([0-9a-f,]+)\s*-->")
RE_DECIDED_IN = re.compile(r"<!--\s*decided-in:(\S+)\s*-->")
RE_HTML_COMMENT = re.compile(r"<!--.*?-->")

# Lane / capability tags. Order matters: the legacy `[HARD — <lane>]` forms must be
# matched BEFORE the bare `[HARD]`, or every legacy item reads as bare-hard.
# The delimiter matches EITHER an em dash or an ASCII hyphen (dual-vocab migration
# window, id:c442 — mirrors relay/scripts/roadmap-lint.sh's `lane_delim_re`); a
# ledger already migrated to the hyphen spelling must not silently degrade to
# lane:untagged just because this reader only knew the old em-dash form.
_LANE_DELIM = r"\s*[—-]\s*"
RE_HARD_LEGACY = re.compile(r"\[HARD" + _LANE_DELIM + r"([a-z][a-z ]*[a-z])\]")
RE_INPUT = re.compile(r"\[INPUT" + _LANE_DELIM + r"([a-z]+)\]")
RE_INTENSIVE = re.compile(r"\[INTENSIVE" + _LANE_DELIM + r"([A-Za-z0-9_.-]+)\]")
RE_HOST = re.compile(r"\[host:([A-Za-z0-9_.-]+)\]", re.IGNORECASE)
RE_ROUTE_INLINE = re.compile(r"route:(meeting|human|decision-gate)")
RE_OWNER_ACCEPTED = re.compile(r"@owner-accepted:(\d{4}-\d{2}-\d{2})")
RE_UNKNOWN_MARKER = re.compile(r"(?<![\w`])@([a-z][a-z0-9-]*)")
RE_SUBFIELD = re.compile(r"\*\*(Acceptance|Tests|Done-check|Context)\*\*\s*[:—-]?\s*(.*)$")

# `[HARD — hands]` has NO single auto-default (hard-lanes.md, amendment 2026-07-02:
# it fragments across FOUR destinations by per-item human judgment). The mapper
# therefore NEVER guesses — it maps to `input:unresolved-hands` and reports it.
LEGACY_HARD_LANES = {
    "pool": ("hard", None, "pool"),
    "meeting": ("input", "meeting", None),
    "decision gate": ("input", "decision", None),
    "hands": ("input", "unresolved-hands", None),
}

KNOWN_MARKERS = {"manual", "needs-auth", "wire", "owner-verify", "owner-accepted"}

# Section names that mean "this whole section is parked" (mirrors
# relay/scripts/roadmap-lint.sh:256's gated-heading predicate).
RE_GATED_SECTION = re.compile(r"(gated|deferred|done|icebox|archive|parked)", re.IGNORECASE)

# view -> (filename, archived)
LEDGER_FILES = [
    ("todo", "TODO.md", False),
    ("todo", "TODO.archive.md", True),
    ("roadmap", "ROADMAP.md", False),
    ("roadmap", "ROADMAP.archive.md", True),
    ("review", "REVIEW_ME.md", False),
    ("review", "REVIEW_ME.archive.md", True),
]


def die(msg: str, code: int = 2) -> NoReturn:
    # NoReturn, not None: this function ALWAYS raises. Annotating it `-> None` made every
    # `except: die(...)` block look like it could fall through, so a type-checker reported
    # a false "possibly unbound" on any name bound in the corresponding `try` (e.g. `lines`
    # in collect_allowed_homonyms). Verified false positive — the body has no return path.
    print("ERROR: %s" % msg, file=sys.stderr)
    raise SystemExit(code)


def synthetic_key(view: str, title: str) -> str:
    """Deterministic key for an id-less line (see SCHEMA.md 'id-less policy').

    Keyed on (view, normalized title) rather than (file, line) so that inserting a
    line above an untracked item does not re-key it. The known cost — documented,
    not hidden — is that REWORDING an untracked line's head text produces a NEW key,
    which an upserting importer (id:94ce) sees as tombstone+create.
    """
    norm = re.sub(r"\s+", " ", title).strip().lower()
    return "~" + hashlib.sha1(("%s\n%s" % (view, norm)).encode("utf-8")).hexdigest()[:12]


def strip_markers(text: str) -> str:
    return re.sub(r"\s+", " ", RE_HTML_COMMENT.sub("", text)).strip()


def make_title(text: str) -> str:
    t = strip_markers(text)
    t = re.sub(r"\[[^\]\[]{1,40}\]", "", t)          # bracket tags
    t = t.replace("**", "").replace("`", "").strip(" -—:")
    t = re.sub(r"\s+", " ", t).strip()
    if len(t) > 200:
        cut = t[:200].rsplit(" ", 1)[0]
        t = cut + "…"
    return t or "(untitled)"


# --------------------------------------------------------------------------- #
# Parsing
# --------------------------------------------------------------------------- #


class Report:
    """Loud-lossy accumulator (id:4347 no-silent-swallow, [[no-swallow-stderr]])."""

    def __init__(self) -> None:
        self.entries = []

    def add(self, construct: str, file: str, line: int, text: str, reason: str) -> None:
        self.entries.append(
            {
                "construct": construct,
                "file": file,
                "line": line,
                "text": strip_markers(text)[:200],
                "reason": reason,
            }
        )

    def counts(self) -> dict:
        out = {}
        for e in self.entries:
            out[e["construct"]] = out.get(e["construct"], 0) + 1
        return dict(sorted(out.items()))


def parse_tags(text: str, file: str, line: int, report: Report, lane_required: bool = True) -> dict:
    """Map the bracket-tag + @marker vocabulary onto labels/lane/resource fields."""
    lane = None
    input_kind = None
    venue = None
    labels = []
    resource = None
    host = None
    markers = []
    owner_accepted = None
    legacy_vocab = False

    m = RE_HARD_LEGACY.search(text)
    if m:
        raw = m.group(1).strip()
        legacy_vocab = True
        if raw in LEGACY_HARD_LANES:
            lane, input_kind, venue = LEGACY_HARD_LANES[raw]
            if raw == "hands":
                report.add(
                    "legacy-hands-unresolved",
                    file,
                    line,
                    text,
                    "[HARD — hands] has no 1:1 successor (hard-lanes.md names FOUR "
                    "candidates); mapped to input:unresolved-hands, never guessed",
                )
        else:
            lane = "untagged"
            report.add("unknown-hard-lane", file, line, text,
                       "unrecognised [HARD — %s] lane" % raw)
    elif "[MECHANICAL]" in text:
        lane = "mechanical"
    elif "[ROUTINE]" in text:
        lane = "routine"
    else:
        mi = RE_INPUT.search(text)
        if mi:
            lane = "input"
            input_kind = mi.group(1)
            if input_kind not in INPUT_KIND_ENUM:
                report.add("unknown-input-kind", file, line, text,
                           "unrecognised [INPUT — %s] kind" % input_kind)
                input_kind = None
        elif "[HARD]" in text:
            lane = "hard"

    if lane is None:
        lane = "untagged"

    mr = RE_INTENSIVE.search(text)
    if mr:
        resource = mr.group(1)
    mh = RE_HOST.search(text)
    if mh:
        host = mh.group(1)

    # Inline auto-gate route markers are EXACT synonyms of the meeting/decision lanes
    # (hard-lanes.md "recognized aliases"). They refine, never override, an explicit tag.
    mrt = RE_ROUTE_INLINE.search(text)
    if mrt and lane in ("input", "untagged"):
        lane = "input"
        if input_kind is None:
            input_kind = "decision" if mrt.group(1) == "decision-gate" else "meeting"

    moa = RE_OWNER_ACCEPTED.search(text)
    if moa:
        owner_accepted = moa.group(1)

    for mm in RE_UNKNOWN_MARKER.finditer(text):
        name = mm.group(1)
        if name in KNOWN_MARKERS:
            if name not in markers:
                markers.append(name)
        else:
            report.add("unknown-marker", file, line, text, "@%s is not in the known marker set" % name)

    # A REVIEW_ME box has no capability lane by design; emitting `lane:untagged` for it
    # would pollute the labels of the ledger item it attaches to (a box on a [HARD] item
    # would read as both lane:hard AND lane:untagged).
    if lane_required or lane != "untagged":
        labels.append("lane:%s" % lane)
    if input_kind:
        labels.append("input:%s" % input_kind)
    if venue:
        labels.append("venue:%s" % venue)
    if legacy_vocab:
        labels.append("vocab:legacy")
    if resource:
        labels.append("resource:%s" % resource)
    if host:
        labels.append("host:%s" % host)
    for mk in markers:
        labels.append("marker:%s" % mk)

    blocked = ("🚧" in text) or ("BLOCKED on" in text) or ("blocked on" in text)
    if blocked:
        labels.append("gate:blocked")

    if lane == "untagged" and lane_required:
        report.add("untagged-lane", file, line, text,
                   "no recognised capability tag; hard-lanes.md makes this a LOUD reject "
                   "at the source (roadmap-lint.sh owns enforcement, this mapper only reports)")

    return {
        "lane": lane,
        "input_kind": input_kind,
        "resource": resource,
        "host": host,
        "markers": markers,
        "owner_accepted": owner_accepted,
        "labels": sorted(set(labels)),
        "blocked": blocked,
    }


def assignee_for(lane: str, markers, kind: str):
    if kind == "review_box":
        return "human"
    if lane == "input":
        return "human"
    if any(m in ("manual", "needs-auth", "owner-verify") for m in markers):
        return "human"
    if lane == "mechanical":
        return "daemon"
    if lane == "routine":
        return "executor"
    if lane == "hard":
        return "apex"
    return None


def parse_file(path: str, relname: str, view: str, archived: bool,
               report: Report) -> list:
    """Parse one ledger file into a list of per-view observations.

    Deliberately repo-BLIND: observations carry a bare `_key`, and `assemble()` is the
    single place that composes the `(repo, id)` uid. (A dead `repo` parameter used to
    sit here, which read as if uids were minted in two places.)
    """
    with open(path, "r", encoding="utf-8") as fh:
        lines = fh.read().split("\n")

    obs = []
    section = None
    cur = None
    prose_run = 0

    def close(item):
        if item is None:
            return
        item["body"] = "\n".join(item["_body"]).strip()
        del item["_body"]
        obs.append(item)

    for i, raw in enumerate(lines, start=1):
        mh = RE_HEADING.match(raw)
        if mh:
            close(cur)
            cur = None
            if len(mh.group("hashes")) >= 2:
                section = strip_markers(mh.group("title"))
            continue

        mc = RE_CHECKBOX.match(raw)
        if mc:
            close(cur)
            indent = len(mc.group("indent").expandtabs(4))
            text = mc.group("text")
            state = "done" if mc.group("box").lower() == "x" else "open"
            # REVIEW_ME boxes carry no capability lane by design (they are human-assignee
            # prose boxes) — a missing lane there is NOT the hard-lanes.md loud reject.
            tags = parse_tags(text, relname, i, report, lane_required=(view != "review"))

            ids = RE_OWN_ID.findall(text)
            # id:6059 — a line carrying SEVERAL anchored id markers is AMBIGUOUS: the
            # grammar spells "this line IS X" and "this line REFERS to X" identically,
            # and the two live shapes put the own id at opposite ends (a body that QUOTES
            # a marker → last; a TRAILING reference → first, loderite routed:3ad9). Both
            # positional rules mis-attribute one shape, so NEITHER is taken: the line
            # imports as UNTRACKED (no id, synthetic key) and is reported below. A wrong
            # id here would be a wrong tracker identity, propagated fleet-wide.
            token = ids[0].lower() if len(ids) == 1 else None
            attaches_to = None
            if view == "review":
                if token is None:
                    ref = RE_OWN_ROADMAP_REF.findall(text)
                    if ref:
                        attaches_to = ref[0].lower()
                else:
                    attaches_to = token
                    token = None

            if len(ids) > 1:
                report.add("multi-id-line", relname, i, text,
                           "line carries %d anchored id markers; the LAST is taken as "
                           "the owning id (lib-anchored-id.sh convention, id:6059) — "
                           "de-literalise the quoted marker in the prose" % len(ids))

            key = token or attaches_to or synthetic_key(view, text)
            cur = {
                "_key": key,
                "_view": view,
                "_attaches_to": attaches_to,
                "id": token,
                "state": state,
                "archived": archived,
                "indent": indent,
                "section": section,
                "section_gated": bool(section and RE_GATED_SECTION.search(section)),
                # Kept even when the line HAS a key of its own: `assemble()` re-keys a
                # review box whose anchor turns out to have no ledger twin, and it can
                # only do that after every file has been parsed (id:b7f4).
                "_synthetic": synthetic_key(view, text),
                "kind": "review_box" if view == "review" else "ledger_item",
                "title": make_title(text),
                "tags": tags,
                "file": relname,
                "line": i,
                "children_of": [t for csv in RE_CHILDREN_OF.findall(text) for t in csv.split(",") if t],
                "children": [t for csv in RE_CHILDREN.findall(text) for t in csv.split(",") if t],
                "gated_on": [t for csv in RE_GATED_ON.findall(text) for t in csv.split(",") if t],
                "links": (
                    [{"kind": "routed", "token": t.lower(), "target_uid": None}
                     for t in RE_ROUTED.findall(text)]
                    + [{"kind": "settles", "token": t.lower(), "target_uid": None}
                       for csv in RE_SETTLES.findall(text) for t in csv.split(",") if t]
                    + [{"kind": "decided-in", "token": None, "target_uid": None, "path": p}
                       for p in RE_DECIDED_IN.findall(text)]
                ),
                "fields": {},
                "_body": [text],
            }
            if token is None and attaches_to is None and view != "review":
                report.add(
                    "id-less-item", relname, i, text,
                    "checkbox line carries no anchored <!-- id:XXXX --> marker; imported "
                    "as identity=untracked with a content-derived synthetic key "
                    "(SCHEMA.md id-less policy), never silently skipped",
                )
            if view == "review" and attaches_to is None:
                report.add("review-box-unanchored", relname, i, text,
                           "REVIEW_ME box carries no anchored id/roadmap marker; imported "
                           "as a standalone untracked review_box item")
            prose_run = 0
            continue

        if cur is not None:
            if raw.strip() == "":
                # A blank line ends an item block only if the next non-blank is not a
                # continuation; keep it simple and treat blank as the block terminator.
                close(cur)
                cur = None
                continue
            cur["_body"].append(raw)
            msf = RE_SUBFIELD.search(raw)
            if msf:
                cur["fields"][msf.group(1).lower().replace("-", "_")] = strip_markers(msf.group(2))
            continue

        if raw.strip():
            prose_run += 1
            if prose_run == 1:
                report.add("section-prose", relname, i, raw,
                           "narrative block outside any checkbox item; not an item, "
                           "carried by no tracker primitive (counted, not imported)")

    close(cur)
    return obs


# --------------------------------------------------------------------------- #
# Item assembly
# --------------------------------------------------------------------------- #


def uid_of(repo: str, key: str) -> str:
    return "%s/%s" % (repo, key)


def derived_status(item: dict) -> str:
    """DERIVED, adapters-only. The per-view fields stay authoritative.

    Rule (SCHEMA.md 'derived_status'): an OPEN view always beats a DONE view — under
    drift the item is never reported done. Promotion to ROADMAP is 'queued'.
    """
    if item["kind"] == "review_box" and item.get("review_status") == "open":
        return "needs-decision"
    if item["roadmap_status"] == "open":
        return "queued"
    if item["todo_status"] == "open":
        return "backlog"
    if item.get("review_status") == "open":
        return "needs-decision"
    if "done" in (item["todo_status"], item["roadmap_status"], item.get("review_status")):
        return "done"
    return "backlog"


def resolve_review_anchors(observations: list, report: Report) -> None:
    """Re-key REVIEW_ME boxes whose anchor id has NO ledger twin (id:b7f4).

    SCHEMA.md 2.3 gave the anchored box exactly two shapes — *attaches to the twin* or
    *standalone untracked* — and silently assumed the anchored one always finds a twin.
    A box anchored to an id that no TODO/ROADMAP line owns fell between them: it kept the
    bare 4-hex key while carrying `id: null`, which is precisely the state `validate`
    rejects ("no id but its key is not a synthetic '~' key"). Observed on the pilot repo
    (`REVIEW_ME.archive.md` box anchored to an id whose ledger line was never written /
    was archived away), where it made the WHOLE repo unimportable.

    Policy (SCHEMA.md 2.3, third row): the box becomes a **standalone untracked** box —
    synthetic `~` key, `identity: "untracked"` — carrying label `dangling-anchor:XXXX`
    and a loud `review-box-dangling-anchor` report. The two rejected alternatives are
    recorded there: keeping the 4-hex key breaks the uid invariant, and promoting the
    anchor to the box's own `id` would fabricate a *tracked* item for an id no ledger
    owns — a ghost on the board and a false positive for every id-consuming scanner.

    Mutates the observations in place; must run BEFORE `assemble()` composes uids, and
    only after EVERY ledger file has been parsed (an anchor may be owned by any of them).
    """
    owned = {ob["id"] for ob in observations if ob.get("id")}
    for ob in observations:
        anchor = ob.get("_attaches_to")
        if ob["_view"] != "review" or not anchor or anchor in owned:
            continue
        report.add(
            "review-box-dangling-anchor", ob["file"], ob["line"], ob["title"],
            "REVIEW_ME box is anchored to id:%s, which NO TODO/ROADMAP line owns; "
            "imported as a standalone untracked review_box with a synthetic key and a "
            "dangling-anchor:%s label (SCHEMA.md 2.3), never attached to a fabricated "
            "twin" % (anchor, anchor),
        )
        ob["_key"] = ob["_synthetic"]
        ob["_attaches_to"] = None
        ob["tags"]["labels"] = sorted(set(ob["tags"]["labels"] + ["dangling-anchor:%s" % anchor]))


def assemble(repo: str, observations: list, report: Report) -> list:
    resolve_review_anchors(observations, report)
    items = {}
    for ob in observations:
        key = ob["_key"]
        uid = uid_of(repo, key)
        it = items.get(uid)
        if it is None:
            it = {
                "uid": uid,
                "repo": repo,
                "id": ob["id"],
                "identity": "tracked" if ob["id"] else "untracked",
                "kind": ob["kind"],
                "title": ob["title"],
                "body": "",
                "todo_status": "absent",
                "roadmap_status": "absent",
                "review_status": "absent",
                "drift": False,
                "derived_status": "backlog",
                "labels": [],
                "assignee": None,
                "parent": None,
                "parents": [],
                "children": [],
                "blocked_by": [],
                "links": [],
                "fields": {},
                "archived": False,
                "section": ob["section"],
                "section_gated": ob["section_gated"],
                "owner_accepted": None,
                "sources": [],
            }
            items[uid] = it

        view = ob["_view"]
        it["sources"].append({
            "file": ob["file"], "line": ob["line"], "view": view, "archived": ob["archived"],
        })
        field = {"todo": "todo_status", "roadmap": "roadmap_status", "review": "review_status"}[view]
        if it[field] != "absent":
            # First-wins, matching lib-typed-edges.sh: the ACTIVE file beats the
            # archive for the same view. Report it rather than silently keeping one.
            report.add("duplicate-view-observation", ob["file"], ob["line"], ob["title"],
                       "%s already has a %s observation; first-wins (active file "
                       "precedes archive)" % (uid, view))
        else:
            it[field] = ob["state"]

        if ob["kind"] == "review_box" and it["kind"] == "ledger_item":
            it["labels"] = sorted(set(it["labels"] + ["has:review-box"]))
        elif ob["kind"] == "review_box":
            it["kind"] = "review_box"

        if ob["archived"]:
            it["archived"] = True
        if not it["body"]:
            it["body"] = ob["body"]
        if it["section"] is None:
            it["section"] = ob["section"]
        it["labels"] = sorted(set(it["labels"] + ob["tags"]["labels"]))
        it["fields"].update(ob["fields"])
        it["links"].extend(ob["links"])
        if ob["tags"]["owner_accepted"]:
            it["owner_accepted"] = ob["tags"]["owner_accepted"]
        for t in ob["children_of"]:
            # id:8302 — a child-side line can declare MULTIPLE parents
            # (`<!-- children-of:aa01,aa02 -->`); collect ALL of them into the
            # `parents` list rather than overwriting a single scalar slot, which
            # silently dropped every parent but the last.
            p = uid_of(repo, t)
            if p not in it["parents"]:
                it["parents"].append(p)
        for t in ob["children"]:
            c = uid_of(repo, t)
            if c not in it["children"]:
                it["children"].append(c)
        for t in ob["gated_on"]:
            b = uid_of(repo, t)
            if b not in it["blocked_by"]:
                it["blocked_by"].append(b)
        if ob["_view"] != "review":
            a = assignee_for(ob["tags"]["lane"], ob["tags"]["markers"], ob["kind"])
            if a:
                it["assignee"] = a
        elif it["assignee"] is None:
            it["assignee"] = "human"

    # id:59c5 — reconcile `children-of:`/`children:` into ONE relation. Each
    # spelling previously populated only its own item's field (a child-side
    # `children-of:P` filled `parents` on the child; a parent-side `children:C`
    # filled `children` on the parent), so a pair naming the same fact from
    # opposite ends produced two different graphs depending on which end wrote
    # it. Mirror both directions here: for every parent an item declares, add
    # the item to that parent's `children`; for every child an item declares,
    # add the item to that child's `parents`. A single pass over all items is
    # sufficient and order-independent — each item's own `parents`/`children`
    # already carry its own directive (populated above), so mirroring from
    # every item's perspective reaches both ends of every edge regardless of
    # which side wrote it or the dict's iteration order. A dangling reference
    # to an id with no observed item is left as-is (nothing to mirror onto).
    for it in items.values():
        for p in it["parents"]:
            parent = items.get(p)
            if parent is not None and it["uid"] not in parent["children"]:
                parent["children"].append(it["uid"])
        for c in it["children"]:
            child = items.get(c)
            if child is not None and it["uid"] not in child["parents"]:
                child["parents"].append(it["uid"])

    for it in items.values():
        # Backward-compat scalar: consumers that read the single `parent` field get
        # the first declared parent (previously they got whichever `children-of:`
        # token happened to be parsed last). The full, lossless fact lives in
        # `parents`.
        it["parent"] = it["parents"][0] if it["parents"] else None
        it["drift"] = (
            it["todo_status"] != "absent"
            and it["roadmap_status"] != "absent"
            and it["todo_status"] != it["roadmap_status"]
        )
        it["derived_status"] = derived_status(it)
        if it["drift"]:
            it["labels"] = sorted(set(it["labels"] + ["drift:cross-ledger"]))
    return [items[k] for k in sorted(items)]


def import_repo(repo: str, root: str) -> dict:
    report = Report()
    obs = []
    seen_files = []
    for view, fname, archived in LEDGER_FILES:
        path = os.path.join(root, fname)
        if not os.path.exists(path):
            continue
        seen_files.append(fname)
        obs.extend(parse_file(path, fname, view, archived, report))
    items = assemble(repo, obs, report)
    return {
        "schema_version": SCHEMA_VERSION,
        "repos": [
            {
                "repo": repo,
                # As GIVEN, never abspath'd: the golden fixture document must be
                # byte-reproducible on any machine, and the fleet driver (id:94ce)
                # passes the absolute path it resolved from relay.toml anyway.
                "path": root,
                "verdict": None,
                "labels": [],
                "ledger_files": seen_files,
            }
        ],
        "items": items,
        "unmapped": report.entries,
        "unmapped_counts": report.counts(),
    }


def merge_docs(docs: list) -> dict:
    out = {
        "schema_version": SCHEMA_VERSION,
        "repos": [],
        "items": [],
        "unmapped": [],
        "unmapped_counts": {},
    }
    for d in docs:
        out["repos"].extend(d.get("repos", []))
        out["items"].extend(d.get("items", []))
        out["unmapped"].extend(d.get("unmapped", []))
    for e in out["unmapped"]:
        k = e["construct"]
        out["unmapped_counts"][k] = out["unmapped_counts"].get(k, 0) + 1
    out["unmapped_counts"] = dict(sorted(out["unmapped_counts"].items()))
    out["items"].sort(key=lambda i: i["uid"])
    return out


# --------------------------------------------------------------------------- #
# Validation
# --------------------------------------------------------------------------- #


def load_schema():
    if not os.path.exists(SCHEMA_PATH):
        die("machine-readable schema missing: %s" % SCHEMA_PATH, 2)
    with open(SCHEMA_PATH, "r", encoding="utf-8") as fh:
        return json.load(fh)


def schema_cross_check(schema: dict) -> list:
    """The JSON Schema file and this mapper must not drift apart.

    There is no stdlib JSON Schema validator and this repo takes no dependencies, so
    `validate` enforces the invariants directly AND asserts that the published schema's
    enums/required-keys are exactly the ones this mapper implements. A drift is a LOUD
    failure, not a warning — the schema file is what an external adapter (id:90f2) reads.
    """
    errs = []
    item = schema.get("$defs", {}).get("item", {})
    props = item.get("properties", {})

    def check_enum(prop, expected, label):
        got = props.get(prop, {}).get("enum")
        if got is None and "null" in str(props.get(prop, {})):
            got = props.get(prop, {}).get("anyOf", [{}])[0].get("enum")
        if sorted(got or []) != sorted(expected):
            errs.append("schema/mapper enum drift for item.%s (%s): schema=%r mapper=%r"
                        % (prop, label, got, expected))

    check_enum("todo_status", STATUS_ENUM, "STATUS_ENUM")
    check_enum("roadmap_status", STATUS_ENUM, "STATUS_ENUM")
    check_enum("review_status", STATUS_ENUM, "STATUS_ENUM")
    check_enum("derived_status", DERIVED_STATUS_ENUM, "DERIVED_STATUS_ENUM")
    check_enum("kind", KIND_ENUM, "KIND_ENUM")

    required = sorted(item.get("required", []))
    expected_required = sorted([
        "uid", "repo", "id", "identity", "kind", "title",
        "todo_status", "roadmap_status", "review_status", "drift", "derived_status",
        "labels", "blocked_by", "links", "sources",
    ])
    if required != expected_required:
        errs.append("schema/mapper required-key drift for item: schema=%r mapper=%r"
                    % (required, expected_required))

    if schema.get("properties", {}).get("schema_version", {}).get("const") != SCHEMA_VERSION:
        errs.append("schema_version drift: schema=%r mapper=%r"
                    % (schema.get("properties", {}).get("schema_version", {}).get("const"),
                       SCHEMA_VERSION))

    errs.extend(repo_cross_check(schema))
    errs.extend(version_copy_check())
    return errs


def repo_cross_check(schema: dict) -> list:
    """`$defs/repo` half of the cross-check (id:8c7f).

    Until now this function read ONLY `$defs.item`, so every property id:c17d and id:90f2
    added to the repo entity had ZERO drift protection — which is how `verdict`'s value
    space could be replaced wholesale under an unchanged `schema_version`, and how
    `head_sha` could become load-bearing in tracker/fleet-state.py while being undeclared
    in the schema.
    """
    errs = []
    repo = schema.get("$defs", {}).get("repo", {})
    props = repo.get("properties", {})

    def enum_of(prop):
        spec = props.get(prop, {})
        if "enum" in spec:
            return spec["enum"]
        for branch in spec.get("anyOf", []):
            if "enum" in branch:
                return branch["enum"]
        return None

    got = enum_of("verdict")
    if sorted(got or []) != sorted(VERDICT_ENUM):
        errs.append("schema/mapper enum drift for repo.verdict (VERDICT_ENUM): "
                    "schema=%r mapper=%r" % (got, VERDICT_ENUM))
    got = enum_of("board_column")
    if sorted(got or []) != sorted(BOARD_COLUMN_ENUM):
        errs.append("schema/mapper enum drift for repo.board_column (BOARD_COLUMN_ENUM): "
                    "schema=%r mapper=%r" % (got, BOARD_COLUMN_ENUM))

    required = sorted(repo.get("required", []))
    if required != sorted(REPO_REQUIRED):
        errs.append("schema/mapper required-key drift for repo: schema=%r mapper=%r"
                    % (required, sorted(REPO_REQUIRED)))
    declared = sorted(props)
    if declared != sorted(REPO_PROPERTIES):
        errs.append("schema/mapper property drift for repo: schema=%r mapper=%r"
                    % (declared, sorted(REPO_PROPERTIES)))
    return errs


def version_copy_check(root: str = None) -> list:
    """No file may re-introduce a hardcoded copy of the version constant (id:8c7f).

    The constant used to exist as FOUR uncross-checked copies (this file, the JSON
    Schema, repo-entity.py, adapters/adapter_common.py) plus a scrape in fleet-import.sh.
    Two remain by necessity — this file's literal and the schema's `const`, which
    `schema_cross_check()` pins to each other — and the rest derive. This check makes the
    collapse enforced rather than merely intended: any line that mentions a schema version
    AND carries a literal `X.Y.Z` is required to name the current one, so re-hardcoding a
    stale copy is caught the next time `validate` runs.
    """
    errs = []
    base = root or os.path.dirname(HERE)
    for rel in VERSION_DERIVED_FILES:
        path = os.path.join(base, rel)
        if not os.path.exists(path):
            continue
        with open(path, "r", encoding="utf-8") as fh:
            for n, line in enumerate(fh, start=1):
                if not RE_VERSION_CONTEXT.search(line):
                    continue
                for lit in RE_VERSION_LITERAL.findall(line):
                    if lit != SCHEMA_VERSION:
                        errs.append(
                            "hardcoded schema_version copy in %s:%d — %r != the single "
                            "source %r; derive it from the JSON Schema's const instead of "
                            "restating it (id:8c7f)" % (rel, n, lit, SCHEMA_VERSION))
    return errs


def validate_repos(doc: dict) -> list:
    """The `repos[]` half of `validate` (id:8c7f).

    `validate` checked `items[]` exhaustively and did not look at `repos[]` at all — the
    gap SCHEMA.md 7 named and left "to that file's owner". It is folded in here because
    the 1.1.0 `verdict` enum is worthless as documentation alone: nothing in this repo
    runs a JSON Schema validator (stdlib only, no deps), so an `enum` keyword catches
    exactly nothing until a check reads it. tracker/repo-entity.py keeps its own
    `validate-repos` for the verdict-to-column invariant; this covers the value spaces.
    """
    errs = []
    seen = set()
    for r in doc.get("repos", []):
        name = r.get("repo") or "<unnamed>"
        for k in REPO_REQUIRED:
            if k not in r:
                errs.append("repo %r: missing required key %r" % (name, k))
        if name in seen:
            errs.append("repo %r appears twice — the repo name is half the composite "
                        "(repo, id) key and must be unique" % name)
        seen.add(name)

        v = r.get("verdict")
        if v is not None and v not in VERDICT_ENUM:
            if v in RETIRED_VERDICTS:
                errs.append("repo %r: verdict %r was RETIRED from the verdict value space "
                            "— it is a `board_column` value now, not a verdict (this is the "
                            "schema_version 1.0.0 -> %s change; a 1.0.0-era document must "
                            "be re-derived, never re-labelled)" % (name, v, SCHEMA_VERSION))
            else:
                errs.append("repo %r: verdict %r not in %r" % (name, v, VERDICT_ENUM))
        col = r.get("board_column")
        if col not in (None, "") and col not in BOARD_COLUMN_ENUM:
            errs.append("repo %r: board_column %r not in %r" % (name, col, BOARD_COLUMN_ENUM))
    return errs


def parent_plugin_family(repos):
    """Return the PARENT repo name if `repos` is a `<parent>` / `<parent>-<suffix>`
    family (e.g. `zkm` + `zkm-whatsapp`), else None.

    This is a GUARD, never the driver (id:9fa2). Repo-name shape alone is not sound
    evidence of a deliberate mirror: `zkm` / `zkm-notmuch` share the shape and their
    `df4e` collision is an ordinary birthday collision, while `zkm` / `zkm-whatsapp`
    carry BOTH deliberate mirrors and two tokens the owner ruled must be re-minted
    (5e19, cfd1, routed:4ede). So the shape can only CONFIRM a declared mirror; it
    can never manufacture one.

    NOTE it is satisfied by any SUPERSET of a family — `{zkm, zkm-whatsapp,
    zkm-notmuch}` passes just as `{zkm, zkm-whatsapp}` does. That is why it is not
    sufficient on its own and `mirror_refusal()` requires PAIR EQUALITY first.
    """
    for cand in repos:
        if all(r == cand or r.startswith(cand + "-") for r in repos):
            return cand
    return None


def mirror_refusal(tok, repos, mirror_tokens):
    """Return None if the declared mirror for `tok` holds over the observed `repos`,
    else the WARN text explaining why the declaration is REFUSED (id:9fa2).

    Two independent conditions, checked in this order because they are different
    findings and the reader must be able to tell them apart:

      1. PAIR EQUALITY. The declared repo set must EQUAL the set that actually carries
         the token. A superset means some further repo minted the same 4-hex token
         independently — a genuine birthday collision *inside* the family, which is
         precisely what class A exists to catch. Honouring the declaration there would
         re-open the hole one level up: the growth would be in the token's REPO SET
         instead of in the token list. (Owner's narrowing ruling, 2026-09-01.)
      2. FAMILY SHAPE. The declared repos must still be a `<parent>`/`<parent>-<suffix>`
         family — the original guard, unchanged: shape can refuse a claim, never
         manufacture one.
    """
    declared = mirror_tokens[tok]
    observed = frozenset(repos)
    if declared != observed:
        extra = sorted(observed - declared)
        absent = sorted(declared - observed)
        detail = []
        if extra:
            detail.append("repos carrying it but NOT declared: %s" % extra)
        if absent:
            detail.append("declared but not carrying it here: %s" % absent)
        return ("parent/plugin MIRROR declaration REFUSED for %r: the declared pair %s "
                "does not equal the repos that actually carry the token, %s (%s). A "
                "mirror is scoped to its EXACT pair, so a declared token appearing in a "
                "further repo is a genuine collision inside the family, not part of the "
                "mirror — it is NOT an undeclared homonym, and it is NOT resolved by "
                "adding the token to the allow-list. Either re-mint the extra repo's id, "
                "or widen the declaration deliberately. The token is treated as an "
                "ordinary class-A homonym for now"
                % (tok, sorted(declared), sorted(observed), "; ".join(detail)))
    if not parent_plugin_family(repos):
        return ("parent/plugin MIRROR declaration REFUSED for %r: repos %s "
                "are not a <parent>/<parent>-<suffix> family — the token is "
                "treated as an ordinary class-A homonym" % (tok, repos))
    return None


def validate_doc(doc: dict, allowed_homonyms=frozenset(), mirror_tokens=None) -> tuple:
    """Return (errors, warnings). Errors are fatal (exit 3).

    `mirror_tokens` is the parent/plugin MIRROR map `{token: frozenset(repos)}`
    (id:9fa2, owner-ratified 2026-09-01: "one recorded convention, no per-token edges",
    NARROWED the same day from family-scoped to REPO-PAIR-scoped). A declared token is
    a deliberate same-item mirror — downgraded to a COUNTED warning — only when the
    declared repo set EQUALS the repos that actually carry it AND those repos form a
    `<parent>`/`<parent>-<suffix>` family. Any other outcome has its claim REFUSED,
    loudly and with the reason (`mirror_refusal()`), and stays fatal. Class B is
    unaffected — a mirror never resolves an ambiguous edge.

    `allowed_homonyms` is an explicit ALLOW-LIST of adjudicated bare tokens (id:ca24,
    owner-decided 2026-08-10; supersedes the blanket boolean shipped by id:2bb1). A
    LISTED class-A homonym is downgraded to a warning; an UNLISTED one is still fatal,
    so the recurring fleet import (id:94ce) cannot switch class A off wholesale and the
    ratified "cross-repo 4-hex collisions fail loudly at import" stays operative for
    every token a human has not yet adjudicated. Class B is never downgradable.
    """
    mirror_tokens = dict(mirror_tokens or {})
    errs = []
    warns = []

    if doc.get("schema_version") != SCHEMA_VERSION:
        errs.append("schema_version %r != %r" % (doc.get("schema_version"), SCHEMA_VERSION))

    errs.extend(validate_repos(doc))

    items = doc.get("items", [])
    by_uid = {}
    by_bare_id = {}

    for it in items:
        uid = it.get("uid")
        if uid in by_uid:
            errs.append("duplicate uid %s — the composite (repo,id) key is not unique; "
                        "an id was reused inside one repo" % uid)
        by_uid[uid] = it

        repo = it.get("repo") or ""
        if not isinstance(uid, str) or not uid.startswith(repo + "/"):
            errs.append("uid %r is not '<repo>/<key>' for repo=%r" % (uid, repo))
        else:
            key = uid.split("/", 1)[1]
            if it.get("id") is not None and key != it["id"]:
                errs.append("uid %r key does not equal id %r (composite (repo,id) key broken)"
                            % (uid, it["id"]))
            if it.get("id") is None and not key.startswith("~"):
                errs.append("uid %r has no id but its key is not a synthetic '~' key" % uid)

        for f in ("todo_status", "roadmap_status", "review_status"):
            if it.get(f) not in STATUS_ENUM:
                errs.append("%s: %s=%r not in %r" % (uid, f, it.get(f), STATUS_ENUM))
        if it.get("derived_status") not in DERIVED_STATUS_ENUM:
            errs.append("%s: derived_status=%r not in %r" % (uid, it.get("derived_status"), DERIVED_STATUS_ENUM))
        if it.get("kind") not in KIND_ENUM:
            errs.append("%s: kind=%r not in %r" % (uid, it.get("kind"), KIND_ENUM))
        if it.get("assignee") is not None and it.get("assignee") not in ASSIGNEE_ENUM:
            errs.append("%s: assignee=%r not in %r" % (uid, it.get("assignee"), ASSIGNEE_ENUM))

        # The defining invariant of this schema: drift is REPRESENTED, never collapsed.
        expect_drift = (
            it.get("todo_status") != "absent"
            and it.get("roadmap_status") != "absent"
            and it.get("todo_status") != it.get("roadmap_status")
        )
        if bool(it.get("drift")) != expect_drift:
            errs.append("%s: drift=%r contradicts todo_status=%r/roadmap_status=%r — "
                        "per-view status must never be collapsed"
                        % (uid, it.get("drift"), it.get("todo_status"), it.get("roadmap_status")))
        if expect_drift and it.get("derived_status") == "done":
            errs.append("%s: derived_status=done while the two views disagree — an OPEN "
                        "view must always beat a DONE view" % uid)

        # `derived_status` is documented (SCHEMA.md + the JSON schema) as DERIVED and
        # never authoritative. ENFORCE that rather than merely document it: re-derive it
        # and fail loudly on any mismatch. Without this, a hand-edited or adapter
        # round-tripped document can carry a derived_status that contradicts its per-view
        # fields and still validate OK — which is how the field would quietly become THE
        # status downstream (id:90f2), re-laundering the very drift meeting 2026-08-10
        # finding 5 forced the schema to represent.
        if all(it.get(f) in STATUS_ENUM for f in
               ("todo_status", "roadmap_status", "review_status")) and it.get("kind") in KIND_ENUM:
            expect_derived = derived_status(it)
            if it.get("derived_status") != expect_derived:
                errs.append("%s: derived_status=%r is not the DERIVED value %r for "
                            "todo=%r/roadmap=%r/review=%r (kind=%r) — derived_status is "
                            "never authoritative and must be recomputable"
                            % (uid, it.get("derived_status"), expect_derived,
                               it.get("todo_status"), it.get("roadmap_status"),
                               it.get("review_status"), it.get("kind")))

        if it.get("id"):
            by_bare_id.setdefault(it["id"], []).append(uid)
            if it.get("identity") != "tracked":
                errs.append("%s: has an id but identity=%r" % (uid, it.get("identity")))
        elif it.get("identity") != "untracked":
            errs.append("%s: has no id but identity=%r" % (uid, it.get("identity")))

    # ---- cross-repo 4-hex id collisions (meeting D2 finding 6) ----------------
    # 4-hex ids are PER-REPO, never fleet-unique. Two classes:
    #   A (homonym)  — the same bare id in >=2 repos, with no cross-repo reference.
    #                  The composite key already disambiguates it, but it is LOUD by
    #                  default because the meeting ratified "cross-repo 4-hex
    #                  collisions fail loudly at import".
    #   B (ambiguous reference) — a cross-repo `routed:`/edge token that resolves to
    #                  >=2 repos. ALWAYS fatal; the allow-list never downgrades it.
    # The escape hatch is an explicit per-token ALLOW-LIST (--allow-homonym, id:ca24),
    # never a blanket boolean: adjudication is per token, so a NEW homonym is still loud.
    routed_tokens = set()
    for it in items:
        for ln in it.get("links", []):
            if ln.get("kind") == "routed" and ln.get("token"):
                routed_tokens.add(ln["token"])

    seen_homonyms = set()
    mirrors_recognised = []
    for tok, uids in sorted(by_bare_id.items()):
        repos = sorted({u.split("/", 1)[0] for u in uids})
        if len(repos) < 2:
            continue
        seen_homonyms.add(tok)
        if tok in routed_tokens:
            errs.append("cross-repo id collision (class B, AMBIGUOUS REFERENCE): bare "
                        "token %r exists in repos %s and is used as a cross-repo routed "
                        "edge — the edge cannot be resolved to one (repo,id)" % (tok, repos))
        elif tok in mirror_tokens and mirror_refusal(tok, repos, mirror_tokens) is None:
            # id:9fa2 — a DELIBERATE mirror of one item across a parent repo and its
            # plugin repo. Reported and COUNTED (see the summary warning below): an
            # invisible downgrade would hide real collisions inside a growing plugin
            # family, which is the whole reason class A is loud.
            mirrors_recognised.append(tok)
            warns.append("cross-repo id MIRROR (class A downgraded): %r in repos %s — "
                         "parent/plugin mirror convention (id:9fa2), declared pair %s; "
                         "parent %r"
                         % (tok, repos, sorted(mirror_tokens[tok]),
                            parent_plugin_family(repos)))
        elif tok in allowed_homonyms:
            warns.append("cross-repo id homonym (class A): %r in repos %s — composite "
                         "key disambiguates; ADJUDICATED via --allow-homonym %s"
                         % (tok, repos, tok))
        else:
            if tok in mirror_tokens:
                # The convention was CLAIMED but does not hold: either the declared pair
                # is not what the document shows (a THIRD repo minted the token — a
                # genuine collision inside the family, not part of the mirror), or the
                # declared repos are not a parent/plugin family at all. Refuse it loudly,
                # saying WHICH, and fall through to the normal class-A treatment.
                warns.append(mirror_refusal(tok, repos, mirror_tokens))
            errs.append("cross-repo id collision (class A, HOMONYM): bare token %r exists "
                        "in repos %s — adjudicate it explicitly with --allow-homonym %s "
                        "(per-token; there is no blanket downgrade)" % (tok, repos, tok))

    # A listed token that is NOT a homonym in this document is stale adjudication — say so,
    # so the allow-list cannot quietly accumulate tokens nobody has re-checked.
    for tok in sorted(set(allowed_homonyms) - seen_homonyms):
        warns.append("--allow-homonym %s is stale: %r is not a class-A cross-repo homonym "
                     "in this document" % (tok, tok))
    for tok in sorted(set(mirror_tokens) - seen_homonyms):
        warns.append("parent/plugin mirror %s is stale: %r is not a class-A cross-repo "
                     "homonym in this document (declared pair %s)"
                     % (tok, tok, sorted(mirror_tokens[tok])))

    # id:9fa2 — the recognised mirrors are COUNTED, always, so the convention can never
    # be a silent downgrade: a mirror set that starts growing is visible in every run.
    if mirrors_recognised:
        warns.append("parent/plugin mirror convention (id:9fa2): recognised %d mirror(s): %s"
                     % (len(mirrors_recognised), ", ".join(sorted(mirrors_recognised))))

    for it in items:
        for b in it.get("blocked_by", []):
            if b not in by_uid:
                warns.append("%s: blocked_by %s is dangling (unresolvable in this document)"
                             % (it["uid"], b))
        # id:8302 — warn on EVERY declared parent, not just the scalar first one, so a
        # dangling second/third parent isn't silently invisible to this check.
        for p in it.get("parents") or ([it["parent"]] if it.get("parent") else []):
            if p not in by_uid:
                warns.append("%s: parent %s is dangling" % (it["uid"], p))

    return errs, warns


def render_status(doc: dict) -> str:
    """Project every item back to its per-view checkbox states.

    This is the round-trip half of the id:2bb1 contract: markdown -> JSON -> the
    per-view checkbox states the markdown carried. Full prose re-rendering is
    deliberately NOT implemented — D1 ratified that markdown need not survive as an
    export, so the information the round-trip must preserve is the STATUS PAIR.
    """
    box = {"open": "[ ]", "done": "[x]", "absent": "-"}
    out = []
    for it in sorted(doc.get("items", []), key=lambda i: i["uid"]):
        out.append("%s\tTODO:%s\tROADMAP:%s\tREVIEW:%s\tdrift=%s\tderived=%s" % (
            it["uid"], box[it["todo_status"]], box[it["roadmap_status"]],
            box[it["review_status"]], "1" if it["drift"] else "0", it["derived_status"]))
    return "\n".join(out)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #


ALLOW_TOKEN_RE = re.compile(r"^[0-9a-f]{4}$")


def _collect_tokens(tokens, path, flag, what) -> frozenset:
    """Read a token set from a repeatable flag plus an optional one-per-line file.

    Every entry must be a literal 4-hex token. A malformed entry (a wildcard, `all`,
    a range) dies loudly rather than being ignored.
    """
    out = set(tokens or [])
    if path:
        try:
            with open(path, "r", encoding="utf-8") as fh:
                lines = fh.read().splitlines()
        except OSError as exc:
            die("%s-file: %s" % (flag, exc))
        for raw in lines:
            entry = raw.split("#", 1)[0].strip()
            if entry:
                out.add(entry)
    bad = sorted(t for t in out if not ALLOW_TOKEN_RE.match(t))
    if bad:
        die("%s takes literal 4-hex tokens, one per %s; rejected: %s "
            "(there is no blanket/wildcard downgrade)"
            % (flag, what, ", ".join(repr(b) for b in bad)))
    return frozenset(out)


def collect_allowed_homonyms(tokens, path) -> frozenset:
    """Build the adjudicated allow-list from --allow-homonym / --allow-homonym-file.

    The only way to accept a class-A homonym is to name it, one token at a time
    (id:ca24).
    """
    return _collect_tokens(tokens, path, "--allow-homonym", "adjudicated homonym")


MIRROR_REPO_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
MIRROR_FORM = "<4-hex token> <repo> <repo> [...]"


def collect_mirror_tokens(tokens, path) -> dict:
    """Build the parent/plugin MIRROR map from --mirror-token / --mirror-file (id:9fa2).

    Returns `{token: frozenset(repos)}`. A mirror is scoped to the EXACT repo pair it
    is declared against, NOT to the parent's whole plugin family (owner's narrowing
    ruling, 2026-09-01). Each declaration is therefore
        `1c7d zkm zkm-whatsapp`
    and `validate` requires SET EQUALITY between the declared repos and the repos that
    actually carry the token.

    A BARE token (no repos) is REJECTED, not defaulted to family scope. That spelling
    IS the defect this narrowing closes: `parent_plugin_family()` is satisfied by any
    SUPERSET, so a fresh birthday collision minted on a declared token in any sibling
    plugin (`zkm-ner`, `zkm-stt`, …) was silently absorbed into the mirror — the exact
    hazard id:9fa2 exists to prevent, displaced from the token list into the token's
    repo set. Accepting the old spelling would preserve that hole under a compatible
    surface; this file has exactly one real consumer (`tracker/fleet-import.sh`), so
    rejecting is cheap and loud. Compare `_collect_tokens`, which stays bare-token for
    `--allow-homonym`: an adjudicated homonym IS a claim about the token alone.

    The shipped record of the convention is `tracker/mirror-tokens.txt`.
    """
    decls = list(tokens or [])
    if path:
        try:
            with open(path, "r", encoding="utf-8") as fh:
                lines = fh.read().splitlines()
        except OSError as exc:
            die("--mirror-file: %s" % exc)
        for raw in lines:
            entry = raw.split("#", 1)[0].strip()
            if entry:
                decls.append(entry)

    out = {}
    for entry in decls:
        fields = [f for f in re.split(r"[\s,:]+", entry.strip()) if f]
        if not fields:
            continue
        tok, repos = fields[0], fields[1:]
        if not ALLOW_TOKEN_RE.match(tok):
            die("--mirror-token takes a literal 4-hex token; rejected %r in %r "
                "(required form: %s; there is no blanket/wildcard downgrade)"
                % (tok, entry, MIRROR_FORM))
        if len(repos) < 2:
            die("--mirror-token %s declares no repo PAIR: a mirror is scoped to the "
                "EXACT repos it spans, never to a parent's whole plugin family — a bare "
                "token would let a fresh collision in ANY sibling plugin be absorbed. "
                "Required form: %s (got %r)" % (tok, MIRROR_FORM, entry))
        bad = [r for r in repos if not MIRROR_REPO_RE.match(r)]
        if bad:
            die("--mirror-token %s: %s is not a literal repo name — a mirror declaration "
                "names its repos exactly; no wildcard, prefix or glob (required form: %s)"
                % (tok, ", ".join(repr(b) for b in bad), MIRROR_FORM))
        if len(set(repos)) != len(repos):
            die("--mirror-token %s repeats a repo: %r" % (tok, repos))
        declared = frozenset(repos)
        if tok in out and out[tok] != declared:
            die("--mirror-token %s is declared twice with different repo sets, %s and %s "
                "— one token cannot name two mirrors; the composite (repo,id) key would "
                "not tell them apart" % (tok, sorted(out[tok]), sorted(declared)))
        out[tok] = declared
    return out


def read_doc(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=CLI_SUMMARY)
    sub = ap.add_subparsers(dest="cmd", required=True)

    p_imp = sub.add_parser("import", help="markdown ledgers -> intermediate JSON (one repo)")
    p_imp.add_argument("repo")
    p_imp.add_argument("root")

    p_mrg = sub.add_parser("merge", help="merge per-repo documents into one fleet document")
    p_mrg.add_argument("docs", nargs="+")

    p_val = sub.add_parser("validate", help="invariants + schema cross-check")
    p_val.add_argument("doc")
    # id:ca24 — an explicit per-token ALLOW-LIST, NOT a boolean. The bare
    # `--allow-homonyms` of id:2bb1 is deliberately GONE (it is not a prefix of either
    # option below, so argparse rejects it): a blanket downgrade would let id:94ce's
    # recurring fleet import switch class A off wholesale, which is exactly the
    # laundering the ratified "fail loudly at import" forbids.
    p_val.add_argument("--allow-homonym", action="append", metavar="TOKEN", default=[],
                       help="adjudicate ONE class-A cross-repo id homonym (4-hex token); "
                            "repeatable. Unlisted homonyms stay FATAL; class-B ambiguous "
                            "references are never downgradable")
    p_val.add_argument("--allow-homonym-file", metavar="PATH",
                       help="file of adjudicated tokens, one per line ('#' comments and "
                            "blank lines ignored) — same semantics as --allow-homonym")
    # id:9fa2 — the parent/plugin MIRROR convention (owner-ratified 2026-09-01). A
    # SEPARATE surface from --allow-homonym on purpose: the allow-list asserts "these
    # are unrelated items whose composite key disambiguates them", which is the WRONG
    # claim for a deliberate mirror of the SAME item across a parent and its plugin.
    p_val.add_argument("--mirror-token", action="append", metavar="DECL", default=[],
                       help="record a parent/plugin MIRROR as '<4-hex token> <repo> "
                            "<repo>'; repeatable. A mirror is scoped to its EXACT repo "
                            "pair: it is downgraded to a COUNTED warning only when the "
                            "declared repos EQUAL the repos actually carrying the token "
                            "AND form a <parent>/<parent>-<suffix> family. A superset "
                            "(the token also minted in a third family repo) is a real "
                            "collision and stays FATAL. A BARE token is rejected")
    p_val.add_argument("--mirror-file", metavar="PATH",
                       help="file of mirror declarations, one '<token> <repo> <repo>' per "
                            "line ('#' comments and blank lines ignored) — the shipped "
                            "record is tracker/mirror-tokens.txt")

    p_ren = sub.add_parser("render-status", help="project items back to per-view checkbox states")
    p_ren.add_argument("doc")

    args = ap.parse_args(argv)

    if args.cmd == "import":
        if not os.path.isdir(args.root):
            die("not a directory: %s" % args.root)
        doc = import_repo(args.repo, args.root)
        print(json.dumps(doc, indent=2, ensure_ascii=False, sort_keys=True))
        counts = doc["unmapped_counts"]
        if counts:
            print("loud-lossy report for %s: %s" % (
                args.repo, ", ".join("%s=%d" % (k, v) for k, v in counts.items())), file=sys.stderr)
        return 0

    if args.cmd == "merge":
        print(json.dumps(merge_docs([read_doc(p) for p in args.docs]),
                         indent=2, ensure_ascii=False, sort_keys=True))
        return 0

    if args.cmd == "validate":
        doc = read_doc(args.doc)
        allowed = collect_allowed_homonyms(args.allow_homonym, args.allow_homonym_file)
        mirrors = collect_mirror_tokens(args.mirror_token, args.mirror_file)
        errs = schema_cross_check(load_schema())
        e2, warns = validate_doc(doc, allowed, mirrors)
        errs.extend(e2)
        for w in warns:
            print("WARN: %s" % w, file=sys.stderr)
        if errs:
            for e in errs:
                print("ERROR: %s" % e, file=sys.stderr)
            print("validate: %d error(s), %d warning(s)" % (len(errs), len(warns)), file=sys.stderr)
            return 3
        print("validate: OK (%d items, %d repos, %d warning(s))"
              % (len(doc.get("items", [])), len(doc.get("repos", [])), len(warns)))
        return 0

    if args.cmd == "render-status":
        print(render_status(read_doc(args.doc)))
        return 0

    return 2


if __name__ == "__main__":
    sys.exit(main())
