#!/usr/bin/env bash
# roadmap:5ac6
# Spec for the INTENSIVE verdict-layer fail-safe (id:5ac6, SAFETY; meeting 2026-06-30-2238).
#
# DECISION: encode [INTENSIVE] as a FLAG on the verdict object, NOT a new verdict value.
# [INTENSIVE] is an orthogonal resource axis that is OPERATIVE only on relay-dispatchable
# lanes (ROUTINE / HARD — pool); gather's `top_intensive` already excludes human-gated
# items (id:a707). classify-verdict.sh copies `top_intensive` VERBATIM to an `intensive`
# field beside an UNCHANGED verdict.
#
# INVARIANT (the free safety property the orthogonality reframe yields):
#   intensive != "" ⇒ verdict ∈ {execute, hard}
# i.e. the flag can never ride a non-dispatchable verdict (human/handoff/idle/blocked/review),
# because top_intensive is "" for human-gated work. A regression of the loop-level
# --allow-intensive partition can then no longer OOM-dispatch intensive work undetected
# (the JS-side fail-closed pre-dispatch assertion is the third layer, tested in the relay-loop JS specs).
#
# RED until classify-verdict.sh emits the `intensive` field (today it drops top_intensive).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CV="$ROOT/relay/scripts/classify-verdict.sh"

[[ -x "$CV" ]] || { echo "classify-verdict.sh not found (RED): $CV"; exit 1; }
field() { "$CV" <<<"$1" | python3 -c "import sys,json;o=json.load(sys.stdin);print(o.get('$2',''))"; }

# 1. Output object carries an `intensive` field (string), always present (even when "").
plain='{"repo":"x","is_finished":false,"hasRoutine":true,"substantive_unaudited":false,"open_hard_pool":0,"top_intensive":"","roadmap_open":1,"roadmap_actionable_open":1,"unpromoted":{"promote":0,"surface":0}}'
"$CV" <<<"$plain" | python3 -c 'import sys,json;o=json.load(sys.stdin);assert "intensive" in o, f"missing intensive field: {o}";assert isinstance(o["intensive"],str), "intensive must be a string"' \
  || { echo "output must always carry a string `intensive` field"; exit 1; }
[[ "$(field "$plain" intensive)" == "" ]] || { echo "no intensive resource ⇒ intensive must be \"\""; exit 1; }

# 2. A [ROUTINE] [INTENSIVE — local-llm] repo → verdict execute AND intensive=local-llm (flag rides execute).
ri='{"repo":"x","is_finished":false,"hasRoutine":true,"substantive_unaudited":false,"open_hard_pool":0,"top_intensive":"local-llm","roadmap_open":1,"roadmap_actionable_open":1,"unpromoted":{"promote":0,"surface":0}}'
[[ "$(field "$ri" verdict)"   == "execute"   ]] || { echo "routine-intensive must keep verdict=execute (flag, not a verdict value)"; exit 1; }
[[ "$(field "$ri" intensive)" == "local-llm" ]] || { echo "top_intensive must be copied verbatim to intensive"; exit 1; }

# 3. A [HARD — pool] [INTENSIVE — local-llm] repo → verdict hard AND intensive=local-llm.
hi='{"repo":"x","is_finished":false,"hasRoutine":false,"substantive_unaudited":false,"open_hard_pool":1,"top_intensive":"local-llm","roadmap_open":1,"roadmap_actionable_open":1,"unpromoted":{"promote":0,"surface":0}}'
[[ "$(field "$hi" verdict)"   == "hard"      ]] || { echo "pool-intensive must keep verdict=hard"; exit 1; }
[[ "$(field "$hi" intensive)" == "local-llm" ]] || { echo "pool-intensive must carry intensive=local-llm"; exit 1; }

# 4. INVARIANT: intensive!="" ⇒ verdict ∈ {execute,hard}. top_intensive is "" for human-gated
#    work (id:a707), so the flag can never ride human/handoff/idle. Assert across a matrix.
python3 - "$CV" <<'PY' || { echo "INVARIANT violated: intensive set on a non-dispatchable verdict"; exit 1; }
import json, subprocess, sys, itertools
cv = sys.argv[1]
def run(d):
    out = subprocess.run([cv], input=json.dumps(d), capture_output=True, text=True, check=True).stdout
    return json.loads(out)
# Sweep states; top_intensive non-empty must ONLY co-occur with execute/hard.
for hasR, unaud, ohp, ti, promote, surface in itertools.product(
        [True,False],[True,False],[0,1],["","local-llm"],[0,1],[0,1]):
    d = {"repo":"x","is_finished":False,"hasRoutine":hasR,"substantive_unaudited":unaud,
         "open_hard_pool":ohp,"top_intensive":ti,"roadmap_open":2,"roadmap_actionable_open":2,
         "unpromoted":{"promote":promote,"surface":surface}}
    o = run(d)
    if o.get("intensive",""):
        assert o["verdict"] in ("execute","hard"), f"intensive on non-dispatchable verdict {o['verdict']}: {d}"
print("invariant-ok")
PY

echo "PASS test_classify_verdict_intensive"
