#!/usr/bin/env bash
# roadmap:99a4 — mechanical-proxy availability probe + two-mode discriminator (owner
# directive 2026-07-23, fixes id:7e6d). Mirrors probe-fable.sh's shape (cache +
# check/set) but the core deliverable specced here is the DISCRIMINATOR:
#
#   relay/scripts/probe-mech-proxy.sh discriminate
#     mode-a   — ANTHROPIC_BASE_URL empty, or set but NOT the loopback+port form
#                (http://127.0.0.1:<MECH_PROXY_PORT default 61843>). Session wasn't
#                launched through the proxy — model:"bash" hits the real API directly.
#                Unfixable in-session; remedy = LOUD warning naming the restart env +
#                Haiku fallback (real API IS reachable directly in this mode).
#     mode-b   — base URL IS the loopback+port form, but a liveness check (TCP-connect
#                the port / trivial echo) fails. Proxy down/broken at the session's own
#                base URL — normal agent() traffic is ALSO dead, so Haiku fallback is
#                equally unreachable. NOT a Haiku-fallback case.
#     healthy  — loopback+port base URL AND the liveness check succeeds.
#
# Env: ANTHROPIC_BASE_URL read via plain "$ANTHROPIC_BASE_URL" (never ${VAR:-}, repo
# convention). Port from MECH_PROXY_PORT, default 61843.
#
# Triangulated cases (id:108e — several DISTINCT cases so special-casing the exact
# inputs is harder than implementing the real behaviour):
#   1. ANTHROPIC_BASE_URL empty                              -> mode-a
#   2. ANTHROPIC_BASE_URL non-loopback (https://api.anthropic.com) -> mode-a
#   3. ANTHROPIC_BASE_URL loopback but a definitely-closed port     -> mode-b
#   4. ANTHROPIC_BASE_URL loopback with a real stub server answering -> healthy
#
# Hermetic: mktemp -d, no network beyond loopback (case 4 spins a throwaway stub HTTP
# server on a free port, killed via trap), no ~/.claude writes.
set -uo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROBE="$SRC_DIR/relay/scripts/probe-mech-proxy.sh"

pass=0 fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); return 0; }
bad() { echo "BAD: $*"; fail=$((fail+1)); return 0; }

if [[ ! -f "$PROBE" ]]; then
  echo "FAIL: relay/scripts/probe-mech-proxy.sh does not exist yet (RED spec, id:99a4)"
  exit 1
fi
if [[ ! -x "$PROBE" ]]; then
  echo "FAIL: probe-mech-proxy.sh exists but is not executable"
  exit 1
fi

TMP="$(mktemp -d)"
STUB_PID=""
cleanup() {
  [[ -n "$STUB_PID" ]] && kill "$STUB_PID" 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT

# --- case 1: ANTHROPIC_BASE_URL empty -> mode-a --------------------------------
out="$(ANTHROPIC_BASE_URL="" "$PROBE" discriminate 2>"$TMP/err1")"
rc=$?
if [[ $rc -eq 0 && "$out" == "mode-a" ]]; then
  ok "empty ANTHROPIC_BASE_URL -> mode-a"
else
  bad "empty ANTHROPIC_BASE_URL should discriminate 'mode-a' (got out='${out}' rc=${rc})"
fi

# --- case 2: ANTHROPIC_BASE_URL set to a non-loopback URL -> mode-a ------------
out="$(ANTHROPIC_BASE_URL="https://api.anthropic.com" "$PROBE" discriminate 2>"$TMP/err2")"
rc=$?
if [[ $rc -eq 0 && "$out" == "mode-a" ]]; then
  ok "non-loopback ANTHROPIC_BASE_URL -> mode-a"
else
  bad "non-loopback ANTHROPIC_BASE_URL should discriminate 'mode-a' (got out='${out}' rc=${rc})"
fi

# --- case 3: ANTHROPIC_BASE_URL loopback+port, port definitely closed -> mode-b --
# Find a port that is almost certainly closed: bind then immediately release it,
# then use the same number (race is acceptable for a closed-port fixture — if
# something else grabs it in that instant this fixture would need re-running, but
# in practice this is stable in CI/dev sandboxes).
CLOSED_PORT="$(python3 - <<'PY'
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
)"
out="$(ANTHROPIC_BASE_URL="http://127.0.0.1:${CLOSED_PORT}" MECH_PROXY_PORT="$CLOSED_PORT" "$PROBE" discriminate 2>"$TMP/err3")"
rc=$?
if [[ $rc -eq 0 && "$out" == "mode-b" ]]; then
  ok "loopback base URL, closed port -> mode-b"
else
  bad "loopback base URL with a closed port should discriminate 'mode-b' (got out='${out}' rc=${rc})"
fi

# --- case 4: ANTHROPIC_BASE_URL loopback+port, a real stub server answers -> healthy
STUB_PORT="$(python3 - <<'PY'
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
)"
python3 -c "
import http.server, socketserver
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'ok')
    def do_POST(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'ok')
    def log_message(self, *a):
        pass
with socketserver.TCPServer(('127.0.0.1', ${STUB_PORT}), H) as httpd:
    httpd.serve_forever()
" &
STUB_PID=$!
# Wait for the stub to actually be accepting connections (bounded poll, hermetic).
for _ in $(seq 1 50); do
  if (exec 3<>"/dev/tcp/127.0.0.1/${STUB_PORT}") 2>/dev/null; then
    exec 3>&- 3<&-
    break
  fi
  sleep 0.1
done

out="$(ANTHROPIC_BASE_URL="http://127.0.0.1:${STUB_PORT}" MECH_PROXY_PORT="$STUB_PORT" "$PROBE" discriminate 2>"$TMP/err4")"
rc=$?
if [[ $rc -eq 0 && "$out" == "healthy" ]]; then
  ok "loopback base URL, live stub server -> healthy"
else
  bad "loopback base URL with a live stub server should discriminate 'healthy' (got out='${out}' rc=${rc})"
fi

echo
echo "pass=$pass fail=$fail"
[[ $fail -eq 0 ]]
