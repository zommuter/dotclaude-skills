#!/usr/bin/env bash
# fails-against: c9c7fc0 (reconcile-repo.sh:179 surfaced the planned park as bare prose "stale
#   worktree … to be parked as relay/orphan/…", which discover-repo.sh's class dispatcher could
#   only read as NOT-orphan-suppress ⇒ SUBSTITUTIVE ⇒ units:[]. Verified red at that revision:
#   case (1) fails with units=0 where 1 is required, and case (4) fails because no surfaced
#   reason carries the STARVED prefix. Cases (2)/(3)/(5) are green both before and after — they
#   are the negative controls proving the fix is not "always classify regardless of surfaced".)
#
# NO `# roadmap:` HEADER ON PURPOSE — this is a DEFECT-FIX test, not the RED spec of an open
# ROADMAP item, so expected-red semantics must NEVER apply to it and its failures always count.
#
# THE DEFECT (id:e7e4). loderite classified `execute` with 6 open executor-actionable [ROUTINE]
# items and produced ZERO work in two consecutive pool runs (relay-20260820-180056-4594 and
# relay-20260821-174757-32436). Its only problem was a leftover worktree from a DEAD run. The
# ratified D1 (meeting 2026-07-23, id:bc49/7e87) says a parked orphan is ADDITIVE SURFACE and
# NEVER suppresses classify/dispatch — but that rule was keyed to the "suppressed re-dispatch:"
# prefix alone, so the round in which a park is PLANNED fell outside it and starved the repo
# repo-scoped. RELAY_STATUS.md then recorded one line indistinguishable from "nothing to do".
#
# WHAT THIS LOCKS (behaviour, never doc strings):
#   (1) a repo with actionable work + a dead run's leftover worktree IS dispatched (units==1,
#       verdict execute) — the loderite shape;
#   (2) the park notification still reaches `surfaced` (additive, not dropped);
#   (3) SAME-ITEM carve-out still applies to a planned park bound to the repo's only open item
#       (units==0) — so (1) is not "classify unconditionally";
#   (4) a genuinely SUBSTITUTIVE block (in-flight/live-claimed, id:ebfb) that carries actionable
#       work is still units:[] BUT its surfaced reason is LOUD: it starts with "STARVED (";
#   (5) a substitutive block with NO actionable work must NOT be labelled STARVED.
#
# Hermetic: mktemp -d fixture git repos, RELAY_WORKTREE_BASE/RELAY_TOML redirected into the temp
# dir, no network, no ~/.claude or real-repo access.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DR="$ROOT/relay/scripts/discover-repo.sh"
[[ -x "$DR" ]] || { echo "FAIL: discover-repo.sh not found/executable: $DR"; exit 1; }

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
# Build the loderite shape: a stale, UNMERGED relay/<bn> branch plus its leftover worktree DIR
# under RELAY_WORKTREE_BASE (the two inputs reconcile-repo.sh's park planner reads).
stale_worktree() { # <repo-dir> <repo-name> <basename> <commit-msg>
  local d="$1" name="$2" bn="$3" msg="$4"
  git -C "$d" branch "relay/$bn" HEAD
  echo partial >> "$d/wip.txt"; git -C "$d" add wip.txt; git -C "$d" commit -qm "$msg"
  git -C "$d" branch -f "relay/$bn" HEAD
  git -C "$d" reset -q --hard HEAD~1      # main drops the wip; it lives only on relay/<bn>
  mkdir -p "$RELAY_WORKTREE_BASE/$name/$bn"
}
ncount()    { python3 -c 'import sys,json; print(len(json.load(sys.stdin).get(sys.argv[1],[])))' "$1"; }
uverdict()  { python3 -c 'import sys,json; u=json.load(sys.stdin).get("units",[]); print(u[0]["verdict"] if u else "<none>")'; }
surf_join() { python3 -c 'import sys,json; print("|".join(s.get("reason","") for s in json.load(sys.stdin).get("surfaced",[])))'; }

# =====================================================================================
# (1)+(2) THE LODERITE SHAPE — actionable work + a dead run's leftover worktree.
#         The park is planned this round; the orphan commit binds to NO roadmap item, so
#         nothing item-scoped may suppress. The repo MUST be dispatched, and the park
#         notification MUST still be surfaced alongside it.
# =====================================================================================
R1="$tmp/loderite"; mkrepo "$R1"
printf '# Roadmap\n## Items\n- [ ] [ROUTINE] work a <!-- id:57d1 -->\n- [ ] [ROUTINE] work b <!-- id:6612 -->\n' > "$R1/ROADMAP.md"
printf '# TODO\n## Current\n' > "$R1/TODO.md"
git -C "$R1" add -A; git -C "$R1" commit -qm init
stale_worktree "$R1" loderite deadrun-execute-repo-0 "executor wip, no item binding"

o1="$("$DR" --repo loderite --path "$R1" --runid freshrun --live-claims "" --main-branch main 2>/dev/null)"
[[ "$(printf '%s' "$o1" | ncount units)" == "1" ]] \
  || fail "(1) STARVATION: a repo with 2 open actionable [ROUTINE] items was NOT dispatched because a dead run left a worktree behind — units=$(printf '%s' "$o1" | ncount units): $o1"
[[ "$(printf '%s' "$o1" | uverdict)" == "execute" ]] \
  || fail "(1) dispatched unit verdict != execute: $o1"
pass "(1) leftover worktree from a dead run no longer zeroes out a repo with actionable work"

# Assert on the MARKER (id:e7e4's "parked-orphan (planned):" class prefix), not the
# worktree BASENAME. The pre-fix suppress reason ALSO names the basename ("stale
# worktree $bn from a dead run"), so a basename grep passes even when the additive-surf
# fold is reverted — id:f0ad(c) demonstrated this leaves the test 5/5-green against a
# revert of discover-repo.sh:170,179,203,245. The marker is the thing the class
# dispatcher actually keys on (discover-repo.sh's ADDITIVE tuple), so it is the only
# assertion that can tell "additive surfaced" apart from "repo-scoped suppressed".
grep -q "^parked-orphan (planned):" < <(printf '%s' "$o1" | surf_join) \
  || fail "(2) the park notification was DROPPED from surfaced (no 'parked-orphan (planned):' marker) — additive means alongside, not instead of, and not gone: $o1"
pass "(2) the planned-park notification is still surfaced (additive), asserted on the marker"

# =====================================================================================
# (3) NEGATIVE CONTROL / SAME-ITEM carve-out — the planned park is bound to the repo's ONLY
#     open item. Reconcile-first: no duplicate execute unit. Green before AND after the fix
#     is NOT acceptable here in the trivial sense: before the fix it passed for the WRONG
#     reason (repo-scoped substitutive suppression), so this case also asserts the surface
#     NAMES the item — which only the item-scoped path produces.
# =====================================================================================
R2="$tmp/sameitem"; mkrepo "$R2"
printf '# Roadmap\n## Items\n- [ ] [ROUTINE] the only item <!-- id:dead -->\n' > "$R2/ROADMAP.md"
printf '# TODO\n## Current\n' > "$R2/TODO.md"
git -C "$R2" add -A; git -C "$R2" commit -qm init
stale_worktree "$R2" sameitem deadrun-execute-dead-0 "executor wip for id:dead"

o2="$("$DR" --repo sameitem --path "$R2" --runid freshrun --live-claims "" --main-branch main 2>/dev/null)"
[[ "$(printf '%s' "$o2" | ncount units)" == "0" ]] \
  || fail "(3) same-item planned park must NOT emit a duplicate execute unit for id:dead (reconcile-first): $o2"
grep -q "id:dead" < <(printf '%s' "$o2" | surf_join) \
  || fail "(3) same-item planned park must surface the ITEM-SCOPED reconcile-first line naming id:dead — a repo-scoped block would not name it: $o2"
pass "(3) planned park bound to the only open item → reconcile-first, item named in the surface"

# =====================================================================================
# (4) LOUDNESS — an in-flight/live-claimed repo (id:ebfb) stays SUBSTITUTIVE (units:[]) but,
#     because it carries actionable work, its surfaced reason must announce the starvation.
# =====================================================================================
R3="$tmp/inflight"; mkrepo "$R3"
printf '# Roadmap\n## Items\n- [ ] [ROUTINE] executable work <!-- id:cccc -->\n' > "$R3/ROADMAP.md"
printf '# TODO\n## Current\n' > "$R3/TODO.md"
git -C "$R3" add -A; git -C "$R3" commit -qm init
mkdir -p "$RELAY_WORKTREE_BASE/inflight/otherrun-wt1"

o3="$("$DR" --repo inflight --path "$R3" --runid freshrun --live-claims "inflight" --main-branch main 2>/dev/null)"
[[ "$(printf '%s' "$o3" | ncount units)" == "0" ]] \
  || fail "(4) in-flight/live-claimed repo must stay substitutive (dc5b collision guard) — units must be 0: $o3"
s3="$(printf '%s' "$o3" | surf_join)"
grep -q "^STARVED (1 actionable item: id:cccc" <<< "$s3" \
  || fail "(4) a repo skipped WHILE carrying actionable work must be LOUD — surfaced reason must start with the STARVED banner naming the count and ids, got: [$s3]"
pass "(4) substitutive block + actionable work → surfaced reason is LOUD (STARVED banner with count + ids)"

# =====================================================================================
# (5) NEGATIVE CONTROL for (4) — same substitutive block, but the repo has NOTHING actionable.
#     It must NOT be labelled STARVED, or the banner becomes noise and stops meaning anything.
# =====================================================================================
R4="$tmp/inflight_idle"; mkrepo "$R4"
printf '# Roadmap\n## Items\n- [x] [ROUTINE] already done <!-- id:eeee -->\n' > "$R4/ROADMAP.md"
printf '# TODO\n## Current\n' > "$R4/TODO.md"
git -C "$R4" add -A; git -C "$R4" commit -qm init
mkdir -p "$RELAY_WORKTREE_BASE/inflight_idle/otherrun-wt1"

o4="$("$DR" --repo inflight_idle --path "$R4" --runid freshrun --live-claims "inflight_idle" --main-branch main 2>/dev/null)"
[[ "$(printf '%s' "$o4" | ncount units)" == "0" ]] \
  || fail "(5) in-flight repo with no actionable work must stay units:[]: $o4"
s4="$(printf '%s' "$o4" | surf_join)"
! grep -q "STARVED" <<< "$s4" \
  || fail "(5) a repo with NO actionable work must not be labelled STARVED (that would make the banner meaningless): [$s4]"
pass "(5) substitutive block with no actionable work is NOT labelled STARVED"

# =====================================================================================
# (6) f0ad(c) — a planned park whose bound item is CLOSED. reconcile-repo.sh:233 sets
#     suppress=false for a closed binding (stale orphan, do not suppress), so the ONLY
#     surface entry produced for this worktree is the "parked-orphan (planned):" line
#     — there is no "suppressed re-dispatch:" line to fall back on. If the additive-surf
#     fold were reverted, this planned park would be read as repo-scoped substitutive
#     suppression and the surfaced list would be EMPTY — a dead run's parked worktree
#     with ZERO operator trace (the 2026-07-28 phantom-park class). This is the state
#     the basename-based case (2) assertion could not distinguish from a healthy repo.
# =====================================================================================
R5="$tmp/closeditem"; mkrepo "$R5"
printf '# Roadmap\n## Items\n- [x] [ROUTINE] already shipped <!-- id:eeee -->\n' > "$R5/ROADMAP.md"
printf '# TODO\n## Current\n' > "$R5/TODO.md"
git -C "$R5" add -A; git -C "$R5" commit -qm init
stale_worktree "$R5" closeditem deadrun-execute-closed-0 "executor wip for id:eeee"

o5="$("$DR" --repo closeditem --path "$R5" --runid freshrun --live-claims "" --main-branch main 2>/dev/null)"
s5="$(printf '%s' "$o5" | surf_join)"
[[ -n "$s5" ]] \
  || fail "(6) a planned park bound to a CLOSED item produced NO surfaced entries at all — the phantom-park class: a dead run's leftover worktree with zero operator trace: $o5"
grep -q "^parked-orphan (planned):" <<< "$s5" \
  || fail "(6) a planned park bound to a CLOSED item must still surface the 'parked-orphan (planned):' marker: [$s5]"
! grep -q "suppressed re-dispatch:" <<< "$s5" \
  || fail "(6) a CLOSED-item binding must NOT ALSO emit 'suppressed re-dispatch:' (that path is for still-open bindings): [$s5]"
pass "(6) planned park bound to a closed item still surfaces the parked-orphan marker (no phantom park)"

echo "ALL PASS: a dead run's leftover worktree no longer starves a repo with actionable work; a skip that still happens is LOUD (id:e7e4)"
