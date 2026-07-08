#!/usr/bin/env bash
# tests/lib/assert-repo-unchanged.sh — shared purity-assertion helper (id:758e).
#
# Sourceable bash library, `set -euo pipefail`-compatible. Sourcing has NO side
# effects. Defines exactly two functions:
#
#   repo_state_snapshot <repo-dir>
#       Prints a deterministic state blob for the repo to stdout, capturing at
#       least: HEAD sha, all refs (git for-each-ref), the HEAD reflog,
#       `git status --porcelain`, `git worktree list --porcelain`, and the
#       stash list. Read-only itself.
#
#   assert_repo_unchanged <repo-dir> <saved-snapshot-file>
#       Exits 0 iff the repo's CURRENT snapshot is byte-identical to the saved
#       one. On drift, exits nonzero and prints a diff/description to stderr
#       (loud, never silent — no-silent-swallow, id:4347).
#
# Any component documented as read-only / snapshot / pure MUST ship a purity
# test built on this helper (see relay/references/executor-contract.md).

repo_state_snapshot() {
  local repo="$1"
  {
    echo "HEAD-SHA: $(git -C "$repo" rev-parse HEAD 2>/dev/null || echo NONE)"
    echo "--- refs (for-each-ref) ---"
    git -C "$repo" for-each-ref
    echo "--- reflog (HEAD) ---"
    git -C "$repo" reflog show HEAD 2>/dev/null || true
    echo "--- status --porcelain ---"
    git -C "$repo" status --porcelain
    echo "--- worktree list --porcelain ---"
    git -C "$repo" worktree list --porcelain
    echo "--- stash list ---"
    git -C "$repo" stash list
  }
}

assert_repo_unchanged() {
  local repo="$1"
  local saved_snapshot="$2"
  local cur
  cur="$(mktemp)"
  repo_state_snapshot "$repo" > "$cur"
  if ! cmp -s "$saved_snapshot" "$cur"; then
    echo "assert_repo_unchanged: DRIFT detected in repo '$repo'" >&2
    echo "--- diff (saved vs current) ---" >&2
    diff -u "$saved_snapshot" "$cur" >&2 || true
    rm -f "$cur"
    return 1
  fi
  rm -f "$cur"
  return 0
}
