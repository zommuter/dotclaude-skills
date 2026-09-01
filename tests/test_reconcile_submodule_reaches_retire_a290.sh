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
# fails-against: relay/scripts/reconcile-repo.sh at the FIRST cut of that reversal, which shipped
#   three further defects in HOW it predicts and reports: (1) the marker predicate was NARROWER
#   than git's own trigger on three counts (an outer `.gitmodules` gate, a non-empty `find` on
#   `<admin>/modules`, and a gitdir resolved against the CWD instead of the worktree directory);
#   (2) the reap path's `|| true` swallowed worktree-retire.sh's non-zero exit entirely, so a
#   missed prediction was TOTAL SILENCE; (3) an UNMERGED unretirable worktree was planned for a
#   park the helper can never complete, whose orphan-suppress then starved the item forever.
# fails-against-rev: f297ea5710e3d896ff4e222bf4903531b453fce7 -- relay/scripts/reconcile-repo.sh
# fails-against-assertion: (f1) STARVATION via the PARK route
#   REACHABILITY, recorded per the CLAUDE.md rule: this file exits at its first failing
#   assertion, so exactly ONE assertion can be declared per revision. Case (f) is ordered first
#   among the new cases so the declared one is the STARVATION assertion (0 units where 1 was
#   expected), which is the consequence the 2026-09-01 owner ruling is about. The other three
#   reds at this same revision were each confirmed in isolation and are recorded here so they
#   cannot be quietly lost:
#     (g2) TOTAL SILENCE: a worktree git refuses to remove was neither predicted nor surfaced,
#          because the predicate gated on .gitmodules being in the tree
#     (h2) an EMPTY <admin>/modules directory was predicted retirable, but git refuses it
#     (i1) a RELATIVE gitdir defeated the prediction
#     (j1) the reap path SWALLOWED worktree-retire.sh's non-zero exit
#
# fails-against: relay/scripts/reconcile-repo.sh at the SECOND cut, which applied "report from
#   the OUTCOME" to the REAP loop ONLY and left the PARK loop on `>/dev/null 2>&1 || true`,
#   defended by an EXISTENCE probe (`show-ref refs/heads/relay/orphan/<bn>`) that asks a
#   different question from "did the helper succeed?". worktree-retire.sh's ORPHAN-COLLISION
#   branch removes the worktree, KEEPS the branch as relay/<bn> and exits 3; show-ref then
#   passes on the PRE-EXISTING ref, so a park is announced onto ANOTHER run's commits, this
#   run's work is stranded on a branch whose worktree directory is now gone, and nothing
#   reaches stderr or the reconcile log in any round.
# fails-against-rev: 3c130b1d3ad4c08bdfa2c15f6ca02869ce589b89 -- relay/scripts/reconcile-repo.sh
# fails-against-assertion: (k2) the park path SWALLOWED worktree-retire.sh's non-zero exit
#   REACHABILITY at this revision: (k2) is the FIRST and ONLY failing assertion. Everything
#   before it passes there, and the cases added alongside it -- (l)/(m), the predicate's
#   NEGATIVE direction for a non-directory `<admin>/modules`, and the rewritten (i) -- pass at
#   this revision by design: they lock behaviour that was already correct so a future widening
#   of git's trigger cannot silently break it.
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
#   (f) THE PARK PATH (owner-ruled 2026-09-01): an UNMERGED worktree the helper will refuse is
#       NOT planned for a park, IS still surfaced, keeps worktree + branch + partial work, and
#       the repo STILL yields its unit. Checked against the parent revision, where it yielded 0.
#       No relay/orphan ref is announced, so the id:1af1 phantom-park line cannot fire.
#   (g) PREDICATE == git's TRIGGER, part 1: a POPULATED worktree with NO `.gitmodules` in its
#       tree (submodule initialised, then `git reset --hard` to a commit predating it) is still
#       refused by git and must still be reported.
#   (h) part 2: an EMPTY `<admin>/modules` directory, in a repo with NO submodules at all, is
#       refused by git -- so the marker must predict True on mere existence of that directory.
#   (i) part 3: `worktree.useRelativePaths` writes `gitdir: ../../…`, relative to the WORKTREE
#       directory; the prediction must survive it.
#   (j) REPORT FROM THE OUTCOME: a non-zero worktree-retire.sh exit on the REAP path is reported
#       on stderr, naming the worktree and quoting the helper. This is the half that guarantees
#       nothing is silent -- a prediction can be wrong, an outcome cannot.
#   (k) THE SAME, ON THE PARK PATH -- and proof the existence probe cannot substitute for it:
#       an ORPHAN-COLLISION park exits 3 while `relay/orphan/<bn>` DOES exist, holding another
#       run's commits. The two loops are asserted symmetric (stderr line + reconcile-log row).
#   (l)/(m) THE PREDICATE'S NEGATIVE DIRECTION: `<admin>/modules` as a regular FILE and as a
#       DANGLING SYMLINK are both retirable, and really are removed. git's trigger is
#       `is_directory()`; if a future git widened it to mere existence, the predicate would
#       start UNDER-predicting, and nothing else in this file would notice.
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
grep -q 'UNRETIRABLE-SUBMODULE-UNRECOGNIZED' "$WORKTREE_RETIRE_LOG" \
  || fail "(b2b) the helper was reached but did not record its FAIL-CLOSED submodule verdict -- that log token exists in worktree-retire.sh and nowhere else, so its absence means the refusal came from somewhere other than the submodule guard: $(cat "$WORKTREE_RETIRE_LOG")"
pass "(b2) worktree-retire.sh was actually invoked and logged its verdict (UNRETIRABLE-SUBMODULE-UNRECOGNIZED)"

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


# =====================================================================================
# (f) THE PARK PATH -- an UNMERGED worktree the helper will REFUSE must NOT be planned for
#     a park (owner-ruled 2026-09-01). This is the handback/crash case the whole change
#     exists for, and it was the one case with no test.
#
#     THE DEFECT: reconcile planned a park that can NEVER complete. worktree-retire.sh exits
#     3 at the WORKTREE step and never reaches branch disposition, so relay/orphan/<bn> never
#     comes into existence -- yet the park was ANNOUNCED, PARK VERIFY FAILED (id:1af1) fired
#     every round, and the orphan-suppress step bound the PLANNED park and suppressed the
#     item's re-dispatch permanently. Measured on the parent revision: discover-repo.sh
#     yielded 0 units where it had yielded 1. Item-scoped, so a second open item still
#     dispatches -- but that item is unreachable for good and a single-item repo goes dark.
#     That is the id:e7e4 starvation class arriving by the park route.
#
#     ACCEPTED COST, asserted here so it is not "fixed" back by accident: the partial work
#     stays on disk AND the item stays dispatchable, so a fresh executor may start over an
#     abandoned worktree. The owner chose that over keeping the suppression, because a silent
#     dispatch reduction is the worse failure. No suppression may reappear in another form.
# =====================================================================================
mksuper unmerged
add_wt "$tmp/unmerged" unmerged deadrun-execute-57d1-0
WT_F="$RELAY_WORKTREE_BASE/unmerged/deadrun-execute-57d1-0"
git -C "$WT_F" submodule update --init -q
printf 'PARTIAL WORK FROM A DEAD EXECUTOR\n' > "$WT_F/partial.txt"
git -C "$WT_F" add partial.txt
git -C "$WT_F" commit -qm "WIP partial work"
if git -C "$tmp/unmerged" merge-base --is-ancestor relay/deadrun-execute-57d1-0 main; then
  fail "(f0) fixture broken: the worktree branch is still an ancestor of main, so this is a REAP not a PARK"
fi
pass "(f0) fixture: an UNMERGED worktree carrying a populated private submodule store"

of="$("$DR" --repo unmerged --path "$tmp/unmerged" --runid freshrun --live-claims "" --main-branch main 2>"$tmp/f.err")"
[[ "$(printf '%s' "$of" | ucount)" == "1" ]] \
  || fail "(f1) STARVATION via the PARK route: the repo yielded no unit for its open [ROUTINE] item. An unmerged worktree the retire helper cannot dispose of was planned for a park that can never complete, and the orphan-suppress step then suppressed the item permanently: $of"
pass "(f1) the repo still yields its unit -- the item stays dispatchable"

ofr="$("$RC" --repo unmerged --path "$tmp/unmerged" --live-claims "" --main-branch main 2>"$tmp/f2.err")"
if grep -q 'park' <<<"$(printf '%s' "$ofr" | acts)"; then
  fail "(f2) a PARK was planned for a worktree worktree-retire.sh structurally cannot park -- the helper exits before branch disposition, so relay/orphan/ can never appear: $ofr"
fi
pass "(f2) no park is planned for a worktree the helper will refuse"

sf="$(printf '%s' "$ofr" | surf_join)"
grep -q 'unretirable-submodule:' <<<"$sf" \
  || fail "(f3) the unmergeable, unretirable worktree was SILENTLY dropped -- not planned, not surfaced: $sf"
pass "(f3) it is still reported under the unretirable-submodule: class marker"

if grep -q 'parked-orphan (planned):' <<<"$sf"; then
  fail "(f4) a relay/orphan ref was ANNOUNCED for a worktree that can never be parked -- the id:1af1 phantom-park shape: $sf"
fi
pass "(f4) no phantom relay/orphan ref is announced"

if git -C "$tmp/unmerged" show-ref --verify --quiet refs/heads/relay/orphan/deadrun-execute-57d1-0; then
  fail "(f5) relay/orphan/deadrun-execute-57d1-0 exists -- something parked a branch this path must leave alone"
fi
git -C "$tmp/unmerged" show-ref --verify --quiet refs/heads/relay/deadrun-execute-57d1-0 \
  || fail "(f6) the unmerged branch relay/deadrun-execute-57d1-0 was renamed or deleted"
[[ -d "$WT_F" && "$(cat "$WT_F/partial.txt")" == "PARTIAL WORK FROM A DEAD EXECUTOR" ]] \
  || fail "(f7) the unmerged worktree or its committed partial work did not survive"
pass "(f5/f6/f7) worktree, branch and partial work are left exactly as they were"

if grep -q 'PARK VERIFY FAILED' "$tmp/f.err" "$tmp/f2.err"; then
  fail "(f8) PARK VERIFY FAILED still fires -- the phantom park was planned after all: $(cat "$tmp/f.err" "$tmp/f2.err")"
fi
pass "(f8) the id:1af1 phantom-park verification never fires, by construction"

# =====================================================================================
# (g) PREDICATE vs TRUTH, case 1 -- a POPULATED worktree with NO `.gitmodules` in its tree.
#     Built the realistic way: initialise the submodule in the worktree, then `git reset
#     --hard` to a commit predating it (git leaves the populated checkout behind, warning
#     "unable to rmdir"). git STILL refuses to remove it, but the old outer
#     `-e "$wtdir/$bn/.gitmodules"` gate skipped the whole block: reap planned, helper
#     refused, and NOTHING was reported anywhere.
# =====================================================================================
mksuper nogm
PRE_G="$(git -C "$tmp/nogm" rev-parse HEAD~1)"   # the commit BEFORE `submodule add`
add_wt "$tmp/nogm" nogm probe-nogm
add_wt "$tmp/nogm" nogm deadrun-review-repo-0
for __w in probe-nogm deadrun-review-repo-0; do
  git -C "$RELAY_WORKTREE_BASE/nogm/$__w" submodule update --init -q
  # stderr captured, not swallowed: `reset --hard` legitimately warns "unable to rmdir
  # 'vendor/x': Directory not empty", which is precisely the state this case is about.
  git -C "$RELAY_WORKTREE_BASE/nogm/$__w" reset --hard -q "$PRE_G" 2>"$tmp/g.reset.err"
done
WT_G="$RELAY_WORKTREE_BASE/nogm/deadrun-review-repo-0"
[[ ! -e "$WT_G/.gitmodules" ]] \
  || fail "(g0) fixture broken: .gitmodules is still in the worktree tree, so this is not the no-.gitmodules case"
[[ -d "$tmp/nogm/.git/worktrees/deadrun-review-repo-0/modules" ]] \
  || fail "(g0b) fixture broken: the private submodule store was cleaned up, so git has nothing to refuse on"
if LC_ALL=C git -C "$tmp/nogm" worktree remove "$RELAY_WORKTREE_BASE/nogm/probe-nogm" 2>"$tmp/g.err"; then
  fail "(g1) git REMOVED a populated worktree that carries no .gitmodules -- the refusal this case is about is gone"
fi
grep -q 'containing submodules' "$tmp/g.err" \
  || fail "(g1b) git refused with an unexpected message: $(cat "$tmp/g.err")"
pass "(g1) git refuses a populated worktree whose tree carries NO .gitmodules"

og="$("$RC" --repo nogm --path "$tmp/nogm" --live-claims "" --main-branch main 2>"$tmp/g2.err")"
sg="$(printf '%s' "$og" | surf_join)"
grep -q 'unretirable-submodule:' <<<"$sg" \
  || fail "(g2) TOTAL SILENCE: a worktree git refuses to remove was neither predicted nor surfaced, because the predicate gated on .gitmodules being in the tree: $sg"
pass "(g2) it is predicted and surfaced -- the predicate no longer gates on .gitmodules"

# =====================================================================================
# (h) PREDICATE vs TRUTH, case 2 -- an EMPTY `<admin>/modules` directory. git refuses on the
#     mere EXISTENCE of that directory, even in a repo with NO submodules at all, so the
#     old non-empty `find` test was narrower than git's own trigger.
# =====================================================================================
mkplain emptymod
add_wt "$tmp/emptymod" emptymod probe-empty
add_wt "$tmp/emptymod" emptymod deadrun-review-repo-0
mkdir -p "$tmp/emptymod/.git/worktrees/probe-empty/modules"
mkdir -p "$tmp/emptymod/.git/worktrees/deadrun-review-repo-0/modules"
if LC_ALL=C git -C "$tmp/emptymod" worktree remove "$RELAY_WORKTREE_BASE/emptymod/probe-empty" 2>"$tmp/h.err"; then
  fail "(h1) git removed a worktree with an EMPTY private modules/ directory -- its trigger is no longer mere existence"
fi
grep -q 'containing submodules' "$tmp/h.err" \
  || fail "(h1b) git refused the empty-modules worktree with an unexpected message: $(cat "$tmp/h.err")"
pass "(h1) git refuses on an EMPTY <admin>/modules directory, in a repo with no submodules at all"

oh="$("$RC" --repo emptymod --path "$tmp/emptymod" --live-claims "" --main-branch main 2>"$tmp/h2.err")"
sh_="$(printf '%s' "$oh" | surf_join)"
grep -q 'unretirable-submodule:' <<<"$sh_" \
  || fail "(h2) an EMPTY <admin>/modules directory was predicted retirable, but git refuses it -- the predicate is narrower than git's trigger: $sh_"
pass "(h2) the marker predicts True for an empty private submodule store"

# =====================================================================================
# (i) GITDIR RESOLUTION -- `worktree.useRelativePaths` writes `gitdir: ../../…`, which is
#     relative to the WORKTREE DIRECTORY. Resolving it against reconcile's own CWD yields a
#     path that does not exist, so every worktree in such a repo predicted "retirable".
#
#     THE RELATIVE `.git` FILE IS WRITTEN DIRECTLY, not via `worktree.useRelativePaths`.
#     What this case asserts is RECONCILE'S GITDIR RESOLUTION, not git's ability to WRITE a
#     relative gitdir -- and that config is only honoured from git 2.48, so keying the fixture
#     on it made a headerless (always-counting) test hard-fail on e.g. Raspbian bookworm's
#     2.39.5 for a reason unrelated to the code under test. Writing the one-line `.git` file
#     by hand exercises the SAME code path on EVERY git version with no precondition: reading
#     a relative `gitdir:` has been supported since long before 2.48 (it is how submodules
#     have always been linked), so the worktree stays fully functional.
# =====================================================================================
mksuper relpath
add_wt "$tmp/relpath" relpath deadrun-review-repo-0
WT_I="$RELAY_WORKTREE_BASE/relpath/deadrun-review-repo-0"
git -C "$WT_I" submodule update --init -q
WT_I_ADMIN="$tmp/relpath/.git/worktrees/deadrun-review-repo-0"
[[ -d "$WT_I_ADMIN/modules" ]] \
  || fail "(i0a) fixture broken: no private submodule store at $WT_I_ADMIN/modules, so there is nothing for the predicate to find"
printf 'gitdir: %s\n' \
  "$(python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$WT_I_ADMIN" "$WT_I")" \
  > "$WT_I/.git"
grep -q '^gitdir: [^/]' "$WT_I/.git" \
  || fail "(i0) fixture broken: gitdir is NOT relative ($(cat "$WT_I/.git"))"
[[ "$(git -C "$WT_I" rev-parse --git-dir)" == "$WT_I_ADMIN" ]] \
  || fail "(i0b) fixture broken: git itself no longer resolves the hand-written relative gitdir ($(git -C "$WT_I" rev-parse --git-dir))"
pass "(i0) fixture: the worktree's .git carries a RELATIVE gitdir that git still resolves"

oi="$("$RC" --repo relpath --path "$tmp/relpath" --live-claims "" --main-branch main 2>"$tmp/i.err")"
si="$(printf '%s' "$oi" | surf_join)"
grep -q 'unretirable-submodule:' <<<"$si" \
  || fail "(i1) a RELATIVE gitdir defeated the prediction -- the admin path was resolved against reconcile's CWD instead of the worktree directory: $si"
pass "(i1) the prediction works with a relative gitdir"

# =====================================================================================
# (j) REPORT FROM THE OUTCOME -- the reap path must not swallow a helper refusal.
#     Case (b) above reaped a populated worktree and the helper exited non-zero. With the
#     old `>/dev/null 2>&1 || true` that produced NOTHING on stderr, which is why a missed
#     prediction was total silence rather than a bounded per-round cost.
# =====================================================================================
grep -q 'REAP RETIRE FAILED' "$tmp/b.err" \
  || fail "(j1) the reap path SWALLOWED worktree-retire.sh's non-zero exit -- a refused reap is reported nowhere: $(cat "$tmp/b.err")"
grep -q 'deadrun-review-repo-0' "$tmp/b.err" \
  || fail "(j2) the reap failure line does not name the worktree it is about: $(cat "$tmp/b.err")"
grep -q 'retire-unretirable' "$tmp/b.err" \
  || fail "(j3) the reap failure line does not carry worktree-retire.sh's own message: $(cat "$tmp/b.err")"
pass "(j1/j2/j3) a refused reap is reported on stderr, naming the worktree and quoting the helper"

# =====================================================================================
# (k) THE PARK PATH REPORTS FROM THE OUTCOME TOO -- and the id:1af1 EXISTENCE check alone
#     structurally cannot see this shape.
#
#     worktree-retire.sh has an ORPHAN-COLLISION branch (`refs/heads/relay/orphan/<bn>`
#     already exists): it removes the worktree, KEEPS the branch as `relay/<bn>`, and exits
#     3. `show-ref --verify refs/heads/relay/orphan/<bn>` then PASSES -- on the PRE-EXISTING
#     ref, which holds a DIFFERENT run's commits. So reconcile announces relay/orphan/<bn>
#     as where this work went; the work is actually stranded on relay/<bn>; the worktree
#     directory is gone, so this path never lists it again in any later round; and with the
#     old `>/dev/null 2>&1 || true` NOTHING reached stderr or the reconcile log, ever.
#     That is the id:1af1 phantom-park class with the ref PRESENT but the WRONG OBJECT.
#
#     "Does the ref exist?" and "did the helper succeed?" are DIFFERENT questions. The
#     OUTCOME check is the load-bearing one; the existence check stays as defence in depth.
#     Symmetric with the reap loop above by construction -- the two loops have now had the
#     same defect found on them in three successive reviews, each time on whichever loop the
#     tests did not cover.
# =====================================================================================
mkplain collide
add_wt "$tmp/collide" collide deadrun-execute-6612-0
WT_K="$RELAY_WORKTREE_BASE/collide/deadrun-execute-6612-0"
printf 'WORK FROM THE SECOND DEAD RUN\n' > "$WT_K/two.txt"
git -C "$WT_K" add two.txt
git -C "$WT_K" commit -qm "WIP work from the second dead run"
K_WORK="$(git -C "$tmp/collide" rev-parse relay/deadrun-execute-6612-0)"
# A PRE-EXISTING orphan of the SAME basename, from an earlier dead run, at a DIFFERENT commit.
git -C "$tmp/collide" branch relay/orphan/deadrun-execute-6612-0 main
K_OLD="$(git -C "$tmp/collide" rev-parse relay/orphan/deadrun-execute-6612-0)"
[[ "$K_WORK" != "$K_OLD" ]] \
  || fail "(k0) fixture broken: the colliding orphan ref points at the same commit as the work, so a wrong-object announcement would be indistinguishable"
if git -C "$tmp/collide" merge-base --is-ancestor relay/deadrun-execute-6612-0 main; then
  fail "(k0b) fixture broken: the worktree branch is an ancestor of main, so this is a REAP not a PARK"
fi
pass "(k0) fixture: an UNMERGED worktree whose orphan ref name is ALREADY TAKEN by another run"

ok="$("$RC" --repo collide --path "$tmp/collide" --live-claims "" --main-branch main 2>"$tmp/k.err")"
grep -q 'park' <<<"$(printf '%s' "$ok" | acts)" \
  || fail "(k1) no park was planned for an ordinary unmerged worktree, so the park path is not even exercised: $ok"
pass "(k1) a park IS planned, so worktree-retire.sh is reached on the park path"

grep -q 'PARK RETIRE FAILED' "$tmp/k.err" \
  || fail "(k2) the park path SWALLOWED worktree-retire.sh's non-zero exit -- the helper hit ORPHAN-COLLISION, kept the work on relay/deadrun-execute-6612-0 and exited 3, yet nothing was reported. The existence check cannot catch this: relay/orphan/deadrun-execute-6612-0 exists, holding ANOTHER run's commits: $(cat "$tmp/k.err")"
grep -q 'deadrun-execute-6612-0' "$tmp/k.err" \
  || fail "(k3) the park failure line does not name the worktree it is about: $(cat "$tmp/k.err")"
grep -q 'orphan ref' "$tmp/k.err" \
  || fail "(k4) the park failure line does not carry worktree-retire.sh's own message (its ORPHAN-COLLISION text): $(cat "$tmp/k.err")"
pass "(k2/k3/k4) a failed park is reported on stderr from the OUTCOME, naming the worktree and quoting the helper"

grep -q 'park-retire-failed' "$RECONCILE_LOG" \
  || fail "(k5) no reconcile-log row was written for the failed park -- the reap path writes one and the two loops must be symmetric: $(cat "$RECONCILE_LOG")"
pass "(k5) a reconcile-log row is written, exactly as the reap path does"

if grep -q 'PARK VERIFY FAILED' "$tmp/k.err"; then
  fail "(k6) fixture assumption broken: the existence check DID fire, so this is not the wrong-object shape it is built to expose"
fi
pass "(k6) the existence check stays silent here -- proof it is not the load-bearing half"

[[ "$(git -C "$tmp/collide" rev-parse relay/orphan/deadrun-execute-6612-0)" == "$K_OLD" ]] \
  || fail "(k7) the pre-existing orphan ref was overwritten -- the helper must never clobber an older run's parked work"
[[ "$(git -C "$tmp/collide" rev-parse relay/deadrun-execute-6612-0)" == "$K_WORK" ]] \
  || fail "(k8) this run's work is no longer on relay/deadrun-execute-6612-0 -- the helper's ORPHAN-COLLISION branch must KEEP it there"
pass "(k7/k8) the older orphan is untouched and this run's work is kept on relay/<bn> (stranded, but reported)"

# =====================================================================================
# (l) NEGATIVE DIRECTION of the predicate, shape 1: `<admin>/modules` as a REGULAR FILE.
#     Nothing else locks this direction. git's trigger is `is_directory()`, so a plain file
#     of that name is NOT refused; `[[ -d … ]]` agrees and predicts RETIRABLE. Asserted so
#     that if a future git widened its trigger from is_directory to mere EXISTENCE, the
#     predicate's under-prediction would be caught here instead of going silent.
# =====================================================================================
mkplain modfile
add_wt "$tmp/modfile" modfile probe-file
add_wt "$tmp/modfile" modfile deadrun-review-repo-0
printf 'not a directory\n' > "$tmp/modfile/.git/worktrees/probe-file/modules"
printf 'not a directory\n' > "$tmp/modfile/.git/worktrees/deadrun-review-repo-0/modules"
LC_ALL=C git -C "$tmp/modfile" worktree remove "$RELAY_WORKTREE_BASE/modfile/probe-file" 2>"$tmp/l.err" \
  || fail "(l1) git REFUSED a worktree whose <admin>/modules is a regular FILE -- its trigger is no longer is_directory, so the predicate now under-predicts: $(cat "$tmp/l.err")"
pass "(l1) git removes a worktree whose <admin>/modules is a regular FILE"

ol="$("$RC" --repo modfile --path "$tmp/modfile" --live-claims "" --main-branch main 2>"$tmp/l2.err")"
if grep -q 'unretirable-submodule:' <<<"$(printf '%s' "$ol" | surf_join)"; then
  fail "(l2) a regular FILE named modules was predicted unretirable, but git removes it -- the predicate now OVER-predicts: $(printf '%s' "$ol" | surf_join)"
fi
[[ ! -d "$RELAY_WORKTREE_BASE/modfile/deadrun-review-repo-0" ]] \
  || fail "(l3) the worktree was not actually removed, so (l2) proves nothing about disposal"
pass "(l2/l3) it is predicted RETIRABLE and really is disposed of"

# =====================================================================================
# (m) NEGATIVE DIRECTION, shape 2: `<admin>/modules` as a DANGLING SYMLINK. `[[ -d … ]]`
#     follows symlinks, so a dangling one is false; git's is_directory() (a stat) agrees.
# =====================================================================================
mkplain modlink
add_wt "$tmp/modlink" modlink probe-link
add_wt "$tmp/modlink" modlink deadrun-review-repo-0
ln -s ./no-such-target "$tmp/modlink/.git/worktrees/probe-link/modules"
ln -s ./no-such-target "$tmp/modlink/.git/worktrees/deadrun-review-repo-0/modules"
[[ -L "$tmp/modlink/.git/worktrees/probe-link/modules" && ! -e "$tmp/modlink/.git/worktrees/probe-link/modules" ]] \
  || fail "(m0) fixture broken: modules is not a DANGLING symlink"
LC_ALL=C git -C "$tmp/modlink" worktree remove "$RELAY_WORKTREE_BASE/modlink/probe-link" 2>"$tmp/m.err" \
  || fail "(m1) git REFUSED a worktree whose <admin>/modules is a DANGLING SYMLINK -- its trigger is no longer is_directory, so the predicate now under-predicts: $(cat "$tmp/m.err")"
pass "(m1) git removes a worktree whose <admin>/modules is a dangling symlink"

om="$("$RC" --repo modlink --path "$tmp/modlink" --live-claims "" --main-branch main 2>"$tmp/m2.err")"
if grep -q 'unretirable-submodule:' <<<"$(printf '%s' "$om" | surf_join)"; then
  fail "(m2) a DANGLING SYMLINK named modules was predicted unretirable, but git removes it -- the predicate now OVER-predicts: $(printf '%s' "$om" | surf_join)"
fi
[[ ! -d "$RELAY_WORKTREE_BASE/modlink/deadrun-review-repo-0" ]] \
  || fail "(m3) the worktree was not actually removed, so (m2) proves nothing about disposal"
pass "(m2/m3) it is predicted RETIRABLE and really is disposed of"

echo "---"
echo "ALL PASS: reconcile reaches worktree-retire.sh for submodule worktrees; the predicate is git's own trigger in BOTH directions, BOTH the reap and the park loop report from the outcome, and an unparkable worktree is surfaced without a park (id:a290)"
