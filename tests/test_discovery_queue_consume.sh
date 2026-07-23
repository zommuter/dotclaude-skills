#!/usr/bin/env bash
# No `# roadmap:XXXX` header — a defect-fix / invariant guard whose failures ALWAYS count
# (CLAUDE.md Testing section).
#
# HISTORY: this file originally pinned the id:7402 (D3) CASE-A recipe — the discover-run agent's
# LLM read that CONSUMED the id:9d97 mechanical work-queue (a `find -newermt` freshness check +
# `cat latest.json` + a sig-gated content-address copy of the classify verdict), falling back to
# the live discover-repo.sh exec path otherwise. That recipe was the "residual LLM surface."
#
# id:24ec (2026-07-23) MECHANIZED the discover-run shard: the whole per-chunk loop is now ONE
# deterministic `model:'bash'` dispatch of discover-chunk.sh (CASE B — per-repo discover-repo.sh
# reconcile+classify, concatenated; zero agents, no LLM). Per the ROADMAP goal ("eliminate the
# id:7402 residual LLM surface"), the CASE-A LLM queue-consume recipe is therefore ELIMINATED
# from relay-loop.js — there is no longer an LLM read to guard here. The CASE-A content-address
# COPY of the queue verdict is a GATED FOLLOW-ON, id:6eb3, which will re-add it MECHANICALLY
# inside discover-chunk.sh (via its reserved --queue-latest / --queue-fresh-secs flags) as a
# model:'bash' hop — NOT as an LLM recipe. So the CASE-A recipe-text assertions this file used to
# carry are RELOCATED to id:6eb3's future test (they cannot pass against relay-loop.js today
# because the recipe is intentionally gone). Coverage MOVED, not silently dropped.
#
# What this file NOW guards (all TRUE post-id:24ec):
#   (1) the shard is the mechanized CASE-B model:'bash' discover-chunk.sh dispatch;
#   (2) FINDING 1 (2026-07-07 Fable second-opinion — the fresh-queue path must NOT drop the live
#       reconcile side-effects) is PRESERVED BY CONSTRUCTION: with CASE A gone there is NO queue
#       shortcut, so reconcile-repo.sh runs LIVE every round for EVERY repo (discover-chunk.sh
#       calls discover-repo.sh WITHOUT --no-reconcile). The regression FINDING 1 guarded against
#       is now structurally impossible;
#   (3) the id:4860 content-address SUBSTRATE (the queue-sig mangle canary, the DISCOVERY_QUEUE_*
#       constants, and the per-repo LIVE sig carried in the chunk) is RETAINED in relay-loop.js —
#       NOT ripped out — so id:6eb3 can wire CASE A back in without re-deriving it.
# relay-loop.js runs in a Workflow sandbox with no fs/net/subprocess (id:2ec4), so these are
# static structural greps on the recipe/dispatch text (mirroring test_relay_discover_shard.sh).

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JS="$SRC_DIR/relay/scripts/relay-loop.js"
CHUNK_SH="$SRC_DIR/relay/scripts/discover-chunk.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$JS" ]] || fail "relay-loop.js not found"
[[ -x "$CHUNK_SH" ]] || fail "discover-chunk.sh not found/executable (id:24ec CASE-B wrapper)"
node --check "$JS" || fail "relay-loop.js fails node --check"

# (1) CASE-B mechanization: the discover-run shard is a model:'bash' dispatch of discover-chunk.sh.
grep -q "discover-chunk.sh" "$JS" || fail "relay-loop.js no longer dispatches discover-chunk.sh (id:24ec CASE-B shard)"
grep -Eq "label: [\`']discover-run:[^\"\`']*[\`'], phase: 'Classify', model: 'bash'" "$JS" \
  || fail "the discover-run shard is not dispatched model:'bash' (id:24ec mechanization)"
grep -q "parseShard" "$JS" || fail "the model:'bash' shard return is not parsed (parseShard, id:24ec)"
pass "(1) discover-run is the mechanized CASE-B model:'bash' discover-chunk.sh dispatch (id:24ec)"

# (2) FINDING 1 preserved by construction — reconcile runs LIVE for EVERY repo, every round.
#     discover-chunk.sh invokes discover-repo.sh WITHOUT --no-reconcile (the LIVE path that runs
#     reconcile-repo.sh's ff-merge / uv.lock commit / worktree reap-park / live-claims filtering),
#     and threads --live-claims + --runid so in-flight worktrees are protected. There is no queue
#     shortcut that could skip reconcile (the CASE-A gap FINDING 1 guarded against), so the
#     regression is now structurally impossible.
# The actual discover-repo.sh invocation line (carries --repo "$name" --path "$path") must NOT
# pass --no-reconcile — that is the LIVE reconcile+classify path (FINDING 1). (A comment in the
# header legitimately explains WHY --no-reconcile is absent, so match the exec line specifically.)
invoke_line="$(grep -n -- '--repo "$name" --path "$path"' "$CHUNK_SH" | head -1)"
[[ -n "$invoke_line" ]] || fail "discover-chunk.sh does not invoke discover-repo.sh per repo"
echo "$invoke_line" | grep -q -- '--no-reconcile' \
  && fail "discover-chunk.sh's discover-repo.sh invocation passes --no-reconcile — CASE B must be the LIVE path (FINDING 1)"
grep -q -- '--live-claims "$live_claims"' "$CHUNK_SH" || fail "discover-chunk.sh does not thread --live-claims (in-flight worktree protection lost)"
grep -Eq "NO --no-reconcile|LIVE reconcile" "$CHUNK_SH" || fail "discover-chunk.sh does not document the LIVE reconcile contract (FINDING 1)"
pass "(2) FINDING 1 preserved by construction: discover-chunk.sh runs discover-repo.sh LIVE (reconcile every round, --live-claims), no queue shortcut"

# (3) the id:4860 content-address SUBSTRATE is RETAINED for the gated id:6eb3 CASE-A re-add —
#     the DISCOVERY_QUEUE_* constants, the per-repo LIVE sig in the chunk, and the queue_sig
#     mangle canary must NOT have been ripped out by the CASE-A recipe removal.
grep -q "DISCOVERY_QUEUE_LATEST" "$JS" || fail "DISCOVERY_QUEUE_LATEST constant was ripped out (id:6eb3 CASE-A substrate lost)"
grep -q "DISCOVERY_QUEUE_FRESH_SECS" "$JS" || fail "DISCOVERY_QUEUE_FRESH_SECS constant was ripped out (id:6eb3 CASE-A substrate lost)"
grep -q "id:4860" "$JS" || fail "the id:4860 content-address canary was ripped out (id:6eb3 substrate lost)"
grep -q "queue_sig" "$JS" || fail "the queue_sig mangle canary was ripped out (id:6eb3 substrate lost)"
grep -Eq "sig: sigByRepo\[r\.repo\]" "$JS" || fail "the chunk no longer carries each repo's LIVE sig (id:4860/id:6eb3 comparison substrate lost)"
pass "(3) id:4860 content-address substrate (queue constants + live chunk sig + queue_sig canary) RETAINED for the gated id:6eb3 CASE-A re-add"

# (4) discover-chunk.sh RESERVES the CASE-A flags (--queue-latest / --queue-fresh-secs) that
#     id:6eb3 will implement — so the CASE-A recipe coverage is RELOCATED to a concrete home, not
#     dropped. (They are accepted-but-unused today; id:6eb3 wires them to the queue content-address.)
grep -q -- "--queue-latest" "$CHUNK_SH" || fail "discover-chunk.sh does not reserve the --queue-latest flag (id:6eb3 CASE-A seam)"
grep -q -- "--queue-fresh-secs" "$CHUNK_SH" || fail "discover-chunk.sh does not reserve the --queue-fresh-secs flag (id:6eb3 CASE-A seam)"
grep -q "id:6eb3" "$CHUNK_SH" || fail "discover-chunk.sh does not point the reserved CASE-A flags at the id:6eb3 follow-on"
pass "(4) CASE-A queue-consume is DEFERRED to id:6eb3: discover-chunk.sh reserves --queue-latest/--queue-fresh-secs (recipe coverage relocated, not dropped)"

echo "ALL PASS: discover-run CASE-B mechanized (id:24ec); FINDING-1 reconcile-live preserved by construction; id:4860 substrate retained; CASE-A queue-consume relocated to id:6eb3"
