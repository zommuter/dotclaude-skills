#!/usr/bin/env bash
# stranded-branch-scan.sh — DETERMINISTIC, observe-only "does this item already have a
# committed branch from a prior attempt?" scanner for the relay pool (id:dd7d).
#
# Motivation (lodelore run relay-20260818-110858-18948, id:15d2): a round-4 dispatch handed
# back on a dirty-tree defer (id:aa93); round 5 re-dispatched the SAME still-open item and the
# second child redid the work from scratch, reaching a different answer than the first
# child's already-COMMITTED branch. Nothing detected the divergence until a manual integrate
# hit an add/add conflict. The two children were SEQUENTIAL, not concurrent — an "at-most-one
# live child" guard would not have caught this; what was missing is a check, at BOTH dispatch
# time and integrate time, for "does a branch for this item already carry real commits?".
#
# Usage:
#   stranded-branch-scan.sh <repo-path> --verdict <v> --item <itemId> [--base <ref>]
#
# Naming contract (verified against the code 2026-08-18, do NOT re-derive):
#   relay-loop.js:2219   unitKey   = ${verdict}-${itemId || 'repo'}-${attempt}
#   relay-loop.js:2228   branchFor = relay/${runId}-${unitKey}
#   worktree-retire.sh:80-81       parks orphans as relay/orphan/$(basename <worktree-dir>),
#                                  which carries the same <runId>-<verdict>-<itemId>-<attempt>
#                                  stem.
# So a branch for a given (verdict, itemId) lives at:
#   relay/*-<verdict>-<itemId>-*            (live namespace, any runId)
#   relay/orphan/*-<verdict>-<itemId>-*     (parked namespace, any runId)
# Both globs are runId-AGNOSTIC on purpose: branchFor is runId-prefixed, so a same-run-only
# glob would miss every branch stranded by an EARLIER run — the longer-lived half of the
# hazard this script exists to catch.
#
# Traps (each already paid for once, see id:dd7d ROADMAP item):
#   (i)   itemId falls back to the literal string 'repo' for repo-scoped units, so
#         '…-review-repo-0' must NEVER item-match a real item id — the glob's literal
#         '-<itemId>-' segment already excludes this, but is called out here because it is
#         easy to accidentally loosen.
#   (ii)  Do NOT special-case a hand-renamed orphan (e.g. relay/orphan/15d2-kepler-...) — that
#         shape is a human rename during manual integration, not the programmatic form, and a
#         matcher fitted to it would never fire on a real stranded branch.
#   (iii) Branch presence is NOT sufficient: a ZERO-commit branch is also exactly what a LIVE
#         parallel child's freshly created worktree branch looks like (id:6e02). Only report a
#         branch with >0 commits beyond base.
#
# Behavior: prints one "<branch>\t<commit-count>" line per matching branch with >0 commits
# beyond <base> (default: origin/main, falling back to 'main' if that does not resolve).
# Prints nothing when none are found. Exit 0 in both cases (observe-only, mirrors
# verify-isolation.sh) — non-zero is reserved for a usage/repo error. NEVER deletes, renames,
# checks out, or merges anything; only `git for-each-ref` / `git rev-list --count`.
set -euo pipefail

repo="${1:-}"; shift || true
verdict=""
item=""
base=""
while [ $# -gt 0 ]; do
  case "$1" in
    --verdict) shift; [ $# -gt 0 ] || { echo "stranded-branch-scan.sh: --verdict needs a value" >&2; exit 2; }; verdict="$1"; shift ;;
    --item) shift; [ $# -gt 0 ] || { echo "stranded-branch-scan.sh: --item needs a value" >&2; exit 2; }; item="$1"; shift ;;
    --base) shift; [ $# -gt 0 ] || { echo "stranded-branch-scan.sh: --base needs a ref" >&2; exit 2; }; base="$1"; shift ;;
    *) echo "stranded-branch-scan.sh: unknown arg '$1'" >&2; exit 2 ;;
  esac
done

[ -n "$repo" ] || { echo "stranded-branch-scan.sh: <repo-path> required" >&2; exit 2; }
[ -n "$verdict" ] || { echo "stranded-branch-scan.sh: --verdict required" >&2; exit 2; }
[ -n "$item" ] || { echo "stranded-branch-scan.sh: --item required" >&2; exit 2; }
if [ ! -d "$repo" ] || ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
  echo "stranded-branch-scan.sh: '$repo' is not a git repo" >&2
  exit 2
fi

if [ -z "$base" ]; then
  if git -C "$repo" rev-parse --verify -q origin/main >/dev/null 2>&1; then
    base="origin/main"
  else
    base="main"
  fi
fi
if ! git -C "$repo" rev-parse --verify -q "$base" >/dev/null 2>&1; then
  echo "stranded-branch-scan.sh: base ref '$base' does not resolve in '$repo'" >&2
  exit 2
fi

# Literal '-<verdict>-<item>-' segment (not a loose grep) so trap (i) can't slip through:
# a repo-scoped branch's unitKey is "<verdict>-repo-<attempt>" and never contains
# "-<verdict>-<item>-" unless item literally is "repo".
live_pattern="relay/*-${verdict}-${item}-*"
orphan_pattern="relay/orphan/*-${verdict}-${item}-*"

# for-each-ref is used (not branch -a / grep) because it never invokes a pager, is
# script-stable across git versions, and lets us glob both namespaces in one call.
while IFS= read -r branch; do
  [ -n "$branch" ] || continue
  count="$(git -C "$repo" rev-list --count "$base..$branch" 2>/dev/null || echo 0)"
  if [ "$count" -gt 0 ]; then
    printf '%s\t%s\n' "$branch" "$count"
  fi
done < <(git -C "$repo" for-each-ref --format='%(refname:short)' "refs/heads/$live_pattern" "refs/heads/$orphan_pattern" | sort -u)

exit 0
