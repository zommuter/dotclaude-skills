#!/usr/bin/env bash
# claim.sh — per-shard cross-session claim registry for the relay pool (id:ebfb).
# A live claim records who is working a repo/item/resource right now. Claims are
# high-churn and must NOT live in the contended ledger/relay.toml — they get a
# dedicated per-shard registry (mirrors persona-events shards), reconcilable against
# worktree+git truth, with a read-only projection into RELAY_STATUS. Granularity:
# keyed by item id for display, enforced per-repo (a 2nd claimant for a held key is
# refused). Staleness = claim-file mtime + TTL; a flock'd reap drops stale shards
# (handback nuance for stale-with-live-worktree is the relay-loop's job, not this).
#
# SCOPE INVARIANT — the `hard` lease guards CODE/WORKTREE integration ONLY (id:179e,
# meeting D2 `docs/meeting-notes/2026-06-17-0953-k3s-parallelity-coordination-design.md`):
#   - A repo `acquire <repo> --mode <execute|review|hard|handoff|intensive>` is the HARD
#     lease: it serializes the actors that build code in a worktree and integrate (merge)
#     it into the repo's main checkout. Two of those must never run on the same repo at once.
#   - LEDGER-ONLY writes (TODO.md / ROADMAP.md / REVIEW_ME.md via meeting/md-merge.py or
#     relay/scripts/commit-ledger.sh) are NOT protected by this lease. `/meeting` step 2a
#     (id:c144) and `/relay human` (human.md §5) do NOT acquire it for a ledger write-back —
#     they PEEK-AND-WARN, then proceed. A ledger write is made safe instead by three layers:
#       (1) the per-file flock in md-merge.py / commit-ledger.sh (atomic write),
#       (2) the atomic scoped commit (id:148b / id:2147 — never `git add -A`, id:debf), and
#       (3) the `meeting/orphan-scan.sh --cross-ledger` post-hoc divergence backstop.
#   Acquiring the hard lease for a ledger write over-blocks it for the full duration of a
#   multi-repo pool run (the routed:da2f incident) — which is exactly what id:c144 removed.
#   (The bilateral advisory claim the pool would *honor* for ledger writes is the separate,
#   observe-first id:9000 follow-up; today peek is read-only awareness, not a gate.)
#
# Subcommands:
#   acquire <key> [--repo R] [--run RUNID] [--mode M] [--item ID] [--worktree WT] [--pid PID]
#       Under flock: if claims/<safekey>.json exists AND is LIVE (fresh mtime within TTL,
#       OR id:7570 a long child whose held --worktree has commits beyond main, OR id:1b11 a
#       recorded --pid that is still alive), print the holder JSON to stderr and exit 1
#       (already claimed). Otherwise (absent/stale/dead) write the shard and exit 0, printing
#       the safekey on stdout. --worktree records the child's worktree so liveness can outlive
#       the TTL for a genuinely-working long child. --pid (id:1b11) anchors liveness to a
#       standalone long job with NO worktree (e.g. a multi-hour local-LLM drain): the claim
#       stays live while that PID lives and auto-expires when it dies.
#   release <key>
#       Under flock: move claims/<safekey>.json → claims.done/ if present. Idempotent
#       (exit 0 even when absent).
#   heartbeat <key> [--run RUNID]
#       id:7570 — refresh a held claim's mtime (run-scoped: only if THIS run holds it, or
#       unscoped). Keeps a legitimately-long child (>TTL) from losing its lease mid-work.
#       Idempotent; exit 0 even when the claim is absent (nothing to refresh).
#   peek
#       Non-consuming: emit each LIVE claim as one compact JSON line (dead/stale skipped).
#   reap
#       Under flock: move every DEAD (stale mtime AND no working worktree) shard →
#       claims.done/. A stale claim whose worktree still has commits beyond main is LIVE
#       (id:7570 long-child signal, the converse of id:3ac8) and is NOT reaped. Print
#       "reaped N" to stderr.
#
# Paths: base = $CLAIM_BASE (default ~/.config/relay). Claims = $base/claims,
# consumed = $base/claims.done, lock = $base/.claim.lock. TTL = $CLAIM_TTL seconds
# (default 1800). The <safekey> replaces '/' and ':' with '_' (original key kept in
# the JSON). Override $CLAIM_BASE for hermetic tests.
set -euo pipefail

CLAIM_BASE="${CLAIM_BASE:-$HOME/.config/relay}"
CLAIMS="$CLAIM_BASE/claims"
DONE="$CLAIM_BASE/claims.done"
LOCK="$CLAIM_BASE/.claim.lock"
TTL="${CLAIM_TTL:-1800}"
LOG="${CLAIM_LOG:-$HOME/.claude/logs/relay-claim.log}"

mkdir -p "$CLAIMS" "$DONE" "$(dirname "$LOG")"
: >>"$LOCK"

log() { printf '%s claim.sh %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >>"$LOG" 2>/dev/null || true; }

# safekey: replace '/' and ':' with '_'.
safekey() { printf '%s' "$1" | tr '/:' '__'; }

# is_fresh <file>: true if file exists and its mtime is within TTL of now.
is_fresh() {
  local f="$1" now mt
  [ -f "$f" ] || return 1
  now="$(date +%s)"
  mt="$(stat -c %Y "$f" 2>/dev/null || echo 0)"
  [ $((now - mt)) -lt "$TTL" ]
}

# worktree_working <file>: id:7570 — true if the claim records a --worktree that EXISTS and
# carries commits beyond its repo's main (HEAD is NOT an ancestor of / equal to main). This
# is the converse of the id:3ac8 staleness signal: there, a stale claim whose worktree HEAD
# == main is DEAD; here, a stale claim whose worktree HEAD has DIVERGED from main is a
# legitimately-long LIVE child still doing work, so its lease must survive past the TTL even
# without a heartbeat. A claim with no worktree field, a missing worktree, or HEAD==main → false.
worktree_working() {
  local f="$1" wt head mainref
  wt="$(jq -r '.worktree // ""' "$f" 2>/dev/null)" || wt=""
  [ -n "$wt" ] || return 1
  # tilde-expand a leading ~ (claims may store the path with ~ from the JS side).
  case "$wt" in "~"/*) wt="$HOME/${wt#'~'/}" ;; "~") wt="$HOME" ;; esac
  [ -d "$wt" ] || return 1
  head="$(git -C "$wt" rev-parse --verify -q HEAD 2>/dev/null)" || return 1
  [ -n "$head" ] || return 1
  # main may be 'main' or 'master'; pick whichever resolves.
  mainref="$(git -C "$wt" rev-parse --verify -q main 2>/dev/null \
            || git -C "$wt" rev-parse --verify -q master 2>/dev/null)" || mainref=""
  [ -n "$mainref" ] || return 1
  # HEAD is an ancestor of (or equal to) main → no work beyond main → NOT working.
  git -C "$wt" merge-base --is-ancestor "$head" "$mainref" 2>/dev/null && return 1
  return 0
}

# pid_alive <file>: id:1b11 — true if the claim records a numeric live_pid that is still a
# live process (kill -0). Lets a STANDALONE long-running job that has NO worktree to anchor
# on (e.g. a multi-hour local-LLM drain adopted via acquire-resource.sh --pid) keep its
# lease past the mtime TTL for as long as the process actually lives, then auto-expire the
# instant it dies. Keyed on the DEDICATED live_pid field (NOT the incidental .pid = claim.sh's
# own $$), so a claim only opts into PID-anchored liveness when an explicit --pid was passed —
# existing callers (no --pid → no live_pid) are wholly unaffected, no PID-reuse exposure.
# CAVEAT: PID reuse — a recycled live_pid reads as alive; this only ever EXTENDS a claim's
# life (conservative/safe: at worst the relay defers an intensive unit it needn't have).
pid_alive() {
  local f="$1" pid
  pid="$(jq -r '.live_pid // ""' "$f" 2>/dev/null)" || pid=""
  [ -n "$pid" ] || return 1
  case "$pid" in *[!0-9]*) return 1 ;; esac   # numeric only
  kill -0 "$pid" 2>/dev/null
}

# heartbeat_alive_for_run <runId>: id:33d3 — true if heartbeat.sh reports the run as
# "alive". Fail-safe: any error (heartbeat.sh not found, bad output, absent marker) →
# return 1 (NOT alive), so the worktree clause falls back to mtime-TTL (the safe/D2
# direction). Never introduces a new TTL knob — heartbeat.sh's own HEARTBEAT_TTL governs.
heartbeat_alive_for_run() {
  local run="$1"
  [ -n "$run" ] || return 1
  local hb_script status
  hb_script="$(dirname "$0")/heartbeat.sh"
  [ -x "$hb_script" ] || return 1
  status="$("$hb_script" status "$run" 2>/dev/null || true)"
  [ "$status" = "alive" ]
}

# is_live <file>: a claim is live if its mtime is fresh OR (id:7570, id:33d3) its worktree
# is still working AND the claim's run heartbeat is alive, OR (id:1b11) its recorded
# live_pid is still alive. The worktree clause (id:7570) is gated on the run heartbeat
# (id:33d3): committed git objects persist after the owning process dies, so the worktree
# alone is not a liveness signal — only a FRESH heartbeat backing it extends the lease past
# mtime-TTL. Dead/absent heartbeat → worktree clause does not extend liveness; the claim
# falls back to the ordinary mtime-TTL (D2). Single liveness predicate peek/reap/acquire share.
is_live() {
  local f="$1"
  [ -f "$f" ] || return 1
  is_fresh "$f" && return 0
  if worktree_working "$f"; then
    local run_id
    run_id="$(jq -r '.runId // ""' "$f" 2>/dev/null)" || run_id=""
    heartbeat_alive_for_run "$run_id" && return 0
  fi
  pid_alive "$f"
}

cmd="${1:-}"; shift || true

case "$cmd" in
  acquire)
    key="${1:-}"; shift || true
    [ -n "$key" ] || { echo "claim.sh acquire: <key> required" >&2; exit 2; }
    repo=""; run=""; mode=""; item=""; worktree=""; live_pid=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --repo)     repo="${2:-}";     shift 2 ;;
        --run)      run="${2:-}";      shift 2 ;;
        --mode)     mode="${2:-}";     shift 2 ;;
        --item)     item="${2:-}";     shift 2 ;;
        --worktree) worktree="${2:-}"; shift 2 ;;
        --pid)      live_pid="${2:-}"; shift 2 ;;   # id:1b11 — PID to anchor liveness on (a standalone long job with no worktree)
        *) echo "claim.sh acquire: unknown arg '$1'" >&2; exit 2 ;;
      esac
    done
    sk="$(safekey "$key")"
    shard="$CLAIMS/$sk.json"
    exec 9>"$LOCK"
    flock -w 30 9 || { echo "claim.sh acquire: lock timeout" >&2; exit 1; }
    if is_live "$shard"; then
      # Re-entrant per run: a live claim held by the SAME runId is re-acquirable (the run
      # already owns the repo — e.g. the review→execute re-chain) and the write below
      # refreshes its mtime (heartbeat). A live claim held by a DIFFERENT run is REFUSED.
      # "Live" (id:7570) = fresh mtime OR a working held worktree, so a long child can't be
      # stolen mid-work just because its TTL elapsed.
      holder_run="$(jq -r '.runId // ""' "$shard" 2>/dev/null)"
      if [ -z "$run" ] || [ "$holder_run" != "$run" ]; then
        jq -c '.' "$shard" >&2 2>/dev/null || cat "$shard" >&2
        flock -u 9 || true
        log "acquire REFUSED key=$key (held by run=$holder_run, requester=$run)"
        exit 1
      fi
    fi
    ts="$(date '+%Y-%m-%dT%H:%M:%S%z')"
    tmp="$CLAIMS/.$sk.tmp"
    # id:7570 — preserve an existing worktree field on a re-entrant refresh when this call
    # didn't pass one, so a heartbeat-via-acquire doesn't drop the long-child liveness anchor.
    if [ -z "$worktree" ] && [ -f "$shard" ]; then
      worktree="$(jq -r '.worktree // ""' "$shard" 2>/dev/null)" || worktree=""
    fi
    # id:1b11 — preserve an existing live_pid on a re-entrant refresh when this call didn't
    # pass --pid, so a heartbeat-via-acquire doesn't drop the standalone-job liveness anchor.
    if [ -z "$live_pid" ] && [ -f "$shard" ]; then
      live_pid="$(jq -r '.live_pid // ""' "$shard" 2>/dev/null)" || live_pid=""
    fi
    jq -n --arg key "$key" --arg repo "$repo" --arg run "$run" \
          --arg pid "$$" --arg mode "$mode" --arg item "$item" --arg ts "$ts" \
          --arg worktree "$worktree" --arg live_pid "$live_pid" \
      '{key:$key, repo:$repo, runId:$run, pid:$pid, mode:$mode, item:$item, worktree:$worktree, live_pid:$live_pid, claimed_at:$ts}' \
      >"$tmp"
    mv "$tmp" "$shard"
    flock -u 9 || true
    log "acquire key=$key repo=$repo run=$run mode=$mode item=$item"
    echo "$sk"
    ;;

  release)
    key="${1:-}"; shift || true
    [ -n "$key" ] || { echo "claim.sh release: <key> required" >&2; exit 2; }
    run=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --run) run="${2:-}"; shift 2 ;;
        *) echo "claim.sh release: unknown arg '$1'" >&2; exit 2 ;;
      esac
    done
    sk="$(safekey "$key")"
    shard="$CLAIMS/$sk.json"
    exec 9>"$LOCK"
    flock -w 30 9 || { echo "claim.sh release: lock timeout" >&2; exit 1; }
    if [ -f "$shard" ]; then
      # Run-scoped: with --run, only release a claim THIS run holds — so a
      # "claimed-elsewhere" handback can safely call release without deleting the
      # other run's claim. Without --run, force-release (admin/cleanup).
      holder_run="$(jq -r '.runId // ""' "$shard" 2>/dev/null)"
      if [ -z "$run" ] || [ "$holder_run" = "$run" ]; then
        mv "$shard" "$DONE/$sk.json"
        log "release key=$key run=$run"
      else
        log "release SKIPPED key=$key (held by run=$holder_run, requester=$run)"
      fi
    fi
    flock -u 9 || true
    ;;

  heartbeat)
    # id:7570 — refresh a held claim's mtime so a legitimately-long child (>TTL) keeps its
    # lease. Run-scoped with --run (only refresh a claim THIS run holds); unscoped touches
    # any present claim. Idempotent: exit 0 even when the claim is absent.
    key="${1:-}"; shift || true
    [ -n "$key" ] || { echo "claim.sh heartbeat: <key> required" >&2; exit 2; }
    run=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --run) run="${2:-}"; shift 2 ;;
        *) echo "claim.sh heartbeat: unknown arg '$1'" >&2; exit 2 ;;
      esac
    done
    sk="$(safekey "$key")"
    shard="$CLAIMS/$sk.json"
    exec 9>"$LOCK"
    flock -w 30 9 || { echo "claim.sh heartbeat: lock timeout" >&2; exit 1; }
    if [ -f "$shard" ]; then
      holder_run="$(jq -r '.runId // ""' "$shard" 2>/dev/null)"
      if [ -z "$run" ] || [ "$holder_run" = "$run" ]; then
        touch "$shard"
        log "heartbeat key=$key run=$run"
      else
        log "heartbeat SKIPPED key=$key (held by run=$holder_run, requester=$run)"
      fi
    fi
    flock -u 9 || true
    ;;

  peek)
    # Non-consuming: emit each LIVE claim as compact JSON; skip dead (id:7570 is_live).
    shopt -s nullglob
    for f in $(printf '%s\n' "$CLAIMS"/*.json | sort); do
      [ -f "$f" ] || continue
      is_live "$f" || continue
      jq -c '.' "$f" 2>/dev/null || true
    done
    ;;

  reap)
    exec 9>"$LOCK"
    flock -w 30 9 || { echo "claim.sh reap: lock timeout" >&2; exit 1; }
    shopt -s nullglob
    n=0
    for f in $(printf '%s\n' "$CLAIMS"/*.json | sort); do
      [ -f "$f" ] || continue
      # id:7570 — only reap a DEAD claim (stale mtime AND no working worktree). A stale
      # claim whose worktree still has commits beyond main is a live long child; keep it.
      is_live "$f" && continue
      mv "$f" "$DONE/$(basename "$f")"
      n=$((n+1))
    done
    flock -u 9 || true
    [ "$n" -gt 0 ] && log "reap reaped=$n" || true
    echo "reaped $n" >&2
    ;;

  ""|-h|--help|help)
    sed -n '2,56p' "$0"
    ;;

  *)
    echo "claim.sh: unknown subcommand '$cmd' (use acquire|release|heartbeat|peek|reap)" >&2
    exit 2
    ;;
esac
