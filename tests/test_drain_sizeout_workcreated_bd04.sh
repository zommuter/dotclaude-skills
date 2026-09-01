#!/usr/bin/env bash
# id:bd04 — a child-reported SIZE-OUT that proposes seams must count as work-created, so the
# round is not scored dry. (Defect-fix test: no ROADMAP item, so no `roadmap:` header — its
# failures always count.)
#
# Incident: csgebra run relay-20260818-205434-31345 exited stopReason:'drained', rounds:6 after
# two hard size-outs whose reports explicitly carried route=hard-split with a 4-seam and a 3-seam
# proposed_split; classify-repo.sh on the same tree immediately reported verdict=hard,
# open_hard=4. Root cause (verified against ~/.config/relay/relay-events.jsonl for that run): a
# size-out takes the `if (!report.contract_met)` branch and NEVER reaches integrate(), but
# `workCreated` was set ONLY at the integrate() push site — so id:c919, which exists precisely to
# stop a decomposing round scoring dry, was inert for the one case it was built for.
# fails-against: rev a85334644b72 -- the tree as it stood immediately before the commit that
#   added this test, i.e. the pre-fix relay/scripts/relay-loop.js. Derived + verified by tests/verify-negative-cases.py.
# fails-against-rev: a85334644b72 -- relay/scripts/relay-loop.js
# fails-against-assertion: (1) id:bd04 REGRESSION: the size-out handback push does not set workCreated — id:c919 is inert for size-outs, and a decomposing round will score dry again

set -euo pipefail
SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JS="$SRC_DIR/relay/scripts/relay-loop.js"
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

# (1) STRUCTURAL — the size-out push site must carry workCreated. This is the regression that bit.
sizeout_push="$(head -1 < <(grep -n 'reason: hbReason, worktreePath: report.worktree' "$JS") )"
[[ -n "$sizeout_push" ]] || fail "(1) could not find the contract_met=false handback push site"
grep -q 'reason: hbReason, worktreePath: report.worktree, workCreated:' "$JS" \
  || fail "(1) id:bd04 REGRESSION: the size-out handback push does not set workCreated — id:c919 is inert for size-outs, and a decomposing round will score dry again"
pass "(1) the size-out handback push sets workCreated"

# (2) ONE predicate, not two inline copies (the divergence that let the two sites disagree).
[[ "$(grep -c 'function handbackCreatedWork' "$JS")" == "1" ]] || fail "(2) handbackCreatedWork must be defined exactly once"
[[ "$(grep -c 'handbackCreatedWork(report)' "$JS")" -ge 2 ]] \
  || fail "(2) both handback sites must consume the shared predicate, not re-inline it"
pass "(2) both sites share one handbackCreatedWork predicate"

# (3) BEHAVIOURAL — evaluate the real extracted predicate + isDryRound against the incident's
#     actual reports. A structural grep alone would not have caught the original bug's effect.
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
python3 - "$JS" > "$TMP/pred.mjs" <<'PY'
import sys, re
src = open(sys.argv[1], encoding='utf-8').read()
start = src.index('function handbackCreatedWork(report) {')
end = src.index('\n}', src.index('function isDryRound(r) {')) + 2
open('/dev/stdout', 'w').write(src[start:end] + "\nexport { handbackCreatedWork, isDryRound }\n")
PY
node --input-type=module -e "
import('file://$TMP/pred.mjs').then(m => {
  const out = []
  const ok = (n, c) => out.push(n + '=' + (c ? 1 : 0))
  // csgebra id:866f — route=hard-split, 4 seams (the real first size-out)
  const sizeout866f = { contract_met: false, route: 'hard-split',
    proposed_split: [{title:'seam contract'},{title:'manifold3d adapter'},{title:'occt adapter'},{title:'pwa shell'}] }
  ok('sizeout_creates_work', m.handbackCreatedWork(sizeout866f) === true)
  // the round it occurred in: nothing integrated, nothing surfaced — dry ONLY if workCreated is lost
  ok('decomposing_round_not_dry', m.isDryRound({ substantive: 0, surfaced: 0, workCreated: 1 }) === false)
  ok('regression_shape_would_be_dry', m.isDryRound({ substantive: 0, surfaced: 0, workCreated: 0 }) === true)
  // a size-out that proposes NOTHING is still a dry handback — the guard must not over-fire
  ok('empty_split_no_work', m.handbackCreatedWork({ contract_met: false, route: 'hard-split', proposed_split: [] }) === false)
  ok('other_route_no_work', m.handbackCreatedWork({ contract_met: false, route: 'decision-gate', proposed_split: [{t:1}] }) === false)
  ok('junk_no_throw', (() => { try { return m.handbackCreatedWork(null) === false && m.handbackCreatedWork(undefined) === false } catch { return false } })())
  console.log(out.join('\n'))
})
" > "$TMP/res" 2>&1 || { cat "$TMP/res"; fail "(3) could not evaluate the extracted predicate"; }
while IFS='=' read -r k v; do
  [[ -z "$k" ]] && continue
  [[ "$v" == "1" ]] && pass "(3) $k" || fail "(3) case failed — $k"
done < "$TMP/res"
echo "ALL PASS: a decomposing size-out counts as work-created (id:bd04)"
