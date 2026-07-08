#!/usr/bin/env bash
# No `# roadmap:XXXX` header: id:9d97 has a TODO.md entry (design-record
# docs/meeting-notes/2026-07-07-1228-relay-discovery-off-workflow.md) but no matching
# ROADMAP.md item, so the expected-red/EXPECTED-RED gate doesn't apply here — this test's
# failures always count, per the testing convention in CLAUDE.md.
#
# Spec for relay/scripts/discover-repos-mechanical.sh (id:9d97) — the mechanical discovery
# PRODUCER that replaces the Haiku "exec discover-repo.sh + echo the JSON" discover-run
# shard with a zero-LLM script, so the reliability-motivated mangle risk (2026-07-07
# meeting, docs/meeting-notes/2026-07-07-1228-relay-discovery-off-workflow.md) never
# reaches an LLM at all.
#
# Contract under test:
#   discover-repos-mechanical.sh [--runid <id>] [--live-claims <csv>] [--main-branch <name>]
#     - enumerates CONFIRMED own repos from relay.toml (classification="own", honoring
#       `# path:` overrides and `paused`)
#     - execs discover-repo.sh (id:64b4) UNMODIFIED per repo
#     - writes a schema-checked aggregate snapshot to
#       $RELAY_DISCOVERY_QUEUE_DIR/{queue-<tag>.json,latest.json}, atomically
#
# Two properties pinned here:
#   (1) SCHEMA VALIDITY — the emitted latest.json parses and matches the documented
#       shape: {schema_version, generated_at, run_id, repos[], units[], surfaced[], skipped[]}.
#   (2) DETERMINISM PARITY — for a fixture repo set, the per-repo unit embedded in the
#       aggregate is CONTENT-IDENTICAL (same JSON value; the producer never mutates,
#       re-derives, or re-classifies) to what a direct `discover-repo.sh` call for that
#       same repo/path produces. This pins the invariant that a future refactor of
#       either script can't silently let the two diverge.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROD="$ROOT/relay/scripts/discover-repos-mechanical.sh"
DR="$ROOT/relay/scripts/discover-repo.sh"

[[ -x "$PROD" ]] || { echo "discover-repos-mechanical.sh not found (RED): $PROD"; exit 1; }
[[ -x "$DR" ]]   || { echo "discover-repo.sh not found: $DR"; exit 1; }

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

mkrepo() {
  local d="$1"
  mkdir -p "$d"
  git -C "$d" init -q
  git -C "$d" config user.email t@e
  git -C "$d" config user.name t
  git -C "$d" config commit.gpgsign false
}

tmp="$(mktemp -d)"
tmp_parse="$(mktemp -d)"    # id:0fa0 finding (a) — malformed relay.toml
tmp_garbage="$(mktemp -d)"  # id:0fa0 finding (b) — one repo's garbage stdout
tmp_allerr="$(mktemp -d)"   # id:0fa0 finding (c) — every repo errors
trap 'rm -rf "$tmp" "$tmp_parse" "$tmp_garbage" "$tmp_allerr"' EXIT
export SRC_DIR="$tmp/src"
export RELAY_TOML="$tmp/relay.toml"
export RELAY_DISCOVERY_QUEUE_DIR="$tmp/queue"
export RELAY_WORKTREE_BASE="$tmp/wt"
# id:54fc: the producer now beats a heartbeat marker (heartbeat.sh, id:e149) on success.
# Redirect it into the tmpdir so this test never touches the real ~/.config/relay/heartbeats.
export HEARTBEAT_BASE="$tmp/heartbeats"
export HEARTBEAT_LOG=/dev/null
mkdir -p "$SRC_DIR"

# --- fixture repo 1: clean + open [ROUTINE] → execute unit -------------------------------
R1="$SRC_DIR/r_exec"; mkrepo "$R1"
printf '# Roadmap\n## Items\n- [ ] [ROUTINE] do it <!-- id:1111 -->\n' > "$R1/ROADMAP.md"
printf '# TODO\n## Current\n' > "$R1/TODO.md"
git -C "$R1" add -A; git -C "$R1" commit -qm init

# --- fixture repo 2: finished/idle → idle unit + skipped ---------------------------------
R2="$SRC_DIR/r_idle"; mkrepo "$R2"
printf '# Roadmap\n## Items\n- [x] [ROUTINE] done <!-- id:3333 -->\n' > "$R2/ROADMAP.md"
printf '# TODO\n## Current\n- [x] done <!-- id:3334 -->\n' > "$R2/TODO.md"
git -C "$R2" add -A; git -C "$R2" commit -qm init
git -C "$R2" tag -a relay-ckpt-20260101-0000 -m ckpt

# --- fixture repo 3: dirty non-lock → blocked → surfaced ---------------------------------
R3="$SRC_DIR/r_dirty"; mkrepo "$R3"
printf '# Roadmap\n## Items\n- [ ] [ROUTINE] do it <!-- id:4444 -->\n' > "$R3/ROADMAP.md"
printf '# TODO\n## Current\n' > "$R3/TODO.md"
git -C "$R3" add -A; git -C "$R3" commit -qm init
echo change >> "$R3/ROADMAP.md"   # dirty non-lock

cat > "$RELAY_TOML" <<EOF
[repos.r_exec]
classification = "own"

[repos.r_idle]
classification = "own"

[repos.r_dirty]
classification = "own"
EOF

# === run the mechanical producer =========================================================
out="$("$PROD" --runid parity-run --live-claims "" --main-branch main)"
echo "$out"

[[ -f "$RELAY_DISCOVERY_QUEUE_DIR/latest.json" ]] || fail "latest.json was not written"
snapshot_count="$(find "$RELAY_DISCOVERY_QUEUE_DIR" -maxdepth 1 -name 'queue-*.json' | wc -l)"
[[ "$snapshot_count" -eq 1 ]] || fail "expected exactly 1 queue-*.json snapshot, found $snapshot_count"

# === (1) SCHEMA VALIDITY ==================================================================
python3 - "$RELAY_DISCOVERY_QUEUE_DIR/latest.json" <<'PY' || exit 1
import json, sys

path = sys.argv[1]
with open(path) as fh:
    data = json.load(fh)

assert isinstance(data, dict), "top-level value must be an object"
required = ["schema_version", "generated_at", "run_id", "repos", "units", "surfaced", "skipped"]
missing = [k for k in required if k not in data]
assert not missing, f"missing top-level keys: {missing}"

assert data["schema_version"] == 1, f"schema_version != 1: {data['schema_version']!r}"
assert isinstance(data["generated_at"], str) and data["generated_at"], "generated_at must be a non-empty string"
assert data["run_id"] == "parity-run", f"run_id mismatch: {data['run_id']!r}"

for key in ("repos", "units", "surfaced", "skipped"):
    assert isinstance(data[key], list), f"{key} must be a list"

repo_names = {r["repo"] for r in data["repos"]}
assert repo_names == {"r_exec", "r_idle", "r_dirty"}, f"repos mismatch: {repo_names}"

for r in data["repos"]:
    assert set(r.keys()) == {"repo", "path"}, f"repos entry has unexpected keys: {r}"

unit_repos = {u["repo"] for u in data["units"]}
assert "r_exec" in unit_repos, "r_exec should have emitted a unit"
assert "r_idle" in unit_repos, "r_idle should have emitted a unit (idle verdict)"

surfaced_repos = {s["repo"] for s in data["surfaced"]}
assert "r_dirty" in surfaced_repos, "r_dirty (dirty non-lock) should be surfaced, not classified"

skipped_repos = {s["repo"] for s in data["skipped"]}
assert "r_idle" in skipped_repos, "r_idle (idle) should also appear in skipped"

print("schema validity: OK")
PY
[[ $? -eq 0 ]] && pass "(1) latest.json is schema-valid" || fail "(1) schema validity check failed"

# === (2) DETERMINISM PARITY ===============================================================
# For each fixture repo that reaches classify-repo.sh (r_exec, r_idle — NOT r_dirty, which
# discover-repo.sh itself routes to "surfaced" before any unit is minted), the unit embedded
# in the aggregate must be CONTENT-IDENTICAL to a fresh direct discover-repo.sh call for the
# same repo/path (same runid/live-claims/main-branch — the only inputs that vary the output).
for name_path in "r_exec:$R1" "r_idle:$R2"; do
  name="${name_path%%:*}"; path="${name_path#*:}"

  # id:0fa0 finding (d): the producer ALWAYS calls discover-repo.sh --no-reconcile (the
  # read-only classify path, per the producer's own header/id:9d97 data-loss fix). A
  # baseline call WITHOUT --no-reconcile takes a DIFFERENT code path (it also runs
  # reconcile-repo.sh's side effects) — comparing against it only "passed parity" by
  # coincidence on these clean fixtures; a real divergence between the two paths' classify
  # verdicts would go undetected. Pin the SAME path the producer actually takes.
  direct="$("$DR" --repo "$name" --path "$path" --runid parity-run --live-claims "" --main-branch main --no-reconcile)"

  MATCH_NAME="$name" python3 - "$RELAY_DISCOVERY_QUEUE_DIR/latest.json" "$direct" <<'PY' || exit 1
import json, os, sys

agg_path, direct_json = sys.argv[1], sys.argv[2]
name = os.environ["MATCH_NAME"]

with open(agg_path) as fh:
    agg = json.load(fh)
agg_unit = next((u for u in agg["units"] if u["repo"] == name), None)
assert agg_unit is not None, f"{name}: no unit found in aggregate"

direct_obj = json.loads(direct_json)
direct_units = direct_obj.get("units", [])
assert direct_units, f"{name}: direct discover-repo.sh call produced no units"
direct_unit = direct_units[0]

assert json.dumps(agg_unit, sort_keys=True) == json.dumps(direct_unit, sort_keys=True), (
    f"{name}: aggregate unit != direct discover-repo.sh unit\n"
    f"  aggregate: {agg_unit}\n"
    f"  direct:    {direct_unit}"
)
print(f"{name}: determinism parity OK")
PY
  [[ $? -eq 0 ]] || fail "(2) determinism parity failed for $name"
done
pass "(2) mechanical producer's per-repo units are content-identical to direct discover-repo.sh calls"

echo "ALL PASS: discover-repos-mechanical.sh schema + determinism parity"

# === (3) id:0fa0 finding (a): malformed relay.toml → LOUD nonzero exit, NO queue write ====
# A relay.toml with a duplicate key fails tomllib.load(). Before the fix, own_repos()'s
# failure was silently discarded by `done < <(own_repos)`, so the producer enumerated ZERO
# repos and happily wrote a schema-valid EMPTY latest.json + beat the heartbeat GREEN.
SRC_DIR_PARSE="$tmp_parse/src"
mkdir -p "$SRC_DIR_PARSE"
RELAY_TOML_PARSE="$tmp_parse/relay.toml"
cat > "$RELAY_TOML_PARSE" <<'EOF'
[repos.dup]
classification = "own"
classification = "own"
EOF
QUEUE_DIR_PARSE="$tmp_parse/queue"
HEARTBEAT_BASE_PARSE="$tmp_parse/heartbeats"

parse_rc=0
parse_out="$(SRC_DIR="$SRC_DIR_PARSE" RELAY_TOML="$RELAY_TOML_PARSE" \
             RELAY_DISCOVERY_QUEUE_DIR="$QUEUE_DIR_PARSE" \
             RELAY_WORKTREE_BASE="$tmp_parse/wt" \
             HEARTBEAT_BASE="$HEARTBEAT_BASE_PARSE" HEARTBEAT_LOG=/dev/null \
             "$PROD" --runid parse-guard-run --live-claims "" --main-branch main 2>&1)" || parse_rc=$?

[[ "$parse_rc" -ne 0 ]] || fail "(3) malformed relay.toml: expected nonzero exit, got 0. Output: $parse_out"
[[ ! -e "$QUEUE_DIR_PARSE/latest.json" ]] || fail "(3) malformed relay.toml: latest.json was written, should not have been"
[[ ! -d "$HEARTBEAT_BASE_PARSE" ]] || [[ -z "$(ls -A "$HEARTBEAT_BASE_PARSE" 2>/dev/null)" ]] \
  || fail "(3) malformed relay.toml: a heartbeat marker was written, should not have been"
pass "(3) malformed relay.toml → nonzero exit, no queue write, no heartbeat beat"

# === (4) id:0fa0 finding (b): one repo's garbage stdout is isolated, others survive =========
# A stub discover-repo.sh that emits empty stdout (rc 0) for ONE repo and real output for the
# others must NOT abort the whole aggregate — the healthy repos' units must still land.
SRC_DIR_GARBAGE="$tmp_garbage/src"
mkdir -p "$SRC_DIR_GARBAGE"
G1="$SRC_DIR_GARBAGE/g_good"; mkrepo "$G1"
printf '# Roadmap\n## Items\n- [ ] [ROUTINE] do it <!-- id:5555 -->\n' > "$G1/ROADMAP.md"
printf '# TODO\n## Current\n' > "$G1/TODO.md"
git -C "$G1" add -A; git -C "$G1" commit -qm init

G2="$SRC_DIR_GARBAGE/g_garbage"; mkrepo "$G2"
printf '# Roadmap\n## Items\n- [ ] [ROUTINE] do it <!-- id:6666 -->\n' > "$G2/ROADMAP.md"
printf '# TODO\n## Current\n' > "$G2/TODO.md"
git -C "$G2" add -A; git -C "$G2" commit -qm init

RELAY_TOML_GARBAGE="$tmp_garbage/relay.toml"
cat > "$RELAY_TOML_GARBAGE" <<EOF
[repos.g_good]
classification = "own"

[repos.g_garbage]
classification = "own"
EOF

# Stub discover-repo.sh: real discover-repo.sh for g_good, empty stdout (rc 0) for g_garbage.
STUB_DR="$tmp_garbage/discover-repo-stub.sh"
cat > "$STUB_DR" <<STUBEOF
#!/usr/bin/env bash
set -euo pipefail
real="$DR"
repo=""
args=("\$@")
for ((i=0; i<\${#args[@]}; i++)); do
  if [[ "\${args[i]}" == "--repo" ]]; then repo="\${args[i+1]}"; fi
done
if [[ "\$repo" == "g_garbage" ]]; then
  exit 0   # empty stdout, rc 0 — the garbage case
fi
exec "\$real" "\${args[@]}"
STUBEOF
chmod +x "$STUB_DR"

QUEUE_DIR_GARBAGE="$tmp_garbage/queue"

# The producer resolves discover-repo.sh relative to its OWN script dir (no env override,
# by design — it never fs-hunts), so exercise the stub by symlinking a private copy of
# relay/scripts/ with ONLY discover-repo.sh swapped for the stub. This keeps every other
# script (heartbeat.sh, lib-own-repos.sh) the SAME real file the producer normally uses.
STUB_SCRIPT_DIR="$tmp_garbage/scripts"
mkdir -p "$STUB_SCRIPT_DIR"
for f in "$ROOT"/relay/scripts/*; do ln -sf "$f" "$STUB_SCRIPT_DIR/$(basename "$f")"; done
rm -f "$STUB_SCRIPT_DIR/discover-repo.sh"
cp "$STUB_DR" "$STUB_SCRIPT_DIR/discover-repo.sh"
chmod +x "$STUB_SCRIPT_DIR/discover-repo.sh"

garbage_out="$(SRC_DIR="$SRC_DIR_GARBAGE" RELAY_TOML="$RELAY_TOML_GARBAGE" \
               RELAY_DISCOVERY_QUEUE_DIR="$QUEUE_DIR_GARBAGE" \
               RELAY_WORKTREE_BASE="$tmp_garbage/wt" \
               HEARTBEAT_BASE="$tmp_garbage/heartbeats" HEARTBEAT_LOG=/dev/null \
               "$STUB_SCRIPT_DIR/discover-repos-mechanical.sh" --runid garbage-run \
               --live-claims "" --main-branch main 2>&1)" || fail "(4) garbage-stdout run failed: $garbage_out"
echo "$garbage_out"

[[ -f "$QUEUE_DIR_GARBAGE/latest.json" ]] || fail "(4) latest.json was not written despite one repo's garbage stdout"

python3 - "$QUEUE_DIR_GARBAGE/latest.json" <<'PY' || exit 1
import json, sys
with open(sys.argv[1]) as fh:
    data = json.load(fh)
unit_repos = {u["repo"] for u in data["units"]}
assert "g_good" in unit_repos, f"g_good should still have a unit; units={data['units']}"
garbage_entries = [s for s in data["surfaced"] if s.get("repo") == "g_garbage"]
assert garbage_entries, "g_garbage should be isolated into surfaced"
assert garbage_entries[0].get("producer_error") is True, f"g_garbage surfaced entry should be producer_error-marked: {garbage_entries[0]}"
print("garbage isolation: OK")
PY
[[ $? -eq 0 ]] || fail "(4) garbage-stdout isolation check failed"
pass "(4) one repo's garbage stdout is isolated into surfaced; other repos' entries survive"

# === (5) id:0fa0 finding (c): heartbeat NOT beaten when every repo errors ===================
# All confirmed repos point at a path that doesn't exist — every one is synthesized into
# `surfaced` as a producer_error entry. The snapshot must still be WRITTEN (consumer
# transparency) but the heartbeat must NOT be beaten.
SRC_DIR_ALLERR="$tmp_allerr/src"
mkdir -p "$SRC_DIR_ALLERR"
RELAY_TOML_ALLERR="$tmp_allerr/relay.toml"
cat > "$RELAY_TOML_ALLERR" <<EOF
[repos.missing_one]
classification = "own"
path = "$tmp_allerr/does-not-exist"

[repos.missing_two]
classification = "own"
path = "$tmp_allerr/also-does-not-exist"
EOF
QUEUE_DIR_ALLERR="$tmp_allerr/queue"
HEARTBEAT_BASE_ALLERR="$tmp_allerr/heartbeats"

allerr_out="$(SRC_DIR="$SRC_DIR_ALLERR" RELAY_TOML="$RELAY_TOML_ALLERR" \
              RELAY_DISCOVERY_QUEUE_DIR="$QUEUE_DIR_ALLERR" \
              RELAY_WORKTREE_BASE="$tmp_allerr/wt" \
              HEARTBEAT_BASE="$HEARTBEAT_BASE_ALLERR" HEARTBEAT_LOG=/dev/null \
              "$PROD" --runid allerr-run --live-claims "" --main-branch main 2>&1)" \
  || fail "(5) all-error run unexpectedly exited nonzero: $allerr_out"
echo "$allerr_out"

[[ -f "$QUEUE_DIR_ALLERR/latest.json" ]] || fail "(5) all-error snapshot was NOT written; should be (consumer transparency)"
[[ ! -d "$HEARTBEAT_BASE_ALLERR" ]] || [[ -z "$(ls -A "$HEARTBEAT_BASE_ALLERR" 2>/dev/null)" ]] \
  || fail "(5) all-error snapshot beat the heartbeat; should NOT have"
printf '%s\n' "$allerr_out" | grep -q 'heartbeat NOT beaten' \
  || fail "(5) expected a loud stderr line about the heartbeat not being beaten"
pass "(5) all-repos-errored snapshot is written for transparency but does NOT beat the heartbeat"

echo "ALL PASS: discover-repos-mechanical.sh id:0fa0 robustness (parse guard / garbage isolation / heartbeat-usable-output)"
