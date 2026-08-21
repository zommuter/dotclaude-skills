#!/usr/bin/env bash
# test_discover_repo_starved_gate_f0ad.sh — id:f0ad(a): discover-repo.sh's e7e4 STARVED
# banner used to gate on `actionable_routine_open > 0` ALONE, with no verdict check, while
# the sibling tool shipped the same day (run-anomaly-scan.sh) gates the identical signal on
# verdict membership in POOL_ACTIONABLE = {execute,review,hard,handoff}. classify-repo.sh
# folds actionable_routine_open in at the TOP LEVEL regardless of verdict (a raw ROADMAP
# scan), so a genuinely diverged repo — blocked by classify-verdict.sh, and substitutive via
# reconcile-repo.sh's own independent diverged detection — got a self-contradicting banner:
#   STARVED (N actionable items …, verdict=blocked) skipped because — diverged … (id:c3f7)
# `diverged` is the MOST COMMON substitutive class, so most production STARVED banners were
# false positives while run-anomaly-scan.sh reported nothing for the same repo. Two tools
# disagreeing about the same anomaly is how a signal stops being read (id:4347).
#
# NO `# roadmap:` HEADER ON PURPOSE — defect-fix test, failures always count.
#
# fails-against: discover-repo.sh gating the STARVED banner on actionable_routine_open alone,
#   pre id:f0ad(a). Verified red: case (1) below (diverged + actionable) produced a banner
#   starting "STARVED (" at that revision.
#
# Hermetic: mktemp -d git fixtures, RELAY_WORKTREE_BASE/RELAY_TOML redirected into the temp
# dir, no network beyond a local bare "origin", no ~/.claude or real-repo access.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DR="$ROOT/relay/scripts/discover-repo.sh"
[[ -x "$DR" ]] || { echo "FAIL: discover-repo.sh not found/executable: $DR"; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export RELAY_WORKTREE_BASE="$tmp/wt"
export RELAY_TOML="$tmp/relay.toml"; : > "$RELAY_TOML"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

surf_join() { python3 -c 'import sys,json; print("|".join(s.get("reason","") for s in json.load(sys.stdin).get("surfaced",[])))'; }
ncount()    { python3 -c 'import sys,json; print(len(json.load(sys.stdin).get(sys.argv[1],[])))' "$1"; }

# =====================================================================================
# (1) THE DEFECT SHAPE — a DIVERGED repo (reconcile-repo.sh's own diverged detection, the
#     same "local +N / origin +N" state classify-verdict.sh independently blocks on) that
#     ALSO carries open [ROUTINE] items. reconcile returns a SUBSTITUTIVE surfaced block
#     (diverged-surface); discover-repo.sh's e7e4 loudness probe then re-classifies the repo
#     and finds verdict=blocked (same diverged fact) + actionable_routine_open>0. The banner
#     must NOT say STARVED — the repo is correctly non-dispatchable, not starved.
# =====================================================================================
origin="$(mktemp -d)"; git -C "$origin" init -q --bare
work="$tmp/diverged"; mkdir -p "$work"; git -C "$work" init -q -b main
git -C "$work" config user.email t@e.st; git -C "$work" config user.name t
printf '# Roadmap\n## Items\n- [ ] [ROUTINE] work a <!-- id:57d1 -->\n- [ ] [ROUTINE] work b <!-- id:6612 -->\n' > "$work/ROADMAP.md"
printf '# TODO\n## Current\n' > "$work/TODO.md"
git -C "$work" add -A; git -C "$work" commit -qm init
git -C "$work" remote add origin "$origin"
git -C "$work" push -q -u origin HEAD:refs/heads/main

c2="$(mktemp -d)"; git clone -q "$origin" "$c2"
git -C "$c2" config user.email t@e.st; git -C "$c2" config user.name t
echo o > "$c2/fo"; git -C "$c2" add fo; git -C "$c2" commit -qm origin-side
git -C "$c2" push -q origin HEAD:refs/heads/main

echo l > "$work/fl"; git -C "$work" add fl; git -C "$work" commit -qm local-side
git -C "$work" fetch -q origin
# work is now diverged: 1 local-only commit, 1 origin-only commit unpulled.

o1="$("$DR" --repo diverged --path "$work" --runid freshrun --live-claims "" --main-branch main 2>/dev/null)"
[[ "$(printf '%s' "$o1" | ncount units)" == "0" ]] \
  || fail "(1) a diverged repo must stay substitutive (units:[]): $o1"
s1="$(printf '%s' "$o1" | surf_join)"
grep -qi "diverged" <<< "$s1" \
  || fail "(1) the surfaced reason must still name the diverged block: [$s1]"
! grep -q "^STARVED (" <<< "$s1" \
  || fail "(1) id:f0ad(a) REGRESSION — a diverged (verdict=blocked) repo with open [ROUTINE] items must NOT be labelled STARVED, even though actionable_routine_open>0: [$s1]"
pass "(1) diverged + actionable-but-blocked repo is NOT labelled STARVED (verdict-gated, id:f0ad(a))"

# =====================================================================================
# (2) NEGATIVE CONTROL for the gate itself — an in-flight/live-claimed repo (verdict stays
#     genuinely pool-actionable, e.g. execute) with actionable work IS still labelled STARVED.
#     This is test_park_starvation_e7e4.sh case (4), re-asserted here so the verdict gate
#     cannot be satisfied by simply muting the banner outright.
# =====================================================================================
R3="$tmp/inflight"; mkdir -p "$R3"; git -C "$R3" init -q -b main
git -C "$R3" config user.email t@e.st; git -C "$R3" config user.name t
printf '# Roadmap\n## Items\n- [ ] [ROUTINE] executable work <!-- id:cccc -->\n' > "$R3/ROADMAP.md"
printf '# TODO\n## Current\n' > "$R3/TODO.md"
git -C "$R3" add -A; git -C "$R3" commit -qm init
mkdir -p "$RELAY_WORKTREE_BASE/inflight/otherrun-wt1"

o3="$("$DR" --repo inflight --path "$R3" --runid freshrun --live-claims "inflight" --main-branch main 2>/dev/null)"
s3="$(printf '%s' "$o3" | surf_join)"
grep -q "^STARVED (1 actionable item: id:cccc" <<< "$s3" \
  || fail "(2) NEGATIVE CONTROL: a live-claimed repo with genuinely pool-actionable (execute) verdict must STILL be labelled STARVED — the gate must not have muted the banner outright: [$s3]"
pass "(2) negative control: a genuinely pool-actionable repo is still labelled STARVED (the gate discriminates, it does not mute)"

echo "ALL PASS: discover-repo.sh's STARVED banner is gated on verdict, matching run-anomaly-scan.sh (id:f0ad(a))"
