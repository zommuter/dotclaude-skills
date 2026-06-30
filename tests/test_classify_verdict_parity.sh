#!/usr/bin/env bash
# roadmap:e424
# Verdict-PARITY extension for classify-verdict.sh (id:e424) — step (a) toward the flip (id:a0b6).
# The discovery shard does not dispatch a repo whose main tree is DIRTY or DIVERGED from origin;
# it surfaces it. For classify-verdict to become the primary verdict source, it must reach the
# same dispatch-or-not decision. Adds a `blocked` verdict (the "needs-attention, do NOT dispatch"
# disposition — distinct from `idle` = clean+no-work) for:
#   - DIVERGED: has_upstream AND ahead>0 AND behind>0  (never dispatch/commit on a diverged repo)
#   - DIRTY (non-lock-only): dirty=true AND NOT dirty_lock_only  (uncommitted work in main tree)
# These outrank every dispatch verdict (a dirty/diverged repo is never dispatched even with
# unaudited commits). NOT blocked: a uv.lock-only dirty tree (dirty_lock_only=true, the id:bae5
# exemption — committed in place by the loop), and a behind-only repo (the shard ff-merges then
# reclassifies; classify-verdict sees the post-ff state). All inputs already arrive from gather via
# classify-repo (which passes the full gather JSON through) — this is a classify-verdict-only change.
# RED until classify-verdict emits `blocked`.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CV="$ROOT/relay/scripts/classify-verdict.sh"
[[ -x "$CV" ]] || { echo "classify-verdict.sh missing"; exit 1; }
verdict_of() { "$CV" <<<"$1" | python3 -c 'import sys,json;print(json.load(sys.stdin)["verdict"])'; }

base='"is_finished":false,"hasRoutine":true,"substantive_unaudited":true,"open_hard_pool":0,"top_intensive":"","roadmap_open":1,"roadmap_actionable_open":1,"unpromoted":{"promote":0,"surface":0}'

# DIRTY (non-lock-only) → blocked, even though it has open routine + unaudited (which would be execute/review)
d="{$base,\"dirty\":true,\"dirty_lock_only\":false,\"has_upstream\":true,\"upstream_ahead_behind\":\"0\t0\"}"
[[ "$(verdict_of "$d")" == "blocked" ]] || { echo "dirty (non-lock) must be blocked, got $(verdict_of "$d")"; exit 1; }

# DIVERGED (ahead>0 AND behind>0) → blocked
v="{$base,\"dirty\":false,\"dirty_lock_only\":false,\"has_upstream\":true,\"upstream_ahead_behind\":\"2\t3\"}"
[[ "$(verdict_of "$v")" == "blocked" ]] || { echo "diverged must be blocked, got $(verdict_of "$v")"; exit 1; }

# uv.lock-only dirty → NOT blocked (falls through; open routine → execute)
l="{$base,\"dirty\":true,\"dirty_lock_only\":true,\"has_upstream\":true,\"upstream_ahead_behind\":\"0\t0\"}"
[[ "$(verdict_of "$l")" == "execute" ]] || { echo "lock-only dirty must fall through (execute), got $(verdict_of "$l")"; exit 1; }

# behind-only → NOT blocked (shard ff-merges first; classify-verdict sees post-ff). open routine → execute
b="{$base,\"dirty\":false,\"dirty_lock_only\":false,\"has_upstream\":true,\"upstream_ahead_behind\":\"0\t3\"}"
[[ "$(verdict_of "$b")" == "execute" ]] || { echo "behind-only must NOT block (execute), got $(verdict_of "$b")"; exit 1; }

# clean + in-sync → normal verdict (execute), unchanged
c="{$base,\"dirty\":false,\"dirty_lock_only\":false,\"has_upstream\":true,\"upstream_ahead_behind\":\"0\t0\"}"
[[ "$(verdict_of "$c")" == "execute" ]] || { echo "clean in-sync must be execute, got $(verdict_of "$c")"; exit 1; }

# no upstream → never blocked on the sync axis (has_upstream false); clean dirty=false → execute
n="{$base,\"dirty\":false,\"dirty_lock_only\":false,\"has_upstream\":false,\"upstream_ahead_behind\":\"0\t0\"}"
[[ "$(verdict_of "$n")" == "execute" ]] || { echo "no-upstream clean must be execute, got $(verdict_of "$n")"; exit 1; }

# backward-compat: inputs WITHOUT the dirty/upstream fields still classify (fail-open, not blocked)
[[ "$(verdict_of "{$base}")" == "execute" ]] || { echo "missing dirty/upstream fields must not block (compat), got $(verdict_of "{$base}")"; exit 1; }

echo "PASS test_classify_verdict_parity"
