#!/bin/bash
# Called by Claude Code's Notification hook (settings.json) whenever Claude needs
# user input or permission. Claude Code intentionally delays ~5s before firing this
# hook to avoid spamming notifications when the terminal is already in focus.
#
# Auto-dismisses when Claude resumes (PostToolUse hook touches /tmp/claude-resume-<sid>),
# which reliably signals that the permission was granted or input was provided.

[ -z "$DISPLAY" ] && exit 0

data=$(cat)
sid=$(echo "$data" | jq -r '.session_id // "?"')
msg=$(echo "$data" | jq -r '.message // "Input required"')
project=$(basename "$PWD")
short_sid="${sid:0:8}"
wid=$(cat "/tmp/claude-wid-$sid" 2>/dev/null)
icon="$HOME/.local/share/icons/claude.png"
title="Claude Code [$project · $short_sid]"
signal="/tmp/claude-resume-$sid"

close_notification() {
    gdbus call --session \
        --dest org.freedesktop.Notifications \
        --object-path /org/freedesktop/Notifications \
        --method org.freedesktop.Notifications.CloseNotification \
        "$1" 2>/dev/null
}

if [ -n "$wid" ]; then
    rm -f "$signal"
    tmpout=$(mktemp)
    notify-send --print-id -i "$icon" -t 30000 -A "focus=Focus Terminal" "$title" "$msg" >"$tmpout" &
    notif_pid=$!

    # Wait briefly for notify-send to write the notification ID
    sleep 0.2
    notif_id=$(head -1 "$tmpout")

    # Auto-dismiss when Claude resumes (permission handled / input provided)
    while kill -0 "$notif_pid" 2>/dev/null; do
        if [ -f "$signal" ]; then
            close_notification "$notif_id"
            break
        fi
        sleep 0.5
    done

    wait "$notif_pid" 2>/dev/null
    action=$(sed -n '2p' "$tmpout")
    rm -f "$tmpout"
    [ "$action" = "focus" ] && wmctrl -ia "$wid"
else
    notify-send -i "$icon" -t 10000 "$title" "$msg"
fi
