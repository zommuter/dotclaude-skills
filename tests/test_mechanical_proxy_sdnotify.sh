#!/usr/bin/env bash
# roadmap:4044
# Unit spec for the sd_notify/WatchdogSec addition to
# relay/scripts/mechanical-proxy.py (id:4044) — catches a hung-but-listening
# daemon that Restart=always alone can't detect.
#
# This test covers the WORKTREE-VERIFIABLE half: the standalone/no-op path.
# With $NOTIFY_SOCKET unset (no real systemd involved — the normal case for a
# direct `python3 mechanical-proxy.py` run, or this very test), every notify
# call must be a silent no-op:
#   (a) module imports/loads cleanly with the new code present;
#   (b) _sd_notify() is a no-op when NOTIFY_SOCKET is unset — no exception,
#       no socket created, no observable effect;
#   (c) _start_sd_watchdog() does not start a watchdog thread when
#       NOTIFY_SOCKET is unset;
#   (d) with NOTIFY_SOCKET SET to a real UNIX datagram socket (a controlled
#       fixture, not real systemd), _sd_notify() DOES send the expected bytes —
#       proving the guard is conditional on the env var, not a permanent no-op.
#
# The live "systemd actually restarts a wedged daemon inside WatchdogUSec" check
# is host-gated (requires real systemd --user) and is NOT this test's job — see
# ROADMAP.md id:4044's done-check, verified by the orchestrator post-merge.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODULE="$ROOT/relay/scripts/mechanical-proxy.py"

[[ -f "$MODULE" ]] || { echo "FAIL: module not found at $MODULE"; exit 1; }

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

python3 - "$MODULE" "$WORKDIR" <<'PYEOF'
import importlib.util
import os
import socket
import sys
import threading
import time

path, workdir = sys.argv[1], sys.argv[2]

def load():
    spec = importlib.util.spec_from_file_location("mechanical_proxy_sdnotify", path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m

failures = []
def check(cond, msg):
    if cond:
        print(f"PASS: {msg}")
    else:
        print(f"FAIL: {msg}")
        failures.append(msg)

# ── (a) module loads cleanly with NOTIFY_SOCKET unset (the standalone/test case) ──
os.environ.pop("NOTIFY_SOCKET", None)
mod = load()
check(hasattr(mod, "_sd_notify"), "(a) module exposes _sd_notify after loading with NOTIFY_SOCKET unset")
check(hasattr(mod, "_start_sd_watchdog"), "(a) module exposes _start_sd_watchdog")

# ── (b) _sd_notify is a no-op when NOTIFY_SOCKET is unset ──────────────────
try:
    mod._sd_notify("READY=1")
    mod._sd_notify("WATCHDOG=1")
    ok = True
except Exception as exc:
    ok = False
    print(f"  exception: {exc}")
check(ok, "(b) _sd_notify('READY=1'/'WATCHDOG=1') raises nothing when NOTIFY_SOCKET is unset")

# ── (c) _start_sd_watchdog starts NO thread when NOTIFY_SOCKET is unset ────
before = {t.name for t in threading.enumerate()}
mod._start_sd_watchdog()
time.sleep(0.05)
after = {t.name for t in threading.enumerate()}
check("sd-watchdog" not in after,
      f"(c) no 'sd-watchdog' thread started when NOTIFY_SOCKET unset (threads: {after - before})")

# ── (d) POSITIVE control: with NOTIFY_SOCKET set to a real fixture socket, ──
# _sd_notify DOES send — proving (b)/(c) are a real conditional guard, not a
# permanently-dead code path.
sock_path = os.path.join(workdir, "notify.sock")
srv = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
srv.bind(sock_path)
srv.settimeout(2)
os.environ["NOTIFY_SOCKET"] = sock_path
mod2 = load()
mod2._sd_notify("READY=1")
try:
    data, _ = srv.recvfrom(4096)
    got = data.decode()
except socket.timeout:
    got = None
check(got == "READY=1", f"(d) with NOTIFY_SOCKET set, _sd_notify sends the expected datagram (got {got!r})")
srv.close()

# Restore a clean env for anything else in-process (defensive; each test file
# runs in its own python3 subprocess anyway).
os.environ.pop("NOTIFY_SOCKET", None)

if failures:
    print(f"\n{len(failures)} assertion(s) failed")
    sys.exit(1)
print("\nALL PASS: mechanical-proxy sd_notify standalone/no-op guard + positive control (id:4044)")
PYEOF
