#!/usr/bin/env bash
# Defect-fix test (no roadmap item). The Workflow sandbox FORBIDS Node APIs and nondeterministic
# built-ins — new Date()/Date.now()/.toISOString() (ShimDate throws), process.* / require() / fs.*
# (no Node API access), Math.random() (nondeterministic). On 2026-06-15 the pool's autonomous
# id:3826 logGamingFlags() shipped TWO such violations in one function — `new Date().toISOString()`
# AND `process.env.HOME` — each threw SYNCHRONOUSLY out of integrate() and crashed the ENTIRE pool
# at the first review integration (the .catch only guards the agent promise, not the sync throw).
# The pool can't test against the live Workflow, so it keeps reintroducing these — this guard is
# the backstop. Values must come from agents (shell-expanded paths, agent-returned timestamps),
# never the JS runtime.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JS="$ROOT/relay/scripts/relay-loop.js"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$JS" ]] || fail "relay-loop.js not found"
node --check "$JS" || fail "relay-loop.js fails node --check"

# Flag any Workflow-forbidden API that is NOT inside a comment line (the `:[[:space:]]*//`
# filter drops whole-line comments, where these are legitimately named in warnings).
PATTERN='new Date\(|Date\.now\(|\.toISOString\(|process\.|require\(|Math\.random\(|\bfs\.'
hits=$(grep -nE "$PATTERN" "$JS" | grep -vE ':[[:space:]]*//' || true)
if [[ -n "$hits" ]]; then
  fail "forbidden Workflow-sandbox API in relay-loop.js (throws synchronously → pool crash):
$hits"
fi
pass "no live Date/process/require/fs/Math.random in relay-loop.js (Workflow-sandbox safe)"
