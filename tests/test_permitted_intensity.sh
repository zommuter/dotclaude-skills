#!/usr/bin/env bash
# roadmap:e407 — permitted-intensity.json + relay-intensity.sh graded-window CLI
# (slice A, meeting 2026-07-02-1924 decision 4).
#
# Replaces (conceptually) the binary ALLOW_INTENSIVE gate with a GRADED, time-boxed,
# auto-expiring permit — "tea" (15m/light) vs "lunch" (2h/heavy). This RED spec pins the
# config file + CLI + `permits` predicate (the executor-buildable slice); the risky
# relay-loop.js engine wiring is a tracked follow-up, NOT required for green.
#
# CONTRACT:
#   permitted-intensity.json = {max_wall_seconds, resource_ceiling, expires_at}
#     (path env-overridable via RELAY_INTENSITY_FILE).
#   relay-intensity.sh --for <dur> --light|--heavy   write a tea/lunch window
#                      --afk                          conservative default (NOT full intensive)
#                      --intensive                    permissive window (supersedes ALLOW_INTENSIVE)
#                      --clear                         remove the permit
#                      --status                        print the current permit (or none)
#                      permits <est_wall> <resource>   exit 0 IFF est_wall<=window AND
#                                                       resource fits ceiling AND now<expires_at
#
# The resource->tier mapping (which names count "heavy") is the executor's judgment; this
# spec pins only the MONOTONIC property (local-llm passes a --heavy window, fails a --light
# one). REVIEW_ME records the mapping call.
#
# Hermetic: RELAY_INTENSITY_FILE points at a tmp file; no ~/.config, no network.
# RED until relay-intensity.sh lands.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SH="$ROOT/relay/scripts/relay-intensity.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SH" ]] || fail "relay-intensity.sh not found/executable at $SH (RED)"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export RELAY_INTENSITY_FILE="$tmp/permitted-intensity.json"

permits() { "$SH" permits "$1" "$2" >/dev/null 2>&1; }

# --- (1) no permit → deny by default (conservative) --------------------------
"$SH" --clear >/dev/null 2>&1 || true
if permits 60 cpu; then fail "(1) with no permit, permits must DENY (nonzero)"; fi
pass "(1) no permit → deny by default"

# --- (2) a lunch window (2h/heavy) permits a heavy job within the window ------
"$SH" --for 2h --heavy >/dev/null 2>&1 || fail "(2) --for 2h --heavy must succeed"
permits 3600 local-llm || fail "(2) a 1h heavy job must be permitted inside a 2h heavy window"
pass "(2) --for 2h --heavy permits a heavy job that fits the window"

# --- (3) over-window (est_wall > max_wall_seconds) → deny --------------------
if permits 100000 local-llm; then fail "(3) an over-window est_wall must be denied"; fi
pass "(3) over-window est_wall is denied"

# --- (4) a light/short window does NOT permit a heavy resource --------------
"$SH" --clear >/dev/null 2>&1 || true
"$SH" --for 15m --light >/dev/null 2>&1 || fail "(4) --for 15m --light must succeed"
if permits 60 local-llm; then fail "(4) a --light window must NOT permit a heavy resource (local-llm)"; fi
permits 60 cpu || fail "(4) a --light window must permit a light resource (cpu) within its window"
pass "(4) a light window admits light resources, refuses heavy ones"

# --- (5) bare --afk is conservative (NOT full intensive) --------------------
"$SH" --clear >/dev/null 2>&1 || true
"$SH" --afk >/dev/null 2>&1 || fail "(5) --afk must write a conservative permit"
if permits 3600 local-llm; then
  fail "(5) bare --afk must NOT permit a heavy job (conservative, not full intensive)"
fi
pass "(5) bare --afk is a conservative window, not full intensive"

# --- (6) --status reflects the current permit; --clear empties it ------------
"$SH" --for 2h --heavy >/dev/null 2>&1
st="$("$SH" --status 2>&1)" || fail "(6) --status must exit 0"
[[ -n "$st" ]] || fail "(6) --status must print the current permit"
grep -qiv '^none$' <<<"$st" || fail "(6) --status must not say 'none' while a permit is set"
"$SH" --clear >/dev/null 2>&1
if permits 60 cpu; then fail "(6) after --clear, permits must DENY (nonzero)"; fi
pass "(6) --status reflects the permit; --clear removes it"

# --- (7) an immediately-expired window (--for 0m) denies --------------------
"$SH" --for 0m --heavy >/dev/null 2>&1 || true
if permits 1 cpu; then fail "(7) a 0-duration/expired window must deny (now >= expires_at)"; fi
pass "(7) an expired window denies"

echo "ALL PASS: permitted-intensity graded window (id:e407)"
