#!/usr/bin/env bash
# (no `# roadmap:` header — this specs TODO id:2bb1, which has no ROADMAP entry.
#  Its failures therefore ALWAYS count.)
#
# id:2bb1 supporting contract: the three artifacts must not drift apart.
#   1. the committed fixture JSON is byte-reproducible from the fixture ledgers
#      (determinism is a prerequisite for id:94ce's "two consecutive runs, zero diffs")
#   2. the published JSON Schema's enums/required keys agree with the mapper's
#   3. tracker/SCHEMA.md documents every construct the mapper actually reports
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TRK="$ROOT/tracker"
MAP="$TRK/ledger-map.py"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*"; exit 1; }

cd "$TRK"

# --- 1. determinism + golden-fixture agreement -------------------------------------
for repo in repo-alpha repo-beta; do
  python3 "$MAP" import "$repo" "fixtures/$repo" > "$tmp/$repo.a.json" 2>/dev/null || fail "import $repo failed"
  python3 "$MAP" import "$repo" "fixtures/$repo" > "$tmp/$repo.b.json" 2>/dev/null || fail "import $repo failed (2nd)"
  cmp -s "$tmp/$repo.a.json" "$tmp/$repo.b.json" \
    || fail "import $repo is NOT deterministic across two runs"
  cmp -s "$tmp/$repo.a.json" "fixtures/expected/$repo.json" \
    || fail "fixtures/expected/$repo.json is stale — regenerate it (see tracker/SCHEMA.md §6)"
done
python3 "$MAP" merge "$tmp/repo-alpha.a.json" "$tmp/repo-beta.a.json" > "$tmp/fleet.json" || fail "merge failed"
cmp -s "$tmp/fleet.json" "fixtures/expected/fleet-collision.json" \
  || fail "fixtures/expected/fleet-collision.json is stale — regenerate it"

# --- 2. schema <-> mapper cross-check ---------------------------------------------
python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$TRK/schema/ledger-intermediate.schema.json" \
  || fail "schema/ledger-intermediate.schema.json is not valid JSON"

# validate performs the cross-check itself; a drift there is a fatal ERROR.
python3 "$MAP" validate "fixtures/expected/repo-alpha.json" > /dev/null 2> "$tmp/err" \
  || fail "validate failed on the golden fixture: $(cat "$tmp/err")"
if grep -qi 'schema/mapper' "$tmp/err"; then fail "schema/mapper drift reported: $(cat "$tmp/err")"; fi

# A deliberately mutated schema MUST be caught — the cross-check has to be able to fail.
mut="$tmp/mut"
mkdir -p "$mut/schema"
cp "$MAP" "$mut/ledger-map.py"
python3 - "$TRK/schema/ledger-intermediate.schema.json" "$mut/schema/ledger-intermediate.schema.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
s["$defs"]["item"]["properties"]["todo_status"]["enum"] = ["open", "done"]   # drop `absent`
json.dump(s, open(sys.argv[2], "w"))
PY
set +e
python3 "$mut/ledger-map.py" validate "$TRK/fixtures/expected/repo-alpha.json" > /dev/null 2> "$tmp/mut.err"
rcm=$?
set -e
[[ "$rcm" -ne 0 ]] || fail "a mutated JSON Schema (enum missing 'absent') was NOT caught — the cross-check is vacuous"
grep -qi 'enum drift' "$tmp/mut.err" || fail "mutated schema rejected without naming the enum drift: $(cat "$tmp/mut.err")"

# --- 3. every reported construct is documented in SCHEMA.md ------------------------
constructs="$(python3 - <<'PY'
import json
docs = [json.load(open("fixtures/expected/%s.json" % r)) for r in ("repo-alpha", "repo-beta")]
seen = set()
for d in docs:
    seen.update(d["unmapped_counts"])
print("\n".join(sorted(seen)))
PY
)"
[[ -n "$constructs" ]] || fail "the fixtures report no loud-lossy constructs at all"
while read -r c; do
  [[ -z "$c" ]] && continue
  grep -qF -- "$c" "$TRK/SCHEMA.md" \
    || fail "construct '$c' is reported by the mapper but not documented in tracker/SCHEMA.md"
done <<<"$constructs"

# The full construct vocabulary the mapper can emit must also be documented, not just
# the subset the fixtures happen to trip.
while read -r c; do
  [[ -z "$c" ]] && continue
  grep -qF -- "$c" "$TRK/SCHEMA.md" \
    || fail "construct '$c' can be emitted by ledger-map.py but is undocumented in SCHEMA.md"
done < <(grep -oE 'report\.add\(\s*"[a-z-]+"' "$MAP" | grep -oE '"[a-z-]+"' | tr -d '"' | sort -u)

echo "PASS: golden fixture reproducible, schema<->mapper in sync, constructs documented (id:2bb1)"
