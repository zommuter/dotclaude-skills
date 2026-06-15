#!/usr/bin/env bash
# roadmap:baf1 — on-demand high-priority executor-task injection.
# Covers the inject.sh helper (add/peek/take/consume) hermetically, the relay-loop.js
# wiring (schema + injected-first sort + discovery take + quota skip), and Makefile
# registration (so the new script can't ship un-symlinked — the id:5f09 lesson).

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SH="$SRC_DIR/relay/scripts/inject.sh"
JS="$SRC_DIR/relay/scripts/relay-loop.js"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SH" ]] || fail "inject.sh not found/executable at $SH"

# ── Helper semantics (hermetic) ──
export INJECT_BASE; INJECT_BASE="$(mktemp -d)"
export INJECT_LOG=/dev/null
trap 'rm -rf "$INJECT_BASE"' EXIT

# add → token printed, shard is valid JSON with the requested fields
tok="$("$SH" add zkm-photo --item baf1 --verdict execute --prompt 'rebuild index')"
[[ "$tok" == inj-* ]] || fail "add did not print an inj-* token (got '$tok')"
shard="$INJECT_BASE/inject.d/$tok.json"
[[ -f "$shard" ]] || fail "add did not write the shard $shard"
jq -e '.repo=="zkm-photo" and .verdict=="execute" and .item=="baf1" and .prompt=="rebuild index"' "$shard" >/dev/null \
  || fail "shard JSON missing/incorrect fields"
pass "add writes a valid per-shard JSON with repo/verdict/item/prompt"

# default verdict is execute
tok2="$("$SH" add some-repo)"
jq -e '.verdict=="execute"' "$INJECT_BASE/inject.d/$tok2.json" >/dev/null || fail "default verdict not execute"
pass "add defaults verdict to execute"

# bad verdict rejected
if "$SH" add r --verdict bogus 2>/dev/null; then fail "add accepted an invalid verdict"; fi
pass "add rejects an invalid verdict"

# peek is NON-consuming (emits both, leaves shards in place)
peeked="$("$SH" peek | wc -l)"
[[ "$peeked" -eq 2 ]] || fail "peek should emit 2 lines (got $peeked)"
[[ -f "$shard" ]] || fail "peek consumed a shard (must be non-consuming)"
pass "peek emits pending injections without consuming"

# take emits AND consumes (shards move to inject.done)
taken="$("$SH" take | wc -l)"
[[ "$taken" -eq 2 ]] || fail "take should emit 2 lines (got $taken)"
[[ ! -f "$shard" ]] || fail "take did not consume the shard"
[[ -f "$INJECT_BASE/inject.done/$tok.json" ]] || fail "take did not move shard to inject.done"
pass "take emits and consumes (moves to inject.done)"

# take again → nothing pending
again="$("$SH" take | wc -l)"
[[ "$again" -eq 0 ]] || fail "second take should emit nothing (got $again)"
pass "consumed injections are not re-listed"

# ── relay-loop.js wiring (static) ──
[[ -f "$JS" ]] || fail "relay-loop.js not found"
grep -q "injected:" "$JS" || fail "DISCOVER_SCHEMA missing 'injected' field"
grep -q "inject_token:" "$JS" || fail "DISCOVER_SCHEMA missing 'inject_token' field"
grep -q "inject.sh take" "$JS" || fail "discovery prompt does not call 'inject.sh take'"
# injected-first sort key present in BOTH sorts (normal + --fable-down demote)
inj_sorts="$(grep -c "(b.injected ? 1 : 0) - (a.injected ? 1 : 0)" "$JS" || true)"
[[ "$inj_sorts" -ge 2 ]] || fail "injected-first sort key missing from one of the schedulers (found $inj_sorts, need >=2)"
grep -q "!unit.injected && !(await quotaGate" "$JS" || fail "injected units do not skip the quota gate in runUnit"
pass "relay-loop.js: schema + discovery take + injected-first sort + quota skip wired"

# ── Makefile registration (id:5f09 lesson — no un-symlinked helper) ──
# inject.sh must appear once in each of relay_FILES/_EXEC/_ALLOW → 3 occurrences total.
mk_count="$(grep -c "scripts/inject.sh" "$SRC_DIR/Makefile" || true)"
[[ "$mk_count" -ge 3 ]] || fail "Makefile must register inject.sh in relay_FILES/_EXEC/_ALLOW (3x); got $mk_count"
pass "Makefile registers inject.sh in relay_FILES/_EXEC/_ALLOW"

echo "ALL PASS: on-demand injection (id:baf1)"
