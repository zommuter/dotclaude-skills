#!/usr/bin/env python3
"""Vikunja adapter for the ledger intermediate document (TODO id:90f2).

    plan   <doc.json>              target-shaped operations, offline, deterministic
    graph  <doc.json>              the canonical item graph RECOVERED from those ops
    apply  <doc.json>              push the plan to a live Vikunja (network)
    verify <doc.json>              re-read the LIVE board and diff it against the plan
                                   (network; exit 4 on any gap, including an
                                   id:857d per-view carrier that did not survive)

`plan` and `graph` never touch the network — they are what the hermetic test
suite exercises.  `apply` is the only networked verb and is never invoked by a
test.

Verified live against Vikunja **v2.4.0** at the pilot project on 2026-08-10.

## Target mapping

| intermediate                    | Vikunja                                            |
|---------------------------------|----------------------------------------------------|
| item                            | task in the pilot project                           |
| `uid`                           | `[[ledger-views uid=…]]` marker in the description  |
| `todo/roadmap/review_status`    | `view:<view>=<state>` labels **and** the marker     |
| `drift`                         | `drift:cross-ledger` label + a ⚠ banner line        |
| `derived_status`                | `done` boolean (board column) + `derived:<s>` label |
| `assignee` (a ROLE, not a user) | `assignee:<role>` label                             |
| `parent` / `children`           | `parenttask` / `subtask` task relations             |
| `blocked_by`                    | `blocked` task relations                            |
| `links[]`                       | `related` relation when resolvable, else a label    |

`assignee` is carried as a label, not a Vikunja assignee: the schema's assignee
is a ROLE (`executor`/`apex`/`human`/`daemon`), and inventing four user accounts
to hold four roles would be a fabricated mapping.  Both adapters do the same, so
the equivalence contract compares the role.

**`done` is set from `derived_status`, which is derived and never authoritative**
(SCHEMA.md §1.2).  It is a board convenience only — the per-view triple above is
what the id:857d gate requires and what `graph` recovers.
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import adapter_common as C  # noqa: E402

TARGET = "vikunja"

# canonical relation kind -> Vikunja relation_kind
RELATION_KIND = {
    "parent": "parenttask",
    "child": "subtask",
    "blocked_by": "blocked",
    "link": "related",
}
RELATION_KIND_INV = {v: k for k, v in RELATION_KIND.items()}

# Vikunja materialises the inverse of every relation it stores, so a live read
# sees kinds the plan never wrote.  `blocking` is the inverse of `blocked`; the
# other pair (`subtask`/`parenttask`) is already both-ways in RELATION_KIND.
INVERSE_KIND = {"blocking": "blocked_by"}


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


def description(item: dict) -> str:
    """Vikunja stores description as HTML."""
    body = item.get("body") or ""
    parts = ["<p>%s</p>" % _esc(C.views_banner(item))]
    if body:
        parts.append("<pre>%s</pre>" % _esc(body))
    for key in sorted((item.get("fields") or {})):
        parts.append("<p><strong>%s</strong>: %s</p>" % (_esc(key), _esc(item["fields"][key])))
    parts.append("<p>%s</p>" % _esc(C.views_marker(item)))
    return "".join(parts)


def _esc(text: str) -> str:
    return (
        str(text)
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
    )


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
                    "title": item["title"],
                    "description": description(item),
                    "done": item["derived_status"] == "done",
                },
            }
        )

    for item in sorted(doc["items"], key=lambda i: i["uid"]):
        for edge in C.relation_edges(item):
            dangling = edge["to"] not in uids
            op = {
                "op": "upsert_relation",
                "from_uid": edge["from"],
                "to_uid": edge["to"],
                "kind": edge["kind"],
                "dangling": dangling,
                "payload": {"relation_kind": RELATION_KIND[edge["kind"]]},
            }
            if "link_kind" in edge:
                op["link_kind"] = edge["link_kind"]
            ops.append(op)

    label_ops = [
        {"op": "upsert_label", "key": name, "payload": {"title": name}}
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
            uid = op["uid"]
            labels = op["labels"]
            payload = op["payload"]
            views = C.recover_views(labels, payload["description"], uid)

            # `done` is the Vikunja-native board column; cross-check it against
            # the recovered derived_status so a divergence is loud.
            want_done = views["derived_status"] == "done"
            if bool(payload["done"]) != want_done:
                raise C.AdapterError(
                    "%s: Vikunja `done`=%s contradicts derived_status=%s"
                    % (uid, payload["done"], views["derived_status"])
                )

            assignee = None
            for label in labels:
                if label.startswith("assignee:"):
                    assignee = label.split(":", 1)[1]
            node = {
                "uid": uid,
                "title": payload["title"],
                "assignee": assignee,
                "labels": C.canonical_labels(labels),
            }
            node.update(views)
            nodes.append(node)
        elif op["op"] == "upsert_relation":
            kind = RELATION_KIND_INV[op["payload"]["relation_kind"]]
            if kind != op["kind"]:
                raise C.AdapterError(
                    "relation kind mismatch: %s vs %s" % (kind, op["kind"])
                )
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
# apply (networked — never exercised by the test suite)
# --------------------------------------------------------------------------- #

class Vikunja:
    def __init__(self, base: str, token: str):
        self.base = base.rstrip("/")
        self.token = token

    @classmethod
    def from_env(cls) -> "Vikunja":
        base = os.environ.get("VIKUNJA_API_URL")
        if not base:
            raise C.AdapterError("VIKUNJA_API_URL is unset (inject it from your secrets file)")
        user = os.environ.get("VIKUNJA_USER")
        password = os.environ.get("VIKUNJA_PASSWORD")
        token = os.environ.get("VIKUNJA_TOKEN")
        client = cls(base, token or "")
        if user and password:
            # A scoped API token cannot reach /tasks/{id}/labels or
            # /tasks/{id}/relations (verified 2026-08-10: both 401 with a
            # projects/tasks/labels-scoped token), so prefer a JWT when
            # credentials are present.
            client.token = client.login(user, password)
        elif not token:
            raise C.AdapterError("neither VIKUNJA_USER/VIKUNJA_PASSWORD nor VIKUNJA_TOKEN is set")
        return client

    def login(self, user: str, password: str) -> str:
        data = self._raw("POST", "/login", {"username": user, "password": password}, auth=False)
        return data["token"]

    def _raw(self, method: str, path: str, body=None, auth: bool = True):
        url = self.base + path
        payload = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(url, data=payload, method=method)
        req.add_header("Content-Type", "application/json")
        if auth:
            req.add_header("Authorization", "Bearer %s" % self.token)
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                raw = resp.read().decode()
        except urllib.error.HTTPError as exc:  # loud, never swallowed
            raise C.AdapterError(
                "%s %s -> HTTP %s: %s" % (method, path, exc.code, exc.read().decode()[:400])
            )
        return json.loads(raw) if raw.strip() else None

    def get(self, path):
        return self._raw("GET", path)

    def put(self, path, body):
        return self._raw("PUT", path, body)

    def post(self, path, body):
        return self._raw("POST", path, body)


def _paged(client: "Vikunja", path: str) -> list:
    out, page = [], 1
    while True:
        sep = "&" if "?" in path else "?"
        chunk = client.get("%s%spage=%d" % (path, sep, page)) or []
        out.extend(chunk)
        if len(chunk) < 50:
            return out
        page += 1


def apply_plan(plan: dict, project_id: int, client: "Vikunja") -> dict:
    label_ids = {l["title"]: l["id"] for l in (_paged(client, "/labels") or [])}
    tasks = _paged(client, "/projects/%d/tasks" % project_id)

    by_uid = {}
    for task in tasks:
        try:
            marker = C.parse_views_marker(task.get("description") or "")
        except C.AdapterError:
            continue
        by_uid[marker["uid"]] = task

    stats = {"labels_created": 0, "items_created": 0, "items_updated": 0,
             "relations_set": 0, "relations_skipped_dangling": 0}

    for op in plan["ops"]:
        if op["op"] == "upsert_label":
            name = op["key"]
            if name not in label_ids:
                label_ids[name] = client.put("/labels", op["payload"])["id"]
                stats["labels_created"] += 1

        elif op["op"] == "upsert_item":
            uid, payload = op["uid"], op["payload"]
            existing = by_uid.get(uid)
            if existing is None:
                task = client.put("/projects/%d/tasks" % project_id, payload)
                stats["items_created"] += 1
            else:
                body = dict(existing)
                body.update(payload)
                task = client.post("/tasks/%d" % existing["id"], body)
                stats["items_updated"] += 1
            by_uid[uid] = task
            have = {l["title"] for l in (task.get("labels") or [])}
            for name in op["labels"]:
                if name not in have:
                    client.put("/tasks/%d/labels" % task["id"], {"label_id": label_ids[name]})

        elif op["op"] == "upsert_relation":
            if op["dangling"]:
                stats["relations_skipped_dangling"] += 1
                C.warn(
                    "dangling %s relation %s -> %s: target not in this document; "
                    "loud, never silently dropped (SCHEMA.md §2.7)"
                    % (op["kind"], op["from_uid"], op["to_uid"])
                )
                continue
            src, dst = by_uid.get(op["from_uid"]), by_uid.get(op["to_uid"])
            if not src or not dst:
                stats["relations_skipped_dangling"] += 1
                C.warn("relation %s -> %s: endpoint missing in target" % (op["from_uid"], op["to_uid"]))
                continue
            try:
                client.put(
                    "/tasks/%d/relations" % src["id"],
                    {"other_task_id": dst["id"], "relation_kind": op["payload"]["relation_kind"]},
                )
                stats["relations_set"] += 1
            except C.AdapterError as exc:
                if "already exist" in str(exc).lower():
                    stats["relations_set"] += 1
                else:
                    raise
    return stats


def fetch_graph(client: "Vikunja", project_id: int) -> dict:
    """Recover the item graph FROM THE LIVE SERVER (not from the plan).

    This is the real id:857d evidence: it proves the per-view triple survived the
    round-trip through the target's own storage and sanitizer, not merely that
    the adapter intended to write it.
    """
    nodes, edges, id_to_uid = [], [], {}
    tasks = []
    for stub in _paged(client, "/projects/%d/tasks" % project_id):
        task = client.get("/tasks/%d" % stub["id"])
        try:
            marker = C.parse_views_marker(task.get("description") or "")
        except C.AdapterError:
            continue
        id_to_uid[task["id"]] = marker["uid"]
        tasks.append(task)

    for task in tasks:
        uid = id_to_uid[task["id"]]
        labels = [l["title"] for l in (task.get("labels") or [])]
        views = C.recover_views(labels, task.get("description") or "", uid)
        want_done = views["derived_status"] == "done"
        if bool(task.get("done")) != want_done:
            raise C.AdapterError(
                "%s: live `done`=%s contradicts derived_status=%s"
                % (uid, task.get("done"), views["derived_status"])
            )
        assignee = None
        for label in labels:
            if label.startswith("assignee:"):
                assignee = label.split(":", 1)[1]
        node = {
            "uid": uid,
            "title": task["title"],
            "assignee": assignee,
            "labels": C.canonical_labels(labels),
        }
        node.update(views)
        nodes.append(node)

        for vk_kind, others in (task.get("related_tasks") or {}).items():
            kind = RELATION_KIND_INV.get(vk_kind)
            inverse = INVERSE_KIND.get(vk_kind)
            if kind is None and inverse is None:
                C.warn("%s: unmapped live relation_kind %r" % (uid, vk_kind))
                continue
            for other in others:
                target = id_to_uid.get(other["id"])
                if target is None:
                    C.warn("%s: %s relation to a task outside this import" % (uid, vk_kind))
                    continue
                if kind is not None:
                    edges.append({"from": uid, "to": target, "kind": kind, "dangling": False})
                else:
                    edges.append({"from": target, "to": uid, "kind": inverse, "dangling": False})
    return C.sort_graph({"nodes": nodes, "edges": edges})


def verify_live(doc: dict, client: "Vikunja", project_id: int) -> dict:
    """Compare the live server's state against the plan. Exit non-zero on any gap."""
    plan = build_plan(doc)
    planned = extract_graph(plan)
    live = fetch_graph(client, project_id)

    problems = []
    problems += ["gate: %s" % v for v in C.check_gate(doc, live)]

    planned_nodes = {n["uid"]: n for n in planned["nodes"]}
    live_nodes = {n["uid"]: n for n in live["nodes"]}
    for uid, want in planned_nodes.items():
        got = live_nodes.get(uid)
        if got is None:
            problems.append("missing on server: %s" % uid)
            continue
        for key in ("title", "assignee", "todo_status", "roadmap_status",
                    "review_status", "drift", "derived_status"):
            if got[key] != want[key]:
                problems.append("%s: %s live=%r planned=%r" % (uid, key, got[key], want[key]))
        missing = set(want["labels"]) - set(got["labels"])
        if missing:
            problems.append("%s: labels missing on server: %s" % (uid, sorted(missing)))

    # Vikunja materialises the inverse of every relation, so the live edge set is
    # a SUPERSET; require every planned non-dangling edge to be present.
    live_edges = {(e["from"], e["kind"], e["to"]) for e in live["edges"]}
    for edge in planned["edges"]:
        if edge["dangling"]:
            continue
        key = (edge["from"], edge["kind"], edge["to"])
        if key not in live_edges:
            problems.append("relation missing on server: %s" % (key,))

    return {
        "items_planned": len(planned_nodes),
        "items_live": len(live_nodes),
        "edges_planned_non_dangling": sum(1 for e in planned["edges"] if not e["dangling"]),
        "edges_live": len(live_edges),
        "problems": problems,
        "verdict": "PASS" if not problems else "FAIL",
    }


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
            doc = C.load_document(args[0])
            project = int(os.environ.get("VIKUNJA_PILOT_PROJECT_ID") or 0)
            if not project:
                raise C.AdapterError("VIKUNJA_PILOT_PROJECT_ID is unset")
            stats = apply_plan(build_plan(doc), project, Vikunja.from_env())
            sys.stdout.write(C.dump_json(stats))
        elif verb == "verify":
            doc = C.load_document(args[0])
            project = int(os.environ.get("VIKUNJA_PILOT_PROJECT_ID") or 0)
            if not project:
                raise C.AdapterError("VIKUNJA_PILOT_PROJECT_ID is unset")
            report = verify_live(doc, Vikunja.from_env(), project)
            sys.stdout.write(C.dump_json(report))
            return 0 if report["verdict"] == "PASS" else 4
        else:
            sys.stderr.write("unknown verb %r\n" % verb)
            return 2
    except C.AdapterError as exc:
        sys.stderr.write("ERROR: %s\n" % exc)
        return 3
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
