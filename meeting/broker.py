#!/usr/bin/env python3
"""HTTP+SSE event broker for meeting-rpg IPC.
Usage: python broker.py <session-id>
Writes /tmp/meeting-rpg/<session>/broker.json → {port, pid, session}.
"""
import json, os, queue, signal, sys, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

sessions: dict = {}
_lock = threading.Lock()


def get_session(sid: str) -> dict:
    with _lock:
        if sid not in sessions:
            sessions[sid] = {"ev": threading.Event(), "answer": None, "subs": []}
        return sessions[sid]


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args): pass  # suppress access log

    def _json_body(self) -> dict:
        return json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))

    def _ok(self, data: dict = {}):
        body = json.dumps(data).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        d, sid = self._json_body(), ""
        sid = d.get("session", "")
        s = get_session(sid)
        if self.path == "/event":
            with _lock:
                [q.put(d) for q in list(s["subs"])]
            self._ok()
        elif self.path == "/question":
            with _lock:
                s["answer"] = None
                s["ev"].clear()
                [q.put({"type": "question", **d}) for q in list(s["subs"])]
            self._ok()
        elif self.path == "/response":
            with _lock:
                s["answer"] = {"id": d.get("id"), "answer": d.get("answer")}
                s["ev"].set()
            self._ok()
        else:
            self.send_error(404)

    def do_GET(self):
        p = urlparse(self.path)
        sid = (parse_qs(p.query).get("session") or [""])[0]
        s = get_session(sid)
        if p.path == "/await":
            s["ev"].wait(timeout=600)
            with _lock:
                self._ok(s["answer"] or {"id": None, "answer": None})
        elif p.path == "/status":
            with _lock:
                self._ok({"subscribers": len(s["subs"])})
        elif p.path == "/events":
            q: queue.Queue = queue.Queue()
            with _lock:
                s["subs"].append(q)
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            try:
                while True:
                    try:
                        self.wfile.write(f"data: {json.dumps(q.get(timeout=30))}\n\n".encode())
                        self.wfile.flush()
                    except queue.Empty:
                        self.wfile.write(b": heartbeat\n\n")
                        self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError):
                pass
            finally:
                with _lock:
                    s["subs"].remove(q)
        else:
            self.send_error(404)


if __name__ == "__main__":
    session_id = sys.argv[1] if len(sys.argv) > 1 else "default"
    srv = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    port = srv.server_address[1]
    disc = f"/tmp/meeting-rpg/{session_id}"
    os.makedirs(disc, exist_ok=True)
    with open(f"{disc}/broker.json", "w") as f:
        json.dump({"port": port, "pid": os.getpid(), "session": session_id}, f)
    print(f"broker port={port} session={session_id} pid={os.getpid()}", flush=True)
    signal.signal(signal.SIGTERM, lambda *_: srv.shutdown())
    srv.serve_forever()
