#!/usr/bin/env bash
# quota-sample.sh — periodic Claude usage-quota sampler (git-versioned time series).
#
# WHY: the Claude Code statusline only fetches /api/oauth/usage while a session is
# rendering it, so a quota anomaly that happens *while idle* (e.g. the 2026-06-18
# weekly-limit accounting bug, which spiked many users 60%→100% "with no active
# session") leaves no local trace. This sampler runs on a systemd.timer and records
# every bucket's utilization to an append-only JSONL in a private git repo, so the
# next spike is captured for forensics and later visualization (quota-report.py).
#
# COOPERATIVE, not a second poller (statusline gotcha: /api/oauth/usage 429s hard,
# ~5 req/token before backoff). It shares the statusline's /tmp cache + lock + backoff:
#   - cache fresh (< QUOTA_FRESH_SECS, kept warm by a running statusline) → just read it
#     (source=cache, ZERO added API calls during active sessions)
#   - cache stale (idle: statusline isn't running) → fetch ourselves under the SHARED
#     lockfile + backoff, and refresh the shared cache too (good citizen). We are then
#     the only caller, so no 429 contention. This is exactly when an idle spike is caught.
#
# Every sample carries source ("fetch"|"cache") + cache_age_s + stale, so a piggybacked
# stale reading is never mistaken for a fresh fetch.
#
# Append every run; commit+push to the diary repo (QUOTA_COMMIT_INTERVAL, default every
# run; set >0 to coarsen) via git-lock-push.sh manifest mode — staging
# ONLY the data file, race-free against git-diary-workflow.
#
# Env overrides (all optional; defaults are the live config):
#   QUOTA_DIARY_DIR       repo holding the data        (default ~/src/claude-diary)
#   QUOTA_DATA_REL        data path within that repo   (default quota/quota-samples.jsonl)
#   QUOTA_CACHE           shared statusline cache      (default /tmp/claude-usage-cache.json)
#   QUOTA_FRESH_SECS      reuse cache if younger       (default 300)
#   QUOTA_COMMIT_INTERVAL min secs between git commits (default 0 = commit every run;
#                         set e.g. 3600 to coarsen to hourly snapshots)
#   QUOTA_NO_COMMIT=1     append only, never touch git (tests/dry-run)
#   QUOTA_CREDENTIALS     OAuth creds json             (default ~/.claude/.credentials.json)
set -euo pipefail

DIARY_DIR="${QUOTA_DIARY_DIR:-$HOME/src/claude-diary}"
DATA_REL="${QUOTA_DATA_REL:-quota/quota-samples.jsonl}"
DATA_FILE="$DIARY_DIR/$DATA_REL"
CACHE="${QUOTA_CACHE:-/tmp/claude-usage-cache.json}"
FRESH_SECS="${QUOTA_FRESH_SECS:-300}"
COMMIT_INTERVAL="${QUOTA_COMMIT_INTERVAL:-0}"
CREDS="${QUOTA_CREDENTIALS:-$HOME/.claude/.credentials.json}"

# Shared with the statusline — DO NOT rename (cooperation depends on identical paths).
USAGE_LOCK="/tmp/claude-usage-lock"
USAGE_BACKOFF="/tmp/claude-usage-backoff"
USAGE_HISTORY="/tmp/claude-usage-history"

LOG="$HOME/.claude/logs/quota-sample.log"
mkdir -p "$(dirname "$LOG")" "$(dirname "$DATA_FILE")"
log() { printf '%s %s\n' "$(date -Is)" "$*" >> "$LOG"; }

NOW=$(date +%s)
cache_mtime() { stat -c %Y "$CACHE" 2>/dev/null || echo 0; }

# ---- 1. Refresh the shared cache if stale (cooperative fetch) --------------------
SOURCE="cache"
age=$(( NOW - $(cache_mtime) ))
if [ "$age" -ge "$FRESH_SECS" ]; then
    # Respect the shared backoff window so we never hammer a 429ing endpoint.
    backoff_line=$(cat "$USAGE_BACKOFF" 2>/dev/null || echo "0 0")
    backoff_until=${backoff_line%% *}
    backoff_last=${backoff_line##* }
    # Clear a dead lock (>30s), matching the statusline's own staleness rule.
    if [ -f "$USAGE_LOCK" ] && [ $(( NOW - $(stat -c %Y "$USAGE_LOCK" 2>/dev/null || echo 0) )) -ge 30 ]; then
        rm -f "$USAGE_LOCK"
    fi
    if [ "$NOW" -ge "$backoff_until" ] && (set -o noclobber; echo $$ > "$USAGE_LOCK") 2>/dev/null; then
        trap 'rm -f "$USAGE_LOCK"' EXIT
        TOKEN=$(jq -r '.claudeAiOauth.accessToken' "$CREDS" 2>/dev/null || echo "")
        if [ -n "$TOKEN" ] && [ "$TOKEN" != "null" ]; then
            code=$(curl -sf --max-time 4 -o "$CACHE.tmp" -w "%{http_code}" \
                -H "Authorization: Bearer $TOKEN" \
                -H "anthropic-beta: oauth-2025-04-20" \
                "https://api.anthropic.com/api/oauth/usage" 2>/dev/null || echo "000")
            if [ "$code" = "200" ] && [ -s "$CACHE.tmp" ]; then
                mv "$CACHE.tmp" "$CACHE"
                rm -f "$USAGE_BACKOFF"
                SOURCE="fetch"
                # Keep the statusline's 2-sample extrapolation history warm too.
                s=$(jq -r '.five_hour.utilization // 0' "$CACHE")
                w=$(jq -r '.seven_day.utilization // 0' "$CACHE")
                echo "$NOW $s $w" >> "$USAGE_HISTORY"
                tail -2 "$USAGE_HISTORY" > "$USAGE_HISTORY.tmp" 2>/dev/null && mv "$USAGE_HISTORY.tmp" "$USAGE_HISTORY"
                log "fetch ok code=200"
            else
                rm -f "$CACHE.tmp"
                next=$(( backoff_last < 60 ? 60 : backoff_last * 2 ))
                [ "$next" -gt 600 ] && next=600
                echo "$(( NOW + next )) $next" > "$USAGE_BACKOFF"
                log "fetch fail code=$code backoff=${next}s (using cached, age=${age}s)"
            fi
        else
            log "no token in $CREDS (using cached, age=${age}s)"
        fi
        rm -f "$USAGE_LOCK"; trap - EXIT
    else
        log "backoff/lock active (using cached, age=${age}s)"
    fi
fi

if [ ! -s "$CACHE" ]; then
    log "no cache available — skipping sample"
    exit 0
fi

# Recompute age after a possible refresh; flag stale (older than 2× our interval guess).
age=$(( NOW - $(cache_mtime) ))
stale=false
[ "$age" -ge $(( FRESH_SECS * 2 )) ] && stale=true

# ---- 2. Build one rich JSONL line from the cache --------------------------------
LINE=$(jq -c \
    --arg ts "$(date -Is)" --argjson epoch "$NOW" \
    --arg source "$SOURCE" --argjson cache_age "$age" --argjson stale "$stale" '
  {
    ts: $ts, epoch: $epoch, source: $source, cache_age_s: $cache_age, stale: $stale,
    five_hour:            (.five_hour.utilization        // null),
    seven_day:            (.seven_day.utilization        // null),
    seven_day_sonnet:     (.seven_day_sonnet.utilization // null),
    seven_day_opus:       (.seven_day_opus.utilization   // null),
    seven_day_oauth_apps: (.seven_day_oauth_apps.utilization // null),
    five_hour_resets_at:  (.five_hour.resets_at  // null),
    seven_day_resets_at:  (.seven_day.resets_at  // null),
    extra_credits_used:   (.extra_usage.used_credits // null),
    extra_utilization:    (.extra_usage.utilization  // null)
  }' "$CACHE")

# Atomic append under a local lock (concurrent timer/manual runs).
APPEND_LOCK="$(dirname "$DATA_FILE")/.quota-sample.lock"
exec 9>"$APPEND_LOCK"
flock 9
printf '%s\n' "$LINE" >> "$DATA_FILE"
flock -u 9
log "sample appended source=$SOURCE 7d=$(jq -r '.seven_day // "?"' <<<"$LINE") stale=$stale"

# ---- 3. Gated commit, opportunistic push (coarser cadence) -----------------------
# claude-diary is chronically dirty (DIARY.md edits in flight), so we do NOT use
# git-lock-push manifest mode (its id:aa93 guard refuses to rebase a dirty tree, and
# nesting its fd-8 lock under ours would deadlock). Instead: a *scoped partial commit*
# of only the data file under the diary push-lock (serializing with git-diary-workflow,
# never touching its staged DIARY.md), then a push only when the tree is otherwise clean.
[ "${QUOTA_NO_COMMIT:-0}" = "1" ] && exit 0
git -C "$DIARY_DIR" rev-parse --show-toplevel >/dev/null 2>&1 || { log "diary not a git repo — append-only"; exit 0; }

last_commit=$(git -C "$DIARY_DIR" log -1 --format=%ct -- "$DATA_REL" 2>/dev/null || echo 0)
[ -z "$last_commit" ] && last_commit=0
[ $(( NOW - last_commit )) -lt "$COMMIT_INTERVAL" ] && exit 0

LOCKF="$DIARY_DIR/.git-lock-push.lock"
committed=0
exec 8>"$LOCKF"
if flock -x -w 30 8; then
    git -C "$DIARY_DIR" add -- "$DATA_REL"
    if git -C "$DIARY_DIR" diff --cached --quiet -- "$DATA_REL"; then
        log "no new rows staged (already committed)"
    elif git -C "$DIARY_DIR" commit -q -m "quota: samples through $(date -Is)" -- "$DATA_REL"; then
        committed=1; log "local commit ok"
    else
        log "commit failed (index race?) — data safe on disk"
    fi
    flock -u 8
else
    log "diary lock busy (30s) — append-only this round"
fi
exec 8>&-

# Push OUTSIDE our lock (git-lock-push takes its own fd-8 lock — nesting would deadlock),
# and only when the rest of the tree is clean, so we never rebase over live diary edits.
if [ "$committed" = 1 ] && [ -z "$(git -C "$DIARY_DIR" status --porcelain)" ]; then
    if ~/.claude/skills/git-diary-workflow/git-lock-push.sh "$DIARY_DIR" >> "$LOG" 2>&1; then
        log "pushed"
    else
        log "push deferred (lock/divergence) — committed locally"
    fi
elif [ "$committed" = 1 ]; then
    log "tree dirty — push deferred to next clean run / git-diary-workflow"
fi
exit 0
