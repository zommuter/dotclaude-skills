#!/usr/bin/env bash
# roadmap:85df
# Spec for relay/scripts/classify-verdict.sh (id:85df; meeting 2026-06-30-1523 DP1).
#
# A PURE-FUNCTION deterministic verdict classifier: gather-repo-state JSON (with an
# `unpromoted` scan summary folded in) on stdin → {verdict,reason,evidence,ambiguous}
# on stdout. It REPLACES the LLM discover-shard as the PRIMARY verdict source — the
# shard fires ONLY when this script emits verdict "AMBIGUOUS" (DP1/DP2). The classifier
# is SIDE-EFFECT-FREE: it reads its JSON input and emits a verdict; it never mutates a
# ledger, claims a lease, or dispatches (DP6 hard property).
#
# verdict ∈ {execute, review, hard, handoff, human, idle, AMBIGUOUS}.
# Cases below are seeded from the REAL 2026-06-30 discovery failures (TODO id:4d8e
# corpus a/b/h). The lint-layer cases (c) tag/prose disagreement and (d) free-typed
# INTENSIVE are loud-ERRORs, not verdicts — they live in tests/test_roadmap_lint_tagprose.sh
# (# roadmap:297b), asserted by exit-code + stderr, never a verdict label.
#
# RED until classify-verdict.sh exists and passes (it does not yet).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CV="$ROOT/relay/scripts/classify-verdict.sh"

[[ -x "$CV" ]] || { echo "classify-verdict.sh not yet implemented (RED): $CV"; exit 1; }

verdict_of() { "$CV" <<<"$1" | python3 -c 'import sys,json;print(json.load(sys.stdin)["verdict"])'; }

# --- Case (a) id:fb7f — phantom `hard` ----------------------------------------------------
# The `[HARD — pool]` token appears ONLY inside back-tick'd re-lane PROSE, so the deterministic
# open_hard_pool count is 0. A repo with no actionable routine/unaudited/pool work must NOT be `hard`.
a='{"repo":"x","is_finished":false,"hasRoutine":false,"substantive_unaudited":false,"open_hard_pool":0,"top_intensive":"","roadmap_open":2,"roadmap_actionable_open":0,"unpromoted":{"promote":0,"surface":0}}'
[[ "$(verdict_of "$a")" != "hard" ]] || { echo "case a: open_hard_pool=0 must NOT yield hard"; exit 1; }

# inverse: a genuine open [HARD — pool] item (open_hard_pool>=1, nothing earlier in D3 order) → hard
ha='{"repo":"x","is_finished":false,"hasRoutine":false,"substantive_unaudited":false,"open_hard_pool":1,"top_intensive":"","roadmap_open":1,"roadmap_actionable_open":1,"unpromoted":{"promote":0,"surface":0}}'
[[ "$(verdict_of "$ha")" == "hard" ]] || { echo "case a inverse: open_hard_pool>=1 must be hard"; exit 1; }

# --- Case (b) id:9014 — effectively-drained ROADMAP ---------------------------------------
# ROADMAP open count is 1, but its only open item is @manual/human-lane (roadmap_actionable_open=0),
# while unpromoted-scan reports a real TODO backlog. Must route to `handoff` (promote/surface the
# backlog), NEVER "human"/"idle" that hides the backlog.
b='{"repo":"x","is_finished":false,"hasRoutine":false,"substantive_unaudited":false,"open_hard_pool":0,"top_intensive":"","roadmap_open":1,"roadmap_actionable_open":0,"unpromoted":{"promote":0,"surface":35}}'
[[ "$(verdict_of "$b")" == "handoff" ]] || { echo "case b: drained(@manual-only)+surface backlog must be handoff"; exit 1; }

# --- Case (h) zelegator — "finished" must consult the scan ---------------------------------
# is_finished=true (0-open ROADMAP, clean, no unaudited) BUT unpromoted-scan reports promote/surface
# items → must be `handoff`, never `idle`. The finished guard must consult the scan before declaring done.
h='{"repo":"x","is_finished":true,"hasRoutine":false,"substantive_unaudited":false,"open_hard_pool":0,"top_intensive":"","roadmap_open":0,"roadmap_actionable_open":0,"unpromoted":{"promote":1,"surface":6}}'
[[ "$(verdict_of "$h")" == "handoff" ]] || { echo "case h: finished + unpromoted backlog must be handoff, not idle"; exit 1; }

# truly finished: is_finished AND nothing unpromoted → idle
f='{"repo":"x","is_finished":true,"hasRoutine":false,"substantive_unaudited":false,"open_hard_pool":0,"top_intensive":"","roadmap_open":0,"roadmap_actionable_open":0,"unpromoted":{"promote":0,"surface":0}}'
[[ "$(verdict_of "$f")" == "idle" ]] || { echo "truly finished (scan clean) must be idle"; exit 1; }

# D3 verdict-class order: unaudited work outranks fresh hard work (review before hard).
ru='{"repo":"x","is_finished":false,"hasRoutine":false,"substantive_unaudited":true,"open_hard_pool":1,"top_intensive":"","roadmap_open":1,"roadmap_actionable_open":1,"unpromoted":{"promote":0,"surface":0}}'
[[ "$(verdict_of "$ru")" == "review" ]] || { echo "D3: unaudited commits must outrank hard (review first)"; exit 1; }

# open [ROUTINE] work → execute (outranks everything)
ex='{"repo":"x","is_finished":false,"hasRoutine":true,"substantive_unaudited":true,"open_hard_pool":1,"top_intensive":"","roadmap_open":3,"roadmap_actionable_open":3,"unpromoted":{"promote":0,"surface":0}}'
[[ "$(verdict_of "$ex")" == "execute" ]] || { echo "D3: open routine work must be execute"; exit 1; }

# --- Output contract: valid JSON carrying all four keys + a D3 priority-class rank ---------
out="$("$CV" <<<"$f")"
python3 -c '
import sys,json
o=json.load(sys.stdin)
for k in ("verdict","reason","evidence","ambiguous"):
    assert k in o, f"missing key {k}: {o}"
assert isinstance(o["evidence"], list), "evidence must be a list of pointers"
assert isinstance(o["ambiguous"], bool), "ambiguous must be a bool"
' <<<"$out" || { echo "contract: must emit {verdict,reason,evidence[],ambiguous}"; exit 1; }

echo "PASS test_classify_verdict"
