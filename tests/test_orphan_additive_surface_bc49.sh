#!/usr/bin/env bash
# roadmap:bc49
# RED SPEC for id:bc49 — "Orphan existence must NEVER block a repo's independent progress".
# Authored by /relay handoff 2026-07-23 (targeted C3); AMENDED 2026-07-23 per the --fabled
# closing-pass amendments A2/A3/A4 (meeting docs/meeting-notes/2026-07-23-1735-relay-orphan-
# existence-never-blocks.md, § "Amendment session — --fabled closing pass", id:7e87).
#
# RATIFIED CONTRACT (D1 + A2/A3/A4):
#   A parked orphan is ADDITIVE SURFACE only — its mere EXISTENCE never suppresses a repo's
#   classify verdict or dispatch. The id:1f53 repo-scoped `surfaced NON-EMPTY → units:[] + STOP`
#   at discover-repo.sh step 1 (twinned in relay-loop.js:1163 CASE-A prompt, the :1172
#   "each repo appears exactly once" invariant, and the schema comment "a surfaced repo is
#   never dispatched") is REMOVED and replaced by item-scoped/additive routing.
#
#   SURFACE-CLASS TABLE (A4-i, SAFETY — the removed block fired on ~5 surface classes; ONLY
#   ONE is additive):
#     • orphan-suppress (reconcile-repo.sh action.kind=="suppress", id:1f53) → ADDITIVE:
#       emit the classify execute unit ALONGSIDE the suppress surface (unless it is the
#       SAME item — see the same-item carve-out below).
#     • in-flight-elsewhere / claimed-by-another-live-run (id:ebfb) → SUBSTITUTIVE (units:[]).
#     • diverged-from-origin (id:c3f7)                             → SUBSTITUTIVE (units:[]).
#     • e3ad fail-closed reap/park REFUSAL (id:e3ad)               → SUBSTITUTIVE (units:[]).
#     • discover-error                                             → SUBSTITUTIVE (units:[]).
#   Rationale for the substitutive four: an executor dispatched into a repo held by another
#   live run is the dc5b cross-run ledger collision; a diverged/refused/errored repo genuinely
#   cannot be worked. Only orphan-suppress fires on SUCCESS + on UNRELATED items, so only it
#   is the false-suppression being removed.
#
#   SAME-ITEM carve-out (D1, the ONLY item-scoped rule): when the parked orphan is bound to the
#   repo's ONLY (or the classify-selected) open item, the repo does NOT emit a duplicate execute
#   unit AND does NOT go units:[] — it RECONCILES that orphan first (auto-integrate-if-safe via
#   id:1048, else surface). At the discover-repo.sh seam the mechanically-testable half is: do
#   NOT emit a duplicate same-item execute unit; surface reconcile-first. (The auto-integrate
#   half is gated on id:1048 — its RED spec is tests/test_bounded_auto_integrate_1048.sh.)
#
#   AMBIGUOUS-BINDING (A3, amends a4e9-D3): an orphan whose commit carries NO bindable id:
#   token is ADDITIVE-SURFACE (NOT repo-suppress, NOT a resurrected existence-keyed block).
#   The failure-keyed guards (id:1432 applyNoWorkSuppression / id:365b >3× breaker) are the
#   ONLY backstop against duplicate work here — no existence/repo-scoped suppression returns.
#
#   ENFORCEMENT (A4-ii): item-scoping must REACH the executor — discover-repo.sh injects an
#   item-scoped "orphan-parked, reconcile-first, do NOT work id:X" note into the emitted
#   unit.reason (the child prompt already relays unit.reason).
#
# SEAM: discover-repo.sh (relay/scripts/discover-repo.sh) — the deterministic per-repo
# composition the live shard runs (CASE B) and the mechanical producer wraps. Fixing its
# ROUTING here fixes the live loop's CASE B path; the relay-loop.js:1163 CASE-A shard-prompt
# routing text + the :1172 "each repo appears exactly once across units+surfaced" invariant +
# the schema comment "a surfaced repo is never dispatched" are the twin surfaces (named in the
# ROADMAP acceptance — all become FALSE under the additive contract).
#
# RED until id:bc49's ROADMAP checkbox is ticked: cases (A) and (E) FAIL on current code
# (units==0 where the additive contract requires units==1).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DR="$ROOT/relay/scripts/discover-repo.sh"
[[ -x "$DR" ]] || { echo "discover-repo.sh not found (RED): $DR"; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export RELAY_WORKTREE_BASE="$tmp/wt"   # per-repo subdirs created only for the cases that need one
export RELAY_TOML="$tmp/relay.toml"; : > "$RELAY_TOML"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }
mkrepo() { local d="$1"; mkdir -p "$d"; git -C "$d" init -q; git -C "$d" config user.email t@e; git -C "$d" config user.name t; git -C "$d" config commit.gpgsign false; }
ncount()   { python3 -c 'import sys,json; print(len(json.load(sys.stdin).get(sys.argv[1],[])))' "$1"; }
uverdict() { python3 -c 'import sys,json; u=json.load(sys.stdin).get("units",[]); print(u[0]["verdict"] if u else "<none>")'; }
ureason()  { python3 -c 'import sys,json; u=json.load(sys.stdin).get("units",[]); print(u[0].get("reason","") if u else "")'; }
surf_join(){ python3 -c 'import sys,json; print("|".join(s.get("reason","") for s in json.load(sys.stdin).get("surfaced",[])))'; }

# ============================================================================================
# (A) ADDITIVE — parked orphan for a DIFFERENT open item must NOT zero out independent work,
#     AND the emitted unit must carry the item-scoped reconcile-first ENFORCEMENT note (A4-ii).
# ============================================================================================
# Repo has an independent open [ROUTINE] id:aaaa (executable) AND an open [ROUTINE] id:bbbb whose
# partial work is parked to relay/orphan/*. Contract: still emit the id:aaaa execute unit; surface
# the id:bbbb suppress line ALONGSIDE it; inject "reconcile-first, do NOT work id:bbbb" into reason.
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
# the orphan notification is preserved (surfaced alongside, carrying the parked item's id)
printf '%s' "$oa" | surf_join | grep -q "id:bbbb" \
  || fail "(A) parked item's suppress line must still be SURFACED (additive notification), reason missing id:bbbb: $oa"
# ENFORCEMENT (A4-ii): item-scoping reaches the executor via unit.reason
printf '%s' "$oa" | ureason | grep -q "id:bbbb" \
  || fail "(A/A4-ii) emitted unit.reason must NAME the parked item (id:bbbb) for item-scoped executor guidance: reason=[$(printf '%s' "$oa" | ureason)]"
printf '%s' "$oa" | ureason | grep -qi "reconcile" \
  || fail "(A/A4-ii) emitted unit.reason must carry the 'reconcile-first, do NOT work id:X' note: reason=[$(printf '%s' "$oa" | ureason)]"
pass "(A) different-item orphan is ADDITIVE — execute unit emitted + suppress surfaced + reconcile-first note injected into unit.reason"

# ============================================================================================
# (B) SUBSTITUTIVE — a genuine REPO-LEVEL block (diverged) stays units:[] (already correct today;
#     triangulates so the (A) fix cannot be "always classify regardless of surfaced").
# ============================================================================================
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
pass "(B) diverged (repo-level) surface stays substitutive — units:[]"

# ============================================================================================
# (C) SUBSTITUTIVE (A4-i SAFETY) — an in-flight / live-claimed repo stays units:[] EVEN WITH an
#     executable open item. Guards the dc5b cross-run collision: the additive fix must NOT make
#     in-flight-elsewhere additive (that would dispatch into a repo another live run holds).
# ============================================================================================
RC="$tmp/r_inflight"; mkrepo "$RC"
printf '# Roadmap\n## Items\n- [ ] [ROUTINE] executable work <!-- id:cccc -->\n' > "$RC/ROADMAP.md"
printf '# TODO\n## Current\n' > "$RC/TODO.md"
git -C "$RC" add -A; git -C "$RC" commit -qm init
# a live executor worktree for THIS repo held by another run: reconcile surfaces id:ebfb when
# the repo name is in --live-claims (it surfaces BEFORE any reap/park, reconcile-repo.sh:161).
mkdir -p "$RELAY_WORKTREE_BASE/r_inflight/otherrun-wt1"
oc="$("$DR" --repo r_inflight --path "$RC" --runid myrun123 --live-claims "r_inflight" --main-branch main)"
[[ "$(printf '%s' "$oc" | ncount units)" == "0" ]] \
  || fail "(C) in-flight/live-claimed repo must stay SUBSTITUTIVE (dc5b collision guard) — units must be 0 despite an executable item: $oc"
printf '%s' "$oc" | surf_join | grep -qi "in-flight" \
  || fail "(C) in-flight repo must surface the in-flight-elsewhere reason: $oc"
pass "(C) in-flight/live-claimed repo stays substitutive — units:[] (dc5b cross-run collision guard)"

# ============================================================================================
# (D) SAME-ITEM carve-out (D1) — the parked orphan is bound to the repo's ONLY open item.
#     Do NOT emit a duplicate execute unit for that same item; surface reconcile-first.
#     (Auto-integrate-if-safe half is gated on id:1048 — see test_bounded_auto_integrate_1048.sh.)
# ============================================================================================
RD="$tmp/r_same"; mkrepo "$RD"
printf '# Roadmap\n## Items\n- [ ] [ROUTINE] the only item <!-- id:dddd -->\n' > "$RD/ROADMAP.md"
printf '# TODO\n## Current\n' > "$RD/TODO.md"
git -C "$RD" add -A; git -C "$RD" commit -qm init
git -C "$RD" branch "relay/orphan/deadrun-dddd" HEAD
echo partial > "$RD/wip.txt"; git -C "$RD" add wip.txt; git -C "$RD" commit -qm "executor wip for id:dddd" >/dev/null
git -C "$RD" branch -f "relay/orphan/deadrun-dddd" HEAD
git -C "$RD" reset -q --hard HEAD~1
od="$("$DR" --repo r_same --path "$RD" --runid myrun123 --live-claims "" --main-branch main)"
[[ "$(printf '%s' "$od" | ncount units)" == "0" ]] \
  || fail "(D) same-item orphan must NOT emit a duplicate execute unit for id:dddd — units must be 0 (reconcile-first): $od"
printf '%s' "$od" | surf_join | grep -q "id:dddd" \
  || fail "(D) same-item repo must surface the reconcile-first suppress line naming id:dddd: $od"
pass "(D) same-item-only orphan → reconcile-first, no duplicate execute unit (integrate half gated on id:1048)"

# ============================================================================================
# (E) AMBIGUOUS-BINDING (A3) — an orphan whose commit carries NO bindable id: token is
#     ADDITIVE-SURFACE (NOT repo-suppress). The repo's independent executable item still
#     dispatches; the ambiguous orphan is surfaced alongside. Failure-keyed guards (id:1432/
#     id:365b) are the only backstop — no existence/repo-scoped suppression is resurrected.
# ============================================================================================
RE="$tmp/r_ambig"; mkrepo "$RE"
printf '# Roadmap\n## Items\n- [ ] [ROUTINE] executable work <!-- id:eeee -->\n' > "$RE/ROADMAP.md"
printf '# TODO\n## Current\n' > "$RE/TODO.md"
git -C "$RE" add -A; git -C "$RE" commit -qm init
git -C "$RE" branch "relay/orphan/deadrun-noid" HEAD
echo partial > "$RE/wip.txt"; git -C "$RE" add wip.txt; git -C "$RE" commit -qm "executor wip no binding" >/dev/null  # NO id: token
git -C "$RE" branch -f "relay/orphan/deadrun-noid" HEAD
git -C "$RE" reset -q --hard HEAD~1
oe="$("$DR" --repo r_ambig --path "$RE" --runid myrun123 --live-claims "" --main-branch main)"
[[ "$(printf '%s' "$oe" | ncount units)" == "1" ]] \
  || fail "(E) ambiguous-binding orphan must be ADDITIVE (A3) — the independent execute unit is still expected, got units=$(printf '%s' "$oe" | ncount units): $oe"
[[ "$(printf '%s' "$oe" | uverdict)" == "execute" ]] \
  || fail "(E) surviving unit verdict != execute: $oe"
printf '%s' "$oe" | surf_join | grep -qi "ambiguous" \
  || fail "(E) ambiguous orphan must still be SURFACED (additive) with its no-binding reason: $oe"
pass "(E) ambiguous-binding orphan is ADDITIVE — execute unit still emitted + surfaced (A3)"

echo "ALL PASS: orphan existence never blocks — only orphan-suppress is additive; in-flight/diverged/refuse/error stay substitutive; same-item→reconcile-first; ambiguous→additive (id:bc49)"
