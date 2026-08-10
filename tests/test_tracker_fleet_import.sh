#!/usr/bin/env bash
# (no `# roadmap:` header — this specs TODO id:94ce, which has no ROADMAP entry.
#  Its failures therefore ALWAYS count.)
#
# id:94ce — the fleet driver: relay.toml own-set authority, pinned-SHA reads, upserts,
# tombstones, loud-lossy counts, and the two headline contract clauses:
#
#   (A) two consecutive runs over an unchanged fleet produce zero diffs
#   (B) a mid-run ledger edit cannot yield torn state
#
# Hermetic: a synthetic fleet of throwaway git repos under mktemp -d, its own relay.toml,
# its own state file. No network, no ~/.claude, none of the real 60 repos.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMPORT="$ROOT/tracker/fleet-import.sh"
STATEPY="$ROOT/tracker/fleet-state.py"
# shellcheck source=lib/assert-repo-unchanged.sh
source "$ROOT/tests/lib/assert-repo-unchanged.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*"; exit 1; }

# --- synthetic fleet -------------------------------------------------------------------
FLEET="$tmp/fleet"
mkdir -p "$FLEET"
export SRC_DIR="$FLEET"
export RELAY_TOML="$tmp/relay.toml"
STATE="$tmp/state.json"
OUT="$tmp/fleet-doc.json"
ALLOW="$tmp/allow.txt"
: > "$ALLOW"

g() { local d="$1"; shift; git -C "$d" -c user.email=t@example.invalid -c user.name=t \
        -c core.hooksPath=/dev/null -c commit.gpgsign=false "$@"; }

mkrepo() {   # $1=dir  $2=TODO.md content
  mkdir -p "$1"
  git init -q "$1"
  printf '%s\n' "$2" > "$1/TODO.md"
  g "$1" add -A
  g "$1" commit -q --no-verify -m "init"
}

mkrepo "$FLEET/repo-alpha" "# TODO

## Current

- [ ] [ROUTINE] alpha one <!-- id:1111 -->
- [x] [HARD] alpha two <!-- id:2222 -->
- [ ] alpha untagged line with no id"

# repo-beta lives OUTSIDE \$SRC_DIR on purpose, reachable only via the \`# path:\`
# comment override — so a \`~/src/*\` glob could not find it.
BETA="$tmp/elsewhere/repo-beta"
mkrepo "$BETA" "# TODO

## Current

- [ ] [MECHANICAL] beta one <!-- id:3333 -->"

cat > "$RELAY_TOML" <<EOF
[repos.repo-alpha]
classification = "own"

[repos.repo-beta]
# path: $BETA
classification = "own"

[repos.repo-paused]
classification = "own"
paused = true
path = "$tmp/nope-paused"

[repos.repo-foreign]
classification = "foreign"
path = "$tmp/nope-foreign"
EOF

run() { "$IMPORT" --state "$STATE" --out "$OUT" --allowlist-file "$ALLOW" "$@"; }

# --- 0. purity: a read-only driver must not mutate any scanned repo --------------------
snap_a="$tmp/snap.alpha"; snap_b="$tmp/snap.beta"
repo_state_snapshot "$FLEET/repo-alpha" > "$snap_a"
repo_state_snapshot "$BETA" > "$snap_b"

run > "$tmp/run1.out" 2> "$tmp/run1.err" || fail "first run failed: $(cat "$tmp/run1.err")"

assert_repo_unchanged "$FLEET/repo-alpha" "$snap_a" || fail "fleet-import.sh MUTATED repo-alpha"
assert_repo_unchanged "$BETA" "$snap_b" || fail "fleet-import.sh MUTATED repo-beta"

# --- 1. relay.toml is the authority: own+unpaused only, `# path:` honoured -------------
python3 - "$STATE" <<'PY' || fail "repo set is not the relay.toml own-set"
import json, sys
st = json.load(open(sys.argv[1]))
names = sorted(r["repo"] for r in st["repos"])
assert names == ["repo-alpha", "repo-beta"], names
assert st["repo_errors"] == [], st["repo_errors"]
paths = {r["repo"]: r["path"] for r in st["repos"]}
assert "elsewhere" in paths["repo-beta"], paths           # `# path:` override honoured
assert all(r["head_sha"] for r in st["repos"]), "no pinned head_sha recorded"
uids = sorted(r["uid"] for r in st["items"])
assert "repo-alpha/1111" in uids and "repo-beta/3333" in uids, uids
PY

grep -q 'id-less-item' "$tmp/run1.err" || fail "loud-lossy report did not name id-less-item"
grep -qE 'loud-lossy report \(construct=count' "$tmp/run1.err" \
  || fail "no loud-lossy count line on stderr"

# --- 2. CONTRACT (A): two consecutive runs over an unchanged fleet, zero diffs ---------
cp "$STATE" "$tmp/state.run1"; cp "$OUT" "$tmp/out.run1"
run > /dev/null 2>&1 || fail "second run failed"
cmp -s "$tmp/state.run1" "$STATE" || { diff -u "$tmp/state.run1" "$STATE" | head -40; \
  fail "CONTRACT (A) VIOLATED: two runs over an unchanged fleet differ (state)"; }
cmp -s "$tmp/out.run1" "$OUT" || fail "CONTRACT (A) VIOLATED: fleet document differs across runs"

# --- 3. an UNCOMMITTED working-tree edit is invisible (reads come from the commit) -----
echo '- [ ] [ROUTINE] dirty uncommitted <!-- id:9999 -->' >> "$FLEET/repo-alpha/TODO.md"
run > /dev/null 2>&1 || fail "run with a dirty worktree failed"
cmp -s "$tmp/state.run1" "$STATE" \
  || fail "an UNCOMMITTED edit changed the import — content is being read from the worktree, not the pinned commit"
g "$FLEET/repo-alpha" checkout -- TODO.md

# --- 4. CONTRACT (B): a mid-run COMMIT lands after the pin ⇒ invisible to that run -----
# TRACKER_IMPORT_PIN_HOOK fires between the pin phase and the first content read, so this
# is a genuine mid-run ledger edit, not a simulation of one.
sha_before="$(git -C "$FLEET/repo-alpha" rev-parse HEAD)"
hook="printf '%s\n' '- [ ] [ROUTINE] torn state <!-- id:abcd -->' >> '$FLEET/repo-alpha/TODO.md'; \
git -C '$FLEET/repo-alpha' -c user.email=t@e -c user.name=t -c core.hooksPath=/dev/null add -A; \
git -C '$FLEET/repo-alpha' -c user.email=t@e -c user.name=t -c core.hooksPath=/dev/null commit -q --no-verify -m midrun"
TRACKER_IMPORT_PIN_HOOK="$hook" run > /dev/null 2> "$tmp/run4.err" || fail "mid-run-edit run failed"

python3 - "$STATE" "$sha_before" <<'PY' || fail "CONTRACT (B) VIOLATED: torn state"
import json, sys
st = json.load(open(sys.argv[1]))
uids = {r["uid"] for r in st["items"]}
assert "repo-alpha/abcd" not in uids, "an item committed AFTER the pin leaked into the run"
sha = {r["repo"]: r["head_sha"] for r in st["repos"]}["repo-alpha"]
assert sha == sys.argv[2], "head_sha %s is not the PINNED sha %s" % (sha, sys.argv[2])
PY
cmp -s "$tmp/state.run1" "$STATE" \
  || fail "CONTRACT (B) VIOLATED: a mid-run commit perturbed the state document"

# the very next run DOES see it — the edit is deferred, not lost
run > /dev/null 2>&1 || fail "follow-up run failed"
python3 -c '
import json,sys
st=json.load(open(sys.argv[1]))
assert "repo-alpha/abcd" in {r["uid"] for r in st["items"]}, "the mid-run edit was lost, not deferred"
' "$STATE" || fail "mid-run edit never appeared on the following run"

# --- 5. upsert on (repo,id): a changed item is rewritten, its neighbours are carried ---
cp "$STATE" "$tmp/state.pre-upsert"
sed -i 's/- \[ \] \[ROUTINE\] alpha one/- [x] [ROUTINE] alpha one/' "$FLEET/repo-alpha/TODO.md"
g "$FLEET/repo-alpha" commit -q --no-verify -am "close 1111"
run > /dev/null 2>&1 || fail "upsert run failed"
python3 - "$tmp/state.pre-upsert" "$STATE" <<'PY' || fail "upsert did not behave"
import json, sys
a = {r["uid"]: r for r in json.load(open(sys.argv[1]))["items"]}
b = {r["uid"]: r for r in json.load(open(sys.argv[2]))["items"]}
assert set(a) == set(b), (set(a) ^ set(b))
assert a["repo-alpha/1111"]["item"]["todo_status"] == "open"
assert b["repo-alpha/1111"]["item"]["todo_status"] == "done", "checkbox change not upserted"
assert a["repo-alpha/1111"]["content_hash"] != b["repo-alpha/1111"]["content_hash"]
assert a["repo-alpha/1111"]["changed_at_sha"] != b["repo-alpha/1111"]["changed_at_sha"], \
    "changed_at_sha did not advance on a real change"
# an untouched neighbour in the SAME repo must be carried byte-identically
assert a["repo-alpha/2222"] == b["repo-alpha/2222"], "an unchanged item was rewritten"
assert a["repo-beta/3333"] == b["repo-beta/3333"], "an unchanged item in another repo was rewritten"
PY

# --- 6. tombstones: an item that vanishes is tombstoned, and stays stable --------------
grep -v 'id:2222' "$FLEET/repo-alpha/TODO.md" > "$tmp/t" && mv "$tmp/t" "$FLEET/repo-alpha/TODO.md"
g "$FLEET/repo-alpha" commit -q --no-verify -am "drop 2222"
run > /dev/null 2> "$tmp/run6.err" || fail "tombstone run failed"
grep -q 'tombstoned: repo-alpha/2222' "$tmp/run6.err" || fail "tombstone not reported loudly"
python3 -c '
import json,sys
r = {x["uid"]: x for x in json.load(open(sys.argv[1]))["items"]}["repo-alpha/2222"]
assert r["state"] == "tombstoned", r
assert r["tombstoned_at_sha"], "no sha recorded for the tombstone"
assert r["item"]["id"] == "2222", "the last-known item body was dropped"
' "$STATE" || fail "tombstone record is wrong"
cp "$STATE" "$tmp/state.tomb"
run > /dev/null 2>&1 || fail "post-tombstone run failed"
cmp -s "$tmp/state.tomb" "$STATE" || fail "a tombstone is not idempotent across runs"

# resurrection
printf '%s\n' '- [ ] [HARD] alpha two <!-- id:2222 -->' >> "$FLEET/repo-alpha/TODO.md"
g "$FLEET/repo-alpha" commit -q --no-verify -am "restore 2222"
run > /dev/null 2> "$tmp/run6b.err" || fail "resurrection run failed"
grep -q 'resurrected: repo-alpha/2222' "$tmp/run6b.err" || fail "resurrection not reported"
python3 -c '
import json,sys
r = {x["uid"]: x for x in json.load(open(sys.argv[1]))["items"]}["repo-alpha/2222"]
assert r["state"] == "live" and "tombstoned_at_sha" not in r, r
' "$STATE" || fail "resurrected record still carries a tombstone"

# --- 7. a repo ERROR is loud, non-fatal, and tombstones NOTHING ------------------------
cp "$STATE" "$tmp/state.pre-error"
mv "$BETA" "$tmp/elsewhere/moved-away"
set +e; run > /dev/null 2> "$tmp/run7.err"; rc=$?; set -e
[[ "$rc" -eq 4 ]] || fail "a repo error should exit 4, got $rc"
grep -q 'repo-error \[repo-beta\]' "$tmp/run7.err" || fail "repo error not reported loudly"
python3 - "$tmp/state.pre-error" "$STATE" <<'PY' || fail "an errored repo's items were disturbed"
import json, sys
a = {r["uid"]: r for r in json.load(open(sys.argv[1]))["items"]}
b = {r["uid"]: r for r in json.load(open(sys.argv[2]))["items"]}
assert a["repo-beta/3333"] == b["repo-beta/3333"], \
    "a repo that FAILED to import had its items rewritten/tombstoned — one transient " \
    "failure must never mass-tombstone a repo"
assert b["repo-beta/3333"]["state"] == "live"
PY
grep -q 'retained-absent-repo' "$tmp/run7.err" || fail "retained-absent-repo not reported"
mv "$tmp/elsewhere/moved-away" "$BETA"

# --- 8. a corrupt relay.toml aborts LOUDLY and writes nothing (never an empty fleet) ---
cp "$STATE" "$tmp/state.pre-corrupt"
cp "$RELAY_TOML" "$tmp/relay.toml.good"
printf '%s\n' '[repos.broken' >> "$RELAY_TOML"
set +e; run > /dev/null 2> "$tmp/run8.err"; rc=$?; set -e
[[ "$rc" -eq 3 ]] || fail "a corrupt relay.toml should exit 3, got $rc"
grep -qi 'FAILED to parse relay.toml' "$tmp/run8.err" || fail "corrupt relay.toml not named"
cmp -s "$tmp/state.pre-corrupt" "$STATE" || fail "a corrupt relay.toml still wrote state"
cp "$tmp/relay.toml.good" "$RELAY_TOML"

# --- 9. cross-repo homonym: strict by default, and the allow-list is PER-TOKEN ---------
# Give repo-beta an id that collides with repo-alpha's 1111 (a class-A homonym).
printf '%s\n' '- [ ] [ROUTINE] beta homonym <!-- id:1111 -->' >> "$BETA/TODO.md"
g "$BETA" commit -q --no-verify -am "homonym"
cp "$STATE" "$tmp/state.pre-homonym"
set +e; run > /dev/null 2> "$tmp/run9.err"; rc=$?; set -e
[[ "$rc" -eq 3 ]] || fail "an unadjudicated cross-repo homonym must be FATAL (exit 3), got $rc"
grep -qi 'collision' "$tmp/run9.err" || fail "homonym failure did not name a collision"
cmp -s "$tmp/state.pre-homonym" "$STATE" || fail "a fatal validate still wrote state"

# PINNED to the post-ca24 world (review 2026-08-10). This block previously accepted EITHER
# exit 5 (pre-ca24: only the superseded boolean exists ⇒ refuse) OR exit 0 (post-ca24: the
# allow-list is honoured). id:ca24 has LANDED, so exit 0 is now the ONLY lawful outcome —
# a test that passes in both worlds is precisely what let the singular/plural flag-name
# mismatch reach integration. The exit-5 refusal keeps its own dedicated test at 9b below.
printf '%s\n' '1111' > "$ALLOW"
set +e; run > /dev/null 2> "$tmp/run9b.err"; rc=$?; set -e
[[ "$rc" -eq 0 ]] || fail "id:ca24 has landed, so an ADJUDICATED homonym must pass (exit 0), got $rc: $(cat "$tmp/run9b.err")"
# an UNLISTED second homonym must still be fatal
printf '%s\n' '- [ ] [ROUTINE] beta second homonym <!-- id:3333 -->' >> "$FLEET/repo-alpha/TODO.md"
g "$FLEET/repo-alpha" commit -q --no-verify -am "second homonym"
set +e; run > /dev/null 2> "$tmp/run9c.err"; rc2=$?; set -e
[[ "$rc2" -eq 3 ]] || fail "an UNLISTED homonym passed while 1111 was allow-listed — the allow-list is behaving like a blanket downgrade"
grep -q '3333' "$tmp/run9c.err" || fail "the failure does not name the unlisted token"
g "$FLEET/repo-alpha" reset -q --hard HEAD~1

# --- 9b. the superseded-boolean REFUSAL (exit 5), reached with a STUB ------------------
# The refusal is fail-closed scaffolding: unreachable against this repo's ledger-map.py,
# so it needs a stub to be exercised at all. Without this, the guard is untested dead code
# and could rot silently — which is what the plural-spelling fallbacks it replaced did.
stub_dir="$tmp/stub"; mkdir -p "$stub_dir/tracker"
cp "$ROOT/tracker/fleet-import.sh" "$stub_dir/tracker/"
cp "$ROOT/tracker/fleet-state.py"  "$stub_dir/tracker/"
mkdir -p "$stub_dir/relay/scripts"
cp "$ROOT/relay/scripts/lib-own-repos.sh" "$stub_dir/relay/scripts/"
# The stub is a real (tiny) ledger-map.py: it emits valid documents for import/merge so
# the driver reaches the allow-list step, but advertises ONLY the superseded boolean.
cat > "$stub_dir/tracker/ledger-map.py" <<'STUB'
import json, sys
SCHEMA_VERSION = "1.0.0"
EMPTY = {"schema_version": SCHEMA_VERSION, "repos": [], "items": [],
         "unmapped": [], "unmapped_counts": {}}
cmd = sys.argv[1] if len(sys.argv) > 1 else ""
if cmd == "validate" and "--help" in sys.argv:
    print("usage: ledger-map.py validate [-h] [--allow-homonyms] doc")
    print("  --allow-homonyms   downgrade class-A cross-repo id homonyms to warnings")
    sys.exit(0)
if cmd == "import":
    doc = dict(EMPTY, repos=[{"repo": sys.argv[2], "path": sys.argv[3],
                              "verdict": None, "labels": []}])
    print(json.dumps(doc)); sys.exit(0)
if cmd == "merge":
    print(json.dumps(EMPTY)); sys.exit(0)
sys.exit(0)
STUB
printf '%s\n' '1111' > "$ALLOW"
set +e
"$stub_dir/tracker/fleet-import.sh" --state "$tmp/stub-state.json" \
  --allowlist-file "$ALLOW" > /dev/null 2> "$tmp/run9d.err"
rc3=$?
set -e
[[ "$rc3" -eq 5 ]] \
  || fail "a ledger-map.py exposing ONLY the superseded boolean must be REFUSED with exit 5, got $rc3: $(cat "$tmp/run9d.err")"
grep -qi 'REFUSING' "$tmp/run9d.err" \
  || fail "exit 5 without naming the refusal to use the superseded boolean"
grep -qi 'ca24' "$tmp/run9d.err" || fail "the refusal does not point at id:ca24"

# The driver must never reach for the bare boolean, in any code path...
grep -qE -- '--allow-homonyms"?[[:space:]]*\)' "$IMPORT" \
  && fail "fleet-import.sh appears to pass a bare --allow-homonyms"
# ...and must pass ca24's SINGULAR surface, one adjudicated token at a time. Pinning the
# actual shipped spelling: the superseded plural spellings matched no ledger-map.py that
# ever existed, and asserting on them cemented unreachable code.
grep -q 'homonym_flags+=(--allow-homonym "\$t")' "$IMPORT" \
  || fail "fleet-import.sh no longer passes homonym tokens explicitly, one at a time (--allow-homonym)"
grep -q 'homonym_flags=(--allow-homonym-file "\$f")' "$IMPORT" \
  || fail "fleet-import.sh no longer offers ca24's --allow-homonym-file surface"
grep -qE -- '--allow-homonyms-file|--allow-homonyms "' "$IMPORT" \
  && fail "fleet-import.sh still carries a superseded PLURAL allow-list spelling (dead code)"

# --- 10. purity again, after every mutation path above --------------------------------
repo_state_snapshot "$FLEET/repo-alpha" > "$tmp/snap.alpha2"
repo_state_snapshot "$BETA" > "$tmp/snap.beta2"
: > "$ALLOW"
set +e; run > /dev/null 2>&1; set -e
assert_repo_unchanged "$FLEET/repo-alpha" "$tmp/snap.alpha2" || fail "a later run mutated repo-alpha"
assert_repo_unchanged "$BETA" "$tmp/snap.beta2" || fail "a later run mutated repo-beta"

# --- 11. fleet-state.py is a PURE function of its inputs ------------------------------
python3 "$STATEPY" upsert --fleet "$OUT" --state "$tmp/state.run1" > "$tmp/pure.a" 2>/dev/null \
  || fail "fleet-state.py upsert failed"   # stderr is the notes channel, checked elsewhere
python3 "$STATEPY" upsert --fleet "$OUT" --state "$tmp/state.run1" > "$tmp/pure.b" 2>/dev/null
cmp -s "$tmp/pure.a" "$tmp/pure.b" || fail "fleet-state.py upsert is not deterministic"
cmp -s "$tmp/state.run1" "$tmp/state.run1.orig" 2>/dev/null || true   # (no-op guard)
python3 "$STATEPY" diff "$STATE" > /dev/null || fail "fleet-state.py diff failed"

echo "PASS: fleet import — relay.toml authority, pinned-SHA reads (no torn state), zero-diff idempotence, upserts, tombstones, loud-lossy counts, per-token homonym allow-list (id:94ce)"
