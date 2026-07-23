#!/usr/bin/env bash
# relay/scripts/discover-chunk.sh — deterministic, mechanical DISCOVER-RUN SHARD (id:24ec).
#
# WHY: the `discover-run` shard in relay-loop.js (label 'discover-run') used to be a
# `model:'haiku'` agent() whose ONLY job was pure transport — run reconcile+classify per repo
# in a CHUNK and echo the concatenated JSON verbatim, no judgment (classify-verdict never emits
# AMBIGUOUS today). Haiku has been observed to MANGLE even that (2026-07-07 discovery-off-
# Workflow meeting, D2), so — like the discover-prelude (id:86a2) and the id:6176 mechanical
# hops before it — the whole per-chunk loop is wrapped into ONE deterministic script dispatched
# via a single `model:'bash'` (```relay-mech) fence. This is the id:c14d pattern (a former
# multi-step Haiku prompt → "run exactly this command") applied to the discovery shard, un-gated
# by the id:a36e proxy fix.
#
# CONTRACT (CASE B — the SHIPPED default: no fresh id:9d97 discovery queue is consumed here):
#   discover-chunk.sh --runid <id> --live-claims <csv> [--main-branch <name>]
#                     [--queue-latest <path>] [--queue-fresh-secs <n>]
#     reads a CHUNK JSON array on stdin:  [{"repo":<name>,"path":<abs>,"sig":<hex-or-"">}, ...]
#     emits ONE JSON on stdout: {"units":[...],"surfaced":[...],"skipped":[...]}
#       = the CONCATENATION, in chunk order, of discover-repo.sh's output for each repo
#         (LIVE reconcile+classify — NO --no-reconcile; the live loop's reap/park is load-bearing).
#
# LIVE per repo (id:9d97): discover-repo.sh runs WITHOUT --no-reconcile, so reconcile-repo.sh's
# bounded SIDE-EFFECTS (fetch / ff-merge behind-origin / uv.lock cascade commit / worktree
# reap+park + orphan suppress-redispatch / live-claims filtering) run every round on real pool
# state — exactly the behaviour the old Haiku shard's CASE-B branch performed. --live-claims +
# --runid are threaded through so a live executor's worktree is NEVER reaped as stale.
#
# --sig is IGNORED here (CASE B): the per-repo `sig` field in the chunk is only used by the
# CASE-A content-address copy of the id:9d97 queue verdict (the id:7402/6eb3 residual LLM read),
# which is OUT OF THIS SCRIPT'S SCOPE (a gated follow-on, id:6eb3). --queue-latest /
# --queue-fresh-secs are accepted for signature/forward-compat but UNUSED — this script always
# takes the full live discover-repo.sh path (CASE B). Adding CASE A here is deliberately deferred.
#
# DETERMINISTIC + NO LLM: pure bash/python composition of discover-repo.sh; no agent(), no
# `claude -p`. Two invocations on the same on-disk state produce byte-identical output (the only
# non-determinism discover-repo.sh carries is a genuine reconcile side-effect that MUTATED state
# between calls — by design, the live loop wants that).
#
# PER-REPO ISOLATION (mirrors discover-repos-mechanical.sh id:0fa0 finding b / no-silent-swallow
# id:4347): a repo whose path is missing/not-a-git-repo, or whose discover-repo.sh call exits
# nonzero or emits empty/non-JSON/malformed stdout, is isolated into `surfaced` as a
# {repo,reason,producer_error:true} entry for THAT repo only — it NEVER aborts the concatenation
# of the other repos' verdicts, and is NEVER silently dropped.
#
# NO-FILESYSTEM-HUNTING (mirrors discover-repo.sh id:612f): this script runs NO git commands of
# its own beyond the per-repo is-a-git-repo probe and does NO ledger/transcript reading — it only
# parses the stdin chunk and execs discover-repo.sh, which already does everything else.
#
# Env overrides (hermetic testing; mirror the sibling scripts' idiom): RELAY_WORKTREE_BASE /
# RELAY_TOML / CLAIM env are threaded straight to discover-repo.sh's sub-scripts, unchanged.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISCOVER_REPO="$SCRIPT_DIR/discover-repo.sh"

LOG="${RELAY_DISCOVER_CHUNK_LOG:-$HOME/.claude/logs/discover-chunk.log}"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
log() { printf '%s discover-chunk.sh %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >>"$LOG" 2>/dev/null || true; }

runid="" live_claims="" main_branch="" queue_latest="" queue_fresh_secs=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --runid) runid="$2"; shift 2 ;;
    --live-claims) live_claims="$2"; shift 2 ;;
    --main-branch) main_branch="$2"; shift 2 ;;
    --queue-latest) queue_latest="$2"; shift 2 ;;          # reserved (CASE A, id:6eb3) — unused here
    --queue-fresh-secs) queue_fresh_secs="$2"; shift 2 ;;  # reserved (CASE A, id:6eb3) — unused here
    *) echo "discover-chunk.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ ! -x "$DISCOVER_REPO" ]]; then
  echo "discover-chunk.sh: discover-repo.sh not found/executable at $DISCOVER_REPO" >&2
  exit 1
fi

# --- parse the stdin chunk into a TSV of "<repo>\t<path>" rows (LOUD on malformed input) ------
chunk_raw="$(cat)"
records_file="$(mktemp)"
trap 'rm -- "$records_file" 2>/dev/null || true' EXIT

if ! CHUNK="$chunk_raw" python3 -c '
import json, os, sys
raw = os.environ.get("CHUNK", "")
if not raw.strip():
    # An empty chunk is a legitimate empty shard (zero repos) — emit no rows.
    sys.exit(0)
try:
    arr = json.loads(raw)
except json.JSONDecodeError as exc:
    sys.stderr.write("discover-chunk.sh: stdin chunk is not valid JSON: %s\n" % exc)
    sys.exit(3)
if not isinstance(arr, list):
    sys.stderr.write("discover-chunk.sh: stdin chunk must be a JSON array, got %s\n" % type(arr).__name__)
    sys.exit(3)
for entry in arr:
    if not isinstance(entry, dict):
        sys.stderr.write("discover-chunk.sh: chunk entry is not an object: %r\n" % (entry,))
        sys.exit(3)
    repo = entry.get("repo")
    path = entry.get("path")
    if not repo or not path:
        sys.stderr.write("discover-chunk.sh: chunk entry missing repo/path: %r\n" % (entry,))
        sys.exit(3)
    # sig is intentionally ignored here (CASE B). Tabs/newlines in names would corrupt the TSV.
    if "\t" in repo or "\n" in repo or "\t" in path or "\n" in path:
        sys.stderr.write("discover-chunk.sh: repo/path contains a tab/newline: %r\n" % (entry,))
        sys.exit(3)
    sys.stdout.write("%s\t%s\n" % (repo, path))
' > "$records_file"; then
  echo "discover-chunk.sh: FAILED to parse the stdin chunk — NOTHING emitted (see $LOG)." >&2
  log "chunk parse FAILED — aborting before any output"
  exit 3
fi

# --- run discover-repo.sh LIVE per repo, in chunk order (per-repo isolated) -------------------
# One NDJSON record per repo: "<json-object-from-discover-repo.sh>" (or a synthesized
# producer_error object for a repo this script could not classify), collected in chunk order.
outputs_file="$(mktemp)"
# shellcheck disable=SC2064
trap 'rm -- "$records_file" "$outputs_file" 2>/dev/null || true' EXIT

n_repos=0
while IFS=$'\t' read -r name path; do
  [[ -n "$name" ]] || continue
  n_repos=$((n_repos + 1))

  if [[ ! -d "$path" ]] || ! git -C "$path" rev-parse --git-dir >/dev/null 2>&1; then
    log "repo=$name path-missing-or-not-git=$path — surfacing producer_error, no discover-repo.sh call"
    reason="path not found or not a readable git repo: $path"
    REPO_ARG="$name" REASON_ARG="$reason" python3 -c '
import json, os
print(json.dumps({"units": [], "surfaced": [{"repo": os.environ["REPO_ARG"], "reason": os.environ["REASON_ARG"], "producer_error": True}], "skipped": []}))
' >> "$outputs_file"
    continue
  fi

  # LIVE (NO --no-reconcile): discover-repo.sh runs reconcile-repo.sh's bounded side-effects +
  # classify-repo.sh, threading --live-claims + --runid so an in-flight executor worktree is
  # protected. --main-branch is threaded ONLY when the caller passed it; absent, discover-repo.sh
  # resolves each repo's trunk from HEAD (trunk-branch.sh) — matching the old CASE-B shard, which
  # never forced a branch name.
  mb_args=()
  [[ -n "$main_branch" ]] && mb_args=(--main-branch "$main_branch")
  if out="$("$DISCOVER_REPO" --repo "$name" --path "$path" --runid "$runid" \
            --live-claims "$live_claims" "${mb_args[@]}" 2>>"$LOG")"; then
    if [[ -n "${out//[[:space:]]/}" ]]; then
      printf '%s\n' "$out" >> "$outputs_file"
    else
      log "repo=$name discover-repo.sh emitted empty stdout (rc 0) — surfacing producer_error"
      REPO_ARG="$name" python3 -c '
import json, os
print(json.dumps({"units": [], "surfaced": [{"repo": os.environ["REPO_ARG"], "reason": "discover-repo.sh emitted empty stdout (rc 0)", "producer_error": True}], "skipped": []}))
' >> "$outputs_file"
    fi
  else
    rc=$?
    log "repo=$name discover-repo.sh FAILED rc=$rc"
    REPO_ARG="$name" RC_ARG="$rc" python3 -c '
import json, os
print(json.dumps({"units": [], "surfaced": [{"repo": os.environ["REPO_ARG"], "reason": "discover-repo.sh exited " + os.environ["RC_ARG"], "producer_error": True}], "skipped": []}))
' >> "$outputs_file"
  fi
done < "$records_file"

log "ran discover-repo.sh LIVE for $n_repos repo(s) in chunk"

# --- fold the per-repo outputs into ONE {units,surfaced,skipped} (concatenation, chunk order) --
# PER-REPO ISOLATION (id:4347): a per-repo blob that is empty/non-JSON/non-object/malformed is
# isolated into surfaced as a producer_error entry — never aborts assembly of the other repos.
python3 -c '
import json, sys

units = []
surfaced = []
skipped = []

with open(sys.argv[1], encoding="utf-8") as fh:
    for line in fh:
        line = line.rstrip("\n")
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError as exc:
            sys.stderr.write("WARN: discover-repo.sh emitted invalid JSON — isolating: %s\n" % exc)
            surfaced.append({"repo": "?", "reason": "discover-repo.sh emitted invalid JSON: %s" % exc, "producer_error": True})
            continue
        if not isinstance(obj, dict):
            surfaced.append({"repo": "?", "reason": "discover-repo.sh emitted a non-object JSON value", "producer_error": True})
            continue
        ok = True
        for key in ("units", "surfaced", "skipped"):
            if not isinstance(obj.get(key, []), list):
                surfaced.append({"repo": "?", "reason": "discover-repo.sh field %r is not a list" % key, "producer_error": True})
                ok = False
                break
        if not ok:
            continue
        units.extend(obj.get("units", []))
        surfaced.extend(obj.get("surfaced", []))
        skipped.extend(obj.get("skipped", []))

print(json.dumps({"units": units, "surfaced": surfaced, "skipped": skipped}))
' "$outputs_file"
