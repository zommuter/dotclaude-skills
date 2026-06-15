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
# Subcommands:
#   acquire <key> [--repo R] [--run RUNID] [--mode M] [--item ID]
#       Under flock: if claims/<safekey>.json exists AND is FRESH (mtime within TTL),
#       print the holder JSON to stderr and exit 1 (already claimed). Otherwise (absent
#       or stale) write the shard and exit 0, printing the safekey on stdout.
#   release <key>
#       Under flock: move claims/<safekey>.json → claims.done/ if present. Idempotent
#       (exit 0 even when absent).
#   peek
#       Non-consuming: emit each FRESH claim as one compact JSON line (stale skipped).
#   reap
#       Under flock: move every STALE (mtime older than TTL) shard → claims.done/.
#       Print "reaped N" to stderr.
#
# Paths: base = $CLAIM_BASE (default ~/.config/fables-turn). Claims = $base/claims,
# consumed = $base/claims.done, lock = $base/.claim.lock. TTL = $CLAIM_TTL seconds
# (default 1800). The <safekey> replaces '/' and ':' with '_' (original key kept in
# the JSON). Override $CLAIM_BASE for hermetic tests.
set -euo pipefail

CLAIM_BASE="${CLAIM_BASE:-$HOME/.config/fables-turn}"
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

cmd="${1:-}"; shift || true

case "$cmd" in
  acquire)
    key="${1:-}"; shift || true
    [ -n "$key" ] || { echo "claim.sh acquire: <key> required" >&2; exit 2; }
    repo=""; run=""; mode=""; item=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --repo) repo="${2:-}"; shift 2 ;;
        --run)  run="${2:-}";  shift 2 ;;
        --mode) mode="${2:-}"; shift 2 ;;
        --item) item="${2:-}"; shift 2 ;;
        *) echo "claim.sh acquire: unknown arg '$1'" >&2; exit 2 ;;
      esac
    done
    sk="$(safekey "$key")"
    shard="$CLAIMS/$sk.json"
    exec 9>"$LOCK"
    flock -w 30 9 || { echo "claim.sh acquire: lock timeout" >&2; exit 1; }
    if is_fresh "$shard"; then
      # Re-entrant per run: a fresh claim held by the SAME runId is re-acquirable (the run
      # already owns the repo — e.g. the review→execute re-chain) and the write below
      # refreshes its mtime (heartbeat). A fresh claim held by a DIFFERENT run is REFUSED.
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
    jq -n --arg key "$key" --arg repo "$repo" --arg run "$run" \
          --arg pid "$$" --arg mode "$mode" --arg item "$item" --arg ts "$ts" \
      '{key:$key, repo:$repo, runId:$run, pid:$pid, mode:$mode, item:$item, claimed_at:$ts}' \
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

  peek)
    # Non-consuming: emit each FRESH claim as compact JSON; skip stale.
    shopt -s nullglob
    for f in $(printf '%s\n' "$CLAIMS"/*.json | sort); do
      [ -f "$f" ] || continue
      is_fresh "$f" || continue
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
      is_fresh "$f" && continue
      mv "$f" "$DONE/$(basename "$f")"
      n=$((n+1))
    done
    flock -u 9 || true
    [ "$n" -gt 0 ] && log "reap reaped=$n" || true
    echo "reaped $n" >&2
    ;;

  ""|-h|--help|help)
    sed -n '2,28p' "$0"
    ;;

  *)
    echo "claim.sh: unknown subcommand '$cmd' (use acquire|release|peek|reap)" >&2
    exit 2
    ;;
esac
