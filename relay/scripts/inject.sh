#!/usr/bin/env bash
# inject.sh — on-demand high-priority executor-task injection into the running relay pool
# (id:baf1). A user (or another session) enqueues a unit; the pool's discovery step calls
# `take` each round and dispatches the injected unit AHEAD of its normal verdict-class
# schedule (execute→review→hard→handoff). Rides the cluster registry pattern (id:ebfb):
# per-shard JSON files under an inbox dir, flock-guarded.
#
# Subcommands:
#   add <repo> [--item ID] [--verdict V] [--prompt TEXT]
#       Enqueue a unit. Writes inject.d/<token>.json. Prints the token.
#   peek [--repo NAME]
#       Emit each pending injection as one compact JSON object per line. NON-consuming
#       (for RELAY_STATUS projection / status display).
#   take [--repo NAME]
#       Atomically emit AND consume each pending injection (one JSON per line), moving its
#       shard to inject.done/. Used by the pool's discovery step. flock-guarded.
#
# SCOPE (routed:a923) — `--repo NAME` restricts the operation to shards whose `.repo` is
# exactly NAME; every other shard is LEFT PENDING. Without it, `take` drains the inbox
# GLOBALLY, so a repo-scoped pool (`/relay --only X`) would consume — and then be unable to
# work — a unit another session injected for a different repo. Consumed injections have no
# re-enqueue path, so such a steal LOSES the unit from both the inbox and the ledger
# (observed 2026-08-11, run relay-20260811-221031-22542). The pool passes its `--only` scope
# through discover-prelude.sh and the mid-round take; an UNSCOPED pool still drains globally
# (today's behaviour). Same steal-once shape as the id:cd94 run-scoped STOP sentinel.
#
# Paths: base = $INJECT_BASE (default ~/.config/relay). Inbox = $base/inject.d,
# consumed = $base/inject.done, lock = $base/.inject.lock. Override $INJECT_BASE for tests.
set -euo pipefail

INJECT_BASE="${INJECT_BASE:-$HOME/.config/relay}"
INBOX="$INJECT_BASE/inject.d"
DONE="$INJECT_BASE/inject.done"
LOCK="$INJECT_BASE/.inject.lock"
LOG="${INJECT_LOG:-$HOME/.claude/logs/relay-inject.log}"

mkdir -p "$INBOX" "$DONE" "$(dirname "$LOG")"
: >>"$LOCK"

log() { printf '%s inject.sh %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >>"$LOG" 2>/dev/null || true; }

cmd="${1:-}"; shift || true

case "$cmd" in
  add)
    repo="${1:-}"; shift || true
    [ -n "$repo" ] || { echo "inject.sh add: <repo> required" >&2; exit 2; }
    verdict="execute"; item=""; prompt=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --item)    item="${2:-}";    shift 2 ;;
        --verdict) verdict="${2:-}"; shift 2 ;;
        --prompt)  prompt="${2:-}";  shift 2 ;;
        *) echo "inject.sh add: unknown arg '$1'" >&2; exit 2 ;;
      esac
    done
    case "$verdict" in execute|review|hard|handoff) ;; *)
      echo "inject.sh add: --verdict must be execute|review|hard|handoff (got '$verdict')" >&2; exit 2 ;;
    esac
    token="inj-$(date '+%Y%m%d-%H%M%S')-$$-${RANDOM}"
    ts="$(date '+%Y-%m-%dT%H:%M:%S%z')"
    # Build JSON with jq -n --arg (apostrophes/braces safe; never inline into the shell).
    tmp="$INBOX/.$token.tmp"
    jq -n --arg token "$token" --arg repo "$repo" --arg verdict "$verdict" \
          --arg item "$item" --arg prompt "$prompt" --arg ts "$ts" \
      '{token:$token, repo:$repo, verdict:$verdict, item:$item, prompt:$prompt, requested_at:$ts}' \
      >"$tmp"
    mv "$tmp" "$INBOX/$token.json"
    log "add repo=$repo verdict=$verdict item=$item token=$token"
    echo "$token"
    ;;

  peek|take)
    # Shared arg parsing: --repo NAME scopes BOTH subcommands to one repo (routed:a923).
    scope=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --repo) scope="${2:-}"; shift 2 ;;
        *) echo "inject.sh $cmd: unknown arg '$1' (only --repo NAME)" >&2; exit 2 ;;
      esac
    done
    # in_scope <shard-file> — true when unscoped, or when the shard's .repo matches exactly.
    in_scope() {
      [ -z "$scope" ] && return 0
      [ "$(jq -r '.repo // ""' "$1" 2>/dev/null)" = "$scope" ]
    }

    if [ "$cmd" = peek ]; then
      # Non-consuming: emit each pending shard as compact JSON, sorted by filename (FIFO-ish).
      shopt -s nullglob
      for f in $(printf '%s\n' "$INBOX"/*.json | sort); do
        [ -f "$f" ] || continue
        in_scope "$f" || continue
        jq -c '.' "$f" 2>/dev/null || true
      done
      exit 0
    fi

    # take — atomic emit+consume under flock: list pending shards, print each, move to
    # inject.done. Out-of-scope shards are SKIPPED, never consumed (routed:a923).
    exec 9>"$LOCK"
    flock -w 30 9 || { echo "inject.sh take: lock timeout" >&2; exit 1; }
    shopt -s nullglob
    n=0; skipped=0
    for f in $(printf '%s\n' "$INBOX"/*.json | sort); do
      [ -f "$f" ] || continue
      if ! in_scope "$f"; then skipped=$((skipped+1)); continue; fi
      jq -c '.' "$f" 2>/dev/null || continue
      mv "$f" "$DONE/$(basename "$f")"
      n=$((n+1))
    done
    flock -u 9 || true
    { [ "$n" -gt 0 ] || [ "$skipped" -gt 0 ]; } \
      && log "take scope=${scope:-<global>} consumed=$n left-pending=$skipped" || true
    ;;

  ""|-h|--help|help)
    sed -n '2,26p' "$0"
    ;;

  *)
    echo "inject.sh: unknown subcommand '$cmd' (use add|peek|take)" >&2
    exit 2
    ;;
esac
