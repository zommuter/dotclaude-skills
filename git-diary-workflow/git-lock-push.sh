#!/usr/bin/env bash
# git-lock-push.sh — flock-serialized git pull --rebase + push
#
# Ensures parallel Claude sessions (or user) don't race on commit+push
# for the same repo. Run AFTER git commit — the commit is local and safe;
# only the pull+push needs serialization.
#
# Usage: git-lock-push.sh [-b branch]
#   -b  Branch to rebase against (default: detected from tracking branch)

set -euo pipefail

branch=""
while getopts "b:" opt; do
  case "$opt" in
    b) branch="$OPTARG" ;;
    *) echo "Usage: $0 [REPO_PATH] [-b branch]" >&2; exit 1 ;;
  esac
done
shift $((OPTIND - 1))

if [[ -n "${1:-}" ]]; then
  cd "$1"
fi

repo_root="$(git rev-parse --show-toplevel)"

# Lock file in repo root — except ~/.claude, where we use /tmp to avoid
# needing blanket write permissions on the settings directory.
if [[ "$repo_root" == "$HOME/.claude" ]]; then
  lock_file="/tmp/claude-git-dotclaude.lock"
else
  lock_file="$repo_root/.git-lock-push.lock"
fi

exec 8>"$lock_file"
if ! flock -x -w 30 8; then
  echo "WARNING: Could not acquire git lock after 30s. Commit saved locally, not pushed." >&2
  echo "Run 'git push' manually or it will push next session." >&2
  exec 8>&-
  exit 0  # non-fatal — work is committed
fi

# Detect tracking branch, fall back to origin main
if [[ -n "$branch" ]]; then
  target="$branch"
else
  target="$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null | tr '/' ' ')" || target="origin main"
fi

git pull --rebase --autostash $target

# push to all remotes (skip guard pushurls)
for remote in $(git remote); do
  pushurl=$(git remote get-url --push "$remote")
  [ "$pushurl" = "no_push" ] && continue
  git push "$remote"
done

exec 8>&-
