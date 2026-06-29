#!/usr/bin/env bash
# roadmap:e149 — run-level liveness marker for the relay loop. The FOUNDATION the
# auto-reconcile (id:7809) and watchdog (id:98f0) both read. Contract:
#   - a fresh heartbeat reads "alive"; one older than TTL reads "dead"
#   - a cleanly-stopped run leaves NO marker (never flagged dead)
#   - dead-runs emits present-but-stale runs; live-runs emits fresh ones
#   - staleness is PURE ts+TTL — a left-behind working worktree must NOT mask a
#     dead loop (the key difference from claim.sh liveness)
# Hermetic: HEARTBEAT_BASE in a tmpdir, staleness forced via an aged heartbeat_ts /
# touch, no network/~.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SH="$SRC_DIR/relay/scripts/heartbeat.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SH" ]] || fail "heartbeat.sh not found/executable at $SH"

export HEARTBEAT_BASE; HEARTBEAT_BASE="$(mktemp -d)/heartbeats"
export HEARTBEAT_LOG=/dev/null
export HEARTBEAT_TTL=3600   # large TTL; all staleness is forced via aged ts/touch
trap 'rm -rf "$(dirname "$HEARTBEAT_BASE")"' EXIT

# helper: age a marker past TTL by rewriting heartbeat_ts to "2 hours ago" + touch.
age_marker() {
  local f="$1" old; old="$(( $(date +%s) - 7200 ))"
  jq --argjson t "$old" '.heartbeat_ts=$t' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  touch -d '2 hours ago' "$f"
}

# ── a fresh beat reads alive ──────────────────────────────────────────────────
sk="$("$SH" beat relay-RUNA --pid 4242)"
marker="$HEARTBEAT_BASE/$sk.json"
[[ -f "$marker" ]] || fail "beat did not create a marker file"
jq -e '.runId=="relay-RUNA" and (.pid=="4242") and (.heartbeat_ts|type=="number")' "$marker" >/dev/null \
  || fail "beat marker missing runId/pid/heartbeat_ts"
[[ "$("$SH" status relay-RUNA)" == alive ]] || fail "a fresh beat should read alive"
"$SH" status relay-RUNA >/dev/null && : || fail "status alive should exit 0"
pass "a fresh heartbeat reads alive (id:e149)"

# beat preserves started_at across refreshes
s1="$(jq -r '.started_at' "$marker")"
sleep 1
"$SH" beat relay-RUNA >/dev/null
s2="$(jq -r '.started_at' "$marker")"
[[ "$s1" == "$s2" ]] || fail "re-beat changed started_at ($s1 → $s2)"
h2="$(jq -r '.heartbeat_ts' "$marker")"
[[ "$h2" -ge "$s1" ]] || fail "re-beat did not refresh heartbeat_ts"
pass "re-beat refreshes heartbeat_ts but preserves started_at (id:e149)"

# ── an aged heartbeat reads dead ──────────────────────────────────────────────
age_marker "$marker"
out="$("$SH" status relay-RUNA || true)"
[[ "$out" == dead ]] || fail "a heartbeat older than TTL should read dead (got '$out')"
if "$SH" status relay-RUNA >/dev/null 2>&1; then fail "status dead should exit non-zero"; fi
pass "a heartbeat older than TTL reads dead (id:e149)"

# dead-runs emits the stale run; live-runs does not
"$SH" dead-runs | jq -e 'select(.runId=="relay-RUNA")' >/dev/null \
  || fail "dead-runs did not emit the stale run"
[[ -z "$("$SH" live-runs)" ]] || fail "live-runs emitted a stale run"
"$SH" dead-runs | jq -e 'select(.runId=="relay-RUNA") | .state=="dead" and (.age_s>=3600)' >/dev/null \
  || fail "dead-runs JSON missing state=dead / age_s"
pass "dead-runs emits present-but-stale runs, live-runs excludes them (id:e149)"

# ── a working worktree must NOT mask a dead loop (vs claim.sh liveness) ────────
# Build a worktree with commits beyond main and point a (now-aged) marker's pid at
# a live process — neither may keep the run "alive". (heartbeat.sh ignores both.)
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
wt="$(mktemp -d)/wt"; git init -q -b main "$wt"
( cd "$wt" && echo base>a && git add a && git commit -qm base \
  && git checkout -q -b relay/feat && echo work>b && git add b && git commit -qm work )
sleep 600 & livepid=$!   # a genuinely live pid
"$SH" beat relay-RUNB --pid "$livepid" >/dev/null
mk2="$HEARTBEAT_BASE/$(printf relay-RUNB | tr '/:' '__').json"
age_marker "$mk2"
out2="$("$SH" status relay-RUNB || true)"
kill "$livepid" 2>/dev/null || true
[[ "$out2" == dead ]] || fail "a left-behind working worktree / live pid wrongly masked a dead loop (got '$out2')"
rm -rf "$(dirname "$wt")"
pass "ts+TTL staleness ignores worktree/pid — a dead loop reads dead (id:e149)"

# ── a cleanly-stopped run leaves no marker (never flagged dead) ────────────────
"$SH" beat relay-RUNC >/dev/null
"$SH" stop relay-RUNC
[[ "$("$SH" status relay-RUNC || true)" == absent ]] || fail "stop did not remove the marker"
[[ -z "$("$SH" dead-runs | jq -rc 'select(.runId=="relay-RUNC")')" ]] \
  || fail "a cleanly-stopped run appeared in dead-runs"
"$SH" stop relay-RUNC   # idempotent
pass "a cleanly-stopped run leaves no marker and is never flagged dead (id:e149)"

# ── reap archives dead markers but keeps alive ones ───────────────────────────
"$SH" beat relay-DEAD1 >/dev/null
"$SH" beat relay-ALIVE1 >/dev/null
age_marker "$HEARTBEAT_BASE/$(printf relay-DEAD1 | tr '/:' '__').json"
"$SH" reap 2>/dev/null
[[ "$("$SH" status relay-DEAD1 || true)" == absent ]] || fail "reap did not archive a dead marker"
[[ "$("$SH" status relay-ALIVE1)" == alive ]] || fail "reap wrongly archived an alive marker"
pass "reap archives dead markers and keeps alive ones (id:98f0 watchdog/7809 dedup)"

echo "ALL PASS: relay run-heartbeat liveness foundation (id:e149)"
