#!/usr/bin/env bash
# (no `# roadmap:` header — this is a defect fix under TODO id:b7f4, which has no ROADMAP
#  entry. Its failures therefore ALWAYS count; there is no expected-red escape.)
#
# id:b7f4 — a REVIEW_ME box anchored to an id that NO ledger line owns must import
# cleanly.
#
# The defect: SCHEMA.md §2.3 gave the anchored box two shapes (attaches-to-twin /
# standalone-untracked) and silently assumed the anchor always finds a twin. A box
# anchored to a MISSING twin kept the bare 4-hex key while carrying `id: null` — exactly
# the state `validate` rejects with "no id but its key is not a synthetic '~' key". One
# such box made an entire real repo (the deep-fidelity pilot) unimportable, because
# `validate` is whole-document and fails the lot.
#
# Hermetic: builds its own ledger tree in mktemp; never reads the pilot repo.
# fails-against: rev 064ae4424967 -- the tree as it stood immediately before the commit that
#   added this test, i.e. the pre-fix tracker/SCHEMA.md, tracker/adapters/adapter_common.py, tracker/fixtures/expected/fleet-collision.json (+5 more). Derived + verified by tests/verify-negative-cases.py.
# fails-against-rev: 064ae4424967 -- tracker/SCHEMA.md tracker/adapters/adapter_common.py tracker/fixtures/expected/fleet-collision.json tracker/fixtures/expected/repo-alpha.json tracker/fixtures/expected/repo-beta.json tracker/ledger-map.py tracker/repo-entity.py tracker/schema/ledger-intermediate.schema.json
# fails-against-assertion: validate REJECTED a document whose only oddity is a dangling review anchor:

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAP="$ROOT/tracker/ledger-map.py"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*"; exit 1; }
pass() { echo "PASS: $*"; }

repo="$tmp/repo"
mkdir -p "$repo"

cat > "$repo/TODO.md" <<'MD'
# TODO

## Current

- [ ] [ROUTINE] a tracked item with a real twin <!-- id:aaaa -->
MD

cat > "$repo/ROADMAP.md" <<'MD'
# ROADMAP

## Queue

- [ ] [ROUTINE] the same item, promoted <!-- id:aaaa -->
MD

# Three boxes: one anchored to a LIVE twin, one anchored to a twin that exists nowhere,
# one with no anchor at all. All three shapes in one document on purpose — the fix must
# not disturb the two that already worked.
cat > "$repo/REVIEW_ME.md" <<'MD'
# REVIEW_ME

- [ ] anchored to a live twin — should attach, never mint a second item <!-- id:aaaa -->
- [ ] anchored to an id no ledger owns — the id:b7f4 case <!-- id:bbbb -->
- [ ] no anchor at all — the standalone case
MD

# Same defect through the OTHER anchor spelling, and from an ARCHIVE file (which is where
# the real instance lived — an archived box outliving its ledger line).
cat > "$repo/REVIEW_ME.archive.md" <<'MD'
# REVIEW_ME archive

- [x] archived box pointing at a vanished roadmap item <!-- roadmap:cccc -->
MD

# --- 1. import + validate must both succeed -----------------------------------------
python3 "$MAP" import danglerepo "$repo" > "$tmp/doc.json" 2> "$tmp/import.err" \
  || fail "import exited non-zero: $(cat "$tmp/import.err")"
python3 "$MAP" validate "$tmp/doc.json" > "$tmp/val.out" 2> "$tmp/val.err" \
  || fail "validate REJECTED a document whose only oddity is a dangling review anchor: $(cat "$tmp/val.err")"
grep -q 'no id but its key is not a synthetic' "$tmp/val.err" \
  && fail "the id:b7f4 error is still emitted"

# --- 2. the policy is the documented one, not merely 'no crash' ---------------------
python3 - "$tmp/doc.json" <<'PY' || fail "dangling-anchor policy check failed"
import json, sys

doc = json.load(open(sys.argv[1]))
items = {i["uid"]: i for i in doc["items"]}
ok = True

def err(m):
    global ok
    print("ERROR: %s" % m)
    ok = False

# (a) the LIVE anchor still attaches to its twin and mints no second item
twin = items.get("danglerepo/aaaa")
if twin is None:
    err("the tracked item danglerepo/aaaa vanished")
else:
    if twin["review_status"] != "open":
        err("the live-anchored box did not set review_status on its twin")
    if "has:review-box" not in twin["labels"]:
        err("the live-anchored box did not label its twin has:review-box")
    if twin["kind"] != "ledger_item":
        err("the twin was turned into a review_box")

# (b) NO item may be keyed on a dangling anchor token
for tok in ("bbbb", "cccc"):
    if "danglerepo/%s" % tok in items:
        err("a dangling anchor %r still minted a 4-hex-keyed item — that is the defect" % tok)

# (c) each dangling box is a standalone UNTRACKED review_box with a synthetic key,
#     carrying the anchor it could not resolve
for tok in ("bbbb", "cccc"):
    lab = "dangling-anchor:%s" % tok
    found = [i for i in doc["items"] if lab in i["labels"]]
    if len(found) != 1:
        err("expected exactly 1 item labelled %r, got %d" % (lab, len(found)))
        continue
    it = found[0]
    key = it["uid"].split("/", 1)[1]
    if it["id"] is not None:
        err("%s carries id=%r — the anchor must NOT be promoted to a real id "
            "(that would fabricate a tracked item for an id no ledger owns)" % (it["uid"], it["id"]))
    if it["identity"] != "untracked":
        err("%s identity=%r, expected untracked" % (it["uid"], it["identity"]))
    if not key.startswith("~"):
        err("%s key %r is not the synthetic '~' key the policy requires" % (it["uid"], key))
    if it["kind"] != "review_box":
        err("%s kind=%r, expected review_box" % (it["uid"], it["kind"]))
    if it["assignee"] != "human":
        err("%s assignee=%r, expected human" % (it["uid"], it["assignee"]))
    if it["derived_status"] not in ("needs-decision", "done"):
        err("%s derived_status=%r" % (it["uid"], it["derived_status"]))

# (d) the loss is LOUD, per file+line (id:4347 no-silent-swallow)
n = doc["unmapped_counts"].get("review-box-dangling-anchor", 0)
if n != 2:
    err("expected 2 review-box-dangling-anchor reports, got %d (counts=%r)"
        % (n, doc["unmapped_counts"]))
for e in doc["unmapped"]:
    if e["construct"] == "review-box-dangling-anchor" and not (e["file"] and e["line"]):
        err("a dangling-anchor report carries no file/line")

# (e) the unanchored box is untouched by the fix
if doc["unmapped_counts"].get("review-box-unanchored", 0) != 1:
    err("the plain unanchored box stopped being reported as review-box-unanchored")

sys.exit(0 if ok else 1)
PY
pass "a REVIEW_ME box anchored to a missing twin imports as standalone-untracked and validates"

# --- 3. the construct is documented (SCHEMA.md is the prose contract) ---------------
grep -qF -- 'review-box-dangling-anchor' "$ROOT/tracker/SCHEMA.md" \
  || fail "review-box-dangling-anchor is reported by the mapper but undocumented in tracker/SCHEMA.md"
pass "the new loud-lossy construct is documented in SCHEMA.md"

# --- 4. non-vacuity: an anchor whose twin DOES exist must still attach --------------
# If the fix re-keyed every anchored box, section 2(a) would still pass on the dangling
# ones while the whole attach-when-anchored policy quietly died. Drive it separately.
solo="$tmp/solo"
mkdir -p "$solo"
printf '# TODO\n\n- [ ] [ROUTINE] twin <!-- id:dddd -->\n' > "$solo/TODO.md"
printf '# REVIEW_ME\n\n- [ ] box on the twin <!-- id:dddd -->\n' > "$solo/REVIEW_ME.md"
python3 "$MAP" import solo "$solo" > "$tmp/solo.json" 2>/dev/null || fail "solo import failed"
python3 - "$tmp/solo.json" <<'PY' || fail "an anchored box with a LIVE twin stopped attaching"
import json, sys
doc = json.load(open(sys.argv[1]))
uids = [i["uid"] for i in doc["items"]]
assert uids == ["solo/dddd"], "expected exactly the twin item, got %r" % uids
assert doc["items"][0]["review_status"] == "open", doc["items"][0]
assert doc["unmapped_counts"].get("review-box-dangling-anchor", 0) == 0, doc["unmapped_counts"]
PY
pass "attach-when-anchored still holds when the twin exists (the fix is not a blanket re-key)"

echo "ALL PASS: REVIEW_ME anchors to a missing twin (id:b7f4)"
