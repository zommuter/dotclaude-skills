#!/usr/bin/env bash
# sync-origin.sh — "is this local clone safe to commit on?" check for the relay (id:c3f7).
# Motivated by the 2026-06-15 ai-codebench incident: a clone ~1 month behind origin got
# a doomed parallel timeline. Before the relay commits in a repo, it asks: are we in sync
# with origin, merely behind (catch up), or diverged (abort — don't fork the timeline)?
#
# Usage:
#   sync-origin.sh <repo-path> [--ff]
#
# Behavior (all git ops via `git -C <repo-path>`):
#   1. `git fetch origin -q` (fetch failure — offline/missing remote — is ignored; we
#      continue with whatever the local remote-tracking ref already has).
#   2. Resolve upstream U = @{upstream}. No upstream → print "no-upstream", exit 0.
#   3. ahead/behind via `git rev-list --left-right --count HEAD...U` (ahead behind).
#   4. Decide:
#        ahead>0 AND behind>0          → "diverged <ahead> <behind>" ; exit 3
#        ahead==0 AND behind>0:
#            --ff AND clean worktree   → merge --ff-only U, "ff <behind>" ; exit 0
#            else                      → "behind <behind>" ; exit 2
#        otherwise (in sync / ahead)   → "ok" ; exit 0
#
# Prints exactly one status word/line to stdout. Details logged to
# $SYNC_LOG (default ~/.claude/logs/relay-sync.log). Missing/non-git path → stderr + exit 2.
set -euo pipefail

LOG="${SYNC_LOG:-$HOME/.claude/logs/relay-sync.log}"
mkdir -p "$(dirname "$LOG")"

log() { printf '%s sync-origin.sh %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >>"$LOG" 2>/dev/null || true; }

repo="${1:-}"; shift || true
ff=0
while [ $# -gt 0 ]; do
  case "$1" in
    --ff) ff=1; shift ;;
    *) echo "sync-origin.sh: unknown arg '$1'" >&2; exit 2 ;;
  esac
done

[ -n "$repo" ] || { echo "sync-origin.sh: <repo-path> required" >&2; exit 2; }
if [ ! -d "$repo" ] || ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
  echo "sync-origin.sh: '$repo' is not a git repository" >&2
  exit 2
fi

# 1. Best-effort fetch; offline / missing remote is non-fatal.
git -C "$repo" fetch origin -q 2>/dev/null || log "fetch failed (offline/no-remote) repo=$repo"

# 2. Resolve upstream (must not crash under set -e when absent).
upstream=""
if upstream="$(git -C "$repo" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)"; then
  :
else
  upstream=""
fi
if [ -z "$upstream" ]; then
  log "no-upstream repo=$repo"
  echo "no-upstream"
  exit 0
fi

# 3. ahead/behind. Guard against rev-list failure (e.g. unrelated histories).
counts=""
if ! counts="$(git -C "$repo" rev-list --left-right --count "HEAD...$upstream" 2>/dev/null)"; then
  log "rev-list failed repo=$repo upstream=$upstream"
  echo "ok"
  exit 0
fi
ahead="${counts%%[[:space:]]*}"
behind="${counts##*[[:space:]]}"
ahead="${ahead:-0}"
behind="${behind:-0}"

# 4. Decide.
if [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ]; then
  log "diverged repo=$repo upstream=$upstream ahead=$ahead behind=$behind"
  echo "diverged $ahead $behind"
  exit 3
fi

if [ "$ahead" -eq 0 ] && [ "$behind" -gt 0 ]; then
  if [ "$ff" -eq 1 ] && [ -z "$(git -C "$repo" status --porcelain 2>/dev/null)" ]; then
    if git -C "$repo" merge --ff-only "$upstream" >/dev/null 2>&1; then
      log "ff repo=$repo upstream=$upstream behind=$behind"
      echo "ff $behind"
      exit 0
    fi
    log "ff-only merge failed repo=$repo upstream=$upstream behind=$behind"
  fi
  log "behind repo=$repo upstream=$upstream behind=$behind ff=$ff"
  echo "behind $behind"
  exit 2
fi

log "ok repo=$repo upstream=$upstream ahead=$ahead behind=$behind"
echo "ok"
exit 0
