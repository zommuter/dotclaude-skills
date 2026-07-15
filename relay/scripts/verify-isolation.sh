#!/usr/bin/env bash
# verify-isolation.sh — DETERMINISTIC, FAIL-SAFE "did this child actually work in its
# worktree?" gate for the relay integrator (id:f682).
#
# Motivation (observed 2026-07-14, loderite R2 consumer handoff): a spawned child correctly
# ran `git worktree add …` but then wrote every edit to the target's MAIN checkout instead
# (repo-root-relative paths, never `cd`-ing into the worktree). Its worktree stayed EMPTY (0
# commits ahead of base), so its "commit in worktree" self-report was a no-op and wrong; the
# whole handoff's changes landed loose in the main checkout, mixed with unrelated in-flight
# edits, and had to be reconciled by hand. This gate lets the integrator (invariant 5) catch
# that BEFORE merging — mirrors clean-tree-gate.sh's shape: observe-only, fail-safe, exit
# 0 = safe to merge / exit 2 = isolation failure, never mutates.
#
# Usage:
#   verify-isolation.sh <worktree> [--base <ref>]   (default --base origin/main, falling
#                                                      back to the checkout's current branch
#                                                      if origin/main does not resolve)
#
# Behavior:
#   (a) worktree has ≥1 commit beyond base AND a clean tree → print "ok …", exit 0.
#   (b) EMPTY worktree (no commits beyond base)             → exit 2, names the isolation
#                                                                failure (empty/no commits).
#   (c) worktree has commits beyond base but a DIRTY tree   → exit 2, names dirty entries.
#   (d) non-existent path / not a git worktree               → exit 2, stderr message.
#
# This script ONLY observes (git log / git status). It NEVER runs stash / reset --hard /
# checkout -- / clean. The caller aborts the merge and defers on any non-zero exit — never
# attempts to "fix" an isolation failure itself; recovery is the id:15d5 main-checkout-under-
# lease pattern (see relay/references/conventions.md).
set -euo pipefail

LOG="${VERIFY_ISOLATION_LOG:-$HOME/.claude/logs/relay-verify-isolation.log}"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

log() { printf '%s verify-isolation.sh %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >>"$LOG" 2>/dev/null || true; }

worktree="${1:-}"; shift || true
base=""
while [ $# -gt 0 ]; do
  case "$1" in
    --base) shift; [ $# -gt 0 ] || { echo "verify-isolation.sh: --base needs a ref" >&2; exit 2; }; base="$1"; shift ;;
    *) echo "verify-isolation.sh: unknown arg '$1'" >&2; exit 2 ;;
  esac
done

[ -n "$worktree" ] || { echo "verify-isolation.sh: <worktree> required" >&2; exit 2; }
if [ ! -d "$worktree" ] || ! git -C "$worktree" rev-parse --git-dir >/dev/null 2>&1; then
  echo "verify-isolation.sh: '$worktree' is not a git worktree" >&2
  exit 2
fi

# Resolve the base ref: explicit --base wins; else origin/main; else the worktree's own
# current branch's upstream is unavailable in a bare test repo, so fall back to whatever
# the local default branch is (best-effort, observe-only — never fails the gate by itself).
if [ -z "$base" ]; then
  if git -C "$worktree" rev-parse --verify -q origin/main >/dev/null 2>&1; then
    base="origin/main"
  else
    default_branch="$(git -C "$worktree" symbolic-ref --short -q refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')"
    base="${default_branch:-main}"
  fi
fi

if ! git -C "$worktree" rev-parse --verify -q "$base" >/dev/null 2>&1; then
  echo "verify-isolation.sh: base ref '$base' does not resolve in '$worktree'" >&2
  exit 2
fi

# (a)/(b): commits beyond base?
commits="$(git -C "$worktree" log --oneline "$base"..HEAD 2>/dev/null || true)"
if [ -z "$commits" ]; then
  log "empty worktree=$worktree base=$base"
  echo "isolation failure: worktree has NO commits beyond base '$base' — likely a child that wrote to the main checkout instead of this worktree (empty/no commits ahead)"
  exit 2
fi

# (c): dirty tree?
porcelain="$(git -C "$worktree" status --porcelain 2>/dev/null || true)"
if [ -n "$porcelain" ]; then
  log "dirty worktree=$worktree base=$base"
  echo "isolation failure: worktree has a DIRTY tree (uncommitted changes) — not safe to merge"
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    printf '  %s\n' "$entry"
  done <<< "$porcelain"
  exit 2
fi

n_commits="$(printf '%s\n' "$commits" | wc -l | tr -d ' ')"
log "ok worktree=$worktree base=$base commits=$n_commits"
echo "ok: $n_commits commit(s) beyond '$base', tree clean"
exit 0
