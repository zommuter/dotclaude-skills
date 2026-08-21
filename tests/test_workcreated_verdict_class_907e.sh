#!/usr/bin/env bash
# roadmap:907e
# RED SPEC for id:907e — amend id:c919's `workCreated` predicate to VERDICT-CLASS CHANGE.
#
# Today `relay-loop.js:2266` reads:
#     const workCreated = report && report.route === 'hard-split' && hbSplit > 0
# which counts ONLY a handback that added dispatchable [ROUTINE] work. A gate-writing
# handback that drops `actionable_routine_open` to 0 flips the repo's verdict class
# `execute -> review` — a REVIEW unit was created — and c919 scores that as nothing, so
# the K=2 dry counter trips and the pool quits on the exact round the verdict changed
# (loderite run relay-20260730-173701-17132, rounds 8-9).
#
# The Workflow engine cannot be run hermetically (no sandbox, no API), so the producer
# side is a SOURCE-SHAPE spec in the style of tests/test_rechain_depth_cc90.sh. Stated
# honestly: assertions 1-5 guard the SHAPE of the change (predicate widened, fresh
# classifier invocation, documented id:c3a6 cache bypass, repo-scoped before/after pair,
# oscillation guard), not its runtime behaviour.
#
# Assertion 6 is NOT source-shape: it runs the real classify-verdict.sh over two fixture
# states and proves the class flip the predicate must observe. It PASSES today — it is
# the premise-guard, included so the spec is not purely grep-shaped and so a future
# cascade edit that destroys the premise fails loudly here.
#
# TRIANGULATION (id:108e): six assertions over five distinct concerns, one of them a real
# behavioural fixture, so satisfying this by special-casing a single grep is harder than
# doing the work.
#
# RED until relay-loop.js's workCreated producer is amended. roadmap:907e unticked
# => EXPECTED-RED.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JS="$ROOT/relay/scripts/relay-loop.js"
CV="$ROOT/relay/scripts/classify-verdict.sh"
[[ -f "$JS" ]] || { echo "FAIL: relay-loop.js not found at $JS"; exit 1; }
[[ -x "$CV" ]] || { echo "FAIL: classify-verdict.sh not found/executable at $CV"; exit 1; }

fail() { echo "FAIL: $*"; exit 1; }
pass() { echo "PASS: $*"; }

# The producer BLOCK: the 40 lines around the `workCreated` assignment. Every source-shape
# assertion below is scoped to this window rather than the whole file, so an unrelated
# mention of "classify-verdict" elsewhere in relay-loop.js cannot satisfy the spec.
line="$(head -1 < <(grep -n 'const workCreated' "$JS") | cut -d: -f1 || true)"
[[ -n "$line" ]] || fail "(0) no 'const workCreated' assignment found in relay-loop.js — the c919 producer moved; re-derive this spec before editing it"
lo=$(( line > 40 ? line - 40 : 1 ))
hi=$(( line + 40 ))
block="$(sed -n "${lo},${hi}p" "$JS")"

# 1. The OLD predicate is no longer the whole story: the bare route==='hard-split' test
#    must not be the sole determinant of workCreated any more.
if grep -Eq "const workCreated = report && report\.route === 'hard-split' && hbSplit > 0" "$JS"; then
  fail "(1) workCreated is still the unamended c919 predicate (route==='hard-split' && hbSplit>0) — a gate-writing handback that flips the verdict class still scores as nothing (id:907e)"
fi
pass "(1) the c919 route-only predicate is gone"

# 2. Clause (i) — the predicate re-derives the verdict from a DIRECT classifier
#    invocation, not from the round's cached discovery verdict.
grep -Eq 'classify-repo\.sh|classify-verdict\.sh' <<<"$block" \
  || fail "(2) the workCreated site does not invoke classify-repo.sh/classify-verdict.sh — without a fresh classification the predicate cannot see a verdict-class change (id:907e clause i)"
pass "(2) the predicate site invokes the classifier directly"

# 3. Clause (i), second half — the id:c3a6 signature cache MUST be addressed in-source.
#    Reading the cached/reused verdict makes the answer permanently "unchanged" and the
#    whole amendment ships as a silent no-op (the banned detector-without-resolution
#    anti-pattern). The executor must say how the cache is bypassed, citing c3a6.
grep -q 'c3a6' <<<"$block" \
  || fail "(3) the workCreated site does not mention the id:c3a6 discovery cache — the cache bypass must be documented at the site or the amendment is a silent no-op (id:907e clause i)"
pass "(3) the id:c3a6 cache bypass is documented at the site"

# 4. Clause (ii) — REPO-WIDE scoping: a before/after verdict-class pair, not per-handback
#    causality. In-repo parallelism (id:1f4f) lets another unit flip the class in the same
#    round, so single-report attribution under-counts.
befores="$(head -5 < <(grep -Eoi '[A-Za-z_]*(verdictClass|classBefore|verdict_before|priorVerdict|verdictWas)[A-Za-z_]*' <<<"$block") || true)"
[[ -n "$befores" ]] \
  || fail "(4) no verdict-class before/after identifier at the workCreated site — the predicate must ask 'did THIS ROUND change THIS REPO's verdict class', not 'did this handback cause it' (id:907e clause ii)"
pass "(4) a repo-scoped verdict-class comparison exists ($(tr '\n' ' ' <<<"$befores"))"

# 5. Clause (iii) — OSCILLATION GUARD. Verdict-class flapping must count as dry, or at
#    minimum produce its own distinguishable exit reason, so it fails loudly rather than
#    livelocking the pool (--fabled F6).
grep -Eqi 'oscillat|flapp?ing' "$JS" \
  || fail "(5) no oscillation/flapping guard anywhere in relay-loop.js — a repo whose class alternates execute<->review keeps the pool alive forever (id:907e clause iii)"
pass "(5) an oscillation guard is present"

# 6. BEHAVIOURAL premise-guard (passes today): the class flip the predicate must observe.
#    Same repo state, only actionable_routine_open differs -> verdict execute vs review.
mk() { printf '{"hasRoutine":%s,"actionable_routine_open":%s,"substantive_unaudited":true,"open_hard_pool":0,"dirty":false,"diverged":false}' "$1" "$2"; }
v_before="$(mk true 3  | bash "$CV" | python3 -c 'import json,sys; print(json.load(sys.stdin)["verdict"])')"
v_after="$( mk false 0 | bash "$CV" | python3 -c 'import json,sys; print(json.load(sys.stdin)["verdict"])')"
[[ "$v_before" == "execute" ]] \
  || fail "(6) premise broken: 3 actionable [ROUTINE] items no longer classify as 'execute' (got '$v_before') — re-derive id:907e before implementing it"
[[ "$v_after" == "review" ]] \
  || fail "(6) premise broken: dropping actionable_routine_open to 0 with substantive_unaudited no longer classifies as 'review' (got '$v_after') — re-derive id:907e before implementing it"
pass "(6) premise holds: the gate-write flips the repo's verdict class $v_before -> $v_after"

# 7. The engine still parses and lints clean after the edit.
node --check "$JS" >/dev/null 2>&1 || fail "(7) node --check failed on relay-loop.js after the 907e edit"
LINT="$ROOT/relay/scripts/lint-workflow-templates.mjs"
[[ -f "$LINT" ]] || fail "(7) lint-workflow-templates.mjs not found; cannot verify template safety"
if ! out="$(node "$LINT" "$JS" 2>&1)"; then
  fail "(7) relay-loop.js has a template-literal violation after the 907e edit:
$out"
fi
pass "(7) relay-loop.js parses and lints clean"

echo "PASS test_workcreated_verdict_class_907e"
