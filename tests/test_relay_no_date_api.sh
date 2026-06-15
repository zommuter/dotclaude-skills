#!/usr/bin/env bash
# Defect-fix test (no roadmap item). The Workflow runtime FORBIDS new Date() / Date.now() /
# .toISOString() — ShimDate throws to keep runs deterministic/resumable. On 2026-06-15 a
# logGamingFlags() (id:3826) built a telemetry entry with `new Date().toISOString()` synchronously,
# which threw out of integrate() and crashed the ENTIRE pool (every relaunch failed at the first
# review integration). Timestamps must come from an agent (e.g. integrate result.ts / state.ts),
# never from the JS runtime. This guard asserts no LIVE Date API call survives in relay-loop.js.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JS="$ROOT/relay/scripts/relay-loop.js"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$JS" ]] || fail "relay-loop.js not found"
node --check "$JS" || fail "relay-loop.js fails node --check"

# Flag any new Date( / Date.now( / .toISOString( that is NOT inside a comment line.
hits=$(grep -nE 'new Date\(|Date\.now\(|\.toISOString\(' "$JS" | grep -vE ':[[:space:]]*//' || true)
if [[ -n "$hits" ]]; then
  fail "forbidden Workflow Date API in relay-loop.js (ShimDate throws → pool crash):
$hits"
fi
pass "no live new Date()/Date.now()/.toISOString() in relay-loop.js (Workflow ShimDate safe)"
