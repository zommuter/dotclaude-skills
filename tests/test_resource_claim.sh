#!/usr/bin/env bash
# roadmap:a643 — standalone GPU/intensive jobs acquire a relay `resource:<name>` claim
# so `--intensive` can serialize against them. Hermetic over a temp CLAIM_BASE: asserts
# acquire-resource.sh composes claim.sh (no new lock), the standalone claim COLLIDES with
# a relay-held resource claim on the SAME key (the busy-refusal that prevents a second
# GPU load), the wrap acquires-then-always-releases, the shared vocabulary doc exists,
# and the helper is registered in the Makefile (id:69ef install-completeness).
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SH="$SRC_DIR/relay/scripts/acquire-resource.sh"
CLAIM="$SRC_DIR/relay/scripts/claim.sh"
DOC="$SRC_DIR/relay/references/resource-claims.md"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SH" ]]    || fail "acquire-resource.sh not found/executable at $SH"
[[ -x "$CLAIM" ]] || fail "claim.sh not found/executable at $CLAIM"

# ── Hermetic claim base (shared by both the helper and the simulated relay) ──
export CLAIM_BASE; CLAIM_BASE="$(mktemp -d)"
export CLAIM_LOG=/dev/null
export RESOURCE_CLAIM_LOG=/dev/null
trap 'rm -rf "$CLAIM_BASE"' EXIT

# ── (1) bare --acquire on a free resource → exit 0, claim shard written under the
#        SAME key the relay would use (resource:<name>). ──
sk="$("$SH" gpu --acquire --run standalone-A)"
[[ "$sk" == "resource_gpu" ]] || fail "bare --acquire should print the resource:gpu safekey (got '$sk')"
shard="$CLAIM_BASE/claims/resource_gpu.json"
[[ -f "$shard" ]] || fail "acquire did not write the resource:gpu shard"
jq -e '.key=="resource:gpu" and .mode=="intensive"' "$shard" >/dev/null \
  || fail "shard JSON missing key=resource:gpu / mode=intensive"
pass "bare --acquire writes a resource:<name> claim under the shared key"

# ── (2) THE collision: a relay intensive child acquiring resource:gpu while the
#        standalone job holds it is REFUSED (exit 1) — this is what stops a 2nd GPU load. ──
if "$CLAIM" acquire resource:gpu --run relay-RUN --mode intensive >/dev/null 2>&1; then
  fail "relay acquire of resource:gpu must be REFUSED while the standalone job holds it"
fi
pass "relay's resource:gpu acquire collides with the standalone claim (busy → refused)"

# ── (3) release frees it; the relay can then acquire. ──
"$SH" gpu --release --run standalone-A
[[ ! -f "$shard" ]] || fail "--release did not move the shard out of claims/"
"$CLAIM" acquire resource:gpu --run relay-RUN --mode intensive >/dev/null \
  || fail "relay acquire should succeed after the standalone job released"
"$CLAIM" release resource:gpu --run relay-RUN
pass "release frees the resource; relay can then acquire"

# ── (4) wrap form: acquires for the command, ALWAYS releases on exit (even on failure). ──
"$SH" local-llm --run wrap-OK -- true || fail "wrap of a succeeding command should exit 0"
[[ ! -f "$CLAIM_BASE/claims/resource_local-llm.json" ]] \
  || fail "wrap did not release resource:local-llm after a successful command"
if "$SH" local-llm --run wrap-FAIL -- false; then fail "wrap should propagate the command's nonzero exit"; fi
[[ ! -f "$CLAIM_BASE/claims/resource_local-llm.json" ]] \
  || fail "wrap did not release resource:local-llm after a FAILING command (trap must fire on exit)"
pass "wrap acquires for the command and always releases on exit (success + failure)"

# ── (5) wrap refuses to run the command at all when the resource is busy (no 2nd load). ──
"$CLAIM" acquire resource:local-llm --run other-RUN --mode intensive >/dev/null
sentinel="$CLAIM_BASE/ran.flag"
if "$SH" local-llm --run wrap-BUSY -- touch "$sentinel" 2>/dev/null; then
  fail "wrap should exit nonzero when the resource is busy"
fi
[[ ! -e "$sentinel" ]] || fail "wrap RAN the command despite the resource being busy (the OOM hazard)"
"$CLAIM" release resource:local-llm --run other-RUN
pass "wrap refuses to run the wrapped command when the resource is already held"

# ── (6) the shared vocabulary doc exists and names the contract. ──
[[ -f "$DOC" ]] || fail "shared vocabulary doc $DOC missing"
grep -q 'resource:<name>' "$DOC" || fail "doc must document the resource:<name> key"
grep -q 'INTENSIVE' "$DOC"       || fail "doc must tie the token to the [INTENSIVE — <resource>] tag"
pass "resource-claims.md documents the shared resource:<name> vocabulary"

# ── (7) Makefile registration (id:69ef — no un-symlinked helper / un-installed doc). ──
mk_exec="$(grep -c "scripts/acquire-resource.sh" "$SRC_DIR/Makefile" || true)"
[[ "$mk_exec" -ge 3 ]] || fail "Makefile must register acquire-resource.sh in FILES/EXEC/ALLOW (3x); got $mk_exec"
grep -q "references/resource-claims.md" "$SRC_DIR/Makefile" \
  || fail "Makefile must register references/resource-claims.md in relay_FILES"
pass "Makefile registers acquire-resource.sh (3x) and resource-claims.md"

echo "ALL PASS: standalone resource:<name> claim collision (id:a643)"
