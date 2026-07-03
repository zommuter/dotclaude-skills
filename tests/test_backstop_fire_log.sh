#!/usr/bin/env bash
# roadmap:854c — instrument that the three JS-side dispatch backstops in relay-loop.js FIRE.
# Each backstop (id:000d finished-demote, id:9973 HARD-pool demote, id:ad74 INTENSIVE promote)
# already log() when it fires, but that log goes only to Workflow-sandbox stdout — nothing
# persists it, so there is NO measure of how often the backstops actually fire. b50e (delete
# the backstops) is blocked on that missing evidence (b50e GO-criterion (a)).
#
# SINK (chosen, reused — not invented): the append-only history substrate `relay-events.jsonl`,
# via the SAME pipeline dispatch/integrate/handback events already use to persist durably from
# inside the sandbox:
#     pushEvent(kind, fields)  →  pendingEvents  →  snapshotState() drains via splice
#         →  RELAY_STATUS heredoc after the ===RELAY-EVENTS=== sentinel
#         →  relay-status-publish.sh  →  relay-state-write.sh event-append  →  relay-events.jsonl
# A backstop fire is an EVENT (a thing that happened), not a current-state snapshot, so it
# belongs in the append-only event log — NOT relay.toml (toml-set) or RELAY_STATUS.md
# (status-write), both of which are rewritten each round and cannot accumulate a fire count
# over a window of runs. relay-loop.js runs inside the Workflow sandbox (no fs/net/shell), so
# pushEvent is the ONLY durable side channel available — hence reuse it, don't invent a sink.
#
# The executor's natural implementation: inside each of the three backstop blocks emit a
# `backstop`-kind event through pushEvent (directly, or via one small helper reused by all
# three) carrying WHICH backstop, the repo/unit, and the verdict it demoted/promoted.
#
# Two parts:
#   (A) source-shape — the three backstops emit a durable `backstop` event through pushEvent
#       (RED against current code, which only log()s). Static, because the Workflow engine
#       cannot be run hermetically (mirrors test_dispatch_event_sig.sh / test_relay_status_offcrit.sh).
#   (B) outcome — a synthetic backstop event round-trips through the real publish→event-append
#       pipeline and lands durably in relay-events.jsonl with the identifying fields. Proves the
#       chosen SINK actually persists the intended record shape end-to-end.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JS="$SRC_DIR/relay/scripts/relay-loop.js"
PUB="$SRC_DIR/relay/scripts/relay-status-publish.sh"
LINT="$SRC_DIR/relay/scripts/lint-workflow-templates.mjs"
pass=0 fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); return 0; }
bad() { echo "BAD: $*"; fail=$((fail+1)); return 0; }

[[ -f "$JS" ]]  || { echo "FAIL: relay-loop.js not found at $JS"; exit 1; }
[[ -x "$PUB" ]] || { echo "FAIL: relay-status-publish.sh not found/executable"; exit 1; }

# ── (A) relay-loop.js persists each backstop fire through the pushEvent → relay-events.jsonl sink ──

# A1 (load-bearing / RED): a durable `backstop` event is emitted through the canonical pushEvent
#    sink. Current backstops only call log(), so this is ABSENT → RED.
grep -q "pushEvent('backstop'" "$JS" \
  || bad "854c: no pushEvent('backstop', …) in relay-loop.js — backstop fires are not persisted to the relay-events.jsonl sink (only log()'d to sandbox stdout)"

# A2: the emitted backstop record identifies the repo it acted on and the verdict it changed.
#     Look inside the backstop-emit region (pushEvent('backstop' … up to the closing brace).
emit_region="$(grep -n "pushEvent('backstop'" "$JS" | head -1 | cut -d: -f1 || true)"
if [[ -n "$emit_region" ]]; then
  block="$(sed -n "${emit_region},$((emit_region+4))p" "$JS")"
  grep -q "repo" <<<"$block" \
    && ok "854c: backstop event carries a repo field" \
    || bad "854c: backstop event does not carry a repo field (cannot attribute a fire to a repo/unit)"
  grep -q "verdict" <<<"$block" \
    && ok "854c: backstop event carries the verdict it demoted/promoted" \
    || bad "854c: backstop event does not carry the verdict field (cannot tell demote from promote)"
else
  bad "854c: backstop event carries a repo field (no pushEvent('backstop') to inspect)"
  bad "854c: backstop event carries the verdict field (no pushEvent('backstop') to inspect)"
fi

# A3: all THREE backstops participate — each backstop's id literal ('000d','9973','ad74',
#     quoted, i.e. an event-value not a comment 'id:000d') appears on an emit-context line
#     (a direct pushEvent('backstop', {backstop:'000d',…}) OR a shared helper call
#     emitBackstopFire('000d', …)). Robust to either factoring.
for id in 000d 9973 ad74; do
  if grep -Eq "(pushEvent\('backstop'|emitBackstop[A-Za-z]*\().*'$id'|'$id'.*(pushEvent\('backstop'|emitBackstop[A-Za-z]*\()" "$JS"; then
    ok "854c: backstop id:$id fire is persisted (its tag is passed to the event sink)"
  else
    bad "854c: backstop id:$id does not emit a durable fire event — its fires remain uncounted"
  fi
done

# A4: the marker ties the wiring to the roadmap item; JS still parses + lints clean (the engine
#     forbids fs/net/shell + has a template-literal backtick hazard).
grep -q "id:854c" "$JS" \
  && ok "854c: relay-loop.js carries the id:854c marker" \
  || bad "854c: no id:854c marker in relay-loop.js tying the fire-log wiring to the roadmap item"
node --check "$JS" >/dev/null 2>&1 \
  && ok "854c: relay-loop.js still parses (node --check)" \
  || bad "854c: relay-loop.js fails node --check after the fire-log edit"
if [[ -f "$LINT" ]]; then
  node "$LINT" "$JS" >/dev/null 2>&1 \
    && ok "854c: relay-loop.js still lints clean (no template-literal violation)" \
    || bad "854c: relay-loop.js has a template-literal violation after the fire-log edit"
fi

# ── (B) the chosen SINK durably persists the backstop record shape end-to-end (outcome) ──
# A synthetic backstop event, sent through the real publish→event-append pipeline exactly as
# relay-loop.js emits events (content, then the ===RELAY-EVENTS=== sentinel, then JSON lines),
# must land appended in relay-events.jsonl with kind=backstop + backstop id + repo + verdict.
# Hermetic: sandboxed HOME + FABLES_CONFIG under mktemp; claim/burn find an empty sandbox.
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP"
export FABLES_CONFIG="$TMP/.config/relay"
mkdir -p "$FABLES_CONFIG"
STATUS="$FABLES_CONFIG/RELAY_STATUS.md"
EVENTS="$FABLES_CONFIG/relay-events.jsonl"

printf '%s\n' \
  '# RELAY_STATUS — body' \
  '===RELAY-EVENTS===' \
  '{"ts":"20260703-1200","runId":"relay-20260703-test","kind":"backstop","backstop":"000d","repo":"demo","verdict":"demote"}' \
  | "$PUB" --path "$STATUS" --run relay-20260703-test --events-path "$EVENTS" >/dev/null

if [[ -f "$EVENTS" ]] \
  && grep -q '"kind":"backstop"' "$EVENTS" \
  && grep -q '"backstop":"000d"' "$EVENTS" \
  && grep -q '"repo":"demo"' "$EVENTS" \
  && grep -q '"verdict":"demote"' "$EVENTS"; then
  ok "854c: a backstop event round-trips durably to relay-events.jsonl (kind+backstop+repo+verdict)"
else
  bad "854c: backstop event did not persist to relay-events.jsonl with the expected fields (sink broken)"
fi

echo "---- $pass ok, $fail bad ----"
[[ "$fail" -eq 0 ]] || exit 1
echo "ALL PASS: backstop-fire instrumentation persisted to relay-events.jsonl (roadmap:854c)"
