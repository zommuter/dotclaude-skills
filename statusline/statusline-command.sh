#!/bin/bash
# Read JSON input from stdin
input=$(cat)

CL_D="\e[0;39;49m"
CL_R="\e[0;31m"
CL_G="\e[0;32m"
CL_B="\e[0;34m"
#CL_W="\e[1;37m"
ON_R="\e[41m"

hash2rgb()
{
    HASH=$(echo $1 | sha1sum)
    C=$((16#${HASH:0:2}/2))
    M=$((16#${HASH:2:2}/2))
    Y=$((16#${HASH:4:2}))
    R=$((256-$C/2))
    G=$((256-$M))
    B=$((256-$Y/2))
    FG="\e[38;2;${R};${G};${B}m"
    BG="\e[48;2;${C};${M};${Y}m"
    echo "${FG}${BG}"
}

percent_to_gradient()
{
    local pct=$1
    local r g b

    if (( $(echo "$pct <= 50" | bc -l) )); then
        # 0-50%: green to orange
        # R: 0 -> 255, G: 255 -> 165, B: 0
        r=$(echo "scale=0; 255 * $pct / 50" | bc)
        g=$(echo "scale=0; 255 - (90 * $pct / 50)" | bc)
        b=0
    else
        # 50-100%: orange to red
        # R: 255, G: 165 -> 0, B: 0
        r=255
        g=$(echo "scale=0; 165 - (165 * ($pct - 50) / 50)" | bc)
        b=0
    fi

    echo "\e[38;2;${r};${g};${b}m"
}

# Fetch usage limits (cached 60s, backoff on failure)
# Known issue: /api/oauth/usage has a per-token limit of ~5 requests total,
# so any polling interval will eventually 429. We use a lockfile to prevent
# concurrent fetches, backoff on failure, and extrapolate when stale >5m.
USAGE_CACHE="/tmp/claude-usage-cache.json"
USAGE_HISTORY="/tmp/claude-usage-history"  # "epoch session_pct weekly_pct" per line (last 2 samples)
USAGE_BACKOFF="/tmp/claude-usage-backoff"
USAGE_LOCK="/tmp/claude-usage-lock"
NOW=$(date +%s)
CACHE_MTIME=$(stat -c %Y "$USAGE_CACHE" 2>/dev/null || echo 0)
CACHE_AGE=$((NOW - CACHE_MTIME))

# Backoff: after a failed fetch, wait progressively longer before retrying
# Backoff file format: "retry_after_epoch last_wait_secs"
BACKOFF_LINE=$(cat "$USAGE_BACKOFF" 2>/dev/null || echo "0 0")
BACKOFF_UNTIL=${BACKOFF_LINE%% *}
BACKOFF_LAST=${BACKOFF_LINE##* }

# Clean stale lockfile (>30s = probably dead process)
if [ -f "$USAGE_LOCK" ] && [ $((NOW - $(stat -c %Y "$USAGE_LOCK" 2>/dev/null || echo 0))) -ge 30 ]; then
    rm -f "$USAGE_LOCK"
fi

if [ $CACHE_AGE -ge 60 ] && [ $NOW -ge $BACKOFF_UNTIL ]; then
    # Lockfile: prevent concurrent fetches from multiple sessions
    if (set -o noclobber; echo $$ > "$USAGE_LOCK") 2>/dev/null; then
        trap "rm -f '$USAGE_LOCK'" EXIT
        TOKEN=$(jq -r '.claudeAiOauth.accessToken' "$HOME/.claude/.credentials.json" 2>/dev/null)
        if [ -n "$TOKEN" ]; then
            HTTP_CODE=$(curl -sf --max-time 2 -o "$USAGE_CACHE.tmp" -w "%{http_code}" \
                -H "Authorization: Bearer $TOKEN" \
                -H "anthropic-beta: oauth-2025-04-20" \
                "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
            if [ "$HTTP_CODE" = "200" ] && [ -s "$USAGE_CACHE.tmp" ]; then
                mv "$USAGE_CACHE.tmp" "$USAGE_CACHE"
                CACHE_MTIME=$NOW
                CACHE_AGE=0
                rm -f "$USAGE_BACKOFF"
                # Record sample for burn rate extrapolation (keep last 2)
                S=$(jq -r '.five_hour.utilization // 0' "$USAGE_CACHE")
                W=$(jq -r '.seven_day.utilization // 0' "$USAGE_CACHE")
                echo "$NOW $S $W" >> "$USAGE_HISTORY"
                tail -2 "$USAGE_HISTORY" > "$USAGE_HISTORY.tmp" && mv "$USAGE_HISTORY.tmp" "$USAGE_HISTORY"
            else
                rm -f "$USAGE_CACHE.tmp"
                # Exponential backoff: 60s, 120s, 240s, max 600s
                NEXT_WAIT=$(( BACKOFF_LAST < 60 ? 60 : BACKOFF_LAST * 2 ))
                [ $NEXT_WAIT -gt 600 ] && NEXT_WAIT=600
                echo "$((NOW + NEXT_WAIT)) $NEXT_WAIT" > "$USAGE_BACKOFF"
            fi
        fi
        rm -f "$USAGE_LOCK"
    fi
fi
SESSION_PCT=$(jq -r '.five_hour.utilization // 0' "$USAGE_CACHE" 2>/dev/null)
WEEKLY_PCT=$(jq -r '.seven_day.utilization // 0' "$USAGE_CACHE" 2>/dev/null)
SESSION_RESETS=$(jq -r '.five_hour.resets_at // ""' "$USAGE_CACHE" 2>/dev/null)
WEEKLY_RESETS=$(jq -r '.seven_day.resets_at // ""' "$USAGE_CACHE" 2>/dev/null)

# Extrapolate usage when cache is stale >5 minutes
EXTRAPOLATED=""
if [ $CACHE_AGE -ge 300 ] && [ -f "$USAGE_HISTORY" ]; then
    HIST_LINES=$(wc -l < "$USAGE_HISTORY")
    if [ "$HIST_LINES" -ge 2 ]; then
        # Read two most recent samples to compute burn rate
        SAMPLE1=$(head -1 "$USAGE_HISTORY")
        SAMPLE2=$(tail -1 "$USAGE_HISTORY")
        T1=${SAMPLE1%% *}; REST1=${SAMPLE1#* }; S1=${REST1%% *}; W1=${REST1##* }
        T2=${SAMPLE2%% *}; REST2=${SAMPLE2#* }; S2=${REST2%% *}; W2=${REST2##* }
        DT=$((T2 - T1))
        if [ $DT -gt 0 ]; then
            # Burn rate: pct per second (scaled x10000 for integer math)
            S_RATE=$(echo "scale=6; ($S2 - $S1) / $DT" | bc)
            W_RATE=$(echo "scale=6; ($W2 - $W1) / $DT" | bc)
            ELAPSED=$((NOW - T2))
            S_EXTRAP=$(echo "scale=1; $S2 + $S_RATE * $ELAPSED" | bc)
            W_EXTRAP=$(echo "scale=1; $W2 + $W_RATE * $ELAPSED" | bc)
            # Clamp 0-100
            S_EXTRAP=$(echo "if ($S_EXTRAP < 0) 0 else if ($S_EXTRAP > 100) 100 else $S_EXTRAP" | bc)
            W_EXTRAP=$(echo "if ($W_EXTRAP < 0) 0 else if ($W_EXTRAP > 100) 100 else $W_EXTRAP" | bc)
            EXTRAPOLATED="1"
            SESSION_PCT_ORIG="$SESSION_PCT"
            WEEKLY_PCT_ORIG="$WEEKLY_PCT"
            SESSION_PCT="$S_EXTRAP"
            WEEKLY_PCT="$W_EXTRAP"
        fi
    fi
fi

# Calculate cooldown timers and elapsed percentage
calc_window_stats() {
    local reset_ts="$1"
    local type="$2"  # "5h" or "7d"
    local window_secs

    if [ "$type" = "5h" ]; then
        window_secs=$((5 * 3600))
    else
        window_secs=$((7 * 24 * 3600))
    fi

    [ -z "$reset_ts" ] && echo "||0" && return
    local reset_epoch=$(date -d "$reset_ts" +%s 2>/dev/null)
    [ -z "$reset_epoch" ] && echo "||0" && return
    local now=$(date +%s)
    local remaining=$((reset_epoch - now))
    [ $remaining -le 0 ] && remaining=0

    # Calculate elapsed percentage of window
    local elapsed=$((window_secs - remaining))
    local elapsed_pct=$((elapsed * 100 / window_secs))

    # Format cooldown display
    local cooldown
    if [ $remaining -le 0 ]; then
        cooldown="0m"
    elif [ "$type" = "5h" ]; then
        local hours=$((remaining / 3600))
        local mins=$(((remaining % 3600) / 60))
        cooldown="${hours}h${mins}m"
    else
        local days=$((remaining / 86400))
        local hours=$(((remaining % 86400) / 3600))
        cooldown="${days}d${hours}h"
    fi

    echo "${cooldown}|${elapsed_pct}"
}

# Color based on usage vs elapsed time consistency
# Green if usage <= elapsed (sustainable pace), red gradient if over
consistency_color() {
    local usage_pct=$1
    local elapsed_pct=$2

    # How much over the sustainable rate? (negative = under, positive = over)
    local overage=$((usage_pct - elapsed_pct))

    if [ $overage -le 0 ]; then
        # At or below sustainable rate - green
        echo "\e[0;32m"
    elif [ $overage -le 20 ]; then
        # Slightly over - yellow/orange gradient
        local r=$((128 + overage * 6))
        local g=$((255 - overage * 4))
        echo "\e[38;2;${r};${g};0m"
    else
        # Significantly over - orange to red
        local r=255
        local g=$((175 - (overage - 20) * 2))
        [ $g -lt 0 ] && g=0
        echo "\e[38;2;${r};${g};0m"
    fi
}

SESSION_STATS=$(calc_window_stats "$SESSION_RESETS" "5h")
WEEKLY_STATS=$(calc_window_stats "$WEEKLY_RESETS" "7d")
SESSION_COOLDOWN=$(echo "$SESSION_STATS" | cut -d'|' -f1)
SESSION_ELAPSED=$(echo "$SESSION_STATS" | cut -d'|' -f2)
WEEKLY_COOLDOWN=$(echo "$WEEKLY_STATS" | cut -d'|' -f1)
WEEKLY_ELAPSED=$(echo "$WEEKLY_STATS" | cut -d'|' -f2)

CL_SESSION=$(consistency_color "${SESSION_PCT%.*}" "$SESSION_ELAPSED")
CL_WEEKLY=$(consistency_color "${WEEKLY_PCT%.*}" "$WEEKLY_ELAPSED")
if [ -n "$EXTRAPOLATED" ]; then
    SESSION_DISPLAY=$(printf "~%.0f%%(%.0f%%)" "$SESSION_PCT" "$SESSION_PCT_ORIG")
    WEEKLY_DISPLAY=$(printf "~%.0f%%(%.0f%%)" "$WEEKLY_PCT" "$WEEKLY_PCT_ORIG")
else
    SESSION_DISPLAY=$(printf "%.0f%%" "$SESSION_PCT")
    WEEKLY_DISPLAY=$(printf "%.0f%%" "$WEEKLY_PCT")
fi

# Extract values using jq
MODEL_DISPLAY=$(echo "$input" | jq -r '.model.display_name // .model.name // .modelName // .model // "claude"')
CL_MODEL=$(hash2rgb "$MODEL_DISPLAY")
TOTAL_COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
COST_DISPLAY=$(printf "\$%.2f" "$TOTAL_COST")

# Calculate context window percentage
TOTAL_INPUT=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
TOTAL_OUTPUT=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')
CONTEXT_SIZE=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
TOTAL_TOKENS=$((TOTAL_INPUT + TOTAL_OUTPUT))
CONTEXT_PCT=$(echo "scale=1; $TOTAL_TOKENS * 100 / $CONTEXT_SIZE" | bc)
CL_CONTEXT=$(percent_to_gradient "$CONTEXT_PCT")
CONTEXT_DISPLAY=$(printf "%.0f%%" "$CONTEXT_PCT")

CURRENT_DIR=$(echo "$input" | jq -r '.workspace.current_dir // .currentDir // .cwd // ""')
CL_DIR=$(hash2rgb "$CURRENT_DIR")

# Get user and hostname
USER=$(whoami)
CL_USER=$(hash2rgb $USER)
HOST=$(hostname -s)
CL_HOST=$(hash2rgb $HOST)
CL_HSTUSR=$(hash2rgb $USER@$HOSTNAME)

# Get git status using __git_ps1
# Source git-prompt to get __git_ps1 function
if [ -f /etc/bash_completion.d/git-prompt ]; then
    source /etc/bash_completion.d/git-prompt
    GIT_PS1_SHOWDIRTYSTATE=1
    GIT_PS1_SHOWSTASHSTATE=1
    GIT_PS1_SHOWUNTRACKEDFILES=1
    GIT_PS1_SHOWCOLORHINTS=
    GIT_PS1_DESCRIBE_STYLE="branch"
    GIT_PS1_SHOWUPSTREAM="auto git verbose"
    GIT_INFO=$(cd "$CURRENT_DIR" 2>/dev/null && __git_ps1 2>/dev/null || true)
    CL_GIT=$(hash2rgb "$GIT_INFO")
fi

# Cache age indicator with color
# Green <1m, yellow <5m, orange <10m, red >10m
age_color() {
    local age=$1
    if [ $age -lt 60 ]; then
        echo "\e[0;32m"  # green
    elif [ $age -lt 300 ]; then
        echo "\e[0;33m"  # yellow
    elif [ $age -lt 600 ]; then
        echo "\e[38;2;255;165;0m"  # orange
    else
        echo "\e[0;31m"  # red
    fi
}

age_display() {
    local age=$1
    if [ $age -lt 60 ]; then
        echo "${age}s"
    elif [ $age -lt 3600 ]; then
        echo "$((age / 60))m"
    else
        echo "$((age / 3600))h$((age % 3600 / 60))m"
    fi
}

CL_AGE=$(age_color "$CACHE_AGE")
AGE_DISPLAY=$(age_display "$CACHE_AGE")

# KV-cache TTL countdown (prompt cache 5-min TTL)
KV_DISPLAY=""
CL_KV=""
TRANSCRIPT=$(echo "$input" | jq -r '.transcript_path // ""')
if [ -n "$TRANSCRIPT" ] && LAST=$(stat -c %Y "$TRANSCRIPT" 2>/dev/null); then
    KV_REMAIN=$((300 - (NOW - LAST)))
    if [ $KV_REMAIN -le 0 ]; then
        KV_DISPLAY="KV:cold"
        CL_KV="\e[0;31m"  # red
    else
        kv_m=$((KV_REMAIN / 60))
        kv_s=$((KV_REMAIN % 60))
        KV_DISPLAY=$(printf "KV:%dm%02ds" "$kv_m" "$kv_s")
        # Color: green (fresh) → orange → red (about to expire)
        # expired_pct = (300 - KV_REMAIN) * 100 / 300
        expired_pct=$(( (300 - KV_REMAIN) * 100 / 300 ))
        CL_KV=$(percent_to_gradient "$expired_pct")
    fi
fi

# Print status line with colors
if [ -n "$KV_DISPLAY" ]; then
    echo -e "${CL_MODEL}${MODEL_DISPLAY}${CL_D} ${CL_CONTEXT}${CONTEXT_DISPLAY}${CL_D} 5h:${CL_SESSION}${SESSION_DISPLAY}${CL_D}→${SESSION_COOLDOWN} 7d:${CL_WEEKLY}${WEEKLY_DISPLAY}${CL_D}→${WEEKLY_COOLDOWN} ${COST_DISPLAY} ${CL_AGE}${AGE_DISPLAY}${CL_D} ${CL_KV}${KV_DISPLAY}${CL_D}\n${CL_USER}${USER}@${CL_HOST}${HOST}${CL_HSTUSR}:${CL_DIR}${CURRENT_DIR}${CL_GIT}${GIT_INFO}${CL_D}"
else
    echo -e "${CL_MODEL}${MODEL_DISPLAY}${CL_D} ${CL_CONTEXT}${CONTEXT_DISPLAY}${CL_D} 5h:${CL_SESSION}${SESSION_DISPLAY}${CL_D}→${SESSION_COOLDOWN} 7d:${CL_WEEKLY}${WEEKLY_DISPLAY}${CL_D}→${WEEKLY_COOLDOWN} ${COST_DISPLAY} ${CL_AGE}${AGE_DISPLAY}${CL_D}\n${CL_USER}${USER}@${CL_HOST}${HOST}${CL_HSTUSR}:${CL_DIR}${CURRENT_DIR}${CL_GIT}${GIT_INFO}${CL_D}"
fi
