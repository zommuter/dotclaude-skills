#!/usr/bin/env python3
"""tracker/derived-index.py -- the DERIVED-INDEX arm of the tracker pilot (TODO id:dcf3).

WHAT THIS IS
------------
A third, server-less pilot arm: cartulary's ratified design (text-is-truth plus a
DERIVED index; its D2 and A14) made runnable and measurable, so it can be compared
against Vikunja and Plane on the same evidence rather than sitting in the pilot as an
implicit "do nothing" option.

It is field-comparable BY CONSTRUCTION: it consumes exactly the `id:2bb1` intermediate
JSON document that the Vikunja and Plane adapters consume (`tracker/ledger-map.py
import` + `merge`), so a query answered here and a board built there are answering from
byte-identical input. It emits NOTHING to any tracker and writes NO file: like
`relay/scripts/control-board.sh` it is stdout-only (the pilot's standing rule is that no
relay script writes to a tracker).

Do not read this file as a ratified arm. The pre-registration amendment that would admit
it is a PROPOSAL awaiting owner ratification (TODO id:a08d); until that is ruled, this is
instrumentation, not a measured arm.

THE `id:cb00` CHILDREN-OF TRAP, HANDLED EXPLICITLY
--------------------------------------------------
`relay/scripts/lib-typed-edges.sh` parses only the forward `<!-- children:a,b -->` form
and is blind to `<!-- children-of:PARENT -->`, which outnumbers it 45 to 12 in this
repo's TODO.md. This script does NOT inherit that blindness and does not work around it
locally either: it never touches the bash library. `tracker/ledger-map.py` already reads
BOTH spellings (`RE_CHILDREN` / `RE_CHILDREN_OF`), so the intermediate document sees the
79% of edges the bash library cannot.

MEASURED CAVEAT, found while building this arm and filed as `id:7a9c`: reading both
spellings is not the same as NORMALISING them. In the emitted document each spelling
populates only ONE direction -- a downward `<!-- children:X -->` fills the parent's
`children` but leaves X's `parent` null, and an upward `<!-- children-of:P -->` fills the
child's `parent` but is absent from P's `children`. So neither field alone is the graph.
The `parent_child_edges()` helper below takes the UNION of both fields and is the
reference both-directions reader; `id:cb00` should converge the bash library onto that
edge set, and `id:7a9c` covers making the document itself symmetric. Nothing here edits
the shared mapper: the normalisation is derived, in memory, by the consumer.

Note the pilot queries in this file are GATE-only, and `gated-on:` is unaffected by
`id:cb00` in either library.

WHY IT IS NOT PART OF `control-board.sh`
----------------------------------------
`control-board.sh` is the pilot's pre-registered CONTROL arm (`id:8066`). A control that
grows the treatment's capabilities stops being a control. It is also REPO-grained over
`classify-repo.sh` verdicts; this is ITEM-grained over typed edges, and shares no data
source with it. Two arms, two files.

VIEWS
-----
  keystones   open human-assigned items ranked by how many OPEN items are transitively
              blocked on them (the `id:c3f6` fan-out ranking, over typed edges rather
              than the prose-grep that item explicitly forbids)
  stale-gates open items whose gate target is already DONE, or does not resolve at all --
              `id:c3f6`'s "(i) STALE gates ... unblock = re-check/re-tag, ~zero cost"
  child-edges the normalised parent/child edge set (union of both marker spellings), the
              runnable reference reader for `id:cb00` / `id:7a9c`

All take `--json`.

CROSS-REPO GATES, STATED NOT GUESSED
------------------------------------
`ledger-map.py` qualifies edge targets per repo (`repo/id`), which is correct for
identity but drops fleet-crossing gates, because 4-hex tokens are per-repo. This script
resolves a gate target in its OWN repo first; failing that, it accepts a fleet-unique
bare token and marks the edge `cross_repo`. An AMBIGUOUS bare token (two repos own it)
resolves to nothing and is reported as `unresolved` -- loudly, never silently dropped
(`id:4347`), and never guessed positionally.

Stdlib only (repo convention).
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict

OPEN_VIEWS = ("todo_status", "roadmap_status", "review_status")


def is_open(item: dict) -> bool:
    """OPEN in ANY view. Per-view statuses are never collapsed (2026-08-10 D2,
    finding 5); 'open anywhere' is a QUERY over the triple, not a new status field."""
    return any(item.get(v) == "open" for v in OPEN_VIEWS)


def load_doc(path: str) -> dict:
    fh = sys.stdin if path == "-" else open(path, encoding="utf-8")
    try:
        doc = json.load(fh)
    finally:
        if fh is not sys.stdin:
            fh.close()
    if not isinstance(doc, dict) or not isinstance(doc.get("items"), list):
        sys.exit("derived-index.py: not an intermediate document (no items[]): %s" % path)
    return doc


def build(doc: dict):
    """Return (by_uid, gate_edges, unresolved).

    gate_edges: uid -> list of (target_uid, cross_repo)
    unresolved: list of (uid, raw_target, reason)
    """
    by_uid = {}
    by_bare = defaultdict(list)
    for it in doc["items"]:
        uid = it.get("uid")
        if not uid:
            continue
        by_uid[uid] = it
        bare = uid.split("/", 1)[-1]
        by_bare[bare].append(uid)

    gate_edges = defaultdict(list)
    unresolved = []
    for it in doc["items"]:
        uid = it.get("uid")
        if not uid:
            continue
        repo = it.get("repo", "")
        for raw in it.get("blocked_by") or []:
            bare = raw.split("/", 1)[-1]
            same = "%s/%s" % (repo, bare)
            if same in by_uid:
                gate_edges[uid].append((same, False))
                continue
            cands = by_bare.get(bare, [])
            if len(cands) == 1:
                gate_edges[uid].append((cands[0], True))
            elif len(cands) > 1:
                unresolved.append((uid, raw, "ambiguous fleet-wide (%d owners: %s)"
                                   % (len(cands), ",".join(sorted(cands)))))
            else:
                unresolved.append((uid, raw, "no item owns this token"))
    return by_uid, gate_edges, unresolved


def reverse(gate_edges):
    """gate target -> set of uids blocked directly on it."""
    rev = defaultdict(set)
    for child, targets in gate_edges.items():
        for tgt, _cross in targets:
            rev[tgt].add(child)
    return rev


def descendants(root, rev):
    seen, stack = set(), [root]
    while stack:
        for ch in rev.get(stack.pop(), ()):
            if ch not in seen:
                seen.add(ch)
                stack.append(ch)
    return seen


def parent_child_edges(by_uid):
    """The normalised parent -> child edge set: the UNION of both marker directions.

    `<!-- children:X -->` on the parent populates only `children`; `<!-- children-of:P -->`
    on the child populates only `parent`. Either field read alone is a partial graph
    (`id:7a9c`). This union is the reference reader `id:cb00` should converge onto.
    Each edge carries how it was declared, so a one-sided edge stays visible as one.
    """
    seen = {}
    for uid, it in by_uid.items():
        p = it.get("parent")
        if p:
            seen.setdefault((p, uid), set()).add("upward")
        for c in it.get("children") or []:
            seen.setdefault((uid, c), set()).add("downward")
    return [{"parent": p, "child": c, "declared": sorted(d)}
            for (p, c), d in sorted(seen.items())]


def view_child_edges(by_uid, args):
    rows = parent_child_edges(by_uid)
    if args.assignee:
        rows = [r for r in rows
                if by_uid.get(r["child"], {}).get("assignee") == args.assignee]
    return rows


def view_keystones(by_uid, gate_edges, args):
    rev = reverse(gate_edges)
    rows = []
    for uid, it in by_uid.items():
        if not is_open(it):
            continue
        if args.assignee and it.get("assignee") != args.assignee:
            continue
        desc = descendants(uid, rev)
        open_desc = sorted(d for d in desc if is_open(by_uid.get(d, {})))
        if not open_desc:
            continue
        direct = sorted(d for d in rev.get(uid, ()) if is_open(by_uid.get(d, {})))
        rows.append({
            "uid": uid,
            "repo": it.get("repo", ""),
            "assignee": it.get("assignee"),
            "labels": [l for l in it.get("labels", []) if l.startswith(("lane:", "input:"))],
            "ungates_open": len(open_desc),
            "ungates_direct_open": len(direct),
            "ungates": open_desc,
            "title": it.get("title", ""),
        })
    rows.sort(key=lambda r: (-r["ungates_open"], -r["ungates_direct_open"], r["uid"]))
    return rows


def view_stale_gates(by_uid, gate_edges, unresolved, args):
    rows = []
    for uid, targets in gate_edges.items():
        it = by_uid[uid]
        if not is_open(it):
            continue
        if args.assignee and it.get("assignee") != args.assignee:
            continue
        for tgt, cross in targets:
            t = by_uid[tgt]
            if is_open(t):
                continue
            rows.append({
                "uid": uid, "repo": it.get("repo", ""), "title": it.get("title", ""),
                "gate": tgt, "gate_title": t.get("title", ""),
                "reason": "gate is closed in every view", "cross_repo": cross,
            })
    for uid, raw, why in unresolved:
        it = by_uid.get(uid, {})
        if not is_open(it):
            continue
        if args.assignee and it.get("assignee") != args.assignee:
            continue
        rows.append({
            "uid": uid, "repo": it.get("repo", ""), "title": it.get("title", ""),
            "gate": raw, "gate_title": "", "reason": why, "cross_repo": False,
        })
    rows.sort(key=lambda r: (r["uid"], str(r["gate"])))
    return rows


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="derived-index.py", description=__doc__.split("\n")[0])
    ap.add_argument("view", choices=["keystones", "stale-gates", "child-edges"])
    ap.add_argument("doc", help="intermediate JSON document, or - for stdin")
    ap.add_argument("--json", action="store_true", help="emit JSON rather than a table")
    ap.add_argument("--assignee", default=None,
                    help="restrict to one assignee (e.g. human) -- default: all")
    ap.add_argument("--limit", type=int, default=0, help="cap table rows (0 = no cap)")
    args = ap.parse_args(argv)

    doc = load_doc(args.doc)
    by_uid, gate_edges, unresolved = build(doc)

    if args.view == "keystones":
        rows = view_keystones(by_uid, gate_edges, args)
    elif args.view == "child-edges":
        rows = view_child_edges(by_uid, args)
    else:
        rows = view_stale_gates(by_uid, gate_edges, unresolved, args)

    # Unresolved edges are ALWAYS reported on stderr, in EVERY view and every output
    # mode (id:4347) -- a --json consumer that ignores the field still sees them.
    for u, t, w in unresolved:
        print("derived-index.py: UNRESOLVED gate %s -> %s: %s" % (u, t, w), file=sys.stderr)

    if args.json:
        print(json.dumps({"view": args.view, "rows": rows,
                          "unresolved_gates": [{"uid": u, "target": t, "reason": w}
                                               for u, t, w in unresolved]},
                         indent=2, sort_keys=True))
        return 0

    shown = rows[: args.limit] if args.limit else rows
    if args.view == "keystones":
        print("%4s %4s  %-24s %-10s %s" % ("ung", "dir", "uid", "assignee", "title"))
        for r in shown:
            print("%4d %4d  %-24s %-10s %s"
                  % (r["ungates_open"], r["ungates_direct_open"], r["uid"],
                     r["assignee"] or "-", r["title"][:88]))
    elif args.view == "child-edges":
        print("%-24s %-24s %s" % ("parent", "child", "declared"))
        for r in shown:
            print("%-24s %-24s %s" % (r["parent"], r["child"], ",".join(r["declared"])))
    else:
        print("%-24s %-24s %s" % ("uid", "gate", "reason"))
        for r in shown:
            print("%-24s %-24s %s%s" % (r["uid"], r["gate"], r["reason"],
                                        " [cross-repo]" if r["cross_repo"] else ""))
    print("\n%d row(s); %d item(s), %d open; %d gate edge(s), %d unresolved"
          % (len(rows), len(by_uid), sum(1 for i in by_uid.values() if is_open(i)),
             sum(len(v) for v in gate_edges.values()), len(unresolved)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
