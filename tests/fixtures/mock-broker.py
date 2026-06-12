#!/usr/bin/env python3
"""mock-broker.py — minimal stand-in for meeting/broker.py, for tests.

Usage: mock-broker.py --port-file PATH --log PATH

Binds 127.0.0.1 on an ephemeral port, writes the port number to --port-file,
then serves until killed:
  POST /event /question /response  -> log {"path":..., "body": <parsed json>} and reply {}
  GET  /status                     -> {"subscribers": 1}
  GET  /await                      -> {"answer": "mock"}
Each handled request appends one JSON line to --log.
"""
import argparse
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--port-file", required=True)
    ap.add_argument("--log", required=True)
    args = ap.parse_args()

    class Handler(BaseHTTPRequestHandler):
        def _reply(self, obj):
            data = json.dumps(obj).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def _log_req(self, body=None):
            with open(args.log, "a") as fh:
                fh.write(json.dumps({
                    "method": self.command,
                    "path": urlparse(self.path).path,
                    "query": urlparse(self.path).query,
                    "body": body,
                }) + "\n")

        def do_GET(self):
            path = urlparse(self.path).path
            self._log_req()
            if path == "/status":
                self._reply({"subscribers": 1})
            elif path == "/await":
                self._reply({"answer": "mock"})
            else:
                self._reply({})

        def do_POST(self):
            length = int(self.headers.get("Content-Length", 0))
            raw = self.rfile.read(length).decode() if length else ""
            try:
                body = json.loads(raw) if raw else None
            except json.JSONDecodeError:
                body = {"_unparseable": raw}
            self._log_req(body)
            self._reply({})

        def log_message(self, fmt, *a):  # silence default stderr noise
            pass

    srv = HTTPServer(("127.0.0.1", 0), Handler)
    with open(args.port_file, "w") as fh:
        fh.write(str(srv.server_address[1]))
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        sys.exit(0)


if __name__ == "__main__":
    main()
