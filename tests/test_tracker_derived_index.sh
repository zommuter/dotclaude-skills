#!/usr/bin/env bash
# roadmap:dcf3
#
# TODO/ROADMAP id:dcf3 -- the tracker pilot's DERIVED-INDEX arm (tracker/derived-index.py).
#
# Contract asserted here:
#   1. keystones ranks open items by TRANSITIVE open fan-out over typed gate edges,
#      and --assignee filters to the human-decision population.
#   2. stale-gates reports a gate whose target is closed in every view, and reports an
#      unresolvable gate token LOUDLY on stderr instead of dropping it (id:4347).
#   3. a gate token that crosses repos resolves when it is fleet-unique, and resolves to
#      NOTHING (reported unresolved) when two repos own the same 4-hex token.
#   4. the id:cb00 children-of trap: the arm's substrate (tracker/ledger-map.py) reads
#      BOTH the `children:` and `children-of:` spellings into one graph, so this arm does
#      not inherit lib-typed-edges.sh's children-of blindness. Asserted directly, because
#      the whole reason this arm consumes the intermediate document is that it must not.
#
# Hermetic: builds its own fixture ledgers in a mktemp dir; touches no repo state, no
# network, no ~/.claude, and never writes to a tracker.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAP="$ROOT/tracker/ledger-map.py"
IDX="$ROOT/tracker/derived-index.py"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*"; exit 1; }

mkdir -p "$tmp/alpha" "$tmp/beta"

# --- alpha: a gate chain, a stale gate, a dangling gate, both child spellings ---------
cat > "$tmp/alpha/TODO.md" <<'EOF'
# TODO — alpha (fixture)

## work

- [ ] [INPUT — decision] The keystone: everything hangs off this <!-- id:1000 -->
- [ ] [ROUTINE] Blocked directly on the keystone <!-- gated-on:1000 --> <!-- id:1001 -->
- [ ] [ROUTINE] Blocked on 1001, so transitively on the keystone <!-- gated-on:1001 --> <!-- id:1002 -->
- [ ] [ROUTINE] Blocked on a gate that is already closed <!-- gated-on:1003 --> <!-- id:1004 -->
- [x] [ROUTINE] The already-closed gate <!-- id:1003 -->
- [ ] [ROUTINE] Blocked on a token nobody owns <!-- gated-on:dead --> <!-- id:1005 -->
- [ ] [HARD] Parent declaring its child downward <!-- children:1007 --> <!-- id:1006 -->
- [ ] [HARD] The downward-declared child <!-- id:1007 -->
- [ ] [HARD] Child declaring its parent upward <!-- children-of:1006 --> <!-- id:1008 -->
- [ ] [INPUT — decision] Blocked on a gate that only beta owns <!-- gated-on:2001 --> <!-- id:1009 -->
- [ ] [ROUTINE] Blocked on a token two OTHER repos both own <!-- gated-on:cccc --> <!-- id:100a -->
EOF

cat > "$tmp/beta/TODO.md" <<'EOF'
# TODO — beta (fixture)

## work

- [ ] [INPUT — decision] Beta's fleet-unique gate target <!-- id:2001 -->
- [ ] [ROUTINE] Beta's copy of the colliding token <!-- id:cccc -->
EOF

mkdir -p "$tmp/gamma"
cat > "$tmp/gamma/TODO.md" <<'EOF'
# TODO — gamma (fixture)

## work

- [ ] [ROUTINE] Gamma's copy of the colliding token <!-- id:cccc -->
EOF

python3 "$MAP" import alpha "$tmp/alpha" > "$tmp/alpha.json" 2>"$tmp/alpha.err" \
  || fail "ledger-map import alpha failed: $(cat "$tmp/alpha.err")"
python3 "$MAP" import beta "$tmp/beta" > "$tmp/beta.json" 2>/dev/null \
  || fail "ledger-map import beta failed"
python3 "$MAP" import gamma "$tmp/gamma" > "$tmp/gamma.json" 2>/dev/null \
  || fail "ledger-map import gamma failed"
python3 "$MAP" merge "$tmp/alpha.json" "$tmp/beta.json" "$tmp/gamma.json" > "$tmp/fleet.json" 2>/dev/null \
  || fail "ledger-map merge failed"

# --- 4. the id:cb00 trap: BOTH child spellings reach ONE graph -------------------------
# Asserted on the UNION reader, not on either raw field: `id:7a9c` measured that each
# spelling populates only one direction in the document, so `parent` alone and `children`
# alone are each a partial graph. A future symmetric mapper keeps this assertion true.
python3 "$IDX" child-edges "$tmp/fleet.json" --json > "$tmp/edges.json" 2>/dev/null \
  || fail "child-edges view failed"
python3 - "$tmp/edges.json" <<'PY' || fail "id:cb00 both-spelling contract broken -- this arm would inherit lib-typed-edges.sh's children-of blindness"
import json, sys
rows = {(r["parent"], r["child"]): r for r in json.load(open(sys.argv[1]))["rows"]}
ok = True
d = rows.get(("alpha/1006", "alpha/1007"))
if not d or "downward" not in d["declared"]:
    print("downward `children:` edge 1006->1007 missing: %r" % (d,)); ok = False
u = rows.get(("alpha/1006", "alpha/1008"))
if not u or "upward" not in u["declared"]:
    print("upward `children-of:` edge 1006->1008 missing: %r" % (u,)); ok = False
sys.exit(0 if ok else 1)
PY

# --- 1. keystones: transitive fan-out + assignee filter --------------------------------
python3 "$IDX" keystones "$tmp/fleet.json" --json > "$tmp/keys.json" 2>/dev/null \
  || fail "keystones view failed"
python3 - "$tmp/keys.json" <<'PY' || fail "keystones ranking is wrong"
import json, sys
rows = {r["uid"]: r for r in json.load(open(sys.argv[1]))["rows"]}
ok = True
k = rows.get("alpha/1000")
if not k:
    print("keystone alpha/1000 absent"); sys.exit(1)
if k["ungates_open"] != 2:
    print("alpha/1000 ungates_open == %r, expected 2 (1001 direct + 1002 transitive)" % k["ungates_open"]); ok = False
if k["ungates_direct_open"] != 1:
    print("alpha/1000 direct == %r, expected 1" % k["ungates_direct_open"]); ok = False
if sorted(k["ungates"]) != ["alpha/1001", "alpha/1002"]:
    print("alpha/1000 ungates == %r" % (k["ungates"],)); ok = False
if "alpha/1002" in rows:
    print("alpha/1002 ungates nothing and must not be listed"); ok = False
# cross-repo: beta/2001 gates alpha/1009
b = rows.get("beta/2001")
if not b or b["ungates_open"] != 1 or b["ungates"] != ["alpha/1009"]:
    print("cross-repo gate beta/2001 -> alpha/1009 not ranked: %r" % (b,)); ok = False
sys.exit(0 if ok else 1)
PY

python3 "$IDX" keystones "$tmp/fleet.json" --json --assignee human > "$tmp/keys-h.json" 2>/dev/null \
  || fail "keystones --assignee human failed"
python3 - "$tmp/keys-h.json" <<'PY' || fail "--assignee human filter is wrong"
import json, sys
rows = json.load(open(sys.argv[1]))["rows"]
uids = sorted(r["uid"] for r in rows)
if uids != ["alpha/1000", "beta/2001"]:
    print("human keystones == %r, expected the two [INPUT — decision] items" % (uids,)); sys.exit(1)
if any(r["assignee"] != "human" for r in rows):
    print("a non-human row survived the filter"); sys.exit(1)
PY

# --- 2 + 3. stale gates, dangling tokens, ambiguous cross-repo tokens -------------------
python3 "$IDX" stale-gates "$tmp/fleet.json" --json > "$tmp/stale.json" 2>"$tmp/stale.err" \
  || fail "stale-gates view failed"
python3 - "$tmp/stale.json" <<'PY' || fail "stale-gates content is wrong"
import json, sys
d = json.load(open(sys.argv[1]))
rows = {(r["uid"], str(r["gate"])): r for r in d["rows"]}
ok = True
r = rows.get(("alpha/1004", "alpha/1003"))
if not r or "closed" not in r["reason"]:
    print("closed-gate row for alpha/1004 missing: %r" % (r,)); ok = False
r = rows.get(("alpha/1005", "alpha/dead"))
if not r or "no item owns" not in r["reason"]:
    print("dangling-token row for alpha/1005 missing: %r" % (r,)); ok = False
r = rows.get(("alpha/100a", "alpha/cccc"))
if not r or "ambiguous" not in r["reason"]:
    print("a token two OTHER repos own must resolve to NOTHING, reported ambiguous: %r" % (r,)); ok = False
amb = [u for u in d["unresolved_gates"] if u["uid"] == "alpha/100a"]
if not amb or "ambiguous" not in amb[0]["reason"]:
    print("ambiguous fleet-wide token not in unresolved_gates: %r" % (amb,)); ok = False
if any(x["uid"] == "alpha/1001" for x in d["rows"]):
    print("alpha/1001's gate is OPEN and must not be reported stale"); ok = False
sys.exit(0 if ok else 1)
PY

grep -q 'UNRESOLVED gate' "$tmp/stale.err" \
  || fail "unresolved gates must be reported LOUDLY on stderr (id:4347), got: $(cat "$tmp/stale.err")"

# --- side-effect freedom: the arm writes nothing ----------------------------------------
before="$(find "$tmp/alpha" "$tmp/beta" "$tmp/gamma" -type f | sort | xargs md5sum | md5sum)"
python3 "$IDX" keystones "$tmp/fleet.json" >/dev/null 2>&1
python3 "$IDX" stale-gates "$tmp/fleet.json" >/dev/null 2>&1
after="$(find "$tmp/alpha" "$tmp/beta" "$tmp/gamma" -type f | sort | xargs md5sum | md5sum)"
[[ "$before" == "$after" ]] || fail "derived-index.py mutated its input ledgers"

echo "PASS: tracker/derived-index.py — keystone fan-out, stale/dangling/ambiguous gates, cb00 both-spelling substrate, read-only"
