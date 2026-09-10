#!/usr/bin/env bash
# roadmap:4e84
# RED SPEC for id:4e84 -- the chain-end classifier RE-ASK must accept the whole DISPATCHABLE
# verdict set, and must tell the classifier which classes this run already dispatched for that
# repo. Detail: docs/ledger-notes/4e84.md (read its OWNER RULINGS + CORRECTIONS sections first;
# the approach is SETTLED and this file does not re-open it).
#
# WHAT IS BROKEN, both defects LOOP-side (the classifier cascade is already sufficient -- id:bc2b
# `--exclude` walks it demote-only, measured: no flag -> execute, `--exclude execute` -> hard,
# `--exclude execute,hard` -> handoff, `+handoff` -> idle):
#
#   (1) relay-loop.js:4615 reads `if (chainEndVerdict === 'review' && !quotaStopped)`. Every
#       verdict that is not `review` is COMPUTED, LOGGED ("classifier says hard; no review
#       owed") and then DISCARDED. The dispatchable set is the one already spelled at
#       relay-loop.js:1705 -- execute|hard|handoff -- plus review.
#   (2) The hop (command built around relay-loop.js:4610) passes NO `--exclude`, so the
#       classifier re-answers `execute` for any repo with open routine work and `hard`/`handoff`
#       can never come back from it at all. The exclusion set must be THIS RUN's dispatches for
#       THIS repo, which already exist as the `redispatchGuard` keys (`${repo}:${verdict}`,
#       relay-loop.js:1454/2598) -- no new state. It must NOT be keyed on the breaker's ">3x
#       same-verdict" condition: that condition is false on round 1, so such a fix is a no-op
#       exactly when starvation starts. This harness dispatches ONE unit, so the breaker count is
#       1 and a breaker-keyed implementation fails case D below. That is the discriminator.
#
# HOW THIS IS TESTED -- behaviourally, by EXECUTING relay-loop.js, not by grepping it. The
# harness below is the id:aec5 `tests/fixtures/loop-round-exec-harness.mjs` technique (stub the
# Workflow globals, wrap the body in an async IIFE, drive one real round), narrowed to one repo
# and one round and extended so the `chain-end-reask:<repo>` hop's reply is scripted per
# scenario and its PROMPT is captured. `node --check` cannot parse relay-loop.js at all
# (top-level return), so the parse guard goes through `workflow_node_check` (id:62c9).
#
# POSITIVE CONTROL, run before this file was committed: the same harness was pointed at a
# scratch copy of relay-loop.js carrying a minimal widening (accept review|hard|handoff|execute,
# push `verdict: chainEndVerdict`, append `--exclude '<redispatchGuard keys for this repo>'`).
# Every assertion below then PASSED, and the exclusion argument came back as `'execute'`. So the
# cases are reachable and discriminating, not an unreached fixture (the feedback-verify-delegated
# -work corollary: a BEFORE side that never reaches the guarded path proves nothing).
#
# CASES
#   A. re-ask answers `hard`    -> a hard unit is DISPATCHED for that repo this round.
#   B. re-ask answers `handoff` -> a handoff unit is DISPATCHED (the promotion path, victim 3).
#   C. re-ask answers `review`  -> still dispatched. The shipped id:8123 A1 behaviour must not
#      regress; this is the one case that is GREEN today.
#   D. the hop's command carries `--exclude` naming `execute`, the class dispatched this run.
#   E. CONTROL: re-ask answers `idle` -> NO second unit. The widening must not manufacture work.
#      Plus the one-re-ask-per-repo-per-round bound (dc5b C2 keeps one rung per round): exactly
#      one `chain-end-reask:<repo>` hop fires even when the re-ask's own unit ends a chain.
#   F. INTENSIVE, the live hazard this widening makes reachable. relay-loop.js:4362 is the
#      fail-closed OOM gate and it keys on `unit.intensive`; the queue.push at :4617 sets no
#      such field, and the sibling id:bc2b demote path at :2044 deliberately blanks it. So a
#      widened `hard` unit for an [INTENSIVE] item would dispatch UNGATED. Asserted as a PAIR
#      under ALLOW_INTENSIVE=false, which pins the behaviour without naming a mechanism: the
#      classifier's answer carrying `intensive:""` must dispatch, and the same answer carrying
#      `intensive:"local-llm"` must NOT. Note what that requires of the implementation --
#      `parseVerdictClass` (relay-loop.js:1791) returns ONLY the verdict string, so the
#      `intensive` field of the re-ask's reply is discarded today and the hop must be widened to
#      carry it. The id:5ac6 invariant (classify-verdict.sh:427-433, intensive non-empty only for
#      execute/hard) HOLDS under demotion, so the value to carry is the RE-CLASSIFIED one for the
#      new verdict, never the suppressed lane's old claim.
#   G. the hop's command still passes mechanical-proxy.py's `_command_allowed` gate. GREEN today
#      and the routed:c555 burn class: a `jq` stage in this very pipeline made the re-ask 100%
#      dead for every repo for weeks, silently, because the proxy refused the command and the
#      model:"bash" fallback 404'd. An exclusion argument is appended to exactly that pipeline.
#
# Hermetic: mktemp -d, HOME and TMPDIR redirected into it, no git, no network, never touches the
# real ~/.claude or ~/.config/relay (id:1975 -- a test here destroyed 19 live production units by
# inheriting a default path). relay-loop.js itself has no fs/process.env access by contract.
#
# Exit 3 = could not run (missing node/file), never granted EXPECTED-RED. Exit 1 = assertions
# failed, which while roadmap:4e84 is unticked is reported EXPECTED-RED: the red IS the spec.
#
# fails-against: the defect is in the CURRENT tree, so there is no ancestor to overlay and no
# "green now" side to check -- this file is RED until the fix lands, and `verify-negative-cases.py`
# correctly parks it in the roadmap-spec bucket meanwhile. The declared mutation is the case to
# run AFTER the fix ships: it strips the exclusion argument back off the chain-end command,
# re-introducing defect (2) alone. Because the harness's stub answers the hop regardless of the
# command text, that mutation fires case D and NOTHING else, so the declaration is both the last
# and the only fired FAIL line. Case D is therefore ordered LAST in the body. RE-ANCHOR THE
# MUTATION if the fix builds the command across several lines (the id:bc2b hop at :2024-2026 is
# string concatenation, not one template literal): the verifier will then report GREEN-THERE,
# which is loud, not silent. A second case for defect (1) is deliberately NOT declared -- its
# mutation has no stable anchor until the widened predicate exists; add one in the same commit
# as the fix, anchored on whatever marker that predicate carries.
# RE-ANCHORED 2026-09-10 by the reviewer. The original declaration was
#   sed -i '/--emit unit --chain-ended/s/--exclude/--no-exclude-NEUTERED/' relay/scripts/relay-loop.js
# and the adversarial review PROVED it a complete no-op: the landed fix appends `--exclude` on a
# SEPARATE line from `--emit unit --chain-ended`, so that address never matches a line containing
# `--exclude` and the sed left the file byte-identical (diff exit 0). This file's own header had
# instructed the fix commit to re-anchor it and the fix commit did not. Anchoring on the
# `chainEndExclude` identifier instead, which is where the set is BUILT and cannot drift onto
# another line without renaming the variable.
# fails-against-mutation: sed -i 's/const chainEndExclude = \[\.\.\.dispatchedThisRound\]/const chainEndExclude = []; const _neutered = [...dispatchedThisRound]/' relay/scripts/relay-loop.js
# fails-against-assertion: (D) the chain-end re-ask passes NO --exclude naming this run's dispatches
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/lib-workflow-check.sh"   # id:62c9 workflow_node_check
JS="$ROOT/relay/scripts/relay-loop.js"
PROXY="$ROOT/relay/scripts/mechanical-proxy.py"
BUILDERS="$ROOT/tests/fixtures/loop-round-exec-harness.mjs"

for f in "$JS" "$PROXY" "$BUILDERS"; do
  [[ -f "$f" ]] || { echo "ERROR: missing $f -- cannot run"; exit 3; }
done
command -v node >/dev/null 2>&1 || { echo "ERROR: node not on PATH -- cannot run"; exit 3; }
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 not on PATH -- cannot run"; exit 3; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0; fails=0
ok()  { echo "ok: $*"; pass=$((pass+1)); }
bad() { echo "FAIL: $*"; fails=$((fails+1)); }

# ── the harness ─────────────────────────────────────────────────────────────────────────────
cat >"$TMP/harness.mjs" <<'HARNESS'
// id:4e84 -- one-repo, one-round executable harness over relay-loop.js (id:aec5 technique).
// argv: <relay-loop.js> <json-out> <wrapped-copy-path>
// env:  REASK_VERDICT, REASK_INTENSIVE, ALLOW_INT=0|1
import fs from 'node:fs'

const [SRC, OUT, WRAPPED] = process.argv.slice(2)
const REASK = process.env.REASK_VERDICT || 'hard'
const REASK_INTENSIVE = process.env.REASK_INTENSIVE || ''
const ALLOW_INTENSIVE = process.env.ALLOW_INT === '1'

let code = fs.readFileSync(SRC, 'utf8')
code = code.replace(/^export\s+const\s+meta/m, 'const meta')
code = `globalThis.__reproResult = (async () => {\n${code}\n})()\n`

const labels = [], reaskPrompts = [], logs = []
let thunkThrew = null, discoverRuns = 0

globalThis.log = (m) => { logs.push(String(m)) }
globalThis.phase = () => {}
globalThis.budget = { total: null, spent: () => 0, remaining: () => Infinity }
globalThis.workflow = async () => ({})
// once:false DELIBERATELY. Under `--once` the id:a615 wave dispatch budget is queue.length at
// the snapshot, and every chain-pushed follow-on is REFUSED and surfaced by design -- which
// would make this whole item untestable in that mode. Rounds are bounded instead by the
// discovery stub going empty after round 1, so the loop drains in 2 rounds.
globalThis.args = { STRONG_TIER: 'opus', interactive: false, fableDown: false, allowIntensive: ALLOW_INTENSIVE, afk: true, once: false }

globalThis.parallel = async (thunks) => Promise.all(thunks.map((t, i) =>
  Promise.resolve().then(t).catch((e) => { thunkThrew = `thunk[${i}]: ${e && e.stack ? e.stack : e}`; return null })))
globalThis.pipeline = async (items, ...stages) => {
  const out = []
  for (let i = 0; i < items.length; i++) {
    let v = items[i]
    try { for (const s of stages) v = await s(v, items[i], i) } catch (_) { v = null }
    out.push(v)
  }
  return out
}

globalThis.agent = async (prompt, opts = {}) => {
  const label = opts.label || ''
  labels.push(label)
  if (label.includes('discover-prelude')) {
    return {
      runId: 'relay-harness-4e84', ts: '2026-09-10T00:00:00Z',
      repos: [{ repo: 'alpha', path: '/tmp/harness/alpha', income: true }],
      skippedConfig: [], liveClaimRepos: [], injectedUnits: [], signatures: [], stopRequested: false,
    }
  }
  if (label.startsWith('discover-run')) {
    if (discoverRuns++ > 0) return { units: [], surfaced: [], skipped: [] }
    // ONE execute unit: the productive-repo shape. A successful execute changes work_sig, so the
    // id:353e/365b breaker never trips -- that is the exact complement the existing starvation
    // relief misses (docs/ledger-notes/4e84.md, "Why the existing starvation relief misses").
    return {
      units: [{
        verdict: 'execute', repo: 'alpha', path: '/tmp/harness/alpha', reason: 'harness execute unit',
        lastCkpt: '', income: true, intensive: '', open_hard_pool: 2,
        roadmap_actionable_open: 3, actionable_routine_open: 1,
      }],
      surfaced: [], skipped: [],
    }
  }
  if (label.startsWith('chain-end-reask')) {
    reaskPrompts.push(String(prompt))
    // The real hop's reply is classify-verdict.sh's stdout VERBATIM, i.e. a JSON string -- not an
    // object (parseVerdictClass stringifies and hunts for braces).
    return JSON.stringify({ verdict: REASK, reason: 'harness scripted re-ask', intensive: REASK_INTENSIVE, priority_rank: 3 })
  }
  if (label.startsWith('quota:')) return { exitCode: 0, buckets: [{ bucket: 'seven_day', pctRemaining: 95, resetTime: '2026-09-17T12:00:00Z' }] }
  const done = { contract_met: true, branch: 'relay/h', worktree: '/tmp/harness/wt', summary: 'done', review_me_count: 0, diary_fragment: 'h', handback: '', routine_open: 0, worked_ids: [] }
  // routine_open:0 matters: a non-zero value re-chains the repo (review/execute -> execute) and
  // `rechainedSameRepo` SUPPRESSES the chain-end re-ask entirely.
  if (label.startsWith('execute:') || label.startsWith('hard:') || label.startsWith('handoff:')) return done
  if (label.startsWith('review:')) return { ...done, verified_green: [], gaming_flags: [], reopened: [] }
  if (label.startsWith('integrate:')) return { merged: true, ckptTag: 'relay-ckpt-h', pushStatus: 'pushed', ts: '2026-09-10T00:00:01Z', postSig: '', openRoutine: 0, openHard: 0 }
  if (label.startsWith('provision:')) return 'PROVISION-OK /tmp/harness/wt-' + label.slice('provision:'.length)
  if (label === 'inject-take') return { units: [] }
  if (label === 'auto-reconcile-restart') return 'no dead run, skipped'
  return { contract_met: false, branch: '', worktree: '', summary: '', ok: true, units: [] }
}

fs.writeFileSync(WRAPPED, code)
let topThrow = null
try {
  await import('file://' + WRAPPED)
  await globalThis.__reproResult
} catch (e) { topThrow = String(e && e.stack ? e.stack : e) }
fs.writeFileSync(OUT, JSON.stringify({ labels, reaskPrompts, logs, thunkThrew, topThrow }))
HARNESS

cat >"$TMP/q.py" <<'QUERY'
import json, sys
j = json.load(open(sys.argv[1]))
q = sys.argv[2]
if q == 'dispatched':                       # argv[3] = label prefix
    print('yes' if any(l.startswith(sys.argv[3]) for l in j['labels']) else 'no')
elif q == 'reaskcount':
    print(sum(1 for l in j['labels'] if l.startswith('chain-end-reask')))
elif q == 'threw':
    print(j['thunkThrew'] or j['topThrow'] or '')
elif q == 'mechcmd':                        # the fenced relay-mech command of the first re-ask
    p = j['reaskPrompts'][0] if j['reaskPrompts'] else ''
    print(p.split('```relay-mech', 1)[1].split('```', 1)[0].strip() if '```relay-mech' in p else '')
elif q == 'logs':
    print('\n'.join(j['logs']))
else:
    sys.exit('unknown query ' + q)
QUERY

# run_scenario <name> <reask-verdict> <reask-intensive> <allow-int 0|1>
run_scenario() {
  local name="$1" verdict="$2" intensive="$3" allow="$4"
  HOME="$TMP/home" TMPDIR="$TMP/tmpdir" REASK_VERDICT="$verdict" REASK_INTENSIVE="$intensive" ALLOW_INT="$allow" \
    node "$TMP/harness.mjs" "$JS" "$TMP/$name.json" "$TMP/$name.wrapped.mjs" >"$TMP/$name.stdout" 2>"$TMP/$name.stderr" || true
  if [[ ! -s "$TMP/$name.json" ]]; then
    echo "ERROR: harness scenario '$name' produced no result JSON; stderr was:"
    sed 's/^/       | /' "$TMP/$name.stderr"
    exit 3
  fi
}
q() { python3 "$TMP/q.py" "$TMP/$1.json" "${@:2}"; }

mkdir -p "$TMP/home" "$TMP/tmpdir"

# ── engine guards (GREEN today; the fix edits a prompt template, so both must stay green) ────
if workflow_node_check "$JS" >/dev/null 2>&1; then
  ok "relay-loop.js still parses under the Workflow async wrapper (id:62c9)"
else
  bad "relay-loop.js does not parse under workflow_node_check -- the 4e84 edit broke the engine"
fi

if out="$(HOME="$TMP/home" TMPDIR="$TMP/tmpdir" node "$BUILDERS" "$JS" 2>&1)"; then
  ok "the id:aec5 all-builders exec harness still reaches every non-discovery prompt builder"
else
  bad "the id:aec5 all-builders exec harness broke after the 4e84 edit:
$(printf '%s\n' "$out" | sed 's/^/       | /')"
fi

# ── A. the re-ask answers `hard` -> a hard unit must be dispatched ──────────────────────────
run_scenario hard hard '' 0
t="$(q hard threw)"; [[ -z "$t" ]] || bad "(A) the harness round threw: $t"
if [[ "$(q hard dispatched 'hard:')" == yes ]]; then
  ok "(A) chain-end re-ask answering 'hard' dispatches a hard unit"
else
  bad "(A) the chain-end re-ask got verdict 'hard' for a repo whose execute was already dispatched this run, and dispatched NOTHING -- relay-loop.js:4615 accepts only 'review', so every [HARD] item stays starved (id:4e84 defect 1; 4 open [HARD] items went undispatched across 3 pools in a day). Loop said: $(q hard logs | grep -F 'chain-end re-ask' || echo '(no chain-end log line at all)')"
fi

# ── B. the re-ask answers `handoff` -> the promotion path must open ─────────────────────────
run_scenario handoff handoff '' 0
t="$(q handoff threw)"; [[ -z "$t" ]] || bad "(B) the harness round threw: $t"
if [[ "$(q handoff dispatched 'handoff:')" == yes ]]; then
  ok "(B) chain-end re-ask answering 'handoff' dispatches a handoff unit"
else
  bad "(B) the chain-end re-ask got verdict 'handoff' and dispatched NOTHING -- promotion stays structurally unreachable on any repo with open routine work (id:4e84 victim 3: id:32c3 sat unpromoted for ~3 weeks with its scope ratified and no gating edge)"
fi

# ── C. `review` must NOT regress (the shipped id:8123 A1 behaviour) ─────────────────────────
run_scenario review review '' 0
t="$(q review threw)"; [[ -z "$t" ]] || bad "(C) the harness round threw: $t"
if [[ "$(q review dispatched 'review:')" == yes ]]; then
  ok "(C) chain-end re-ask answering 'review' still dispatches a review unit (id:8123 not regressed)"
else
  bad "(C) REGRESSION -- the chain-end re-ask no longer dispatches on verdict 'review'; the shipped id:8123 chain-end audit is the mechanism ratified by meeting A1 and widening it must not cost it"
fi

# ── E. CONTROL: `idle` manufactures nothing, and the one-per-repo-per-round bound holds ─────
run_scenario idle idle '' 0
t="$(q idle threw)"; [[ -z "$t" ]] || bad "(E) the harness round threw: $t"
second_unit=no
for p in 'hard:' 'handoff:' 'review:'; do
  [[ "$(q idle dispatched "$p")" == yes ]] && second_unit=yes
done
if [[ "$second_unit" == no ]]; then
  ok "(E) CONTROL: a re-ask answering 'idle' yields no second unit -- the widening manufactures no work"
else
  bad "(E) CONTROL VIOLATED -- a re-ask answering 'idle' still produced a second unit; the widened accepted set must be exactly the DISPATCHABLE classes (relay-loop.js:1705 execute|hard|handoff, plus review), never 'anything the classifier returned'"
fi
n="$(q hard reaskcount)"
if [[ "$n" == 1 ]]; then
  ok "(E) exactly one chain-end re-ask per repo per round (chainEndReasked bound intact; dc5b C2 keeps one rung per round)"
else
  bad "(E) $n chain-end re-asks fired for one repo in one round -- the chainEndReasked bound (relay-loop.js:2885) must survive the widening, or the re-asked unit's own chain end re-asks again"
fi

# ── F. the INTENSIVE lane claim must survive onto the widened unit ──────────────────────────
# A PAIR, both under ALLOW_INTENSIVE=false, pinning behaviour rather than a mechanism:
#   F1 classifier answers intensive:""          -> the hard unit dispatches
#   F2 classifier answers intensive:"local-llm" -> it must NOT (relay-loop.js:4362 fail-closed)
run_scenario int_none hard '' 0
run_scenario int_claim hard 'local-llm' 0
t="$(q int_claim threw)"; [[ -z "$t" ]] || bad "(F) the harness round threw: $t"
f1="$(q int_none dispatched 'hard:')"
f2="$(q int_claim dispatched 'hard:')"
if [[ "$f1" == yes && "$f2" == no ]]; then
  ok "(F) the re-ask's intensive lane claim is honoured: empty dispatches, 'local-llm' is gated by the fail-closed OOM guard"
else
  bad "(F) the widened unit does not carry the classifier's intensive lane claim (intensive='' dispatched=$f1, intensive='local-llm' dispatched=$f2; both must be yes/no). relay-loop.js:4362 is the fail-closed OOM gate and it keys on unit.intensive; the queue.push at :4617 sets no such field and parseVerdictClass (:1791) throws the classifier's intensive away, so an [INTENSIVE] hard item dispatches UNGATED -- and this widening is exactly what makes hard units, hence that hazard, common. Carry the RE-CLASSIFIED value for the new verdict (id:5ac6 invariant, classify-verdict.sh:427-433), never the suppressed lane's old claim (contrast relay-loop.js:2044)"
fi

# ── G. the command must still pass mechanical-proxy.py's gate (routed:c555 burn class) ──────
cmd="$(q hard mechcmd)"
if [[ -z "$cmd" ]]; then
  bad "(G) no fenced relay-mech command found in the chain-end re-ask prompt -- the hop must stay a single mechanical command (id:907e shape)"
else
  allowed="$(python3 - "$PROXY" "$cmd" <<'PYGATE'
import importlib.util, sys
spec = importlib.util.spec_from_file_location('mp', sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
print('yes' if m._command_allowed(sys.argv[2]) else 'no')
PYGATE
)"
  if [[ "$allowed" == yes ]]; then
    ok "(G) the chain-end command still passes mechanical-proxy _command_allowed"
  else
    bad "(G) the chain-end re-ask command is REFUSED by mechanical-proxy._command_allowed, so the hop falls open to the real API and model:'bash' 404s -- the re-ask goes 100% dead SILENTLY for every repo (routed:c555, which cost weeks). Command was: $cmd"
  fi
fi

# ── D. the exclusion set, built from THIS RUN's dispatches. Ordered LAST because it is the one
#      assertion the declared mutation fires (see the header's fails-against block). ──────────
if [[ "$cmd" != *--exclude* ]]; then
  bad "(D) the chain-end re-ask passes NO --exclude naming this run's dispatches, so classify-verdict.sh re-answers 'execute' for any repo with open routine work and hard/handoff can never come back from this hop (id:4e84 defect 2). Command was: $cmd"
else
  excl="$(printf '%s' "$cmd" | sed -n "s/.*--exclude[ =]*'\{0,1\}\([a-z,]*\).*/\1/p")"
  if [[ ",$excl," == *,execute,* ]]; then
    ok "(D) the re-ask excludes 'execute' -- the class dispatched for this repo THIS RUN (excl='$excl')"
  else
    bad "(D) the chain-end re-ask passes --exclude '$excl', which does not name 'execute' -- the class this run already dispatched for this repo. The set must come from the redispatchGuard keys for the repo (relay-loop.js:1454/2598), NOT from the breaker's >3x-same-verdict condition: this round made exactly ONE dispatch, so a breaker-keyed set is empty and the re-ask is a no-op precisely on round 1, when starvation begins"
  fi
fi

echo "---"
echo "summary: $pass ok, $fails FAIL"
(( fails == 0 )) || exit 1
echo "ALL PASS: the chain-end re-ask accepts the dispatchable verdict set and excludes this run's dispatches (id:4e84)"
