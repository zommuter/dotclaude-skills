#!/usr/bin/env python3
"""Global HTTP+SSE event broker for meeting-rpg IPC.
Binds to MEETING_BROKER_PORT (default 64109). On bind-fail, probes /status to
discriminate our-daemon (already running → exit 0) from stranger (→ ephemeral fallback).
Writes /tmp/meeting-rpg/broker.json → {port, pid}.
Idle self-shutdown after MEETING_BROKER_IDLE seconds (default 300; 0 = never).
"""
import json, os, queue, signal, sys, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse
from urllib.request import urlopen

BROKER_DIR = "/tmp/meeting-rpg"
BROKER_JSON = f"{BROKER_DIR}/broker.json"
PORT = int(os.environ.get("MEETING_BROKER_PORT", 64109))
IDLE_TIMEOUT = int(os.environ.get("MEETING_BROKER_IDLE", 300))

sessions: dict = {}
_lock = threading.Lock()
_last_activity = [time.monotonic()]


def _touch():
    _last_activity[0] = time.monotonic()


def get_session(sid: str) -> dict:
    with _lock:
        if sid not in sessions:
            sessions[sid] = {"ev": threading.Event(), "answer": None, "subs": []}
        return sessions[sid]


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args): pass

    def _json_body(self) -> dict:
        return json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))

    def _ok(self, data: dict = {}):
        body = json.dumps(data).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_POST(self):
        d = self._json_body()
        sid = d.get("session", "")
        s = get_session(sid)
        _touch()
        if self.path == "/event":
            with _lock:
                targets = list(s["subs"])
                if sid != "live":
                    targets += list((sessions.get("live") or {}).get("subs", []))
                [q.put(d) for q in targets]
            self._ok()
        elif self.path == "/question":
            with _lock:
                s["answer"] = None
                s["ev"].clear()
                targets = list(s["subs"])
                if sid != "live":
                    targets += list((sessions.get("live") or {}).get("subs", []))
                [q.put({"type": "question", **d}) for q in targets]
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
        _touch()
        if p.path == "/await":
            s["ev"].wait(timeout=600)
            with _lock:
                ans = s["answer"] or {"id": None, "answer": None}
            self._ok(ans)
        elif p.path == "/status":
            with _lock:
                subs = len(s["subs"])
                if sid != "live":
                    subs += len((sessions.get("live") or {}).get("subs", []))
            self._ok({"subscribers": subs})
        elif p.path == "/events":
            q: queue.Queue = queue.Queue()
            with _lock:
                s["subs"].append(q)
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Access-Control-Allow-Origin", "*")
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


def _our_broker_running(port: int) -> bool:
    """Return True if port responds to /status like our broker."""
    try:
        with urlopen(f"http://127.0.0.1:{port}/status", timeout=1) as r:
            data = json.loads(r.read())
            return "subscribers" in data
    except Exception:
        return False


if __name__ == "__main__":
    try:
        srv = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
        actual_port = PORT
    except OSError:
        if _our_broker_running(PORT):
            print(f"broker already running on port={PORT}", flush=True)
            sys.exit(0)
        # Stranger owns PORT → fall back to ephemeral
        srv = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        actual_port = srv.server_address[1]

    os.makedirs(BROKER_DIR, exist_ok=True)
    with open(BROKER_JSON, "w") as f:
        json.dump({"port": actual_port, "pid": os.getpid()}, f)
    print(f"broker port={actual_port} pid={os.getpid()}", flush=True)

    def _shutdown(*_):
        srv.shutdown()

    signal.signal(signal.SIGTERM, _shutdown)

    if IDLE_TIMEOUT > 0:
        def _idle_watcher():
            while True:
                time.sleep(min(IDLE_TIMEOUT, 30))
                with _lock:
                    has_subs = any(s["subs"] for s in sessions.values())
                if not has_subs and time.monotonic() - _last_activity[0] > IDLE_TIMEOUT:
                    srv.shutdown()
                    break
        threading.Thread(target=_idle_watcher, daemon=True).start()

    srv.serve_forever()
