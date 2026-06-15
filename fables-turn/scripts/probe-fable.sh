#!/usr/bin/env bash
# probe-fable.sh — Fable-availability probe CACHE manager for the fables-turn front door (id:da26).
#
# The ACTUAL probe (spawning a tiny claude-fable-5 agent) stays in the front door
# (SKILL.md step 0). This helper ONLY manages the on-disk cache + 2h staleness: it
# reads the cache and tells the front door whether a fresh result exists, and it
# records a fresh result the agent-probe produced. Keeping the agent out of here keeps
# the helper hermetically testable (no model, no network).
#
# Cache JSON shape (matches SKILL.md step 0):
#   { "available": true|false, "checked": "<ISO 8601 timestamp>" }
#
# Usage:
#   probe-fable.sh check
#       Read the cache and print one of:
#         fresh-available    (exit 0) — cache <2h old, available=true  → skip the agent-probe, use Fable
#         fresh-unavailable  (exit 0) — cache <2h old, available=false → skip the agent-probe, use Opus
#         stale              (exit 1) — cache exists but >2h old       → RUN the agent-probe, then `set`
#         absent             (exit 1) — no cache yet                   → RUN the agent-probe, then `set`
#       Exit 0 = a fresh decision exists (no probe needed); exit 1 = caller should
#       run the actual agent-probe and record the result via `set`.
#
#   probe-fable.sh set <true|false> [ISO-timestamp]
#       Write {available, checked} to the cache. The timestamp arg is accepted so
#       tests can pin staleness deterministically; it falls back to `date -Iseconds`.
#
# Env:
#   PROBE_CACHE   cache path, default ~/.config/fables-turn/fable-probe.json (override for tests)
set -euo pipefail

PROBE_CACHE="${PROBE_CACHE:-$HOME/.config/fables-turn/fable-probe.json}"
STALE_SECS=7200   # 2 hours

usage() {
  echo "usage: probe-fable.sh check | set <true|false> [ISO-timestamp]" >&2
  exit 2
}

cmd="${1:-}"
case "$cmd" in
  check)
    if [[ ! -f "$PROBE_CACHE" ]]; then
      echo "absent"
      exit 1
    fi
    # Read fields with python3 (stdlib; the project's only JSON dependency besides jq).
    read -r available checked < <(
      python3 - "$PROBE_CACHE" <<'PY'
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
    print(("true" if d.get("available") else "false"), d.get("checked", ""))
except Exception:
    print("error", "")
PY
    )
    if [[ "$available" == "error" || -z "$checked" ]]; then
      # Unreadable / malformed cache → treat as absent (caller re-probes).
      echo "absent"
      exit 1
    fi
    # Compute age from the `checked` ISO timestamp (not the file mtime — the cache
    # records when the probe ran, which is the staleness clock the front door cares about).
    checked_epoch=$(date -d "$checked" +%s 2>/dev/null || echo "")
    if [[ -z "$checked_epoch" ]]; then
      echo "absent"
      exit 1
    fi
    now_epoch=$(date +%s)
    age=$(( now_epoch - checked_epoch ))
    if [[ "$age" -gt "$STALE_SECS" ]]; then
      echo "stale"
      exit 1
    fi
    if [[ "$available" == "true" ]]; then
      echo "fresh-available"
    else
      echo "fresh-unavailable"
    fi
    exit 0
    ;;
  set)
    val="${2:-}"
    case "$val" in
      true|false) ;;
      *) echo "probe-fable: set requires 'true' or 'false', got '${val}'" >&2; usage ;;
    esac
    ts="${3:-$(date -Iseconds)}"
    mkdir -p "$(dirname "$PROBE_CACHE")"
    python3 - "$PROBE_CACHE" "$val" "$ts" <<'PY'
import json, sys
path, val, ts = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, "w") as f:
    json.dump({"available": val == "true", "checked": ts}, f)
    f.write("\n")
PY
    echo "set available=$val checked=$ts"
    exit 0
    ;;
  *)
    usage
    ;;
esac
