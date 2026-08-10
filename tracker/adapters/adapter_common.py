#!/usr/bin/env python3
"""Shared contract layer for the tracker adapters (TODO id:90f2, children-of:2bb1).

Both adapters (`plane_adapter.py`, `vikunja_adapter.py`) are *thin*: all of the
intellectual content lives in `tracker/SCHEMA.md` + `tracker/ledger-map.py`.  What
lives HERE is only what the two adapters must agree on:

  1. the `schema_version` refusal gate (SCHEMA.md §5 — "an adapter must REFUSE a
     schema_version it does not know");
  2. the **per-view status carrier** — the id:857d binding gate;
  3. the canonical *item graph* the equivalence contract is stated over.

## The id:857d gate (owner-decided 2026-08-10, not advisory)

An adapter that reads only `derived_status` and renders one column is a CONTRACT
VIOLATION: it satisfies "never a collapsed single status" in the JSON while
defeating it in the product — cross-ledger drift becomes invisible exactly where
the owner would look for it.  So every adapter MUST carry, per item, into its
target:

  * `todo_status`, `roadmap_status`, `review_status` — all three, individually
    recoverable from the target's own payload; AND
  * a visible drift marker when `drift` is true.

`derived_status` MAY drive the board's status column; it must never be the only
thing carried.  `check_gate()` below is the executable form of that rule and is
asserted for BOTH adapters by
`tests/test_tracker_adapter_equivalence.sh`.

## Two independent carriers, cross-checked

The per-view triple is written into the target TWICE by design:

  * as labels — `view:todo=open` … — because labels are filterable/board-visible
    in both targets; and
  * as an anchored marker inside the item description —
    `[[ledger-views ...]]` — because labels are the surface a human is most
    likely to bulk-edit away.

The marker is **bracketed plain text, not an HTML comment**, on purpose: both
targets store descriptions as rich text through a sanitizer.  Vikunja v2.4.0 was
verified live to preserve an HTML comment verbatim, but Plane's editor could not
be verified this session (`id:02f7`), and a stripped comment would silently
delete the per-view carrier — exactly the failure id:857d exists to prevent.
Text content survives every sanitizer, and it is human-visible as a bonus.

Recovery reads BOTH and fails loudly if they disagree, so a half-applied edit
surfaces as an error instead of a quietly wrong board.
"""

from __future__ import annotations

import json
import re
import sys

SUPPORTED_SCHEMA_VERSIONS = ("1.0.0",)

VIEWS = ("todo", "roadmap", "review")
VIEW_STATES = ("open", "done", "absent")
DERIVED_STATES = ("backlog", "queued", "done", "needs-decision")

# The visible drift marker.  A label, so it is filterable on both boards.
DRIFT_LABEL = "drift:cross-ledger"

VIEWS_MARKER_RE = re.compile(r"\[\[ledger-views\s+(.*?)\s*\]\]", re.S)


class AdapterError(Exception):
    """Loud, non-swallowed adapter failure (id:4347 no-silent-swallow)."""


# --------------------------------------------------------------------------- #
# 1. schema_version refusal gate
# --------------------------------------------------------------------------- #

def load_document(path: str) -> dict:
    """Load an intermediate document, REFUSING an unknown schema_version."""
    with open(path, "r", encoding="utf-8") as fh:
        doc = json.load(fh)
    return check_schema_version(doc)


def check_schema_version(doc: dict) -> dict:
    got = doc.get("schema_version")
    if got not in SUPPORTED_SCHEMA_VERSIONS:
        raise AdapterError(
            "REFUSING document: schema_version %r is not one of %s. "
            "SCHEMA.md §5 — an adapter must refuse a version it does not know, "
            "because a stale adapter reading a changed document fails SILENTLY."
            % (got, ", ".join(SUPPORTED_SCHEMA_VERSIONS))
        )
    return doc


# --------------------------------------------------------------------------- #
# 2. the per-view carrier (id:857d)
# --------------------------------------------------------------------------- #

def view_labels(item: dict) -> list:
    """The per-view status labels — one per view, never collapsed."""
    out = []
    for view in VIEWS:
        state = item["%s_status" % view]
        if state not in VIEW_STATES:
            raise AdapterError("item %s: bad %s_status %r" % (item["uid"], view, state))
        out.append("view:%s=%s" % (view, state))
    return out


def derived_label(item: dict) -> str:
    state = item["derived_status"]
    if state not in DERIVED_STATES:
        raise AdapterError("item %s: bad derived_status %r" % (item["uid"], state))
    return "derived:%s" % state


def views_marker(item: dict) -> str:
    """Anchored, machine-readable per-view marker for the item description.

    Anchored comment form on purpose — same discipline as the ledger's own
    `<!-- id:XXXX -->` (bare substrings are not markers; id:4da4/0d58).
    """
    return (
        "[[ledger-views uid=%s todo=%s roadmap=%s review=%s drift=%s derived=%s]]"
        % (
            item["uid"],
            item["todo_status"],
            item["roadmap_status"],
            item["review_status"],
            "yes" if item["drift"] else "no",
            item["derived_status"],
        )
    )


def views_banner(item: dict) -> str:
    """Human-visible one-liner — the drift marker a person actually sees."""
    parts = " · ".join("%s=%s" % (v, item["%s_status" % v]) for v in VIEWS)
    banner = "views: %s | derived=%s" % (parts, item["derived_status"])
    if item["drift"]:
        banner += (
            " | ⚠ CROSS-LEDGER DRIFT: TODO says %s, ROADMAP says %s"
            % (item["todo_status"], item["roadmap_status"])
        )
    return banner


def parse_views_marker(text: str) -> dict:
    """Recover the per-view triple from a description.  Loud on absence."""
    m = VIEWS_MARKER_RE.search(text or "")
    if not m:
        raise AdapterError(
            "no [[ledger-views ...]] marker in the item description — "
            "the id:857d per-view carrier is missing"
        )
    fields = {}
    for tok in m.group(1).split():
        if "=" not in tok:
            raise AdapterError("malformed ledger-views token %r" % tok)
        k, v = tok.split("=", 1)
        fields[k] = v
    missing = [k for k in ("uid", "todo", "roadmap", "review", "drift", "derived") if k not in fields]
    if missing:
        raise AdapterError("ledger-views marker missing keys: %s" % ", ".join(missing))
    return fields


def recover_views(labels, description: str, uid: str) -> dict:
    """Recover per-view statuses from a target payload, cross-checking carriers.

    `labels` is the label set actually attached in the target; `description` the
    text actually written there.  Both carriers must agree — a disagreement means
    one of them was edited away and the board is silently wrong.
    """
    marker = parse_views_marker(description)
    if marker["uid"] != uid:
        raise AdapterError("ledger-views marker uid %s != item uid %s" % (marker["uid"], uid))

    labelset = set(labels)
    out = {}
    for view in VIEWS:
        from_label = [l for l in labelset if l.startswith("view:%s=" % view)]
        if len(from_label) != 1:
            raise AdapterError(
                "%s: expected exactly one view:%s= label, found %d — "
                "the id:857d per-view carrier is missing or ambiguous"
                % (uid, view, len(from_label))
            )
        state = from_label[0].split("=", 1)[1]
        if state != marker[view]:
            raise AdapterError(
                "%s: view:%s label says %s but the ledger-views marker says %s "
                "— the two carriers disagree" % (uid, view, state, marker[view])
            )
        out["%s_status" % view] = state

    drift = marker["drift"] == "yes"
    if drift != (DRIFT_LABEL in labelset):
        raise AdapterError(
            "%s: drift marker mismatch — marker says drift=%s but the %s label is %s"
            % (uid, marker["drift"], DRIFT_LABEL, "present" if DRIFT_LABEL in labelset else "absent")
        )
    out["drift"] = drift
    out["derived_status"] = marker["derived"]
    return out


def check_gate(doc: dict, graph: dict) -> list:
    """The executable id:857d gate.  Returns a list of violation strings.

    Asserts, for every item in the source document, that the graph an adapter
    RECOVERED FROM ITS OWN TARGET PAYLOAD still carries all three per-view
    statuses and the drift marker, unchanged.
    """
    violations = []
    nodes = {n["uid"]: n for n in graph["nodes"]}
    for item in doc["items"]:
        uid = item["uid"]
        node = nodes.get(uid)
        if node is None:
            violations.append("%s: item not present in the target graph" % uid)
            continue
        for view in VIEWS:
            key = "%s_status" % view
            if node.get(key) != item[key]:
                violations.append(
                    "%s: %s not carried into the target (source %s, target %r) — "
                    "collapsed-status contract violation (id:857d)"
                    % (uid, key, item[key], node.get(key))
                )
        if node.get("drift") != item["drift"]:
            violations.append(
                "%s: drift marker not carried (source %s, target %r)"
                % (uid, item["drift"], node.get("drift"))
            )
    return violations


# --------------------------------------------------------------------------- #
# 3. the canonical item graph — what "equivalent in both targets" MEANS
# --------------------------------------------------------------------------- #
#
# The contract on id:90f2 is: "the same fixture JSON yields equivalent item
# graphs — relations, labels, assignee, statuses — in both targets".  The graph
# is deliberately recovered from each adapter's OWN emitted target payloads, not
# re-derived from the source document; otherwise the comparison would be
# vacuous (both sides would just echo the input).

EDGE_KINDS = ("parent", "child", "blocked_by", "link")


def canonical_labels(labels) -> list:
    """Label set both targets must agree on, sorted and de-duplicated."""
    return sorted(set(labels))


def relation_edges(item: dict) -> list:
    """Target-neutral relation edges for one item, in canonical form."""
    edges = []
    if item.get("parent"):
        edges.append({"from": item["uid"], "kind": "parent", "to": item["parent"]})
    for child in item.get("children") or []:
        edges.append({"from": item["uid"], "kind": "child", "to": child})
    for blocker in item.get("blocked_by") or []:
        edges.append({"from": item["uid"], "kind": "blocked_by", "to": blocker})
    for link in item.get("links") or []:
        target = link.get("target_uid")
        edges.append(
            {
                "from": item["uid"],
                "kind": "link",
                "to": target if target else "?%s:%s" % (link["kind"], link.get("token") or link.get("path") or ""),
                "link_kind": link["kind"],
            }
        )
    return edges


def sort_graph(graph: dict) -> dict:
    graph["nodes"] = sorted(graph["nodes"], key=lambda n: n["uid"])
    graph["edges"] = sorted(graph["edges"], key=lambda e: json.dumps(e, sort_keys=True))
    return graph


def dump_json(obj) -> str:
    return json.dumps(obj, indent=2, sort_keys=True, ensure_ascii=False) + "\n"


def known_uids(doc: dict) -> set:
    return {i["uid"] for i in doc["items"]}


def warn(msg: str) -> None:
    sys.stderr.write("WARN: %s\n" % msg)
