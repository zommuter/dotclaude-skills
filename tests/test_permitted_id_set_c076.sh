#!/usr/bin/env bash
# id:c076 -- the classifier's computed permitted-id set must reach the dispatched child, and an
# EMPTY set must fail CLOSED.
#
# Defect-fix test, no roadmap item. THE INCIDENT (review 2026-09-09, REVIEW_ME id:c076):
# classify-repo.sh scored id:6446's ROADMAP line is_routine=True, blocked=True (the 🚧),
# is_owner_gated=True, so it was excluded from actionable_routine_ids -- and the Sonnet execute
# child worked it anyway. Nothing at the code level had ever told the child what it was allowed
# to work: the exclusion set was computed and consumed by nothing. Restating the marker
# exclusions in executor-contract.md prose was explicitly NOT chosen (it is prose an executor
# can miss, the id:d35a silent-no-op class), so the guard is STRUCTURAL: the set is handed over.
#
# fails-against-mutation: python3 -c "import io; p='relay/scripts/relay-loop.js'; s=io.open(p,encoding='utf-8').read(); n=s.replace('executeNamedInstruction(unit) || EXECUTE_NO_PERMITTED_SET', 'executeNamedInstruction(unit) || SURVEY_FALLBACK'); assert n != s, 'mutation matched nothing'; io.open(p,'w',encoding='utf-8').write(n)"
# fails-against-assertion: (D) the dispatch site no longer resolves to the fail-closed brief
#
# The mutation restores the SHAPE of the pre-c076 dispatch-site fallback: the execute branch
# resolves to something OTHER than the fail-closed brief for an id-less unit. Cases (A)-(C) run
# off executeNamedInstruction and are untouched by it, and (D)'s positive control (a unit WITH
# ids) still short-circuits before the fallback, so the id-less render is the only thing that
# breaks -- the single, last FAIL line. The declared assertion pins the WIRING half of (D); the
# text half (the refusal actually saying "work nothing, hand back") is asserted immediately
# after it and is what a wording regression would hit instead.
#
# FIXTURE-SANITY, and why it is here: the first draft of this file attached each node heredoc to
# the enclosing `if ... fi` rather than to the `node` command, so node read an EMPTY program,
# exited 0, and every case "passed". `make verify-negatives` caught it as VACUOUS. The JS now
# goes through a file, and each block asserts a positive control that cannot hold if the script
# did not run.
#
# Cases:
#   (A) the rendered instruction carries the CLOSED permitted set, enumerating EVERY permitted
#       id -- not just the primary and its two bounded alternates.
#   (B) a suppressed / stranded id is NOT in the set (it composes with namedItemsFor's
#       subtraction, id:b09e/id:a360), and the set FORBIDS unlisted ids with a hand-back
#       instruction rather than expressing a preference.
#   (C) a user-injected item (id:baf1) is IN the set and FIRST in it.
#   (D) an EMPTY permitted set FAILS CLOSED at the dispatch site: the rendered execute line is
#       the refusal, and is NOT the historical "work the open [ROUTINE] items" survey.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOOP="$ROOT/relay/scripts/relay-loop.js"

rcode=0
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; rcode=1; }

command -v node >/dev/null 2>&1 || { echo "SKIP: node not available"; exit 0; }
[[ -f "$LOOP" ]] || { echo "FAIL: relay-loop.js missing at $LOOP"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# The dispatch-naming block is extracted at the same seam tests/test_dispatch_names_item_b09e.sh
# case (6) uses -- anchored source markers, evaluated directly, no Workflow engine.
cat > "$TMP/abc.js" <<'JS'
const fs = require('node:fs')
const src = fs.readFileSync(process.argv[2], 'utf8')
const start = src.indexOf('// id:b09e — NAME the item')
const end   = src.indexOf('function unitPrompt(')
if (start < 0 || end < 0 || end <= start) { console.log('(A) cannot locate the dispatch-naming block in relay-loop.js'); process.exit(1) }
let fn
try { fn = new Function(src.slice(start, end) + '\nreturn executeNamedInstruction')() }
catch (e) { console.log('(A) dispatch-naming block failed to evaluate: ' + e); process.exit(1) }

let bad = 0
const need = (cond, msg) => { if (!cond) { console.log(msg); bad = 1 } }

// (A) EVERY permitted id is enumerated -- including ones beyond the bounded walk list.
const many = fn({ verdict: 'execute', actionable_routine_ids: ['aaa1','aaa2','aaa3','aaa4','aaa5'] })
// positive control: if this block did not really run, nothing below could have failed either.
need(many.length > 0, '(A) executeNamedInstruction returned nothing for a unit with five actionable ids -- the fixture did not exercise the code')
need(/PERMITTED SET \(id:c076\)/.test(many), '(A) the rendered instruction carries no PERMITTED SET (id:c076) clause at all')
for (const id of ['aaa1','aaa2','aaa3','aaa4','aaa5']) {
  need(new RegExp('id:' + id).test(many), '(A) permitted id ' + id + ' is missing from the set -- an incomplete set cannot be the authority on what is out of scope')
}

// (B) composition with the b09e/a360 subtraction, and the set must FORBID, not merely prefer.
const sub = fn({ verdict: 'execute', actionable_routine_ids: ['aaa1','bbb2','ccc3'], suppressed_item_ids: ['bbb2'], stranded_item_ids: ['ccc3'] })
need(/id:aaa1/.test(sub), '(B) the surviving permitted id aaa1 is missing -- subtraction removed too much')
need(!/id:bbb2/.test(sub), '(B) an orphan-suppressed id reached the permitted set')
need(!/id:ccc3/.test(sub), '(B) a stranded id reached the permitted set')
need(/OUT OF SCOPE/.test(sub), '(B) the set does not say unlisted items are OUT OF SCOPE')
need(/hand ?back/i.test(sub), '(B) the set does not tell the child to hand back on an unlisted id -- a preference is not a boundary')

// (C) an injected item is IN the set and FIRST.
const inj = fn({ verdict: 'execute', inject_item: 'bbbb', actionable_routine_ids: ['aaa1','aaa2'] })
const m = inj.match(/PERMITTED SET \(id:c076\)[^:]*: ([^.]+)\./)
need(m !== null, '(C) cannot parse the permitted-set enumeration out of the injected-item instruction')
if (m) {
  const listed = m[1].split(',').map((s) => s.trim())
  need(listed[0] === 'id:bbbb', '(C) a user-injected item is not FIRST in the permitted set (got: ' + listed.join(' ') + ')')
  need(listed.includes('id:aaa1'), '(C) injection dropped the classifier candidates from the permitted set instead of unioning with them')
}
process.exit(bad)
JS

if node "$TMP/abc.js" "$LOOP" > "$TMP/abc.out" 2>&1; then
  pass "(A)(B)(C) permitted set is complete, closed, subtraction-aware, and injection-first"
else
  while IFS= read -r line; do [[ -n "$line" ]] && fail "$line"; done < "$TMP/abc.out"
fi

# ── (D) THE FAIL-CLOSED BRANCH, read at the DISPATCH SITE, not off the helper. ─────────
# The helper correctly returns '' for a unit with no ids (pinned by b09e case 6); what matters
# is what the CALLER then renders. Pre-c076 that was 'Work the open [ROUTINE] items in
# ROADMAP.md' -- a wide survey handed over in exactly the situation where the orchestrator has
# LEAST idea what is safe to work. So the template's own expression is compiled and rendered
# here, not a constant read in isolation.
cat > "$TMP/d.js" <<'JS'
const fs = require('node:fs')
const src = fs.readFileSync(process.argv[2], 'utf8')
const start = src.indexOf('// id:b09e — NAME the item')
const end   = src.indexOf('function unitPrompt(')
const tmplLine = src.split('\n').find((l) => l.includes("unit.verdict === 'execute' ?"))
if (start < 0 || end < 0 || !tmplLine) { console.log('(D) cannot locate the dispatch-naming block or the execute template line'); process.exit(1) }
const expr = tmplLine.slice(tmplLine.indexOf('${') + 2, tmplLine.lastIndexOf('}'))
let render
try { render = new Function('unit', src.slice(start, end) + '\nreturn (' + expr + ')') }
catch (e) { console.log('(D) execute template expression failed to compile: ' + e); process.exit(1) }

let bad = 0
const need = (cond, msg) => { if (!cond) { console.log(msg); bad = 1 } }
// positive control FIRST: a unit that DOES carry ids must still render its named instruction
// through this same expression, so a rendering that silently yields '' cannot pass case (D).
let named = ''
try { named = String(render({ verdict: 'execute', actionable_routine_ids: ['aaa1'] }) || '') }
catch (e) { console.log('(D) the execute template expression threw for a unit WITH ids: ' + e); process.exit(1) }
need(/id:aaa1/.test(named), '(D) control failed: the execute template expression does not render the named instruction for a unit with ids')

let out = ''
try { out = String(render({ verdict: 'execute' }) || '') }
catch (e) { console.log('(D) the dispatch site no longer resolves to the fail-closed brief for an id-less unit: ' + e); process.exit(1) }
need(!/Work the open \[ROUTINE\] items/.test(out), '(D) an empty permitted set still renders the historical plural survey instruction')
// THE declared assertion. LAST, so it is the line the negative-case runner matches.
need(/FAIL-CLOSED \(id:c076\)/.test(out) && /NOT PERMISSION TO WORK ANYTHING/.test(out) && /contract_met=false/.test(out),
  '(D) an EMPTY permitted set does not fail CLOSED -- the rendered execute instruction carries no refusal telling the child to work nothing and hand back')
process.exit(bad)
JS

if node "$TMP/d.js" "$LOOP" > "$TMP/d.out" 2>&1; then
  pass "(D) an empty permitted set renders the fail-closed refusal, never a survey"
else
  while IFS= read -r line; do [[ -n "$line" ]] && fail "$line"; done < "$TMP/d.out"
fi

if [[ $rcode -eq 0 ]]; then
  pass "id:c076 -- the computed permitted-id set is threaded into the dispatch prompt as a CLOSED set, and an empty set fails closed"
fi
exit $rcode
