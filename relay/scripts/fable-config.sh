#!/usr/bin/env bash
# relay/scripts/fable-config.sh — explicit Fable-availability CONFIG reader (id:aa26).
#
# REPLACES probe-fable.sh (retired 2026-07-28, constraint archaeology): Fable is now a
# fixed part of the Max subscription, so "is Fable up right now?" is a question with a
# permanently-constant answer. There is nothing left to PROBE — no cache, no staleness
# window, no spawned agent-probe. This script only reads a DECLARED setting so a user
# WITHOUT Fable access can turn it off; everyone else gets the Max default.
#
# Cache/probe machinery this intentionally does NOT have (compare probe-fable.sh):
#   - no ~/.config/relay/fable-probe.json (or any cache file at all)
#   - no staleness/TTL check
#   - no code path that spawns a model to test availability
#
# Config shape (relay.toml):
#   [relay]
#   fable_available = false   # optional; ABSENT ⇒ available (the Max default)
#
# Usage:
#   fable-config.sh check
#       Prints one of:
#         available     (exit 0) — config absent, or fable_available = true
#         unavailable   (exit 1) — fable_available = false
#
# Env:
#   RELAY_TOML   relay.toml path, default ~/.config/relay/relay.toml (override for tests)
set -euo pipefail

RELAY_TOML="${RELAY_TOML:-$HOME/.config/relay/relay.toml}"

usage() {
  echo "usage: fable-config.sh check" >&2
  exit 2
}

cmd="${1:-}"
case "$cmd" in
  check)
    # Absent config file ⇒ available (the Max default) — no relay.toml at all is a valid
    # "nothing declared" state, same convention as lib-own-repos.sh's own_repos().
    if [[ ! -f "$RELAY_TOML" ]]; then
      echo "available"
      exit 0
    fi
    result="$(RELAY_TOML="$RELAY_TOML" python3 -c '
import os, sys, tomllib
path = os.environ["RELAY_TOML"]
try:
    with open(path, "rb") as f:
        data = tomllib.load(f)
except Exception as e:
    print(f"fable-config: FAILED to parse relay.toml ({path}): {e}", file=sys.stderr)
    sys.exit(2)
relay = data.get("relay", {})
avail = relay.get("fable_available", True)
print("available" if avail else "unavailable")
')"
    echo "$result"
    [[ "$result" == "available" ]]
    ;;
  *)
    usage
    ;;
esac
