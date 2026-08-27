#!/usr/bin/env bash
# fixture-branch-leak-scan.sh — cheap standing detector for id:b54b: a test fixture that
# escaped its `mktemp -d` sandbox and left a `relay/*` branch in a REAL own repo.
#
# Background: on 2026-08-22 a test fixture leaked a `relay/ok` branch (1 commit, "child
# work ok") into this real repo. relay-reconcile.sh:250 enumerates refs/heads/relay/* to
# find orphaned relay runs to (auto-)integrate, so a fixture branch sitting in that exact
# namespace is indistinguishable from a real parked orphan — a pool could merge fixture
# junk into main. See TODO.md id:b54b.
#
# What counts as a real relay branch (naming contract, see stranded-branch-scan.sh's own
# header, verified against relay-loop.js:2219/2228): `relay/<runId>-<verdict>-<item>-<n>`,
# where runId itself looks like `relay-YYYYMMDD-HHMMSS-PID`. A branch is flagged SUSPECT
# when EITHER:
#   (shape)   its name under `refs/heads/relay/*` does not even match that run-scoped
#             shape (e.g. `relay/ok` — no runId component at all), or
#   (unknown) it does match the shape, but the runId it names is reachable from no run —
#             RELAY_LOG.md never mentions it.
# `refs/heads/relay/orphan/*` is a distinct, deliberately-parked namespace (see
# relay-reconcile.sh) and is excluded — a parked orphan is a working feature, not a leak.
#
# Usage: fixture-branch-leak-scan.sh [<repo-path>]
#   <repo-path> defaults to `git rev-parse --show-toplevel` from the caller's cwd.
#
# Output: one "<branch>\t<sha>\t<reason>\t<subject>" line per suspect branch, to stdout.
# Exit 0 with no output when clean; exit 1 with output when any suspect is found. Never
# deletes, renames, checks out, or merges anything — observe-only, mirrors
# stranded-branch-scan.sh / verify-isolation.sh.
set -euo pipefail

repo="${1:-}"
if [ -z "$repo" ]; then
  repo="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi
[ -n "$repo" ] || { echo "fixture-branch-leak-scan.sh: no repo path given and cwd is not inside a git repo" >&2; exit 2; }
if [ ! -d "$repo" ] || ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
  echo "fixture-branch-leak-scan.sh: '$repo' is not a git repo" >&2
  exit 2
fi

RELAY_LOG="$repo/RELAY_LOG.md"

found=0
while IFS= read -r br; do
  [ -n "$br" ] || continue
  case "$br" in "relay/orphan/"*) continue ;; esac   # parked orphans are a different, intentional namespace

  sha="$(git -C "$repo" rev-parse --short "$br" 2>/dev/null || echo '???????')"
  subj="$(git -C "$repo" log -1 --format='%s' "$br" 2>/dev/null || true)"

  stem="${br#relay/}"
  reason=""
  case "$stem" in
    relay-*)
      # strip trailing -<verdict>-<item-or-repo>-<attempt> to recover the bare runId,
      # same regex as stranded-branch-scan.sh's sibling list_stranded in relay-reconcile.sh
      runid="$(printf '%s' "$stem" | sed -E 's/-[a-z]+-[^-]+-[0-9]+$//')"
      if [ ! -f "$RELAY_LOG" ] || ! grep -qF "$runid" "$RELAY_LOG"; then
        reason="unknown-runid:$runid"
      fi
      ;;
    *)
      reason="shape-anomaly"
      ;;
  esac

  if [ -n "$reason" ]; then
    printf '%s\t%s\t%s\t%s\n' "$br" "$sha" "$reason" "$subj"
    found=1
  fi
done < <(git -C "$repo" for-each-ref --format='%(refname:short)' 'refs/heads/relay/*')

exit $(( found ? 1 : 0 ))
