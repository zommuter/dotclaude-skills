#!/usr/bin/env bash
# Post-hoc cost lookup for a Claude Code session.
# Usage: cost-of.sh <session-id>
# Exit code 0 on success; non-zero if session not found.

SESSION_ID="${1:?usage: cost-of.sh <session-id>}"

JSONL=$(find ~/.claude/projects -name "${SESSION_ID}.jsonl" 2>/dev/null | command head -1)
if [[ -z "$JSONL" ]]; then
  echo "error: no jsonl found for session $SESSION_ID" >&2
  exit 1
fi

TURNS=$(wc -l < "$JSONL")
SIZE_BYTES=$(stat -c %s "$JSONL")
SIZE_KB=$(( SIZE_BYTES / 1024 ))
APPROX_KTOK=$(( SIZE_KB / 4 ))  # SIZE_KB/4 ≈ kTokens (1KB ≈ 250 tok)

# Wall time: extract first and last timestamps in a single jq pass
read -r FIRST_TS LAST_TS < <(jq -r '
  select(.timestamp != null) | .timestamp
' "$JSONL" 2>/dev/null | awk 'NR==1{first=$0} {last=$0} END{print first, last}')

WALL_FMT="unknown"
if [[ -n "$FIRST_TS" && -n "$LAST_TS" && "$FIRST_TS" != "$LAST_TS" ]]; then
  FIRST_EPOCH=$(date -d "$FIRST_TS" +%s 2>/dev/null || echo 0)
  LAST_EPOCH=$(date -d "$LAST_TS" +%s 2>/dev/null || echo 0)
  WALL_SEC=$(( LAST_EPOCH - FIRST_EPOCH ))
  WALL_FMT=$(printf '%dm%ds' $(( WALL_SEC / 60 )) $(( WALL_SEC % 60 )))
fi

echo "Session:       $SESSION_ID"
echo "File:          $JSONL"
echo "Turns (lines): $TURNS"
echo "Size:          ${SIZE_KB} KB"
echo "Approx tokens: ~${APPROX_KTOK}k"
echo "Wall time:     $WALL_FMT"
