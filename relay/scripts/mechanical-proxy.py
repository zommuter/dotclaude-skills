#!/usr/bin/env python3
"""
Mechanical-dispatch proxy — the "fake-Haiku" short-circuit (id:176f).

A local plain-HTTP gateway on loopback (reached over plain http via
ANTHROPIC_BASE_URL=http://127.0.0.1:PORT — a zelegator check confirmed the base-URL
override is honoured over plain http; no inbound TLS handling, the real API's own
TLS is used only on the outbound pass-through leg). It fronts ANTHROPIC_BASE_URL for
BOTH relay execution substrates that share the host harness's single global
ANTHROPIC_BASE_URL: the off-Workflow host driver (id:93fe) AND the in-Workflow pool
itself (the Workflow's agent() traffic also transits that same global base URL). The
pool is a prime consumer: a measured ~30-min pool spent only ~12 min on productive
LLM work — the mechanical per-round hops are the waste this removes.
It inspects each Messages-API request:

  * model == "bash"  -> the explicit mechanical trigger (owner 2026-07-19). The
      caller declares, by construction, that this "turn" is a single Bash step.
      The proxy reads the shell command from the request (the echo-runner-shaped
      user content), runs it locally, and builds a valid Anthropic Messages
      response (SSE or non-streaming) whose assistant turn carries the command's
      stdout verbatim. No request is made to the real upstream for this class.
  * anything else    -> relayed to the real upstream unchanged (the e905
      validated transport path — meeting/contrib/llm-proxy.py).

Fail-open: if a request is not clearly a model=="bash" mechanical request (JSON
parse error, missing/empty command, unexpected shape) it is relayed to the real
model. The proxy never fabricates a turn it is unsure about — a false positive
would fabricate an unreviewed "success" with zero reasoning, worse than an LLM
mistake (id:176f risk #1). The explicit model=="bash" opt-in is what removes that
risk: the caller, not a heuristic, declares mechanical-ness.

ToS posture (one-line check, id:176f): for the intercepted class this proxy makes
zero real model calls — it declines to send a request and answers locally. That is
a materially different posture from vendor-substitution (routing a Claude request
to a different vendor's inference), which is the reason the earlier llama-proxy was
killed. Declining-to-send is not re-using someone else's inference; it sends nothing.

Security:
  * binds 127.0.0.1 only (never a routable interface)
  * opt-in only: nothing uses it unless ANTHROPIC_BASE_URL points here; never a
    global default path
  * relayed requests are forwarded to the real upstream unaltered; the proxy adds
    nothing and inspects nothing beyond the model field, and originates its own
    upstream TLS
  * the local subprocess runs with the driver's own privileges — front this proxy
    only with a driver whose traffic you trust (the relay-svc / os-users tier is
    the relevant containment; this proxy adds no sandbox of its own)

Transport helpers (_stream_chunked / _stream_plain / hop-by-hop handling /
TCP_NODELAY / Accept-Encoding strip) are adapted from the validated e905 spike
(meeting/contrib/llm-proxy.py) — the unbuffered-SSE pass-through that a real Claude
Code turn was confirmed to complete over.

Usage:
  python3 relay/scripts/mechanical-proxy.py
  # then, for the off-Workflow driver:
  ANTHROPIC_BASE_URL=http://127.0.0.1:61843 <driver that dispatches model:"bash" units>

Env vars:
  MECH_PROXY_PORT             (default 61843)      local bind port
  MECH_PROXY_LOG              (default /tmp/mechanical-proxy.log)
  MECH_PROXY_UPSTREAM_HOST    (default api.anthropic.com)
  MECH_PROXY_UPSTREAM_PORT    (default 443)
  MECH_PROXY_UPSTREAM_SCHEME  (default https; set http for a local mock upstream)
  MECH_PROXY_SHELL            (default /bin/sh)    interpreter for the mechanical command
  MECH_PROXY_TIMEOUT          (default 120)        seconds before a mechanical command is killed
  MECH_PROXY_STATE            (default ~/.config/relay/mech-proxy-state.json)
                              startup state file published for the currency check (id:9e48):
                              {pid, started_at, allowlist_digest} — see mech-currency.sh
"""
import datetime
import hashlib
import http.client
import json
import os
import re
import secrets
import shlex
import socket
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("MECH_PROXY_PORT", 61843))
WATCHDOG_INTERVAL_SEC = float(os.environ.get("MECH_PROXY_WATCHDOG_INTERVAL", 10))
LOG_FILE = os.environ.get("MECH_PROXY_LOG", "/tmp/mechanical-proxy.log")
UPSTREAM_HOST = os.environ.get("MECH_PROXY_UPSTREAM_HOST", "api.anthropic.com")
UPSTREAM_PORT = int(os.environ.get("MECH_PROXY_UPSTREAM_PORT", 443))
UPSTREAM_SCHEME = os.environ.get("MECH_PROXY_UPSTREAM_SCHEME", "https")
MECH_SHELL = os.environ.get("MECH_PROXY_SHELL", "/bin/sh")
MECH_TIMEOUT = int(os.environ.get("MECH_PROXY_TIMEOUT", 120))

# The ONE real directory an allowlisted relay script may live in. The gate pins a
# candidate leader to this root by filesystem IDENTITY (realpath), never by
# basename — so a look-alike path ending in `relay/scripts/<name>` under an
# attacker-controlled directory (e.g. /tmp/x/relay/scripts/claim.sh) does NOT
# match and is refused (→ fail-open passthrough). Defaults to the real per-file
# symlink install; MECHANICAL_PROXY_RELAY_ROOT overrides it for hermetic tests.
CANONICAL_RELAY_SCRIPTS_ROOT = os.path.realpath(os.path.expanduser(
    os.environ.get("MECHANICAL_PROXY_RELAY_ROOT",
                   "~/.claude/skills/relay/scripts")))

# The explicit mechanical-dispatch trigger. The caller declares mechanical-ness by
# passing this as the request's `model` — no detection heuristic, no fail-open guess.
MECH_MODEL = "bash"

# Opt-in shape-debug (id:94b8): when set, log the raw last-user text of a model=="bash"
# request that FAILED the extract/allowlist gate, so the harness's REAL agent() wrapper can be
# inspected in one capture run. OFF by default — it logs request content; enable only for a
# deliberate capture (MECH_PROXY_DEBUG_SHAPE=1).
DEBUG_SHAPE = bool(os.environ.get("MECH_PROXY_DEBUG_SHAPE"))

# Hop-by-hop headers we must not forward (RFC 7230 §6.1) — from the e905 spike.
_HOP_BY_HOP = frozenset([
    "connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
    "te", "trailers", "transfer-encoding", "upgrade",
])

# ── systemd sd_notify (id:4044) ─────────────────────────────────────────────
# Stdlib-only sd_notify: talk directly to $NOTIFY_SOCKET via a UNIX datagram
# socket (no `python-systemd` dependency, which isn't a stdlib package). Guarded
# on NOTIFY_SOCKET being set at all — when the daemon is NOT run under systemd
# (standalone invocation, the test suite, a plain `python3 mechanical-proxy.py`)
# NOTIFY_SOCKET is unset and every call below is a silent, side-effect-free
# no-op, so behavior is unchanged from before this feature existed.
def _sd_notify(state: str) -> None:
    """Send one sd_notify datagram (e.g. 'READY=1', 'WATCHDOG=1') to the
    systemd-provided notification socket. No-op if NOTIFY_SOCKET is unset, the
    socket can't be reached, or the send fails for any reason — sd_notify is
    fire-and-forget by design and must never crash or block the caller."""
    addr = os.environ.get("NOTIFY_SOCKET")
    if not addr:
        return
    # systemd's abstract-namespace convention: a leading '@' maps to a NUL byte.
    if addr.startswith("@"):
        addr = "\0" + addr[1:]
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
        try:
            sock.sendto(state.encode("utf-8"), addr)
        finally:
            sock.close()
    except Exception:
        pass  # sd_notify is best-effort; never let a notify failure affect the daemon


def _sd_watchdog_loop(interval: float, stop_event: threading.Event) -> None:
    """Daemon-thread loop: emit WATCHDOG=1 every `interval` seconds until
    `stop_event` is set. No-op (never even sleeps meaningfully long) when
    NOTIFY_SOCKET is unset — the caller only starts this thread when it is,
    but _sd_notify's own guard makes the loop harmless either way."""
    while not stop_event.wait(interval):
        _sd_notify("WATCHDOG=1")


def _start_sd_watchdog() -> None:
    """Start the periodic WATCHDOG=1 heartbeat iff NOTIFY_SOCKET is set (i.e.
    we are actually running under systemd with a watchdog configured). A
    standalone run never starts this thread at all."""
    if not os.environ.get("NOTIFY_SOCKET"):
        return
    thread = threading.Thread(
        target=_sd_watchdog_loop,
        args=(WATCHDOG_INTERVAL_SEC, threading.Event()),
        daemon=True,
        name="sd-watchdog",
    )
    thread.start()


_log_lock = threading.Lock()


def _log(entry: dict):
    line = json.dumps(entry)
    with _log_lock:
        with open(LOG_FILE, "a") as f:
            f.write(line + "\n")
    print(line, flush=True)


# ── Mechanical interception ─────────────────────────────────────────────────
def _last_user_text(obj: dict):
    """Read the text of the last user message (the echo-runner-shaped command).

    Content may be a bare string or a list of content blocks; concatenate text
    blocks. Returns the stripped command, or None if none is extractable
    (→ fail-open passthrough)."""
    messages = obj.get("messages")
    if not isinstance(messages, list):
        return None
    for msg in reversed(messages):
        if not isinstance(msg, dict) or msg.get("role") != "user":
            continue
        content = msg.get("content")
        if isinstance(content, str):
            text = content
        elif isinstance(content, list):
            parts = []
            for block in content:
                if isinstance(block, dict) and block.get("type") == "text":
                    parts.append(block.get("text", ""))
                elif isinstance(block, str):
                    parts.append(block)
            text = "\n".join(parts)
        else:
            return None
        text = (text or "").strip()
        return text or None
    return None


# Mechanical-command envelope (id:94b8 probe, 2026-07-21): a REAL Workflow agent() wraps the
# task in subagent scaffolding, so the raw last-user message is prose — not a bare command.
# The old "the whole last-user message IS the command" assumption therefore fell open on every
# real agent() call (the probe saw model=="bash" forwarded upstream → 404, never intercepted;
# test_mechanical_proxy.sh passed only because it hand-fed a bare-command shape). The emitter
# (relay-loop.js, deterministic) delimits the command in an explicit fenced block the proxy
# extracts, robust to any surrounding wrapper:
#     ```relay-mech
#     <one allowlisted relay command or pipeline>
#     ```
# No fence → the whole text is treated as the command (the bare-command shape a direct caller
# or the unit test sends). _command_allowed() still gates the result in BOTH cases, so wrapper
# prose that merely mentions a relay path — but carries no fence — fails open (never run).
_MECH_FENCE_RE = re.compile(r"```relay-mech[ \t]*\r?\n(.*?)\r?\n```", re.DOTALL | re.IGNORECASE)

# id:33b2 — the DATA-plane fence, separate from the ```relay-mech COMMAND fence above.
# A ```relay-mech-stdin block carries a payload that is piped to the child process's
# STDIN and is NEVER handed to the shell (see _run_mechanical's `input=`). This is what
# unblocks the hops whose payload embeds arbitrary repo/item prose (heredoc, JSON, `$(…)`,
# newlines) that _command_allowed() must otherwise refuse: the command stays a single
# bare allowlisted script invocation, while its DATA arrives out-of-band on stdin.
#
# The two fences are disjoint by construction: the COMMAND regex above requires
# `[ \t]*\r?\n` immediately after `relay-mech`, so it never matches the `-stdin` opener;
# this regex requires the literal `-stdin` suffix, so it never matches a plain command
# fence. A request may carry the command fence alone (legacy path, no stdin) or both.
_MECH_STDIN_FENCE_RE = re.compile(
    r"```relay-mech-stdin[ \t]*\r?\n(.*?)\r?\n```", re.DOTALL | re.IGNORECASE)


def _command_from_wrapped(text: str):
    """Pull the mechanical command out of a (possibly wrapper-framed) user message.

    Returns the body of the first ```relay-mech fenced block when present; otherwise
    returns `text` unchanged (the bare-command shape). Never runs anything itself —
    _command_allowed() remains the gate on whatever this returns."""
    m = _MECH_FENCE_RE.search(text)
    if m:
        return m.group(1).strip() or None
    return text


def extract_stdin_payload(text: str):
    """Return the BYTE-IDENTICAL payload of the first ```relay-mech-stdin fenced block,
    or None when no such fence is present.

    The payload is inert DATA destined for a child process's stdin, so — unlike a
    command — it is NEVER stripped: leading/trailing whitespace, embedded backticks,
    `$(…)`, `;`, `&&` and newlines must reach the script exactly as authored. The
    regex's capture already excludes only the single newline after the opener and the
    single newline before the closing fence; everything between is returned verbatim."""
    m = _MECH_STDIN_FENCE_RE.search(text)
    if m:
        return m.group(1)
    return None


def _extract_mechanical_command(body: bytes):
    """Return the shell command iff this is a clear model=="bash" mechanical request.

    Returns None for every non-mechanical or ambiguous request — the fail-open
    contract: parse error, wrong model, or no extractable command all relay to the
    real upstream rather than fabricate a turn."""
    try:
        obj = json.loads(body)
    except Exception:
        return None
    if not isinstance(obj, dict):
        return None
    if obj.get("model") != MECH_MODEL:
        return None
    text = _last_user_text(obj)
    if text is None:
        return None
    return _command_from_wrapped(text)


# ── Relay-command allowlist ─────────────────────────────────────────────────
# The only commands the gateway will run locally are the fixed set of relay
# scaffolding scripts under relay/scripts/. This list is derived from the
# mechanical command invocations in relay-loop.js (grep 'skills/relay/scripts/')
# — the read/atomic-op scripts a mechanical (echo-runner / model:"bash") unit
# actually calls. Extend it by adding a basename here; keep it auditable.
ALLOWED_RELAY_SCRIPTS = frozenset([
    "classify-repo.sh", "classify-verdict.sh",
    "claim.sh", "inject.sh",
    "discover-sig.sh", "discover-repo.sh", "discover-repos.sh",
    "discover-chunk.sh",  # id:24ec — the mechanized discover-run SHARD wrapper (echo <chunk> | discover-chunk.sh)
    "discover-prelude.sh",  # id:86a2 — the mechanized discover-PRELUDE wrapper; missing here would 404 the prelude's model:'bash' dispatch (wave-1 gap caught by 24ec review)
    "reconcile-repo.sh", "relay-reconcile.sh",
    "stop-sentinel.sh", "file-surface-decisions.sh",
    "relay-status-publish.sh", "relay-state-write.sh", "relay-intensity.sh",
    "heartbeat.sh", "sync-origin.sh", "clean-tree-gate.sh",
    "verify-isolation.sh", "gather-repo-state.sh",
    "ckpt-tag.sh", "quota-stop.sh",
    "worktree-retire.sh",  # id:4df8/1f8e — the force-free context-death retirement wrapper; missing here 404s retireDeadWorktree()'s model:'bash' dispatch (id:5bbb completeness-test gap, observed live run relay-20260729-142725-13077)
    "provision-worktree.sh",  # id:34b7 — pre-dispatch parent-side worktree creation + gitignored-artifact provisioning; missing here 404s provisionWorktree()'s model:'bash' dispatch
])


# ── Startup state publication / currency (id:9e48) ──────────────────────────
# Python binds ALLOWED_RELAY_SCRIPTS at IMPORT time and this module has no reload
# path, so a long-running proxy keeps whatever set was on disk when it started. On
# 2026-08-11 a proxy started 13:32 held a frozenset predating the 19:22 commit that
# added provision-worktree.sh: every provision hop was refused → fail-open
# passthrough → 404 on model "bash". Every existing guard read SOURCE (the fence
# completeness test), or connected a TCP socket (probe-mech-proxy.sh), or mapped a
# mode to a token (mech-preflight.sh) — none could observe the LIVE process's
# in-memory set, so all three reported healthy for the whole incident.
#
# The fix is to publish what THIS process actually loaded, so an outside checker can
# compare it against the current source: at startup we write {pid, started_at,
# allowlist_digest} to MECH_PROXY_STATE. mech-currency.sh recomputes the digest by
# importing this module (calling allowlist_digest() below — deliberately ONE
# implementation of the predicate; a second one would drift and re-open this class
# of bug) and reports STALE on a mismatch, a dead pid, or NO state file at all.
#
# ABSENCE MUST READ AS STALE, never healthy: the exact process this detects predates
# the feature and therefore wrote no state file — fail-closed on the unknown.
STATE_FILE = os.path.expanduser(
    os.environ.get("MECH_PROXY_STATE", "~/.config/relay/mech-proxy-state.json"))


def allowlist_digest() -> str:
    """Stable hash of the allowlist THIS module holds.

    Over the SORTED entries, so set iteration order (which varies per process) can
    never make two identical allowlists look different. Pure and side-effect-free:
    the checker imports this module solely to call it, and importing must never
    touch the state file it is about to inspect.
    """
    joined = "\n".join(sorted(ALLOWED_RELAY_SCRIPTS))
    return hashlib.sha256(joined.encode("utf-8")).hexdigest()


def write_state_file(path: str = None) -> str:
    """Publish {pid, started_at, allowlist_digest} for the currency check.

    Best-effort: a proxy that cannot write its state file still serves traffic (the
    checker then reports STALE, which is the correct fail-closed reading of "I cannot
    tell what this process loaded"). Called from main() ONLY — never at import.
    """
    path = path or STATE_FILE
    state = {
        "pid": os.getpid(),
        "started_at": datetime.datetime.now().replace(microsecond=0).isoformat(),
        "allowlist_digest": allowlist_digest(),
        "allowlist_count": len(ALLOWED_RELAY_SCRIPTS),
        "port": PORT,
    }
    try:
        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
        tmp = path + ".tmp"
        with open(tmp, "w") as fh:
            json.dump(state, fh, indent=2)
            fh.write("\n")
        os.replace(tmp, path)  # atomic — a reader never sees a half-written file
    except OSError as exc:
        print(f"mechanical proxy: WARNING — could not write state file {path}: {exc}",
              flush=True)
    return path

# id:33b2 / id:a05c option B — the OPT-IN stdin channel allowlist. A ```relay-mech-stdin
# fence (a payload piped to a child's stdin) is honoured ONLY when the command's pinned
# last-stage script is an EXPLICIT member of this set. It is a SEPARATE, hand-maintained
# frozenset — deliberately NOT derived from, defaulted to, or aliased to
# ALLOWED_RELAY_SCRIPTS. Option A (every allowlisted script inherits stdin) was rejected by
# the owner (2026-07-28): admitting a script to the DATA plane must stay a deliberate,
# reviewable act, never a property a future ALLOWED_RELAY_SCRIPTS addition silently inherits.
# A change that makes this default to / alias / derive from ALLOWED_RELAY_SCRIPTS is a
# ruling violation, not an optimization.
#
# STANDING OBLIGATION for every member below: the script MUST treat its stdin as INERT
# DATA — never `eval` it, `source` it, or shell-interpolate it. The proxy's command scanner
# cannot see what a member does with the bytes it receives; this comment is the only place a
# future author admitting a script here will meet that hazard. Admit a script only after
# confirming it consumes stdin as opaque data (e.g. `cat`, a `--path -` reader, `python -`
# that json.loads it), never as code.
STDIN_ALLOWED_SCRIPTS = frozenset([
    "relay-status-publish.sh",  # write-relay-status (id:d4ca) moves a markdown doc as its payload
])

# Plumbing tokens permitted as a NON-leading pipeline stage (e.g. `echo {json} |
# discover-sig.sh`). A command still has to contain at least one allowlisted relay
# script; these alone are never enough to run locally.
_SAFE_PLUMBING = frozenset(["echo", "printf", "cat", "true", "false", ":", "test", "["])

# Shell separators we split a command on to inspect each simple command in turn.
_SEG_SPLIT_RE = re.compile(r"\|\||&&|[|;\n&]")


def _segment_leader(segment: str):
    """Return the leading executable token of one simple command, skipping leading
    VAR=val assignments and an optional sh/bash '-c' interpreter wrapper. Returns
    None if the segment can't be tokenised (→ treated as not-allowed → fail-open)."""
    try:
        toks = shlex.split(segment)
    except ValueError:
        return None
    i = 0
    while i < len(toks) and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", toks[i]):
        i += 1  # skip environment assignments
    if i < len(toks) and os.path.basename(toks[i]) in ("sh", "bash", "/bin/sh", "/bin/bash"):
        i += 1
        while i < len(toks) and toks[i].startswith("-"):  # skip -c and friends
            i += 1
    return toks[i] if i < len(toks) else None


def _token_is_relay_script(tok: str):
    """Return the basename iff `tok` resolves, by filesystem IDENTITY, to an
    allowlisted script living DIRECTLY under the pinned canonical root — else None.

    The old check matched any path *ending* in `relay/scripts/<allowlisted-name>`
    by basename, so `sh /tmp/x/relay/scripts/claim.sh` ran an attacker's file. Now
    the leader is realpath-resolved and required to equal
    `realpath(CANONICAL_RELAY_SCRIPTS_ROOT/<name>)`. Both sides are realpath'd so
    the per-file symlink install (~/.claude/skills/relay/scripts/foo.sh →
    ~/src/dotclaude-skills/relay/scripts/foo.sh) still resolves to the same real
    file, while a look-alike path under any other directory does not. The file
    must also exist; a name not resolving here → None → not allowed → fail-open."""
    if "/" not in tok:
        return None  # bare name, never a path to a pinned script
    real = os.path.realpath(os.path.expanduser(tok))
    name = os.path.basename(real)
    if name not in ALLOWED_RELAY_SCRIPTS:
        return None
    expected = os.path.realpath(os.path.join(CANONICAL_RELAY_SCRIPTS_ROOT, name))
    if real != expected:
        return None  # correct basename but NOT the pinned canonical file
    if not os.path.isfile(real):
        return None  # pinned path but no such file present
    return name


def _has_unquoted_sequence_operator(command: str) -> bool:
    """True if `command` carries an unquoted sequential/background/logical-or
    operator OUTSIDE quotes: `;`, a newline, `&` (catches both a background `&`
    and `&&`), or `||`. These operators concatenate the STDOUT of independent
    commands (id:f9cd) — `cat ~/.claude/.credentials.json ; claim.sh peek` passes
    the old per-segment leader check (cat=plumbing, claim.sh=pinned relay, >=1
    relay present) and the proxy then returns the credential file's contents
    verbatim in the model:"bash" reply. A single `|` (pipeline) is NOT refused
    here — only the LAST pipeline stage's stdout is ever returned, and
    _command_allowed() separately requires that last stage to be a pinned relay
    script. Quote-aware and modelled on _has_unquoted_redirection: a `;`/`&`/`|`
    byte inside a quoted argument is not mistaken for an operator."""
    quote = None
    i = 0
    n = len(command)
    while i < n:
        c = command[i]
        if quote is not None:
            if c == quote:
                quote = None
        elif c in ("'", '"'):
            quote = c
        elif c == "\\":
            i += 1  # skip the escaped byte
        elif c in (";", "\n", "&"):
            return True
        elif c == "|" and i + 1 < n and command[i + 1] == "|":
            return True  # `||` — logical-or, not a single pipe
        i += 1
    return False


def _has_unquoted_redirection(command: str) -> bool:
    """True if `command` carries an unquoted redirection operator (`>`, `<`, `>>`,
    `2>`, `&>`, …). A mechanical relay hop never redirects; refusing here stops an
    output-clobber such as `heartbeat.sh >> ~/.ssh/authorized_keys` from writing
    the script's stdout to an attacker path. Quote-aware so a `<`/`>` byte inside a
    quoted JSON argument is not mistaken for redirection (that case just fails open
    anyway). Also catches the `<` of process substitution as a backstop."""
    quote = None
    i = 0
    while i < len(command):
        c = command[i]
        if quote is not None:
            if c == quote:
                quote = None
        elif c in ("'", '"'):
            quote = c
        elif c == "\\":
            i += 1  # skip the escaped byte
        elif c in ("<", ">"):
            return True
        i += 1
    return False


def _command_allowed(command: str) -> bool:
    """True iff `command` is a SINGLE PIPELINE (no `;`/`&`/`&&`/`||`/newline —
    see _has_unquoted_sequence_operator) whose stages each lead with either a safe
    plumbing token or an allowlisted relay script, AND whose LAST stage leads with
    an allowlisted relay script. Anything else — a sequential/background/logical-or
    operator, an unrecognised leading command, an unknown relay script, an
    unparseable segment, a command substitution, or a pipeline that doesn't END in
    a pinned relay script — returns False, and the caller then relays the request
    to the real model (fail-open).

    The last-stage requirement is the id:f9cd hardening: the proxy always returns
    only the FINAL pipeline stage's stdout (a shell pipeline's stdout is whatever
    the last stage writes), so pinning the last stage to a relay script guarantees
    the returned text is always that script's own output — never a plumbing
    command (`cat`, `echo`, …) reading an arbitrary/secret file. Combined with the
    sequence-operator refusal above (which would otherwise let independent
    commands' stdouts be concatenated), a mechanical hop can never surface
    anything but a pinned relay script's own stdout."""
    if not command or not command.strip():
        return False
    # Sequential/background/logical-or operators let independent commands' stdout
    # be concatenated in the reply (the id:f9cd exfil: `cat <secret> ; claim.sh
    # peek` — both leaders pass the per-segment check below in isolation). Refuse
    # before any further parsing so nothing downstream can smuggle one back in.
    if _has_unquoted_sequence_operator(command):
        return False
    # Command substitution is never part of a mechanical relay hop; refuse it so a
    # nested command can't smuggle in around the per-segment leader check. Process
    # substitution `<(...)` / `>(...)` is the same hazard under bash (MECH_SHELL is
    # bash on this host even as /bin/sh), so refuse those markers too.
    if "$(" in command or "`" in command or "<(" in command or ">(" in command:
        return False
    # A mechanical hop also never redirects; any unquoted redirection operator
    # (>, <, >>, 2>, &>) could clobber/read an attacker path, so refuse the command.
    if _has_unquoted_redirection(command):
        return False
    segments = [seg for seg in _SEG_SPLIT_RE.split(command) if seg.strip()]
    if not segments:
        return False
    saw_relay_script = False
    last_is_relay_script = False
    last_idx = len(segments) - 1
    for idx, segment in enumerate(segments):
        leader = _segment_leader(segment)
        if leader is None:
            return False
        name = _token_is_relay_script(leader)
        if name is not None:
            if name not in ALLOWED_RELAY_SCRIPTS:
                return False  # a relay-scripts path that isn't on the allowlist
            saw_relay_script = True
            if idx == last_idx:
                last_is_relay_script = True
        elif leader not in _SAFE_PLUMBING:
            return False  # a leading command that is neither plumbing nor a relay script
    return saw_relay_script and last_is_relay_script


def _last_stage_relay_script(command: str):
    """Return the basename of the pinned relay script leading the LAST pipeline stage
    of `command`, or None. Mirrors _command_allowed()'s last-stage identification so the
    stdin opt-in gate keys off exactly the script whose stdout the proxy would return —
    the one that will actually receive the piped payload on its stdin. Callers must have
    already established `_command_allowed(command) is True`; this only names the script."""
    segments = [seg for seg in _SEG_SPLIT_RE.split(command) if seg.strip()]
    if not segments:
        return None
    leader = _segment_leader(segments[-1])
    if leader is None:
        return None
    return _token_is_relay_script(leader)


def _mechanical_command(body: bytes):
    """Combined gate: return the command to run locally iff the request is a clear
    model=="bash" mechanical request AND its command is an allowlisted relay
    invocation. Returns None otherwise (fail-open → relay to the real model)."""
    command = _extract_mechanical_command(body)
    if command is None:
        return None          # not a model=="bash" mechanical request at all — nothing to say
    if not _command_allowed(command):
        # id:5552 — LOUD refusal (no-silent-swallow, id:4347). Before this, a REFUSED
        # mechanical command and a request that was never mechanical collapsed into the same
        # silent None, so the refusal was indistinguishable from a broken model: the request
        # fell through to the real API, which has no "bash" model, and the hop died with
        # "There's an issue with the selected model (bash)". That is how the chain-end
        # classifier re-ask could be 100% dead for EVERY repo without anyone noticing — twice
        # over, since id:8123 replaced id:cc90's depth-K trigger precisely because that one
        # "could not have worked", and the replacement never fired either (loderite run
        # relay-20260731-221039-22914; routed:c555). One log line makes this class
        # self-diagnosing: the refused command is named, so the missing allowlist entry or the
        # offending pipeline stage is immediate rather than a run-costing mystery.
        _log({"event": "mechanical_refused", "command": command,
              "reason": "command not allowed by _command_allowed (see _SAFE_PLUMBING / "
                        "relay-script allowlist); falling open to the real API, which will "
                        "404 on model=\"bash\""})
        return None
    return command


def _extract_mechanical_stdin(body: bytes):
    """Return the byte-identical ```relay-mech-stdin payload for a model=="bash" request,
    or None (no fence present, or the request is not a mechanical one at all). Mirrors
    _extract_mechanical_command's parse/guard shape; never strips the payload."""
    try:
        obj = json.loads(body)
    except Exception:
        return None
    if not isinstance(obj, dict) or obj.get("model") != MECH_MODEL:
        return None
    text = _last_user_text(obj)
    if text is None:
        return None
    return extract_stdin_payload(text)


def _mechanical_dispatch(body: bytes):
    """Full interception decision INCLUDING the opt-in stdin channel (id:33b2).

    Returns a `(command, stdin_payload)` tuple to run locally, or None to fall open to
    the real upstream. `stdin_payload` is None for the legacy no-stdin path — the byte-
    identical behaviour from before this channel existed — and a str only when a
    ```relay-mech-stdin fence is present AND the command's pinned script is admitted to
    STDIN_ALLOWED_SCRIPTS.

    The gate is AND, not OR: `_command_allowed()` still governs the command fence exactly
    as before (via _mechanical_command), and the stdin opt-in is an ADDITIONAL narrowing
    layered on top — never a way to run something the command gate would have refused."""
    command = _mechanical_command(body)
    if command is None:
        return None                      # not mechanical, or command not allowed — fail open
    stdin_payload = _extract_mechanical_stdin(body)
    if stdin_payload is None:
        return (command, None)           # legacy path — byte-identical to pre-id:33b2
    # A ```relay-mech-stdin fence is present. Option B (id:a05c): honour it ONLY when the
    # command's pinned last-stage script is an EXPLICIT member of STDIN_ALLOWED_SCRIPTS —
    # a separate set from ALLOWED_RELAY_SCRIPTS. Not admitted → refuse (fail open), never
    # silently run; the whole point is that admission is deliberate, not inherited.
    pinned = _last_stage_relay_script(command)
    if pinned not in STDIN_ALLOWED_SCRIPTS:
        _log({"event": "mechanical_stdin_refused", "command": command, "pinned": pinned,
              "reason": "```relay-mech-stdin fence for a script not in STDIN_ALLOWED_SCRIPTS "
                        "(opt-in DATA-plane admission, id:a05c option B); falling open to the "
                        "real API, which will 404 on model=\"bash\""})
        return None
    return (command, stdin_payload)


def _run_mechanical(command: str, stdin: str = None) -> str:
    """Run the command locally and return the echo-runner-shaped payload.

    Success (non-empty stdout) -> stdout verbatim (UNCHANGED — hops that parse
                stdout, e.g. classify verdicts, inject-take JSON, discover
                output, must see exactly what the script printed).
    Success (empty/whitespace-only stdout) -> the sentinel 'MECH-OK exit=0\\n'.
                A real empty string here reads to the model:"bash" agent
                harness as an empty completion, which it treats as a
                retryable failure and re-dispatches forever — wedging silent
                mechanical hops (quota-stop.sh proceed verdict, heartbeat.sh
                beat, claim.sh release, inject.sh take with nothing pending).
                id:3557, observed live 2026-07-23 (run relay-20260723-141926-10371).
    Failure  -> 'MECH-ERROR exit=<code>' + newline + stderr verbatim (mirrors the
                echo-runner agent contract exactly).

    `stdin` (id:33b2): when a ```relay-mech-stdin payload is supplied it is fed to the
    child on its stdin as INERT DATA and never handed to the shell — the command line is
    only ever `[MECH_SHELL, '-c', command]`, so the payload cannot be word-split, expanded,
    or command-substituted. When stdin is None the call is byte-identical to before this
    channel existed (`input=None` leaves the child's stdin inherited, exactly as before)."""
    try:
        proc = subprocess.run(
            [MECH_SHELL, "-c", command],
            input=stdin,
            capture_output=True, text=True, timeout=MECH_TIMEOUT,
        )
    except subprocess.TimeoutExpired:
        return f"MECH-ERROR exit=124\ncommand timed out after {MECH_TIMEOUT}s"
    if proc.returncode == 0:
        if proc.stdout.strip() == "":
            return "MECH-OK exit=0\n"
        return proc.stdout
    return f"MECH-ERROR exit={proc.returncode}\n{proc.stderr}"


# ── Synthetic Anthropic Messages responses ──────────────────────────────────
def _sse_event(event_type: str, data: dict) -> bytes:
    return (
        f"event: {event_type}\r\n"
        f"data: {json.dumps(data)}\r\n\r\n"
    ).encode("utf-8")


def _serve_mechanical_sse(handler, text: str, model: str):
    """Emit a minimal but valid Messages streaming (SSE) turn carrying `text`."""
    msg_id = "msg_mech_" + secrets.token_hex(12)
    # A rough token estimate keeps the usage block plausible; it is display-only.
    out_tokens = max(1, len(text) // 4)

    handler.send_response(200)
    handler.send_header("Content-Type", "text/event-stream; charset=utf-8")
    handler.send_header("Cache-Control", "no-cache")
    # id:a36e — MUST close the connection after this synthetic stream. The server has no
    # protocol_version override (defaults HTTP/1.0), and we send no Content-Length and no
    # chunked terminator; if we kept the connection alive the client's SSE reader would
    # block for more body AFTER message_stop, never see EOF, and its agent() promise would
    # hang until the engine's 180s watchdog retried into the same hang (the observed wedge —
    # exact-180s retries, message persisted but promise pending). `Connection: close` sets
    # close_connection=True so BaseHTTPRequestHandler closes the socket → client sees EOF →
    # promise resolves. The pass-through path already relies on this (it strips Connection as
    # hop-by-hop → HTTP/1.0 default close), which is exactly why it never wedged.
    handler.send_header("Connection", "close")
    handler.end_headers()

    def emit(event_type, data):
        handler.wfile.write(_sse_event(event_type, data))
        handler.wfile.flush()

    emit("message_start", {
        "type": "message_start",
        "message": {
            "id": msg_id, "type": "message", "role": "assistant",
            "model": model, "content": [], "stop_reason": None,
            "stop_sequence": None,
            "usage": {"input_tokens": 1, "output_tokens": 1},
        },
    })
    emit("content_block_start", {
        "type": "content_block_start", "index": 0,
        "content_block": {"type": "text", "text": ""},
    })
    emit("content_block_delta", {
        "type": "content_block_delta", "index": 0,
        "delta": {"type": "text_delta", "text": text},
    })
    emit("content_block_stop", {"type": "content_block_stop", "index": 0})
    emit("message_delta", {
        "type": "message_delta",
        "delta": {"stop_reason": "end_turn", "stop_sequence": None},
        "usage": {"output_tokens": out_tokens},
    })
    emit("message_stop", {"type": "message_stop"})
    # id:a36e — belt-and-suspenders: force the handler to close after this response even if
    # a Python version parsed the Connection header differently. Without EOF the promise hangs.
    handler.close_connection = True


def _serve_mechanical_json(handler, text: str, model: str):
    """Emit a non-streaming Messages response carrying `text`."""
    msg_id = "msg_mech_" + secrets.token_hex(12)
    out_tokens = max(1, len(text) // 4)
    payload = {
        "id": msg_id, "type": "message", "role": "assistant", "model": model,
        "content": [{"type": "text", "text": text}],
        "stop_reason": "end_turn", "stop_sequence": None,
        "usage": {"input_tokens": 1, "output_tokens": out_tokens},
    }
    blob = json.dumps(payload).encode("utf-8")
    handler.send_response(200)
    handler.send_header("Content-Type", "application/json")
    handler.send_header("Content-Length", str(len(blob)))
    handler.end_headers()
    handler.wfile.write(blob)
    handler.wfile.flush()


# ── Pass-through transport (adapted from the e905 spike) ─────────────────────
def _stream_chunked(resp, wfile) -> bool:
    """Manually decode a chunked response and forward decoded bytes to wfile.

    fp.read1() on a live keep-alive socket never returns b"" — it blocks waiting
    for the next response. We detect the terminating chunk (size == 0) ourselves.
    """
    fp = resp.fp
    while True:
        line = fp.readline(256)
        if not line:
            return False
        try:
            chunk_size = int(line.split(b";")[0].strip(), 16)
        except ValueError:
            return False
        if chunk_size == 0:
            while True:
                trailer = fp.readline(256)
                if trailer in (b"\r\n", b"\n", b""):
                    break
            return True
        remaining = chunk_size
        while remaining > 0:
            try:
                data = fp.read1(min(4096, remaining))
            except AttributeError:
                data = fp.read(min(256, remaining))
            if not data:
                return False
            remaining -= len(data)
            wfile.write(data)
            wfile.flush()
        fp.read(2)  # consume trailing \r\n after chunk body


def _stream_plain(resp, wfile) -> bool:
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


class ProxyHandler(BaseHTTPRequestHandler):
    def setup(self):
        super().setup()
        # TCP_NODELAY: send each SSE chunk immediately (Nagle + delayed-ACK on
        # loopback would otherwise batch small writes and stall between events).
        self.request.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)

    def log_message(self, format, *args): pass  # silence default access log  # noqa: A002

    def _proxy(self):
        req_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(req_length) if req_length else b""

        # ── Interception: model=="bash" + allowlisted relay command ───────────
        # id:33b2 — _mechanical_dispatch returns (command, stdin_payload); stdin_payload
        # is None on the legacy no-fence path (byte-identical to before this channel).
        dispatch = _mechanical_dispatch(body)
        if dispatch is not None:
            command, stdin_payload = dispatch
            try:
                obj = json.loads(body)
            except Exception:
                obj = {}
            model = obj.get("model", MECH_MODEL)
            wants_stream = bool(obj.get("stream")) or \
                "text/event-stream" in self.headers.get("Accept", "")
            output = _run_mechanical(command, stdin=stdin_payload)
            try:
                if wants_stream:
                    _serve_mechanical_sse(self, output, model)
                else:
                    _serve_mechanical_json(self, output, model)
            except (BrokenPipeError, ConnectionResetError):
                pass
            _log({
                "event": "mechanical", "path": self.path,
                "command": command, "stream": wants_stream,
                "stdin_bytes": len(stdin_payload.encode("utf-8")) if stdin_payload else 0,
                "output_bytes": len(output.encode("utf-8")),
                "upstream_hit": False,
            })
            return

        # ── Shape-debug (id:94b8, opt-in): a model=="bash" request that fell open ──
        # Capture the real agent() wrapper exactly when we need it — a fail-open on a
        # model=="bash" body means the extractor could not pull an allowlisted command
        # from whatever scaffolding the harness added. Log the raw last-user text (bounded)
        # so the wrapper can be inspected in a single capture run. OFF unless DEBUG_SHAPE.
        if DEBUG_SHAPE:
            try:
                _dbg = json.loads(body)
            except Exception:
                _dbg = None
            if isinstance(_dbg, dict) and _dbg.get("model") == MECH_MODEL:
                _raw = _last_user_text(_dbg) or ""
                _log({
                    "event": "shape-debug", "path": self.path,
                    "last_user_text_len": len(_raw),
                    "last_user_text_prefix": _raw[:1500],
                })

        # ── Fail-open pass-through to the real upstream (e905 path) ────────────
        fwd_headers = {
            k: v for k, v in self.headers.items()
            if k.lower() not in _HOP_BY_HOP and k.lower() not in ("host", "accept-encoding")
        }
        if body:
            fwd_headers["Content-Length"] = str(len(body))

        try:
            if UPSTREAM_SCHEME == "http":
                conn = http.client.HTTPConnection(UPSTREAM_HOST, UPSTREAM_PORT, timeout=120)
            else:
                conn = http.client.HTTPSConnection(UPSTREAM_HOST, UPSTREAM_PORT, timeout=120)
            conn.request(self.command, self.path, body=body or None, headers=fwd_headers)
            resp = conn.getresponse()
        except Exception as exc:
            _log({"event": "upstream_error", "path": self.path, "error": str(exc)})
            self.send_error(502, str(exc))
            return

        self.send_response(resp.status)
        for k, v in resp.getheaders():
            if k.lower() in _HOP_BY_HOP:
                continue
            self.send_header(k, v)
        self.end_headers()

        is_chunked = bool(resp.chunked)
        try:
            if is_chunked:
                _stream_chunked(resp, self.wfile)
            else:
                _stream_plain(resp, self.wfile)
        except (BrokenPipeError, ConnectionResetError):
            pass
        finally:
            conn.close()

        _log({
            "event": "passthrough", "method": self.command, "path": self.path,
            "request_body_bytes": req_length, "response_status": resp.status,
            "is_chunked": is_chunked, "upstream_hit": True,
        })

    do_GET = do_POST = do_PUT = do_DELETE = do_PATCH = _proxy


def main():
    server = ThreadingHTTPServer(("127.0.0.1", PORT), ProxyHandler)
    # The socket is bound and listening at this point (ThreadingHTTPServer's
    # __init__ already called bind()+listen()) — tell systemd we're ready
    # promptly, before serve_forever() blocks. No-op if NOTIFY_SOCKET is unset.
    _sd_notify("READY=1")
    _start_sd_watchdog()
    state_path = write_state_file()
    print(f"mechanical proxy on http://127.0.0.1:{PORT} "
          f"→ {UPSTREAM_SCHEME}://{UPSTREAM_HOST}:{UPSTREAM_PORT}", flush=True)
    print(f"  model=='{MECH_MODEL}' → run locally (zero upstream calls); else relay",
          flush=True)
    print(f"Log: {LOG_FILE}", flush=True)
    print(f"State: {state_path} (allowlist digest {allowlist_digest()[:12]}… — "
          f"check with mech-currency.sh --currency)", flush=True)
    print(f"To use: ANTHROPIC_BASE_URL=http://127.0.0.1:{PORT} <driver>", flush=True)
    print("Ctrl-C to stop.", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down.", flush=True)


if __name__ == "__main__":
    main()
