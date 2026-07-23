#!/usr/bin/env bash
# roadmap:a0b6 — the relay-loop.js verdict-source swap (flip step b). Static-structural checks
# that the LLM discovery SHARD has been replaced by the MECHANICAL runner (discover-repo.sh per
# repo) while the downstream merge/backstop contract is untouched.
#
# The mechanical discovery path (reconcile-repo.sh id:5987 + classify-repo.sh --emit unit id:3d61
# + discover-repo.sh id:64b4) is behaviorally tested elsewhere; this pins the ENGINE wiring.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JS="$SRC_DIR/relay/scripts/relay-loop.js"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$JS" ]] || fail "relay-loop.js not found at $JS"
node --check "$JS" || fail "relay-loop.js fails node --check"

# (1) The old LLM classifier shard prompt is DELETED (not commented) — it was the template-
#     literal-lint liability that crashed the pool 3×.
grep -q 'discovery SHARD classifier' "$JS" && fail "old LLM shardPrompt still present (must be DELETED)"
grep -q 'const shardPrompt' "$JS" && fail "shardPrompt binding still present (must be DELETED)"
pass "(1) old LLM shard prompt is deleted"

# (2) The mechanical runner replaces it: a runnerPrompt that dispatches the per-repo discovery.
#     id:24ec (2026-07-23): the runner is now MECHANIZED a second step — the per-repo
#     discover-repo.sh LOOP moved OUT of the LLM prompt into a deterministic wrapper,
#     discover-chunk.sh, dispatched via a single model:'bash' (```relay-mech) fence. runnerPrompt
#     is RETAINED but now BUILDS that fence (echoes the chunk into discover-chunk.sh); the per-repo
#     discover-repo.sh invocation lives in the wrapper. SAME faithful-relocation id:86a2 used for
#     the prelude — coverage MOVED to discover-chunk.sh's own test
#     (test_discover_chunk_mechanized_24ec.sh), never dropped.
CHUNK_SH="$SRC_DIR/relay/scripts/discover-chunk.sh"
grep -q 'const runnerPrompt' "$JS" || fail "runnerPrompt binding missing"
grep -q 'discover-chunk.sh' "$JS" || fail "runner does not dispatch the mechanized discover-chunk.sh (id:24ec)"
grep -q -- '--repo "$name" --path "$path"' "$CHUNK_SH" || fail "discover-chunk.sh does not invoke discover-repo.sh per repo"
pass "(2) mechanical runner dispatches discover-chunk.sh, which invokes discover-repo.sh per repo"

# (3) The agent() call uses runnerPrompt and dispatches model:'bash' (id:24ec — the shard is a
#     mechanical hop, not an LLM agent). SHARD_SCHEMA is RETAINED as the documented output contract
#     the merge code consumes, but — like id:86a2's PRELUDE_SCHEMA — is no longer PASSED to agent()
#     (a model:'bash' hop returns raw stdout, parsed by parseShard).
grep -Eq 'agent\(runnerPrompt\(chunk\)' "$JS" || fail "agent() call does not use runnerPrompt(chunk)"
grep -Eq "label: [\`']discover-run:[^\"\`']*[\`'], phase: 'Classify', model: 'bash'" "$JS" \
  || fail "the discover-run shard agent() is not dispatched model:'bash' (id:24ec)"
grep -q 'SHARD_SCHEMA' "$JS" || fail "SHARD_SCHEMA (the merge code's documented contract) is gone"
grep -q 'parseShard' "$JS" || fail "the model:'bash' shard return is not parsed (parseShard, id:24ec)"
pass "(3) runner agent dispatches model:'bash', parsed by parseShard; SHARD_SCHEMA retained as contract"

# (4) The NO-FILESYSTEM-HUNTING guard (id:612f) is carried into the wrapper (id:24ec relocation).
grep -q 'NO-FILESYSTEM-HUNTING' "$CHUNK_SH" || fail "id:612f no-filesystem-hunting guard missing from discover-chunk.sh"
pass "(4) id:612f no-filesystem-hunting guard preserved (relocated to discover-chunk.sh)"

# (5) The four JS-side backstops (A2: kept this session) are INTACT — the merge/backstop code
#     the runner feeds is unchanged.
for marker in \
  'id:000d finished-repo demote' \
  'id:9973 HARD-pool demote' \
  'id:ad74 INTENSIVE promote' \
  'id:365b re-dispatch circuit breaker'; do
  grep -q "$marker" "$JS" || fail "backstop missing after swap: $marker"
done
pass "(5) all four JS-side backstops (000d/9973/ad74/365b) intact"

# (6) The downstream merge still consumes shardResults (the runner's results) — wiring intact.
grep -q 'shardResults.forEach' "$JS" || fail "downstream merge no longer consumes shardResults"
pass "(6) downstream merge consumes the runner results"

# (7) Template-literal lint clean on the new prompt (the 3×-crash guard).
node "$SRC_DIR/relay/scripts/lint-workflow-templates.mjs" "$JS" >/dev/null 2>&1 \
  || fail "lint-workflow-templates flags the new runner prompt (template-literal hazard)"
pass "(7) new runner prompt passes the template-literal lint"

echo "ALL PASS: relay-loop.js mechanical runner swap (id:a0b6)"
