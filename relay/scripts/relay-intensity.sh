#!/usr/bin/env bash
# relay-intensity.sh — graded, time-boxed, auto-expiring permit for an intensive
# mechanical run (id:e407, meeting 2026-07-02-1924 decision 4). Replaces the binary
# ALLOW_INTENSIVE gate conceptually: instead of "on/off", a human authorizes a
# bounded window — "tea" (15m/light) or "lunch" (2h/heavy) — that expires on its own.
#
# State file (JSON): {max_wall_seconds, resource_ceiling, expires_at}
#   - max_wall_seconds: the longest single job the window covers.
#   - resource_ceiling:  "light" or "heavy" — ORDERED, light < heavy. A light window
#     covers only light-tier resources (e.g. cpu); a heavy window covers both.
#   - expires_at: unix epoch seconds; permits() denies once now >= expires_at.
#
# Path is env-overridable via RELAY_INTENSITY_FILE (default
# ~/.config/relay/permitted-intensity.json) — the RED test hermetically points this
# at a tmp file, no ~/.config / network touched by the test.
#
# Usage:
#   relay-intensity.sh --for <dur> --light|--heavy   write a tea/lunch style window
#                                                     (dur: <N>s / <N>m / <N>h)
#   relay-intensity.sh --afk                         CONSERVATIVE default: short+light
#                                                     (NOT full intensive — preserves the
#                                                     old binary ALLOW_INTENSIVE=off-by-default
#                                                     semantics for unattended runs)
#   relay-intensity.sh --intensive | --allow-intensive
#                                                     back-compat: a permissive (heavy,
#                                                     long) window, superseding the old
#                                                     binary ALLOW_INTENSIVE=1 gate
#   relay-intensity.sh --clear                       remove the permit
#   relay-intensity.sh --status                      print the current permit (or "none")
#   relay-intensity.sh permits <est_wall_seconds> <resource>
#                                                     predicate: exit 0 IFF est_wall <=
#                                                     max_wall_seconds AND resource fits
#                                                     resource_ceiling AND now < expires_at;
#                                                     exit 1 otherwise (no permit / expired /
#                                                     over-window / over-ceiling — DENY by
#                                                     default is the conservative failure mode)
#
# Resource -> tier mapping (executor judgment call, id:e407 Context note; recorded in
# REVIEW_ME): resource names in HEAVY_RESOURCES below are "heavy" (need a --heavy/lunch
# or --intensive window); everything else is treated as "light" (permitted by any
# non-expired window, including --light/tea and --afk).
set -euo pipefail

STATE_FILE="${RELAY_INTENSITY_FILE:-$HOME/.config/relay/permitted-intensity.json}"

# Resource names considered "heavy" — GPU/local-model style jobs. Anything not listed
# here (cpu, disk, network, ...) is "light". Keep in sync with
# relay/references/resource-claims.md's resource vocabulary if it grows.
HEAVY_RESOURCES=(gpu local-llm local-model llama)

usage() { sed -n '2,45p' "$0"; }

is_heavy_resource() {
  local r="$1" h
  for h in "${HEAVY_RESOURCES[@]}"; do
    [ "$r" = "$h" ] && return 0
  done
  return 1
}

# tier_rank: light=1, heavy=2 (ordered, light < heavy).
tier_rank() {
  case "$1" in
    light) echo 1 ;;
    heavy) echo 2 ;;
    *) echo "relay-intensity.sh: unknown resource_ceiling tier '$1'" >&2; exit 2 ;;
  esac
}

# parse_duration <N>s|<N>m|<N>h -> seconds
parse_duration() {
  local d="$1"
  case "$d" in
    *h) echo $(( ${d%h} * 3600 )) ;;
    *m) echo $(( ${d%m} * 60 )) ;;
    *s) echo $(( ${d%s} )) ;;
    ''|*[!0-9]*) echo "relay-intensity.sh: bad duration '$d' (want <N>s|<N>m|<N>h)" >&2; exit 2 ;;
    *) echo "$d" ;;  # bare integer -> seconds
  esac
}

write_permit() {
  local max_wall="$1" ceiling="$2" for_seconds="$3"
  local now expires
  now="$(date +%s)"
  expires=$(( now + for_seconds ))
  mkdir -p "$(dirname "$STATE_FILE")"
  jq -n --argjson max_wall_seconds "$max_wall" \
        --arg resource_ceiling "$ceiling" \
        --argjson expires_at "$expires" \
        '{max_wall_seconds: $max_wall_seconds, resource_ceiling: $resource_ceiling, expires_at: $expires_at}' \
        >"$STATE_FILE.tmp"
  mv "$STATE_FILE.tmp" "$STATE_FILE"
}

cmd_clear() {
  # idempotent: the state file may not exist (clearing when nothing is set). No force, no swallow.
  [ -e "$STATE_FILE" ] && rm -- "$STATE_FILE"
  return 0
}

cmd_status() {
  if [ ! -f "$STATE_FILE" ]; then
    echo "none"
    return 0
  fi
  local now max_wall ceiling expires
  now="$(date +%s)"
  max_wall="$(jq -r '.max_wall_seconds' "$STATE_FILE")"
  ceiling="$(jq -r '.resource_ceiling' "$STATE_FILE")"
  expires="$(jq -r '.expires_at' "$STATE_FILE")"
  if [ "$now" -ge "$expires" ]; then
    echo "none (expired at $expires)"
    return 0
  fi
  echo "max_wall_seconds=$max_wall resource_ceiling=$ceiling expires_at=$expires (in $(( expires - now ))s)"
}

cmd_permits() {
  local est_wall="$1" resource="$2"
  [ -f "$STATE_FILE" ] || return 1

  local now max_wall ceiling expires
  now="$(date +%s)"
  max_wall="$(jq -r '.max_wall_seconds // empty' "$STATE_FILE" 2>/dev/null || true)"
  ceiling="$(jq -r '.resource_ceiling // empty' "$STATE_FILE" 2>/dev/null || true)"
  expires="$(jq -r '.expires_at // empty' "$STATE_FILE" 2>/dev/null || true)"
  [ -n "$max_wall" ] && [ -n "$ceiling" ] && [ -n "$expires" ] || return 1

  # now < expires_at (strict — an immediately-expired/0-duration window denies).
  [ "$now" -lt "$expires" ] || return 1

  # est_wall <= max_wall_seconds
  [ "$est_wall" -le "$max_wall" ] || return 1

  # resource <= resource_ceiling (ordered: light < heavy)
  local resource_rank ceiling_rank
  if is_heavy_resource "$resource"; then resource_rank=2; else resource_rank=1; fi
  ceiling_rank="$(tier_rank "$ceiling")"
  [ "$resource_rank" -le "$ceiling_rank" ] || return 1

  return 0
}

[ $# -gt 0 ] || { usage; exit 2; }

case "$1" in
  -h|--help|help)
    usage; exit 0
    ;;
  --for)
    dur="${2:-}"; tier_flag="${3:-}"
    [ -n "$dur" ] || { echo "relay-intensity.sh: --for requires a duration (e.g. 15m, 2h)" >&2; exit 2; }
    for_seconds="$(parse_duration "$dur")"
    case "$tier_flag" in
      --light) ceiling="light"; max_wall="$for_seconds" ;;
      --heavy) ceiling="heavy"; max_wall="$for_seconds" ;;
      *) echo "relay-intensity.sh: --for <dur> requires --light or --heavy (got '$tier_flag')" >&2; exit 2 ;;
    esac
    write_permit "$max_wall" "$ceiling" "$for_seconds"
    ;;
  --afk)
    # CONSERVATIVE default: short + light. Bare --afk must NOT permit a heavy job —
    # this preserves the old binary ALLOW_INTENSIVE semantics for unattended runs
    # (see [[relay-hands-disposition-redesign-2026-06-30]] / [[fable-down-flag]]).
    write_permit 300 light 900
    ;;
  --intensive|--allow-intensive)
    # Back-compat: a permissive (heavy, long) window superseding the old binary
    # ALLOW_INTENSIVE=1 gate.
    write_permit 7200 heavy 7200
    ;;
  --clear)
    cmd_clear
    ;;
  --status)
    cmd_status
    ;;
  permits)
    est_wall="${2:-}"; resource="${3:-}"
    [ -n "$est_wall" ] && [ -n "$resource" ] || { echo "relay-intensity.sh: permits <est_wall_seconds> <resource>" >&2; exit 2; }
    cmd_permits "$est_wall" "$resource"
    ;;
  *)
    echo "relay-intensity.sh: unknown argument '$1'" >&2
    usage
    exit 2
    ;;
esac
