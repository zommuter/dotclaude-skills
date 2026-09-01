#!/usr/bin/env bash
# (no `# roadmap:` header — this specs TODO id:2bb1, which has no ROADMAP entry.
#  Its failures therefore ALWAYS count; there is no expected-red escape.)
#
# id:2bb1 contract, clause (b): a synthetic cross-repo id collision exits non-zero.
#
# 4-hex ids are minted PER REPO and are never fleet-unique (TODO id:c3f6 caveat 1), so
# the key is the composite (repo, id). A fleet import that merges two repos' `cccc`
# into one item is the failure --fabled finding 6 named. Two classes are asserted:
#   A homonym            — same bare token, no cross-repo reference   -> fatal by default
#   B ambiguous routed   — a routed: edge resolving to >=2 repos      -> fatal ALWAYS
# fails-against: rev 8f1e25e1522b -- the tree as it stood immediately before the commit that
#   added this test, i.e. the pre-fix tracker/SCHEMA.md, tracker/fixtures/expected/fleet-collision.json, tracker/fixtures/expected/repo-alpha.json (+8 more). Derived + verified by tests/verify-negative-cases.py.
# fails-against-rev: 8f1e25e1522b -- tracker/SCHEMA.md tracker/fixtures/expected/fleet-collision.json tracker/fixtures/expected/repo-alpha.json tracker/fixtures/expected/repo-beta.json tracker/fixtures/repo-alpha/REVIEW_ME.md tracker/fixtures/repo-alpha/ROADMAP.md tracker/fixtures/repo-alpha/TODO.archive.md tracker/fixtures/repo-alpha/TODO.md tracker/fixtures/repo-beta/TODO.md tracker/ledger-map.py tracker/schema/ledger-intermediate.schema.json
# fails-against-assertion: import repo-alpha exited non-zero

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAP="$ROOT/tracker/ledger-map.py"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*"; exit 1; }

cd "$ROOT/tracker"
python3 "$MAP" import repo-alpha fixtures/repo-alpha > "$tmp/alpha.json" 2>/dev/null \
  || fail "import repo-alpha exited non-zero"
python3 "$MAP" import repo-beta  fixtures/repo-beta  > "$tmp/beta.json" 2>/dev/null \
  || fail "import repo-beta exited non-zero"
python3 "$MAP" merge "$tmp/alpha.json" "$tmp/beta.json" > "$tmp/fleet.json" \
  || fail "merge exited non-zero"

# Sanity: the fixture really does contain the synthetic collision (ground truth read
# from the ledgers, not from the thing under test).
grep -q '<!-- id:cccc -->' fixtures/repo-alpha/TODO.md || fail "fixture repo-alpha lost id:cccc"
grep -q '<!-- id:cccc -->' fixtures/repo-beta/TODO.md  || fail "fixture repo-beta lost id:cccc"
grep -q '<!-- routed:cafe -->' fixtures/repo-alpha/TODO.md || fail "fixture lost the routed:cafe edge"
grep -q '<!-- id:cafe -->' fixtures/repo-alpha/TODO.md || fail "fixture repo-alpha lost id:cafe"
grep -q '<!-- id:cafe -->' fixtures/repo-beta/TODO.md  || fail "fixture repo-beta lost id:cafe"

# --- each repo ALONE must be clean: the collision is a FLEET property --------------
python3 "$MAP" validate "$tmp/alpha.json" > /dev/null 2>&1 || fail "repo-alpha alone must validate clean"
python3 "$MAP" validate "$tmp/beta.json"  > /dev/null 2>&1 || fail "repo-beta alone must validate clean"

# --- clause (b): the merged fleet document exits NON-ZERO -------------------------
set +e
python3 "$MAP" validate "$tmp/fleet.json" > "$tmp/out" 2> "$tmp/err"
rc=$?
set -e
[[ "$rc" -ne 0 ]] || fail "validate exited 0 on a document with a cross-repo id collision"
[[ "$rc" -eq 3 ]] || fail "expected exit 3 (validation failure), got $rc"

# LOUD, not merely non-zero: it must name the token, both repos, and the class.
grep -qi 'collision' "$tmp/err" || fail "stderr never mentions a collision: $(cat "$tmp/err")"
grep -q "'cccc'" "$tmp/err"     || fail "class-A homonym token cccc not named: $(cat "$tmp/err")"
grep -q "'cafe'" "$tmp/err"     || fail "class-B ambiguous token cafe not named: $(cat "$tmp/err")"
grep -q 'repo-alpha' "$tmp/err" || fail "colliding repo repo-alpha not named"
grep -q 'repo-beta'  "$tmp/err" || fail "colliding repo repo-beta not named"

# --- class B is NEVER downgradable -------------------------------------------------
# (id:ca24 replaced the blanket boolean with a per-token allow-list; the two assertions
#  below are unchanged in substance — class B stays fatal, an ADJUDICATED class A warns.)
set +e
python3 "$MAP" validate "$tmp/fleet.json" --allow-homonym cccc --allow-homonym cafe \
  > "$tmp/out2" 2> "$tmp/err2"
rc2=$?
set -e
[[ "$rc2" -ne 0 ]] || fail "the allow-list silenced the class-B ambiguous routed edge; it must stay fatal"
grep -q "'cafe'" "$tmp/err2" || fail "class-B token cafe not named under the allow-list"
grep -qi 'ERROR.*class B' "$tmp/err2" || fail "class-B collision is no longer reported as an ERROR"
# ...while an adjudicated class A is downgraded to a WARN, and stays visible.
grep -qi 'WARN.*homonym' "$tmp/err2" || fail "--allow-homonym cccc dropped the class-A homonym instead of warning"
if grep -qi 'ERROR.*class A' "$tmp/err2"; then fail "--allow-homonym cccc left class A fatal"; fi

# --- a duplicate uid INSIDE one repo is always fatal (id reuse, not a homonym) -----
python3 - "$tmp/alpha.json" "$tmp/dupe.json" <<'PY'
import copy, json, sys
doc = json.load(open(sys.argv[1]))
first = doc["items"][0]
doc["items"].append(copy.deepcopy(first))
json.dump(doc, open(sys.argv[2], "w"))
PY
set +e
python3 "$MAP" validate "$tmp/dupe.json" --allow-homonym cccc > /dev/null 2> "$tmp/err3"
rc3=$?
set -e
[[ "$rc3" -ne 0 ]] || fail "validate accepted a duplicate uid within one repo"
grep -q 'duplicate uid' "$tmp/err3" || fail "duplicate uid not named: $(cat "$tmp/err3")"

# --- the composite key is what disambiguates: both cccc items survive as distinct --
python3 - "$tmp/fleet.json" <<'PY' || fail "composite-key check failed"
import json, sys
doc = json.load(open(sys.argv[1]))
uids = [i["uid"] for i in doc["items"] if i["id"] == "cccc"]
if sorted(uids) != ["repo-alpha/cccc", "repo-beta/cccc"]:
    print("ERROR: the two cccc items did not survive as distinct uids: %r" % uids)
    sys.exit(1)
PY

echo "PASS: synthetic cross-repo id collision exits non-zero and is loud (id:2bb1 clause b)"
