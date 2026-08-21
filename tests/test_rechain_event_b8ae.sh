#!/usr/bin/env bash
# roadmap:b8ae
# Static source-shape assertion: mechanize the review->execute (or execute->execute) re-chain
# signal — the observe-only remainder ("watch the log line") went uncaught for six weeks
# (RELAY_LOG/diary/events checked 2026-07-02 and again 2026-08-14, both empty). Owner-decided
# fix (2026-08-14, /relay human .): "Mechanize it — emit an event". This asserts the re-chain
# site in relay-loop.js pushes a durable relay-events.jsonl entry naming the repo, the
# re-enqueued verdict, and that it was a re-chain, instead of relying on a human reading a log.
# Cannot run the Workflow engine hermetically (no sandbox, no API) — mirrors the source-shape
# pattern of test_dispatch_event_sig.sh / test_rechain_depth_cc90.sh.
# RED until relay-loop.js's rechain block calls pushEvent. roadmap:b8ae unticked => EXPECTED-RED.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JS="$ROOT/relay/scripts/relay-loop.js"
[[ -f "$JS" ]] || { echo "FAIL: relay-loop.js not found at $JS"; exit 1; }

fail() { echo "FAIL: $*"; exit 1; }
pass() { echo "PASS: $*"; }

# 1. A pushEvent call exists inside the rechain block (after rechainedSameRepo = true, before
#    the id:8123 chain-end-reask section), so the event is emitted exactly when a re-chain
#    actually happens (not speculatively / unconditionally elsewhere).
block="$(awk '/rechainedSameRepo = true/,/id:8123 — CHAIN-END/' "$JS")"
grep -q "pushEvent(" < <(echo "$block") \
  || fail "(1) no pushEvent(...) call inside the rechain block (id:b8ae)"
pass "(1) rechain block calls pushEvent"

# 2. The event names the repo.
grep -Eq "pushEvent\([^)]*repo:\s*unit\.repo" < <(echo "$block") \
  || fail "(2) the rechain pushEvent does not name the repo (repo: unit.repo) (id:b8ae)"
pass "(2) rechain event carries repo"

# 3. The event names the RE-ENQUEUED verdict — the queue.push above always re-enqueues
#    verdict: 'execute', so the event must say so explicitly (not just echo unit.verdict,
#    which is the FROM side of the chain, not the re-enqueued TO side).
grep -Eq "pushEvent\([^)]*'execute'" < <(echo "$block") \
  || fail "(3) the rechain pushEvent does not name the re-enqueued verdict ('execute') (id:b8ae)"
pass "(3) rechain event carries the re-enqueued verdict"

# 4. The event is distinguishable as a RE-CHAIN (not a generic dispatch/verdict event) —
#    either a dedicated event kind or an explicit chain-depth field on the payload.
grep -Eq "pushEvent\('rechain'|chainDepth" < <(echo "$block") \
  || fail "(4) the rechain pushEvent carries nothing marking it as a re-chain (kind or chainDepth) (id:b8ae)"
pass "(4) rechain event is marked as a re-chain"

# 5. The engine still parses and still lints clean.
node --check "$JS" >/dev/null 2>&1 || fail "(5) node --check failed on relay-loop.js after the b8ae edit"
LINT="$ROOT/relay/scripts/lint-workflow-templates.mjs"
[[ -f "$LINT" ]] || fail "(5) lint-workflow-templates.mjs not found; cannot verify template safety"
if ! out="$(node "$LINT" "$JS" 2>&1)"; then
  fail "(5) relay-loop.js has a template-literal violation after the b8ae edit:
$out"
fi
pass "(5) relay-loop.js parses and lints clean"

echo "PASS test_rechain_event_b8ae"
