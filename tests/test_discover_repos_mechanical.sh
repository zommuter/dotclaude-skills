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

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
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

  direct="$("$DR" --repo "$name" --path "$path" --runid parity-run --live-claims "" --main-branch main)"

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
