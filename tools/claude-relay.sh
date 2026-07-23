# claude-relay (dotclaude-skills id:69f6/id:99a4) — canonical source; rc files `source` this
# via `make install-claude-relay`. Launch Claude Code THROUGH the local mechanical-proxy
# (127.0.0.1:MECH_PROXY_PORT) ONLY when the proxy is healthy; otherwise run direct.
#
# Opt-in by design: plain `claude` stays direct and unperturbed — the proxy is a MITM in
# every request path, and the 2026-06-03 ratified guardrail (id:e905) keeps it opt-in-only,
# never global. The health check reuses probe-mech-proxy.sh (id:99a4). NOTE: the probe's
# `discriminate` reads the CURRENT $ANTHROPIC_BASE_URL, so we call it WITH the loopback URL
# set — otherwise (base URL unset) it always returns mode-a and we'd never use the proxy.
# If the script is absent, or the probe returns anything but `healthy`, we fall through to a
# normal direct launch.
claude-relay() {
  local probe="$HOME/.claude/skills/relay/scripts/probe-mech-proxy.sh"
  local port="${MECH_PROXY_PORT:-61843}"
  local url="http://127.0.0.1:${port}"
  if [ -x "$probe" ] && [ "$(ANTHROPIC_BASE_URL="$url" "$probe" discriminate)" = "healthy" ]; then
    ANTHROPIC_BASE_URL="$url" command claude "$@"
  else
    echo "claude-relay: mech-proxy not healthy — running direct" >&2
    command claude "$@"
  fi
}
