#!/usr/bin/env bash
# relay/scripts/discover-repo.sh — per-repo discovery composition (id:64b4)
#
# Composes reconcile-repo.sh (side-effecting git, id:5987) + classify-repo.sh --emit unit
# (full DISCOVER_SCHEMA unit, id:3d61) and applies the discovery ROUTING for ONE repo, so the
# mechanical runner can replace the LLM discovery shard (flip step b, id:a0b6).
#
# Usage: discover-repo.sh --repo <name> --path <abs> [--runid <id>]
#                          [--live-claims <comma-list>] [--main-branch <name>]
#                          [--no-reconcile]
#
# Emits ONE JSON object on stdout: {"units":[…0 or 1…],"surfaced":[…],"skipped":[…]}
#
# --no-reconcile (id:9d97 data-loss fix): SKIP reconcile-repo.sh entirely — run ONLY the
#   side-effect-free classify path (classify-repo.sh --emit unit). Reconcile-repo.sh performs
#   BOUNDED SIDE-EFFECTING git (fetch, ff-merge, uv.lock commit, and worktree reap/park =
#   `git worktree remove --force` + branch rename). That reap/park is CORRECT and load-bearing
#   for the LIVE dispatch loop (relay-loop.js), which protects in-flight worktrees by passing
#   --live-claims + --runid. But a READ-ONLY *snapshot* producer (discover-repos-mechanical.sh,
#   a 15-min timer) passes NO live-claims, so reconcile would treat every executor worktree as
#   stale and destroy it. --no-reconcile lets that producer classify without mutating anything.
#   The live loop NEVER passes this flag → its reconcile+reap behaviour is byte-for-byte unchanged.
#
# ROUTING:
#   1. Unless --no-reconcile: run reconcile-repo.sh. If its surfaced array is non-empty → return
#      it verbatim (units:[], skipped:[]) and STOP — do NOT classify, never double-surface.
#   2. Else run classify-repo.sh --emit unit and route by unit.verdict:
#        blocked    → surfaced += {repo,reason}; no unit
#        AMBIGUOUS  → surfaced += {repo,reason: loud}; no unit (dormant hook, NO LLM call)
#        idle       → units += unit; skipped += {repo,reason}
#        else       → units += unit
#
# discover-repo.sh itself makes NO git calls and NO filesystem hunting (id:612f) — it only
# invokes the two sibling scripts and folds their JSON. RELAY_WORKTREE_BASE / RELAY_TOML are
# passed through to the sub-scripts unchanged via env (not stripped).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RECONCILE="$SCRIPT_DIR/reconcile-repo.sh"
CLASSIFY="$SCRIPT_DIR/classify-repo.sh"

repo="" path="" runid="" live_claims="" main_branch="main" no_reconcile=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    --path) path="$2"; shift 2 ;;
    --runid) runid="$2"; shift 2 ;;
    --live-claims) live_claims="$2"; shift 2 ;;
    --main-branch) main_branch="$2"; shift 2 ;;
    --no-reconcile) no_reconcile=1; shift ;;
    *) echo "discover-repo.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$repo" ]] || { echo "discover-repo.sh: --repo is required" >&2; exit 2; }
[[ -n "$path" ]] || { echo "discover-repo.sh: --path is required" >&2; exit 2; }

# Step 1 (SKIPPED under --no-reconcile — id:9d97): bounded side-effecting reconcile. The live
# dispatch loop always runs this (its reap/park is load-bearing); the read-only snapshot
# producer sets --no-reconcile so it never mutates a live executor's worktree.
if [[ -z "$no_reconcile" ]]; then
  rec_json="$("$RECONCILE" --repo "$repo" --path "$path" --runid "$runid" \
              --live-claims "$live_claims" --main-branch "$main_branch")"

  rec_surfaced_count="$(printf '%s' "$rec_json" | python3 -c 'import sys,json; print(len(json.load(sys.stdin).get("surfaced", [])))')"

  if [[ "$rec_surfaced_count" -gt 0 ]]; then
    printf '%s' "$rec_json" | python3 -c '
import sys, json
rec = json.load(sys.stdin)
print(json.dumps({"units": [], "surfaced": rec.get("surfaced", []), "skipped": []}))
'
    exit 0
  fi
fi

unit_json="$("$CLASSIFY" --emit unit --repo "$repo" --path "$path")"

REPO_ARG="$repo" python3 -c '
import json, os, sys

repo = os.environ["REPO_ARG"]
unit = json.load(sys.stdin)
verdict = unit.get("verdict", "")

if verdict == "blocked":
    out = {"units": [], "surfaced": [{"repo": repo, "reason": unit.get("reason", "")}], "skipped": []}
elif verdict == "AMBIGUOUS":
    out = {"units": [], "surfaced": [{"repo": repo, "reason": "classifier returned AMBIGUOUS — needs LLM/human triage (loud, id:a0b6)"}], "skipped": []}
elif verdict == "idle":
    out = {"units": [unit], "surfaced": [], "skipped": [{"repo": repo, "reason": unit.get("reason", "")}]}
else:
    out = {"units": [unit], "surfaced": [], "skipped": []}

print(json.dumps(out))
' <<< "$unit_json"
