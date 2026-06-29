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

mkdir -p "$(dirname "$STATE")" "$(dirname "$EVID")" "$(dirname "$LOG")"
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

# Current dead run-ids (present-but-stale markers). dead-runs emits one JSON line per dead run.
dead="$("$HB" dead-runs 2>>"$LOG" || true)"
current_ids="$(printf '%s\n' "$dead" | jq -r 'select(.runId!=null and .runId!="")|.runId' 2>/dev/null | sort -u)"

if [ -z "$current_ids" ]; then
  # Nothing dead — clear the de-dup state so a future death notifies cleanly.
  rm -f "$STATE" 2>/dev/null || true
  log "tick: no dead runs"
  exit 0
fi

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
  log "tick: ${current_ids//$'\n'/ } already notified (no repeat)"
  exit 0
fi

# Evidence log (the re-open gate) — one JSONL line per NEW dead run, with detection time.
detected_at="$(date -Is)"
for id in "${new_ids[@]}"; do
  printf '%s\n' "$dead" | jq -c --arg id "$id" --arg t "$detected_at" \
    'select(.runId==$id) + {detected_at:$t, source:"relay-watchdog"}' >>"$EVID" 2>/dev/null || \
    printf '{"runId":"%s","detected_at":"%s","source":"relay-watchdog"}\n' "$id" "$detected_at" >>"$EVID"
done

ids_str="$(printf '%s ' "${new_ids[@]}")"
notify "⚠️ Relay loop died (${#new_ids[@]} new)" \
  "Dead run(s): ${ids_str}— the pool stopped WITHOUT a clean shutdown (no heartbeat for >TTL). Restart with /relay --afk; on restart its SAFE (ledger-only) leftovers auto-reconcile and the rest surface in REVIEW_ME (id:7809). Evidence: $EVID"
log "NOTIFIED ${#new_ids[@]} new dead run(s): ${ids_str}"
echo "relay-watchdog: notified ${#new_ids[@]} new dead run(s): ${ids_str}" >&2
exit 0
