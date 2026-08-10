#!/usr/bin/env bash
# (no `# roadmap:` header — this specs TODO id:90f2, which has no ROADMAP entry.
#  Its failures therefore ALWAYS count.)
#
# id:90f2 contract: "the same fixture JSON yields equivalent item graphs —
# relations, labels, assignee, statuses — in both targets (Plane, Vikunja)".
# Plus the BINDING id:857d gate: each adapter must carry the per-view
# todo/roadmap/review triple (or a visible drift marker) INTO its target; an
# adapter that reads only `derived_status` and renders one column is a contract
# violation.
#
# Hermetic by construction: only the adapters' `plan`/`graph` verbs are
# exercised, and those never touch the network (asserted below with sockets
# disabled). `apply` is a manual, reported step and no test depends on a server.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TRK="$ROOT/tracker"
AD="$TRK/adapters"
FIX="$TRK/fixtures/expected"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*"; exit 1; }

FIXTURES=(repo-alpha repo-beta fleet-collision)

# --- 1. the equivalence contract --------------------------------------------------
for f in "${FIXTURES[@]}"; do
  python3 "$AD/vikunja_adapter.py" graph "$FIX/$f.json" > "$tmp/$f.vikunja.json" \
    || fail "vikunja graph failed on $f"
  python3 "$AD/plane_adapter.py"   graph "$FIX/$f.json" > "$tmp/$f.plane.json" \
    || fail "plane graph failed on $f"
  cmp -s "$tmp/$f.vikunja.json" "$tmp/$f.plane.json" \
    || fail "$f: Plane and Vikunja item graphs are NOT equivalent (id:90f2 contract)
$(diff "$tmp/$f.vikunja.json" "$tmp/$f.plane.json" | head -20)"
done

# The graphs must be non-trivial, or "equivalent" is vacuous.
python3 - "$tmp/repo-alpha.vikunja.json" <<'PY' || fail "graph is too thin to be a meaningful comparison"
import json, sys
g = json.load(open(sys.argv[1]))
assert len(g["nodes"]) >= 15, g
kinds = {e["kind"] for e in g["edges"]}
assert {"parent", "child", "blocked_by", "link"} <= kinds, kinds
assert any(n["assignee"] for n in g["nodes"])
assert any(len(n["labels"]) >= 5 for n in g["nodes"])
PY

# --- 2. determinism ----------------------------------------------------------------
for a in vikunja plane; do
  python3 "$AD/${a}_adapter.py" plan "$FIX/repo-alpha.json" > "$tmp/$a.plan.1"
  python3 "$AD/${a}_adapter.py" plan "$FIX/repo-alpha.json" > "$tmp/$a.plan.2"
  cmp -s "$tmp/$a.plan.1" "$tmp/$a.plan.2" || fail "$a plan is not deterministic"
done

# --- 3. the BINDING id:857d per-view gate, for BOTH adapters ----------------------
python3 - "$AD" "$FIX" <<'PY' || fail "id:857d per-view gate FAILED"
import json, sys, importlib
ad, fix = sys.argv[1], sys.argv[2]
sys.path.insert(0, ad)
import adapter_common as C

for name in ("vikunja_adapter", "plane_adapter"):
    mod = importlib.import_module(name)
    for f in ("repo-alpha", "repo-beta", "fleet-collision"):
        doc = C.load_document("%s/%s.json" % (fix, f))
        graph = mod.extract_graph(mod.build_plan(doc))
        bad = C.check_gate(doc, graph)
        if bad:
            print("%s/%s: %s" % (name, f, bad[:5]))
            sys.exit(1)

    # The drift cases specifically: both directions, both views distinct, and a
    # drift marker present. This is what a derived_status-only adapter loses.
    doc = C.load_document("%s/repo-alpha.json" % fix)
    graph = mod.extract_graph(mod.build_plan(doc))
    nodes = {n["uid"]: n for n in graph["nodes"]}
    a, b = nodes["repo-alpha/1111"], nodes["repo-alpha/2222"]
    assert (a["todo_status"], a["roadmap_status"]) == ("open", "done"), (name, a)
    assert (b["todo_status"], b["roadmap_status"]) == ("done", "open"), (name, b)
    assert a["drift"] and b["drift"], name
    assert a["derived_status"] != "done" and b["derived_status"] != "done", name
    assert C.DRIFT_LABEL in a["labels"] and C.DRIFT_LABEL in b["labels"], name
    # all three views individually recoverable, review included
    for n in graph["nodes"]:
        for v in C.VIEWS:
            assert n["%s_status" % v] in C.VIEW_STATES, (name, n["uid"], v)
print("ok")
PY

# --- 4. the gate is NOT vacuous: a derived_status-only adapter must FAIL it -------
python3 - "$AD" "$FIX" <<'PY' || fail "a derived_status-only (collapsed) adapter was NOT rejected — the id:857d gate is vacuous"
import json, sys, importlib
ad, fix = sys.argv[1], sys.argv[2]
sys.path.insert(0, ad)
import adapter_common as C

for name in ("vikunja_adapter", "plane_adapter"):
    mod = importlib.import_module(name)
    doc = C.load_document("%s/repo-alpha.json" % fix)
    plan = mod.build_plan(doc)

    # Simulate the forbidden adapter: keep ONLY derived_status, drop the per-view
    # labels and the [[ledger-views]] marker.
    for op in plan["ops"]:
        if op["op"] == "upsert_item":
            op["labels"] = [l for l in op["labels"]
                            if not l.startswith("view:") and l != C.DRIFT_LABEL]
            for key in ("description", "description_html"):
                if key in op["payload"]:
                    op["payload"][key] = "<p>collapsed single status</p>"
    try:
        graph = mod.extract_graph(plan)
    except C.AdapterError:
        continue                      # rejected loudly at recovery — good
    bad = C.check_gate(doc, graph)
    if not bad:
        print("%s: collapsed plan passed the gate" % name)
        sys.exit(1)
print("ok")
PY

# --- 5. the two carriers must AGREE (a half-edited board is loud) -----------------
python3 - "$AD" "$FIX" <<'PY' || fail "tampering with ONE per-view carrier was not detected"
import sys, importlib
ad, fix = sys.argv[1], sys.argv[2]
sys.path.insert(0, ad)
import adapter_common as C

for name in ("vikunja_adapter", "plane_adapter"):
    mod = importlib.import_module(name)
    plan = mod.build_plan(C.load_document("%s/repo-alpha.json" % fix))
    for op in plan["ops"]:
        if op["op"] == "upsert_item" and op["uid"] == "repo-alpha/1111":
            op["labels"] = ["view:todo=done" if l == "view:todo=open" else l
                            for l in op["labels"]]
    try:
        mod.extract_graph(plan)
    except C.AdapterError as exc:
        assert "disagree" in str(exc), (name, exc)
        continue
    print("%s: label/marker disagreement went undetected" % name)
    sys.exit(1)
print("ok")
PY

# --- 6. schema_version refusal (SCHEMA.md §5) -------------------------------------
python3 -c '
import json,sys
d=json.load(open(sys.argv[1])); d["schema_version"]="9.9.9"
json.dump(d, open(sys.argv[2],"w"))
' "$FIX/repo-alpha.json" "$tmp/future.json"
for a in vikunja plane; do
  set +e
  python3 "$AD/${a}_adapter.py" graph "$tmp/future.json" > /dev/null 2> "$tmp/$a.err"
  rc=$?
  set -e
  [[ "$rc" -ne 0 ]] || fail "$a accepted an UNKNOWN schema_version — SCHEMA.md §5 says refuse"
  grep -qi 'REFUSING' "$tmp/$a.err" || fail "$a rejected a future schema_version without saying so: $(cat "$tmp/$a.err")"
done

# --- 7. plan/graph are OFFLINE (the suite must never need a server) ---------------
python3 - "$AD" "$FIX" <<'PY' || fail "plan/graph attempted a network call — the suite must be hermetic"
import socket, sys, importlib
ad, fix = sys.argv[1], sys.argv[2]

class NoNet(socket.socket):
    def __init__(self, *a, **k):
        raise AssertionError("network access attempted in plan/graph")
socket.socket = NoNet
socket.create_connection = lambda *a, **k: (_ for _ in ()).throw(
    AssertionError("network access attempted in plan/graph"))

sys.path.insert(0, ad)
import adapter_common as C
for name in ("vikunja_adapter", "plane_adapter"):
    mod = importlib.import_module(name)
    mod.extract_graph(mod.build_plan(C.load_document("%s/repo-alpha.json" % fix)))
print("ok")
PY

# --- 8. no credential may be hardcoded in a PUBLIC repo ---------------------------
if grep -nEi '(api[_-]?key|token|password)[[:space:]]*=[[:space:]]*["'"'"'][A-Za-z0-9_.-]{12,}' \
     "$AD"/*.py; then
  fail "a literal-looking credential is present in an adapter — read secrets by injection only"
fi

echo "PASS: tracker adapter equivalence + id:857d per-view gate"
