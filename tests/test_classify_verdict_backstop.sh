#!/usr/bin/env bash
# roadmap:c79e
# Spec for folding the id:000d / id:ad74 JS-side relay-loop.js runtime backstops' per-round
# logic NATIVELY into classify-verdict.sh (id:c79e, b50e forward path).
#
# BACKGROUND (b50e CLOSED NO-GO 2026-07-06, forward window relay-20260704-173233-19787):
# the two JS backstops fired repeatedly on the SAME repos every round:
#   - id:000d (finished-repo demote): zelegator — 0 open ROADMAP items (is_finished=true),
#     yet re-proposed with a stale/inconsistent actionable_routine_open/open_hard_pool count
#     that would otherwise route it to execute/hard. is_finished is the independently-derived,
#     holistic "truly nothing to do" signal and must override those counts DEFENSIVELY so the
#     cascade falls through to promote/surface/idle instead.
#   - id:ad74 (INTENSIVE promote): isochrone — carries an open `[INTENSIVE — r5-jvm]` (id:11c3)
#     item that gather-repo-state.sh surfaces via `top_intensive`, but a stale/undercounted
#     actionable_routine_open/open_hard_pool left classify-verdict.sh emitting `idle` instead
#     of `execute` with the `intensive` flag set.
#
# This test asserts classify-verdict.sh ITSELF (not the JS loop) now catches both conditions
# deterministically, so the JS backstops fire 0x natively (the b50e forward-path re-open gate).
# The JS-side id:000d/id:ad74/id:9973 guards in relay-loop.js are NOT deleted by this change —
# they remain a belt-and-suspenders backstop (b50e's NO-GO proved them load-bearing); this test
# only specs the NEW native mechanical coverage.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CV="$ROOT/relay/scripts/classify-verdict.sh"

[[ -x "$CV" ]] || { echo "classify-verdict.sh not found (RED): $CV"; exit 1; }
field() { "$CV" <<<"$1" | python3 -c "import sys,json;o=json.load(sys.stdin);print(o.get('$2',''))"; }

# --- Condition (a): id:000d finished-repo authority (the zelegator fixture) ---------------
# is_finished=true but open_hard_pool/actionable_routine_open are STALE (nonzero, disagreeing
# with is_finished) AND there is promotable TODO backlog (case h). is_finished must win:
# verdict must NOT be execute/hard; it must fall through to the promote>0 -> handoff branch.
zelegator_stale_hard='{"repo":"zelegator","is_finished":true,"hasRoutine":false,"substantive_unaudited":false,"open_hard_pool":1,"actionable_routine_open":1,"top_intensive":"","unpromoted":{"promote":2,"surface":0}}'
v="$(field "$zelegator_stale_hard" verdict)"
[[ "$v" != "execute" && "$v" != "hard" ]] || { echo "FAIL (a): is_finished=true must never yield verdict=$v (000d native fold)"; exit 1; }
[[ "$v" == "handoff" ]] || { echo "FAIL (a): is_finished=true + promotable backlog must fall through to handoff, got $v"; exit 1; }

# Same repo shape but with ZERO promotable/surface backlog too -> must land idle, never execute/hard.
zelegator_drained='{"repo":"zelegator","is_finished":true,"hasRoutine":false,"substantive_unaudited":false,"open_hard_pool":1,"actionable_routine_open":1,"top_intensive":"","unpromoted":{"promote":0,"surface":0}}'
v2="$(field "$zelegator_drained" verdict)"
[[ "$v2" == "idle" ]] || { echo "FAIL (a): finished + drained backlog must be idle, got $v2"; exit 1; }

# --- Condition (b): id:ad74 INTENSIVE native promote (the isochrone fixture) --------------
# top_intensive is set (an open [INTENSIVE — r5-jvm] item exists, gather already excludes
# human-gated lanes id:a707) but actionable_routine_open/open_hard_pool UNDERCOUNT it (both 0).
# classify-verdict.sh must promote natively: verdict=execute AND intensive=r5-jvm (never idle).
isochrone='{"repo":"isochrone","is_finished":false,"hasRoutine":false,"substantive_unaudited":false,"open_hard_pool":0,"actionable_routine_open":0,"top_intensive":"r5-jvm","unpromoted":{"promote":0,"surface":0}}'
[[ "$(field "$isochrone" verdict)"   == "execute" ]] || { echo "FAIL (b): undercounted INTENSIVE item must promote to execute (ad74 native fold)"; exit 1; }
[[ "$(field "$isochrone" intensive)" == "r5-jvm"  ]] || { echo "FAIL (b): intensive flag must ride the promoted execute verdict"; exit 1; }

# --- Regression: dirty/diverged parity guards (rank 0) still outrank BOTH native folds ----
zelegator_dirty='{"repo":"zelegator","is_finished":true,"hasRoutine":false,"substantive_unaudited":false,"open_hard_pool":1,"actionable_routine_open":1,"top_intensive":"","unpromoted":{"promote":2,"surface":0},"dirty":true,"dirty_lock_only":false}'
[[ "$(field "$zelegator_dirty" verdict)" == "blocked" ]] || { echo "FAIL: dirty tree must still outrank the is_finished native fold"; exit 1; }

echo "PASS test_classify_verdict_backstop"
