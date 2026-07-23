#!/usr/bin/env bash
# mech-preflight.sh — front-door mechanical-tier preflight (roadmap:4239, owner directive
# 2026-07-23). CONSUMES the id:99a4 discriminator (probe-mech-proxy.sh) and turns its raw
# mode verdict into an ACTIONABLE signal + a LOUD operator warning. This is the tested helper
# the front-door PROSE calls (mirrors how probe-fable.sh is a tested helper SKILL.md step 0
# invokes) — the front door relays the warning to the operator and threads the stdout token
# into the Workflow (relay-loop.js reads it as A.MECH_FALLBACK, a single run-level flag, and
# dispatches its ~12 model:"bash" mechanical hops as model:"haiku" instead when told to).
#
#   relay/scripts/mech-preflight.sh preflight
#
# STDOUT TOKEN CONTRACT (exactly one line, exit 0 for all three — a preflight verdict is not
# an error; the caller branches on the token, never on the exit code):
#   fallback-haiku  — the proxy is NOT in the request path (probe mode-a): the session wasn't
#                     launched through mechanical-proxy.py, so model:"bash" hits the real API
#                     directly and 404s. The real API IS reachable directly, so the ~12
#                     model:"bash" mechanical hops must fall back to model:"haiku" for this run
#                     (Haiku genuinely runs the fenced relay-mech command via its Bash tool —
#                     the pre-proxy echo-runner path). A LOUD warning naming the exact restart
#                     env is printed to STDERR so the operator can relaunch through the proxy.
#   abort           — the base URL IS the proxy loopback form but the proxy is DOWN (probe
#                     mode-b): normal agent() traffic ALSO transits this dead proxy, so the whole
#                     session is degraded and Haiku is EQUALLY unreachable through it — a
#                     Haiku fallback is impossible. NEVER a fallback case. A LOUD warning is
#                     printed to STDERR; the caller surfaces it and (unattended) proceeds
#                     conservatively — the mechanical hops will fail-open as before, but they
#                     must NOT be silently swapped to an equally-dead Haiku.
#   proceed         — the proxy is healthy (probe healthy): model:"bash" is intercepted locally
#                     as designed. No warning, no fallback.
#
# Env:
#   MECH_PROBE   path to the discriminator, default the sibling probe-mech-proxy.sh (override
#                for tests to stub each mode). Invoked as `$MECH_PROBE discriminate`; it reads
#                the CURRENT $ANTHROPIC_BASE_URL (tolerating unset, per its own id:99a4 fix) and
#                MECH_PROXY_PORT.
#
# Hermetic: no writes, no cache, no ~/.claude touches — a thin decision layer over the probe.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MECH_PROBE="${MECH_PROBE:-$SCRIPT_DIR/probe-mech-proxy.sh}"

# The exact env a mode-a operator must relaunch with to route through the mechanical proxy.
# Kept as a single named constant so the warning text and any future consumer agree verbatim.
RESTART_ENV="ANTHROPIC_BASE_URL=http://127.0.0.1:61843"

usage() {
  echo "usage: mech-preflight.sh preflight" >&2
  exit 2
}

cmd="${1:-}"
case "$cmd" in
  preflight)
    # Run the discriminator. It exits 0 on every valid mode (mode-a/mode-b/healthy) and prints
    # the mode to stdout; a usage error exits 2. Capture stdout; let a hard failure surface.
    mode="$("$MECH_PROBE" discriminate)"

    case "$mode" in
      mode-a)
        {
          echo "mech-preflight: WARNING — mechanical proxy NOT in the request path (probe mode-a)."
          echo "  This session was NOT launched through mechanical-proxy.py, so the relay pool's"
          echo "  model:\"bash\" mechanical hops (quota gates, inject-take, heartbeat, file-surface)"
          echo "  would hit the real Anthropic API directly and 404 (no model named \"bash\")."
          echo "  Falling those ~12 hops back to model:\"haiku\" for THIS run (the real API is"
          echo "  reachable directly, so Haiku runs the fenced commands via its Bash tool)."
          echo "  To use the mechanical tier natively, relaunch the session with:"
          echo "      $RESTART_ENV"
        } >&2
        echo "fallback-haiku"
        exit 0
        ;;
      mode-b)
        {
          echo "mech-preflight: WARNING — proxy down at your base URL — whole session degraded (probe mode-b)."
          echo "  ANTHROPIC_BASE_URL points at the mechanical-proxy loopback form, but the proxy is"
          echo "  NOT answering. ALL agent() traffic transits this dead proxy, not just model:\"bash\""
          echo "  hops — so no model is reachable and a Haiku fallback is IMPOSSIBLE (Haiku routes"
          echo "  through the same dead proxy). Start/restart mechanical-proxy.py, or relaunch WITHOUT"
          echo "      $RESTART_ENV"
          echo "  Not falling back to Haiku (it is equally unreachable through a dead proxy)."
        } >&2
        echo "abort"
        exit 0
        ;;
      healthy)
        echo "proceed"
        exit 0
        ;;
      *)
        echo "mech-preflight: unexpected discriminator output '${mode}' from $MECH_PROBE" >&2
        exit 3
        ;;
    esac
    ;;
  *)
    usage
    ;;
esac
