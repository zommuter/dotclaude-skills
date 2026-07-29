#!/usr/bin/env bash
# roadmap:89d6
# RED SPEC for id:89d6 — `claim.sh release --run <runId>` SWEEP verb (meeting
# docs/meeting-notes/2026-07-29-0911-mechanical-hop-proxy-coupling.md, D1-A).
#
# Today `claim.sh release` REQUIRES a <key> positional (`release: <key> required`, exit 2)
# and `--run` merely SCOPES a single-key release. The sweep shape — no key, release every
# shard whose JSON .runId matches — does not exist, so this spec is RED.
#
# Why it matters: a blocked/failed per-unit releaseLease (relay-loop.js:2415) strands a
# lease until CLAIM_TTL (1800s). Observed harm: loderite held by a run whose pid 2988585
# was already dead, until a human released it by hand. With an exit sweep, per-unit release
# stops being load-bearing and becomes a latency optimization.
#
# Triangulation (id:108e — several distinct cases so special-casing is harder than
# implementing): N=3 keys of MIXED shapes (bare repo, resource:, pool:) in ONE call;
# a second run's key that must SURVIVE; idempotence on an already-swept run; a no-op on a
# run that holds nothing; and the three PRE-EXISTING forms must not regress.
#
# Hermetic: CLAIM_BASE + CLAIM_LOG are redirected into mktemp -d; nothing touches
# ~/.config/relay, ~/.claude, or the network.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SH="$ROOT/relay/scripts/claim.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SH" ]] || fail "claim.sh not found/executable at $SH"

export CLAIM_BASE; CLAIM_BASE="$(mktemp -d)"
export CLAIM_LOG=/dev/null
trap 'rm -rf "$CLAIM_BASE"' EXIT

RUN_A="relay-20260729-100152-27550"
RUN_B="relay-20260729-110000-99999"

shard_for() { printf '%s/claims/%s.json' "$CLAIM_BASE" "$(printf '%s' "$1" | tr '/:' '__')"; }

seed() {
  # (re)create the fixture: RUN_A holds 3 keys of different shapes, RUN_B holds 1.
  rm -rf "$CLAIM_BASE/claims" "$CLAIM_BASE/claims.done"
  "$SH" acquire loderite       --repo loderite --run "$RUN_A" --mode execute >/dev/null
  "$SH" acquire resource:local-llm            --run "$RUN_A" --mode intensive >/dev/null
  "$SH" acquire pool:autonomous               --run "$RUN_A" --mode autonomous >/dev/null
  "$SH" acquire truncocraft    --repo truncocraft --run "$RUN_B" --mode review >/dev/null
}

# ── (1) one sweep call releases ALL N keys held by the run ────────────────────────────────
seed
for k in loderite resource:local-llm pool:autonomous truncocraft; do
  [[ -f "$(shard_for "$k")" ]] || fail "(1) fixture setup failed — no shard for '$k'"
done

"$SH" release --run "$RUN_A" \
  || fail "(1) 'claim.sh release --run <runId>' (sweep, no key) must exit 0 — it does not exist yet"

for k in loderite resource:local-llm pool:autonomous; do
  [[ ! -f "$(shard_for "$k")" ]] \
    || fail "(1) sweep left key '$k' (held by $RUN_A) still claimed"
  [[ -f "$CLAIM_BASE/claims.done/$(printf '%s' "$k" | tr '/:' '__').json" ]] \
    || fail "(1) sweep did not move '$k' into claims.done/ (must reuse the release path)"
done
pass "(1) one sweep call released all 3 keys held by the run, into claims.done/"

# ── (2) the sweep NEVER touches another run's key ─────────────────────────────────────────
[[ -f "$(shard_for truncocraft)" ]] \
  || fail "(2) sweep released 'truncocraft', which is held by a DIFFERENT run ($RUN_B) — run-scoping violated"
if "$SH" acquire truncocraft --repo truncocraft --run "$RUN_A" 2>/dev/null; then
  fail "(2) after the sweep, another run's live claim became acquirable — it was really released"
fi
pass "(2) a key held by a different run survives the sweep and is still enforced"

# ── (3) idempotent: sweeping the same run again is a clean no-op ──────────────────────────
"$SH" release --run "$RUN_A" \
  || fail "(3) a second sweep of an already-swept run must exit 0 (idempotent)"
[[ -f "$(shard_for truncocraft)" ]] || fail "(3) the repeat sweep collaterally released $RUN_B's key"
pass "(3) sweeping an already-swept run is an idempotent no-op"

# ── (4) sweeping a run that holds nothing is a clean no-op, not an error ──────────────────
"$SH" release --run "relay-does-not-exist-0000" \
  || fail "(4) sweeping a run holding nothing must exit 0"
[[ -f "$(shard_for truncocraft)" ]] || fail "(4) sweeping an unknown run released someone else's key"
pass "(4) sweeping a run that holds nothing is a no-op, exit 0"

# ── (5) the three PRE-EXISTING release forms must not regress ─────────────────────────────
seed

# 5a. unscoped single-key force-release still works
"$SH" release loderite || fail "(5a) 'release <key>' (unscoped force-release) regressed"
[[ ! -f "$(shard_for loderite)" ]] || fail "(5a) unscoped release did not remove the shard"
pass "(5a) 'release <key>' unscoped force-release still works"

# 5b. run-scoped single-key release still refuses to touch another run's claim
"$SH" release truncocraft --run "$RUN_A" || fail "(5b) run-scoped release exited non-zero"
[[ -f "$(shard_for truncocraft)" ]] \
  || fail "(5b) 'release <key> --run <other-run>' deleted a claim held by a different run"
pass "(5b) 'release <key> --run R' still refuses a claim held by another run"

# 5c. release with NEITHER a key NOR --run is still a usage error (exit 2)
rc=0; "$SH" release >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 2 ]] || fail "(5c) bare 'release' must still exit 2 (usage), got $rc"
pass "(5c) bare 'release' (no key, no --run) is still a usage error, exit 2"

# ── (6) the sweep is real code in claim.sh, not a wrapper elsewhere ───────────────────────
grep -q -- '--run' "$SH" || fail "(6) claim.sh does not mention --run at all"
pass "(6) the sweep verb lives in claim.sh itself"

echo "ALL PASS: claim.sh release --run <runId> sweep verb (id:89d6)"
