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
#   verify-isolation.sh <worktree> [--base <ref>]   (default --base derives from the repo's
#                                                      OWN checked-out branch via `git
#                                                      symbolic-ref --short HEAD`, falling back
#                                                      to origin/HEAD only if HEAD is detached/
#                                                      unborn — id:758a, never a hard-coded
#                                                      origin/main -> main -> master guess)
#
# Behavior (id:7612 main-HEAD discriminator — "worktree empty" alone is AMBIGUOUS: it is the
# signature of BOTH a legitimate id:8e3e no-op review (child audited its window, found nothing
# to change) AND an isolation breach (child wrote to the main checkout instead of its worktree).
# `base = merge-base(worktree HEAD, main ref)` IS the dispatch-time main HEAD, so both facts —
# "is the worktree empty" and "did main move since dispatch" — are derivable without any new
# pool plumbing):
#   (a) worktree has ≥1 commit beyond base AND a clean tree        → print "ok …", exit 0.
#   (b0) EMPTY worktree (no commits beyond base) AND a DIRTY tree  → exit 2, names dirty
#        entries — checked BEFORE b1/b3 below, regardless of whether main moved (id:1b13,
#        owner-decided 2026-08-14: breach-shaped, the closest signature to "the child worked
#        but never committed"). "DIRTY" is the SHARED lib-clean-tree.sh predicate (id:0fad),
#        so cosmetic git-annex pointer noise (` M` with an empty diff) is NOT b0: it prints a
#        note and falls through to b1/b2/b3 like any other clean empty worktree.
#   (b1) EMPTY worktree (no commits beyond base), CLEAN tree, main UNMOVED → exit 0
#        (legitimate id:8e3e no-op review; a handback here would re-dispatch the same
#        review forever).
#   (b2) EMPTY worktree, CLEAN tree, main advanced by ≥1 NON-MERGE commit → exit 2, names the
#        offending commit(s) (the loderite/jobAI isolation-breach signature).
#   (b3) EMPTY worktree, CLEAN tree, main advanced ONLY by merge commit(s) → exit 0 (another
#        unit's --no-ff integration is not this child's breach).
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

# shellcheck source=lib-ledger-only-diff.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-ledger-only-diff.sh"
# shellcheck source=lib-clean-tree.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-clean-tree.sh"

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

# Resolve the base ref: explicit --base wins. Otherwise derive from the repo's OWN
# checked-out branch (id:758a, owner ruling 2026-08-26, general invariant: base-ref
# resolution must use the repo's ACTUAL checked-out branch — NEVER a hard-coded
# origin/main -> main -> master guess). Mirrors the fail-closed, HEAD-not-name posture
# id:8739 already implements on the integrate path (relay/scripts/integrate.sh:455-465).
# A guess-list (adding 'master' as a further fallback) is actively WORSE than failing
# loudly: on git-annex, 'master' DOES resolve — but to a stale upstream mirror, not the
# real checked-out branch ('annex-dotgit') — so a guess-list would silently verify
# isolation against the WRONG base instead of refusing.
if [ -z "$base" ]; then
  # `|| true` is REQUIRED, not decorative: `symbolic-ref -q` exits 1 when HEAD is detached
  # or unborn (or when origin/HEAD is absent), `set -o pipefail` propagates that through the
  # pipe, and `set -e` then killed the whole gate — exit 1 with COMPLETELY EMPTY output, on
  # every repo without a resolvable ref (i.e. every hermetic fixture missing one). A gate
  # that fails silently is worse than no gate: the caller cannot distinguish "isolation
  # breach" from "could not determine the base ref". Never caught because all four callers
  # in tests/test_verify_isolation.sh pass --base and skip this fallback;
  # tests/test_provision_symlink_ignored_76d2.sh is the first to reach it.
  # Found 2026-08-12 by the id:76d2 executor, reproduced by the reviewer before fixing.
  #
  # NOTE this must resolve the MAIN checkout's checked-out branch, NOT $worktree's own —
  # $worktree is always a LINKED worktree on a throwaway child branch (e.g.
  # relay/<run>-<verdict>-<item>-<attempt>), so `symbolic-ref HEAD` run directly against it
  # would just echo that same throwaway branch back as its own base (0 commits beyond
  # itself, always), silently disabling the whole gate. `git worktree list --porcelain`
  # always lists the MAIN worktree first (the repo's own checked-out branch lives there);
  # it works from any linked worktree because they share one git-common-dir/object db.
  main_wt="$(awk '/^worktree /{print $2; exit}' < <(git -C "$worktree" worktree list --porcelain 2>/dev/null) || true)"
  branch=""
  [ -n "$main_wt" ] && branch="$(git -C "$main_wt" symbolic-ref --short -q HEAD 2>/dev/null || true)"
  if [ -n "$branch" ]; then
    base="$branch"
  else
    # HEAD detached or unborn: fall back to origin/HEAD only (still no main/master guess).
    base="$(git -C "$worktree" symbolic-ref --short -q refs/remotes/origin/HEAD 2>/dev/null || true)"
  fi
fi

if [ -z "$base" ]; then
  echo "verify-isolation.sh: could not determine a base ref in '$worktree' (HEAD is detached/unborn and no origin/HEAD symbolic ref) — refusing to guess main/master (id:758a)" >&2
  exit 2
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
  #
  # id:1b13 (owner-decided 2026-08-14): an EMPTY worktree with a DIRTY tree is NOT a
  # legitimate no-op review under ANY of the b1/b3 short-circuits below — it is the
  # closest signature to "the child worked but never committed" (the same breach family
  # this gate exists for), so check dirty FIRST and fail loud before any of the
  # main-moved discrimination gets a chance to wave it through.
  #
  # id:0fad -- "DIRTY" here MUST be the SAME question the (c) branch below asks, answered by
  # the SAME shared predicate. It was not: this branch tested a BARE `status --porcelain` for
  # non-emptiness, so on a git-annex repo the id:3016/id:68e2 filter-aware predicate was never
  # reached (it is only consulted after the commits-beyond-base test, i.e. for NON-empty
  # worktrees), and cosmetic pointer noise read as a breach. Measured 2026-09-11, pool run
  # relay-20260911-103808-7255: code.lawless unit a736 handed back `handbackCode=21 ...
  # breach-shaped (id:1b13)` listing ` M` annexed PNGs under docs/research/img/card-match/,
  # with `workCreated:false` -- a child that legitimately did nothing, called a breach. Its
  # worktree measured ahead=0 porcelain=204 diff=0.
  #
  # THE id:1b13 SEMANTIC IS UNCHANGED AND MUST STAY UNCHANGED. Only the COSMETIC case moves,
  # and it moves to the id:8b1f clean-sized-out shape (no commits + nothing to lose), NOT to
  # "merge it": a cosmetic tree falls THROUGH to the b1/b2/b3 main-moved discrimination below
  # exactly as a genuinely clean empty worktree does, so a real breach that ALSO left main
  # moved still exits 2. Untracked / staged / added / deleted / conflicted entries keep a
  # non-` M` porcelain pair and stay DIRTY (`git diff` never shows untracked), and a `git diff`
  # that errors stays DIRTY -- both enforced inside tree_clean_probe, see lib-clean-tree.sh.
  #
  # rc=2 (UNKNOWN -- `git status` ITSELF failed) is deliberately NOT treated as a breach here.
  # That is the pre-existing behaviour preserved byte-for-byte: the old
  # `$(... 2>/dev/null || true)` yielded an empty string on a git error, which read as
  # not-dirty and fell through to the same discrimination. Flipping it to fail-closed is a
  # DISPATCH-behaviour change (it would start blocking work that proceeds today) and is
  # id:b545's, which owns the identical fail-open on the (c) branch at the bottom of this file
  # and must fix BOTH together -- half-closing it here would leave the gate refusing an
  # unreadable EMPTY worktree while still merging an unreadable one WITH commits, which is
  # strictly harder to reason about than the consistent fail-open we have. What id:0fad does
  # guarantee is that an error can never reach the new RELAXATION: on rc=2 the probe leaves
  # TREE_COSMETIC=0 and TREE_PORCELAIN empty, so the cosmetic branch is unreachable and the
  # verdict is identical to today's.
  empty_tree_rc=0
  tree_clean_probe "$worktree" || empty_tree_rc=$?
  # Only rc 1 is DIRTY. rc 2 leaves TREE_PORCELAIN empty and is handled as not-dirty, above.
  porcelain_empty="$TREE_PORCELAIN"
  if [ "$empty_tree_rc" -eq 1 ]; then
    log "empty+dirty worktree=$worktree base=$base"
    echo "isolation failure: worktree has NO commits beyond base '$base' AND a DIRTY tree (uncommitted changes) — breach-shaped (id:1b13): looks like the child worked but never committed, not safe to merge"
    while IFS= read -r entry; do
      [ -n "$entry" ] || continue
      printf '  %s\n' "$entry"
    done <<< "$porcelain_empty"
    exit 2
  fi
  if [ "$TREE_COSMETIC" -eq 1 ]; then
    log "empty+cosmetic-dirty (annex pointers, id:0fad) worktree=$worktree base=$base entries=$TREE_COSMETIC_COUNT"
    echo "note: $TREE_COSMETIC_COUNT path(s) report modified with an EMPTY diff -- cosmetic git-annex pointer noise (id:3016), not a real modification; $(tree_cosmetic_remedy "$worktree"). NOT breach-shaped (id:0fad); treating the tree as CLEAN and continuing the id:1b13/8e3e discrimination."
  fi
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
      # id:88f0 — an id:c144-sanctioned ledger-only advance (ROADMAP/TODO/REVIEW_ME/
      # RELAY_LOG/CHANGELOG writes done directly in the main checkout under the
      # documented /relay human / /meeting write-back path, id:15d5/2147) is NOT a
      # breach even though it is a non-merge commit on the first-parent chain — it is
      # the exact class id:c144 exempts from the relay lease. Anything not PROVABLY
      # ledger-only still defers below (fail-safe direction unchanged).
      if ledger_only_diff "$worktree" "$merge_base..$main_head"; then
        log "empty+main_moved(ledger-only) worktree=$worktree base=$base merge_base=$merge_base main_head=$main_head"
        # id:5340 — DERIVE the file list from the predicate's own variable, never restate it:
        # this message hardcoded the pre-archive set and would have kept naming the old five
        # after the set grew, which is exactly the derived-doc drift the house rule warns about.
        echo "ok: worktree has no commits beyond base '$base'; main advanced since dispatch, but only via id:c144-sanctioned ledger-only commit(s) ($(echo "$LEDGER_ONLY_DIFF_FILES" | tr ' ' '/')) — not a breach (id:88f0)"
        exit 0
      fi
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
#
# The id:3016 filter-aware predicate now lives in relay/scripts/lib-clean-tree.sh (id:68e2),
# sourced above, because worktree-retire.sh asked the same question with a BARE porcelain test
# and therefore answered it differently about the very same worktree. The full reasoning --
# why annex pointer files report ` M` with an empty diff, why `git update-index --refresh`
# does NOT clear them, and why "empty diff means clean" would blind this gate to untracked
# residue -- is in that file's header. It is not restated here, so there is one copy to keep
# true.
#
# UNKNOWN (`git status` itself failed) is deliberately handled HERE the way this script has
# always handled it: the old `$(... 2>/dev/null || true)` produced an empty string, which read
# as a clean tree. That is preserved BYTE-FOR-BYTE rather than quietly upgraded, because
# tightening it is a real behaviour change (an unreadable worktree would start failing the
# isolation gate) and belongs to its own decision, not to this extraction. It is the same
# fail-open shape that id:a290 round-3 found destroying work in worktree-retire.sh's hatch, so
# it is flagged, not hidden. The retire-side call sites added under id:68e2 all treat UNKNOWN
# as DIRTY.
tree_rc=0
tree_clean_probe "$worktree" || tree_rc=$?
if [ "$tree_rc" -eq 2 ]; then
  TREE_PORCELAIN=""   # preserved pre-id:68e2 behaviour, see the paragraph above
fi
porcelain="$TREE_PORCELAIN"
if [ -n "$porcelain" ]; then
  if [ "$TREE_COSMETIC" -eq 1 ]; then
    n_cosmetic="$TREE_COSMETIC_COUNT"
    log "cosmetic-dirty (annex pointers, id:3016) worktree=$worktree base=$base entries=$n_cosmetic"
    remedy="$(tree_cosmetic_remedy "$worktree")"
    echo "note: $n_cosmetic path(s) report modified with an EMPTY diff -- cosmetic git-annex pointer noise (id:3016), not a real modification; $remedy. Treating the tree as CLEAN."
  else
    log "dirty worktree=$worktree base=$base"
    echo "isolation failure: worktree has a DIRTY tree (uncommitted changes) — not safe to merge"
    while IFS= read -r entry; do
      [ -n "$entry" ] || continue
      printf '  %s\n' "$entry"
    done <<< "$porcelain"
    exit 2
  fi
fi

n_commits="$(printf '%s\n' "$commits" | wc -l | tr -d ' ')"
log "ok worktree=$worktree base=$base commits=$n_commits"
echo "ok: $n_commits commit(s) beyond '$base', tree clean"
exit 0
