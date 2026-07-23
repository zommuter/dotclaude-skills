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

# (3) the CONSUMING inject.sh take + claim.sh peek run in the PRELUDE. The per-repo classifier
#     is now the MECHANICAL discover-run runner (id:a0b6 flip), which does not judge or peek
#     itself at all: it invokes discover-repo.sh --repo once per repo and its NO-FILESYSTEM-
#     HUNTING GUARD explicitly restricts it to running ONLY that one script — so it structurally
#     cannot re-run claim.sh peek or inject.sh take (delegation by omission + an explicit guard,
#     replacing the old shard prompt's "do NOT run claim.sh peek yourself" wording).
#     id:86a2 (2026-07-23): the discover-prelude is now MECHANIZED — a model:'bash' dispatch of
#     discover-prelude.sh — so the CONSUMING inject.sh take + the claim.sh peek moved from the
#     prelude PROMPT into that wrapper. relay-loop.js dispatches it; assert the invocations in
#     their new home (the wrapper), each run exactly once.
PRELUDE_SH="$SRC_DIR/relay/scripts/discover-prelude.sh"
grep -q "discover-prelude.sh" "$JS" || fail "relay-loop.js no longer dispatches the mechanized discover-prelude.sh"
[[ "$(grep -c '"\$INJECT_SH" take' "$PRELUDE_SH")" == "1" ]] || fail "discover-prelude.sh does not run inject.sh take EXACTLY once (CONSUMING)"
grep -q '"\$CLAIM_SH" peek' "$PRELUDE_SH" || fail "discover-prelude.sh does not run claim.sh peek"
#     id:24ec (2026-07-23): the discover-run SHARD is now ALSO mechanized — a model:'bash'
#     dispatch of discover-chunk.sh — so the per-repo `discover-repo.sh --repo` LOOP + the
#     NO-FILESYSTEM-HUNTING guarantee moved from the runner PROMPT in relay-loop.js INTO that
#     wrapper (the SAME faithful-relocation as the prelude: coverage MOVED to the wrapper's own
#     test, test_discover_chunk_mechanized_24ec.sh — never dropped). Assert them in their new home.
CHUNK_SH="$SRC_DIR/relay/scripts/discover-chunk.sh"
grep -q "discover-chunk.sh" "$JS" || fail "relay-loop.js no longer dispatches the mechanized discover-chunk.sh (id:24ec)"
grep -Eq 'DISCOVER_REPO=.*discover-repo\.sh' "$CHUNK_SH" || fail "discover-chunk.sh does not reference discover-repo.sh"
grep -q -- '--repo "$name" --path "$path"' "$CHUNK_SH" || fail "discover-chunk.sh does not invoke discover-repo.sh --repo/--path per repo"
grep -q "NO-FILESYSTEM-HUNTING" "$CHUNK_SH" || fail "discover-chunk.sh does not carry the NO-FILESYSTEM-HUNTING guarantee"

# (4) shards fan out in PARALLEL over round-robin chunks. Since id:24ec mechanized the shard to a
#     model:'bash' dispatch of discover-chunk.sh (raw stdout, parsed by parseShard), SHARD_SCHEMA
#     is no longer PASSED to agent() (mirroring id:86a2 dropping PRELUDE_SCHEMA from the prelude
#     agent()); it is RETAINED as the documented output contract the wrapper must emit.
grep -q "discover-shard" "$JS" || fail "no discover-shard classifiers"
grep -Eq "await parallel\(chunks\.map" "$JS" || fail "shards are not fanned out via parallel(chunks.map(...))"
grep -q "SHARD_SCHEMA" "$JS" || fail "SHARD_SCHEMA (the documented shard output contract) is gone"
grep -Eq "label: [\`']discover-run:[^\"\`']*[\`'], phase: 'Classify', model: 'bash'" "$JS" \
  || fail "the discover-run shard is not dispatched model:'bash' (id:24ec mechanization)"
grep -q "parseShard" "$JS" || fail "the model:'bash' shard return is not parsed (parseShard, id:24ec)"

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
