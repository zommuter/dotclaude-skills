#!/usr/bin/env bash
# meeting-guard-marker.sh — session-scoped marker read by hooks/meeting-question-guard.py
# (the Stop hook that BLOCKS a /meeting turn ending on bare prose without a
# same-turn AskUserQuestion; routed:29bc / TODO id:2419).
#
# Usage (session id defaults to $CLAUDE_SESSION_ID, set by the SessionStart hook):
#   meeting-guard-marker.sh start [--class fable|default] [--session ID]
#   meeting-guard-marker.sh end                           [--session ID]
#   meeting-guard-marker.sh disable                       [--session ID]
#   meeting-guard-marker.sh status                        [--session ID]
#   meeting-guard-marker.sh path                          [--session ID]
#
#   start    pin the harness class explicitly (otherwise the guard derives it from
#            the transcript's `message.model`). Fable-class is EXEMPT by spec —
#            format.md §Interactive mode requires Fable runs to end on prose with
#            inline numbered options and NOT call AskUserQuestion.
#   end      mark the meeting closed early (before the meeting note is written).
#   disable  ESCAPE HATCH — turn the block off for this session only.
#   status   print the marker JSON (or "absent").
#
# The marker can only ever REDUCE firing; it never arms the guard on its own.
# The guard's arming condition is derived from the transcript (a /meeting window
# with no meeting note written yet), so a forgotten `start` cannot silently
# disarm it and a forgotten `end` cannot block the rest of the session.
#
# Marker location: $CLAUDE_MEETING_GUARD_DIR, else $TMPDIR, else /tmp —
# session-scoped and outside every repo tree, so it can never be committed.
set -euo pipefail

action="${1:-status}"
shift || true

session="${CLAUDE_SESSION_ID:-}"
class=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --session) session="${2:-}"; shift 2 ;;
    --class)   class="${2:-}";   shift 2 ;;
    *) echo "meeting-guard-marker.sh: unknown argument '$1'" >&2; exit 64 ;;
  esac
done

if [[ -z "$session" ]]; then
  echo "meeting-guard-marker.sh: no session id (\$CLAUDE_SESSION_ID unset — pass --session ID)" >&2
  exit 64
fi

dir="${CLAUDE_MEETING_GUARD_DIR:-${TMPDIR:-/tmp}}"
mkdir -p "$dir"
marker="$dir/claude-meeting-guard-${session}.json"

case "$action" in
  start)
    [[ -z "$class" ]] && class="default"
    printf '{"session": "%s", "active": true, "class": "%s"}\n' "$session" "$class" > "$marker"
    echo "meeting-question-guard: class pinned to '$class' ($marker)"
    ;;
  end)
    printf '{"session": "%s", "active": false}\n' "$session" > "$marker"
    echo "meeting-question-guard: meeting marked closed ($marker)"
    ;;
  disable)
    printf '{"session": "%s", "disabled": true}\n' "$session" > "$marker"
    echo "meeting-question-guard: DISABLED for this session ($marker)"
    ;;
  status)
    if [[ -f "$marker" ]]; then cat "$marker"; else echo "absent ($marker)"; fi
    ;;
  path)
    echo "$marker"
    ;;
  *)
    echo "meeting-guard-marker.sh: unknown action '$action' (start|end|disable|status|path)" >&2
    exit 64
    ;;
esac
