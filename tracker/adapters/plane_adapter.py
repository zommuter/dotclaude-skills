#!/usr/bin/env python3
"""Plane adapter for the ledger intermediate document (TODO id:90f2).

    plan   <doc.json>              target-shaped operations, offline, deterministic
    graph  <doc.json>              the canonical item graph RECOVERED from those ops
    apply  <doc.json>              push the plan to a live Plane (network)
    verify <doc.json>              re-read the LIVE board and diff it against the plan

`plan` and `graph` never touch the network — they are what the hermetic test
suite exercises, and they are byte-for-byte equivalent (as a canonical item
graph) to the Vikunja adapter's.

## LIVE VERIFICATION STATUS — VERIFIED against Plane v2.6.3 (2026-08-11)

`id:02f7` cleared (the proxy binds after a host reboot), so `apply`/`verify` have
now issued real requests against a live self-hosted Plane v2.6.3 commercial
instance.  Three things previously recorded as *unknown* are now *measured*, and
two of them corrected what was written here:

  1. **Plane's public API v1 DOES expose an issue-relation endpoint** —
     `POST/GET /issues/<id>/relations/`, body `{"relation_type": …, "issues": […]}`,
     with `blocked_by` / `relates_to` / `blocking` / `duplicate` / `start_*` /
     `finish_*` all accepted (verified live).  The previous "no relation endpoint,
     WARN and keep it in the body" fallback was WRONG, and is gone: `blocked_by`
     and `link` edges are now written as real relations.  Plane materialises the
     inverse (`blocking`), so the live edge set is a SUPERSET of the planned one —
     same shape as Vikunja.
  2. **The `derived_status → workflow state` map is confirmed NON-injective** on a
     real project.  Plane's default state set is `Backlog / Todo / In Progress /
     Done / Cancelled` (groups `backlog/unstarted/started/completed/cancelled`) —
     there is no column for `needs-decision`, so it shares `Backlog`.  That is
     exactly why `derived:<state>` is ALSO a label: the column is lossy, the label
     is not, and `verify` recovers `derived_status` from the marker, never the
     column.
  3. **Plane's description sanitizer STRIPS HTML comments** (measured; see
     `adapter_common`'s module docstring).  The bracketed-plain-text carrier was
     the right call — an HTML-comment marker would have been deleted silently on
     every item.

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
| `blocked_by`                    | issue relation `blocked_by` *(verified live)*         |
| `links[]`                       | issue relation `relates_to` *(verified live)*         |

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
import time
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import adapter_common as C  # noqa: E402

TARGET = "plane"

# derived_status -> Plane workflow state name.  NOT injective (`needs-decision`
# and `backlog` share a column) — CONFIRMED live against a default Plane project,
# whose only states are Backlog / Todo / In Progress / Done / Cancelled.  This is
# precisely why `derived:<s>` is also a label: the board column is lossy, the
# label is not.
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

# Plane relation_type -> canonical kind, for reading the LIVE relations endpoint.
# Plane materialises the inverse of a directed relation, so `blocking` comes back
# on the other endpoint and is folded back to a `blocked_by` edge in the right
# direction rather than being reported as an unmapped kind.
LIVE_RELATION = {"blocked_by": "blocked_by", "relates_to": "link"}
LIVE_RELATION_INVERSE = {"blocking": "blocked_by"}


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
# apply / verify (networked — verified live, see the module docstring)
# --------------------------------------------------------------------------- #

class Plane:
    """Plane public API v1 client (verified against v2.6.3)."""

    #: requests/minute the client paces itself to; 0 disables pacing.
    DEFAULT_RATE_PER_MIN = 55          # a little under Plane's 60/min default
    DEFAULT_MAX_RETRIES = 5

    def __init__(self, base: str, api_key: str, workspace: str, project: str,
                 rate_per_min: float = DEFAULT_RATE_PER_MIN,
                 max_retries: int = DEFAULT_MAX_RETRIES):
        self.base = base.rstrip("/")
        self.api_key = api_key
        self.workspace = workspace
        self.project = project
        self.min_interval = 60.0 / rate_per_min if rate_per_min else 0.0
        self.max_retries = max_retries
        self._last_request = 0.0

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
            rate_per_min=float(os.environ.get("PLANE_RATE_PER_MIN") or cls.DEFAULT_RATE_PER_MIN),
        )

    def _url(self, path: str) -> str:
        return "%s/api/v1/workspaces/%s/projects/%s%s" % (
            self.base, self.workspace, self.project, path
        )

    def _pace(self) -> None:
        """Stay under Plane's per-key rate limit instead of provoking it.

        Plane throttles API keys at `API_KEY_RATE_LIMIT`, default **60/min** on a
        self-hosted instance (observed: a 19-item apply is ~65 requests and hit
        HTTP 429 mid-run).  A plain client-side spacer is the cheap fix; the 429
        retry below is the backstop for a shared limit we do not control.
        """
        if self.min_interval <= 0:
            return
        wait = self.min_interval - (time.monotonic() - self._last_request)
        if wait > 0:
            time.sleep(wait)

    def request(self, method: str, path: str, body=None):
        payload = json.dumps(body).encode() if body is not None else None
        attempt = 0
        while True:
            self._pace()
            req = urllib.request.Request(self._url(path), data=payload, method=method)
            req.add_header("Content-Type", "application/json")
            req.add_header("X-API-Key", self.api_key)
            try:
                with urllib.request.urlopen(req, timeout=30) as resp:
                    raw = resp.read().decode()
                self._last_request = time.monotonic()
                return json.loads(raw) if raw.strip() else None
            except urllib.error.HTTPError as exc:
                self._last_request = time.monotonic()
                detail = exc.read().decode()[:400]
                if exc.code == 429 and attempt < self.max_retries:
                    # honour an explicit Retry-After, INCLUDING "0" — `or` would
                    # discard a zero and sleep the full backoff for nothing.
                    retry_after = (exc.headers or {}).get("Retry-After")
                    delay = float(retry_after) if retry_after is not None else 5 * 2 ** attempt
                    attempt += 1
                    C.warn(
                        "Plane rate limit (HTTP 429) on %s %s — backing off %.0fs "
                        "(retry %d/%d); never silent" % (method, path, delay, attempt, self.max_retries)
                    )
                    time.sleep(delay)
                    continue
                raise C.AdapterError(  # loud, never swallowed
                    "%s %s -> HTTP %s: %s" % (method, path, exc.code, detail)
                )

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


def _issues_by_uid(client: "Plane") -> dict:
    """Every issue in the project that carries a [[ledger-views]] marker, by uid.

    The list endpoint returns `description_html`, so no per-issue GET is needed
    (verified live: 19/19 markers recovered straight off the list response).
    """
    by_uid = {}
    for issue in client.paged("/issues/"):
        try:
            marker = C.parse_views_marker(issue.get("description_html") or "")
        except C.AdapterError:
            continue
        by_uid[marker["uid"]] = issue
    return by_uid


def apply_plan(plan: dict, client: "Plane") -> dict:
    label_ids = {l["name"]: l["id"] for l in client.paged("/labels/")}
    state_ids = {s["name"]: s["id"] for s in client.paged("/states/")}
    by_uid = _issues_by_uid(client)

    stats = {"labels_created": 0, "items_created": 0, "items_updated": 0,
             "relations_set": 0, "relations_already_present": 0,
             "relations_skipped_dangling": 0}
    # issue id -> its live relations, fetched lazily so a re-apply can tell an
    # already-present relation from one it actually created (the idempotence
    # evidence the id:90f2 contract is checked with).
    rel_cache = {}

    def live_relations(issue_id: str) -> dict:
        if issue_id not in rel_cache:
            rel_cache[issue_id] = client.request("GET", "/issues/%s/relations/" % issue_id) or {}
        return rel_cache[issue_id]

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
            if mechanism in ("parent_field", "parent_field_inverse"):
                # `parent` edge: from=child, to=parent.  `child` edge: the reverse.
                if mechanism == "parent_field":
                    child, parent = by_uid[op["from_uid"]], by_uid[op["to_uid"]]
                else:
                    child, parent = by_uid[op["to_uid"]], by_uid[op["from_uid"]]
                if child.get("parent") == parent["id"]:
                    stats["relations_already_present"] += 1
                else:
                    child.update(
                        client.request("PATCH", "/issues/%s/" % child["id"],
                                       {"parent": parent["id"]}) or {}
                    )
                    stats["relations_set"] += 1
            else:
                # Plane's public API v1 DOES expose an issue-relation endpoint
                # (verified live on v2.6.3) — see the module docstring.  Writing a
                # real relation, not a body-only fallback.
                relation_type = op["payload"]["relation_type"]
                src, dst = by_uid[op["from_uid"]], by_uid[op["to_uid"]]
                if dst["id"] in (live_relations(src["id"]).get(relation_type) or []):
                    stats["relations_already_present"] += 1
                    continue
                client.request(
                    "POST", "/issues/%s/relations/" % src["id"],
                    {"relation_type": relation_type, "issues": [dst["id"]]},
                )
                rel_cache.pop(src["id"], None)
                rel_cache.pop(dst["id"], None)
                stats["relations_set"] += 1
    return stats


# --------------------------------------------------------------------------- #
# the LIVE graph — read back off the server, not off the plan
# --------------------------------------------------------------------------- #

def fetch_graph(client: "Plane") -> dict:
    """Recover the item graph FROM THE LIVE SERVER (not from the plan).

    This is the real id:857d evidence: it proves the per-view triple survived the
    round-trip through Plane's own storage and description SANITIZER — which is
    not a formality here, since that sanitizer is known to delete HTML comments.
    """
    label_names = {l["id"]: l["name"] for l in client.paged("/labels/")}
    state_names = {s["id"]: s["name"] for s in client.paged("/states/")}

    issues, id_to_uid = [], {}
    for issue in client.paged("/issues/"):
        try:
            marker = C.parse_views_marker(issue.get("description_html") or "")
        except C.AdapterError:
            continue
        id_to_uid[issue["id"]] = marker["uid"]
        issues.append(issue)

    nodes, edges = [], []
    for issue in issues:
        uid = id_to_uid[issue["id"]]
        labels = []
        for lid in issue.get("labels") or []:
            name = label_names.get(lid if isinstance(lid, str) else lid.get("id"))
            if name is None:
                raise C.AdapterError("%s: issue carries unknown label id %r" % (uid, lid))
            labels.append(name)
        views = C.recover_views(labels, issue.get("description_html") or "", uid)

        want_state = STATE_NAME[views["derived_status"]]
        got_state = state_names.get(issue.get("state"))
        if got_state != want_state:
            raise C.AdapterError(
                "%s: live workflow state %r contradicts derived_status=%s (expected %r)"
                % (uid, got_state, views["derived_status"], want_state)
            )

        assignee = None
        for label in labels:
            if label.startswith("assignee:"):
                assignee = label.split(":", 1)[1]
        node = {
            "uid": uid,
            "title": issue["name"],
            "assignee": assignee,
            "labels": C.canonical_labels(labels),
        }
        node.update(views)
        nodes.append(node)

        parent = issue.get("parent")
        if parent:
            target = id_to_uid.get(parent)
            if target is None:
                C.warn("%s: parent points outside this import" % uid)
            else:
                edges.append({"from": uid, "to": target, "kind": "parent", "dangling": False})
                edges.append({"from": target, "to": uid, "kind": "child", "dangling": False})

        live = client.request("GET", "/issues/%s/relations/" % issue["id"]) or {}
        for plane_type, others in live.items():
            kind = LIVE_RELATION.get(plane_type)
            inverse = LIVE_RELATION_INVERSE.get(plane_type)
            if kind is None and inverse is None:
                if others:
                    C.warn("%s: unmapped live relation_type %r" % (uid, plane_type))
                continue
            for other in others or []:
                target = id_to_uid.get(other)
                if target is None:
                    C.warn("%s: %s relation to an issue outside this import" % (uid, plane_type))
                    continue
                if kind is not None:
                    edges.append({"from": uid, "to": target, "kind": kind, "dangling": False})
                else:
                    edges.append({"from": target, "to": uid, "kind": inverse, "dangling": False})
    return C.sort_graph({"nodes": nodes, "edges": edges})


def verify_live(doc: dict, client: "Plane") -> dict:
    """Compare the live server's state against the plan. Non-zero exit on any gap."""
    plan = build_plan(doc)
    planned = extract_graph(plan)
    live = fetch_graph(client)

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

    # Plane materialises the inverse of every relation (`blocking` for `blocked_by`,
    # and `relates_to` both ways), so the live edge set is a SUPERSET; require every
    # planned non-dangling edge to be present.
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
            stats = apply_plan(build_plan(C.load_document(args[0])), Plane.from_env())
            sys.stdout.write(C.dump_json(stats))
        elif verb == "verify":
            report = verify_live(C.load_document(args[0]), Plane.from_env())
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
