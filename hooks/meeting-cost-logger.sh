#!/usr/bin/env bash
# Stop hook: append one CSV line per session to ~/.claude/logs/meeting-cost.log
# Format: iso_ts,session_id,project_dir,turns,kb,was_meeting,input_tok,cache_read_tok,cache_create_tok,output_tok
set -euo pipefail

LOG_FILE="$HOME/.claude/logs/meeting-cost.log"
mkdir -p "$HOME/.claude/logs"

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)

[[ -z "$SESSION_ID" ]] && exit 0

JSONL=$(find "$HOME/.claude/projects" -name "${SESSION_ID}.jsonl" 2>/dev/null | head -1)
[[ -z "$JSONL" ]] && exit 0

TURNS=$(wc -l < "$JSONL")
SIZE_KB=$(( $(stat -c %s "$JSONL") / 1024 ))
ISO_TS=$(date -Iseconds)

PROJECT_DIR_ENCODED=$(basename "$(dirname "$JSONL")")

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

# Detect if a meeting note was written this session
# Match Write tool calls to meeting-notes paths only — avoids false positives from reads/audits
WAS_MEETING=false
if [[ -n "$TRANSCRIPT_PATH" && -f "$TRANSCRIPT_PATH" ]]; then
  grep -qE 'Write\(.*meeting-notes.*\.md' "$TRANSCRIPT_PATH" 2>/dev/null && WAS_MEETING=true
fi

echo "${ISO_TS},${SESSION_ID},${PROJECT_DIR_ENCODED},${TURNS},${SIZE_KB},${WAS_MEETING},${INPUT_TOK},${CACHE_READ_TOK},${CACHE_CREATE_TOK},${OUTPUT_TOK}" >> "$LOG_FILE"
exit 0
