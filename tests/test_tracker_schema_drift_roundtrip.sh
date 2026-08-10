#!/usr/bin/env bash
# (no `# roadmap:` header — this specs TODO id:2bb1, which has no ROADMAP entry.
#  Its failures therefore ALWAYS count; there is no expected-red escape.)
#
# id:2bb1 contract, clause (a): a fixture ledger with known cross-ledger drift
# round-trips through the intermediate JSON with BOTH statuses preserved.
#
# The whole point of the schema is that `todo_status` and `roadmap_status` are never
# collapsed into one status — a single-status schema silently launders the drift that
# `meeting/orphan-scan.sh --cross-ledger` exists to report (meeting 2026-08-10, D2 as
# amended by --fabled finding 5). This test drives the drift in BOTH directions and
# asserts the projection back out matches the fixture ledgers' actual checkbox lines.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAP="$ROOT/tracker/ledger-map.py"
FIX="$ROOT/tracker/fixtures/repo-alpha"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$MAP" ]] || fail "missing mapper $MAP"
[[ -d "$FIX" ]] || fail "missing fixture ledger $FIX"

# --- the drift the fixture ledgers actually carry, read from the markdown itself ----
# Deliberately re-derived by grep rather than trusted from the JSON: the test must know
# the ground truth independently of the thing under test.
todo_1111="$(grep -c '^- \[ \].*<!-- id:1111 -->' "$FIX/TODO.md")"
road_1111="$(grep -c '^- \[x\].*<!-- id:1111 -->' "$FIX/ROADMAP.md")"
todo_2222="$(grep -c '^- \[x\].*<!-- id:2222 -->' "$FIX/TODO.md")"
road_2222="$(grep -c '^- \[ \].*<!-- id:2222 -->' "$FIX/ROADMAP.md")"
[[ "$todo_1111" == 1 && "$road_1111" == 1 ]] || fail "fixture lost its id:1111 drift (open in TODO, done in ROADMAP)"
[[ "$todo_2222" == 1 && "$road_2222" == 1 ]] || fail "fixture lost its id:2222 drift (done in TODO, open in ROADMAP)"

# --- import -----------------------------------------------------------------------
cd "$ROOT/tracker"
python3 "$MAP" import repo-alpha fixtures/repo-alpha > "$tmp/doc.json" 2> "$tmp/import.err" \
  || fail "import exited non-zero: $(cat "$tmp/import.err")"

# The loud-lossy report must be on stderr, with counts (id:4347 no-silent-swallow).
grep -q 'loud-lossy report' "$tmp/import.err" \
  || fail "import printed no loud-lossy report to stderr; got: $(cat "$tmp/import.err")"

# --- validate ---------------------------------------------------------------------
python3 "$MAP" validate "$tmp/doc.json" > "$tmp/val.out" 2> "$tmp/val.err" \
  || fail "validate rejected the clean single-repo fixture: $(cat "$tmp/val.err")"

# --- clause (a): BOTH statuses survive, in BOTH directions ------------------------
rs="$(python3 "$MAP" render-status "$tmp/doc.json")"

grep -qP '^repo-alpha/1111\tTODO:\[ \]\tROADMAP:\[x\]\tREVIEW:-\tdrift=1' <<<"$rs" \
  || fail "id:1111 lost its drift; render-status said: $(grep '1111' <<<"$rs" || echo '<absent>')"
grep -qP '^repo-alpha/2222\tTODO:\[x\]\tROADMAP:\[ \]\tREVIEW:-\tdrift=1' <<<"$rs" \
  || fail "id:2222 lost its drift; render-status said: $(grep '2222' <<<"$rs" || echo '<absent>')"

# Non-drifting items must NOT be flagged, or the flag is worthless.
grep -qP '^repo-alpha/3333\tTODO:\[ \]\tROADMAP:\[ \].*drift=0' <<<"$rs" || fail "id:3333 (open/open) wrongly flagged as drift"
grep -qP '^repo-alpha/4444\tTODO:\[x\]\tROADMAP:\[x\].*drift=0' <<<"$rs" || fail "id:4444 (done/done) wrongly flagged as drift"

# `absent` must be distinct from `open`: a TODO-only item is not "open in ROADMAP".
grep -qP '^repo-alpha/5555\tTODO:\[ \]\tROADMAP:-.*drift=0' <<<"$rs" || fail "id:5555 (TODO-only) did not render roadmap_status=absent"
grep -qP '^repo-alpha/eeee\tTODO:-\tROADMAP:\[ \].*drift=0' <<<"$rs" || fail "id:eeee (ROADMAP-only) did not render todo_status=absent"

# --- the collapse must be structurally impossible, not merely absent --------------
# An OPEN view always beats a DONE view: a drifting item is never rendered done.
python3 - "$tmp/doc.json" <<'PY' || fail "per-view status integrity check failed"
import json, sys
doc = json.load(open(sys.argv[1]))
items = {i["uid"]: i for i in doc["items"]}
ok = True
for uid in ("repo-alpha/1111", "repo-alpha/2222"):
    it = items[uid]
    if not it["drift"]:
        print("ERROR: %s: drift flag not set" % uid); ok = False
    if it["derived_status"] == "done":
        print("ERROR: %s: derived_status=done while the views disagree" % uid); ok = False
    if it["todo_status"] == it["roadmap_status"]:
        print("ERROR: %s: the two views were collapsed into one value" % uid); ok = False
# there is no single `status` field to collapse into
for it in doc["items"]:
    if "status" in it:
        print("ERROR: %s carries a collapsed `status` field" % it["uid"]); ok = False
sys.exit(0 if ok else 1)
PY

# --- a hand-corrupted document (drift silently collapsed) must be REJECTED ---------
python3 - "$tmp/doc.json" "$tmp/collapsed.json" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1]))
for it in doc["items"]:
    if it["uid"] == "repo-alpha/1111":
        it["roadmap_status"] = it["todo_status"]   # collapse, leave drift=True
json.dump(doc, open(sys.argv[2], "w"))
PY
if python3 "$MAP" validate "$tmp/collapsed.json" > /dev/null 2> "$tmp/collapsed.err"; then
  fail "validate ACCEPTED a document whose drift flag contradicts its per-view statuses"
fi
grep -q 'never be collapsed' "$tmp/collapsed.err" \
  || fail "validate rejected the collapsed document without naming the collapse: $(cat "$tmp/collapsed.err")"

# --- id-less lines and REVIEW_ME boxes have an EXPLICIT policy, not a silent skip ---
python3 - "$tmp/doc.json" <<'PY' || fail "id-less / review-box policy check failed"
import json, sys
doc = json.load(open(sys.argv[1]))
ok = True
counts = doc["unmapped_counts"]
for k in ("id-less-item", "review-box-unanchored", "legacy-hands-unresolved", "untagged-lane", "unknown-marker"):
    if counts.get(k, 0) < 1:
        print("ERROR: loud-lossy report is missing construct %r (counts=%r)" % (k, counts)); ok = False

untracked = [i for i in doc["items"] if i["identity"] == "untracked"]
if not untracked:
    print("ERROR: no id-less line was imported as identity=untracked (silent skip?)"); ok = False
for i in untracked:
    if i["id"] is not None:
        print("ERROR: %s is untracked but carries an id" % i["uid"]); ok = False
    if not i["uid"].split("/", 1)[1].startswith("~"):
        print("ERROR: %s untracked key is not '~'-prefixed" % i["uid"]); ok = False

boxes = [i for i in doc["items"] if i["kind"] == "review_box"]
if len(boxes) != 2:
    print("ERROR: expected 2 standalone review_box items, got %d" % len(boxes)); ok = False
for b in boxes:
    if b["assignee"] != "human":
        print("ERROR: %s review_box assignee=%r, expected human" % (b["uid"], b["assignee"])); ok = False

# the ANCHORED box attaches to id:3333 rather than minting a second item
it = {i["uid"]: i for i in doc["items"]}["repo-alpha/3333"]
if it["review_status"] != "open":
    print("ERROR: anchored REVIEW_ME box did not set review_status on repo-alpha/3333"); ok = False
if "has:review-box" not in it["labels"]:
    print("ERROR: repo-alpha/3333 is missing the has:review-box label"); ok = False
if it["kind"] != "ledger_item":
    print("ERROR: repo-alpha/3333 was turned into a review_box"); ok = False
sys.exit(0 if ok else 1)
PY

echo "PASS: cross-ledger drift round-trips with both statuses preserved (id:2bb1 clause a)"
