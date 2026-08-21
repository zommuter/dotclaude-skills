#!/usr/bin/env bash
# (no `# roadmap:` header — this specs TODO id:ca24, which has no ROADMAP entry.
#  Its failures therefore ALWAYS count; there is no expected-red escape.)
#
# id:ca24 — `ledger-map.py validate` adjudicates class-A cross-repo homonyms with an
# explicit per-token ALLOW-LIST, never a blanket boolean (owner-decided 2026-08-10,
# superseding the `--allow-homonyms` boolean shipped by id:2bb1).
#
# Contract asserted here:
#   * a document with one LISTED and one UNLISTED homonym exits non-zero, naming ONLY
#     the unlisted token as an ERROR;
#   * the bare boolean `--allow-homonyms` is REJECTED, so the blanket-downgrade path
#     cannot be reintroduced by habit;
#   * no wildcard/"all" entry can stand in for adjudication.
# Rationale: id:94ce's recurring fleet import must not be able to switch class A off
# wholesale — a NEW homonym must still fail loudly.
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
python3 "$MAP" merge "$tmp/alpha.json" "$tmp/beta.json" > "$tmp/merged.json" \
  || fail "merge exited non-zero"

# Derive a TWO-class-A-homonym fixture from the real import: drop the class-B material
# (the `cafe` items and the routed:cafe edge) so the only collisions left are class A,
# then clone the `cccc` pair into a second homonym `beef`.
python3 - "$tmp/merged.json" "$tmp/fleet.json" <<'PY' || fail "fixture derivation failed"
import copy, json, sys
doc = json.load(open(sys.argv[1]))
items = [i for i in doc["items"] if i.get("id") != "cafe"]
for it in items:
    it["links"] = [l for l in it.get("links", []) if l.get("token") != "cafe"]
    it["blocked_by"] = [b for b in it.get("blocked_by", []) if not b.endswith("/cafe")]
    if (it.get("parent") or "").endswith("/cafe"):
        it["parent"] = None
clones = []
for it in items:
    if it.get("id") == "cccc":
        c = copy.deepcopy(it)
        c["id"] = "beef"
        c["uid"] = "%s/beef" % c["repo"]
        c["links"] = []
        c["blocked_by"] = []
        c["parent"] = None
        clones.append(c)
if len(clones) != 2:
    print("ERROR: expected two cccc items to clone, got %d" % len(clones)); sys.exit(1)
doc["items"] = items + clones
json.dump(doc, open(sys.argv[2], "w"))
PY

# --- baseline: with NO adjudication both homonyms are fatal ------------------------
set +e
python3 "$MAP" validate "$tmp/fleet.json" > /dev/null 2> "$tmp/none.err"
rc=$?
set -e
[[ "$rc" -eq 3 ]] || fail "unadjudicated homonyms must exit 3, got $rc: $(cat "$tmp/none.err")"
grep -q "ERROR.*'cccc'" "$tmp/none.err" || fail "cccc not fatal by default"
grep -q "ERROR.*'beef'" "$tmp/none.err" || fail "beef not fatal by default"

# --- THE CONTRACT: one listed + one unlisted -> non-zero, naming ONLY the unlisted --
set +e
python3 "$MAP" validate "$tmp/fleet.json" --allow-homonym cccc > /dev/null 2> "$tmp/one.err"
rc=$?
set -e
[[ "$rc" -eq 3 ]] || fail "an UNLISTED homonym must still exit 3, got $rc: $(cat "$tmp/one.err")"
grep -q "ERROR.*'beef'" "$tmp/one.err" \
  || fail "the unlisted token beef is not named as an ERROR: $(cat "$tmp/one.err")"
if grep -q "'cccc'" < <(grep '^ERROR' "$tmp/one.err") ; then
  fail "the ADJUDICATED token cccc is still reported as an ERROR: $(cat "$tmp/one.err")"
fi
grep -qi "WARN.*'cccc'" "$tmp/one.err" \
  || fail "the adjudicated homonym cccc must stay VISIBLE as a WARN: $(cat "$tmp/one.err")"

# --- adjudicating both is what makes the document pass -----------------------------
set +e
python3 "$MAP" validate "$tmp/fleet.json" --allow-homonym cccc --allow-homonym beef \
  > /dev/null 2> "$tmp/both.err"
rc=$?
set -e
[[ "$rc" -eq 0 ]] || fail "both homonyms adjudicated should validate OK, got $rc: $(cat "$tmp/both.err")"

# --- the file form carries the same semantics --------------------------------------
printf '# adjudicated 2026-08-10\ncccc\n\nbeef  # composite key disambiguates\n' > "$tmp/allow.txt"
set +e
python3 "$MAP" validate "$tmp/fleet.json" --allow-homonym-file "$tmp/allow.txt" \
  > /dev/null 2> "$tmp/file.err"
rc=$?
set -e
[[ "$rc" -eq 0 ]] || fail "--allow-homonym-file did not adjudicate both tokens: $(cat "$tmp/file.err")"

printf 'cccc\n' > "$tmp/partial.txt"
set +e
python3 "$MAP" validate "$tmp/fleet.json" --allow-homonym-file "$tmp/partial.txt" \
  > /dev/null 2> "$tmp/partial.err"
rc=$?
set -e
[[ "$rc" -eq 3 ]] || fail "--allow-homonym-file listing only cccc must still fail on beef"
grep -q "ERROR.*'beef'" "$tmp/partial.err" || fail "beef not named via the file form"

# --- THE BOOLEAN IS GONE: bare --allow-homonyms must be REJECTED -------------------
for bad_flag in "--allow-homonyms" "--allow-homonyms=1"; do
  set +e
  python3 "$MAP" validate "$tmp/fleet.json" $bad_flag > /dev/null 2> "$tmp/bool.err"
  rc=$?
  set -e
  [[ "$rc" -ne 0 ]] || fail "$bad_flag was ACCEPTED — the blanket-downgrade path is back"
  grep -qi 'unrecognized\|invalid\|error' "$tmp/bool.err" \
    || fail "$bad_flag rejected without an explanation: $(cat "$tmp/bool.err")"
done
# ...and it certainly must not downgrade anything.
set +e
python3 "$MAP" validate "$tmp/fleet.json" --allow-homonyms cccc > /dev/null 2> "$tmp/bool2.err"
rc=$?
set -e
[[ "$rc" -ne 0 ]] || fail "--allow-homonyms cccc was accepted as a blanket boolean"

# --- no wildcard may stand in for per-token adjudication ---------------------------
for wild in '*' 'all' 'ALL' '.*' 'cc*'; do
  set +e
  python3 "$MAP" validate "$tmp/fleet.json" --allow-homonym "$wild" > /dev/null 2> "$tmp/wild.err"
  rc=$?
  set -e
  [[ "$rc" -ne 0 ]] || fail "--allow-homonym '$wild' was accepted as a blanket downgrade"
done

# --- a stale adjudication is surfaced, not silently kept ---------------------------
set +e
python3 "$MAP" validate "$tmp/fleet.json" --allow-homonym cccc --allow-homonym beef \
  --allow-homonym 0f0f > /dev/null 2> "$tmp/stale.err"
rc=$?
set -e
[[ "$rc" -eq 0 ]] || fail "a stale allow-list entry must not be fatal, got $rc"
grep -qi "stale" "$tmp/stale.err" || fail "stale allow-list entry 0f0f not surfaced: $(cat "$tmp/stale.err")"

# --- the help text must not advertise a blanket knob -------------------------------
python3 "$MAP" validate --help > "$tmp/help" 2>&1 || fail "validate --help exited non-zero"
grep -q -- "--allow-homonym " "$tmp/help" || fail "--allow-homonym missing from validate --help"
if grep -q -- "--allow-homonyms\b" "$tmp/help"; then fail "help still advertises --allow-homonyms"; fi

echo "PASS: class-A homonyms are adjudicated per token; the blanket boolean is gone (id:ca24)"
