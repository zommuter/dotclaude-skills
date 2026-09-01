#!/usr/bin/env bash
# roadmap:8302
#
# id:8302 — `children-of:` and `children:` are the SAME parent/child edge written from
# opposite ends, but `tracker/ledger-map.py` assigns `children-of:` to a SCALAR `parent`
# (`:641-642`) and `children:` to a LIST `children` (`:643-646`) with no reconciliation.
#
# The scalar is what makes this DATA LOSS rather than an ergonomics gap: the importer
# loops over every `children-of:` token and assigns each to the same scalar slot, so a
# line declaring several parents silently keeps only the LAST one. No warning, no error,
# no exit code — the edge simply is not in the output document.
#
#   for t in ob["children_of"]:
#       it["parent"] = uid_of(repo, t)     # <-- last write wins, silently
#
# RED until 8302 lands. The contract, from the item:
#   (a) a line declaring TWO parents round-trips BOTH — neither is silently dropped;
#   (b) the two spellings resolve to ONE relation, so a parent-side `children:` edge and
#       a child-side `children-of:` edge naming the same pair produce the same fact;
#   (c) this fixture pins the multi-parent case that currently loses silently.
#
# Deliberately asserts the OBSERVABLE (both parents survive the import), not a chosen
# representation — whether the fix widens `parent` to a list, folds `children-of:` into
# the existing `children` list on the parent side, or adds a reconciliation pass is the
# implementer's call, and this test must not pin one of those three.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAP="$ROOT/tracker/ledger-map.py"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*"; exit 1; }

# --- a minimal ledger whose child declares TWO parents ------------------------------
mkdir -p "$tmp/repo/.git"
cat > "$tmp/repo/TODO.md" <<'EOF'
# TODO

## Current

- [ ] Parent one <!-- id:aa01 -->
- [ ] Parent two <!-- id:aa02 -->
- [ ] Child of both parents <!-- children-of:aa01,aa02 --> <!-- id:bb01 -->
- [ ] Parent-side declaration <!-- children:bb02 --> <!-- id:aa03 -->
- [ ] Child named from the parent side <!-- id:bb02 -->
EOF

python3 "$MAP" import repo "$tmp/repo" > "$tmp/doc.json" 2>"$tmp/err" \
  || fail "import exited non-zero: $(cat "$tmp/err")"

# Ground truth read from the fixture, not from the thing under test.
grep -q 'children-of:aa01,aa02' "$tmp/repo/TODO.md" || fail "fixture lost the multi-parent line"

# --- (a) BOTH declared parents survive the import ------------------------------------
python3 - "$tmp/doc.json" <<'PY' > "$tmp/out"
import json, sys
doc = json.load(open(sys.argv[1]))
items = doc["items"] if isinstance(doc, dict) and "items" in doc else doc
by_id = {}
for it in (items.values() if isinstance(items, dict) else items):
    key = it.get("id") or it.get("uid", "")
    by_id[str(key).split(":")[-1]] = it

child = by_id.get("bb01")
if child is None:
    print("child_present=0"); print("parent_aa01=0"); print("parent_aa02=0")
    raise SystemExit(0)
print("child_present=1")

# Accept ANY STRUCTURAL representation that carries the edge: a scalar `parent`, a list
# `parents`, or a `blocked_by`/`links`/`fields` edge naming the token. What is asserted is
# that the FACT survived, not where it was stored.
#
# `body`, `title` and `sources` are EXCLUDED on purpose. `body` retains the raw
# `<!-- children-of:aa01,aa02 -->` marker verbatim, so a whole-item substring match is
# VACUOUS — it passes against the present, broken importer (measured: the item ships
# `"parent": "repo/aa02"` with aa01 dropped, yet `"aa01" in json.dumps(item)` is True).
EDGE_KEYS = ("parent", "parents", "children", "blocked_by", "links", "fields", "labels")
blob = json.dumps({k: child.get(k) for k in EDGE_KEYS if k in child})
for tok in ("aa01", "aa02"):
    print(f"parent_{tok}=" + ("1" if tok in blob else "0"))
PY

while IFS='=' read -r k v; do
  [[ -z "$k" ]] && continue
  [[ "$v" == "1" ]] || fail "id:8302 (a) multi-parent line loses an edge — $k=$v (only the LAST children-of: token survives; see ledger-map.py:641-642)"
done < "$tmp/out"

echo "PASS: id:8302 — a multi-parent children-of: line round-trips both parents"
