#!/usr/bin/env bash
# (no `# roadmap:` header — this specs TODO id:90f2's Plane half, which has no
#  ROADMAP entry. Its failures therefore ALWAYS count.)
#
# Pins what the 2026-08-11 LIVE Plane run (v2.6.3, self-hosted) established, so the
# findings become mechanical checks instead of prose that rots:
#
#   1. `apply` -> `verify` round-trips through Plane's OWN transport semantics —
#      exercised here against an in-memory Plane double whose behaviour was
#      CALIBRATED against the live server (grouped relations dict, materialised
#      inverse relations, list-endpoint labels-as-ids, sanitizer).
#   2. The id:857d gate is NON-VACUOUS against a live-shaped board: killing either
#      carrier server-side (a `view:*=` label, or the `[[ledger-views]]` marker)
#      must be caught and NAMED, never silently tolerated.
#   3. The description marker must NOT be an HTML comment — measured live, Plane's
#      sanitizer DELETES HTML comments, which would silently destroy the per-view
#      carrier on every item.  This is the regression test for that.
#   4. Plane rate-limits API keys (60/min default, hit live) — a 429 is retried,
#      loudly, not surfaced as a lost write.
#   5. The `schema_version` gate refuses an unknown version while staying in step
#      with the mapper in the SAME checkout.
#
# HERMETIC: no test here touches the network. The Plane double is injected as the
# client, and the whole file runs with sockets disabled to prove it.
# fails-against: rev 064ae4424967 -- the tree as it stood immediately before the commit that
#   added this test, i.e. the pre-fix tracker/adapters/adapter_common.py, tracker/adapters/plane_adapter.py. Derived + verified by tests/verify-negative-cases.py.
# fails-against-rev: 064ae4424967 -- tracker/adapters/adapter_common.py tracker/adapters/plane_adapter.py
# fails-against-assertion: Plane live-contract checks failed

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AD="$ROOT/tracker/adapters"
FIX="$ROOT/tracker/fixtures/expected"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*"; exit 1; }

# --- the Plane double, shared by the checks below --------------------------------
cat > "$tmp/fake_plane.py" <<'PY'
"""In-memory Plane v2.6.3 double, calibrated against the live instance (2026-08-11).

Only the behaviours the adapter actually depends on, and each one OBSERVED rather
than assumed:

  * `GET /issues/` returns `labels` as a list of label **ids** (not objects), and
    includes `description_html` — so no per-issue GET is needed;
  * `GET /issues/<id>/relations/` returns a dict GROUPED BY relation type, with
    every type present (empty lists included);
  * a `blocked_by` write materialises the INVERSE `blocking` on the other issue,
    and `relates_to` materialises symmetrically;
  * `description_html` is passed through a sanitizer that DELETES HTML comments
    and wraps the body in a <div> — the single most important observed behaviour,
    because an HTML-comment carrier would vanish here.
"""
import re

SANITIZER_COMMENT_RE = re.compile(r"<!--.*?-->", re.S)

DEFAULT_STATES = [
    {"id": "st-backlog", "name": "Backlog", "group": "backlog"},
    {"id": "st-todo", "name": "Todo", "group": "unstarted"},
    {"id": "st-progress", "name": "In Progress", "group": "started"},
    {"id": "st-done", "name": "Done", "group": "completed"},
    {"id": "st-cancelled", "name": "Cancelled", "group": "cancelled"},
]

RELATION_TYPES = ("blocking", "blocked_by", "duplicate", "relates_to",
                  "start_after", "start_before", "finish_after", "finish_before")
INVERSE = {"blocked_by": "blocking", "blocking": "blocked_by"}
SYMMETRIC = ("relates_to", "duplicate")


def sanitize(html):
    """What Plane stores, given what you POSTed. Comments do NOT survive."""
    return "<div>%s</div>" % SANITIZER_COMMENT_RE.sub("", html or "")


class FakePlane:
    def __init__(self):
        self.labels = {}
        self.issues = {}
        self.relations = {}
        self.calls = []
        self._n = 0

    # -- the two methods the adapter calls -------------------------------------
    def paged(self, path):
        return self.request("GET", path)

    def request(self, method, path, body=None):
        self.calls.append((method, path.split("?")[0]))
        p = path.split("?")[0]
        if p == "/labels/" and method == "GET":
            return list(self.labels.values())
        if p == "/labels/" and method == "POST":
            self._n += 1
            lab = {"id": "lb-%d" % self._n, "name": body["name"]}
            self.labels[lab["id"]] = lab
            return lab
        if p == "/states/" and method == "GET":
            return list(DEFAULT_STATES)
        if p == "/issues/" and method == "GET":
            return [self._as_list_row(i) for i in self.issues.values()]
        if p == "/issues/" and method == "POST":
            self._n += 1
            iid = "is-%d" % self._n
            issue = {"id": iid, "name": body["name"],
                     "description_html": sanitize(body.get("description_html")),
                     "state": body.get("state"), "labels": list(body.get("labels") or []),
                     "parent": body.get("parent")}
            self.issues[iid] = issue
            self.relations[iid] = {}
            return self._as_list_row(issue)
        m = re.match(r"^/issues/([^/]+)/$", p)
        if m and method == "PATCH":
            issue = self.issues[m.group(1)]
            for k, v in body.items():
                issue[k] = sanitize(v) if k == "description_html" else v
            return self._as_list_row(issue)
        if m and method == "DELETE":
            self.issues.pop(m.group(1), None)
            return None
        m = re.match(r"^/issues/([^/]+)/relations/$", p)
        if m and method == "GET":
            got = self.relations.get(m.group(1), {})
            return {k: sorted(got.get(k, [])) for k in RELATION_TYPES}
        if m and method == "POST":
            src, rt = m.group(1), body["relation_type"]
            for dst in body["issues"]:
                self.relations.setdefault(src, {}).setdefault(rt, [])
                if dst not in self.relations[src][rt]:
                    self.relations[src][rt].append(dst)
                back = rt if rt in SYMMETRIC else INVERSE.get(rt)
                if back:
                    self.relations.setdefault(dst, {}).setdefault(back, [])
                    if src not in self.relations[dst][back]:
                        self.relations[dst][back].append(src)
            return []
        raise AssertionError("Plane double got an un-modelled request: %s %s" % (method, p))

    def _as_list_row(self, issue):
        row = dict(issue)
        row["labels"] = list(issue["labels"])          # ids, as the live list endpoint returns
        return row

    # -- helpers the tampering checks use --------------------------------------
    def find(self, uid):
        for issue in self.issues.values():
            if "uid=%s " % uid in (issue["description_html"] or ""):
                return issue
        raise AssertionError("no issue carrying uid %s" % uid)

    def label_id(self, name):
        for lid, lab in self.labels.items():
            if lab["name"] == name:
                return lid
        raise AssertionError("no label %r" % name)
PY

# --- everything below runs with sockets DISABLED ---------------------------------
python3 - "$AD" "$FIX" "$tmp" <<'PY' || fail "Plane live-contract checks failed"
import json, socket, sys

ad, fix, tmp = sys.argv[1], sys.argv[2], sys.argv[3]


class NoNet(socket.socket):
    def __init__(self, *a, **k):
        raise AssertionError("network access attempted — this suite must be hermetic")


socket.socket = NoNet
socket.create_connection = lambda *a, **k: (_ for _ in ()).throw(
    AssertionError("network access attempted — this suite must be hermetic"))

sys.path.insert(0, ad)
sys.path.insert(0, tmp)
import adapter_common as C
import plane_adapter as P
from fake_plane import FakePlane, sanitize

DOC = "%s/repo-alpha.json" % fix


def fresh():
    doc = C.load_document(DOC)
    board = FakePlane()
    stats = P.apply_plan(P.build_plan(doc), board)
    return doc, board, stats


# --- 1. apply is complete, then verify PASSes ------------------------------------
doc, board, stats = fresh()
assert stats["items_created"] == 19, stats
assert stats["labels_created"] == 39, stats
assert stats["relations_set"] == 3, stats
assert stats["relations_skipped_dangling"] == 2, stats

report = P.verify_live(doc, board)
assert report["verdict"] == "PASS", report
assert report["items_live"] == report["items_planned"] == 19, report
# Plane must never DROP a planned edge on round-trip (`edges_live` is deduped
# server-observed triples; `edges_planned_non_dangling` is the plan's own list).
# Pre-id:59c5 this was a strict SUPERSET, because the ledger stored a parent/child
# pair in only ONE direction and Plane's `parent` field implicitly supplied the
# other on read-back. id:59c5 mirrors both directions into the document itself,
# so the plan now already declares what Plane used to have to infer, and the two
# counts legitimately coincide for this fixture — the invariant that matters
# (no silent loss) is `>=`, not a stale `>` premised on the fixed asymmetry.
assert report["edges_live"] >= report["edges_planned_non_dangling"], report

# --- 2. apply is IDEMPOTENT -------------------------------------------------------
again = P.apply_plan(P.build_plan(doc), board)
assert again["items_created"] == 0, again
assert again["labels_created"] == 0, again
assert again["relations_set"] == 0, again
# 5 non-dangling ops now (id:59c5 mirrors both parent/child directions into the
# document, so the plan carries 2 extra redundant-but-idempotent parent/child
# ops beyond the 3 that ever actually write); all 5 read back as already-present.
assert again["relations_already_present"] == 5, again
assert P.verify_live(doc, board)["verdict"] == "PASS"

# --- 3. the id:857d gate is NON-VACUOUS on a live-shaped board --------------------
# 3a. a per-view LABEL deleted server-side must be caught, and NAMED.
doc, board, _ = fresh()
issue = board.find("repo-alpha/1111")
issue["labels"] = [l for l in issue["labels"]
                   if not board.labels[l]["name"].startswith("view:todo=")]
try:
    P.verify_live(doc, board)
except C.AdapterError as exc:
    assert "repo-alpha/1111" in str(exc) and "view:todo" in str(exc), exc
else:
    raise AssertionError("deleting a view:todo= label went UNDETECTED — gate is vacuous")

# 3b. the DESCRIPTION marker stripped server-side must be caught, and NAMED.
doc, board, _ = fresh()
issue = board.find("repo-alpha/3333")
issue["description_html"] = C.VIEWS_MARKER_RE.sub("(bulk-edited away)", issue["description_html"])
report = P.verify_live(doc, board)
assert report["verdict"] == "FAIL", report
assert any("repo-alpha/3333" in p for p in report["problems"]), report

# 3c. drift must be readable off the board in BOTH directions, and an item in
#     drift must NOT render as done.
doc, board, _ = fresh()
live = {n["uid"]: n for n in P.fetch_graph(board)["nodes"]}
a, b = live["repo-alpha/1111"], live["repo-alpha/2222"]
assert (a["todo_status"], a["roadmap_status"]) == ("open", "done"), a
assert (b["todo_status"], b["roadmap_status"]) == ("done", "open"), b
assert a["drift"] and b["drift"], (a, b)
assert C.DRIFT_LABEL in a["labels"] and C.DRIFT_LABEL in b["labels"], (a, b)
for n in live.values():
    assert not (n["drift"] and n["derived_status"] == "done"), n
    for v in ("todo", "roadmap", "review"):
        assert n["%s_status" % v] in C.VIEW_STATES, (n["uid"], v)

# 3d. a board whose workflow COLUMN contradicts the carried derived_status is loud.
doc, board, _ = fresh()
issue = board.find("repo-alpha/1111")
issue["state"] = "st-done"
try:
    P.fetch_graph(board)
except C.AdapterError as exc:
    assert "repo-alpha/1111" in str(exc) and "contradicts" in str(exc), exc
else:
    raise AssertionError("a workflow state contradicting derived_status went undetected")

# --- 4. relations: both kinds are WRITTEN, and read back in the right direction ---
# repo-alpha has no resolvable `link`, so the relates_to path is covered with a doc
# whose dangling link is retargeted at a real item (exactly what the live run did).
doc = C.load_document(DOC)
uids = [i["uid"] for i in doc["items"]]
retargeted = 0
for item in doc["items"]:
    for link in (item.get("links") or []):
        if not link.get("target_uid"):
            link["target_uid"] = next(u for u in uids if u != item["uid"])
            retargeted += 1
assert retargeted == 1, retargeted

board = FakePlane()
stats = P.apply_plan(P.build_plan(doc), board)
assert stats["relations_set"] == 4, stats            # 3 + the newly resolvable link
report = P.verify_live(doc, board)
assert report["verdict"] == "PASS", report

live_edges = {(e["from"], e["kind"], e["to"]) for e in P.fetch_graph(board)["edges"]}
assert ("repo-alpha/cccc", "link", "repo-alpha/1111") in live_edges, sorted(live_edges)
assert any(k == "blocked_by" for _, k, _ in live_edges), sorted(live_edges)

# The inverse Plane materialises (`blocking`) must fold back to a blocked_by edge
# in the ORIGINAL direction, not a spurious reversed one.
blocked = {(f, t) for f, k, t in live_edges if k == "blocked_by"}
planned_blocked = {(e["from"], e["to"]) for e in P.extract_graph(P.build_plan(doc))["edges"]
                   if e["kind"] == "blocked_by" and not e["dangling"]}
assert planned_blocked <= blocked, (planned_blocked, blocked)

# --- 5. the marker must survive a COMMENT-STRIPPING sanitizer (measured live) -----
# Plane v2.6.3 deletes HTML comments from description_html. If the per-view carrier
# is ever changed to a comment, every item silently loses its triple — so assert the
# emitted description still yields the triple AFTER that sanitizer runs.
doc = C.load_document(DOC)
for op in P.build_plan(doc)["ops"]:
    if op["op"] != "upsert_item":
        continue
    stored = sanitize(op["payload"]["description_html"])
    assert "[[ledger-views" in stored, op["uid"]
    C.recover_views(op["labels"], stored, op["uid"])          # raises if the carrier died
# ...and the sanitizer double must actually be capable of killing a comment, or the
# check above proves nothing.
assert "CANARY" not in sanitize("<p>x</p><!-- CANARY -->"), "sanitizer double is toothless"

# --- 6. a 429 is retried loudly, not lost -----------------------------------------
import urllib.error
import urllib.request

calls = {"n": 0}


class FakeResp:
    def __init__(self, payload):
        self._p = payload

    def read(self):
        return self._p

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False


def flaky_urlopen(req, timeout=None):
    calls["n"] += 1
    if calls["n"] == 1:
        raise urllib.error.HTTPError(
            "u", 429, "Too Many Requests", {"Retry-After": "0"}, None)
    return FakeResp(b'{"ok": true}')


real_urlopen, real_sleep = urllib.request.urlopen, P.time.sleep
urllib.request.urlopen = flaky_urlopen
P.time.sleep = lambda s: None
try:
    client = P.Plane("http://x", "k", "ws", "pr", rate_per_min=0)
    assert client.request("GET", "/issues/") == {"ok": True}
    assert calls["n"] == 2, calls
finally:
    urllib.request.urlopen, P.time.sleep = real_urlopen, real_sleep


class AlwaysThrottled(urllib.error.HTTPError):
    pass


def always_429(req, timeout=None):
    raise urllib.error.HTTPError("u", 429, "Too Many Requests", {"Retry-After": "0"}, None)


urllib.request.urlopen = always_429
P.time.sleep = lambda s: None
try:
    client = P.Plane("http://x", "k", "ws", "pr", rate_per_min=0, max_retries=2)
    try:
        client.request("GET", "/issues/")
    except C.AdapterError as exc:
        assert "429" in str(exc), exc               # gives up LOUDLY, never silently
    else:
        raise AssertionError("an unrecoverable 429 was swallowed")
finally:
    urllib.request.urlopen, P.time.sleep = real_urlopen, real_sleep

# --- 7. schema_version: in step with THIS checkout's mapper, closed to others -----
supported = C.supported_schema_versions()
mapper = C._mapper_schema_version()
assert mapper, "could not read ledger-map.py's SCHEMA_VERSION"
assert mapper in supported, (mapper, supported)
assert "9.9.9" not in supported
# a mapper bump is picked up without editing the adapter...
bumped = "%s/bumped-map.py" % tmp
open(bumped, "w").write('SCHEMA_VERSION = "1.1.0"\n')
assert C._mapper_schema_version(bumped) == "1.1.0"
# ...but an unknown version is still REFUSED, loudly.
try:
    C.check_schema_version({"schema_version": "9.9.9", "items": []})
except C.AdapterError as exc:
    assert "REFUSING" in str(exc), exc
else:
    raise AssertionError("an unknown schema_version was accepted")

print("ok")
PY

echo "PASS: Plane live-contract (apply/verify, id:857d non-vacuity, sanitizer, 429, schema gate)"
