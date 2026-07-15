#!/usr/bin/env bash
# profile-active.sh — emit user-profile.md (passthrough) + log active/full ratio.
# Default: emits the full file; appends (full_lines, active_lines, ratio) to log.
# --filter or PROFILE_ACTIVE_FILTER=1: emits only active blocks.
# Active block definition: Pre-emption-eligible: yes AND Confidence: med or high.
set -euo pipefail

PROFILE="${PROFILE_ACTIVE_FILE:-$HOME/.claude/skills/meeting/user-profile.md}"
LOG="${PROFILE_ACTIVE_LOG:-$HOME/.claude/logs/meeting-profile-active.log}"
FILTER=${PROFILE_ACTIVE_FILTER:-0}
[[ "${1:-}" == "--filter" ]] && FILTER=1

full_lines=$(wc -l < "$PROFILE")

# Extract active blocks: file header (before first ##) + ## sections where
# Pre-emption-eligible: yes AND (Confidence: med OR Confidence: high).
_tmp=$(mktemp)
trap 'rm -- "$_tmp"' EXIT

awk '
    BEGIN { header=1; buf=""; hdr=""; eligible=0; conf_ok=0 }
    header && /^## / { printf "%s", hdr; header=0 }
    header { hdr = hdr $0 ORS; next }
    /^## / {
        if (buf != "" && eligible && conf_ok) printf "%s", buf
        buf = $0 ORS; eligible=0; conf_ok=0; next
    }
    { buf = buf $0 ORS }
    /\*\*Pre-emption-eligible:\*\* yes/ { eligible=1 }
    /\*\*Confidence:\*\* med/ || /\*\*Confidence:\*\* high/ { conf_ok=1 }
    END { if (buf != "" && eligible && conf_ok) printf "%s", buf }
' "$PROFILE" > "$_tmp"

active_lines=$(wc -l < "$_tmp")
ratio=$(awk -v f="$full_lines" -v a="$active_lines" 'BEGIN { printf "%.2f", a/(f>0?f:1) }')

# Append metrics to log
mkdir -p "$(dirname "$LOG")"
printf '%s\tfull=%d\tactive=%d\tratio=%s\n' \
    "$(date '+%Y-%m-%dT%H:%M')" "$full_lines" "$active_lines" "$ratio" >> "$LOG"

# Emit
if [[ "$FILTER" == "1" ]]; then
    cat "$_tmp"
else
    cat "$PROFILE"
fi
