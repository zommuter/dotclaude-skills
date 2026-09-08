#!/usr/bin/env bash
# No roadmap header -- defect-fix spec for TODO id:c3c1 step 4. Failures always count.
#
# Defect: `grep -c agentType relay/scripts/relay-loop.js` was 0, so every pool child was
# dispatched on the DEFAULT delegated-subagent type and paid the full ~82k preamble.
# Measured 2026-09-08: that preamble is 46% of the ~176.7k Sonnet wall, and 5 of 15 execute
# children died `Prompt is too long` in one run -- all Sonnet, 0 of 12 Opus.
#
# Clause, three parts:
#   (1) an OPT-IN knob `args.EXECUTE_AGENT_TYPE` names a custom agent type for the `execute`
#       (Sonnet) lane. Unset/blank is a STRICT no-op: `opts.agentType` must not be present on
#       the object handed to agent() at all (not `agentType: undefined`), so an unconfigured
#       run dispatches exactly as it did before this item.
#   (2) it is `execute`-ONLY. review/handoff/hard run Opus, are not dying, and must never be
#       given a custom type by this knob.
#   (3) it FAILS LOUD. A configured-but-missing type ("Agent type '<name>' not found") must
#       produce a handback naming the remedy, NEVER a silent fall-through to the default
#       agent -- a silent fallback would look like a working run while every child quietly
#       kept paying the full preamble, i.e. the misconfiguration the knob exists to fix would
#       be invisible (id:4347 no-silent-swallow). This is the EXPECTED failure, not a
#       hypothetical: a definition installed after a session started is invisible to it.
#
# fails-against: the wiring and this spec land in the same commit, so the negative case is a
# mutation that blinds the fail-loud detector while leaving every other clause intact.
# fails-against-mutation: sed -i "s|^const AGENT_TYPE_MISSING_RE = .*|const AGENT_TYPE_MISSING_RE = /zzz_mutation_never_matches_zzz/i|" relay/scripts/relay-loop.js
# fails-against-assertion: (E) a configured-but-missing agent type produced NO loud handback reason
#
# Hermetic: reads relay-loop.js, extracts its pure helpers + the two dispatch lines and runs
# them under node in a mktemp -d. No ~/.claude, no ~/.config/relay, no network, no dispatch.

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

# --- extract the two regions under test, verbatim from the source -------------------------
# (1) the pure-helper block, delimited by its own markers.
awk '/^\/\/ --- id:c3c1 pure helpers/{f=1} f{print} /^\/\/ --- end id:c3c1 pure helpers/{f=0}' \
  "$JS" > "$TMP/helpers.js"
[[ -s "$TMP/helpers.js" ]] || { echo "FAIL: could not extract the id:c3c1 pure-helper block"; exit 1; }
grep -q 'function executeAgentTypeFor' "$TMP/helpers.js" || bad "helper block lacks executeAgentTypeFor"
grep -q 'function agentTypeMissingReason' "$TMP/helpers.js" || bad "helper block lacks agentTypeMissingReason"

# (2) the dispatch-site lines that decide whether opts.agentType is set at all. Extracted
# rather than pattern-matched, so the assertions below EXECUTE the real code: a mutation that
# makes the assignment unconditional changes behaviour here, it does not merely fail a grep.
awk '/const unitAgentType = executeAgentTypeFor\(/{f=1} f{print} /opts\.agentType = unitAgentType/{if(f)exit}' \
  "$JS" > "$TMP/dispatch.js"
[[ -s "$TMP/dispatch.js" ]] || { echo "FAIL: could not extract the id:c3c1 dispatch lines"; exit 1; }

cat > "$TMP/probe.js" <<'PROBE'
const fs = require('fs')
const helpers = fs.readFileSync(process.argv[2], 'utf8')
const dispatch = fs.readFileSync(process.argv[3], 'utf8')
const src = helpers + '\n' +
  'function buildOpts (verdict, EXECUTE_AGENT_TYPE) {\n' +
  '  const unit = { verdict }\n' +
  "  const opts = { label: verdict + ':repo', phase: 'p', model: 'sonnet' }\n" +
  dispatch + '\n' +
  '  return opts\n' +
  '}\n' +
  'return { buildOpts, agentTypeMissingReason }\n'
const api = new Function(src)()
const out = []
const t = (name, cond) => out.push((cond ? 'PASS ' : 'FAIL ') + name)

// (A) OFF by default: the key must be ABSENT, not undefined.
for (const v of ['execute', 'review', 'handoff', 'hard']) {
  t('A:' + v, !('agentType' in api.buildOpts(v, '')))
}
t('A:undefined-arg', !('agentType' in api.buildOpts('execute', undefined)))
t('A:blank-arg', !('agentType' in api.buildOpts('execute', '   ')))

// (B) ON + execute: the configured type is used, trimmed.
t('B:set', api.buildOpts('execute', 'relay-implementer').agentType === 'relay-implementer')
t('B:trimmed', api.buildOpts('execute', '  relay-implementer  ').agentType === 'relay-implementer')

// (C) ON + a non-execute (Opus) verdict: still absent.
for (const v of ['review', 'handoff', 'hard']) {
  t('C:' + v, !('agentType' in api.buildOpts(v, 'relay-implementer')))
}

// (E) fail-loud detection: the harness's rejection text yields a remedy-naming reason.
const err = new Error("Agent type 'relay-implementer' not found")
const reason = api.agentTypeMissingReason(err, 'relay-implementer', 'zkm')
t('E:nonempty', !!reason)
t('E:names-type', reason.includes('relay-implementer'))
t('E:names-repo', reason.includes('zkm'))
t('E:names-install', reason.includes('make install-agents'))
t('E:names-restart', /restart/i.test(reason))
t('E:says-not-silent', /silent/i.test(reason))
t('E:string-error', !!api.agentTypeMissingReason("Agent type 'x' not found", 'x', 'r'))

// (F) knob OFF: the same error must NOT be attributed to the agent type.
t('F:off', api.agentTypeMissingReason(err, '', 'zkm') === '')

// (G) an unrelated failure must fall through to the generic failsafe, not the loud branch.
t('G:unrelated', api.agentTypeMissingReason(new Error('Prompt is too long'), 'relay-implementer', 'zkm') === '')

console.log(out.join('\n'))
PROBE

node "$TMP/probe.js" "$TMP/helpers.js" "$TMP/dispatch.js" > "$TMP/out.txt" 2> "$TMP/err.txt" || {
  echo "FAIL: the id:c3c1 probe did not run: $(head -3 "$TMP/err.txt")"
  exit 1
}

grepv() { grep -q "^PASS $1\$" "$TMP/out.txt"; }

if grepv 'A:execute' && grepv 'A:review' && grepv 'A:handoff' && grepv 'A:hard' \
   && grepv 'A:undefined-arg' && grepv 'A:blank-arg'; then
  ok "(A) unset/blank EXECUTE_AGENT_TYPE leaves opts.agentType ABSENT -- a strict no-op"
else
  bad "(A) an unconfigured run still put an agentType key on the dispatch opts"
fi

if grepv 'B:set' && grepv 'B:trimmed'; then
  ok "(B) a configured type reaches an execute unit's dispatch opts (whitespace-trimmed)"
else
  bad "(B) a configured EXECUTE_AGENT_TYPE did not reach an execute unit's dispatch opts"
fi

if grepv 'C:review' && grepv 'C:handoff' && grepv 'C:hard'; then
  ok "(C) review/handoff/hard (Opus lanes) are never given the custom type"
else
  bad "(C) the execute-only knob leaked onto an Opus lane"
fi

if grepv 'E:nonempty' && grepv 'E:names-type' && grepv 'E:names-repo' \
   && grepv 'E:names-install' && grepv 'E:names-restart' && grepv 'E:says-not-silent' \
   && grepv 'E:string-error'; then
  ok "(E) a missing agent type yields a loud reason naming type, repo, install and restart"
else
  bad "(E) a configured-but-missing agent type produced NO loud handback reason"
fi

grepv 'F:off' \
  && ok "(F) with the knob off, the same harness error is NOT blamed on the agent type" \
  || bad "(F) the loud branch fires even when EXECUTE_AGENT_TYPE is unset"

grepv 'G:unrelated' \
  && ok "(G) an unrelated dispatch error falls through to the generic failsafe" \
  || bad "(G) an unrelated dispatch error was misreported as a missing agent type"

# --- structural: the loud branch is WIRED into the dispatch catch, and it RETURNS ----------
# the branch must RETURN -- a fall-through would auto-resume a handoff into the same missing
# type and would surface a reason that never names the agent type.
h_ok=1
grep -qF 'const typeMissing = agentTypeMissingReason(e, opts.agentType, unit.repo)' "$JS" || h_ok=0
grep -qF "pushEvent('handback', { repo: unit.repo, mode: unit.verdict, reason: 'id:c3c1 execute agent type not found' })" "$JS" || h_ok=0
branch_shape="$(awk '/const typeMissing = agentTypeMissingReason\(/{f=1} f&&/state\.handbacks\.push/{h=1} f&&/scheduleStatusWrite\(state\)/{s=1} f&&h&&s&&/^ *return$/{print "OK"; exit}' "$JS")"
[[ "$branch_shape" == OK ]] || h_ok=0
[[ "$h_ok" -eq 1 ]] \
  && ok "(H) the loud branch is wired into the dispatch catch and returns without dispatching" \
  || bad "(H) the missing-agent-type branch is not wired to hand back and return"

# --- the script still parses as a Workflow script (bare `node --check` cannot judge it: the
# --- harness wraps the body in an async function, so a top-level `return` is legal there and
# --- illegal to node --check. tests/lib-workflow-check.sh does the same wrapping).
# shellcheck source=/dev/null
. "$ROOT/tests/lib-workflow-check.sh"
workflow_node_check "$JS" >/dev/null 2>&1 \
  && ok "(I) relay-loop.js still parses as a Workflow script after the id:c3c1 edit" \
  || bad "(I) relay-loop.js no longer parses after the id:c3c1 edit"

echo "test_relay_execute_agent_type_c3c1: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
