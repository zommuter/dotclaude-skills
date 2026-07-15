#!/usr/bin/env bash
# relay/scripts/discover-repos-mechanical.sh — mechanical discovery PRODUCER (id:9d97).
#
# WHY: post-a0b6, the Workflow's `discover-run` shard is pure transport — a Haiku agent()
# whose only job is "exec discover-repo.sh per repo and echo the JSON verbatim" — but Haiku
# has been observed to mangle even that (2026-07-07 meeting doctrine: "no LLM if mechanical
# can do as good or better", docs/meeting-notes/2026-07-07-1228-relay-discovery-off-workflow.md,
# decision D2). This script performs the SAME exec-and-collect step as a `--user` systemd
# TIMER, zero LLM, so the mangle-prone step never touches an LLM at all. It calls
# discover-repo.sh (id:64b4) per repo with --no-reconcile — the READ-ONLY classify path — and
# writes a schema-checked snapshot into a drop-dir the (future, gated, id:7402) executor prelude
# will consume instead of dispatching the Haiku discover-run shard.
#
# READ-ONLY (id:9d97 data-loss fix): --no-reconcile SKIPS reconcile-repo.sh's bounded
# SIDE-EFFECTS (fetch / ff-merge / uv.lock commit / worktree reap+park). A snapshot timer has
# NO view of the live pool's in-flight worktrees; without this it would pass no --live-claims,
# so reconcile would treat every executor worktree as stale and `git worktree remove --force`
# it, destroying uncommitted work. The CLASSIFY verdict CONTENT is unchanged (reconcile only
# mutates + surfaces in-flight/orphan cases, never re-derives a verdict) — which is exactly why
# this snapshot only ever feeds the live loop's CLASSIFY half. The LIVE dispatch loop
# (relay-loop.js discover-run recipe, CASE A) ALWAYS runs reconcile-repo.sh LIVE per round
# (with --live-claims + --runid) for the side-effecting reconcile half — ff-merge, uv.lock
# cascade commit, worktree reap/park, live-claims filtering — and takes ONLY the deterministic
# classify verdict from this snapshot when it is fresh (else it runs the full discover-repo.sh
# live, CASE B). It NEVER consumes reconcile results from the queue. So this snapshot being based
# on un-fetched, un-reconciled local state is FINE: the live loop reconciles on real pool state
# when it actually dispatches; the queue only ever supplies the classify verdict.
#
# Usage:
#   discover-repos-mechanical.sh [--runid <id>] [--live-claims <csv>] [--main-branch <name>]
#
# Enumerates CONFIRMED own repos from relay.toml (classification = "own", honoring the
# `# path:` comment override and the `paused` flag — via the SHARED own_repos() parser in
# lib-own-repos.sh, sourced by this script AND relay-doctor.sh, id:0fa0 finding (e); never a
# fresh ~/src glob, id:7633), then for EACH repo execs discover-repo.sh --no-reconcile
# (read-only classify path) and folds its {units,surfaced,skipped} into ONE aggregate object:
#
#   {
#     "schema_version": 1,
#     "generated_at": "<ISO-8601 UTC, e.g. 2026-07-07T13:00:00Z>",
#     "run_id":  "<the --runid value, or \"\" if omitted>",
#     "repos":   [ {"repo": "<name>", "path": "<abs>"}, ... ],  // every confirmed own repo considered
#     "units":   [ ... ],  // concatenation, in repo-enumeration order, of every
#                          // discover-repo.sh call's units[] (0 or 1 entries each)
#     "surfaced":[ ... ],  // concatenation of every discover-repo.sh call's surfaced[]
#                          // (plus one synthesized {"repo","reason","producer_error":true}
#                          // entry per repo whose path is missing/not a git repo, whose
#                          // discover-repo.sh invocation exited nonzero, or whose stdout was
#                          // empty/non-JSON/malformed — NEVER silently dropped, id:4347, and
#                          // NEVER aborts the whole aggregate for the other repos, id:0fa0
#                          // finding (b): the `producer_error` marker is what distinguishes
#                          // these synthesized entries from a GENUINE surfaced verdict
#                          // discover-repo.sh itself emitted, e.g. for a dirty repo)
#     "skipped": [ ... ]   // concatenation of every discover-repo.sh call's skipped[]
#   }
#
# NO-FILESYSTEM-HUNTING (mirrors discover-repo.sh's own id:612f guard): this script runs NO
# git commands itself and does NO ledger/transcript reading beyond relay.toml — it only
# enumerates relay.toml and execs discover-repo.sh, which already does everything else.
# NO `claude -p`, NO agent(), NO LLM call anywhere in this script.
#
# PER-REPO ISOLATION (id:0fa0 finding b): a repo whose discover-repo.sh call exits 0 but
# emits empty/non-JSON/non-object/malformed-field stdout is isolated into `surfaced` as a
# `producer_error` entry for THAT repo only — it never aborts assembly of the other repos'
# already-collected verdicts. Only a genuine ASSEMBLY-level failure (the records file itself
# unreadable, or the top-level shape check failing) is a LOUD failure (no-silent-swallow,
# id:4347) on stderr with a nonzero exit — NEVER written to the drop-dir half-formed.
#
# RELAY.TOML PARSE GUARD (id:0fa0 finding a): if $RELAY_TOML EXISTS but fails to parse
# (syntax error, duplicate key, …), own_repos() (lib-own-repos.sh) returns nonzero. This
# script checks that exit status EXPLICITLY (never a bare `done < <(own_repos)`, which would
# silently discard a subshell failure and enumerate zero repos) and, on failure, exits
# nonzero LOUDLY on stderr BEFORE writing any queue file and BEFORE beating the heartbeat —
# mirrors relay-doctor.sh's registry_parse_check (id:2945).
#
# HEARTBEAT = USABLE OUTPUT (id:0fa0 finding c): the heartbeat is beaten only when the
# written snapshot contains at least one non-error entry (any units[] entry, or any
# surfaced[]/skipped[] entry that is NOT a `producer_error` synthesized one). If every
# confirmed repo errored, the snapshot is still written (consumer transparency — a reader can
# see exactly which repos failed and why) but the heartbeat beat is SKIPPED and a loud stderr
# line is printed, so the outage watchdog correctly reports the producer domain stale rather
# than reading "producing garbage" as healthy.
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
DISCOVER_SIG="$SCRIPT_DIR/discover-sig.sh"
HEARTBEAT_SH="$SCRIPT_DIR/heartbeat.sh"
LIB_OWN_REPOS="$SCRIPT_DIR/lib-own-repos.sh"

RELAY_TOML="${RELAY_TOML:-$HOME/.config/relay/relay.toml}"
SRC_DIR="${SRC_DIR:-$HOME/src}"
QUEUE_DIR="${RELAY_DISCOVERY_QUEUE_DIR:-$HOME/.config/relay/discovery-queue}"
LOG="${RELAY_DISCOVER_MECH_LOG:-$HOME/.claude/logs/discover-repos-mechanical.log}"
PRODUCER_RUN_ID="${DISCOVERY_PRODUCER_RUN_ID:-discovery-producer}"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
log() { printf '%s discover-repos-mechanical.sh %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >>"$LOG" 2>/dev/null || true; }

# shellcheck source=lib-own-repos.sh
source "$LIB_OWN_REPOS"

# usage(): print this header comment in full. Computed (not a hardcoded line range) so a
# future header edit can never silently truncate --help again (id:0fa0 minor finding — the
# prior hardcoded '2,66p' had already gone stale once the header grew past line 66).
usage() {
  local header_end
  header_end="$(grep -n '^set -euo pipefail' "$0" | head -1 | cut -d: -f1)"
  sed -n "2,$((header_end - 1))p" "$0"
}

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

mkdir -p "$QUEUE_DIR"

# --- enumerate own repos, checking own_repos()'s exit status EXPLICITLY (id:0fa0 finding a) -
# A bare `done < <(own_repos)` discards a process-substitution subshell's exit status, so a
# relay.toml parse error (tomllib exception → nonzero exit) would silently read as "0 own
# repos" here — enumerating nothing, then writing a schema-valid EMPTY latest.json and
# beating the heartbeat GREEN while the pool actually has repos it just can't see. Capture to
# a file and check `$?` instead: on failure, exit LOUDLY before any write / heartbeat beat.
own_repos_file="$(mktemp)"
own_repos_rc=0
own_repos > "$own_repos_file" 2>>"$LOG" || own_repos_rc=$?
if [[ "$own_repos_rc" -ne 0 ]]; then
  rm -- "$own_repos_file"   # mktemp'd above ⇒ exists; no -f needed
  echo "discover-repos-mechanical.sh: FAILED to parse relay.toml ($RELAY_TOML), rc=$own_repos_rc — own-repo enumeration aborted; NOTHING written, heartbeat NOT beaten. See $LOG." >&2
  log "own_repos() FAILED rc=$own_repos_rc — relay.toml parse error, aborting before any write (id:0fa0)"
  exit 1
fi

# --- content-address the queue (id:4860): stamp each repo's discover-sig.sh value ---------
# For each confirmed own repo, compute its SUPERSET discovery signature (discover-sig.sh,
# id:c3a6) and stamp it onto that repo's queue entries as `queue_sig`. The LIVE consumer
# (relay-loop.js CASE A) copies a repo's classify verdict ONLY when this queue_sig is
# byte-identical to the repo's LIVE sig the prelude computed that round — a pure string
# equality that structurally dissolves the stale-verdict (executor committed AFTER this
# snapshot) and went-dirty-after-snapshot gaps, and a JS-side assert re-checks it as a
# mangle canary. discover-sig.sh's contract is respected verbatim: it needs ABSOLUTE paths
# (id:2ec4 — own_repos() already emits expanded absolute paths) and is FAIL-OPEN (a git
# error / non-repo path → empty "" sentinel sig). An empty sig is stamped AS-IS and simply
# never matches the live sig → that repo always falls to the live discover-repo.sh path
# (fail-safe, never a stale copy). We call discover-sig.sh ONCE for the whole own-repo set
# (it reads one {repos,liveClaims} JSON on stdin and emits one {repo,sig} line per repo),
# threading the SAME --live-claims this invocation was given so the `inlive` section of the
# sig matches what the live loop computes for a claimed repo.
declare -A SIG_BY_REPO
if [[ -x "$DISCOVER_SIG" ]]; then
  sig_input="$(LIVE_CLAIMS="$live_claims" python3 -c '
import json, os, sys
claims = [c for c in os.environ.get("LIVE_CLAIMS", "").split(",") if c]
repos = []
with open(sys.argv[1], encoding="utf-8") as fh:
    for line in fh:
        line = line.rstrip("\n")
        if not line:
            continue
        name, path = line.split("\t", 1)
        repos.append({"repo": name, "path": path})
print(json.dumps({"repos": repos, "liveClaims": claims}))
' "$own_repos_file")"
  while IFS= read -r sigline; do
    [[ -n "$sigline" ]] || continue
    r="$(printf '%s' "$sigline" | jq -r '.repo // empty')"
    s="$(printf '%s' "$sigline" | jq -r '.sig // ""')"
    [[ -n "$r" ]] && SIG_BY_REPO["$r"]="$s"
  done < <(printf '%s' "$sig_input" | "$DISCOVER_SIG" 2>>"$LOG" || true)
  log "computed discover-sig for ${#SIG_BY_REPO[@]} repo(s) (id:4860 content-address)"
else
  log "discover-sig.sh not found/executable at $DISCOVER_SIG — queue_sig stamped empty for all repos (fail-open, always live path) (id:4860)"
fi

# One NDJSON record per repo: "<name>\t<path>\t<sig>\t<json-object-from-discover-repo.sh>"
# where <json-object> is either discover-repo.sh's real output, or a synthesized
# {"units":[],"surfaced":[{"repo","reason","producer_error":true}],"skipped":[]} for a repo
# this script itself could not even hand to discover-repo.sh (missing path / not a git repo /
# discover-repo.sh exited nonzero) — NEVER silently dropped. The `producer_error` marker lets
# the assembly step (below) and the heartbeat-gate tell these synthesized entries apart from
# a genuine surfaced verdict discover-repo.sh itself emitted (id:0fa0 finding c).
records_file="$(mktemp)"
# swallow-ok: best-effort crash cleanup — rm -f already no-ops on missing files/dirs (e.g. a
# crash before mkdir -p "$QUEUE_DIR", or before any .tmp.$$.* was ever created); this trap
# only prevents a crash BETWEEN the tmp-write and the mv (below) from littering QUEUE_DIR with
# an orphaned .tmp.$$.* file (id:0fa0 minor finding).
trap 'rm -f "$records_file" "$own_repos_file" "$QUEUE_DIR"/.tmp.$$.* 2>/dev/null || true' EXIT  # force-ok: the .tmp.$$.* glob may not expand and mktemp files may be gone on a crash — -f is ENOENT-tolerance here, not a destructive force

n_repos=0
while IFS=$'\t' read -r name path; do
  [[ -n "$name" ]] || continue
  n_repos=$((n_repos + 1))

  if [[ ! -d "$path" ]] || ! git -C "$path" rev-parse --git-dir >/dev/null 2>&1; then
    log "repo=$name path-missing-or-not-git=$path — surfacing, no discover-repo.sh call"
    reason="path not found or not a readable git repo: $path"
    out="$(REPO_ARG="$name" REASON_ARG="$reason" python3 -c '
import json, os
print(json.dumps({"units": [], "surfaced": [{"repo": os.environ["REPO_ARG"], "reason": os.environ["REASON_ARG"], "producer_error": True}], "skipped": []}))
')"
    printf '%s\t%s\t%s\t%s\n' "$name" "$path" "${SIG_BY_REPO[$name]:-}" "$out" >> "$records_file"
    continue
  fi

  # --no-reconcile (id:9d97 data-loss fix): this is a READ-ONLY verdict SNAPSHOT producer, so it
  # must never trigger reconcile-repo.sh's bounded SIDE-EFFECTS (fetch / ff-merge / uv.lock commit /
  # worktree reap+park). Passing NO --live-claims (this timer has no view of the live pool's
  # in-flight worktrees) would otherwise make reconcile treat every executor worktree as stale and
  # `git worktree remove --force` it — destroying uncommitted work. --no-reconcile takes the pure
  # classify path only. The LIVE dispatch loop (relay-loop.js) NEVER sets this flag AND never
  # consumes reconcile results from this snapshot: it runs reconcile-repo.sh LIVE per round for the
  # side-effecting half (reap/park/ff-merge/uv.lock/live-claims), taking only the classify verdict
  # from the queue when fresh — so its reconcile side-effects run every round on real pool state.
  if out="$("$DISCOVER_REPO" --repo "$name" --path "$path" --runid "$runid" \
            --live-claims "$live_claims" --main-branch "$main_branch" --no-reconcile 2>>"$LOG")"; then
    printf '%s\t%s\t%s\t%s\n' "$name" "$path" "${SIG_BY_REPO[$name]:-}" "$out" >> "$records_file"
  else
    rc=$?
    log "repo=$name discover-repo.sh FAILED rc=$rc"
    reason="discover-repo.sh exited $rc"
    out="$(REPO_ARG="$name" REASON_ARG="$reason" python3 -c '
import json, os
print(json.dumps({"units": [], "surfaced": [{"repo": os.environ["REPO_ARG"], "reason": os.environ["REASON_ARG"], "producer_error": True}], "skipped": []}))
')"
    printf '%s\t%s\t%s\t%s\n' "$name" "$path" "${SIG_BY_REPO[$name]:-}" "$out" >> "$records_file"
  fi
done < "$own_repos_file"

rm -- "$own_repos_file"   # mktemp'd above ⇒ exists; no -f needed

log "enumerated $n_repos confirmed own repo(s) from $RELAY_TOML"

# --- aggregate + schema-check (LOUD failure, never a half-written file) -----------------
generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
epoch="$(date +%s)"
run_tag="${runid:-noid}-${epoch}"

# PER-REPO ISOLATION (id:0fa0 finding b): a repo whose discover-repo.sh call exited 0 but
# emitted empty/non-JSON/non-object/malformed-field stdout is isolated into `surfaced` as a
# `producer_error` entry for THAT repo only — never lets one flaky repo abort assembly of
# every OTHER repo's already-collected verdict (the id:44-49 per-repo-isolation intent this
# assembly step had previously violated). Only a genuine internal failure (the records file
# itself unreadable) reaches the outer nonzero-exit guard below.
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
        name, path, sig, blob = line.split("\t", 3)
        repos.append({"repo": name, "path": path})

        err = None
        obj = None
        try:
            obj = json.loads(blob)
        except json.JSONDecodeError as exc:
            err = f"discover-repo.sh emitted invalid/empty JSON (rc 0): {exc}"
        else:
            if not isinstance(obj, dict):
                err = "discover-repo.sh emitted a non-object JSON value (rc 0)"
            else:
                for key in ("units", "surfaced", "skipped"):
                    if not isinstance(obj.get(key, []), list):
                        err = f"discover-repo.sh field {key!r} is not a list (rc 0)"
                        break

        if err is not None:
            sys.stderr.write(f"WARN: repo {name}: {err} — isolating into surfaced; other repos unaffected\n")
            # queue_sig on the synthesized producer_error entry too (id:4860) — consistent
            # shape; an errored repo has an empty ("") fail-open sig anyway (never matches).
            surfaced.append({"repo": name, "reason": err, "producer_error": True, "queue_sig": sig})
            continue

        # id:4860 — content-address the queue: stamp the per-repo discover-sig.sh value onto
        # every entry as queue_sig. The live consumer (relay-loop.js CASE A) copies a verdict
        # only when queue_sig == the live sig; a JS-side assert re-checks it as a mangle
        # canary. Fail-open: an empty sig is stamped as-is (never matches -> that repo always
        # falls to the live discover-repo.sh path).
        for key, bucket in (("units", units), ("surfaced", surfaced), ("skipped", skipped)):
            for entry in obj.get(key, []):
                if isinstance(entry, dict):
                    entry["queue_sig"] = sig
                bucket.append(entry)

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

# --- heartbeat = USABLE OUTPUT (id:0fa0 finding c) --------------------------------------
# The heartbeat must never be beaten on a snapshot that is nothing but `producer_error`
# entries — that would read as "producer healthy" when every confirmed repo actually failed.
# Beat only when at least one non-error entry exists: any units[] entry (a repo actually got
# classified), or any surfaced[]/skipped[] entry that is NOT `producer_error`-marked (a
# genuine verdict discover-repo.sh itself emitted, e.g. a dirty-repo surface). The snapshot
# is written either way (consumer transparency) — only the heartbeat beat is gated.
has_usable_output=1
if [[ "$n_repos" -gt 0 ]]; then
  python3 -c '
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    data = json.load(fh)
usable = bool(data["units"]) or any(not e.get("producer_error") for e in data["surfaced"]) \
         or any(not e.get("producer_error") for e in data["skipped"])
sys.exit(0 if usable else 1)
' "$QUEUE_DIR/latest.json" || has_usable_output=0
fi
# n_repos == 0 (relay.toml parsed OK but declared zero confirmed own repos, e.g. all paused,
# or the file is simply absent) is a legitimate empty state, not "producing garbage" — a
# genuine relay.toml parse FAILURE already exited loudly above, before any write. Beat the
# heartbeat as usual in this case.

if [[ "$has_usable_output" -eq 1 ]]; then
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
else
  echo "discover-repos-mechanical.sh: EVERY confirmed repo (n=$n_repos) errored this round — snapshot written for transparency but heartbeat NOT beaten (id:0fa0 finding c); the outage watchdog will correctly see the producer domain go stale." >&2
  log "ALL $n_repos repo(s) errored — heartbeat beat SKIPPED (id:0fa0 finding c)"
fi

echo "discover-repos-mechanical.sh: wrote $QUEUE_DIR/$snapshot_name (repos=$n_repos)"
