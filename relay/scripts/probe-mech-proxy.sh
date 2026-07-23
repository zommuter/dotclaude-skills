#!/usr/bin/env bash
# probe-mech-proxy.sh — mechanical-proxy availability probe + two-mode discriminator
# (owner directive 2026-07-23, fixes id:7e6d, roadmap:99a4). Mirrors probe-fable.sh's
# shape (small, hermetic, no model calls) but the deliverable here is the
# DISCRIMINATOR, not a cache.
#
#   relay/scripts/probe-mech-proxy.sh discriminate
#     mode-a   — ANTHROPIC_BASE_URL empty, or set but NOT the loopback+port form
#                (http://127.0.0.1:<MECH_PROXY_PORT default 61843>). The session
#                wasn't launched through the proxy: model:"bash" hits the real API
#                directly. Unfixable in-session (the harness binds the global base
#                URL at startup) — the remedy is a LOUD warning naming the exact
#                restart env, plus falling model:"bash" steps back to Haiku for this
#                run (the real API IS reachable directly in mode-a).
#     mode-b   — base URL IS the loopback+port form, but a liveness check (TCP
#                connect the port) fails. The proxy is down/broken at the session's
#                own base URL — normal agent() traffic is ALSO dead, so a Haiku
#                fallback is equally unreachable through a dead proxy. NOT a
#                Haiku-fallback case: the remedy is attempt (re)start / else LOUD
#                ABORT, never a silent degrade.
#     healthy  — loopback+port base URL AND the liveness check succeeds.
#
# Env: ANTHROPIC_BASE_URL read via plain "$ANTHROPIC_BASE_URL" (never ${VAR:-}, repo
# convention — that expansion form trips a permission prompt). Port from
# MECH_PROXY_PORT, default 61843.
#
# Hermetic: no writes, no cache, no ~/.claude touches — a pure TCP-connect check.
set -euo pipefail

usage() {
  echo "usage: probe-mech-proxy.sh discriminate" >&2
  exit 2
}

# is_loopback_base_url <url> <port>: true iff url is exactly http://127.0.0.1:<port>
# (literal loopback + literal port match — no partial/prefix match).
is_loopback_base_url() {
  local url="$1" port="$2"
  [[ "$url" == "http://127.0.0.1:${port}" ]]
}

# port_alive <port>: true iff a TCP connect to 127.0.0.1:<port> succeeds.
port_alive() {
  local port="$1"
  (exec 3<>"/dev/tcp/127.0.0.1/${port}") 2>/dev/null
  local rc=$?
  exec 3>&- 3<&- 2>/dev/null || true
  return "$rc"
}

cmd="${1:-}"
case "$cmd" in
  discriminate)
    port="${MECH_PROXY_PORT:-61843}"

    base_url="$ANTHROPIC_BASE_URL"

    if [[ -z "$base_url" ]]; then
      echo "mode-a"
      exit 0
    fi

    if ! is_loopback_base_url "$base_url" "$port"; then
      echo "mode-a"
      exit 0
    fi

    if port_alive "$port"; then
      echo "healthy"
      exit 0
    else
      echo "mode-b"
      exit 0
    fi
    ;;
  *)
    usage
    ;;
esac
