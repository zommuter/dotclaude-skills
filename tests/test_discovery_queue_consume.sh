#!/usr/bin/env bash
# No matching ROADMAP item exists for id:7402 (it is a TODO-only item, gated on id:9d97 —
# see docs/meeting-notes/2026-07-07-1228-relay-discovery-off-workflow.md, decision D3), so this
# file intentionally omits a `# roadmap:XXXX` header — its failures always count per CLAUDE.md's
# Testing section ("Defect-fix tests without a roadmap item omit the header").
#
# id:7402 (D3) wires the relay discovery runner's agent() recipe to CONSUME the mechanical
# work-queue the id:9d97 producer (discover-repos-mechanical.sh) writes, when a FRESH snapshot
# is present, and to fall back to the pre-existing live discover-repo.sh exec path otherwise —
# and LABELS the residual queue-read as the known-remaining LLM surface (no-silent-swallow,
# per the meeting note's D3). relay-loop.js runs inside a Workflow sandbox with no fs/net/
# subprocess (id:2ec4), so the only way to change "what the discovery runner reads" is to change
# the AGENT RECIPE (the prompt text), not JS-side file access — this test is therefore
# structural (static grep on the recipe text), mirroring test_relay_discover_shard.sh's pattern
# for the same reason (live discovery too expensive/impossible to run hermetically).

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JS="$SRC_DIR/relay/scripts/relay-loop.js"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$JS" ]] || fail "relay-loop.js not found"
node --check "$JS" || fail "relay-loop.js fails node --check"

# (a) the recipe references the discovery-queue dir + a freshness (TTL) check.
grep -q "DISCOVERY_QUEUE_LATEST" "$JS" || fail "no DISCOVERY_QUEUE_LATEST constant (queue path not wired)"
grep -q "discovery-queue/latest.json" "$JS" || fail "recipe does not reference the id:9d97 drop-dir's latest.json"
grep -q "DISCOVERY_QUEUE_FRESH_SECS" "$JS" || fail "no freshness TTL constant"
grep -Eq "newermt" "$JS" || fail "recipe does not perform a freshness (mtime/TTL) check before trusting the queue"

# (b) the live discover-repo.sh fallback path is still present, unchanged in substance —
#     a live pool with the id:9d97 timer NOT installed/enabled (the shipped default) must keep
#     behaving exactly as before this change (non-breaking by construction).
grep -q "discover-repo.sh --repo" "$JS" || fail "live discover-repo.sh fallback exec path is gone"
grep -Eq "FALL BACK to the live exec path" "$JS" || fail "recipe does not explicitly fall back to the live exec path when the queue is missing/stale"
grep -q "NO-FILESYSTEM-HUNTING GUARD" "$JS" || fail "runner prompt lost its NO-FILESYSTEM-HUNTING GUARD"

# (c) the residual queue-read is LABELED as the known-remaining LLM surface (no-silent-swallow,
#     D3), both in the recipe text itself and surfaced in the round log (buildRelayStatus /
#     log() — visible to the operator, not buried).
grep -q "RESIDUAL LLM SURFACE" "$JS" || fail "recipe does not label the queue-read as the residual LLM surface"
grep -q "id:7402/D3" "$JS" || fail "residual-read label does not point at the D3 deferral (id:7402)"
grep -Eq "log\(\`relay-loop: id:7402 discover-run agent\(\) dispatch" "$JS" || fail "no round-log line surfacing the id:7402 residual-surface label"

pass "discovery runner recipe consumes the id:9d97 mechanical queue when fresh, falls back to the live exec path when absent/stale, and labels the residual agent() read as the known-remaining LLM surface (id:7402/D3)"
