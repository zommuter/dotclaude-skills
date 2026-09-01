#!/usr/bin/env bash
# (no `# roadmap:` header — TODO id:8c7f has no ROADMAP entry. Failures ALWAYS count.)
#
# id:8c7f — the three coupled gaps that let a value-space change ship unversioned:
#   1. `schema_version` is 1.1.0, and `verdict` / `board_column` carry real `enum`s that
#      `validate` ENFORCES (a retired verdict value fails).
#   2. the schema cross-check covers `$defs/repo`, not just `$defs.item`, and `head_sha`
#      — load-bearing in fleet-state.py — is declared.
#   3. the version constant has ONE declared source; a re-hardcoded copy is caught.
#
# Each mutation is driven against a COPY of the tree, so the checks are proved non-vacuous
# (a cross-check that cannot fail is not a cross-check). Hermetic: mktemp only.
# fails-against: rev 064ae4424967 -- the tree as it stood immediately before the commit that
#   added this test, i.e. the pre-fix tracker/SCHEMA.md, tracker/adapters/adapter_common.py, tracker/fixtures/expected/fleet-collision.json (+5 more). Derived + verified by tests/verify-negative-cases.py.
# fails-against-rev: 064ae4424967 -- tracker/SCHEMA.md tracker/adapters/adapter_common.py tracker/fixtures/expected/fleet-collision.json tracker/fixtures/expected/repo-alpha.json tracker/fixtures/expected/repo-beta.json tracker/ledger-map.py tracker/repo-entity.py tracker/schema/ledger-intermediate.schema.json
# fails-against-assertion: expected 1.1.0 (id:8c7f)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TRK="$ROOT/tracker"
MAP="$TRK/ledger-map.py"
SCHEMA="$TRK/schema/ledger-intermediate.schema.json"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*"; exit 1; }
pass() { echo "PASS: $*"; }

# --- 0. the version is 1.1.0 everywhere, and declared in exactly one place ----------
version="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["properties"]["schema_version"]["const"])' "$SCHEMA")"
[[ "$version" == "1.1.0" ]] || fail "schema const is $version, expected 1.1.0 (id:8c7f)"

python3 - "$ROOT" "$version" <<'PY' || fail "the four version copies do not agree"
import importlib.util, json, re, sys

root, want = sys.argv[1], sys.argv[2]


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


ok = True
lm = load("%s/tracker/ledger-map.py" % root, "ledger_map")
re_ = load("%s/tracker/repo-entity.py" % root, "repo_entity")
ad = load("%s/tracker/adapters/adapter_common.py" % root, "adapter_common")

got = {
    "ledger-map.py SCHEMA_VERSION": lm.SCHEMA_VERSION,
    "repo-entity.py SCHEMA_VERSION": re_.SCHEMA_VERSION,
    "adapter_common.py SUPPORTED_SCHEMA_VERSIONS[0]": ad.SUPPORTED_SCHEMA_VERSIONS[0],
}
# the 5th reader: fleet-import.sh scrapes ledger-map.py's literal spelling
src = open("%s/tracker/fleet-import.sh" % root, encoding="utf-8").read()
pat = re.search(r'SCHEMA_VERSION = \\"\(\[\^\\"\]\+\)\\"', src)
if pat is None:
    print("ERROR: fleet-import.sh no longer scrapes a SCHEMA_VERSION = \"…\" literal — "
          "the pinned spelling in ledger-map.py may have moved out from under it")
    ok = False
else:
    m = re.search(r'SCHEMA_VERSION = "([^"]+)"',
                  open("%s/tracker/ledger-map.py" % root, encoding="utf-8").read())
    got["fleet-import.sh scrape of ledger-map.py"] = m.group(1) if m else None

for k, v in got.items():
    if v != want:
        print("ERROR: %s == %r, expected %r" % (k, v, want))
        ok = False

# only ONE python file may DECLARE the literal; the rest must derive it
for rel in ("tracker/repo-entity.py", "tracker/adapters/adapter_common.py"):
    text = open("%s/%s" % (root, rel), encoding="utf-8").read()
    for n, line in enumerate(text.splitlines(), 1):
        if re.search(r"schema[_ ]?version", line, re.I) and re.search(r"[\"'][0-9]+\.[0-9]+\.[0-9]+[\"']", line):
            print("ERROR: %s:%d re-declares the version as a literal: %s" % (rel, n, line.strip()))
            ok = False
sys.exit(0 if ok else 1)
PY
pass "schema_version is 1.1.0 and all five readers agree, with one declared copy"

# --- 1. a retired `verdict` value FAILS validation ---------------------------------
doc="$tmp/doc.json"
python3 "$MAP" import repo-alpha "$TRK/fixtures/repo-alpha" > "$doc" 2>/dev/null \
  || fail "fixture import failed"
python3 "$MAP" validate "$doc" >/dev/null 2>"$tmp/clean.err" \
  || fail "validate rejected the clean fixture: $(cat "$tmp/clean.err")"

for retired in relay-poolable needs-feedback design-drained; do
  python3 - "$doc" "$tmp/retired.json" "$retired" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["repos"][0]["verdict"] = sys.argv[3]
json.dump(d, open(sys.argv[2], "w"))
PY
  if python3 "$MAP" validate "$tmp/retired.json" >/dev/null 2>"$tmp/retired.err"; then
    fail "validate ACCEPTED the retired verdict value '$retired' — it is a board_column value now"
  fi
  grep -qi 'retired' "$tmp/retired.err" \
    || fail "'$retired' rejected without naming the retirement: $(cat "$tmp/retired.err")"
  grep -qi 'board_column' "$tmp/retired.err" \
    || fail "'$retired' rejected without naming where the value went: $(cat "$tmp/retired.err")"
done

# a LIVE verdict value must still pass, or the check is just 'reject everything'
python3 - "$doc" "$tmp/live.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["repos"][0]["verdict"] = "execute"
json.dump(d, open(sys.argv[2], "w"))
PY
python3 "$MAP" validate "$tmp/live.json" >/dev/null 2>"$tmp/live.err" \
  || fail "validate rejected the LIVE verdict 'execute': $(cat "$tmp/live.err")"

# and an unknown-but-not-retired verdict is still loud
python3 - "$doc" "$tmp/bogus.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["repos"][0]["verdict"] = "definitely-not-a-verdict"
json.dump(d, open(sys.argv[2], "w"))
PY
python3 "$MAP" validate "$tmp/bogus.json" >/dev/null 2>&1 \
  && fail "validate accepted a verdict outside the enum"
pass "a retired verdict value fails validation, naming the migration; live values pass"

# --- 2. `$defs/repo` drift is caught (it previously had NO protection) -------------
# Same technique as test_tracker_golden_fixture.sh: run the real mapper against a
# deliberately mutated schema and require a loud failure.
mutate_and_expect_failure() {
  local label="$1" pyfrag="$2" mut="$tmp/mut-$3"
  mkdir -p "$mut/schema"
  cp "$MAP" "$mut/ledger-map.py"
  python3 - "$SCHEMA" "$mut/schema/ledger-intermediate.schema.json" <<PY
import json, sys
s = json.load(open(sys.argv[1]))
$pyfrag
json.dump(s, open(sys.argv[2], "w"))
PY
  if python3 "$mut/ledger-map.py" validate "$doc" >/dev/null 2>"$tmp/mut.err"; then
    fail "$label was NOT caught — the \$defs/repo cross-check is vacuous"
  fi
  grep -qi 'drift' "$tmp/mut.err" \
    || fail "$label rejected without naming the drift: $(cat "$tmp/mut.err")"
}

mutate_and_expect_failure "a dropped repo.verdict enum value" \
  's["$defs"]["repo"]["properties"]["verdict"]["anyOf"][0]["enum"].remove("mechanical")' v1
mutate_and_expect_failure "a dropped repo.board_column enum value" \
  's["$defs"]["repo"]["properties"]["board_column"]["enum"].remove("unclassified")' v2
mutate_and_expect_failure "a REMOVED repo property (head_sha)" \
  's["$defs"]["repo"]["properties"].pop("head_sha")' v3
mutate_and_expect_failure "an ADDED undeclared repo property" \
  's["$defs"]["repo"]["properties"]["surprise"] = {"type": "string"}' v4
mutate_and_expect_failure "a changed repo required-key set" \
  's["$defs"]["repo"]["required"].remove("verdict")' v5
pass "\$defs/repo enum / property / required-key drift is all caught"

# --- 2b. head_sha is declared, and it is the field fleet-state.py actually reads ----
python3 -c 'import json,sys; s=json.load(open(sys.argv[1])); assert "head_sha" in s["$defs"]["repo"]["properties"], "head_sha undeclared"' "$SCHEMA" \
  || fail "head_sha is not declared in \$defs/repo"
grep -q 'head_sha' "$TRK/fleet-state.py" \
  || fail "fleet-state.py no longer reads head_sha — the declaration may be pointless now"
pass "head_sha is declared in the schema and still read by fleet-state.py"

# --- 3. a re-hardcoded version copy is caught -------------------------------------
# Build a fake tracker tree so version_copy_check() has a repo-entity.py to look at.
fake="$tmp/fake/tracker"
mkdir -p "$fake/schema" "$fake/adapters"
cp "$MAP" "$fake/ledger-map.py"
cp "$SCHEMA" "$fake/schema/"
printf 'SCHEMA_VERSION = "1.0.0"\n' > "$fake/repo-entity.py"
if python3 "$fake/ledger-map.py" validate "$doc" >/dev/null 2>"$tmp/copy.err"; then
  fail "a re-hardcoded stale schema_version copy was NOT caught (id:8c7f)"
fi
grep -qi 'hardcoded schema_version copy' "$tmp/copy.err" \
  || fail "the stale copy was rejected without naming it: $(cat "$tmp/copy.err")"
grep -q 'repo-entity.py:1' "$tmp/copy.err" \
  || fail "the stale copy was reported without file:line: $(cat "$tmp/copy.err")"

# non-vacuity: the SAME file deriving the version must pass
printf 'SCHEMA_VERSION = _derived()  # no literal\n' > "$fake/repo-entity.py"
python3 "$fake/ledger-map.py" validate "$doc" >/dev/null 2>"$tmp/copy2.err" \
  || fail "a DERIVED version was flagged as a hardcoded copy: $(cat "$tmp/copy2.err")"
pass "re-hardcoding the version constant in a derived file is caught, deriving it is not"

# --- 4. adapters refuse a document from the OTHER version --------------------------
python3 - "$doc" "$tmp/old.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["schema_version"] = "1.0.0"
json.dump(d, open(sys.argv[2], "w"))
PY
python3 - "$ROOT" "$tmp/old.json" <<'PY' || fail "an adapter accepted a 1.0.0 document under 1.1.0"
import importlib.util, sys
spec = importlib.util.spec_from_file_location("adapter_common", "%s/tracker/adapters/adapter_common.py" % sys.argv[1])
ad = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ad)
try:
    ad.load_document(sys.argv[2])
except ad.AdapterError:
    sys.exit(0)
print("ERROR: adapter_common accepted schema_version 1.0.0 while supporting %r"
      % (ad.SUPPORTED_SCHEMA_VERSIONS,))
sys.exit(1)
PY
python3 "$MAP" validate "$tmp/old.json" >/dev/null 2>&1 \
  && fail "ledger-map.py validate accepted a 1.0.0 document"
pass "a 1.0.0 document is refused by both the adapters and validate"

echo "ALL PASS: schema_version 1.1.0, repo cross-check, one version source (id:8c7f)"
