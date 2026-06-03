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

# Real token totals from usage objects on every assistant turn
read -r INPUT_TOK CACHE_READ_TOK CACHE_CREATE_TOK OUTPUT_TOK < <(jq -rs '
  map(select(.type == "assistant" and .message.usage != null) | .message.usage)
  | {
      input:        (map(.input_tokens                // 0) | add // 0),
      cache_read:   (map(.cache_read_input_tokens     // 0) | add // 0),
      cache_create: (map(.cache_creation_input_tokens // 0) | add // 0),
      output:       (map(.output_tokens               // 0) | add // 0)
    }
  | "\(.input) \(.cache_read) \(.cache_create) \(.output)"
' "$JSONL" 2>/dev/null)
INPUT_TOK=${INPUT_TOK:-0}; CACHE_READ_TOK=${CACHE_READ_TOK:-0}
CACHE_CREATE_TOK=${CACHE_CREATE_TOK:-0}; OUTPUT_TOK=${OUTPUT_TOK:-0}
TOTAL_INPUT=$(( INPUT_TOK + CACHE_READ_TOK + CACHE_CREATE_TOK ))

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
echo "Input tokens:  ${TOTAL_INPUT}  (uncached=${INPUT_TOK}  cache_read=${CACHE_READ_TOK}  cache_create=${CACHE_CREATE_TOK})"
echo "Output tokens: ${OUTPUT_TOK}"
echo "Wall time:     $WALL_FMT"
