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

# (d) FINDING 1 (2026-07-07 Fable second-opinion): the FRESH-queue path must NOT drop the live
#     reconcile side-effects. Before the fix the queue path only `cat latest.json` + copied the
#     verdict, so reconcile-repo.sh (ff-merge / uv.lock commit / worktree reap-park / live-claims
#     filtering) NEVER ran that round. The recipe must exec reconcile-repo.sh LIVE on the
#     queue path too — only the CLASSIFY verdict comes from the queue.
grep -q "reconcile-repo.sh --repo" "$JS" \
  || fail "recipe never invokes reconcile-repo.sh — the fresh-queue path drops the live reconcile side-effects (FINDING 1 regression)"
# the reconcile exec must be tied to the fresh-queue (CASE A) path, carrying --live-claims so
# in-flight worktrees are protected (the queue itself carries no live-claims context).
grep -Eq "reconcile-repo.sh --repo <repo> --path <path> --runid \\\$\{prelude.runId\} --live-claims" "$JS" \
  || fail "reconcile-repo.sh on the queue path is not passed --runid/--live-claims (live-claims protection lost)"
grep -q "STILL reconcile LIVE" "$JS" \
  || fail "recipe does not state the queue path STILL reconciles live (verdict-from-queue, reconcile-live split)"
# the round-log line must reflect that reconcile runs live every round (not 'prefer queue over exec').
grep -q "RECONCILE runs LIVE every round" "$JS" \
  || fail "round-log line does not surface that reconcile runs live every round on the queue path"

# (e) id:4860 CONTENT-ADDRESS — the CASE A copy is gated on queue_sig == live sig.
#     The producer (discover-repos-mechanical.sh) stamps each queue entry with the repo's
#     discover-sig.sh value (queue_sig); the runner copies a verdict ONLY when that byte-matches
#     the repo's LIVE sig carried in the chunk. This structurally closes the stale-verdict
#     (executor committed after the snapshot) + went-dirty-after-snapshot gaps that mtime alone
#     let through. Structural pins on the recipe text (can't run the LLM hermetically):
grep -q "id:4860" "$JS" || fail "no id:4860 marker (content-addressed CASE A copy)"
grep -q "queue_sig" "$JS" || fail "recipe/schema never references queue_sig (content-address field)"
# the chunk JSON carries each repo's LIVE sig so the runner can compare
grep -Eq "sig: sigByRepo\[r\.repo\]" "$JS" || fail "chunk does not carry each repo's live sig (sigByRepo) for the CASE A comparison"
# CASE A gates the verbatim copy on a BYTE-IDENTICAL sig equality
grep -q "BYTE-IDENTICAL to this repo's \"sig\"" "$JS" || fail "CASE A does not gate the copy on queue_sig == live sig (byte equality)"
# missing/mismatched queue_sig → fall to the CASE B live path for THAT repo (not a stale copy)
grep -Eq "queue_sig is MISSING or does NOT byte-match" "$JS" || fail "CASE A does not treat a missing/mismatched queue_sig as a fall-to-live-path case"
# the residual-read label is updated to say content-addressing SHRINKS the trust (mangle canary)
grep -q "Content-addressing SHRINKS the trust" "$JS" || fail "residual LLM surface label not updated to note the content-address/mangle-canary shrink (D3 wording, id:4860)"

pass "discovery runner recipe (id:4860): CASE A copies a queue verdict only when queue_sig byte-matches the repo's live sig (else the live path); chunk carries the live sig; residual-read label notes the mangle canary"

pass "discovery runner recipe: queue path takes only the CLASSIFY verdict from the id:9d97 queue but STILL runs reconcile-repo.sh LIVE (with --live-claims) for the side-effecting half; falls back to the full live discover-repo.sh exec when the queue is absent/stale; residual agent() read labeled (id:7402/D3, FINDING 1 fix)"
