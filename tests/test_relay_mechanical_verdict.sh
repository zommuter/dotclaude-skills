#!/usr/bin/env bash
# roadmap:d310 — the 'mechanical' verdict must ROUND-TRIP through the relay pool as a
# POOL-INERT, SURFACED-but-never-dispatched verdict, mirroring EXACTLY how 'human' is handled.
#
# classify-verdict.sh already EMITS verdict='mechanical' (priority_rank 6) for a repo whose only
# remaining backlog is open [MECHANICAL] items, but before id:7616 relay-loop.js's shard schema
# OMITTED 'mechanical' from its verdict enum and PRIORITY — so the first such repo produced a
# verdict its own runner's structured output could not validate, and it was silently dropped.
#
# The CRITICAL INVARIANT (classify-verdict.sh:180): a host daemon dispatches mechanical work
# (A3, gated), NEVER the LLM pool. So 'mechanical' must be REPRESENTABLE (schema enum + PRIORITY)
# and SURFACED (RELAY_STATUS), but NEVER DISPATCHABLE — exactly like 'human' (present in the enum
# + PRIORITY rank 5, but ABSENT from PHASE_BY_VERDICT and never spawns an executor child).
#
# This test pins all four properties: (A) classify-verdict emits it (round-trip source); (B) it
# validates against the shard verdict enum (round-trip); (C) it ranks at 6, matching
# classify-verdict's priority_rank; (D) it is SURFACED into RELAY_STATUS Queued with a pool-inert
# reason; (E) it is NEVER dispatched — absent from PHASE_BY_VERDICT and pulled out of `actionable`
# before the dispatch loop, with no child agent spawned (contrast 'human', which DOES spawn a
# mechanical file-surface agent).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JS="$ROOT/relay/scripts/relay-loop.js"
CV="$ROOT/relay/scripts/classify-verdict.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$JS" ]] || fail "relay-loop.js not found at $JS"
[[ -x "$CV" ]] || fail "classify-verdict.sh not found/executable at $CV"

# --- (A) round-trip SOURCE: classify-verdict.sh emits verdict=mechanical, priority_rank=6 -----
# A repo whose only open backlog is [MECHANICAL] (nothing higher in the D3 cascade) → mechanical.
MECH_IN='{"repo":"x","is_finished":false,"hasRoutine":false,"actionable_routine_open":0,"substantive_unaudited":false,"open_hard_pool":0,"open_mechanical":2,"top_intensive":"","roadmap_open":2,"roadmap_actionable_open":0,"unpromoted":{"promote":0,"surface":0}}'
MECH_OUT="$("$CV" <<<"$MECH_IN")"
CV_VERDICT="$(python3 -c 'import sys,json;print(json.load(sys.stdin)["verdict"])' <<<"$MECH_OUT")"
CV_RANK="$(python3 -c 'import sys,json;print(json.load(sys.stdin)["priority_rank"])' <<<"$MECH_OUT")"
CV_INTENSIVE="$(python3 -c 'import sys,json;print(json.load(sys.stdin)["intensive"])' <<<"$MECH_OUT")"
[[ "$CV_VERDICT" == "mechanical" ]] || fail "classify-verdict.sh did not emit verdict=mechanical for a [MECHANICAL]-only backlog (got '$CV_VERDICT')"
[[ "$CV_RANK" == "6" ]] || fail "classify-verdict.sh mechanical priority_rank must be 6 (got '$CV_RANK')"
# id:5ac6 invariant: intensive != "" => verdict in {execute,hard}; mechanical must keep intensive ""
[[ "$CV_INTENSIVE" == "" ]] || fail "classify-verdict.sh mechanical verdict must keep intensive='' (id:5ac6 invariant), got '$CV_INTENSIVE'"
pass "(A) classify-verdict.sh emits verdict=mechanical, priority_rank=6, intensive='' (round-trip source)"

# --- (B) ROUND-TRIP: the mechanical verdict validates against the shard verdict enum ----------
# The shard runner (SHARD_SCHEMA) reuses DISCOVER_SCHEMA.properties.units, whose verdict enum
# is the ONE gate on a shard's structured output. Extract it from source and assert the verdict
# classify-verdict emitted in (A) is a MEMBER — i.e. it round-trips (validates), never dropped.
node -e '
  const fs = require("fs");
  const src = fs.readFileSync(process.argv[1], "utf8");
  const m = src.match(/verdict:\s*\{\s*enum:\s*(\[[^\]]*\])\s*\}/);
  if (!m) { console.error("no verdict enum found in relay-loop.js"); process.exit(1); }
  const en = eval(m[1]);
  const v = process.argv[2];
  if (!en.includes(v)) { console.error(`verdict "${v}" NOT in shard schema enum ${JSON.stringify(en)} — shard output would fail validation`); process.exit(1); }
  // human must also still be present (regression guard for the whole pool-inert family).
  if (!en.includes("human")) { console.error("human verdict dropped from enum"); process.exit(1); }
' "$JS" "$CV_VERDICT" || fail "(B) mechanical verdict does not validate against the shard schema enum"
pass "(B) the emitted mechanical verdict is a MEMBER of the shard verdict enum (round-trips, not dropped)"

# --- (C) RANK 6: PRIORITY[mechanical] === 6, matching classify-verdict's priority_rank ---------
node -e '
  const fs = require("fs");
  const src = fs.readFileSync(process.argv[1], "utf8");
  const m = src.match(/const\s+PRIORITY\s*=\s*(\{[^}]*\})/);
  if (!m) { console.error("no PRIORITY object found"); process.exit(1); }
  const P = eval("(" + m[1] + ")");
  const rank = parseInt(process.argv[2], 10);
  if (P.mechanical === undefined) { console.error("PRIORITY has no mechanical key — a mechanical unit would sort as NaN and corrupt the queue order"); process.exit(1); }
  if (P.mechanical !== rank) { console.error(`PRIORITY.mechanical=${P.mechanical} != classify-verdict priority_rank ${rank}`); process.exit(1); }
  // mechanical is the LOWEST priority (highest rank) — below human, matching the D3 cascade tail.
  if (!(P.mechanical > P.human)) { console.error(`PRIORITY.mechanical(${P.mechanical}) must rank below human(${P.human})`); process.exit(1); }
' "$JS" "$CV_RANK" || fail "(C) PRIORITY.mechanical is not 6 / not below human"
pass "(C) PRIORITY.mechanical === 6 (matches classify-verdict priority_rank), ranks below human"

# --- (D) SURFACED: mechanical units are surfaced into RELAY_STATUS Queued with a pool-inert reason
# The state.queued mapping must include a mechanicalSurfaced spread carrying a clear pool-inert
# reason, so an operator SEES the [MECHANICAL] backlog rather than it vanishing silently.
grep -q "mechanicalSurfaced.map" "$JS" \
  || fail "(D) mechanicalSurfaced is never spread into state.queued — the verdict would be silently dropped"
grep -qi "pool-inert" "$JS" \
  || fail "(D) surfaced mechanical reason does not say 'pool-inert'"
grep -qi "host daemon" "$JS" \
  || fail "(D) surfaced mechanical reason does not name the host daemon (A3) that actually dispatches it"
pass "(D) mechanical units are surfaced into RELAY_STATUS Queued with a pool-inert / host-daemon reason"

# --- (E) NEVER DISPATCHED: absent from PHASE_BY_VERDICT + pulled from `actionable`, no child -----
# Mirror 'human' EXACTLY: like human, mechanical must NOT be a key in PHASE_BY_VERDICT (the
# per-verdict dispatch phase map) and must be extracted from `actionable` before the dispatch loop.
node -e '
  const fs = require("fs");
  const src = fs.readFileSync(process.argv[1], "utf8");
  const m = src.match(/const\s+PHASE_BY_VERDICT\s*=\s*(\{[^}]*\})/);
  if (!m) { console.error("no PHASE_BY_VERDICT object found"); process.exit(1); }
  const PH = eval("(" + m[1] + ")");
  if ("mechanical" in PH) { console.error("mechanical IS a key in PHASE_BY_VERDICT — CONTRACT VIOLATION: it would be dispatched as an executor child"); process.exit(1); }
  // regression: human must ALSO stay absent (the whole pool-inert family).
  if ("human" in PH) { console.error("human leaked into PHASE_BY_VERDICT (regression)"); process.exit(1); }
' "$JS" || fail "(E) mechanical (or human) is a PHASE_BY_VERDICT key — it would be dispatched"
pass "(E1) mechanical is ABSENT from PHASE_BY_VERDICT (never routed to a dispatch phase, like human)"

# The extraction block pulls mechanical units OUT of `actionable` before the dispatch loop so no
# child is ever spawned for them (the queue = [...actionable] is what the dispatch pool drains).
grep -q "u.verdict === 'mechanical'" "$JS" \
  || fail "(E) relay-loop.js does not partition mechanical units out of the dispatch queue"
# Assert the partition ASSIGNS actionable = the non-mechanical remainder (units are removed, not
# merely inspected). Both the human and the mechanical filters reassign `actionable`.
grep -q "actionable = nonMechanical" "$JS" \
  || fail "(E) mechanical units are not removed from actionable (actionable = nonMechanical missing)"
pass "(E2) mechanical units are pulled OUT of actionable before dispatch (no executor child spawned)"

# Contrast guard: unlike 'human' (which spawns a file-surface-decisions.sh agent), 'mechanical'
# must NOT spawn ANY agent — the host daemon (A3, gated) owns its dispatch. The mechanical block
# must not call agent()/file-surface for mechanical units. Assert the mechanical partition block
# contains no agent( call (scoped check on the id:7616 block).
python3 - "$JS" <<'PYEOF'
import sys, re
src = open(sys.argv[1]).read()
i = src.find("id:7616 — mechanical-verdict surface")
if i < 0:
    sys.exit("no id:7616 mechanical-verdict surface block found")
# take the block from the marker to the next top-level state.runId refresh (its end anchor)
end = src.find("Refresh the cross-round accumulator", i)
if end < 0:
    end = i + 2000
block = src[i:end]
if "agent(" in block:
    sys.exit("the mechanical-surface block spawns an agent() — mechanical must NEVER dispatch (host daemon A3 owns it)")
if "file-surface" in block:
    sys.exit("the mechanical-surface block calls file-surface — that is the HUMAN path; mechanical has no filing step")
PYEOF
pass "(E3) the mechanical-surface block spawns NO agent (contrast human's file-surface) — host daemon owns dispatch"

echo "all checks passed"
