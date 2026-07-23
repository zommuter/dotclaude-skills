#!/usr/bin/env bash
# roadmap:bc49
# RED SPEC for id:bc49 — "Discovery shard suppresses a clean-verdict repo when it is
# orphan-heavy". Authored by /relay handoff 2026-07-23 (targeted C3).
#
# RATIFIED CONTRACT (2026-06-16 meeting docs/meeting-notes/2026-06-16-0938-relay-orphan-reconcile.md,
# D3 / child id:1f53): suppress-redispatch is ITEM-scoped — "suppress fresh dispatch of the
# still-open ITEM that has parked partial work + surface one line". The implementation
# over-reached to REPO-scoped: discover-repo.sh step 1 returns {units:[]} for the WHOLE repo the
# moment reconcile's `surfaced` array is non-empty (relay-loop.js:1163 mirrors this in the shard
# prompt: "surfaced NON-EMPTY → emit units:[] and STOP"). Observed twice on 2026-07-23 (loderite
# AM, dotclaude-skills PM): a single parked orphan for ONE item collateral-blocked every
# independent open ROUTINE unit in the repo, so the repo vanished from dispatch entirely.
#
# THE CONTRACT THIS PINS (user directive 2026-07-23: "notify the orchestrator of reconcile-needed,
# but that must NOT stop independent work"):
#   Orphan-suppress surfacing is ADDITIVE, never a SUBSTITUTE. Given a repo whose classify verdict
#   is executable (ambiguous:false, an open [ROUTINE]) AND a parked relay/orphan/* branch bound to
#   a DIFFERENT still-open item, discover-repo.sh must STILL emit the classify execute unit; the
#   parked item's suppress line is surfaced ALONGSIDE it (the orchestrator is still notified), NOT
#   in place of it.
#   BUT a genuine REPO-LEVEL surface (diverged-from-origin — the whole repo cannot be worked) stays
#   SUBSTITUTIVE: units:[] is correct there. (Triangulation, id:108e: forces the implementer to
#   DISCRIMINATE orphan-suppress from repo-blocking surfaces, not just "ignore surfaced".)
#
# SEAM: discover-repo.sh (relay/scripts/discover-repo.sh) — the deterministic per-repo composition
# the live shard runs (CASE B) and the mechanical producer wraps. Fixing its ROUTING here fixes the
# live loop's CASE B path; the relay-loop.js:1163 CASE A shard-prompt routing text is the twin
# surface (noted in the handoff report — its fix mirrors this one).
#
# RED until id:bc49's ROADMAP checkbox is ticked: assertion (A) FAILS on current code (units==0).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DR="$ROOT/relay/scripts/discover-repo.sh"
[[ -x "$DR" ]] || { echo "discover-repo.sh not found (RED): $DR"; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export RELAY_WORKTREE_BASE="$tmp/wt"   # empty ⇒ reconcile's worktree reap/park block is skipped
export RELAY_TOML="$tmp/relay.toml"; : > "$RELAY_TOML"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }
mkrepo() { local d="$1"; mkdir -p "$d"; git -C "$d" init -q; git -C "$d" config user.email t@e; git -C "$d" config user.name t; git -C "$d" config commit.gpgsign false; }
ncount()   { python3 -c 'import sys,json; print(len(json.load(sys.stdin).get(sys.argv[1],[])))' "$1"; }
uverdict() { python3 -c 'import sys,json; u=json.load(sys.stdin).get("units",[]); print(u[0]["verdict"] if u else "<none>")'; }
surf_join(){ python3 -c 'import sys,json; print("|".join(s.get("reason","") for s in json.load(sys.stdin).get("surfaced",[])))'; }

# === (A) additive: parked orphan for a DIFFERENT open item must NOT zero out independent work ===
# Repo has an independent open [ROUTINE] id:aaaa (executable) AND an open [ROUTINE] id:bbbb whose
# partial work is parked to relay/orphan/*. Contract: still emit the execute unit; surface the
# id:bbbb suppress line alongside it.
RA="$tmp/r_orphan_heavy"; mkrepo "$RA"
printf '# Roadmap\n## Items\n- [ ] [ROUTINE] independent work <!-- id:aaaa -->\n- [ ] [ROUTINE] parked work <!-- id:bbbb -->\n' > "$RA/ROADMAP.md"
printf '# TODO\n## Current\n' > "$RA/TODO.md"
git -C "$RA" add -A; git -C "$RA" commit -qm "add roadmap"
# park partial work for id:bbbb onto relay/orphan/* (commit MESSAGE carries the id binding —
# reconcile-repo.sh binds via `git show --stat`, which surfaces the message, id:1f53)
git -C "$RA" branch "relay/orphan/deadrun-bbbb" HEAD
echo partial > "$RA/wip.txt"; git -C "$RA" add wip.txt; git -C "$RA" commit -qm "executor wip for id:bbbb" >/dev/null
git -C "$RA" branch -f "relay/orphan/deadrun-bbbb" HEAD
git -C "$RA" reset -q --hard HEAD~1   # main drops the wip; it lives only on the orphan ref

oa="$("$DR" --repo r_orphan_heavy --path "$RA" --runid myrun123 --live-claims "" --main-branch main)"
[[ "$(printf '%s' "$oa" | ncount units)" == "1" ]] \
  || fail "(A) orphan-suppress must be ADDITIVE: the independent execute unit is still expected, got units=$(printf '%s' "$oa" | ncount units): $oa"
[[ "$(printf '%s' "$oa" | uverdict)" == "execute" ]] \
  || fail "(A) surviving unit verdict != execute: $oa"
# and the orphan notification is preserved (surfaced alongside, carrying the parked item's id)
printf '%s' "$oa" | surf_join | grep -q "id:bbbb" \
  || fail "(A) parked item's suppress line must still be SURFACED (additive notification), reason missing id:bbbb: $oa"
pass "(A) parked orphan for a DIFFERENT open item is additive — execute unit still emitted + suppress surfaced"

# === (B) TRIANGULATION: a genuine REPO-LEVEL block (diverged) stays SUBSTITUTIVE (units:[]) =====
# This case is already correct today; it is here so the fix for (A) cannot be "always classify
# regardless of surfaced" — a diverged repo genuinely cannot be worked, so units:[] is right.
origin="$(mktemp -d)"; git -C "$origin" init -q --bare
RB="$tmp/r_div"; mkrepo "$RB"
printf '# Roadmap\n## Items\n- [ ] [ROUTINE] do it <!-- id:2222 -->\n' > "$RB/ROADMAP.md"
printf '# TODO\n## Current\n' > "$RB/TODO.md"
git -C "$RB" add -A; git -C "$RB" commit -qm init
git -C "$RB" remote add origin "$origin"; git -C "$RB" push -q -u origin HEAD:refs/heads/main
c2="$(mktemp -d)"; git clone -q "$origin" "$c2"; git -C "$c2" config user.email t@e; git -C "$c2" config user.name t
echo o > "$c2/fo"; git -C "$c2" add fo; git -C "$c2" commit -qm oside; git -C "$c2" push -q origin HEAD:refs/heads/main
echo l > "$RB/fl"; git -C "$RB" add fl; git -C "$RB" commit -qm lside; git -C "$RB" fetch -q origin
ob="$("$DR" --repo r_div --path "$RB" --runid myrun123 --live-claims "" --main-branch main)"
[[ "$(printf '%s' "$ob" | ncount units)" == "0" ]] \
  || fail "(B) a diverged (repo-level) surface must stay SUBSTITUTIVE — units must be 0: $ob"
printf '%s' "$ob" | surf_join | grep -qi diverged \
  || fail "(B) diverged repo must surface the diverged reason: $ob"
pass "(B) diverged (repo-level) surface stays substitutive — units:[] (discrimination triangulation)"

echo "ALL PASS: orphan-suppress is item-scoped/additive; repo-level surfaces stay substitutive (id:bc49)"
