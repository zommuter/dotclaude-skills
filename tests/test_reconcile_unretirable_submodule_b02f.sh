#!/usr/bin/env bash
# NO `# roadmap:` HEADER ON PURPOSE — this is a DEFECT-FIX test, not the RED spec of an open
# ROADMAP item, so expected-red semantics must NEVER apply to it and its failures always count.
#
# THE DEFECT (roadmap:b02f direction (c), never built until 2026-09-01).
# `git worktree remove` refuses ANY worktree whose tree carries `.gitmodules`, regardless of how
# clean or merged it is. Direction (b) — deinit the submodules first — was TESTED AND REFUTED on
# 2026-08-26: git keys the check on the file being in the tree, not on checkout state. So there
# is no force-free disposal route at all, and `--force` is denied fleet-wide (id:221f(a)).
#
# b02f closed on direction (a) alone (worktree-retire.sh emits a clearer message), even though
# the item itself named (c) — "have the census REPORT them as known-unretirable rather than
# RE-ATTEMPTING every run" — as cheap and composing. Without (c), reconcile PLANNED a reap/park
# for these worktrees every single round and APPLY re-invoked worktree-retire.sh to be refused
# every single time, swallowing exit 3 behind `|| true`. Measured 2026-09-01: 221 "containing
# submodules" lines and 51 UNRETIRABLE-SUBMODULE entries in the retire log, and FIVE worktrees /
# 1.8 GB accumulated on yinyang-puzzle between 2026-07-24 and 2026-09-01 — visible only in a log
# nobody reads, while the owner had already hit this exact issue once before.
#
# WHAT THIS LOCKS (behaviour, never doc strings):
#   (1) a submodule-carrying leftover worktree is NOT planned for reap/park (no retry loop);
#   (2) it IS surfaced, under the `unretirable-submodule:` CLASS MARKER;
#   (3) the repo is STILL DISPATCHED — the marker is ADDITIVE. This is the load-bearing one:
#       the surfaced entry fires on EVERY round for as long as the worktree exists, so if it
#       were substitutive the repo would be suppressed FOREVER. That is the id:e7e4 loderite
#       starvation shape, and yinyang-puzzle (5 such worktrees) is the repo it would bite.
#   (4) NEGATIVE CONTROL — the identical shape WITHOUT `.gitmodules` is still planned for
#       reap/park. Without this, "stop re-attempting" could have been implemented by disabling
#       worktree disposal altogether and every other assertion here would still pass.
#
# Hermetic: mktemp -d fixture git repos, RELAY_WORKTREE_BASE/RELAY_TOML redirected into the temp
# dir, no network, no ~/.claude or real-repo access.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DR="$ROOT/relay/scripts/discover-repo.sh"
RC="$ROOT/relay/scripts/reconcile-repo.sh"
[[ -x "$DR" ]] || { echo "FAIL: discover-repo.sh not found/executable: $DR"; exit 1; }
[[ -x "$RC" ]] || { echo "FAIL: reconcile-repo.sh not found/executable: $RC"; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export RELAY_WORKTREE_BASE="$tmp/wt"
export RELAY_TOML="$tmp/relay.toml"; : > "$RELAY_TOML"
export RECONCILE_LOG="$tmp/reconcile.log"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

mkrepo() { # <dir>
  local d="$1"; mkdir -p "$d"; git -C "$d" init -q -b main
  git -C "$d" config user.email t@e; git -C "$d" config user.name t
  git -C "$d" config commit.gpgsign false
}

# A stale MERGED worktree — the yinyang shape. Its commits are already in main, so absent the
# submodule blocker reconcile would plan a REAP for it.
stale_merged_worktree() { # <repo-dir> <repo-name> <basename>
  local d="$1" name="$2" bn="$3"
  git -C "$d" branch "relay/$bn" HEAD
  mkdir -p "$RELAY_WORKTREE_BASE/$name/$bn"
}

acount() { python3 -c 'import sys,json; print(len(json.load(sys.stdin).get("actions",[])))'; }
ucount() { python3 -c 'import sys,json; print(len(json.load(sys.stdin).get("units",[])))'; }
surf_join() { python3 -c 'import sys,json; print("|".join(s.get("reason","") for s in json.load(sys.stdin).get("surfaced",[])))'; }

# =====================================================================================
# (1)+(2) SUBMODULE repo: no reap/park planned, surfaced under the class marker.
# =====================================================================================
R1="$tmp/withsub"; mkrepo "$R1"
printf '# Roadmap\n## Items\n- [ ] [ROUTINE] work a <!-- id:57d1 -->\n' > "$R1/ROADMAP.md"
printf '# TODO\n## Current\n' > "$R1/TODO.md"
printf '[submodule "vendor/x"]\n\tpath = vendor/x\n\turl = https://example.invalid/x.git\n' > "$R1/.gitmodules"
git -C "$R1" add -A; git -C "$R1" commit -qm init
stale_merged_worktree "$R1" withsub deadrun-review-repo-0
# The worktree DIR must carry .gitmodules too — that is what git actually refuses on, and what
# the planner inspects.
cp "$R1/.gitmodules" "$RELAY_WORKTREE_BASE/withsub/deadrun-review-repo-0/.gitmodules"

o1="$("$RC" --dry-run --repo withsub --path "$R1" --live-claims "" --main-branch main 2>/dev/null)"
[[ "$(printf '%s' "$o1" | acount)" == "0" ]] \
  || fail "(1) RETRY LOOP: a submodule-carrying worktree was still planned for reap/park, so APPLY will re-invoke worktree-retire.sh to be refused again every round: $o1"
pass "(1) a submodule-carrying worktree is not planned for reap/park (no retry loop)"

# NB: capture into a variable and use a here-string rather than piping into `grep -q`.
# `grep -q` exits at the first match, so a producer piped into it under `set -o pipefail`
# is the id:81d5 SIGPIPE shape the repo's own lint rejects.
s1="$(printf '%s' "$o1" | surf_join)"
grep -q 'unretirable-submodule:' <<<"$s1" \
  || fail "(2) the unretirable worktree is not surfaced under the 'unretirable-submodule:' class marker: $s1"
pass "(2) it is surfaced under the unretirable-submodule: class marker"

# =====================================================================================
# (3) THE LOAD-BEARING ONE — the marker must be ADDITIVE, so the repo is still dispatched.
#     This surfaced entry recurs on EVERY round; substitutive would suppress the repo forever.
# =====================================================================================
o3="$("$DR" --repo withsub --path "$R1" --runid freshrun --live-claims "" --main-branch main 2>/dev/null)"
[[ "$(printf '%s' "$o3" | ucount)" == "1" ]] \
  || fail "(3) STARVATION: a repo with an open actionable [ROUTINE] item was NOT dispatched because an UNREMOVABLE worktree is surfaced every round — this is the id:e7e4 shape and it would suppress the repo permanently: $o3"
pass "(3) the unretirable-submodule marker is ADDITIVE — the repo is still dispatched"

# =====================================================================================
# (4) NEGATIVE CONTROL — same shape, NO .gitmodules: reap/park is still planned.
#     Without this, disabling worktree disposal entirely would pass (1)-(3).
# =====================================================================================
R2="$tmp/nosub"; mkrepo "$R2"
printf '# Roadmap\n## Items\n- [ ] [ROUTINE] work a <!-- id:6612 -->\n' > "$R2/ROADMAP.md"
printf '# TODO\n## Current\n' > "$R2/TODO.md"
git -C "$R2" add -A; git -C "$R2" commit -qm init
stale_merged_worktree "$R2" nosub deadrun-review-repo-0

o4="$("$RC" --dry-run --repo nosub --path "$R2" --live-claims "" --main-branch main 2>/dev/null)"
[[ "$(printf '%s' "$o4" | acount)" -ge 1 ]] \
  || fail "(4) NEGATIVE CONTROL FAILED: a NON-submodule stale worktree was also skipped — worktree disposal has been disabled wholesale, not narrowed to the submodule case: $o4"
pass "(4) a non-submodule stale worktree is STILL planned for disposal (skip is submodule-scoped)"

s4="$(printf '%s' "$o4" | surf_join)"
if grep -q 'unretirable-submodule:' <<<"$s4"; then
  fail "(4b) a non-submodule worktree was mislabelled unretirable-submodule: $s4"
else
  pass "(4b) the marker is not applied to non-submodule worktrees"
fi

echo "---"
echo "ALL PASS: known-unretirable submodule worktrees are reported, not re-attempted (roadmap:b02f (c))"
