#!/usr/bin/env bash
# No roadmap header -- defect-fix spec for the id:1048 WIRING. Failures always count.
#
# Defect: `grep -c auto-integrate-orphan relay/scripts/relay-loop.js` was 0. The bounded
# auto-integrate primitive `relay/scripts/auto-integrate-orphan.sh` was fully built, tested and
# green (tests/test_bounded_auto_integrate_1048.sh) and NOTHING called it -- the
# built-green-but-unreferenced class. So the "reconcile-first (integrate-if-safe)" half of
# meeting 2026-07-23-1735 A1/D1 was a null op and a parked relay/orphan/* branch was surfaced
# round after round and never consumed.
#
# Clause, three parts:
#   (1) OFF BY DEFAULT, strictly. Unset/empty/false `AUTO_INTEGRATE_ORPHANS` must dispatch NO
#       hop at all and leave the round exactly as it was before the wiring. This is not a
#       preference: a4e9-D1 ruled "NO auto-integration"; id:1048 amends it only to a bounded
#       form, and enabling it grants the pool an autonomous merge-to-main capability.
#   (2) ON, the hop is emitted with the RIGHT script and the RIGHT arguments, as a mechanical
#       `relay-mech` fenced command at MECH_MODEL -- never a new dispatch shape.
#   (3) FAIL-OPEN and LOUD at every branch (throw / MECH-ERROR / no success marker /
#       unresolvable repo path): log why, return, and let the round continue.
#
# fails-against: the wiring and this spec land in the same commit, so the negative case is a
# mutation that removes the off-by-default gate at the single call site while leaving the
# helper, the constant and the hop shape intact.
# fails-against-mutation: sed -i 's|^if (AUTO_INTEGRATE_ORPHANS) await autoIntegrateParkedOrphans(discovery)$|await autoIntegrateParkedOrphans(discovery)|' relay/scripts/relay-loop.js
# fails-against-assertion: (G) the auto-integrate call site is not gated on AUTO_INTEGRATE_ORPHANS
#
# Also non-vacuous against the pre-wiring revision: on `git show main:relay/scripts/relay-loop.js`
# the awk extractions in step (2) below yield EMPTY files, so the run dies at the
# "could not extract" guard before any assertion -- every assertion here is unreachable there.
#
# Hermetic: reads relay-loop.js, extracts three regions and runs them under node in a
# mktemp -d with a stubbed agent()/log(). No ~/.claude, no ~/.config/relay, no git, no network,
# no dispatch, no merge.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JS="$ROOT/relay/scripts/relay-loop.js"
pass=0 fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); return 0; }
bad() { echo "FAIL: $*"; fail=$((fail+1)); return 0; }
[[ -f "$JS" ]] || { echo "FAIL: relay-loop.js missing at $JS"; exit 1; }
command -v node >/dev/null 2>&1 || { echo "SKIP: node not available"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- (2) extract the three regions under test, verbatim from the source -------------------
# (a) the opt-in constant, so its DEFAULTING is executed rather than eyeballed.
awk '/^const AUTO_INTEGRATE_ORPHANS = \(\(\) => \{/{f=1} f{print} f&&/^\}\)\(\)$/{exit}' \
  "$JS" > "$TMP/flag.js"
[[ -s "$TMP/flag.js" ]] || { echo "FAIL: could not extract the AUTO_INTEGRATE_ORPHANS declaration"; exit 1; }

# (b) the pure helper block, delimited by its own markers.
awk '/^\/\/ --- id:1048 pure helper/{f=1} f{print} /^\/\/ --- end id:1048 pure helper/{f=0}' \
  "$JS" > "$TMP/helpers.js"
[[ -s "$TMP/helpers.js" ]] || { echo "FAIL: could not extract the id:1048 pure-helper block"; exit 1; }
grep -q 'function orphanBranchFromSuppressReason' "$TMP/helpers.js" \
  || { echo "FAIL: helper block lacks orphanBranchFromSuppressReason"; exit 1; }

# (c) the dispatch function itself, extracted rather than pattern-matched so the assertions
#     below EXECUTE the real code: a mutation that makes the hop unconditional, drops a
#     fail-open branch, or changes the command changes BEHAVIOUR here, not merely a grep.
awk '/^async function autoIntegrateParkedOrphans\(/{f=1} f{print} f&&/^\}$/{exit}' \
  "$JS" > "$TMP/fn.js"
[[ -s "$TMP/fn.js" ]] || { echo "FAIL: could not extract autoIntegrateParkedOrphans()"; exit 1; }

cat > "$TMP/probe.js" <<'PROBE'
const fs = require('fs')
const flagSrc = fs.readFileSync(process.argv[2], 'utf8')
const helpers = fs.readFileSync(process.argv[3], 'utf8')
const fnSrc   = fs.readFileSync(process.argv[4], 'utf8')

// The constant reads `A` (the normalized args object) -- wrap it so its defaulting runs.
const flagFrom = new Function('A', flagSrc + '\nreturn AUTO_INTEGRATE_ORPHANS\n')

// The dispatch function closes over AUTO_INTEGRATE_ORPHANS / agent / log / MECH_MODEL.
// Declare them as mutable bindings and hand back a setter, so one extraction is exercised
// under every configuration.
const mk = new Function(
  'var AUTO_INTEGRATE_ORPHANS, agent, log, MECH_MODEL;\n' +
  helpers + '\n' + fnSrc + '\n' +
  'return function (flag, agentImpl, logImpl, mech) {\n' +
  '  AUTO_INTEGRATE_ORPHANS = flag; agent = agentImpl; log = logImpl; MECH_MODEL = mech;\n' +
  '  return autoIntegrateParkedOrphans\n' +
  '}\n')()

const helperApi = new Function(helpers + '\nreturn { orphanBranchFromSuppressReason }\n')()

const out = []
const t = (name, cond) => out.push((cond ? 'PASS ' : 'FAIL ') + name)

// The exact line reconcile-repo.sh:424 emits for a suppressing parked orphan.
const SUPPRESS = 'suppressed re-dispatch: parked partial work for id:dddd still OPEN on ' +
  'relay/orphan/deadrun-dddd - manual /relay reconcile; cost hint: relay-burn.sh --run relay-1'
const disc = () => ({
  paths: { loderite: '/home/u/src/loderite' },
  surfaced: [{ repo: 'loderite', reason: SUPPRESS }],
})

// ---- (A) OFF by default -------------------------------------------------------------------
t('A:absent', flagFrom({}) === false)
t('A:empty', flagFrom({ AUTO_INTEGRATE_ORPHANS: '' }) === false)
t('A:null', flagFrom({ autoIntegrateOrphans: null }) === false)
t('A:false-bool', flagFrom({ autoIntegrateOrphans: false }) === false)
t('A:false-str', flagFrom({ AUTO_INTEGRATE_ORPHANS: 'false' }) === false)
t('A:zero', flagFrom({ AUTO_INTEGRATE_ORPHANS: '0' }) === false)
t('A:junk', flagFrom({ AUTO_INTEGRATE_ORPHANS: 'maybe' }) === false)

// ---- (B) ON only on an explicit opt-in ----------------------------------------------------
t('B:bool', flagFrom({ autoIntegrateOrphans: true }) === true)
t('B:one', flagFrom({ AUTO_INTEGRATE_ORPHANS: '1' }) === true)
t('B:true', flagFrom({ AUTO_INTEGRATE_ORPHANS: 'TRUE' }) === true)
t('B:on', flagFrom({ autoIntegrateOrphans: ' on ' }) === true)
t('B:yes', flagFrom({ autoIntegrateOrphans: 'yes' }) === true)

// ---- (C) the surfaced-reason parser is orphan-suppress ONLY --------------------------------
const ob = helperApi.orphanBranchFromSuppressReason
t('C:match', ob(SUPPRESS) === 'relay/orphan/deadrun-dddd')
t('C:inflight', ob('in-flight elsewhere: another live run holds relay/orphan/x') === '')
t('C:diverged', ob('diverged from origin (ahead+behind) on relay/orphan/x') === '')
t('C:discover-error', ob('discover shard failed (transient API/network drop)') === '')
// a PLANNED park (id:e7e4) is still named by its pre-rename relay/<bn> form -- never matched.
t('C:planned', ob('suppressed re-dispatch: parked partial work on relay/run-1-execute-repo-0 - x') === '')
t('C:empty', ob('') === '' && ob(null) === '' && ob(undefined) === '')

// ---- (D) OFF => a STRICT no-op: zero agent calls, zero logs, returns 0 ---------------------
;(async () => {
  let calls = [], logs = []
  const A_ = (p, o) => { calls.push({ p, o }); return 'auto-integrated x' }
  const L_ = (m) => logs.push(String(m))
  let n = await mk(false, A_, L_, 'bash')(disc())
  t('D:returns-0', n === 0)
  t('D:no-agent', calls.length === 0)
  t('D:no-log', logs.length === 0)

  // ---- (E) ON => exactly one hop, right script, right args, right shape --------------------
  calls = []; logs = []
  n = await mk(true, A_, L_, 'bash')(disc())
  t('E:one-call', calls.length === 1)
  const c = calls[0] || { p: '', o: {} }
  t('E:script', /\/relay\/scripts\/auto-integrate-orphan\.sh\b/.test(c.p))
  t('E:repo-arg', c.p.includes('--repo /home/u/src/loderite'))
  t('E:branch-arg', c.p.includes('--orphan-branch relay/orphan/deadrun-dddd'))
  t('E:fenced', c.p.includes('```relay-mech\n') && /```\s*$/.test(c.p.trim()))
  t('E:mech-model', c.o.model === 'bash')
  t('E:phase', c.o.phase === 'Integrate')
  t('E:integrated', n === 1)

  // MECH_MODEL is threaded, never hard-coded (the fallback-haiku posture must survive).
  calls = []
  await mk(true, A_, L_, 'haiku')(disc())
  t('E:mech-model-threaded', (calls[0] || {}).o.model === 'haiku')

  // ---- (F) fail-open and LOUD on every failure branch --------------------------------------
  // (i) the hop throws
  calls = []; logs = []
  n = await mk(true, () => { throw new Error('agent exploded') }, L_, 'bash')(disc())
  t('F:throw-returns', n === 0)
  t('F:throw-logged', logs.some(m => /threw/.test(m) && /agent exploded/.test(m)))

  // (ii) MECH-ERROR sentinel -- also the primitive's normal refusal channel
  calls = []; logs = []
  n = await mk(true, () => 'MECH-ERROR exit=1', L_, 'bash')(disc())
  t('F:mech-error-returns', n === 0)
  t('F:mech-error-logged', logs.some(m => /PARKED/i.test(m) && /MECH-ERROR/.test(m)))

  // (iii) garbled / empty stdout -- no success marker
  calls = []; logs = []
  n = await mk(true, () => '', L_, 'bash')(disc())
  t('F:garbled-returns', n === 0)
  t('F:garbled-logged', logs.some(m => /no success marker/i.test(m)))

  // (iv) a repo whose main-checkout path cannot be resolved
  calls = []; logs = []
  n = await mk(true, A_, L_, 'bash')({ paths: {}, surfaced: [{ repo: 'loderite', reason: SUPPRESS }] })
  t('F:nopath-no-call', calls.length === 0)
  t('F:nopath-returns', n === 0)
  t('F:nopath-logged', logs.some(m => /no main-checkout path/.test(m)))

  // (v) a missing/garbled discovery object must not throw
  calls = []; logs = []
  n = await mk(true, A_, L_, 'bash')(null)
  t('F:null-disc', n === 0 && calls.length === 0)

  // (vi) non-orphan surfaced classes never produce a hop
  calls = []
  await mk(true, A_, L_, 'bash')({
    paths: { r: '/p' },
    surfaced: [
      { repo: 'r', reason: 'in-flight elsewhere: another live run holds this repo' },
      { repo: 'r', reason: 'diverged from origin (ahead+behind)' },
      { repo: 'r', reason: 'circuit breaker (id:365b): r execute dispatched >3x' },
    ],
  })
  t('F:other-classes-no-call', calls.length === 0)

  // (vii) the same orphan surfaced twice is offered ONCE
  calls = []
  await mk(true, A_, L_, 'bash')({
    paths: { r: '/p' },
    surfaced: [{ repo: 'r', reason: SUPPRESS }, { repo: 'r', reason: SUPPRESS }],
  })
  t('F:dedup', calls.length === 1)

  console.log(out.join('\n'))
})().catch(e => { console.log(out.join('\n') + '\nFAIL probe-threw:' + e.message) })
PROBE

node "$TMP/probe.js" "$TMP/flag.js" "$TMP/helpers.js" "$TMP/fn.js" > "$TMP/out.txt" 2> "$TMP/err.txt" || {
  echo "FAIL: the id:1048 probe did not run: $(head -3 "$TMP/err.txt")"
  exit 1
}

grepv() { grep -q "^PASS $1\$" "$TMP/out.txt"; }
allv()  { local n; for n in "$@"; do grepv "$n" || return 1; done; return 0; }

allv A:absent A:empty A:null A:false-bool A:false-str A:zero A:junk \
  && ok "(A) unset/empty/false/junk AUTO_INTEGRATE_ORPHANS is OFF -- the default stays off" \
  || bad "(A) AUTO_INTEGRATE_ORPHANS did not default OFF"

allv B:bool B:one B:true B:on B:yes \
  && ok "(B) an explicit opt-in (true/1/true/on/yes) turns the knob on" \
  || bad "(B) an explicit opt-in did not turn the knob on"

allv C:match C:inflight C:diverged C:discover-error C:planned C:empty \
  && ok "(C) only an orphan-suppress surfaced line yields a relay/orphan/* branch" \
  || bad "(C) the surfaced-reason parser matched a class it must never route"

allv D:returns-0 D:no-agent D:no-log \
  && ok "(D) knob OFF -- ZERO agent dispatches, zero logs, returns 0 (a strict no-op round)" \
  || bad "(D) the knob was off and the auto-integrate hop still did something"

allv E:one-call E:script E:repo-arg E:branch-arg E:fenced E:mech-model E:phase E:integrated E:mech-model-threaded \
  && ok "(E) knob ON -- exactly one fenced relay-mech hop at MECH_MODEL running auto-integrate-orphan.sh --repo/--orphan-branch" \
  || bad "(E) the knob was on but the hop was missing, misshapen, or carried the wrong arguments"

allv F:throw-returns F:throw-logged F:mech-error-returns F:mech-error-logged \
     F:garbled-returns F:garbled-logged F:nopath-no-call F:nopath-returns F:nopath-logged \
     F:null-disc F:other-classes-no-call F:dedup \
  && ok "(F) every failure branch is fail-open AND logged; other surfaced classes and duplicates never dispatch" \
  || bad "(F) a failure branch was not fail-open, was silent, or dispatched when it must not"

# --- structural: exactly ONE call site, and it is GATED on the knob -------------------------
sites="$(grep -nE 'autoIntegrateParkedOrphans\(' "$JS" | grep -v 'async function' | grep -vE '^[0-9]+:\s*//' | grep -c . || true)"
gated="$(grep -cF 'if (AUTO_INTEGRATE_ORPHANS) await autoIntegrateParkedOrphans(discovery)' "$JS" || true)"
if [[ "$sites" == "1" && "$gated" == "1" ]]; then
  ok "(G) exactly one auto-integrate call site, gated on AUTO_INTEGRATE_ORPHANS"
else
  bad "(G) the auto-integrate call site is not gated on AUTO_INTEGRATE_ORPHANS (sites=$sites gated=$gated)"
fi

# --- the script still parses as a Workflow script (bare `node --check` cannot judge it: the
# --- harness wraps the body in an async function, so a top-level `return` is legal there and
# --- illegal to node --check. tests/lib-workflow-check.sh does the same wrapping).
# shellcheck source=/dev/null
. "$ROOT/tests/lib-workflow-check.sh"
workflow_node_check "$JS" >/dev/null 2>&1 \
  && ok "(H) relay-loop.js still parses as a Workflow script after the id:1048 wiring" \
  || bad "(H) relay-loop.js no longer parses after the id:1048 wiring"

echo "test_relay_auto_integrate_orphans_1048: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
