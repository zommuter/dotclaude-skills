#!/usr/bin/env python3
"""
Throwaway LLM proxy spike.

Minimal localhost HTTP → api.anthropic.com HTTPS pass-through.
NOT standing infra — opt-in only, never in a default path.

Guardrails:
  - plain-http 127.0.0.1:PORT only; no cert-MITM; proxy originates own TLS
  - all request headers (incl. Authorization/x-api-key) forwarded byte-for-byte
  - opt-in: set ANTHROPIC_BASE_URL=http://127.0.0.1:PORT before starting claude

Success criterion: one SSE-streaming Claude Code turn completes unbuffered;
proxy logs request-body size + response usage.

Usage:
  python3 meeting/contrib/llm-proxy.py
  # then in a separate shell:
  ANTHROPIC_BASE_URL=http://127.0.0.1:61842 claude

Env vars:
  LLM_PROXY_PORT   (default 61842)
  LLM_PROXY_LOG    (default /tmp/llm-proxy.log)
"""
import http.client
import json
import os
import queue
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

UPSTREAM_HOST = "api.anthropic.com"
PORT = int(os.environ.get("LLM_PROXY_PORT", 61842))
LOG_FILE = os.environ.get("LLM_PROXY_LOG", "/tmp/llm-proxy.log")

# Hop-by-hop headers we must not forward (RFC 7230 §6.1)
_HOP_BY_HOP = frozenset([
    "connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
    "te", "trailers", "transfer-encoding", "upgrade",
])

_log_lock = threading.Lock()

# Connection pool — reuse HTTPS connections to avoid per-request TLS handshake overhead.
# Connections are only returned here when the response body is fully consumed; broken
# or partially-read connections are dropped so the pool stays clean.
_pool: queue.SimpleQueue = queue.SimpleQueue()


def _get_conn() -> http.client.HTTPSConnection:
    try:
        return _pool.get_nowait()
    except queue.Empty:
        return http.client.HTTPSConnection(UPSTREAM_HOST, timeout=120)


def _return_conn(conn: http.client.HTTPSConnection) -> None:
    _pool.put_nowait(conn)


def _log(entry: dict):
    line = json.dumps(entry)
    with _log_lock:
        with open(LOG_FILE, "a") as f:
            f.write(line + "\n")
    print(line, flush=True)


class ProxyHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args): pass  # silence default access log  # noqa: A002

    def _proxy(self):
        req_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(req_length) if req_length else b""

        # Build upstream headers: drop hop-by-hop, replace Host.
        # Strip Accept-Encoding: upstream would send compressed bytes that we can't
        # transparently forward without decompressing first. Force plain text for the spike.
        fwd_headers = {
            k: v for k, v in self.headers.items()
            if k.lower() not in _HOP_BY_HOP and k.lower() not in ("host", "accept-encoding")
        }
        if body:
            fwd_headers["Content-Length"] = str(len(body))

        conn = _get_conn()
        try:
            conn.request(self.command, self.path, body=body or None, headers=fwd_headers)
            resp = conn.getresponse()
        except Exception:
            conn.close()
            # Stale pooled connection — retry once with a fresh one
            conn = http.client.HTTPSConnection(UPSTREAM_HOST, timeout=120)
            try:
                conn.request(self.command, self.path, body=body or None, headers=fwd_headers)
                resp = conn.getresponse()
            except Exception as exc:
                conn.close()
                _log({"event": "upstream_error", "path": self.path, "error": str(exc)})
                self.send_error(502, str(exc))
                return

        # Forward status + response headers (skip hop-by-hop)
        self.send_response(resp.status)
        resp_content_type = ""
        for k, v in resp.getheaders():
            if k.lower() in _HOP_BY_HOP:
                continue
            self.send_header(k, v)
            if k.lower() == "content-type":
                resp_content_type = v
        self.end_headers()

        is_sse = "text/event-stream" in resp_content_type

        # Stream body: use read1() for unbuffered SSE forwarding (one syscall at a time).
        buf_lines: list[bytes] = []
        fully_consumed = False
        try:
            fp = resp.fp  # socket-backed BufferedReader
            while True:
                try:
                    chunk = fp.read1(4096)  # returns immediately with whatever is available
                except AttributeError:
                    chunk = fp.read(256)    # fallback: small fixed read
                if not chunk:
                    fully_consumed = True
                    break
                self.wfile.write(chunk)
                self.wfile.flush()
                if is_sse:
                    buf_lines.append(chunk)
        except (BrokenPipeError, ConnectionResetError):
            pass
        finally:
            if fully_consumed:
                _return_conn(conn)  # safe to reuse — body fully read
            else:
                conn.close()       # partial read — don't reuse

        # Extract usage from the last SSE "data:" line that carries it
        usage = None
        if is_sse:
            full = b"".join(buf_lines).decode("utf-8", errors="replace")
            for line in reversed(full.splitlines()):
                if line.startswith("data:") and '"usage"' in line:
                    try:
                        payload = json.loads(line[5:].strip())
                        usage = payload.get("usage")
                        break
                    except json.JSONDecodeError:
                        pass

        _log({
            "event": "request",
            "method": self.command,
            "path": self.path,
            "request_body_bytes": req_length,
            "response_status": resp.status,
            "is_sse": is_sse,
            "usage": usage,
        })

    do_GET = do_POST = do_PUT = do_DELETE = do_PATCH = _proxy


def main():
    server = ThreadingHTTPServer(("127.0.0.1", PORT), ProxyHandler)
    print(f"LLM proxy on http://127.0.0.1:{PORT} → https://{UPSTREAM_HOST}", flush=True)
    print(f"Log: {LOG_FILE}", flush=True)
    print(f"To use: ANTHROPIC_BASE_URL=http://127.0.0.1:{PORT} claude", flush=True)
    print("Ctrl-C to stop.", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down.", flush=True)


if __name__ == "__main__":
    main()
