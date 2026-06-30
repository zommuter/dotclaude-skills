#!/usr/bin/env bash
# roadmap:5eb3
# Spec for the case-b verdict split (id:5eb3; meeting 2026-06-30-2238).
#
# DECISION: a surface-only backlog (promote==0 ∧ surface>0) is NOT promotable work —
# there is nothing for an Opus `handoff` session to pick up, only mechanical lane-triage
# filing. So `classify-verdict.sh` must split the old case-b three ways:
#   promote>0                 → handoff   (real ROADMAP-promotion work for the apex turn)
#   promote==0 ∧ surface>0     → human     (lane-triage only; NO apex dispatch)
#   promote==0 ∧ surface==0     → idle      (unchanged)
# The anti-gaming invariant is preserved at the LOOP layer (the mechanical surface→
# decision-queue filer, tested separately) — `human` must still be LOUD, never silent idle.
#
# RED until classify-verdict.sh implements the split (today surface-only → handoff).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CV="$ROOT/relay/scripts/classify-verdict.sh"

[[ -x "$CV" ]] || { echo "classify-verdict.sh not found (RED): $CV"; exit 1; }
verdict_of() { "$CV" <<<"$1" | python3 -c 'import sys,json;print(json.load(sys.stdin)["verdict"])'; }

base='"repo":"x","is_finished":false,"hasRoutine":false,"substantive_unaudited":false,"open_hard_pool":0,"top_intensive":"","roadmap_open":1,"roadmap_actionable_open":0'

# promote>0 (with or without surface) → handoff: there is genuinely promotable backlog.
p='{'"$base"',"unpromoted":{"promote":2,"surface":0}}'
[[ "$(verdict_of "$p")" == "handoff" ]] || { echo "promote>0 must stay handoff"; exit 1; }
ps='{'"$base"',"unpromoted":{"promote":1,"surface":6}}'
[[ "$(verdict_of "$ps")" == "handoff" ]] || { echo "promote>0 ∧ surface>0 must be handoff"; exit 1; }

# promote==0 ∧ surface>0 → human (THE CHANGE — was handoff). No apex burns on filing-only.
s='{'"$base"',"unpromoted":{"promote":0,"surface":35}}'
[[ "$(verdict_of "$s")" == "human" ]] || { echo "surface-only (promote==0 ∧ surface>0) must be human, not handoff"; exit 1; }
s1='{'"$base"',"unpromoted":{"promote":0,"surface":1}}'
[[ "$(verdict_of "$s1")" == "human" ]] || { echo "surface==1 boundary must be human"; exit 1; }

# promote==0 ∧ surface==0 ∧ nothing else actionable → idle (unchanged).
z='{'"$base"',"unpromoted":{"promote":0,"surface":0}}'
[[ "$(verdict_of "$z")" == "idle" ]] || { echo "no backlog must be idle"; exit 1; }

# The `human` verdict must NOT outrank real dispatchable work (it is rank 5, below execute/review/hard).
hr='{"repo":"x","is_finished":false,"hasRoutine":false,"substantive_unaudited":false,"open_hard_pool":1,"top_intensive":"","roadmap_open":1,"roadmap_actionable_open":1,"unpromoted":{"promote":0,"surface":9}}'
[[ "$(verdict_of "$hr")" == "hard" ]] || { echo "open [HARD — pool] must still outrank surface→human"; exit 1; }

echo "PASS test_classify_verdict_humanlane"
