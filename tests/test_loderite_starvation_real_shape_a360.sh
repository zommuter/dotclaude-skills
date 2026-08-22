#!/usr/bin/env bash
# test_loderite_starvation_real_shape_a360.sh — the loderite starvation reproduced
# END-TO-END, in the shape it actually had.
#
# NO `# roadmap:` HEADER ON PURPOSE. id:a360 lives in TODO.md, not ROADMAP.md, so a
# `# roadmap:a360` header is inert today (run-tests.sh looks the checkbox up in ROADMAP.md)
# and would become a silent EXPECTED-RED mask the day a360 were promoted (hazard filed as
# id:915b). Defect-fix test ⇒ no header ⇒ its failures always count.
#
# WHY THIS FILE EXISTS ALONGSIDE THE TWO UNIT SPECS
#   tests/test_orphan_item_binding_branch_name.sh  — reconcile-repo.sh's binding, in isolation
#   tests/test_dd7d_item_scoped_skip_a360.sh       — relay-loop.js's dd7d gate, with a FAKE scanner
# Both pass. Neither reproduces the incident: the first models a MILDER variant. It puts f272
# nowhere in the fixture's ledger, so pre-fix the binding landed in the "item not in ROADMAP —
# ambiguous" branch and still produced a suppress entry — a WRONG-ID suppression. That is not
# what happened. In the real loderite repo `f272` occurs EXACTLY ONCE, as prose inside a
# DIFFERENT item's archived, TICKED body (ROADMAP.archive.md:8056, id:0295: "… parked
# force-free as `relay/orphan/…` (id:f272 commit-and-park) …"). reconcile-repo.sh greps a BARE
# `id:$oid` substring, not the anchored `<!-- id:XXXX -->` marker, so the mis-derived f272
# matched a `- [x]` line and took the *closed ⇒ stale orphan ⇒ do NOT suppress* branch.
# The measured pre-fix result was therefore suppressed_item_ids = {d050} — id:57d1 produced NO
# SUPPRESS ENTRY AT ALL, not a wrong one. This file encodes that exact shape and drives the
# whole chain the incident ran through:
#
#   reconcile-repo.sh (binding)  →  discover-repo.sh (suppressed_item_ids + the unit)
#     →  relay-loop.js namedItemsFor/dispatchItemFor (b09e selection)
#     →  the id:dd7d pre-dispatch gate, driven by the REAL stranded-branch-scan.sh
#
# THE GREEN CONDITION IS "THE REPO CAN PROCEED", NOT "THE BINDING CHANGED". Asserting that the
# suppress set grew would go green without loderite being able to work anything, so case (2)
# below asserts the dispatched id is one of the FIVE UNENCUMBERED items AND that the real
# scanner reports it clean. Case (4) is the negative control: an all-stranded repo must still
# refuse — without it this file would also pass against an implementation that just dispatches
# something regardless.
#
# fails-against: 250cb02 (the commit before the a360 merge bb83364). Observed RED there:
#   FAIL: (1) pre-fix binding shape not reproduced ... suppressed=[d050]  ← case (1) inverted
#   FAIL: (2) the repo was ABORTED with a repo-level handback instead of dispatching a clean
#          item — this IS the starvation (handbacks: id:dd7d stranded branch(es) already carry
#          committed work for loderite item 57d1 …)
#
# FIXTURE PROVENANCE: branch names, the residue commit message, the d050 commit message, the
# six actionable ids and their ROADMAP file order are the real recorded values from loderite
# run relay-20260822-102233-32252. Only the item titles and the archived body's wording are
# abridged.
#
# Hermetic: two mktemp -d git fixtures; RELAY_WORKTREE_BASE + RELAY_TOML redirected into the
# temp dir; no ~/.claude, no real relay.toml, no real loderite checkout, no network.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DR="$ROOT/relay/scripts/discover-repo.sh"
SCAN="$ROOT/relay/scripts/stranded-branch-scan.sh"
LOOP="$ROOT/relay/scripts/relay-loop.js"

fail=0
note() { echo "FAIL: $*" >&2; fail=1; }

[[ -x "$DR" ]]   || { echo "FAIL: discover-repo.sh not found/executable at $DR" >&2; exit 1; }
[[ -x "$SCAN" ]] || { echo "FAIL: stranded-branch-scan.sh not found/executable at $SCAN" >&2; exit 1; }
[[ -f "$LOOP" ]] || { echo "FAIL: relay-loop.js not found at $LOOP" >&2; exit 1; }
command -v node >/dev/null 2>&1 || { echo "FAIL: node not available (this spec needs it)" >&2; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export RELAY_WORKTREE_BASE="$tmp/wt"; mkdir -p "$RELAY_WORKTREE_BASE"
export RELAY_TOML="$tmp/relay.toml"; : > "$RELAY_TOML"

# The six actionable [ROUTINE] ids in ROADMAP FILE ORDER, with the stranded one FIRST — that
# ordering is what made dispatchItemFor (namedItemsFor(unit)[0]) select it every single round.
IDS=(57d1 6612 084f c8a7 55a4 5adb)

# ── fixture builder ────────────────────────────────────────────────────────────────────────
# $1 = repo path; $2 = "one" (only 57d1 parked, plus the repo-scoped orphan) | "all" (every
# actionable item parked).
build_repo() {
  local repo="$1" mode="$2" id
  mkdir -p "$repo"
  git -C "$repo" init -q -b main
  git -C "$repo" config user.email t@e.st
  git -C "$repo" config user.name t
  git -C "$repo" config commit.gpgsign false
  {
    printf '# Roadmap\n\n## Items\n'
    printf -- '- [ ] [ROUTINE] editor-core share plumbing <!-- id:57d1 -->\n'
    printf -- '- [ ] [ROUTINE] second actionable item <!-- id:6612 -->\n'
    printf -- '- [ ] [ROUTINE] third actionable item <!-- id:084f -->\n'
    printf -- '- [ ] [ROUTINE] fourth actionable item <!-- id:c8a7 -->\n'
    printf -- '- [ ] [ROUTINE] fifth actionable item <!-- id:55a4 -->\n'
    printf -- '- [ ] [ROUTINE] sixth actionable item <!-- id:5adb -->\n'
  } > "$repo/ROADMAP.md"
  # THE LOAD-BEARING FIXTURE DETAIL: `f272` exists in this repo ONLY as prose inside a
  # DIFFERENT item's archived, TICKED body. reconcile-repo.sh's bare-substring grep matches
  # this `- [x]` line, so a mis-derived oid=f272 lands on "closed ⇒ stale orphan ⇒ do NOT
  # suppress" and emits NOTHING. (loderite ROADMAP.archive.md:8056, id:0295.)
  printf '# Roadmap archive\n\n- [x] [HARD] **Wire `src/share-url.ts` into the app** <!-- id:0295 --> **CLOSED 2026-08-10 (relay HARD).** Prior partial work was committed and parked force-free as `relay/orphan/relay-20260810-111908-1745-execute` (id:f272 commit-and-park) and carries ~307 lines of REAL work toward this item.\n' \
    > "$repo/ROADMAP.archive.md"
  printf '# TODO\n\n## Current\n' > "$repo/TODO.md"
  git -C "$repo" add -A
  git -C "$repo" commit -qm init

  if [[ "$mode" == one ]]; then
    # (a) the commit-and-park RESIDUE orphan for item 57d1 — verbatim observed message. Its
    #     ONLY id: token is f272, the PARKING MECHANISM's id; 57d1 lives in the branch name.
    git -C "$repo" checkout -q -b "relay/orphan/relay-20260820-180056-4594-execute-57d1-0"
    echo residue > "$repo/src-editor-core.ts"; git -C "$repo" add -A
    git -C "$repo" commit -qm "chore(relay): WIP UNVERIFIED residue auto-commit for worktree relay-20260820-180056-4594-execute-57d1-0 (id:f272 commit-and-park; do not treat as reviewed)"
    git -C "$repo" checkout -q main
    # (b) the REPO-SCOPED orphan — its name encodes NO item ('repo'), so it can ONLY bind via
    #     the commit message. This fallback is load-bearing, not defensive.
    git -C "$repo" checkout -q -b "relay/orphan/relay-20260820-180056-4594-execute-repo-0"
    echo driver > "$repo/tools-driver.ts"; git -C "$repo" add -A
    git -C "$repo" commit -qm "feat(tools): headless-Chromium PWABuilder report-card driver (id:d050)"
    git -C "$repo" checkout -q main
  else
    for id in "${IDS[@]}"; do
      git -C "$repo" checkout -q -b "relay/orphan/relay-20260820-180056-4594-execute-$id-0"
      echo "residue-$id" > "$repo/wip-$id.ts"; git -C "$repo" add -A
      git -C "$repo" commit -qm "chore(relay): WIP UNVERIFIED residue auto-commit for worktree relay-20260820-180056-4594-execute-$id-0 (id:f272 commit-and-park; do not treat as reviewed)"
      git -C "$repo" checkout -q main
    done
  fi
}

# ── the node driver: real relay-loop.js selection + the real dd7d dispatch region ──────────
# relay-loop.js is a Workflow module that cannot be imported hermetically (id:2ec4), so — as
# tests/test_dd7d_item_scoped_skip_a360.sh does — the real helpers and the real dispatch-path
# region are EXTRACTED and evaluated against stubbed I/O. The extraction works against BOTH the
# pre-fix and post-fix layouts, which is what makes this file a genuine negative control.
# UNLIKE that spec, the stranded scanner here is NOT faked: it shells out to the shipped
# stranded-branch-scan.sh against the real git fixture, so the two halves of the incident (the
# reconcile binding and the dd7d branch-name key) are exercised over the SAME repo.
{
  awk '/^const namedItemsFor = /,/^\}/'                "$LOOP"
  awk '/^const dispatchItemFor = /{print}'             "$LOOP"
  awk '/^const strandedIdsOf = /{print}'               "$LOOP"
  awk '/^async function strandedDispatchGate\(/,/^\}/' "$LOOP"
  awk '/^const strandedDispatchReason = /,/^\}/'       "$LOOP"
} > "$tmp/helpers.js"

awk '/pre-dispatch stranded-branch guard \(b\)/{f=1} /id:34b7 . the parent creates/{f=0} f' \
  "$LOOP" > "$tmp/region.js"
[[ -s "$tmp/region.js" ]] \
  || note "could not extract the dd7d dispatch-path region from relay-loop.js (markers moved?)"
grep -q 'strandedBranchesFor' "$tmp/region.js" \
  || note "the extracted region does not consult strandedBranchesFor — the dd7d guard is not in it"

cat > "$tmp/drive.js" <<'JS'
const { execFileSync } = require('child_process')
const fs = require('fs')
const SCAN = process.env.SCAN_BIN
const unit = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))

let state = { handbacks: [], inFlight: [] }
const events = []
const logs = []
const emittedHandbackEvents = []
const log = (m) => logs.push(String(m))
const pushEvent = (kind, payload) => events.push(Object.assign({ kind }, payload))
const scheduleStatusWrite = () => {}
const sliceLedgerForUnit = async () => null
const oversizeDispatchReason = () => ''
const unitPrompt = () => ''

// The REAL scanner, invoked exactly as relay-loop.js's strandedBranchesFor invokes it (same
// argv, same "<branch>\t<count>" line contract, same repo-scoped ⇒ [] rule, same fail-open).
const strandedBranchesFor = async (u) => {
  const item = dispatchItemFor(u)
  if (!item) return []
  let raw
  try {
    raw = execFileSync(SCAN, [u.path, '--verdict', u.verdict, '--item', item, '--base', 'main'],
                       { encoding: 'utf8' })
  } catch (e) { return [] }   // fail-open, as the production helper is
  return String(raw).split('\n').map((l) => l.trim()).filter((l) => l.includes('\t'))
}

async function dispatchPath(u) {
  // eslint-disable-next-line no-eval
  REGION_PLACEHOLDER
  // Falling off the end = the unit reached provisioning, i.e. it DISPATCHES.
  return { dispatched: true, item: dispatchItemFor(u) }
}

;(async () => {
  const r = await dispatchPath(unit)
  console.log(JSON.stringify({
    dispatched: !!(r && r.dispatched),
    item: (r && r.item) || '',
    named: namedItemsFor(unit),
    handbacks: state.handbacks.map((h) => h.reason),
    handbackEvents: events.filter((e) => e.kind === 'handback').length,
    logs,
  }))
})()
JS

# The extracted region is spliced in with python3 so no shell quoting can touch the source.
splice() {
  python3 - "$tmp/drive.js" "$tmp/region.js" "$tmp/helpers.js" "$1" <<'PY'
import sys
drive, region, helpers, out = sys.argv[1:5]
body = open(region, encoding='utf-8').read()
src = open(drive, encoding='utf-8').read().replace(
    '  // eslint-disable-next-line no-eval\n  REGION_PLACEHOLDER', body)
# the region names its argument `unit`; the wrapper's parameter is `u` — bind both.
src = src.replace('async function dispatchPath(u) {', 'async function dispatchPath(u) {\n  const unit = u')
open(out, 'w', encoding='utf-8').write(open(helpers, encoding='utf-8').read() + '\n' + src + '\n')
PY
}
splice "$tmp/run.js"

jqp() { python3 -c 'import sys,json; d=json.load(sys.stdin); print(eval(sys.argv[1]))' "$1"; }

# ===========================================================================================
# FIXTURE A — the real incident: ONE stranded item (first in ROADMAP order) + five clean ones.
# ===========================================================================================
repoA="$tmp/loderite"; build_repo "$repoA" one

discA="$("$DR" --repo loderite --path "$repoA" --runid relay-20260822-102233-32252 \
         --live-claims "" --main-branch main 2>"$tmp/discA.err")" \
  || note "discover-repo.sh exited non-zero on fixture A: $(cat "$tmp/discA.err")"

python3 -c 'import sys,json; d=json.load(sys.stdin); u=d["units"]; json.dump(u[0] if u else {}, open(sys.argv[1],"w"))' \
  "$tmp/unitA.json" <<<"$discA"

suppA="$(printf '%s' "$discA" | jqp '" ".join(sorted(d["units"][0].get("suppressed_item_ids",[]))) if d["units"] else "<NO UNIT>"')"
idsA="$(printf '%s' "$discA" | jqp '" ".join(d["units"][0].get("actionable_routine_ids",[])) if d["units"] else "<NO UNIT>"')"
surfA="$(printf '%s' "$discA" | jqp '"|".join(s.get("reason","") for s in d["surfaced"])')"

# ── (1) the pre-fix shape is reproduced, then fixed ─────────────────────────────────────────
# Pre-fix this read "d050": the residue orphan's mis-derived f272 matched id:0295's ARCHIVED
# `- [x]` prose and was classified a stale closed-item orphan, so it emitted no entry at all.
if [[ "$suppA" != "57d1 d050" ]]; then
  note "(1) suppressed_item_ids is [$suppA], expected [57d1 d050]. If it is exactly [d050] this is the pre-fix defect verbatim: the branch-name item 57d1 never reaches discover-repo.sh's suppressed set, because the commit-message derivation yields f272 (the id:f272 commit-and-park MECHANISM id) and f272 matches the ARCHIVED, TICKED id:0295 body — the 'closed ⇒ stale orphan ⇒ do not suppress' branch. Surfaced: [$surfA]"
fi
grep -q 'id:f272' <<<"$surfA" \
  && note "(1) id:f272 leaked into a surfaced suppress reason — the parking MECHANISM's id is not a ledger item: [$surfA]"

# ── (2) ROADMAP file order is preserved, stranded item first ────────────────────────────────
[[ "$idsA" == "57d1 6612 084f c8a7 55a4 5adb" ]] \
  || note "(2) actionable_routine_ids is [$idsA], expected the recorded ROADMAP file order [57d1 6612 084f c8a7 55a4 5adb] with the stranded item FIRST — that ordering is what makes dispatchItemFor pick it every round"

# ── (3) the repo-scoped orphan still binds via its COMMIT MESSAGE ────────────────────────────
lrepo="$(tr '|' '\n' <<<"$surfA" | grep 'execute-repo-0' || true)"
if [[ -z "$lrepo" ]]; then
  note "(3) no surfaced line for the repo-scoped orphan relay/orphan/…-execute-repo-0 — it must still be evaluated: [$surfA]"
else
  grep -q 'id:d050' <<<"$lrepo" \
    || note "(3) the repo-scoped orphan lost its commit-message binding to id:d050. 'repo' is not an item id, so the message fallback is load-bearing, not defensive: [$lrepo]"
fi

# ── (4) THE GREEN CONDITION: the repo actually PROCEEDS, on a non-blocked item ───────────────
if [[ ! -s "$tmp/unitA.json" ]] || [[ "$(cat "$tmp/unitA.json")" == "{}" ]]; then
  note "(4) discover-repo.sh emitted NO unit for a repo with five unencumbered actionable items — zero dispatch is the starvation: $discA"
else
  SCAN_BIN="$SCAN" node "$tmp/run.js" "$tmp/unitA.json" > "$tmp/outA.json" 2>"$tmp/outA.err" \
    || note "(4) the dispatch-path driver errored: $(cat "$tmp/outA.err")"
  if [[ -s "$tmp/outA.json" ]]; then
    dispA="$(jqp 'd["dispatched"]' < "$tmp/outA.json")"
    itemA="$(jqp 'd["item"]' < "$tmp/outA.json")"
    namedA="$(jqp '" ".join(d["named"])' < "$tmp/outA.json")"
    hbA="$(jqp '" || ".join(d["handbacks"])' < "$tmp/outA.json")"

    [[ "$dispA" == "True" ]] \
      || note "(4) THE STARVATION: the unit was ABORTED instead of dispatching, even though five of six actionable items are unencumbered. Handbacks: [$hbA]"
    # not merely "some item" — one of the FIVE genuinely unblocked ones.
    case " 6612 084f c8a7 55a4 5adb " in
      *" $itemA "*) : ;;
      *) note "(4) dispatched id:[$itemA], which is NOT one of the five unencumbered items (6612 084f c8a7 55a4 5adb). The repo must proceed with work it can actually do, not merely have a different suppress set." ;;
    esac
    [[ "$itemA" == "6612" ]] \
      || note "(4) dispatched id:$itemA; with only 57d1 stranded, selection must fall through to the NEXT actionable id in ROADMAP order, id:6612"
    [[ -z "$hbA" ]] \
      || note "(4) a handback was filed for a repo that still had five clean actionable items: [$hbA]"
    [[ "$(jqp 'd["handbackEvents"]' < "$tmp/outA.json")" == "0" ]] \
      && : || note "(4) a handback EVENT was emitted for a repo with clean actionable work"

    # ── (5) the dd7d protection is NOT bypassed ────────────────────────────────────────────
    [[ "$itemA" == "57d1" ]] \
      && note "(5) the STRANDED item id:57d1 was dispatched — dd7d's no-blind-redispatch guarantee (lodelore id:15d2) is broken"
    [[ " $namedA " == *" 57d1 "* ]] \
      && note "(5) the stranded id:57d1 is still in the unit's nameable set, so it can reach the child as a named ALTERNATE: [$namedA]"

    # ── (6) the dispatched item is genuinely clean per the shipped scanner ─────────────────
    if [[ -n "$itemA" ]]; then
      clean="$("$SCAN" "$repoA" --verdict execute --item "$itemA" --base main 2>"$tmp/scan.err")" \
        || note "(6) stranded-branch-scan.sh errored on the dispatched item: $(cat "$tmp/scan.err")"
      [[ -z "$clean" ]] \
        || note "(6) the dispatched id:$itemA is NOT clean — the shipped scanner reports committed work on it: [$clean]. Dispatching would repeat the very hazard dd7d exists to prevent."
    fi
    # and the scanner must still SEE the stranded one (the fixture must keep reproducing)
    "$SCAN" "$repoA" --verdict execute --item 57d1 --base main 2>/dev/null | grep -q 'execute-57d1-0' \
      || note "(6) stranded-branch-scan.sh no longer sees the 57d1 orphan — the fixture stopped reproducing the incident"
  fi
fi

# ===========================================================================================
# FIXTURE B — NEGATIVE CONTROL: every actionable item stranded. Without this, everything above
# would also pass against an implementation that simply dispatches something regardless.
# ===========================================================================================
repoB="$tmp/loderite-all"; build_repo "$repoB" all

discB="$("$DR" --repo loderite-all --path "$repoB" --runid relay-20260822-102233-32252 \
         --live-claims "" --main-branch main 2>/dev/null)"
nunitsB="$(printf '%s' "$discB" | jqp 'len(d["units"])')"
[[ "$nunitsB" == "0" ]] \
  || note "(7) every actionable item is bound to a parked orphan, so discover-repo.sh's SAME-ITEM carve-out must emit NO execute unit (reconcile-first). Got $nunitsB unit(s): $discB"

# and the dd7d gate itself must refuse, even if a unit reached it with an EMPTY suppress set
# (i.e. the binding missing entirely — precisely the pre-fix condition). This is the backstop
# half of the a360 fix: a binding miss must degrade to a loud handback, never to a blind
# re-dispatch of committed work.
python3 - "$tmp/unitB.json" "$repoB" <<'PY'
import json, sys
json.dump({"repo": "loderite-all", "verdict": "execute", "path": sys.argv[2],
           "actionable_routine_ids": ["57d1", "6612", "084f", "c8a7", "55a4", "5adb"],
           "suppressed_item_ids": []}, open(sys.argv[1], "w"))
PY
SCAN_BIN="$SCAN" node "$tmp/run.js" "$tmp/unitB.json" > "$tmp/outB.json" 2>"$tmp/outB.err" \
  || note "(8) the dispatch-path driver errored on fixture B: $(cat "$tmp/outB.err")"
if [[ -s "$tmp/outB.json" ]]; then
  dispB="$(jqp 'd["dispatched"]' < "$tmp/outB.json")"
  hbB="$(jqp '" || ".join(d["handbacks"])' < "$tmp/outB.json")"
  [[ "$dispB" == "False" ]] \
    || note "(8) an ALL-STRANDED repo DISPATCHED id:$(jqp 'd["item"]' < "$tmp/outB.json") — every item carries committed work; the guard must refuse (dd7d/id:15d2). This is the assertion that keeps case (4) from passing against an always-dispatch implementation."
  [[ "$(jqp 'len(d["handbacks"])' < "$tmp/outB.json")" == "1" ]] \
    || note "(8) expected exactly one repo-level handback from an all-stranded repo, got: [$hbB]"
  grep -q 'id:dd7d' <<<"$hbB" \
    || note "(8) the all-stranded handback no longer cites id:dd7d: [$hbB]"
  for id in "${IDS[@]}"; do
    grep -q "execute-$id-0" <<<"$hbB" \
      || note "(8) the handback reason does not name the stranded branch for id:$id — a human dispositions from this text: [$hbB]"
  done
  [[ "$(jqp 'd["handbackEvents"]' < "$tmp/outB.json")" == "1" ]] \
    || note "(8) no handback EVENT emitted for the all-stranded repo (id:4a46 bidirectional surface)"
fi

[[ $fail -eq 0 ]] || exit 1
echo "ALL PASS: the loderite starvation is fixed end-to-end — the residue orphan binds to id:57d1 despite f272 matching an ARCHIVED ticked item, the repo-scoped orphan still binds by commit message, and loderite dispatches the clean id:6612 while the stranded item stays un-dispatched and un-nameable (id:a360)"
