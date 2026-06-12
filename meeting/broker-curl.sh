#!/usr/bin/env bash
# broker-curl.sh <port> <session> <endpoint> [json_body]
# Wrapper for all HTTP calls to the meeting-live broker.
# Allowlist: Bash(~/.claude/skills/meeting/broker-curl.sh *)
#
# Endpoints:
#   status              GET  /status?session=<session>   → {"subscribers": N}
#   events              GET  /events?session=<session>   SSE stream (curl -N)
#   event   <json>      POST /event      stream text to renderer
#   question <json>     POST /question   send decision prompt
#   await               GET  /await?session=<session>    block until renderer answers
#   response <json>     POST /response   renderer submits answer

set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "Usage: broker-curl.sh <port> <session> <status|events|event|question|await|response|say> [json|--opener]" >&2
  exit 1
fi

PORT=$1
SESSION=$2
ENDPOINT=$3
BASE="http://127.0.0.1:${PORT}"

case "$ENDPOINT" in
  status)
    curl -s "${BASE}/status?session=${SESSION}"
    ;;
  events)
    curl -N "${BASE}/events?session=${SESSION}"
    ;;
  await)
    curl -s "${BASE}/await?session=${SESSION}"
    ;;
  event|question|response)
    # NB: do not inline a brace-containing default in ${...} — bash closes the
    # expansion at the first '}', appending a literal '}' that corrupts the JSON.
    if [[ $# -ge 4 ]]; then BODY=$4; else BODY='{}'; fi
    JSON=$(printf '%s' "$BODY" | jq --arg s "$SESSION" '. + {session: $s}')
    curl -s -X POST "${BASE}/${ENDPOINT}" \
      -H 'Content-Type: application/json' \
      -d "$JSON"
    ;;
  say)
    OPENER=0
    if [[ "${4:-}" == "--opener" ]]; then OPENER=1; fi
    first=1
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ -z "$line" ]] && continue
      if [[ $first -eq 1 && $OPENER -eq 1 ]]; then
        JSON=$(jq -n --arg text "$line" --arg s "$SESSION" '{"text":$text,"kind":"opener","session":$s}')
      else
        JSON=$(jq -n --arg text "$line" --arg s "$SESSION" '{"text":$text,"session":$s}')
      fi
      curl -s --fail -X POST "${BASE}/event" \
        -H 'Content-Type: application/json' \
        -d "$JSON" > /dev/null
      first=0
    done
    ;;
  *)
    echo "Unknown endpoint: ${ENDPOINT}" >&2
    echo "Valid: status events event question await response say" >&2
    exit 1
    ;;
esac
