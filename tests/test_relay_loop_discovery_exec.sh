#!/usr/bin/env bash
# Defect-fix test (no roadmap item). EXECUTES the relay-loop.js discovery dispatch under node
# with stubbed Workflow globals — the capability the rest of the suite lacks. Every other
# relay-loop.js test is `node --check` (syntax) + grep (source-text) only; none RUN the Workflow
# body, so a RUNTIME crash in the dispatch ships GREEN.
#
# The burn this guards (2026-07-07): commit e776fb0 put an unescaped backtick pair `\`.timer\``
# inside the discover-run prompt TEMPLATE LITERAL. The inner backtick closed the template early,
# making the tail a tagged-template call on `undefined` → "undefined is not a function", thrown
# synchronously in EVERY discovery shard thunk → the whole autonomous pool died at discovery with
# zero dispatches. `node --check` passed (a tagged template is valid grammar; it only fails when
# the undefined tag is invoked at runtime) and every grep passed. Sibling of test_relay_no_date_api.sh
# (same "sandbox can't be unit-tested → static checks miss runtime throws" class), but this one
# actually executes the dispatch, so it catches ANY synchronous throw in the discovery path, not
# just a denylisted API name.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JS="$ROOT/relay/scripts/relay-loop.js"
HARNESS="$ROOT/tests/fixtures/discovery-exec-harness.mjs"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$JS" ]]      || fail "relay-loop.js not found"
[[ -f "$HARNESS" ]] || fail "discovery-exec-harness.mjs not found"
command -v node >/dev/null 2>&1 || { echo "SKIP: node not available"; exit 0; }

node --check "$JS" || fail "relay-loop.js fails node --check"

out="$(node "$HARNESS" "$JS" 2>&1)"; rc=$?
if [[ $rc -ne 0 ]]; then
  fail "discovery dispatch did NOT execute cleanly (runtime throw in the Workflow body):
$out"
fi
echo "$out" | grep -q '^OK:' || fail "harness did not report success:
$out"
pass "relay-loop.js discovery dispatch executes under node (no synchronous throw in shard thunks)"
