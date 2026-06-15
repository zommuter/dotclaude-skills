#!/usr/bin/env bash
# roadmap:ebfb — per-shard cross-session claim registry.
# Covers the claim.sh helper (acquire/release/peek/reap) hermetically: claim/refuse,
# non-consuming peek, idempotent release + re-acquire, mtime-TTL staleness + reap,
# and resource-key safekey sanitization. Also asserts Makefile registration so the
# new script can't ship un-symlinked (the id:5f09 lesson).

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SH="$SRC_DIR/relay/scripts/claim.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SH" ]] || fail "claim.sh not found/executable at $SH"

# ── Hermetic base ──
export CLAIM_BASE; CLAIM_BASE="$(mktemp -d)"
export CLAIM_LOG=/dev/null
trap 'rm -rf "$CLAIM_BASE"' EXIT

# acquire a key → exit 0, shard exists, JSON carries key/repo/mode.
sk="$("$SH" acquire zkm-photo --repo zkm-photo --run run-1 --mode execute --item baf1)"
[[ -n "$sk" ]] || fail "acquire did not print a safekey"
shard="$CLAIM_BASE/claims/$sk.json"
[[ -f "$shard" ]] || fail "acquire did not write shard $shard"
jq -e '.key=="zkm-photo" and .repo=="zkm-photo" and .mode=="execute" and .item=="baf1"' "$shard" >/dev/null \
  || fail "shard JSON missing/incorrect fields"
pass "acquire writes a fresh shard with key/repo/mode/item"

# acquire the SAME key again → exit 1 (already held, fresh).
if "$SH" acquire zkm-photo --repo zkm-photo 2>/dev/null; then fail "second acquire of a fresh key should fail"; fi
pass "acquire refuses a fresh held key (exit 1)"

# peek → emits the held claim (1 line, non-consuming).
peeked="$("$SH" peek | wc -l)"
[[ "$peeked" -eq 1 ]] || fail "peek should emit 1 line (got $peeked)"
[[ -f "$shard" ]] || fail "peek consumed the shard (must be non-consuming)"
pass "peek emits the held claim without consuming"

# release → shard moved to claims.done, exit 0; release again still exit 0.
"$SH" release zkm-photo
[[ ! -f "$shard" ]] || fail "release did not remove the shard"
[[ -f "$CLAIM_BASE/claims.done/$sk.json" ]] || fail "release did not move shard to claims.done"
"$SH" release zkm-photo
pass "release moves shard to claims.done and is idempotent"

# acquire again after release → exit 0 (re-acquirable).
"$SH" acquire zkm-photo --repo zkm-photo >/dev/null || fail "re-acquire after release should succeed"
pass "key is re-acquirable after release"

# STALE/TTL + reap: age the shard past TTL, reap moves it, then re-acquire succeeds.
export CLAIM_TTL=1
touch -d '1 hour ago' "$shard"
"$SH" acquire zkm-photo --repo zkm-photo >/dev/null 2>&1 || fail "stale shard should be acquirable"
# re-stale and reap it explicitly
touch -d '1 hour ago' "$shard"
"$SH" reap 2>/dev/null
[[ ! -f "$shard" ]] || fail "reap did not move the stale shard"
[[ -f "$CLAIM_BASE/claims.done/$sk.json" ]] || fail "reap did not move stale shard to claims.done"
"$SH" acquire zkm-photo --repo zkm-photo >/dev/null || fail "acquire after reap should succeed"
unset CLAIM_TTL
pass "stale claims (mtime+TTL) are reclaimable and reaped"

# resource-key safety: ':' sanitized in filename, original key preserved in JSON.
rk="$("$SH" acquire 'resource:local-llm' --repo POOL --mode intensive)"
[[ "$rk" == "resource_local-llm" ]] || fail "safekey not sanitized (got '$rk')"
rshard="$CLAIM_BASE/claims/resource_local-llm.json"
[[ -f "$rshard" ]] || fail "resource shard file resource_local-llm.json not found"
jq -e '.key=="resource:local-llm"' "$rshard" >/dev/null || fail "original key not preserved in JSON"
pass "resource-key safekey sanitizes ':' while preserving the original key"

# ── Makefile registration (id:5f09 lesson — no un-symlinked helper) ──
mk_count="$(grep -c "scripts/claim.sh" "$SRC_DIR/Makefile" || true)"
[[ "$mk_count" -ge 3 ]] || fail "Makefile must register claim.sh in relay_FILES/_EXEC/_ALLOW (3x); got $mk_count"
pass "Makefile registers claim.sh in relay_FILES/_EXEC/_ALLOW"

echo "ALL PASS: per-shard claim registry (id:ebfb)"
