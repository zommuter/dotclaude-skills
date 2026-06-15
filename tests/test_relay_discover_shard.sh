#!/usr/bin/env bash
# roadmap:9ed4 — parallel-shard discovery. The single sequential Opus discover agent is split
# into a once-only PRELUDE (runId + the CONSUMING inject.sh take + claim.sh peek + own-repo list
# + non-own skipped) and N SHARD classifiers run in PARALLEL, then merged into the same discovery
# object shape. Static-structural checks on relay-loop.js (live discovery too expensive to run).

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JS="$SRC_DIR/relay/scripts/relay-loop.js"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$JS" ]] || fail "relay-loop.js not found"
node --check "$JS" || fail "relay-loop.js fails node --check"

# (1) prelude + shard schemas exist, and the shard-count knob.
grep -q "PRELUDE_SCHEMA" "$JS" || fail "no PRELUDE_SCHEMA"
grep -q "SHARD_SCHEMA" "$JS" || fail "no SHARD_SCHEMA"
grep -q "DISCOVER_SHARDS" "$JS" || fail "no DISCOVER_SHARDS knob"

# (2) a discover-prelude agent does the once-only global work.
grep -q "label: 'discover-prelude'" "$JS" || fail "no discover-prelude agent"

# (3) the CONSUMING inject.sh take + claim.sh peek run in the PRELUDE, and the SHARD prompt
#     explicitly DELEGATES them to the prelude (running take per shard would lose/duplicate units;
#     running peek per shard would N× the cost). Check the delegation wording, not a global count
#     (inject.sh take legitimately also appears in 6e9d's mid-round takeInjections + comments).
grep -q "inject.sh take EXACTLY ONCE" "$JS" || fail "prelude does not run inject.sh take exactly once"
grep -q "claim.sh peek once" "$JS" || fail "prelude does not run claim.sh peek once"
grep -q "do NOT run claim.sh peek yourself" "$JS" || fail "shard does not delegate claim.sh peek to the prelude"
grep -q "handled ONCE by the PRELUDE via inject.sh take" "$JS" || fail "shard does not delegate inject.sh take to the prelude"

# (4) shards fan out in PARALLEL over round-robin chunks, with a per-shard schema.
grep -q "discover-shard" "$JS" || fail "no discover-shard classifiers"
grep -Eq "await parallel\(chunks\.map" "$JS" || fail "shards are not fanned out via parallel(chunks.map(...))"
grep -q "schema: SHARD_SCHEMA" "$JS" || fail "shard agents do not use SHARD_SCHEMA"

# (5) the merge rebuilds the single discovery object: shard units/surfaced/skipped + the prelude's
#     injectedUnits and non-own skippedConfig.
grep -q "prelude.injectedUnits" "$JS" || fail "merge drops the prelude's injected units"
grep -q "prelude.skippedConfig" "$JS" || fail "merge drops the prelude's non-own skipped rollup"
grep -q "runId: prelude.runId" "$JS" || fail "merged discovery does not carry the prelude runId"
grep -q "id:9ed4" "$JS" || fail "no id:9ed4 marker"

# (6) failure handling preserved: prelude/all-shards failure → discovery stays null → round fails.
grep -q "prelude/shards failed" "$JS" || fail "no prelude/shard failure path feeding the !discovery guard"

# (7) network resilience: a FAILED shard SURFACES its repos (chunks[i]) rather than silently
#     dropping them — a transient API/connection drop must be visible, not invisible.
grep -q "discover shard failed (transient" "$JS" || fail "a failed shard does not surface its repos (silent drop on network blip)"
grep -q 'chunks\[i\]' "$JS" || fail "failed-shard surfacing does not map shard index to repos (chunks[i])"

pass "discovery is sharded with failed-shard surfacing (9ed4 + network-resilience)"
