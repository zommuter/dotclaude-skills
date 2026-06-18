#!/usr/bin/env bash
# clean-tree-gate.sh — DETERMINISTIC, FAIL-SAFE "is this main checkout safe to integrate on?"
# gate for the relay integrator (id:aa93).
#
# Motivation (data-loss bug observed 3× on 2026-06-18): the integrate step's "verify clean
# tree, abort if dirty" was an LLM-agent PROMPT, not a deterministic gate. A foreign-dirty
# main checkout (a human/parallel-session's tracked-but-unstaged edit) was silently destroyed
# when the integrator agent "cleaned" the tree (git stash+drop / checkout -- / reset --hard)
# to make room for its --no-ff merge. reflog showed `reset: moving to HEAD`, stash list EMPTY
# — real, unrecoverable loss. This script replaces the agent's judgement with a hard rule:
#
#   The integrator works on a child's WORKTREE, never on the main checkout. So at integrate
#   time the main checkout MUST already be clean. ANY dirty entry is therefore FOREIGN
#   (a concurrent editor's work) — DEFER the repo and surface it; NEVER force-clean.
#
# This script ONLY observes (git status --porcelain). It NEVER runs stash / checkout -- /
# reset --hard / clean. The caller (relay-loop.js integrate step 1) must likewise NEVER
# attempt to clean a foreign-dirty tree — on a non-zero exit it aborts the merge and defers.
#
# Usage:
#   clean-tree-gate.sh <repo-path> [--accept <pattern>]...
#
#   --accept <pattern>  A porcelain PATH (exact, as printed after the XY status code) that is
#                       declared acceptable and does NOT count as foreign-dirty (e.g. a
#                       build artifact a repo's relay.toml comment whitelists). Repeatable.
#                       Match is exact on the path field; default (no --accept) = strict.
#
# Behavior:
#   - Not a git repo / missing path → stderr message, exit 2.
#   - Tree clean (or every dirty entry is --accept-ed) → print "clean", exit 0.
#   - Foreign-dirty (≥1 non-accepted porcelain entry) → print "dirty <N>" then the offending
#     porcelain lines (each prefixed "  "), exit 2. Caller DEFERS — never merges, never cleans.
#
# Exit codes mirror sync-origin.sh's convention: 0 = safe to proceed, 2 = not safe / error.
set -euo pipefail

LOG="${CLEAN_TREE_LOG:-$HOME/.claude/logs/relay-clean-tree.log}"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

log() { printf '%s clean-tree-gate.sh %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >>"$LOG" 2>/dev/null || true; }

repo="${1:-}"; shift || true
accepts=()
while [ $# -gt 0 ]; do
  case "$1" in
    --accept) shift; [ $# -gt 0 ] || { echo "clean-tree-gate.sh: --accept needs a pattern" >&2; exit 2; }; accepts+=("$1"); shift ;;
    *) echo "clean-tree-gate.sh: unknown arg '$1'" >&2; exit 2 ;;
  esac
done

[ -n "$repo" ] || { echo "clean-tree-gate.sh: <repo-path> required" >&2; exit 2; }
if [ ! -d "$repo" ] || ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
  echo "clean-tree-gate.sh: '$repo' is not a git repository" >&2
  exit 2
fi

# Observe ONLY. Newline-delimited porcelain (paths with embedded newlines — vanishingly
# rare — are git-quoted, so one entry per line holds).
porcelain=""
if ! porcelain="$(git -C "$repo" status --porcelain 2>/dev/null)"; then
  echo "clean-tree-gate.sh: 'git status' failed in '$repo'" >&2
  exit 2
fi

# Collect non-accepted entries. Porcelain record: "XY <path>" (rename shows "orig -> new";
# we keep the whole record as one offending line for the human).
offending=()
if [ -n "$porcelain" ]; then
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    path="${entry:3}"   # strip the 2-char XY status + 1 space
    accepted=0
    for pat in ${accepts[@]+"${accepts[@]}"}; do
      if [ "$path" = "$pat" ]; then accepted=1; break; fi
    done
    [ "$accepted" -eq 1 ] || offending+=("$entry")
  done <<< "$porcelain"
fi

n="${#offending[@]}"
if [ "$n" -eq 0 ]; then
  log "clean repo=$repo (accepts=${#accepts[@]})"
  echo "clean"
  exit 0
fi

# FOREIGN-DIRTY → defer. Report, never clean.
log "dirty repo=$repo n=$n entries=[$(printf '%s; ' "${offending[@]}")]"
echo "dirty $n"
for e in "${offending[@]}"; do
  printf '  %s\n' "$e"
done
exit 2
