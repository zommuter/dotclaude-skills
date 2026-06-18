#!/usr/bin/env bash
# relay-status-publish.sh (id:0d31 — skeleton L1 thin-glue) — deterministic publisher for
# RELAY_STATUS.md + the append-only event log. It replaces a ~40-line haiku "glue" agent recipe
# (writeRelayStatus in relay-loop.js) that the Workflow engine could not run itself (it cannot
# exec shell — id:6e9d). The agent STAYS (engine constraint), but its prompt collapses to one
# piped invocation: short + precise → no target-drift (a weak model formatting claims-JSON into
# markdown and branching on "events or not" is exactly where drift happened).
#
# This script owns the deterministic work the agent used to do by hand:
#   • resolve the status path (refuse a non-absolute / unexpanded ~/$HOME target),
#   • peek live cross-session claims (claim.sh peek) and render the "## Claims (live)" section,
#   • render the "## Burnup this run" section from relay-burn.sh report,
#   • write the combined content ATOMICALLY via the flock'd single-writer (relay-state-write.sh
#     status-write — id:ebfb step 2),
#   • append any event lines to the JSONL via relay-state-write.sh event-append.
#
# I/O: the BASE status content (buildRelayStatus output) is read on stdin. If event lines are to
# be appended, they follow the content after ONE line equal to the sentinel below:
#     <status content>
#     ===RELAY-EVENTS===
#     <event json line 1>
#     <event json line 2>
# Everything before the sentinel is the content; everything after is the events block (may be
# empty / the sentinel absent → no events). The sentinel is intentionally unlikely in markdown.
#
# Usage: relay-status-publish.sh --path <status-path> --run <runId> --events-path <jsonl-path>
set -euo pipefail

SENTINEL='===RELAY-EVENTS==='
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_WRITE="$HERE/relay-state-write.sh"
CLAIM="$HERE/claim.sh"
BURN="$HERE/relay-burn.sh"

path="" run="" events_path=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --path)        path="$2"; shift 2 ;;
    --run)         run="$2"; shift 2 ;;
    --events-path) events_path="$2"; shift 2 ;;
    *) echo "relay-status-publish: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$path" ]] || { echo "relay-status-publish: --path is required" >&2; exit 2; }

# Resolve ~ / $HOME in the target; refuse anything that did not expand to an absolute path
# (the same guard the agent applied + relay-state-write.sh re-checks — id:c34a).
resolve() { python3 -c 'import os,sys; print(os.path.expanduser(sys.argv[1]))' "$1"; }
target="$(resolve "$path")"
case "$target" in
  /*) : ;;
  *) echo "relay-status-publish: refusing non-absolute/unexpanded target: $target" >&2; exit 1 ;;
esac

# Split stdin into the content and the (optional) trailing events block at the sentinel line.
raw="$(cat)"
content="$raw"
events=""
if printf '%s\n' "$raw" | grep -qxF "$SENTINEL"; then
  content="$(printf '%s\n' "$raw" | sed "/^${SENTINEL}\$/,\$d")"
  events="$(printf '%s\n' "$raw" | sed "1,/^${SENTINEL}\$/d")"
fi

# ── ## Claims (live) — render live cross-session claims (id:ebfb). ──
claims_section="## Claims (live)"
claim_lines="$("$CLAIM" peek 2>/dev/null || true)"
if [[ -n "$claim_lines" ]]; then
  rendered="$(printf '%s\n' "$claim_lines" | while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    # {key,repo,runId,mode,item,...}; show repo (or item when repo empty), mode, run.
    printf '%s' "$line" | jq -r '"- " + (if (.repo // "") != "" then .repo else (.item // "?") end)
      + "  mode=" + (.mode // "?") + "  run=" + (.runId // "?")' 2>/dev/null || true
  done)"
  claims_section+=$'\n'"${rendered:-_(none)_}"
else
  claims_section+=$'\n''_(none)_'
fi

# ── ## Burnup this run — from relay-burn.sh report (stdout empty when <2 samples). ──
burnup_section="## Burnup this run"
burn_out=""
[[ -n "$run" ]] && burn_out="$("$BURN" report --run "$run" 2>/dev/null || true)"
if [[ -n "$burn_out" ]]; then
  burnup_section+=$'\n''```'$'\n'"$burn_out"$'\n''```'
else
  burnup_section+=$'\n''_(insufficient samples yet)_'
fi

combined="${content}"$'\n\n'"${claims_section}"$'\n\n'"${burnup_section}"$'\n'

# Atomic, flock'd single-writer (mkdir -p + temp + atomic mv + ~/$HOME refusal — id:ebfb step 2).
printf '%s' "$combined" | "$STATE_WRITE" status-write "$target"

# Append event lines off-critical-path (id:c8b6). Only when there is a non-empty events block.
if [[ -n "${events//[$'\n\t ']/}" && -n "$events_path" ]]; then
  evt="$(resolve "$events_path")"
  printf '%s\n' "$events" | "$STATE_WRITE" event-append "$evt"
fi

echo "relay-status-publish: wrote $target"
