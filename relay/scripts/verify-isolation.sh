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
# Behavior (id:7612 main-HEAD discriminator — "worktree empty" alone is AMBIGUOUS: it is the
# signature of BOTH a legitimate id:8e3e no-op review (child audited its window, found nothing
# to change) AND an isolation breach (child wrote to the main checkout instead of its worktree).
# `base = merge-base(worktree HEAD, main ref)` IS the dispatch-time main HEAD, so both facts —
# "is the worktree empty" and "did main move since dispatch" — are derivable without any new
# pool plumbing):
#   (a) worktree has ≥1 commit beyond base AND a clean tree        → print "ok …", exit 0.
#   (b1) EMPTY worktree (no commits beyond base) AND main UNMOVED  → exit 0 (legitimate id:8e3e
#        no-op review; a handback here would re-dispatch the same review forever).
#   (b2) EMPTY worktree AND main advanced by ≥1 NON-MERGE commit   → exit 2, names the
#        offending commit(s) (the loderite/jobAI isolation-breach signature).
#   (b3) EMPTY worktree AND main advanced ONLY by merge commit(s)  → exit 0 (another unit's
#        --no-ff integration is not this child's breach).
#   (c) worktree has commits beyond base but a DIRTY tree          → exit 2, names dirty entries.
#   (d) non-existent path / not a git worktree                     → exit 2, stderr message.
#
# ACCEPTED FALSE POSITIVE (do NOT chase with author/timestamp heuristics): a legitimate id:8e3e
# no-op review that races a concurrent SUPERVISED direct-to-main commit (id:15d5) also reads as
# "empty + main moved by a non-merge commit" and exits 2. That is the CONSERVATIVE direction —
# it defers a no-op unit rather than risk merging past a possible breach — and costs only a
# re-dispatch, so it is accepted as-is.
#
# This script ONLY observes (git log / git status / git merge-base). It NEVER runs stash /
# reset --hard / checkout -- / clean. The caller aborts the merge and defers on any non-zero
# exit — never attempts to "fix" an isolation failure itself; recovery is the id:15d5
# main-checkout-under-lease pattern (see relay/references/conventions.md).
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
  # EMPTY worktree — ambiguous by itself. Discriminate via main-HEAD: base IS the
  # dispatch-time main HEAD (merge-base of worktree HEAD and the base ref), so whether
  # main has since moved (and by what kind of commit) tells legitimate no-op review
  # (b1/b3) apart from an isolation breach (b2).
  main_head="$(git -C "$worktree" rev-parse --verify -q "$base")"
  merge_base="$(git -C "$worktree" merge-base HEAD "$base" 2>/dev/null || true)"
  if [ -n "$merge_base" ] && [ "$main_head" != "$merge_base" ]; then
    # main advanced since dispatch. Walk ONLY the first-parent (mainline) chain from
    # merge_base to main_head: a --no-ff integrator merge is itself a merge commit and
    # stays ON the first-parent chain, while the feature commits it brought in hang off
    # the merge's second parent and are correctly excluded here. A commit made directly
    # ON main (the loderite/jobAI breach) is a non-merge commit ON the first-parent chain.
    nonmerge="$(git -C "$worktree" log --no-merges --first-parent --oneline "$merge_base".."$main_head" 2>/dev/null || true)"
    if [ -n "$nonmerge" ]; then
      log "empty+main_moved(nonmerge) worktree=$worktree base=$base merge_base=$merge_base main_head=$main_head"
      echo "isolation failure: worktree has NO commits beyond base '$base', AND main advanced since dispatch with a NON-MERGE commit — likely a child that wrote to the main checkout instead of this worktree (empty/no commits ahead + main moved):"
      while IFS= read -r entry; do
        [ -n "$entry" ] || continue
        printf '  %s\n' "$entry"
      done <<< "$nonmerge"
      exit 2
    fi
    log "empty+main_moved(merge-only) worktree=$worktree base=$base merge_base=$merge_base main_head=$main_head"
    echo "ok: worktree has no commits beyond base '$base', but main advanced only by merge commit(s) since dispatch — not this child's breach"
    exit 0
  fi
  log "empty+main_unmoved worktree=$worktree base=$base"
  echo "ok: worktree has no commits beyond base '$base', and main has not moved since dispatch — legitimate no-op review (id:8e3e)"
  exit 0
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
