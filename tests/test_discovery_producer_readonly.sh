#!/usr/bin/env bash
# No `# roadmap:XXXX` header: this is a DEFECT-FIX test (no matching ROADMAP.md item), so
# its failures ALWAYS count per the testing convention in CLAUDE.md.
#
# Regression spec for a CONFIRMED DATA-LOSS bug (strong-model audit of id:9d97):
# discover-repos-mechanical.sh is documented/intended as a READ-ONLY verdict snapshot, but it
# execs discover-repo.sh which composes reconcile-repo.sh — "bounded SIDE-EFFECTING git": fetch,
# ff-merge, uv.lock commits, and worktree reap/park (git worktree remove --force + branch rename,
# reconcile-repo.sh:110-121). The live dispatch loop (relay-loop.js) guards in-flight worktrees by
# passing --live-claims + --runid; the producer's systemd .service passes NEITHER → live_claims=""
# → every repo is treated as not-in-flight → the 15-min timer would force-remove a LIVE executor's
# worktree (destroying uncommitted work) and rename its branch.
#
# FIX (audit option (a)): the PRODUCER must classify WITHOUT reconciling. This test constructs a
# fixture repo with a PRE-EXISTING unmerged worktree + branch (mimicking a live executor), runs the
# producer exactly as its .service does (no --runid, no --live-claims), and asserts:
#   (a) the worktree + branch SURVIVE intact (not force-removed, not renamed to relay/orphan/*);
#   (b) the repo does NOT fetch / ff-merge / commit (HEAD + HEAD-reflog unchanged);
#   (c) the producer STILL emits a schema-valid verdict snapshot that includes the repo.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROD="$ROOT/relay/scripts/discover-repos-mechanical.sh"

[[ -x "$PROD" ]] || { echo "discover-repos-mechanical.sh not found (RED): $PROD"; exit 1; }

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
# Keep the heartbeat beat off the real ~/.config/relay/heartbeats.
export HEARTBEAT_BASE="$tmp/heartbeats"
export HEARTBEAT_LOG=/dev/null
mkdir -p "$SRC_DIR"

# --- fixture repo: clean, open [ROUTINE], WITH a live-executor worktree ahead of main -----
R="$SRC_DIR/r_live"; mkrepo "$R"
printf '# Roadmap\n## Items\n- [ ] [ROUTINE] do it <!-- id:1111 -->\n' > "$R/ROADMAP.md"
printf '# TODO\n## Current\n' > "$R/TODO.md"
git -C "$R" add -A; git -C "$R" commit -qm init

# Mimic a LIVE executor: a worktree at $RELAY_WORKTREE_BASE/<repo>/<bn> on branch relay/<bn>
# that is AHEAD of main (has an uncommitted-work commit not reachable from main). The bn does
# NOT start with the producer's runid (the producer runs with runid="" — its .service passes
# none), so reconcile-repo.sh's "skip my own run" guard does not protect it.
BN="run-dead-abc123-execute"
WT="$RELAY_WORKTREE_BASE/r_live/$BN"
git -C "$R" worktree add -q -b "relay/$BN" "$WT"
printf 'precious in-flight work\n' > "$WT/wip.txt"
git -C "$WT" add -A
git -C "$WT" commit -qm "executor WIP not yet merged"

# Capture pre-run invariants of the MAIN repo.
head_before="$(git -C "$R" rev-parse HEAD)"
reflog_before="$(git -C "$R" reflog show HEAD 2>/dev/null | wc -l)"
wip_tip_before="$(git -C "$R" rev-parse "relay/$BN")"

cat > "$RELAY_TOML" <<EOF
[repos.r_live]
classification = "own"
EOF

# === run the producer EXACTLY as its systemd .service does: no --runid, no --live-claims ==
"$PROD"

# === (a) the worktree + branch must SURVIVE ==============================================
[[ -d "$WT" ]] || fail "(a) LIVE worktree was destroyed: $WT no longer exists (git worktree remove --force ran)"
[[ -f "$WT/wip.txt" ]] || fail "(a) LIVE worktree's uncommitted-ish work was lost: $WT/wip.txt gone"
git -C "$R" show-ref --verify --quiet "refs/heads/relay/$BN" \
  || fail "(a) branch relay/$BN was renamed/deleted (parked to relay/orphan/*)"
if git -C "$R" show-ref --verify --quiet "refs/heads/relay/orphan/$BN"; then
  fail "(a) branch was PARKED to relay/orphan/$BN — producer must not reconcile/park live worktrees"
fi
pass "(a) live worktree + branch survived the producer run intact"

# === (b) no fetch / ff-merge / commit in the repo =======================================
head_after="$(git -C "$R" rev-parse HEAD)"
reflog_after="$(git -C "$R" reflog show HEAD 2>/dev/null | wc -l)"
wip_tip_after="$(git -C "$R" rev-parse "relay/$BN")"
[[ "$head_after" == "$head_before" ]]     || fail "(b) main HEAD moved: $head_before -> $head_after"
[[ "$reflog_after" == "$reflog_before" ]] || fail "(b) HEAD reflog grew ($reflog_before -> $reflog_after) — a commit/merge happened"
[[ "$wip_tip_after" == "$wip_tip_before" ]] || fail "(b) executor branch tip moved: $wip_tip_before -> $wip_tip_after"
pass "(b) repo unchanged — no fetch/ff-merge/commit (HEAD + reflog + branch tip stable)"

# === (c) a schema-valid verdict snapshot was STILL emitted, including the repo ============
[[ -f "$RELAY_DISCOVERY_QUEUE_DIR/latest.json" ]] || fail "(c) latest.json was not written"
python3 - "$RELAY_DISCOVERY_QUEUE_DIR/latest.json" <<'PY' || fail "(c) snapshot schema/inclusion check failed"
import json, sys
with open(sys.argv[1]) as fh:
    data = json.load(fh)
assert isinstance(data, dict), "top-level must be an object"
required = ["schema_version", "generated_at", "run_id", "repos", "units", "surfaced", "skipped"]
missing = [k for k in required if k not in data]
assert not missing, f"missing top-level keys: {missing}"
assert data["schema_version"] == 1, f"schema_version != 1: {data['schema_version']!r}"
for key in ("repos", "units", "surfaced", "skipped"):
    assert isinstance(data[key], list), f"{key} must be a list"
repo_names = {r["repo"] for r in data["repos"]}
assert "r_live" in repo_names, f"r_live missing from repos[]: {repo_names}"
verdict_repos = {x["repo"] for x in data["units"]} | {x["repo"] for x in data["surfaced"]} | {x["repo"] for x in data["skipped"]}
assert "r_live" in verdict_repos, "r_live has no verdict entry (units/surfaced/skipped) — snapshot dropped it"
print("schema + inclusion: OK")
PY
pass "(c) producer still emitted a schema-valid verdict snapshot including r_live"

echo "ALL PASS: discovery producer is read-only (no worktree reap/park, no fetch/ff-merge/commit)"
