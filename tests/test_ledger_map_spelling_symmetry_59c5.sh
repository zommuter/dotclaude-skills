#!/usr/bin/env bash
# roadmap:59c5
#
# id:59c5 — the UNMET half of id:8302's ratified acceptance.
#
# id:8302 shipped clause (a) — a `<!-- children-of:aa01,aa02 -->` line no longer drops a
# parent (`parents` list, `parent` kept as a first-entry alias). Its acceptance had a
# SECOND clause that the RED spec `tests/test_ledger_map_multi_parent_8302.sh` set a
# fixture up for but never asserted, so it shipped unimplemented and the suite stayed
# green:
#
#   "the two spellings resolve to ONE relation, so a parent-side `children:` edge and a
#    child-side `children-of:` edge naming the same pair produce the same fact"
#
# MEASURED on the post-8302 tree (review run relay-20260901-101120-32404):
#
#   repo/aa03  parents=[]              children=['repo/bb02']   <- parent-side spelling
#   repo/bb01  parents=[aa01, aa02]    children=[]              <- child-side spelling
#   repo/aa01  parents=[]              children=[]              <- NOT told it has a child
#   repo/bb02  parents=[]              children=[]              <- NOT told it has a parent
#
# So the relation is resolvable in exactly ONE direction, and WHICH direction depends on
# which end the author happened to write it from. Every consumer that walks the graph
# (closure by child edges, gate fan-out, the tracker projection) therefore sees a
# different graph for two ledgers that state the same fact.
#
# RED until 59c5 lands. Contract:
#   (a) a child-side `children-of:P` on C makes the C->P relation resolvable from BOTH
#       ends: C names P, and P names C;
#   (b) a parent-side `children:C` on P does likewise;
#   (c) the two spellings are INDISTINGUISHABLE in the imported document — the pair
#       declared child-side and the pair declared parent-side yield the same
#       resolvability tuple.
#
# Representation stays the implementer's call (mirror on import, reconcile in a second
# pass, or resolve at read time). What is pinned is the OBSERVABLE. `body`, `title` and
# `sources` are EXCLUDED because `body` retains the raw `<!-- children-of:... -->` marker
# verbatim, which makes a whole-item substring match vacuous (the trap 8302's spec
# documented and this one inherits).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAP="$ROOT/tracker/ledger-map.py"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*"; exit 1; }

mkdir -p "$tmp/repo/.git"
cat > "$tmp/repo/TODO.md" <<'EOF'
# TODO

## Current

- [ ] Parent, declared from the CHILD side <!-- id:aa01 -->
- [ ] Child, declaring its own parent <!-- children-of:aa01 --> <!-- id:bb01 -->
- [ ] Parent, declaring its own child <!-- children:bb02 --> <!-- id:aa03 -->
- [ ] Child, declared from the PARENT side <!-- id:bb02 -->
EOF

# Ground truth read from the fixture, not from the thing under test.
grep -q 'children-of:aa01' "$tmp/repo/TODO.md" || fail "fixture lost the child-side line"
grep -q 'children:bb02'    "$tmp/repo/TODO.md" || fail "fixture lost the parent-side line"

python3 "$MAP" import repo "$tmp/repo" > "$tmp/doc.json" 2>"$tmp/err" \
  || fail "import exited non-zero: $(cat "$tmp/err")"

python3 - "$tmp/doc.json" <<'PY' > "$tmp/out"
import json, sys

doc = json.load(open(sys.argv[1]))
items = doc["items"] if isinstance(doc, dict) and "items" in doc else doc
by_id = {}
for it in (items.values() if isinstance(items, dict) else items):
    key = it.get("id") or it.get("uid", "")
    by_id[str(key).split("/")[-1].split(":")[-1]] = it

# Only STRUCTURAL edge fields count. `body`/`title`/`sources` are excluded on purpose:
# body carries the raw marker text, so including it would make every check vacuous.
EDGE_KEYS = ("parent", "parents", "children", "blocked_by", "links", "fields", "labels")

def mentions(tok, other):
    it = by_id.get(tok)
    if it is None:
        return None
    blob = json.dumps({k: it.get(k) for k in EDGE_KEYS if k in it})
    return other in blob

for tok in ("aa01", "bb01", "aa03", "bb02"):
    if tok not in by_id:
        print(f"missing_{tok}=1")

# child-side spelling: bb01 declares children-of:aa01
print("childside_child_names_parent=" + ("1" if mentions("bb01", "aa01") else "0"))
print("childside_parent_names_child=" + ("1" if mentions("aa01", "bb01") else "0"))
# parent-side spelling: aa03 declares children:bb02
print("parentside_parent_names_child=" + ("1" if mentions("aa03", "bb02") else "0"))
print("parentside_child_names_parent=" + ("1" if mentions("bb02", "aa03") else "0"))
PY

get() { grep -E "^$1=" "$tmp/out" | cut -d= -f2; }

grep -qE '^missing_' "$tmp/out" && fail "id:59c5: import dropped a fixture item: $(grep -E '^missing_' "$tmp/out" | tr '\n' ' ')"

cs_down="$(get childside_child_names_parent)"
cs_up="$(get childside_parent_names_child)"
ps_down="$(get parentside_child_names_parent)"
ps_up="$(get parentside_parent_names_child)"

# (a) + (b): each declaration resolves the relation from BOTH ends.
[[ "$cs_down" == 1 ]] || fail "id:59c5 (a): child-side \`children-of:aa01\` — bb01 does not name aa01 in any structural edge field"
[[ "$cs_up"   == 1 ]] || fail "id:59c5 (a): child-side \`children-of:aa01\` — aa01 is never told it has child bb01, so the relation is resolvable only downward (see ledger-map.py assemble(): children-of: writes only the child's own \`parents\`)"
[[ "$ps_up"   == 1 ]] || fail "id:59c5 (b): parent-side \`children:bb02\` — aa03 does not name bb02 in any structural edge field"
[[ "$ps_down" == 1 ]] || fail "id:59c5 (b): parent-side \`children:bb02\` — bb02 is never told it has parent aa03, so the relation is resolvable only upward"

# (c) the two spellings are indistinguishable in the imported document.
[[ "$cs_down$cs_up" == "$ps_down$ps_up" ]] \
  || fail "id:59c5 (c): the two spellings produce DIFFERENT facts — child-side (down=$cs_down,up=$cs_up) vs parent-side (down=$ps_down,up=$ps_up); the graph a consumer walks depends on which end the author wrote from"

echo "PASS: id:59c5 — children-of: and children: resolve to ONE relation, readable from both ends"
