#!/usr/bin/env bash
# broker-curl.sh <port> <endpoint> [json_body]
# Wrapper for all HTTP calls to the meeting-live broker.
# Allowlist: Bash(~/.claude/skills/meeting/broker-curl.sh *)
#
# Endpoints:
#   status              GET  /status     → {"subscribers": N}
#   events              GET  /events     SSE stream (curl -N)
#   event   <json>      POST /event      stream text to renderer
#   question <json>     POST /question   send decision prompt
#   await               GET  /await      block until renderer answers
#   response <json>     POST /response   renderer submits answer

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: broker-curl.sh <port> <status|events|event|question|await|response> [json]" >&2
  exit 1
fi

PORT=$1
ENDPOINT=$2
BASE="http://127.0.0.1:${PORT}"

case "$ENDPOINT" in
  status)
    curl -s "${BASE}/status"
    ;;
  events)
    curl -N "${BASE}/events"
    ;;
  await)
    curl -s "${BASE}/await"
    ;;
  event|question|response)
    JSON="${3:-{\}}"
    curl -s -X POST "${BASE}/${ENDPOINT}" \
      -H 'Content-Type: application/json' \
      -d "$JSON"
    ;;
  *)
    echo "Unknown endpoint: ${ENDPOINT}" >&2
    echo "Valid: status events event question await response" >&2
    exit 1
    ;;
esac
