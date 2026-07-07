#!/usr/bin/env bash
# heartbeat.sh — run-level liveness marker for the relay loop (id:e149).
#
# The FOUNDATION shared by auto-reconcile-on-restart (id:7809) and the outage
# watchdog (id:98f0): one source of truth for "is a prior relay run still alive,
# or did it die?" — NO separate `.relayactive` file (design
# `docs/meeting-notes/2026-06-22-1546-relay-outage-resilience.md`).
#
# WHY a dedicated marker rather than the claim.sh shards (id:0902/ebfb):
#   claim.sh liveness (is_live) deliberately KEEPS a stale-mtime claim alive when
#   its worktree still has commits beyond main (id:7570 long-child) or its pid is
#   alive (id:1b11). That is exactly WRONG for detecting a dead LOOP: an outage
#   kills the session but LEAVES the half-done worktree with commits — which would
#   read "live" forever and mask the death. The run heartbeat is therefore PURE
#   ts+TTL staleness: a run is dead iff its last heartbeat is older than TTL,
#   regardless of any worktree it left behind. The orphan worktree IS what the
#   downstream reconcile (id:7809) then disposes.
#
# A run that exits CLEANLY calls `stop` and leaves no marker, so it is never
# flagged dead. Only a run that died WITHOUT stopping leaves a stale marker.
#
# Subcommands:
#   beat <runId> [--pid PID]
#       Create-or-refresh the run marker: write heartbeats/<runId>.json with a
#       fresh heartbeat_ts (epoch). Preserves started_at across refreshes (so the
#       first beat stamps it, later beats keep it). --pid records the owning pid
#       (advisory display only — staleness is ts-based, not pid-based, so a recycled
#       pid never masks a real death). Idempotent; flock'd; prints the safe runId.
#   stop <runId>
#       Clean shutdown: move heartbeats/<runId>.json → heartbeats.done/. Idempotent
#       (exit 0 even when absent). A stopped run leaves no stale marker.
#   status <runId>
#       Print one word — alive | dead | absent — and set exit code 0 | 1 | 2.
#       "dead" = a present marker whose heartbeat_ts is older than TTL.
#   dead-runs [--prefix GLOB]
#       Emit one compact JSON line per PRESENT-but-STALE run marker
#       ({runId,pid,started_at,heartbeat_ts,age_s}). This is the set a watchdog
#       notifies on and a restarting loop auto-reconciles. Cleanly-stopped and
#       still-alive runs are NOT emitted.
#       --prefix GLOB scopes the sweep to markers whose `runId` field matches the shell glob
#       (e.g. --prefix 'relay-*'), exactly like `reap --prefix`; non-matching stale markers are
#       omitted. This keeps the DETECTION side namespace-scoped the same way the ARCHIVE side
#       (reap) already is: the dispatch-loop consumers (relay-watchdog.sh domain 1, relay-loop.js
#       auto-reconcile-on-restart) MUST pass --prefix 'relay-*' so the INDEPENDENT
#       discovery-producer marker (fixed runId "discovery-producer", 2100s domain-2 TTL, id:54fc)
#       — whose default 3600s heartbeat TTL ages it into "dead" for the dispatch domain — never
#       trips a spurious dispatch-loop "Relay loop died" alarm or a per-restart --all reconcile
#       (strong-model second-opinion review, 2026-07-07). Without --prefix, every present-but-stale
#       marker is emitted (legacy default), matching reap's default.
#   live-runs
#       Emit one compact JSON line per ALIVE run marker (heartbeat within TTL).
#   list
#       Emit every present marker as JSON with an added "state" field.
#   reap [--prefix GLOB]
#       Archive every PRESENT-but-STALE (dead) marker → heartbeats.done (flock'd). Called by
#       the loop's auto-reconcile-on-restart (id:7809) AFTER it has disposed a dead run's
#       orphans, so the dead run is not re-reconciled or re-notified by the watchdog (id:98f0)
#       forever. Prints "reaped N" to stderr. NEVER touches an alive marker.
#       --prefix GLOB scopes the sweep to markers whose `runId` field matches the shell glob
#       (e.g. --prefix 'relay-*'); non-matching markers are left untouched even if stale.
#       Without --prefix, every present-but-stale marker is reaped (legacy default). The
#       dispatch loop's auto-reconcile-on-restart call MUST pass --prefix 'relay-*' (its own
#       runId namespace, `relay-<ts>-<rand>`) so a restart never reaps the INDEPENDENT
#       discovery-producer marker (fixed runId "discovery-producer", id:54fc) — the two
#       liveness domains are alarmed on separately by relay-watchdog.sh, and an unscoped reap
#       would silently clear the producer's down-alarm on every dispatch-loop restart
#       (cross-domain alarm suppression, strong-model audit run 70 finding 2).
#
# Paths: base = $HEARTBEAT_BASE (default ~/.config/relay/heartbeats), consumed =
# $HEARTBEAT_BASE/../heartbeats.done, lock = $HEARTBEAT_BASE/../.heartbeat.lock.
# TTL = $HEARTBEAT_TTL seconds (default 3600). The loop beats once per round (post-discovery)
# AND once per settled unit (integrator), so a healthy pool refreshes every few minutes; the TTL
# only has to exceed the LONGEST plausible quiet stretch (a long single child with no
# integration). 3600s (1h) clears a slow multi-wave round without false-flagging a live pool as
# dead — the false-positive a too-tight 1800s default produced (a ~40-min round read "dead",
# 2026-06-29). The <safeRunId> replaces '/' and ':' with '_'. Override $HEARTBEAT_BASE for tests.
set -euo pipefail

HEARTBEAT_BASE="${HEARTBEAT_BASE:-$HOME/.config/relay/heartbeats}"
DONE="$(dirname "$HEARTBEAT_BASE")/heartbeats.done"
LOCK="$(dirname "$HEARTBEAT_BASE")/.heartbeat.lock"
TTL="${HEARTBEAT_TTL:-3600}"
LOG="${HEARTBEAT_LOG:-$HOME/.claude/logs/relay-heartbeat.log}"

mkdir -p "$HEARTBEAT_BASE" "$DONE" "$(dirname "$LOG")"
: >>"$LOCK"

log() { printf '%s heartbeat.sh %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >>"$LOG" 2>/dev/null || true; }

# safekey: replace '/' and ':' with '_'.
safekey() { printf '%s' "$1" | tr '/:' '__'; }

# hb_ts <file>: echo the recorded heartbeat_ts (epoch). Falls back to the file's
# mtime if the field is missing/garbled (back-compat / robustness).
hb_ts() {
  local f="$1" ts
  ts="$(jq -r '.heartbeat_ts // empty' "$f" 2>/dev/null)" || ts=""
  case "$ts" in ''|*[!0-9]*) ts="$(stat -c %Y "$f" 2>/dev/null || echo 0)" ;; esac
  printf '%s' "$ts"
}

# is_alive <file>: pure ts+TTL staleness — alive iff heartbeat_ts within TTL of now.
# Deliberately ignores worktrees/pids (see header): a dead loop is dead even with a
# left-behind working worktree.
is_alive() {
  local f="$1" now ts
  [ -f "$f" ] || return 1
  now="$(date +%s)"
  ts="$(hb_ts "$f")"
  [ $((now - ts)) -lt "$TTL" ]
}

# emit_with_state <file> <state>: print the marker JSON with an added age_s + state.
emit_with_state() {
  local f="$1" state="$2" now ts
  now="$(date +%s)"; ts="$(hb_ts "$f")"
  jq -c --arg state "$state" --argjson age "$((now - ts))" \
     '. + {age_s:$age, state:$state}' "$f" 2>/dev/null || true
}

cmd="${1:-}"; shift || true

case "$cmd" in
  beat)
    run="${1:-}"; shift || true
    [ -n "$run" ] || { echo "heartbeat.sh beat: <runId> required" >&2; exit 2; }
    pid=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --pid) pid="${2:-}"; shift 2 ;;
        *) echo "heartbeat.sh beat: unknown arg '$1'" >&2; exit 2 ;;
      esac
    done
    sk="$(safekey "$run")"
    marker="$HEARTBEAT_BASE/$sk.json"
    now="$(date +%s)"
    iso="$(date '+%Y-%m-%dT%H:%M:%S%z')"
    exec 9>"$LOCK"
    flock -w 30 9 || { echo "heartbeat.sh beat: lock timeout" >&2; exit 1; }
    # Preserve started_at across refreshes; stamp it on the first beat.
    started_at="$now"; started_iso="$iso"
    if [ -f "$marker" ]; then
      prev="$(jq -r '.started_at // empty' "$marker" 2>/dev/null)" || prev=""
      case "$prev" in ''|*[!0-9]*) : ;; *) started_at="$prev"
        started_iso="$(jq -r '.started_iso // empty' "$marker" 2>/dev/null)" ;; esac
      [ -z "$pid" ] && pid="$(jq -r '.pid // empty' "$marker" 2>/dev/null)" || true
    fi
    tmp="$HEARTBEAT_BASE/.$sk.tmp"
    jq -n --arg run "$run" --arg pid "$pid" --arg host "$(hostname 2>/dev/null || echo '')" \
          --argjson started "$started_at" --arg started_iso "$started_iso" \
          --argjson hb "$now" --arg hb_iso "$iso" \
      '{runId:$run, pid:$pid, host:$host, started_at:$started, started_iso:$started_iso, heartbeat_ts:$hb, heartbeat_iso:$hb_iso}' \
      >"$tmp"
    mv "$tmp" "$marker"
    flock -u 9 || true
    log "beat run=$run pid=$pid"
    echo "$sk"
    ;;

  stop)
    run="${1:-}"; shift || true
    [ -n "$run" ] || { echo "heartbeat.sh stop: <runId> required" >&2; exit 2; }
    sk="$(safekey "$run")"
    marker="$HEARTBEAT_BASE/$sk.json"
    exec 9>"$LOCK"
    flock -w 30 9 || { echo "heartbeat.sh stop: lock timeout" >&2; exit 1; }
    [ -f "$marker" ] && { mv "$marker" "$DONE/$sk.json"; log "stop run=$run"; } || true
    flock -u 9 || true
    ;;

  status)
    run="${1:-}"; shift || true
    [ -n "$run" ] || { echo "heartbeat.sh status: <runId> required" >&2; exit 2; }
    sk="$(safekey "$run")"
    marker="$HEARTBEAT_BASE/$sk.json"
    if [ ! -f "$marker" ]; then echo absent; exit 2; fi
    if is_alive "$marker"; then echo alive; exit 0; else echo dead; exit 1; fi
    ;;

  dead-runs)
    prefix=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --prefix) prefix="${2:-}"; shift 2 ;;
        *) echo "heartbeat.sh dead-runs: unknown arg '$1'" >&2; exit 2 ;;
      esac
    done
    shopt -s nullglob
    for f in $(printf '%s\n' "$HEARTBEAT_BASE"/*.json | sort); do
      [ -f "$f" ] || continue
      is_alive "$f" && continue
      if [ -n "$prefix" ]; then
        runid="$(jq -r '.runId // empty' "$f" 2>/dev/null)" || runid=""
        # shellcheck disable=SC2254 # intentional glob match against --prefix
        case "$runid" in
          $prefix) : ;;
          *) continue ;;
        esac
      fi
      emit_with_state "$f" dead
    done
    ;;

  live-runs)
    shopt -s nullglob
    for f in $(printf '%s\n' "$HEARTBEAT_BASE"/*.json | sort); do
      [ -f "$f" ] || continue
      is_alive "$f" || continue
      emit_with_state "$f" alive
    done
    ;;

  list)
    shopt -s nullglob
    for f in $(printf '%s\n' "$HEARTBEAT_BASE"/*.json | sort); do
      [ -f "$f" ] || continue
      if is_alive "$f"; then emit_with_state "$f" alive; else emit_with_state "$f" dead; fi
    done
    ;;

  reap)
    prefix=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --prefix) prefix="${2:-}"; shift 2 ;;
        *) echo "heartbeat.sh reap: unknown arg '$1'" >&2; exit 2 ;;
      esac
    done
    exec 9>"$LOCK"
    flock -w 30 9 || { echo "heartbeat.sh reap: lock timeout" >&2; exit 1; }
    shopt -s nullglob
    n=0
    for f in $(printf '%s\n' "$HEARTBEAT_BASE"/*.json | sort); do
      [ -f "$f" ] || continue
      is_alive "$f" && continue
      if [ -n "$prefix" ]; then
        runid="$(jq -r '.runId // empty' "$f" 2>/dev/null)" || runid=""
        # shellcheck disable=SC2254 # intentional glob match against --prefix
        case "$runid" in
          $prefix) : ;;
          *) continue ;;
        esac
      fi
      mv "$f" "$DONE/$(basename "$f")"
      n=$((n+1))
    done
    flock -u 9 || true
    [ "$n" -gt 0 ] && log "reap reaped=$n prefix=${prefix:-<none>}" || true
    echo "reaped $n" >&2
    ;;

  ""|-h|--help|help)
    sed -n '2,66p' "$0"
    ;;

  *)
    echo "heartbeat.sh: unknown subcommand '$cmd' (use beat|stop|status|dead-runs|live-runs|list|reap)" >&2
    exit 2
    ;;
esac
