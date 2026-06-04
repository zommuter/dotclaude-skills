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
import socket
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


def _log(entry: dict):
    line = json.dumps(entry)
    with _log_lock:
        with open(LOG_FILE, "a") as f:
            f.write(line + "\n")
    print(line, flush=True)


def _stream_chunked(resp, wfile, buf_lines: list, is_sse: bool) -> bool:
    """
    Manually decode a chunked response and forward decoded bytes to wfile.

    fp.read1() on a live keep-alive socket never returns b"" — it blocks waiting
    for the next response. We must detect the terminating chunk (size == 0) ourselves
    and stop reading. Returns True if the body was fully consumed.
    """
    fp = resp.fp
    while True:
        # Read chunk-size line (blocks until the next event arrives — expected for SSE)
        line = fp.readline(256)
        if not line:
            return False  # unexpected EOF
        try:
            chunk_size = int(line.split(b";")[0].strip(), 16)
        except ValueError:
            return False  # malformed chunk header
        if chunk_size == 0:
            # Terminating chunk — consume any trailing headers
            while True:
                trailer = fp.readline(256)
                if trailer in (b"\r\n", b"\n", b""):
                    break
            return True  # fully consumed, clean end

        # Read chunk body in pieces (read1 returns immediately with whatever is available)
        remaining = chunk_size
        while remaining > 0:
            try:
                data = fp.read1(min(4096, remaining))
            except AttributeError:
                data = fp.read(min(256, remaining))
            if not data:
                return False  # unexpected EOF mid-chunk
            remaining -= len(data)
            wfile.write(data)
            wfile.flush()
            if is_sse:
                buf_lines.append(data)

        fp.read(2)  # consume trailing \r\n after chunk body


def _stream_plain(resp, wfile, buf_lines: list, is_sse: bool) -> bool:
    """Forward a non-chunked response. Connection close signals end-of-body."""
    fp = resp.fp
    while True:
        try:
            data = fp.read1(4096)
        except AttributeError:
            data = fp.read(256)
        if not data:
            return True
        wfile.write(data)
        wfile.flush()
        if is_sse:
            buf_lines.append(data)


class ProxyHandler(BaseHTTPRequestHandler):
    def setup(self):
        super().setup()
        # TCP_NODELAY: send each SSE chunk immediately; Nagle + delayed-ACK on loopback
        # would otherwise batch small writes and stall between events.
        self.request.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)

    def log_message(self, format, *args): pass  # silence default access log  # noqa: A002

    def _proxy(self):
        req_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(req_length) if req_length else b""

        # Build upstream headers: drop hop-by-hop, replace Host.
        # Strip Accept-Encoding: upstream would compress the response and http.client
        # doesn't auto-decompress — we'd forward opaque bytes and Claude Code would fail.
        fwd_headers = {
            k: v for k, v in self.headers.items()
            if k.lower() not in _HOP_BY_HOP and k.lower() not in ("host", "accept-encoding")
        }
        if body:
            fwd_headers["Content-Length"] = str(len(body))

        try:
            conn = http.client.HTTPSConnection(UPSTREAM_HOST, timeout=120)
            conn.request(self.command, self.path, body=body or None, headers=fwd_headers)
            resp = conn.getresponse()
        except Exception as exc:
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
        is_chunked = bool(resp.chunked)

        buf_lines: list[bytes] = []
        fully_consumed = False
        try:
            if is_chunked:
                fully_consumed = _stream_chunked(resp, self.wfile, buf_lines, is_sse)
            else:
                fully_consumed = _stream_plain(resp, self.wfile, buf_lines, is_sse)
        except (BrokenPipeError, ConnectionResetError):
            pass
        finally:
            conn.close()

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
            "is_chunked": is_chunked,
            "fully_consumed": fully_consumed,
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
