#!/usr/bin/env bash
# relay/scripts/discover-repos-mechanical.sh — mechanical discovery PRODUCER (id:9d97).
#
# WHY: post-a0b6, the Workflow's `discover-run` shard is pure transport — a Haiku agent()
# whose only job is "exec discover-repo.sh per repo and echo the JSON verbatim" — but Haiku
# has been observed to mangle even that (2026-07-07 meeting doctrine: "no LLM if mechanical
# can do as good or better", docs/meeting-notes/2026-07-07-1228-relay-discovery-off-workflow.md,
# decision D2). This script performs the SAME exec-and-collect step as a `--user` systemd
# TIMER, zero LLM, so the mangle-prone step never touches an LLM at all. It reuses
# discover-repo.sh (id:64b4) VERBATIM per repo — determinism parity with the Haiku
# discover-run shard is the whole point — and writes a schema-checked snapshot into a
# drop-dir the (future, gated, id:7402) executor prelude will consume instead of
# dispatching the Haiku discover-run shard.
#
# Usage:
#   discover-repos-mechanical.sh [--runid <id>] [--live-claims <csv>] [--main-branch <name>]
#
# Enumerates CONFIRMED own repos from relay.toml (classification = "own", honoring the
# `# path:` comment override and the `paused` flag — the SAME parser used by
# relay-doctor.sh / relay-reconcile.sh / gather-human-backlog.sh; never a fresh ~/src glob,
# id:7633), then for EACH repo execs discover-repo.sh unmodified and folds its
# {units,surfaced,skipped} into ONE aggregate object:
#
#   {
#     "schema_version": 1,
#     "generated_at": "<ISO-8601 UTC, e.g. 2026-07-07T13:00:00Z>",
#     "run_id":  "<the --runid value, or \"\" if omitted>",
#     "repos":   [ {"repo": "<name>", "path": "<abs>"}, ... ],  // every confirmed own repo considered
#     "units":   [ ... ],  // concatenation, in repo-enumeration order, of every
#                          // discover-repo.sh call's units[] (0 or 1 entries each)
#     "surfaced":[ ... ],  // concatenation of every discover-repo.sh call's surfaced[]
#                          // (plus one synthesized entry per repo whose path is missing/
#                          // not a git repo, or whose discover-repo.sh invocation errored —
#                          // NEVER silently dropped, no-silent-swallow id:4347)
#     "skipped": [ ... ]   // concatenation of every discover-repo.sh call's skipped[]
#   }
#
# NO-FILESYSTEM-HUNTING (mirrors discover-repo.sh's own id:612f guard): this script runs NO
# git commands itself and does NO ledger/transcript reading beyond relay.toml — it only
# enumerates relay.toml and execs discover-repo.sh, which already does everything else.
# NO `claude -p`, NO agent(), NO LLM call anywhere in this script.
#
# Schema-checked BEFORE the atomic write: a malformed aggregate (a sub-script emitted
# non-JSON, or the assembled top-level shape fails the check above) is a LOUD failure
# (no-silent-swallow, id:4347) on stderr with a nonzero exit — NEVER written to the
# drop-dir half-formed.
#
# Drop-dir — NEW location, does NOT reuse the id:64d3/b3d0 recipe drop-dir
# (~/.config/relay/recipes/{pending,running,done}): that schema is a flat
# {id,repo,cmd,host,est_wall,resource,acceptance_artifact} object describing ONE
# EXECUTABLE command the mechanical-run daemon (A3) runs. A discovery snapshot is a
# different shape entirely — an array of per-repo CLASSIFICATION verdicts to be READ by
# the executor prelude, nothing to execute — so folding it into the recipe schema would
# be a category error, not reuse. See relay/references/discovery-queue-manifest.md for
# the full schema + drop-dir contract (mirrors recipe-manifest.md's structure).
#
# Defaults to ~/.config/relay/discovery-queue (RELAY_DISCOVERY_QUEUE_DIR override, for
# hermetic tests). Two files are written per invocation, both via write-to-tmp-then-mv
# in the SAME directory (atomic — a reader never observes a half-written file):
#   - queue-<run_id-or-epoch>-<epoch>.json   — one per invocation, kept for history/forensics
#   - latest.json                            — always the most recent snapshot; this is the
#                                               file id:7402's prelude-consumer reads
#
# Env overrides (hermetic testing; mirrors the sibling scripts' idiom):
#   RELAY_TOML                 default ~/.config/relay/relay.toml
#   SRC_DIR                    default ~/src   (fallback path when a repo has no explicit
#                              `path =` / `# path:` override in relay.toml)
#   RELAY_DISCOVERY_QUEUE_DIR  default ~/.config/relay/discovery-queue
#   RELAY_WORKTREE_BASE        threaded straight to discover-repo.sh's sub-scripts, unchanged
#                              (this script never reads worktree state itself)
#
# LIVENESS (id:54fc): on a successful write, this script beats its OWN heartbeat marker via
# the shared heartbeat.sh (id:e149) mechanism — a SEPARATE domain from the dispatch loop's
# per-round `relay-*` runIds, so the outage watchdog (id:98f0) can tell "the discovery
# producer .timer died" apart from "the dispatch pool is just idle". Same marker
# format/location (HEARTBEAT_BASE), distinct fixed runId (DISCOVERY_PRODUCER_RUN_ID,
# default "discovery-producer" — MUST match relay-watchdog.sh's own default/override).
# Beat failures are logged but NON-FATAL — a heartbeat hiccup must never fail the actual
# discovery write.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISCOVER_REPO="$SCRIPT_DIR/discover-repo.sh"
HEARTBEAT_SH="$SCRIPT_DIR/heartbeat.sh"

RELAY_TOML="${RELAY_TOML:-$HOME/.config/relay/relay.toml}"
SRC_DIR="${SRC_DIR:-$HOME/src}"
QUEUE_DIR="${RELAY_DISCOVERY_QUEUE_DIR:-$HOME/.config/relay/discovery-queue}"
LOG="${RELAY_DISCOVER_MECH_LOG:-$HOME/.claude/logs/discover-repos-mechanical.log}"
PRODUCER_RUN_ID="${DISCOVERY_PRODUCER_RUN_ID:-discovery-producer}"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
log() { printf '%s discover-repos-mechanical.sh %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >>"$LOG" 2>/dev/null || true; }

usage() { sed -n '2,66p' "$0"; }

runid="" live_claims="" main_branch="main"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --runid) runid="$2"; shift 2 ;;
    --live-claims) live_claims="$2"; shift 2 ;;
    --main-branch) main_branch="$2"; shift 2 ;;
    -h|--help|help) usage; exit 0 ;;
    *) echo "discover-repos-mechanical.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ ! -x "$DISCOVER_REPO" ]]; then
  echo "discover-repos-mechanical.sh: discover-repo.sh not found/executable at $DISCOVER_REPO" >&2
  exit 1
fi

# --- own repos from relay.toml (IDENTICAL parser to relay-doctor.sh own_repos()) --------
# Honors `classification = "own"`, `# path:` comment overrides, the `paused` flag.
# Outputs lines of "<name>\t<path>".
own_repos() {
  [[ -f "$RELAY_TOML" ]] || return 0
  SRC_DIR="$SRC_DIR" python3 -c '
import os, re, sys, tomllib
src = os.environ["SRC_DIR"]
toml_path = sys.argv[1]
with open(toml_path, "rb") as f:
    data = tomllib.load(f)

# Recover the `# path:` COMMENT override per repo (tomllib drops comments).
comment_path = {}
cur = None
sect_re = re.compile(r"^\s*\[repos\.([^\]]+)\]\s*$")
path_re  = re.compile(r"^\s*#\s*path:\s*(.+?)\s*$")
with open(toml_path, encoding="utf-8") as f:
    for line in f:
        m = sect_re.match(line)
        if m:
            cur = m.group(1)
            continue
        if cur:
            pm = path_re.match(line)
            if pm and cur not in comment_path:
                comment_path[cur] = pm.group(1)

def expand(p):
    return os.path.expanduser(os.path.expandvars(p))

for name, entry in data.get("repos", {}).items():
    if entry.get("classification") != "own":
        continue
    if entry.get("paused"):
        continue
    path = entry.get("path") or comment_path.get(name) or os.path.join(src, name)
    print(f"{name}\t{expand(path)}")
' "$RELAY_TOML"
}

mkdir -p "$QUEUE_DIR"

# One NDJSON record per repo: "<name>\t<path>\t<json-object-from-discover-repo.sh>"
# where <json-object> is either discover-repo.sh's real output, or a synthesized
# {"units":[],"surfaced":[{"repo","reason"}],"skipped":[]} for a repo this script
# itself could not even hand to discover-repo.sh (missing path / not a git repo /
# discover-repo.sh exited nonzero) — NEVER silently dropped.
records_file="$(mktemp)"
trap 'rm -f "$records_file"' EXIT

n_repos=0
while IFS=$'\t' read -r name path; do
  [[ -n "$name" ]] || continue
  n_repos=$((n_repos + 1))

  if [[ ! -d "$path" ]] || ! git -C "$path" rev-parse --git-dir >/dev/null 2>&1; then
    log "repo=$name path-missing-or-not-git=$path — surfacing, no discover-repo.sh call"
    reason="path not found or not a readable git repo: $path"
    out="$(REPO_ARG="$name" REASON_ARG="$reason" python3 -c '
import json, os
print(json.dumps({"units": [], "surfaced": [{"repo": os.environ["REPO_ARG"], "reason": os.environ["REASON_ARG"]}], "skipped": []}))
')"
    printf '%s\t%s\t%s\n' "$name" "$path" "$out" >> "$records_file"
    continue
  fi

  if out="$("$DISCOVER_REPO" --repo "$name" --path "$path" --runid "$runid" \
            --live-claims "$live_claims" --main-branch "$main_branch" 2>>"$LOG")"; then
    printf '%s\t%s\t%s\n' "$name" "$path" "$out" >> "$records_file"
  else
    rc=$?
    log "repo=$name discover-repo.sh FAILED rc=$rc"
    reason="discover-repo.sh exited $rc"
    out="$(REPO_ARG="$name" REASON_ARG="$reason" python3 -c '
import json, os
print(json.dumps({"units": [], "surfaced": [{"repo": os.environ["REPO_ARG"], "reason": os.environ["REASON_ARG"]}], "skipped": []}))
')"
    printf '%s\t%s\t%s\n' "$name" "$path" "$out" >> "$records_file"
  fi
done < <(own_repos)

log "enumerated $n_repos confirmed own repo(s) from $RELAY_TOML"

# --- aggregate + schema-check (LOUD failure, never a half-written file) -----------------
generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
epoch="$(date +%s)"
run_tag="${runid:-noid}-${epoch}"

if ! aggregate="$(RUN_ID="$runid" GENERATED_AT="$generated_at" python3 -c '
import json, os, sys

run_id = os.environ["RUN_ID"]
generated_at = os.environ["GENERATED_AT"]

repos = []
units = []
surfaced = []
skipped = []

with open(sys.argv[1], encoding="utf-8") as fh:
    for line in fh:
        line = line.rstrip("\n")
        if not line:
            continue
        name, path, blob = line.split("\t", 2)
        repos.append({"repo": name, "path": path})
        try:
            obj = json.loads(blob)
        except json.JSONDecodeError as exc:
            sys.stderr.write(f"ERROR: repo {name} produced non-JSON output: {exc}\n")
            sys.exit(1)
        if not isinstance(obj, dict):
            sys.stderr.write(f"ERROR: repo {name} produced a non-object JSON value\n")
            sys.exit(1)
        for key, bucket in (("units", units), ("surfaced", surfaced), ("skipped", skipped)):
            val = obj.get(key, [])
            if not isinstance(val, list):
                sys.stderr.write(f"ERROR: repo {name} field {key!r} is not a list\n")
                sys.exit(1)
            bucket.extend(val)

out = {
    "schema_version": 1,
    "generated_at": generated_at,
    "run_id": run_id,
    "repos": repos,
    "units": units,
    "surfaced": surfaced,
    "skipped": skipped,
}
print(json.dumps(out, indent=2))
' "$records_file")"; then
  echo "discover-repos-mechanical.sh: FAILED to assemble a schema-valid queue — nothing written (see $LOG)" >&2
  log "assembly FAILED — no queue file written"
  exit 1
fi

# --- atomic write: tmp-then-mv, in the SAME directory as the final name -----------------
snapshot_name="queue-${run_tag}.json"
tmp_snapshot="$QUEUE_DIR/.tmp.$$.$snapshot_name"
printf '%s\n' "$aggregate" > "$tmp_snapshot"
mv -f "$tmp_snapshot" "$QUEUE_DIR/$snapshot_name"

tmp_latest="$QUEUE_DIR/.tmp.$$.latest.json"
printf '%s\n' "$aggregate" > "$tmp_latest"
mv -f "$tmp_latest" "$QUEUE_DIR/latest.json"

log "wrote $QUEUE_DIR/$snapshot_name + latest.json (repos=$n_repos)"

# --- liveness beat (id:54fc) — non-fatal: a heartbeat hiccup never fails the write above --
if [[ -x "$HEARTBEAT_SH" ]]; then
  if "$HEARTBEAT_SH" beat "$PRODUCER_RUN_ID" >/dev/null 2>>"$LOG"; then
    log "beat producer heartbeat runId=$PRODUCER_RUN_ID"
  else
    log "heartbeat beat FAILED for runId=$PRODUCER_RUN_ID (non-fatal)"
  fi
else
  log "heartbeat.sh not found/executable at $HEARTBEAT_SH — producer liveness marker NOT written (non-fatal)"
fi

echo "discover-repos-mechanical.sh: wrote $QUEUE_DIR/$snapshot_name (repos=$n_repos)"
