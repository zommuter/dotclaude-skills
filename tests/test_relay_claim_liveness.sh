#!/usr/bin/env bash
# roadmap:7570 — claim liveness must not (a) leak a dead claim for the full TTL, nor
# (b) expire a legitimately-long LIVE child mid-work. Two new claim.sh facilities:
#   - heartbeat <key> [--run R]: refresh a held claim's mtime (run-scoped) so a >TTL child
#     keeps its lease.
#   - worktree-anchored liveness: a STALE-mtime claim whose recorded --worktree still has
#     commits beyond main is LIVE (the converse of id:3ac8) — peek emits it, reap keeps it,
#     and a different run's acquire is refused; whereas a stale claim with HEAD==main (or no
#     worktree) is DEAD — reapable and re-acquirable.
# Hermetic: CLAIM_BASE in a tmpdir, real git repos in a tmpdir, no network/~.
#
# Hermeticity note (id:6b91 fix): all staleness is forced via `touch -d '1 hour ago'` —
# we never rely on natural mtime aging. CLAIM_TTL is set to 3600 (1 hour) to prevent a
# timing window on a loaded system: with TTL=1 a heartbeat-then-acquire sequence taking
# >1 s on a loaded machine caused the freshly-heartbeated claim to appear stale again,
# letting a steal succeed (the shared surface under parallel test-suite runs). TTL=3600
# eliminates this window; the `touch` commands still exercise the stale-and-dead path
# deterministically. No fixed /tmp path is used — every shared surface is private to
# this test's $CLAIM_BASE tmpdir.
#
# Structural-determinism note (id:16e9 fix): the "wrong-run heartbeat is a no-op" assertion
# no longer compares mtime to an absolute wall-clock timestamp (`$((now - mt)) -ge 2`).
# That comparison was theoretically clock-sensitive — if the system clock moved or stat/date
# returned inconsistent values it could yield a spurious fail. Replaced with a before/after
# snapshot (`mt_before` vs `mt_after`): if the wrong-run heartbeat left the mtime unchanged,
# the two values are identical regardless of what the clock says. Completely timing-free.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SH="$SRC_DIR/relay/scripts/claim.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SH" ]] || fail "claim.sh not found/executable at $SH"

export CLAIM_BASE; CLAIM_BASE="$(mktemp -d)"
export CLAIM_LOG=/dev/null
WORK="$(mktemp -d)"
trap 'rm -rf "$CLAIM_BASE" "$WORK"' EXIT

# git identity for the hermetic repos (don't depend on global config)
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# Build a worktree whose HEAD has a commit BEYOND main (a working long child).
working_wt="$WORK/working"
git init -q -b main "$working_wt"
( cd "$working_wt" && echo base > a && git add a && git commit -qm base \
  && git checkout -q -b relay/feat && echo work > b && git add b && git commit -qm work )

# Build a worktree whose HEAD == main (an idle/dead child, no work yet).
idle_wt="$WORK/idle"
git init -q -b main "$idle_wt"
( cd "$idle_wt" && echo base > a && git add a && git commit -qm base )

# Verify git repos are valid before the main tests — fail fast with a clear message
# rather than a confusing "steal succeeded" later (worktree_working returns false on git error).
git -C "$working_wt" rev-parse HEAD >/dev/null 2>&1 \
  || fail "working_wt setup failed: HEAD not resolvable (git error at repo init time)"
git -C "$working_wt" merge-base --is-ancestor HEAD main 2>/dev/null \
  && fail "working_wt setup wrong: HEAD should NOT be ancestor of main (relay/feat must be ahead)"
git -C "$idle_wt" rev-parse HEAD >/dev/null 2>&1 \
  || fail "idle_wt setup failed: HEAD not resolvable"
git -C "$idle_wt" merge-base --is-ancestor HEAD main 2>/dev/null \
  || fail "idle_wt setup wrong: HEAD should be ancestor of main (HEAD==main, no extra commits)"

# ── heartbeat keeps a >TTL claim alive ──────────────────────────────────────────────
# Use a large TTL (1 hour) — all stale-state is forced via `touch -d '1 hour ago'`, so
# natural aging never triggers. TTL=1 caused timing-sensitive flakes under parallel load
# (id:6b91): heartbeat refreshes at T=0 but acquire runs at T>1s on a busy machine.
export CLAIM_TTL=3600
sk="$("$SH" acquire hb-repo --repo hb-repo --run RUN-HB --mode hard)"
shard="$CLAIM_BASE/claims/$sk.json"
touch -d '1 hour ago' "$shard"          # age it past TTL → would be stale
"$SH" heartbeat hb-repo --run RUN-HB     # refresh mtime
if "$SH" acquire hb-repo --run RUN-OTHER 2>/dev/null; then
  fail "heartbeat did not refresh mtime — a stale claim was stolen by another run"
fi
"$SH" peek | grep -q '"key":"hb-repo"' || fail "peek dropped a freshly-heartbeated claim"
pass "heartbeat refreshes a held claim's mtime (long child keeps its lease) (id:7570)"

# heartbeat is run-scoped: a different run cannot refresh someone else's claim mtime.
touch -d '1 hour ago' "$shard"
mt_before="$(stat -c %Y "$shard")"        # snapshot mtime before the no-op heartbeat
"$SH" heartbeat hb-repo --run RUN-WRONG   # wrong run → no-op (should not touch)
mt_after="$(stat -c %Y "$shard")"
# mtime must be UNCHANGED — no absolute clock comparison (timing-independent assertion)
[[ "$mt_before" -eq "$mt_after" ]] || fail "heartbeat with a wrong --run wrongly refreshed the claim"
# and heartbeat of an absent claim is a no-op exit 0.
"$SH" heartbeat no-such-repo --run RUN-HB || fail "heartbeat of an absent claim should exit 0"
pass "heartbeat is run-scoped and idempotent on an absent claim (id:7570)"

# ── worktree-anchored liveness: stale-mtime + working worktree → LIVE ────────────────
"$SH" release hb-repo >/dev/null 2>&1 || true
sk2="$("$SH" acquire wt-repo --repo wt-repo --run RUN-LONG --mode hard --worktree "$working_wt")"
shard2="$CLAIM_BASE/claims/$sk2.json"
jq -e --arg w "$working_wt" '.worktree==$w' "$shard2" >/dev/null \
  || fail "acquire did not record the --worktree in the shard JSON"
touch -d '1 hour ago' "$shard2"          # stale mtime, but the worktree is still working
# different run must be REFUSED (the long child still owns the repo)
if "$SH" acquire wt-repo --run RUN-STEAL 2>/dev/null; then
  fail "a stale-mtime claim with a WORKING worktree was stolen (long child lost its lease)"
fi
# peek still emits it; reap keeps it
"$SH" peek | grep -q '"key":"wt-repo"' || fail "peek dropped a stale-but-working long-child claim"
"$SH" reap 2>/dev/null
[[ -f "$shard2" ]] || fail "reap wrongly removed a stale-but-working long-child claim"
pass "stale-mtime + working worktree → LIVE (peek emits, reap keeps, acquire refused) (id:7570)"

# ── dead claim (stale + HEAD==main worktree) → reapable / re-acquirable ──────────────
"$SH" release wt-repo >/dev/null 2>&1 || true
sk3="$("$SH" acquire idle-repo --repo idle-repo --run RUN-DEAD --mode hard --worktree "$idle_wt")"
shard3="$CLAIM_BASE/claims/$sk3.json"
touch -d '1 hour ago' "$shard3"          # stale + worktree HEAD==main → DEAD
# another run can take it (no live work to protect — this is the leak/crash recovery case)
"$SH" acquire idle-repo --run RUN-NEW --worktree "$idle_wt" >/dev/null 2>&1 \
  || fail "a stale claim whose worktree HEAD==main should be re-acquirable (dead child)"
pass "stale-mtime + HEAD==main worktree → DEAD (re-acquirable; no false long-child protection) (id:7570)"

# dead claim with NO worktree field at all → still reapable (back-compat: old shards).
sk4="$("$SH" acquire nowt-repo --repo nowt-repo --run RUN-OLD)"
shard4="$CLAIM_BASE/claims/$sk4.json"
touch -d '1 hour ago' "$shard4"
"$SH" reap 2>/dev/null
[[ ! -f "$shard4" ]] || fail "reap kept a stale claim with no worktree anchor (would leak)"
pass "stale claim with no worktree field is reaped (back-compat, no leak) (id:7570)"

echo "ALL PASS: claim liveness — heartbeat + worktree-anchored staleness (id:7570)"
