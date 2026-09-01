#!/usr/bin/env bash
# NO `# roadmap:` HEADER ON PURPOSE -- this is a DEFECT-FIX test, not the RED spec of an open
# ROADMAP item, so expected-red semantics must NEVER apply to it and its failures always count.
#
# fails-against: relay/scripts/reconcile-repo.sh before the 2026-09-01 reversal of the
#   `-e <wt>/.gitmodules` short-circuit -- that skip `continue`d BEFORE plan_reap/plan_park were
#   populated, so worktree-retire.sh was NEVER reached from the reap path and an
#   UNINITIALISED-submodule worktree (which removes force-free, rc=0) was never disposed of.
# fails-against-rev: 0afb77c9e89b0473492df27c0d98139f2ddd8d3b -- relay/scripts/reconcile-repo.sh
# fails-against-assertion: (a) NO reap was planned for an UNINITIALISED-submodule worktree
#
# THE DEFECT.
# `reconcile-repo.sh` short-circuited on `-e "$wtdir/$bn/.gitmodules"` with a bare `continue`,
# placed BEFORE plan_reap/plan_park are populated. Consequence: worktree-retire.sh was never
# invoked from reconcile for ANY submodule-carrying worktree. Only `integrate.sh` step 9 reached
# the helper, and only for the single unit it had just integrated -- so any worktree that
# SURVIVED integrate (handback, crash, abandoned run) became permanent debris. 1.8 GB
# accumulated on yinyang-puzzle that way.
#
# THE SKIP'S PREMISE IS REFUTED. roadmap:b02f recorded that git keys its removal refusal on
# `.gitmodules` being in the tree. Fixture-proven false, twice: a worktree carrying
# `.gitmodules` plus the gitlink in its index, whose submodule was NEVER INITIALISED, removes
# CLEANLY and FORCE-FREE. The refusal needs the submodule POPULATED, and what git actually tests
# is the worktree's PRIVATE submodule store, `<common-git-dir>/worktrees/<name>/modules/<path>`.
# Case (A) below re-derives that from scratch, so the premise cannot rot again silently.
#
# WHAT THIS LOCKS (behaviour, never doc strings):
#   (A) SANITY, and the whole reason the reversal is safe: git removes an UNINITIALISED-submodule
#       worktree force-free, and refuses a POPULATED one. Re-derived per run.
#   (a) an UNINITIALISED-submodule worktree, clean + merged, is now REAPED force-free.
#       This is the behaviour change; it was impossible before the fix.
#   (b) a POPULATED-submodule worktree REACHES worktree-retire.sh, is REFUSED, stays on disk
#       with its branch intact, and is SURFACED under the `unretirable-submodule:` marker --
#       not silently dropped.
#   (c) a DIRTY submodule worktree is surfaced-and-LEFT: nothing forced, the uncommitted bytes
#       survive. The reversal must not turn newly-reachable disposal into work loss.
#   (d) a plain non-submodule worktree behaves exactly as before (reaped, no marker).
#   (e) the marker is ADDITIVE and fires EVERY round -- a repo carrying one is still dispatched.
#       Load-bearing: a substitutive marker would suppress the repo forever (id:e7e4 loderite
#       starvation shape).
#
# SUPERSEDES tests/test_reconcile_unretirable_submodule_b02f.sh, DELETED in the same commit.
# That file's assertion (1) -- "a submodule-carrying worktree is NOT planned for reap/park" --
# IS the behaviour the owner reversed on 2026-09-01, and it was written on the refuted
# `.gitmodules` premise (its fixture is a bare directory carrying a copied `.gitmodules`, with no
# private submodule store at all, i.e. the UNINITIALISED case that removes force-free). Its other
# three assertions are kept, not dropped: its (2) marker-surfaced is case (b5) here, its (3)
# additive/still-dispatched is (e2), and its (4)+(4b) non-submodule negative control is (d).
#
# The id:a290 force hatch inside worktree-retire.sh is OPT-IN and INERT in production; this test
# explicitly UNSETS its enable so case (b) exercises the production configuration.
#
# Hermetic: mktemp -d, isolated GIT_CONFIG_GLOBAL/SYSTEM, local-file submodule remotes, no
# network, no ~/.claude or real-repo access.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RC="$ROOT/relay/scripts/reconcile-repo.sh"
DR="$ROOT/relay/scripts/discover-repo.sh"
[[ -x "$RC" ]] || { echo "FAIL: reconcile-repo.sh not found/executable: $RC"; exit 1; }
[[ -x "$DR" ]] || { echo "FAIL: discover-repo.sh not found/executable: $DR"; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

export GIT_CONFIG_GLOBAL="$tmp/gitconfig"
export GIT_CONFIG_SYSTEM=/dev/null
git config --global user.email t@e
git config --global user.name t
git config --global commit.gpgsign false
git config --global protocol.file.allow always

export RELAY_WORKTREE_BASE="$tmp/wt"
export RELAY_TOML="$tmp/relay.toml"; : > "$RELAY_TOML"
export RECONCILE_LOG="$tmp/reconcile.log"
export WORKTREE_RETIRE_LOG="$tmp/retire.log"
# Production configuration: the id:a290 hatch is opt-in and NO relay caller enables it.
unset WORKTREE_RETIRE_SUBMODULE_FORCE || true
unset WORKTREE_RETIRE_NO_SUBMODULE_FORCE || true

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

acts() { python3 -c 'import sys,json; print(",".join(a.get("kind","") for a in json.load(sys.stdin).get("actions",[])))'; }
surf_join() { python3 -c 'import sys,json; print("|".join(s.get("reason","") for s in json.load(sys.stdin).get("surfaced",[])))'; }
ucount() { python3 -c 'import sys,json; print(len(json.load(sys.stdin).get("units",[])))'; }

# --- the submodule upstream every superproject below points at (local path, no network) ------
SUB="$tmp/subupstream"
mkdir -p "$SUB"; git -C "$SUB" init -q -b main
echo hello > "$SUB/f.txt"; git -C "$SUB" add -A; git -C "$SUB" commit -qm sub1

mksuper() { # <name> -> repo at $tmp/<name>, with ROADMAP/TODO and a committed submodule
  local name="$1" d="$tmp/$1"
  mkdir -p "$d"; git -C "$d" init -q -b main
  printf '# Roadmap\n## Items\n- [ ] [ROUTINE] work a <!-- id:57d1 -->\n' > "$d/ROADMAP.md"
  printf '# TODO\n## Current\n' > "$d/TODO.md"
  git -C "$d" add -A; git -C "$d" commit -qm init
  git -C "$d" submodule add -q "$SUB" vendor/x
  git -C "$d" commit -qm addsub
}

mkplain() { # <name> -> repo at $tmp/<name>, NO submodule
  local name="$1" d="$tmp/$1"
  mkdir -p "$d"; git -C "$d" init -q -b main
  printf '# Roadmap\n## Items\n- [ ] [ROUTINE] work a <!-- id:6612 -->\n' > "$d/ROADMAP.md"
  printf '# TODO\n## Current\n' > "$d/TODO.md"
  git -C "$d" add -A; git -C "$d" commit -qm init
}

# A stale MERGED worktree: branch created at HEAD, so it is an ancestor of main => reconcile
# plans a REAP (not a park) for it.
add_wt() { # <repo-dir> <repo-name> <basename>
  local d="$1" name="$2" bn="$3"
  mkdir -p "$RELAY_WORKTREE_BASE/$name"
  git -C "$d" worktree add -q -b "relay/$bn" "$RELAY_WORKTREE_BASE/$name/$bn"
}

# =====================================================================================
# (A) SANITY -- re-derive git's ACTUAL refusal trigger. If this ever flips, every claim
#     below is about a git that no longer exists, and the reversal must be revisited.
# =====================================================================================
mksuper sanity
add_wt "$tmp/sanity" sanity probe-uninit
add_wt "$tmp/sanity" sanity probe-pop
git -C "$RELAY_WORKTREE_BASE/sanity/probe-pop" submodule update --init -q

[[ -e "$RELAY_WORKTREE_BASE/sanity/probe-uninit/.gitmodules" ]] \
  || fail "(A) fixture broken: the uninitialised worktree does not even carry .gitmodules"
if LC_ALL=C git -C "$tmp/sanity" worktree remove "$RELAY_WORKTREE_BASE/sanity/probe-uninit" 2>"$tmp/A1.err"; then
  pass "(A1) git removes an UNINITIALISED-submodule worktree FORCE-FREE (b02f's .gitmodules premise is refuted)"
else
  fail "(A1) git refused to remove an uninitialised-submodule worktree force-free: $(cat "$tmp/A1.err")"
fi
if LC_ALL=C git -C "$tmp/sanity" worktree remove "$RELAY_WORKTREE_BASE/sanity/probe-pop" 2>"$tmp/A2.err"; then
  fail "(A2) git removed a POPULATED-submodule worktree force-free -- the refusal this test is built around is gone"
else
  grep -q 'containing submodules' "$tmp/A2.err" \
    || fail "(A2) git refused the populated worktree with an UNEXPECTED message: $(cat "$tmp/A2.err")"
  pass "(A2) git refuses a POPULATED-submodule worktree (the refusal is keyed on the private store)"
fi

# =====================================================================================
# (a) THE BEHAVIOUR CHANGE -- an UNINITIALISED-submodule worktree is now REAPED force-free.
# =====================================================================================
mksuper uninit
add_wt "$tmp/uninit" uninit deadrun-review-repo-0
WT_A="$RELAY_WORKTREE_BASE/uninit/deadrun-review-repo-0"

oa="$("$RC" --repo uninit --path "$tmp/uninit" --live-claims "" --main-branch main 2>"$tmp/a.err")"
grep -q 'reap' <<<"$(printf '%s' "$oa" | acts)" \
  || fail "(a) NO reap was planned for an UNINITIALISED-submodule worktree -- reconcile still short-circuits on .gitmodules and never reaches worktree-retire.sh: $oa"
pass "(a1) a reap is planned for an uninitialised-submodule worktree"

[[ ! -d "$WT_A" ]] \
  || fail "(a2) the uninitialised-submodule worktree is STILL ON DISK after APPLY -- it was not disposed of force-free: $WT_A"
pass "(a2) the worktree is gone from disk, removed force-free by worktree-retire.sh"

if git -C "$tmp/uninit" show-ref --verify --quiet refs/heads/relay/deadrun-review-repo-0; then
  fail "(a3) the merged branch relay/deadrun-review-repo-0 survived the reap"
fi
pass "(a3) the merged branch was deleted force-free (git branch -d accepted it)"

sa="$(printf '%s' "$oa" | surf_join)"
if grep -q 'unretirable-submodule:' <<<"$sa"; then
  fail "(a4) an uninitialised-submodule worktree was falsely marked unretirable-submodule: $sa"
fi
pass "(a4) no unretirable-submodule marker for the uninitialised case (the marker is predicted, not assumed)"

# =====================================================================================
# (b) POPULATED -- reaches the helper, is REFUSED, stays on disk, and IS surfaced.
# =====================================================================================
mksuper pop
add_wt "$tmp/pop" pop deadrun-review-repo-0
WT_B="$RELAY_WORKTREE_BASE/pop/deadrun-review-repo-0"
git -C "$WT_B" submodule update --init -q
: > "$WORKTREE_RETIRE_LOG"

ob="$("$RC" --repo pop --path "$tmp/pop" --live-claims "" --main-branch main 2>"$tmp/b.err")"
grep -q 'reap' <<<"$(printf '%s' "$ob" | acts)" \
  || fail "(b1) no disposal was planned for a POPULATED-submodule worktree, so worktree-retire.sh is never reached and cannot refuse specifically: $ob"
pass "(b1) disposal IS planned, so the helper is reached"

grep -q 'deadrun-review-repo-0' "$WORKTREE_RETIRE_LOG" \
  || fail "(b2) worktree-retire.sh was never invoked for the populated worktree (empty/irrelevant retire log): $(cat "$WORKTREE_RETIRE_LOG")"
pass "(b2) worktree-retire.sh was actually invoked and logged its verdict"

[[ -d "$WT_B" ]] \
  || fail "(b3) the POPULATED-submodule worktree was REMOVED -- something forced it; nothing here may force"
pass "(b3) the populated worktree is still on disk (helper refused, nothing forced)"

git -C "$tmp/pop" show-ref --verify --quiet refs/heads/relay/deadrun-review-repo-0 \
  || fail "(b4) the branch of a refused worktree was deleted or parked -- the helper must leave BOTH untouched"
pass "(b4) its branch is untouched"

sb="$(printf '%s' "$ob" | surf_join)"
grep -q 'unretirable-submodule:' <<<"$sb" \
  || fail "(b5) the populated worktree was SILENTLY skipped -- no unretirable-submodule marker surfaced: $sb"
pass "(b5) it is surfaced under the unretirable-submodule: class marker"

# =====================================================================================
# (c) DIRTY -- surfaced-and-left, nothing forced, the uncommitted bytes survive.
# =====================================================================================
mksuper dirty
add_wt "$tmp/dirty" dirty deadrun-review-repo-0
WT_C="$RELAY_WORKTREE_BASE/dirty/deadrun-review-repo-0"
printf 'UNCOMMITTED WORK\n' > "$WT_C/residue.txt"
git -C "$WT_C" add residue.txt   # tracked-but-uncommitted: genuinely dirty, not ignorable

oc="$("$RC" --repo dirty --path "$tmp/dirty" --live-claims "" --main-branch main 2>"$tmp/c.err")"
[[ -d "$WT_C" ]] \
  || fail "(c1) a DIRTY submodule worktree was removed -- the reversal turned newly-reachable disposal into work loss"
[[ "$(cat "$WT_C/residue.txt")" == "UNCOMMITTED WORK" ]] \
  || fail "(c2) the uncommitted residue in a dirty worktree did not survive reconcile"
pass "(c1/c2) a dirty submodule worktree is left on disk with its residue intact (nothing forced)"

git -C "$tmp/dirty" show-ref --verify --quiet refs/heads/relay/deadrun-review-repo-0 \
  || fail "(c3) the branch of a dirty, refused worktree was deleted"
pass "(c3) its branch is untouched"

# =====================================================================================
# (d) NEGATIVE CONTROL -- a plain non-submodule worktree behaves exactly as before.
# =====================================================================================
mkplain plain
add_wt "$tmp/plain" plain deadrun-review-repo-0
WT_D="$RELAY_WORKTREE_BASE/plain/deadrun-review-repo-0"

od="$("$RC" --repo plain --path "$tmp/plain" --live-claims "" --main-branch main 2>"$tmp/d.err")"
grep -q 'reap' <<<"$(printf '%s' "$od" | acts)" \
  || fail "(d1) a plain non-submodule worktree is no longer reaped -- ordinary disposal regressed: $od"
[[ ! -d "$WT_D" ]] || fail "(d2) a plain non-submodule worktree was not removed: $WT_D"
sd="$(printf '%s' "$od" | surf_join)"
if grep -q 'unretirable-submodule:' <<<"$sd"; then
  fail "(d3) a plain non-submodule worktree was mislabelled unretirable-submodule: $sd"
fi
pass "(d) a plain non-submodule worktree is still reaped, unmarked -- behaviour unchanged"

# =====================================================================================
# (e) THE LOAD-BEARING ONE -- the marker is ADDITIVE and recurs EVERY round.
#     A substitutive marker would suppress a repo carrying such a worktree forever (id:e7e4).
# =====================================================================================
oe2="$("$RC" --repo pop --path "$tmp/pop" --live-claims "" --main-branch main 2>"$tmp/e.err")"
se2="$(printf '%s' "$oe2" | surf_join)"
grep -q 'unretirable-submodule:' <<<"$se2" \
  || fail "(e1) the unretirable-submodule marker did NOT fire on the second round -- the class stops being reported: $se2"
pass "(e1) the marker fires again on the next round (report-every-round preserved)"

oe3="$("$DR" --repo pop --path "$tmp/pop" --runid freshrun --live-claims "" --main-branch main 2>"$tmp/e3.err")"
[[ "$(printf '%s' "$oe3" | ucount)" == "1" ]] \
  || fail "(e2) STARVATION: a repo with an open actionable [ROUTINE] item was NOT dispatched while an unremovable worktree is surfaced every round -- the marker has become substitutive (id:e7e4 shape): $oe3"
pass "(e2) the marker is ADDITIVE -- the repo is still dispatched"

echo "---"
echo "ALL PASS: reconcile reaches worktree-retire.sh for submodule worktrees; uninitialised ones are reaped force-free, populated ones refused and reported (id:a290)"
