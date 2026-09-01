#!/usr/bin/env bash
# roadmap:689c — D1: park unmerged orphans on discovery (relay orphan-reconcile, meeting
# 2026-06-16-0938). Today (id:3ac8, test_relay_stale_worktree_reap.sh) a commit-bearing stale
# worktree from a DEAD run is only SURFACED as "needs manual integration" every round and the
# directory stays, so the `ls worktrees/` scan re-surfaces it forever. D1 changes the
# commits-ahead branch of discovery to PARK the orphan: remove the worktree dir (stops the
# re-surface) and rename the branch into the canonical `relay/orphan/*` namespace (the commit
# stays reachable on the ref), emitting ONE summary line — NOT a per-round handback, and NEVER
# an auto-integration. Static-structural checks on the mechanical discovery guard, now in
# reconcile-repo.sh (the old discovery-prompt logic in relay-loop.js was replaced).

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JS="$SRC_DIR/relay/scripts/relay-loop.js"
RECONCILE="$SRC_DIR/relay/scripts/reconcile-repo.sh"
RETIRE="$SRC_DIR/relay/scripts/worktree-retire.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$JS" ]] || fail "relay-loop.js not found at $JS"
node --check "$JS" || fail "relay-loop.js fails node --check"
[[ -x "$RECONCILE" ]] || fail "reconcile-repo.sh not found at $RECONCILE"
[[ -x "$RETIRE" ]] || fail "worktree-retire.sh not found at $RETIRE"

# (1) the D1 marker is present in the discovery guard.
grep -q "id:689c" "$RECONCILE" || fail "no id:689c (D1 park) marker in reconcile-repo.sh"

# (2) commits-ahead orphans are PARKED into the canonical relay/orphan/* namespace
#     (the stranded commit stays reachable on a ref, not lost). The rename now lives in the
#     force-free retire helper (id:373e), invoked by reconcile's park loop.
grep -Eq "relay/orphan/" "$RECONCILE" \
  || fail "reconcile-repo.sh does not park orphans into the relay/orphan/* namespace (D1)"
grep -Eq "worktree-retire\.sh" "$RECONCILE" \
  || fail "reconcile-repo.sh does not delegate reap/park to worktree-retire.sh (id:373e)"
grep -Eq "branch -m " "$RETIRE" \
  || fail "worktree-retire.sh does not rename an unmerged branch with 'git branch -m' into relay/orphan/* (D1)"

# (3) FORCE-FREE (id:373e): the retire path removes the worktree dir WITHOUT --force and never
#     force-deletes a branch. `git worktree remove --force` / `git branch -D` must be ABSENT
#     from both reconcile-repo.sh and the helper.
# (strip full-line comments so an explanatory "NO --force" comment isn't a false positive)
grep -Eq "worktree remove --force" < <(grep -vE '^[[:space:]]*#' "$RECONCILE") \
  && fail "reconcile-repo.sh still uses 'git worktree remove --force' — must be force-free (id:373e)"
# Strip full-line comments AND surfaced-text lines (msg=/echo/log). Since 2026-08-26 the
# helper's own SURFACED message for the submodule case (roadmap:b02f) names the forbidden
# command in prose — "Only 'git worktree remove --force' removes it, which is the op id:373e
# avoids" — precisely so a human is not left thinking a force-free route exists. A guard that
# fires on a command merely QUOTED is the id:221f(b) anchoring defect; test_worktree_retire.sh's
# equivalent check already strips these lines, and this one now matches it.
# AMENDED 2026-09-01 (TODO id:a290, owner-ruled): the helper now carries EXACTLY ONE
# `git worktree remove --force`, the narrow submodule escape hatch. It fires only after the
# helper has itself proved the tree CLEAN and the branch already an ancestor of HEAD, and only
# when it positively recognizes git's verbatim submodule refusal (behaviour pinned by
# tests/test_submodule_force_hatch_a290.sh, including that a dirty or unmerged tree is refused).
# So the invariant is no longer "zero forces" but "exactly one, and no second one sneaks in":
# a bare count keeps this a real ratchet instead of an open door. `branch -D` stays ABSENT
# outright -- id:373e's ban on force-DELETING a ref is untouched by the a290 ruling.
retire_body="$(grep -vE '^[[:space:]]*#' "$RETIRE" | grep -vE '(^[[:space:]]*(log|echo)\b|[[:space:]]*msg=|[[:space:]]*(hatch_refused|why)=)')"
n_force="$(printf '%s\n' "$retire_body" | grep -Ec "worktree remove --force" || true)"
[[ "$n_force" -eq 1 ]] \
  || fail "worktree-retire.sh must carry EXACTLY ONE 'git worktree remove --force' (the id:a290 submodule escape hatch); found $n_force (id:373e)"
grep -Eq "remove +-f +-f|remove +--force +--force" <<<"$retire_body" \
  && fail "worktree-retire.sh must never issue 'remove -f -f' -- a LOCKED worktree stays an independent backstop the a290 hatch cannot override (id:373e/id:a290)"
grep -Eq "branch +-D\b" <<<"$retire_body" \
  && fail "worktree-retire.sh must not use branch -D (id:373e)"
grep -Eq "worktree remove" "$RETIRE" \
  || fail "worktree-retire.sh never removes the orphan worktree dir (would re-surface every round)"

# (4) park describes parking (NOT the old per-round "needs manual integration" handback) and
#     NEVER auto-integrates (no --no-ff merge in the park path).
grep -Eqi "park|parked" "$RECONCILE" \
  || fail "reconcile-repo.sh does not describe parking the orphan (still the old surface-only behaviour)"

pass "reconcile parks commit-bearing orphans into relay/orphan/* via the force-free retire helper (689c/373e)"
