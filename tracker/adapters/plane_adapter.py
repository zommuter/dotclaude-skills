#!/usr/bin/env python3
"""Plane adapter for the ledger intermediate document (TODO id:90f2).

    plan   <doc.json>              target-shaped operations, offline, deterministic
    graph  <doc.json>              the canonical item graph RECOVERED from those ops
    apply  <doc.json>              push the plan to a live Plane (network)

`plan` and `graph` never touch the network — they are what the hermetic test
suite exercises, and they are byte-for-byte equivalent (as a canonical item
graph) to the Vikunja adapter's.

## ⚠ LIVE VERIFICATION STATUS — UNVERIFIED, BLOCKED ON id:02f7

`plan` and `graph` are fully tested against the fixtures.  **`apply` has never
been run against a live Plane instance.**  The pilot deployment does not serve:
21/22 containers run but nothing binds the proxy port, a host rootless-podman /
netavark nftables defect tracked as `id:02f7`.  Until that clears:

  * every request shape below is written from Plane's documented public API v1
    and is a BEST-EFFORT CONTRACT, not an observed one;
  * in particular the **issue-relation** endpoint (`blocked_by`, `relates_to`)
    is not part of Plane's documented public v1 surface at all — `apply` emits a
    loud WARN and records the edges in the issue description as a fallback, so a
    relation is never silently lost;
  * do not report a Plane end-to-end pass on the strength of a green test suite.
    The suite proves the *mapping*; it cannot prove the *transport*.

## Target mapping

| intermediate                    | Plane                                                |
|---------------------------------|------------------------------------------------------|
| item                            | issue in the pilot project                            |
| `uid`                           | `[[ledger-views uid=…]]` marker in `description_html` |
| `todo/roadmap/review_status`    | `view:<view>=<state>` labels **and** the marker       |
| `drift`                         | `drift:cross-ledger` label + a ⚠ banner line          |
| `derived_status`                | workflow state (board column) + `derived:<s>` label   |
| `assignee` (a ROLE, not a user) | `assignee:<role>` label                               |
| `parent`                        | native `parent` field (sub-issue)                     |
| `children`                      | the same field, written on the child                  |
| `blocked_by`                    | issue relation `blocked_by` *(unverified)*            |
| `links[]`                       | issue relation `relates_to` *(unverified)*            |

`assignee` is a ROLE (`executor`/`apex`/`human`/`daemon`), not a Plane member;
inventing four member accounts to hold four roles would be a fabricated mapping.
Both adapters carry it as a label, so the equivalence contract compares the role.

**The workflow state is set from `derived_status`, which is derived and never
authoritative** (SCHEMA.md §1.2).  It is a board convenience only — the per-view
triple is what the id:857d gate requires and what `graph` recovers.
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import adapter_common as C  # noqa: E402

TARGET = "plane"

# derived_status -> Plane workflow state name.  NOT injective (`needs-decision`
# and `backlog` share a column), which is precisely why `derived:<s>` is also a
# label: the board column is lossy, the label is not.
STATE_NAME = {
    "backlog": "Backlog",
    "queued": "Todo",
    "done": "Done",
    "needs-decision": "Backlog",
}

# canonical relation kind -> (mechanism, Plane relation_type)
RELATION = {
    "parent": ("parent_field", None),
    "child": ("parent_field_inverse", None),
    "blocked_by": ("issue_relation", "blocked_by"),
    "link": ("issue_relation", "relates_to"),
}
RELATION_INV = {v: k for k, v in RELATION.items()}


# --------------------------------------------------------------------------- #
# plan (offline, pure)
# --------------------------------------------------------------------------- #

def item_labels(item: dict) -> list:
    labels = list(item.get("labels") or [])
    labels += C.view_labels(item)
    labels.append(C.derived_label(item))
    if item["drift"] and C.DRIFT_LABEL not in labels:
        labels.append(C.DRIFT_LABEL)
    if item.get("assignee"):
        labels.append("assignee:%s" % item["assignee"])
    labels.append("repo:%s" % item["repo"])
    labels.append("kind:%s" % item["kind"])
    labels.append("identity:%s" % item["identity"])
    return C.canonical_labels(labels)


def _esc(text: str) -> str:
    return (
        str(text)
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
    )


def description_html(item: dict) -> str:
    body = item.get("body") or ""
    parts = ["<p>%s</p>" % _esc(C.views_banner(item))]
    if body:
        parts.append("<pre>%s</pre>" % _esc(body))
    for key in sorted((item.get("fields") or {})):
        parts.append("<p><strong>%s</strong>: %s</p>" % (_esc(key), _esc(item["fields"][key])))
    parts.append("<p>%s</p>" % _esc(C.views_marker(item)))
    return "".join(parts)


def build_plan(doc: dict) -> dict:
    C.check_schema_version(doc)
    uids = C.known_uids(doc)
    ops = []
    labels_used = set()

    for item in sorted(doc["items"], key=lambda i: i["uid"]):
        labels = item_labels(item)
        labels_used.update(labels)
        ops.append(
            {
                "op": "upsert_item",
                "uid": item["uid"],
                "labels": labels,
                "payload": {
                    "name": item["title"],
                    "description_html": description_html(item),
                    "state_name": STATE_NAME[item["derived_status"]],
                },
            }
        )

    for item in sorted(doc["items"], key=lambda i: i["uid"]):
        for edge in C.relation_edges(item):
            mechanism, relation_type = RELATION[edge["kind"]]
            op = {
                "op": "upsert_relation",
                "from_uid": edge["from"],
                "to_uid": edge["to"],
                "kind": edge["kind"],
                "dangling": edge["to"] not in uids,
                "payload": {"mechanism": mechanism, "relation_type": relation_type},
            }
            if "link_kind" in edge:
                op["link_kind"] = edge["link_kind"]
            ops.append(op)

    label_ops = [
        {"op": "upsert_label", "key": name, "payload": {"name": name}}
        for name in sorted(labels_used)
    ]
    return {
        "target": TARGET,
        "schema_version": doc["schema_version"],
        "ops": label_ops + ops,
    }


# --------------------------------------------------------------------------- #
# graph — recovered from the adapter's OWN target payloads
# --------------------------------------------------------------------------- #

def extract_graph(plan: dict) -> dict:
    if plan.get("target") != TARGET:
        raise C.AdapterError("plan is for target %r, not %r" % (plan.get("target"), TARGET))
    nodes, edges = [], []
    for op in plan["ops"]:
        if op["op"] == "upsert_item":
            uid, labels, payload = op["uid"], op["labels"], op["payload"]
            views = C.recover_views(labels, payload["description_html"], uid)

            want_state = STATE_NAME[views["derived_status"]]
            if payload["state_name"] != want_state:
                raise C.AdapterError(
                    "%s: Plane state %r contradicts derived_status=%s (expected %r)"
                    % (uid, payload["state_name"], views["derived_status"], want_state)
                )

            assignee = None
            for label in labels:
                if label.startswith("assignee:"):
                    assignee = label.split(":", 1)[1]
            node = {
                "uid": uid,
                "title": payload["name"],
                "assignee": assignee,
                "labels": C.canonical_labels(labels),
            }
            node.update(views)
            nodes.append(node)
        elif op["op"] == "upsert_relation":
            key = (op["payload"]["mechanism"], op["payload"]["relation_type"])
            kind = RELATION_INV[key]
            if kind != op["kind"]:
                raise C.AdapterError("relation kind mismatch: %s vs %s" % (kind, op["kind"]))
            edge = {
                "from": op["from_uid"],
                "to": op["to_uid"],
                "kind": kind,
                "dangling": op["dangling"],
            }
            if "link_kind" in op:
                edge["link_kind"] = op["link_kind"]
            edges.append(edge)
    return C.sort_graph({"nodes": nodes, "edges": edges})


# --------------------------------------------------------------------------- #
# apply (networked — UNVERIFIED, see the module docstring)
# --------------------------------------------------------------------------- #

class Plane:
    """Plane public API v1 client.  **Never executed against a live server yet.**"""

    def __init__(self, base: str, api_key: str, workspace: str, project: str):
        self.base = base.rstrip("/")
        self.api_key = api_key
        self.workspace = workspace
        self.project = project

    @classmethod
    def from_env(cls) -> "Plane":
        need = ("PLANE_API_URL", "PLANE_API_KEY", "PLANE_WORKSPACE_SLUG", "PLANE_PROJECT_ID")
        missing = [k for k in need if not os.environ.get(k)]
        if missing:
            raise C.AdapterError(
                "missing env: %s (inject from your secrets file; never hardcode a token)"
                % ", ".join(missing)
            )
        return cls(
            os.environ["PLANE_API_URL"],
            os.environ["PLANE_API_KEY"],
            os.environ["PLANE_WORKSPACE_SLUG"],
            os.environ["PLANE_PROJECT_ID"],
        )

    def _url(self, path: str) -> str:
        return "%s/api/v1/workspaces/%s/projects/%s%s" % (
            self.base, self.workspace, self.project, path
        )

    def request(self, method: str, path: str, body=None):
        payload = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(self._url(path), data=payload, method=method)
        req.add_header("Content-Type", "application/json")
        req.add_header("X-API-Key", self.api_key)
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                raw = resp.read().decode()
        except urllib.error.HTTPError as exc:  # loud, never swallowed
            raise C.AdapterError(
                "%s %s -> HTTP %s: %s" % (method, path, exc.code, exc.read().decode()[:400])
            )
        return json.loads(raw) if raw.strip() else None

    def paged(self, path: str) -> list:
        out, cursor = [], None
        while True:
            sep = "&" if "?" in path else "?"
            page = self.request("GET", path if cursor is None else "%s%scursor=%s" % (path, sep, cursor))
            if isinstance(page, list):
                return page
            out.extend(page.get("results") or [])
            cursor = page.get("next_cursor")
            if not page.get("next_page_results"):
                return out


def apply_plan(plan: dict, client: "Plane") -> dict:
    C.warn(
        "Plane `apply` has NEVER been run against a live instance (id:02f7 — the "
        "pilot proxy does not bind). Treat every result as unverified."
    )
    label_ids = {l["name"]: l["id"] for l in client.paged("/labels/")}
    state_ids = {s["name"]: s["id"] for s in client.paged("/states/")}

    by_uid = {}
    for issue in client.paged("/issues/"):
        try:
            marker = C.parse_views_marker(issue.get("description_html") or "")
        except C.AdapterError:
            continue
        by_uid[marker["uid"]] = issue

    stats = {"labels_created": 0, "items_created": 0, "items_updated": 0,
             "relations_set": 0, "relations_skipped_dangling": 0,
             "relations_unsupported": 0}

    for op in plan["ops"]:
        if op["op"] == "upsert_label":
            if op["key"] not in label_ids:
                label_ids[op["key"]] = client.request("POST", "/labels/", op["payload"])["id"]
                stats["labels_created"] += 1

        elif op["op"] == "upsert_item":
            uid, payload = op["uid"], op["payload"]
            state_name = payload["state_name"]
            if state_name not in state_ids:
                raise C.AdapterError(
                    "Plane project has no workflow state %r — create it, or the "
                    "board column mapping is a lie" % state_name
                )
            body = {
                "name": payload["name"],
                "description_html": payload["description_html"],
                "state": state_ids[state_name],
                "labels": [label_ids[n] for n in op["labels"]],
            }
            existing = by_uid.get(uid)
            if existing is None:
                by_uid[uid] = client.request("POST", "/issues/", body)
                stats["items_created"] += 1
            else:
                by_uid[uid] = client.request("PATCH", "/issues/%s/" % existing["id"], body)
                stats["items_updated"] += 1

        elif op["op"] == "upsert_relation":
            if op["dangling"] or op["from_uid"] not in by_uid or op["to_uid"] not in by_uid:
                stats["relations_skipped_dangling"] += 1
                C.warn(
                    "dangling %s relation %s -> %s: target not in this document; "
                    "loud, never silently dropped (SCHEMA.md §2.7)"
                    % (op["kind"], op["from_uid"], op["to_uid"])
                )
                continue
            mechanism = op["payload"]["mechanism"]
            if mechanism == "parent_field":
                client.request(
                    "PATCH", "/issues/%s/" % by_uid[op["from_uid"]]["id"],
                    {"parent": by_uid[op["to_uid"]]["id"]},
                )
                stats["relations_set"] += 1
            elif mechanism == "parent_field_inverse":
                client.request(
                    "PATCH", "/issues/%s/" % by_uid[op["to_uid"]]["id"],
                    {"parent": by_uid[op["from_uid"]]["id"]},
                )
                stats["relations_set"] += 1
            else:
                # Plane's public API v1 does not document an issue-relation
                # endpoint. Do NOT guess a URL against a live server: report it
                # loudly and leave the edge visible in the description instead.
                stats["relations_unsupported"] += 1
                C.warn(
                    "%s relation %s -> %s NOT written: Plane public API v1 exposes no "
                    "issue-relation endpoint. Edge is recorded in the issue body only."
                    % (op["kind"], op["from_uid"], op["to_uid"])
                )
    return stats


def main(argv=None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    if not argv or argv[0] in ("-h", "--help"):
        sys.stdout.write(__doc__)
        return 0
    verb, args = argv[0], argv[1:]
    try:
        if verb == "plan":
            sys.stdout.write(C.dump_json(build_plan(C.load_document(args[0]))))
        elif verb == "graph":
            sys.stdout.write(C.dump_json(extract_graph(build_plan(C.load_document(args[0])))))
        elif verb == "apply":
            stats = apply_plan(build_plan(C.load_document(args[0])), Plane.from_env())
            sys.stdout.write(C.dump_json(stats))
        else:
            sys.stderr.write("unknown verb %r\n" % verb)
            return 2
    except C.AdapterError as exc:
        sys.stderr.write("ERROR: %s\n" % exc)
        return 3
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
