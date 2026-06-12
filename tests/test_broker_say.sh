#!/usr/bin/env bash
# roadmap:3b02 — broker-curl.sh gains a batched `say` subcommand:
# reads plain-text lines from stdin, POSTs ONE /event per line (per-line renderer
# painting preserved), --opener marks the first line with kind=opener, jq-safe
# escaping, quiet stdout, empty lines skipped.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BROKER_CURL="$ROOT/meeting/broker-curl.sh"

tmp="$(mktemp -d)"
SRV=""
cleanup() { [[ -n "$SRV" ]] && kill "$SRV" 2>/dev/null; rm -rf "$tmp"; }
trap cleanup EXIT

python3 "$ROOT/tests/fixtures/mock-broker.py" \
  --port-file "$tmp/port" --log "$tmp/requests.jsonl" &
SRV=$!

for _ in $(seq 1 50); do [[ -s "$tmp/port" ]] && break; sleep 0.1; done
[[ -s "$tmp/port" ]] || { echo "mock broker did not start"; exit 1; }
PORT="$(cat "$tmp/port")"

# Three persona lines (middle input has an empty line that must be skipped);
# text includes apostrophe, double quote, and backslash to prove jq escaping.
input=$'🏗️ **Archie:** *(opening test-item)*\n😈 **Riku:** don'\''t ship it\n\n🧭 **Petra:** "quote" and back\\slash'

out="$(printf '%s' "$input" | "$BROKER_CURL" "$PORT" testsid say --opener)" \
  || { echo "say subcommand failed (exit $?)"; exit 1; }

# stdout must stay quiet on success
if [[ -n "$out" ]]; then
  echo "expected quiet stdout, got: $out"
  exit 1
fi

events="$(grep '"path": "/event"' "$tmp/requests.jsonl" || true)"
count="$(printf '%s' "$events" | grep -c . || true)"
if [[ "$count" -ne 3 ]]; then
  echo "expected 3 /event POSTs (one per non-empty line), got $count"
  exit 1
fi

# Line 1: opener kind + session injected
echo "$events" | sed -n 1p | jq -e '.body.kind == "opener"' >/dev/null \
  || { echo "first event must carry kind=opener"; exit 1; }
echo "$events" | sed -n 1p | jq -e '.body.session == "testsid"' >/dev/null \
  || { echo "session must be injected into the body"; exit 1; }
echo "$events" | sed -n 1p | jq -e '.body.text | contains("Archie")' >/dev/null \
  || { echo "first event must be the Archie opener line"; exit 1; }

# Line 2: apostrophe survives, no opener kind
echo "$events" | sed -n 2p | jq -e '.body.text == "😈 **Riku:** don'\''t ship it"' >/dev/null \
  || { echo "second event text mangled (apostrophe escaping)"; exit 1; }
echo "$events" | sed -n 2p | jq -e '.body.kind == null' >/dev/null \
  || { echo "only the first line may carry kind=opener"; exit 1; }

# Line 3: double quote + backslash survive
echo "$events" | sed -n 3p | jq -e '.body.text == "🧭 **Petra:** \"quote\" and back\\slash"' >/dev/null \
  || { echo "third event text mangled (quote/backslash escaping)"; exit 1; }

# Existing endpoints must be untouched: status still works
"$BROKER_CURL" "$PORT" testsid status | jq -e '.subscribers == 1' >/dev/null \
  || { echo "status endpoint regressed"; exit 1; }

# broker-mode.md must route the discussion example through `say`
grep -qE 'broker-curl\.sh .*say' "$ROOT/meeting/broker-mode.md" \
  || { echo "broker-mode.md Discussion section not updated to use say"; exit 1; }

echo ok
