#!/usr/bin/env bash
# provision-worktree.sh — id:34b7 parts (1)+(2): the PARENT creates + provisions a
# relay child's worktree BEFORE dispatch, so the child is never handed the main-checkout
# path and has no reason or means to reach into it.
#
#   (1) `git worktree add` — moved here from the child prompt's "Create your worktree
#       first" instruction (relay-loop.js's unitPrompt()/provisionWorktree()).
#   (2) provision the gitignored build artifacts a child would otherwise have to reach
#       into main for — symlinked, best-effort. Children already did this by hand,
#       per-child, every time (loderite RELAY_LOG.md:2681, with :3022/:3422/:3486 showing
#       them removing the symlink again before commit) — this absorbs that manual step.
#       Deliberately NOT exhaustive of every artifact class a repo might have, just the
#       two named in id:34b7's own text (node_modules, .venv); a missing class is a
#       no-op, not a failure.
#
# Usage: provision-worktree.sh <repo-path> <worktree-dir> <branch>
#
# SCOPE: operates on exactly the one <repo-path>/<worktree-dir>/<branch> passed — no
# globbing, no discovery (same single-target discipline as worktree-retire.sh, id:6e02).
set -euo pipefail

repo_path="${1:?usage: provision-worktree.sh <repo-path> <worktree-dir> <branch>}"
wt="${2:?usage: provision-worktree.sh <repo-path> <worktree-dir> <branch>}"
branch="${3:?usage: provision-worktree.sh <repo-path> <worktree-dir> <branch>}"

git -C "$repo_path" worktree add "$wt" -b "$branch" HEAD

# Part (2), best-effort — a repo missing either artifact class is a no-op, never fatal.
# The trailing `|| true` is DELIBERATE and scoped to these two lines only: under
# `set -euo pipefail` a bare failing `[[ … ]]` would abort the script, and a repo with
# neither artifact class must not be a provisioning failure. Do NOT "clean this up".
[[ -d "$repo_path/node_modules" ]] && ln -s "$repo_path/node_modules" "$wt/node_modules" || true
[[ -d "$repo_path/.venv" ]] && ln -s "$repo_path/.venv" "$wt/.venv" || true

# id:76d2 — the symlinks above must not DIRTY the worktree. The idiomatic gitignore form is
# the trailing-slash DIRECTORY pattern (`.venv/`), and git does NOT match a symlink against it:
# the provisioned link shows as `?? .venv`, verify-isolation.sh (id:f682) correctly refuses the
# merge, and the child's work parks unmerged (live loss: run relay-20260812-001727-5554).
# So the provisioner excludes exactly the names IT created, via git's local, never-committed
# exclude file. No repo's committed .gitignore is touched, and the isolation gate keeps
# special-casing nothing (a name-based carve-out there would also hide a genuine breach).
#
# VERIFIED (git 2.55): a linked worktree's `info/exclude` resolves to the repo-COMMON
# `.git/info/exclude` — a per-worktree `.git/worktrees/<name>/info/exclude` is NOT honoured by
# git at all, so the common file is the only working target. It is still local-only (never
# committed, never part of `git status --porcelain` for any checkout). Resolve it via rev-parse
# rather than assuming `<wt>/.git/info/exclude`: in a linked worktree `<wt>/.git` is a FILE.
excluded=()
for _name in node_modules .venv; do
  if [[ -L "$wt/$_name" ]]; then excluded+=("$_name"); fi
done
if (( ${#excluded[@]} )); then
  exclude_file="$(cd "$wt" && git rev-parse --git-path info/exclude)"
  case "$exclude_file" in /*) ;; *) exclude_file="$wt/$exclude_file" ;; esac
  mkdir -p "$(dirname "$exclude_file")"
  [[ -f "$exclude_file" ]] || : > "$exclude_file"
  # Never glue onto a file that lacks a trailing newline.
  if [[ -s "$exclude_file" && -n "$(tail -c 1 "$exclude_file")" ]]; then printf '\n' >> "$exclude_file"; fi
  grep -qxF '# relay provision-worktree.sh (id:76d2) — provisioned artifact symlinks' "$exclude_file" \
    || printf '%s\n' '# relay provision-worktree.sh (id:76d2) — provisioned artifact symlinks' >> "$exclude_file"
  # Idempotent: re-provisioning must not append duplicate lines.
  for _name in "${excluded[@]}"; do
    grep -qxF "/$_name" "$exclude_file" || printf '/%s\n' "$_name" >> "$exclude_file"
  done
fi

# id:66d9 — SELF-VERIFY the postcondition, then certify it with a POSITIVE token.
# `git worktree add` exiting 0 is not proof the worktree is usable, and the parent
# (relay-loop.js provisionWorktree()) runs in a filesystem-less Workflow sandbox: it can
# see nothing but this script's stdout, relayed through the mechanical proxy. A proxy
# refusal / 404 passthrough / harness message all come back as ordinary non-throwing text,
# so the parent can only fail CLOSED against a token that ONLY a verified success emits.
resolved="$(cd "$wt" && pwd -P)"
grep -qxF "worktree $resolved" < <(git -C "$repo_path" worktree list --porcelain) || {
  echo "provision-worktree.sh: worktree $resolved is NOT registered in '$repo_path' after 'git worktree add'" >&2
  exit 1
}
git -C "$repo_path" rev-parse --verify -q "refs/heads/$branch" >/dev/null || {
  echo "provision-worktree.sh: branch '$branch' does not exist in '$repo_path' after 'git worktree add'" >&2
  exit 1
}

# LAST stdout line, exact form: the parent greps for this and nothing else.
echo "PROVISION-OK $resolved"
exit 0
