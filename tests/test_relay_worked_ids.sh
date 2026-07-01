#!/usr/bin/env bash
# roadmap:de69 — surface the ROADMAP/TODO id a relay unit is/was working on. /workflows used to
# show each agent as ${verdict}:${repo} with NO item id. Two-part fix:
#   (a) live/partial — append a KNOWN-at-dispatch id (injected --item, or a hard unit's bounded
#       item) to the agent label → `execute:zkm-stt id:09a3`.
#   (b) durable — the child REPORT returns worked_ids; the integrator propagates them into the
#       RELAY_STATUS "Completed this run" line, the relay-events integrate event, and the
#       ckpt-tag checkpoint message (since plain execute/review pick the item INSIDE the child,
#       the id only exists post-run).
# Structural assertions on relay-loop.js (a Workflow script — not directly runnable here).
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JS="$SRC_DIR/relay/scripts/relay-loop.js"
pass=0 fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); return 0; }
bad() { echo "BAD: $*"; fail=$((fail+1)); return 0; }
[[ -f "$JS" ]] || { echo "FAIL: relay-loop.js missing"; exit 1; }

grep -q "id:de69" "$JS" || bad "relay-loop.js: no id:de69 marker"

# (a) dispatch-time label enrichment: a known item id is appended to the unit label.
grep -q "const knownItem = unit.inject_item || unit.item || ''" "$JS" \
  || bad "(a) no known-item resolution at dispatch (inject_item/item)"
grep -qF 'knownItem ? ` id:${knownItem}`' "$JS" \
  || bad "(a) unit label does not append the known item id"
ok "(a) dispatch label appends a known-at-dispatch item id (injected/hard) — id:de69"

# (b) REPORT_SCHEMA carries worked_ids.
grep -q "worked_ids: { type: 'array'" "$JS" || bad "(b) REPORT_SCHEMA missing worked_ids"
# children are instructed to return worked_ids (both the main + resume return lines).
[[ "$(grep -c "worked_ids (id:de69" "$JS")" -ge 2 ]] \
  || bad "(b) child return instructions do not ask for worked_ids in both prompts"
ok "(b) REPORT_SCHEMA + child return instructions include worked_ids"

# (b) integrator computes workedIds with fallbacks (explicit → review verified/reopened → dispatch id).
# (Reconciled 2026-07-01 with the asIdArray coercion fix: children sometimes returned a
# JSON-STRING where the schema expects an array — spreading a string iterates characters and
# wrote ids:["[","]"] into integrate events, run relay-20260701-202806-14640. Same resolution
# order: explicit worked_ids → review verified_green∪reopened → dispatch-time id.)
grep -q "let workedIds = asIdArray(report.worked_ids)" "$JS" || bad "(b) integrator does not read report.worked_ids"
grep -qF 'workedIds = [...new Set([...asIdArray(report.verified_green), ...asIdArray(report.reopened)])]' "$JS" \
  || bad "(b) no review verified-green∪reopened fallback for worked_ids"
grep -q "const asIdArray = (v) => {" "$JS" && grep -q "return Array.isArray(p) ? p.filter(Boolean).map(String) : \[\]" "$JS" \
  || bad "(b) missing asIdArray string-coercion guard (ids:[\"[\",\"]\"] regression)"
grep -q "const idSuffix = workedIds.length ?" "$JS" || bad "(b) no idSuffix built for the checkpoint message"
ok "(b) integrator resolves workedIds (explicit → review verified/reopened → dispatch-time id)"

# (b) durable propagation: ckpt-tag message + RELAY_STATUS completed line + integrate event.
grep -q 'ckpt-tag.sh ${unit.path} -m "${report.summary}${idSuffix}"' "$JS" \
  || bad "(b) checkpoint message does not include the worked-id suffix"
grep -q "substantive: unitIsSubstantive(unit.verdict, report), workedIds })" "$JS" \
  || bad "(b) state.completed entry does not carry workedIds"
grep -q "push: result.pushStatus || '?', ids: workedIds })" "$JS" \
  || bad "(b) integrate event does not carry the worked ids"
grep -q 'ids=${r.workedIds.join' "$JS" \
  || bad "(b) RELAY_STATUS Completed line does not render the worked ids"
ok "(b) worked ids propagate to ckpt-tag message + RELAY_STATUS + integrate event"

echo "test_relay_worked_ids: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
