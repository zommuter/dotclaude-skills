#!/usr/bin/env bash
# relay-watchdog.sh — outage watchdog for the local relay loop (id:98f0).
#
# The relay pool's in-session babysitter (/loop, ScheduleWakeup, CronCreate) dies WITH the
# session on an API outage / host kill, and a cloud /schedule routine can't reach local repos;
# an OS-timer running `claude -p` hits the permission wall (memory `babysitter-durable-cron-no-op`).
# So this watchdog deliberately does NOT run `claude -p`. It is a cheap systemd `--user` timer
# (modelled on tools/quota-sample.timer) that reads the SHARED run-heartbeat (id:e149) and, when
# a prior relay loop DIED without a clean stop, NOTIFIES the human for a one-tap restart and logs
# the death to an evidence file. That evidence log is the GATE (design
# `docs/meeting-notes/2026-06-22-1546-relay-outage-resilience.md`) for re-opening the deferred
# heavy build (curated allowlist / dedicated-OS-user; id:2d01) — observe-before-preventing.
#
# It is idempotent and de-duplicated: each dead run is notified+logged ONCE (tracked in a small
# state file), so a 15-min timer doesn't spam. A clean shutdown leaves no marker; a restarted
# loop reaps the dead marker (heartbeat.sh reap, via id:7809), after which the watchdog goes
# quiet. NEVER mutates repos or runs the pool — pure detect+notify.
#
# Notification order (first that works wins; the evidence log is always written regardless):
#   1. $RELAY_WATCHDOG_NOTIFY_CMD — a custom command (e.g. an ntfy/phone push); the message is
#      piped to it on stdin AND passed as $1/$2 (title, body). Set this for true off-host push.
#   2. notify-send — desktop notification (best-effort; needs a session DISPLAY/DBUS).
#   3. logger / stderr — last-resort durable trace.
#
# Env (all optional; defaults match the relay loop so detection "just works"):
#   HEARTBEAT_BASE          run-heartbeat store (default ~/.config/relay/heartbeats)
#   RELAY_WATCHDOG_STATE    de-dup state file   (default ~/.config/relay/watchdog-notified)
#   RELAY_WATCHDOG_EVIDENCE outage-death JSONL  (default ~/.claude/logs/relay-outage-deaths.jsonl)
#   RELAY_WATCHDOG_LOG      tick/diagnostic log (default ~/.claude/logs/relay-watchdog.log)
#   RELAY_WATCHDOG_NOTIFY_CMD  custom push command (see above)
#   RELAY_HEARTBEAT_SH      path to heartbeat.sh (auto-resolved otherwise)
#
# SECOND LIVENESS DOMAIN (id:54fc, 2026-07-07 meeting Item 3): the mechanical discovery
# PRODUCER (id:9d97 — a `--user` `.timer` running discover-repos-mechanical.sh every 15 min,
# see tools/discover-repos-mechanical.timer) is a SEPARATE process from the dispatch loop
# checked above — it can die (timer disabled, script erroring) while the dispatch loop is
# perfectly healthy, which would otherwise read as "no work" rather than "discovery is down".
# The producer beats its OWN heartbeat marker (a fixed runId, NOT one of the dispatch loop's
# per-round relay-* runIds) each time it completes successfully. This watchdog checks that
# marker as an INDEPENDENT domain, with its OWN TTL derived from the timer's cadence (15 min)
# plus one missed-run allowance, and reports it distinctly (separate notify title/body,
# separate de-dup state, separate evidence "domain" tag) — never folded into the generic
# "Relay loop died" dispatch-domain message, so the operator can tell "discovery down" apart
# from "pool idle / no work". Observe-only, same as the dispatch-domain check: NEVER restarts
# the timer or touches repos. A marker that has never existed (producer never run yet) is NOT
# reported — only a PRESENT-but-STALE marker counts, mirroring the dispatch domain's own
# present-but-stale semantics (heartbeat.sh's dead-runs never emits absent markers either).
#   DISCOVERY_PRODUCER_RUN_ID       producer heartbeat runId (default: discovery-producer;
#                                   MUST match discover-repos-mechanical.sh's own default/override)
#   RELAY_WATCHDOG_PRODUCER_TTL     producer staleness TTL, seconds (default 2100 = 15-min
#                                   timer cadence × 2 + buffer, i.e. tolerates one missed run)
#   RELAY_WATCHDOG_PRODUCER_STATE   producer de-dup state file (default: $RELAY_WATCHDOG_STATE.producer)
#
# Exit 0 always on a normal tick (a watchdog that exits non-zero would spam systemd's journal /
# OnFailure); real misuse is the only non-zero path.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Resolve heartbeat.sh: installed symlink first, then the sibling repo path.
HB="${RELAY_HEARTBEAT_SH:-}"
if [ -z "$HB" ]; then
  for cand in "$HOME/.claude/skills/relay/scripts/heartbeat.sh" "$SCRIPT_DIR/../relay/scripts/heartbeat.sh"; do
    [ -x "$cand" ] && { HB="$cand"; break; }
  done
fi

STATE="${RELAY_WATCHDOG_STATE:-$HOME/.config/relay/watchdog-notified}"
EVID="${RELAY_WATCHDOG_EVIDENCE:-$HOME/.claude/logs/relay-outage-deaths.jsonl}"
LOG="${RELAY_WATCHDOG_LOG:-$HOME/.claude/logs/relay-watchdog.log}"
NOTIFY_CMD="${RELAY_WATCHDOG_NOTIFY_CMD:-}"

PRODUCER_RUN_ID="${DISCOVERY_PRODUCER_RUN_ID:-discovery-producer}"
PRODUCER_TTL="${RELAY_WATCHDOG_PRODUCER_TTL:-2100}"
PRODUCER_STATE="${RELAY_WATCHDOG_PRODUCER_STATE:-${STATE}.producer}"

mkdir -p "$(dirname "$STATE")" "$(dirname "$EVID")" "$(dirname "$LOG")" "$(dirname "$PRODUCER_STATE")"
log() { printf '%s relay-watchdog %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >>"$LOG" 2>/dev/null || true; }

if [ -z "$HB" ] || [ ! -x "$HB" ]; then
  log "FATAL heartbeat.sh not found (set RELAY_HEARTBEAT_SH) — cannot detect liveness"
  echo "relay-watchdog: heartbeat.sh not found (set RELAY_HEARTBEAT_SH)" >&2
  exit 2
fi

notify() {  # <title> <body>
  local title="$1" body="$2"
  if [ -n "$NOTIFY_CMD" ]; then
    printf '%s\n%s\n' "$title" "$body" | "$NOTIFY_CMD" "$title" "$body" >>"$LOG" 2>&1 || \
      log "notify-cmd failed: $NOTIFY_CMD"
    return
  fi
  if command -v notify-send >/dev/null 2>&1; then
    DISPLAY="${DISPLAY:-:0}" notify-send -u critical "$title" "$body" >>"$LOG" 2>&1 \
      && return || log "notify-send failed (no session DISPLAY/DBUS?)"
  fi
  command -v logger >/dev/null 2>&1 && logger -t relay-watchdog "$title — $body" || true
}

# ── Domain 1: dispatch loop (id:98f0) ─────────────────────────────────────────
# Current dead run-ids (present-but-stale markers). dead-runs emits one JSON line per dead run.
# --prefix 'relay-*' scopes this to the DISPATCH loop's own runId namespace (relay-<ts>-<rand>)
# so the INDEPENDENT discovery-producer marker (fixed runId "discovery-producer", 2100s domain-2
# TTL, id:54fc) — which ages into "dead" against heartbeat's default 3600s TTL — never trips a
# spurious dispatch-loop "Relay loop died" alarm here. Domain 2 below alarms on the producer
# distinctly (2026-07-07 strong-model review).
dead="$("$HB" dead-runs --prefix 'relay-*' 2>>"$LOG" || true)"
current_ids="$(printf '%s\n' "$dead" | jq -r 'select(.runId!=null and .runId!="")|.runId' 2>/dev/null | sort -u)"

if [ -z "$current_ids" ]; then
  # Nothing dead — clear the de-dup state so a future death notifies cleanly.
  rm -f "$STATE" 2>/dev/null || true
  log "tick: no dead runs (dispatch-loop domain)"
else
  # NEW deaths = currently-dead ids not already notified. Rewrite the state to the CURRENT dead
  # set (drops ids that were reaped/restarted), so a reaped-then-redied id could notify again.
  touch "$STATE"
  new_ids=()
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    grep -qxF "$id" "$STATE" 2>/dev/null || new_ids+=("$id")
  done <<<"$current_ids"
  printf '%s\n' "$current_ids" >"$STATE"

  if [ ${#new_ids[@]} -eq 0 ]; then
    log "tick: ${current_ids//$'\n'/ } already notified (no repeat, dispatch-loop domain)"
  else
    # Evidence log (the re-open gate) — one JSONL line per NEW dead run, with detection time.
    detected_at="$(date -Is)"
    for id in "${new_ids[@]}"; do
      printf '%s\n' "$dead" | jq -c --arg id "$id" --arg t "$detected_at" --arg d "dispatch-loop" \
        'select(.runId==$id) + {detected_at:$t, source:"relay-watchdog", domain:$d}' >>"$EVID" 2>/dev/null || \
        printf '{"runId":"%s","detected_at":"%s","source":"relay-watchdog","domain":"dispatch-loop"}\n' "$id" "$detected_at" >>"$EVID"
    done

    ids_str="$(printf '%s ' "${new_ids[@]}")"
    notify "⚠️ Relay loop died (${#new_ids[@]} new)" \
      "Dead run(s): ${ids_str}— the pool stopped WITHOUT a clean shutdown (no heartbeat for >TTL). Restart with /relay --afk; on restart its SAFE (ledger-only) leftovers auto-reconcile and the rest surface in REVIEW_ME (id:7809). Evidence: $EVID"
    log "NOTIFIED ${#new_ids[@]} new dead run(s): ${ids_str}(dispatch-loop domain)"
    echo "relay-watchdog: notified ${#new_ids[@]} new dead run(s): ${ids_str}(dispatch-loop domain)" >&2
  fi
fi

# ── Domain 2: mechanical discovery producer (id:54fc) ────────────────────────
# Independent check: a fixed runId, its own TTL, its own de-dup state, its own evidence tag.
# Only a PRESENT-but-STALE marker is "down" — a producer that has simply never beaten yet
# (never installed/run) is not reported here (mirrors dead-runs' present-but-stale contract).
producer_status="unknown"
status_tmp="$(mktemp)"
HEARTBEAT_TTL="$PRODUCER_TTL" "$HB" status "$PRODUCER_RUN_ID" >"$status_tmp" 2>>"$LOG" || true
producer_status="$(cat "$status_tmp" 2>/dev/null || echo unknown)"
rm -f "$status_tmp" 2>/dev/null || true

if [ "$producer_status" = "dead" ]; then
  # Present-but-stale: the producer marker exists (heartbeat.sh distinguishes absent via rc=2 /
  # "absent" text; "dead" only prints for a present-but-stale marker) and is older than
  # PRODUCER_TTL — report distinctly, de-duped via its own state file.
  if [ ! -f "$PRODUCER_STATE" ]; then
    detected_at="$(date -Is)"
    printf '{"runId":"%s","detected_at":"%s","source":"relay-watchdog","domain":"discovery-producer"}\n' \
      "$PRODUCER_RUN_ID" "$detected_at" >>"$EVID"
    notify "⚠️ Discovery producer stale/down" \
      "The mechanical discovery producer (${PRODUCER_RUN_ID}, id:9d97) has not beaten its heartbeat in over ${PRODUCER_TTL}s — its .timer is likely disabled or the script is erroring. This is DISTINCT from the dispatch-loop pool being idle: discovery snapshots are stale, not just 'no work'. Evidence: $EVID"
    touch "$PRODUCER_STATE"
    log "NOTIFIED discovery-producer stale/down (${PRODUCER_RUN_ID})"
    echo "relay-watchdog: notified discovery-producer stale/down (${PRODUCER_RUN_ID})" >&2
  else
    log "tick: ${PRODUCER_RUN_ID} already notified (no repeat, discovery-producer domain)"
  fi
else
  # Alive or absent — clear de-dup state so a FUTURE staleness notifies cleanly.
  rm -f "$PRODUCER_STATE" 2>/dev/null || true
  log "tick: discovery-producer domain status=${producer_status}"
fi

exit 0
