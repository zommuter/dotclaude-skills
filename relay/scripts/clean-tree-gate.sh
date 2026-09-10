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
#   - Foreign-dirty (≥1 non-accepted porcelain entry) → print "dirty <N> (inspected: <path>)"
#     then the offending porcelain lines (each prefixed "  "), exit 2. Caller DEFERS: never
#     merges, never cleans.
#   - A ` M` entry whose worktree-vs-index diff is EMPTY is STAT-CACHE DIRT, not foreign dirt,
#     and does not block (id:8cc6; RELAY_STRICT_STATCACHE=1 restores strict). See the block
#     above the check for the git-annex measurement that motivates it and for the staged-change
#     trap it is narrowed around.
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
candidates=()
if [ -n "$porcelain" ]; then
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    path="${entry:3}"   # strip the 2-char XY status + 1 space
    # id:27b4 — an UNTRACKED entry ("??") is not foreign-dirty for merge purposes. A merge
    # that would overwrite an untracked file is refused by git itself, so the aa93 hazard
    # (a tracked edit clobbered by an agent) is unaffected; blocking on untracked files
    # instead silently parks repos (yinyang-puzzle: 19 days over two campaign assets).
    # Set RELAY_STRICT_UNTRACKED=1 to restore the old strict behaviour.
    if [ "${entry:0:2}" = "??" ] && [ "${RELAY_STRICT_UNTRACKED:-0}" != "1" ]; then
      continue
    fi
    accepted=0
    for pat in ${accepts[@]+"${accepts[@]}"}; do
      if [ "$path" = "$pat" ]; then accepted=1; break; fi
    done
    [ "$accepted" -eq 1 ] || candidates+=("$entry")
  done <<< "$porcelain"
fi

# ---- id:8cc6 -- THIRD carve-out: STAT-CACHE DIRT is not foreign dirt. --------------------
#
# THE DEFECT. `git status --porcelain` is CLEAN-FILTER-BLIND. On a git-annex repo with
# `annex.addunlocked`, checkout writes the 100-byte pointer, git stats it into the index, and
# annex swaps in the real content a fraction of a second later; git never re-stats. Every such
# path then reports ` M` forever while its worktree-vs-index DIFF IS EMPTY. Measured 2026-09-10
# on ~/src/code.lawless: 111 paths ` M`, `git diff` empty, and `git hash-object --path` against
# the index blob gave identical=111 / differing=0 -- byte-identical content, on all of them.
# Left uncarved, the id:aa93 dirty guard defers such a repo FOREVER: nothing a human does can
# clear dirt that is not there. That is the self-perpetuating backlog aa93's own design warns of.
#
# WHY `git update-index --really-refresh` DOES NOT HELP -- measured with GIT_TRACE, not assumed:
# it spawns ZERO subprocesses, so it never runs the clean filter, compares a 15,641-byte PNG
# against a 100-byte blob and reports `needs update`. `git diff --quiet` on the SAME path spawns
# `git-annex filter-process`, gets the pointer back, and reports equal. No amount of refreshing
# heals this; only a filter-aware comparison sees the truth. (`verify-isolation.sh` id:3016
# records the same measurement independently. Do not re-add a refresh here.)
#
# WHY IT DISCRIMINATES rather than blanket-relaxing: a LOCKED annexed file carries a genuinely
# stale device number and still reads clean, so ordinary stat drift self-heals; only the
# filter-requiring size mismatch is fatal, and only that survives to be carved out here.
#
# THE ONE WAY TO GET THIS CATASTROPHICALLY WRONG is to read "empty diff means clean". `git diff`
# (no `--cached`) sees WORKTREE-vs-INDEX only. A STAGED change (`M `, `A `, `D `) is invisible to
# it, so a blanket relaxation would collapse real staged work into "clean" and hand it to a merge.
# The carve-out is therefore keyed on the exact XY pair ` M` -- index column BLANK. Anything
# staged, added, deleted, renamed, copied or conflicted keeps a non-` M` pair and still blocks,
# as do untracked entries (which `git diff` never reports at all).
#
# COST: ONE `git diff --name-only` for the whole repo, set-subtracted from the ` M` paths. Never
# one invocation per path -- 111 paths would mean 111 annex filter spawns.
#
# FAIL-CLOSED, LOUD: if that diff fails we say so on stderr and treat every ` M` entry as dirty.
# A false "dirty" defers a repo; a false "clean" lets a child commit over someone's work.
# `RELAY_STRICT_STATCACHE=1` restores the old strict behaviour (mirrors RELAY_STRICT_UNTRACKED).
#
# OBSERVE ONLY, still: `git update-index -- <paths>` would make this dirt vanish permanently and
# is content-neutral, but it is a WRITE to the index of a repo this gate only inspects. Not done
# here, deliberately -- see the header contract.
declare -A unstaged_paths=()
statcache_mode=0   # 0 = carve-out inactive, 1 = active, 2 = diff failed -> fail closed
if [ "${RELAY_STRICT_STATCACHE:-0}" != "1" ]; then
  for e in ${candidates[@]+"${candidates[@]}"}; do
    if [ "${e:0:2}" = " M" ]; then statcache_mode=1; break; fi
  done
fi
if [ "$statcache_mode" -eq 1 ]; then
  # No 2>/dev/null and no `|| true`: a failing diff must be visible and must block.
  if diff_names="$(git -C "$repo" diff --name-only)"; then
    while IFS= read -r dp; do
      [ -n "$dp" ] || continue
      unstaged_paths["$dp"]=1
    done <<< "$diff_names"
  else
    echo "clean-tree-gate.sh: 'git diff --name-only' failed in '$repo' -- treating every worktree-modified entry as DIRTY (fail-closed, id:8cc6)" >&2
    log "diff-failed repo=$repo -- fail-closed, statcache carve-out disabled"
    statcache_mode=2
  fi
fi

offending=()
n_statcache=0
for e in ${candidates[@]+"${candidates[@]}"}; do
  if [ "$statcache_mode" -eq 1 ] && [ "${e:0:2}" = " M" ]; then
    p="${e:3}"
    if [ -z "${unstaged_paths[$p]+set}" ]; then
      n_statcache=$((n_statcache + 1))
      continue
    fi
  fi
  offending+=("$e")
done
[ "$n_statcache" -eq 0 ] || log "statcache-dirt repo=$repo carved=$n_statcache (id:8cc6)"

n="${#offending[@]}"
if [ "$n" -eq 0 ]; then
  log "clean repo=$repo (accepts=${#accepts[@]})"
  echo "clean"
  exit 0
fi

# FOREIGN-DIRTY → defer. Report, never clean.
#
# id:8cc6 -- the dirty line NAMES the path actually inspected. It used to say only "dirty <N>",
# so every consumer had to supply its own noun for it, and one of them said "main checkout"
# while the gate had been pointed at a WORKTREE: an operator sent to inspect a checkout that
# was in fact clean. The path is APPENDED, never prepended, because consumers prefix-match this
# line (`[[ "$out" == dirty\ * ]]`) and the per-entry parser keys on the two-space indent below.
log "dirty repo=$repo n=$n entries=[$(printf '%s; ' "${offending[@]}")]"
echo "dirty $n (inspected: $repo)"
for e in "${offending[@]}"; do
  printf '  %s\n' "$e"
done
exit 2
