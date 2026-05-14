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

# Only pull if the remote branch exists (first-push scenario: skip rebase, just push)
remote_name="${target%% *}"
remote_branch="${target#* }"
if git ls-remote --exit-code "$remote_name" "refs/heads/$remote_branch" >/dev/null 2>&1; then
  git pull --rebase --autostash $target
fi

# push to all remotes (skip guard pushurls); set upstream on first push
current_branch="$(git rev-parse --abbrev-ref HEAD)"
for remote in $(git remote); do
  pushurl=$(git remote get-url --push "$remote")
  [ "$pushurl" = "no_push" ] && continue
  if git ls-remote --exit-code "$remote" "refs/heads/$current_branch" >/dev/null 2>&1; then
    git push "$remote"
  else
    git push --set-upstream "$remote" "$current_branch"
  fi
done

exec 8>&-
