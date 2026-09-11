#!/usr/bin/env bash
# Defect-fix test (no roadmap item -- deliberately no `# roadmap:` header, so its failures
# always count).
#
# id:790d -- discover-repo.sh's SAME-ITEM carve-out (D1) must decide "is every actionable
# [ROUTINE] item bound to a suppressed orphan?" using the STRICT classifier predicate, not a
# re-derived loose line scan.
#
# THE DEFECT, as measured on code.lawless in pool run relay-20260910-234645-16942:
#   The carve-out carried a FOURTH copy of the "which [ROUTINE] items count" predicate, inline
#   in its python block:
#       re.match(r"^\s*- \[ \]", line) and "[ROUTINE]" in line
#           and "@manual" not in line and "@container" not in line
#   It knew nothing about the strict classifier exclusions -- a leading construction-sign
#   marker, "BLOCKED on", @owner-verify and the other HUMAN_GATES, the SURFACED marker, an
#   unsatisfied typed gated-on: edge, parked/exempt ROADMAP sections. On code.lawless it
#   yielded {5ab8, a736, e4a1} where classify-repo.sh yielded exactly ['a736'].
#   {5ab8,a736,e4a1} minus the suppressed {a736,f272} is NON-EMPTY, so the carve-out DECLINED
#   to drop the unit. The unit dispatched with actionable_routine_ids=['a736'] and
#   suppressed_item_ids=['a736','f272'], i.e. a permitted set (namedItemsFor) of NOTHING, and
#   the child correctly refused: 2 of that run's 7 id:c076 empty-permitted-set handbacks.
#
# THE CONTRACT: the carve-out compares suppressed_ids against the unit's OWN
# actionable_routine_ids (id:b09e), which classify-repo.sh already computed with the strict
# predicate. One predicate, one answer -- the carve-out and relay-loop.js's namedItemsFor()
# now agree BY CONSTRUCTION about which ids a child could be offered.
#
# Fail-open is preserved: no ids at all (empty/absent list) keeps the unit.
#
# NEGATIVE CASE: re-widen routine_open by exactly the two ids the removed loose line scan
# wrongly admitted on code.lawless (5ab8, blocked; e4a1, @owner-verify). That is a minimal,
# faithful model of the defect: the carve-out then sees a non-empty free set and declines to
# drop a unit whose whole permitted set is suppressed. Cases (B) and (C) stay green under it
# (both already have a free id), so the declared assertion below is the ONLY line that fires.
# fails-against-mutation: sed -i 's#enumerate(unit.get("actionable_routine_ids") or \[\])#enumerate((unit.get("actionable_routine_ids") or []) + ["5ab8", "e4a1"])#' relay/scripts/discover-repo.sh
# fails-against-assertion: (A) LOOSE-PREDICATE DEFECT
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DR="$ROOT/relay/scripts/discover-repo.sh"
CL="$ROOT/relay/scripts/classify-repo.sh"
[[ -x "$DR" ]] || { echo "FAIL: discover-repo.sh not found: $DR"; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"; mkdir -p "$HOME"
export RELAY_WORKTREE_BASE="$tmp/wt"
export RELAY_TOML="$tmp/relay.toml"; : > "$RELAY_TOML"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }
mkrepo() { local d="$1"; mkdir -p "$d"; git -C "$d" init -q; git -C "$d" config user.email t@e; git -C "$d" config user.name t; git -C "$d" config commit.gpgsign false; }
ncount() { python3 -c 'import sys,json; print(len(json.load(sys.stdin).get(sys.argv[1],[])))' "$1"; }
aids()   { python3 -c 'import sys,json; u=json.load(sys.stdin).get("units",[]); print(",".join(u[0].get("actionable_routine_ids",[])) if u else "<none>")'; }
surf_join(){ python3 -c 'import sys,json; print("|".join(s.get("reason","") for s in json.load(sys.stdin).get("surfaced",[])))'; }

# Park a commit for <id> onto relay/orphan/* so reconcile-repo.sh binds and suppresses it.
park_orphan() {
  local d="$1" id="$2" nonce="$3"
  git -C "$d" branch "relay/orphan/deadrun-$id" HEAD
  echo "partial-$nonce" > "$d/wip-$nonce.txt"
  git -C "$d" add "wip-$nonce.txt"
  git -C "$d" commit -qm "executor wip for id:$id" >/dev/null
  git -C "$d" branch -f "relay/orphan/deadrun-$id" HEAD
  git -C "$d" reset -q --hard HEAD~1
}

# ============================================================================================
# (A) THE code.lawless SHAPE. Three open [ROUTINE] lines; only ONE is strictly actionable.
#     Both orphans are bound (a736 = the actionable one, f272 = an item not even in ROADMAP).
#     Contract: routine_open == {a736}; {a736} - {a736,f272} == {} => DROP the unit.
#     Under the loose scan routine_open was {5ab8,a736,e4a1}, which minus the suppressed set
#     is {5ab8,e4a1} -- non-empty -- so the unit survived with a permitted set of nothing.
# ============================================================================================
RA="$tmp/r_lawless"; mkrepo "$RA"
{
  printf '# Roadmap\n## Items\n'
  printf -- '- [ ] 🚧 [ROUTINE] blocked work <!-- id:5ab8 -->\n'
  printf -- '- [ ] [ROUTINE] the one actionable item <!-- id:a736 -->\n'
  printf -- '- [ ] [ROUTINE] @owner-verify needs the owner on a device <!-- id:e4a1 -->\n'
} > "$RA/ROADMAP.md"
printf '# TODO\n## Current\n' > "$RA/TODO.md"
git -C "$RA" add -A; git -C "$RA" commit -qm init

# CALIBRATION, run before the assertion that depends on it: prove the STRICT classifier really
# yields exactly a736 on this fixture. If this probe came back with all three (or with none),
# the fixture would not model the defect at all and case (A) below would be vacuous.
strict="$("$CL" --emit unit --repo r_lawless --path "$RA" \
  | python3 -c 'import sys,json; print(",".join(json.load(sys.stdin).get("actionable_routine_ids",[])))')"
[[ "$strict" == "a736" ]] \
  || fail "(A) FIXTURE CALIBRATION: classify-repo.sh must see exactly a736 as actionable on this ROADMAP, got [$strict]. The fixture no longer models the loose-vs-strict gap, so case (A) would be vacuous. Fix the fixture, not the assertion."
pass "(A) fixture calibration: the STRICT classifier sees exactly {a736} where a loose line scan sees {5ab8,a736,e4a1}"

park_orphan "$RA" a736 one
park_orphan "$RA" f272 two

oa="$("$DR" --repo r_lawless --path "$RA" --runid myrun790d --live-claims "" --main-branch main)"
grep -q "id:a736" < <(printf '%s' "$oa" | surf_join) \
  || fail "(A) FIXTURE CALIBRATION: reconcile must have SUPPRESSED id:a736 (no suppress surface means the carve-out was never reached and this case is vacuous): $oa"
[[ "$(printf '%s' "$oa" | ncount units)" == "0" ]] \
  || fail "(A) LOOSE-PREDICATE DEFECT: the repo's ONLY strictly-actionable item (a736) is orphan-suppressed, so the SAME-ITEM carve-out must drop the execute unit (units=0, reconcile-first). Got units=$(printf '%s' "$oa" | ncount units) with actionable_routine_ids=[$(printf '%s' "$oa" | aids)] -- a unit whose entire permitted set is subtracted away, which dispatches into the id:c076 empty-permitted-set handback. The carve-out must read the unit's own actionable_routine_ids, never re-derive them by line scan: $oa"
pass "(A) same-item carve-out uses the STRICT classifier set -- blocked/owner-verify siblings no longer keep a fully-suppressed execute unit alive"

# ============================================================================================
# (B) TRIANGULATION -- a genuinely FREE actionable item must still dispatch. Guards against
#     "fix" by always dropping the unit whenever anything is suppressed.
# ============================================================================================
RB="$tmp/r_free"; mkrepo "$RB"
{
  printf '# Roadmap\n## Items\n'
  printf -- '- [ ] 🚧 [ROUTINE] blocked work <!-- id:5ab8 -->\n'
  printf -- '- [ ] [ROUTINE] parked work <!-- id:a736 -->\n'
  printf -- '- [ ] [ROUTINE] genuinely free work <!-- id:b111 -->\n'
} > "$RB/ROADMAP.md"
printf '# TODO\n## Current\n' > "$RB/TODO.md"
git -C "$RB" add -A; git -C "$RB" commit -qm init
park_orphan "$RB" a736 one

ob="$("$DR" --repo r_free --path "$RB" --runid myrun790d --live-claims "" --main-branch main)"
[[ "$(printf '%s' "$ob" | ncount units)" == "1" ]] \
  || fail "(B) a FREE actionable item (b111) must still dispatch alongside the suppress surface (additive, id:bc49 D1) -- got units=$(printf '%s' "$ob" | ncount units): $ob"
[[ "$(printf '%s' "$ob" | aids)" == "a736,b111" ]] \
  || fail "(B) actionable_routine_ids must stay UNFILTERED (the id:b09e count<->list invariant; suppression is a dispatch concern) -- expected 'a736,b111', got [$(printf '%s' "$ob" | aids)]: $ob"
pass "(B) a free actionable item still dispatches; actionable_routine_ids stays unfiltered"

# ============================================================================================
# (C) FAIL-OPEN -- an actionable item that carries NO id contributes an EMPTY-STRING placeholder
#     to actionable_routine_ids. It is unnameable, so it can never be PROVEN same-item; the
#     carve-out must keep the unit rather than wrong-suppress it.
# ============================================================================================
RC="$tmp/r_noid"; mkrepo "$RC"
{
  printf '# Roadmap\n## Items\n'
  printf -- '- [ ] [ROUTINE] parked work <!-- id:a736 -->\n'
  printf -- '- [ ] [ROUTINE] actionable work with no id token at all\n'
} > "$RC/ROADMAP.md"
printf '# TODO\n## Current\n' > "$RC/TODO.md"
git -C "$RC" add -A; git -C "$RC" commit -qm init
park_orphan "$RC" a736 one

oc="$("$DR" --repo r_noid --path "$RC" --runid myrun790d --live-claims "" --main-branch main)"
[[ "$(printf '%s' "$oc" | ncount units)" == "1" ]] \
  || fail "(C) FAIL-OPEN: an unnameable actionable item cannot be proven same-item, so the carve-out must KEEP the unit (never wrong-suppress) -- got units=$(printf '%s' "$oc" | ncount units): $oc"
pass "(C) fail-open preserved: an id-less actionable item keeps the unit"

# ============================================================================================
# (D) NO FOURTH COPY -- the loose line scan must be GONE from discover-repo.sh, and the dead
#     ROADMAP_PATH plumbing with it (a dead env var is what a fifth copy would grow against).
# ============================================================================================
grep -q 'routine_open = set(' "$DR" \
  || fail "(D) discover-repo.sh no longer builds routine_open at all -- the carve-out input vanished: $DR"
grep -q 'actionable_routine_ids' "$DR" \
  || fail "(D) discover-repo.sh's carve-out must READ the classifier's actionable_routine_ids (id:b09e), not re-derive a set: $DR"
if grep -q 'ROADMAP_PATH' "$DR"; then
  grep -q 'ROADMAP_PATH used to be read here' "$DR" \
    || fail "(D) ROADMAP_PATH is still plumbed into discover-repo.sh's fold block. The re-derivation it fed is gone; a live path env var there is an invitation to grow a FIFTH copy of the predicate against it: $DR"
fi
if grep -q '^roadmap_path = ' "$DR"; then
  fail "(D) the fold block still reads roadmap_path -- the loose re-derivation (or a successor to it) is back: $DR"
fi
pass "(D) the fourth predicate copy is gone; the carve-out reads the classifier's own id list"

echo "ALL PASS: SAME-ITEM carve-out decides on the STRICT classifier predicate, one copy (id:790d)"
