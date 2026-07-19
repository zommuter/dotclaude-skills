#!/usr/bin/env bash
# Unit spec for relay/scripts/mechanical-proxy.py — the fake-Haiku mechanical
# short-circuit (owner-ratified relay optimisation, id:176f). Part of the
# dotclaude-skills bash test suite; run by tests/run-tests.sh.
#
# Imports the module's own functions in-process and exercises them directly — no
# subprocess, no external service, no credentials. It verifies the request
# classifier + command allowlist + response builder:
#   (a) model:"bash" + an ALLOWLISTED relay command -> recognised, run locally,
#       and the built reply carries its stdout (no upstream call is made);
#   (b) allowlisted relay command that fails -> reply is 'MECH-ERROR exit=<n>' + stderr;
#   (c) model:"sonnet"                   -> NOT mechanical -> fail-open (relay to real model);
#   (d) model:"bash" with no extractable command / malformed -> NOT mechanical -> fail-open;
#   (e) model:"bash" carrying a NON-allowlisted command -> refused (NOT run locally),
#       fails open to the real model. Security assertion — this is the whole point of
#       the allowlist: only fixed relay scaffolding runs, never arbitrary request text.
#   (f) IDENTITY PIN: a look-alike path ending in relay/scripts/<allowlisted-name>
#       but living OUTSIDE the pinned canonical root is refused — the allowlist keys
#       on filesystem identity, not basename, so an attacker-controlled copy cannot run.
#   (g) PROCESS SUBSTITUTION: <(...) / >(...) in an otherwise-allowlisted command
#       is refused (bash on this host would otherwise honour it) and never executed.
#   (h) REDIRECTION: >, >>, 2>, &> in an otherwise-allowlisted command is refused
#       (a mechanical hop never redirects) and never executed.
# The positive case (a) exercises the REAL pinned-path identity check: the canonical
# root is pointed (via MECHANICAL_PROXY_RELAY_ROOT) at a controlled temp dir, and a
# real allowlisted-basename script is placed THERE. So (a) proves the pin admits the
# genuine file and (f)/(g)/(h) prove it rejects everything else.
# No roadmap item (id:176f is a HARD—meeting TODO built apex-direct), so any failure
# counts — this test must be GREEN.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODULE="$ROOT/relay/scripts/mechanical-proxy.py"

[[ -f "$MODULE" ]] || { echo "FAIL: module not found at $MODULE"; exit 1; }

python3 - "$MODULE" <<'PYEOF'
import importlib.util
import json
import os
import sys
import tempfile

path = sys.argv[1]

def load():
    spec = importlib.util.spec_from_file_location("mechanical_proxy", path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m

# First load with the DEFAULT root — used only to read the allowlist names, so the
# fixture can pick real allowlisted basenames without hardcoding the set.
probe = load()
allow = sorted(probe.ALLOWED_RELAY_SCRIPTS)
name = allow[0]  # any allowlisted basename
assert name.endswith(".sh")

failures = []
def check(cond, msg):
    if cond:
        print(f"PASS: {msg}")
    else:
        print(f"FAIL: {msg}")
        failures.append(msg)

def req(model, messages):
    return json.dumps({"model": model, "messages": messages}).encode()

# ── Fixture: a CONTROLLED canonical relay-scripts root ──────────────────────
# Point the proxy's pinned root at a temp dir we own, and place a REAL
# allowlisted-basename script THERE (under the pinned root). This makes the
# positive case exercise the genuine pinned-path identity check — not the old
# basename-only match — with fully controlled, deterministic script output and no
# real relay side effects.
canon_parent = tempfile.mkdtemp()
canon = os.path.join(canon_parent, "relay", "scripts")
os.makedirs(canon)
ok_script = os.path.join(canon, name)
with open(ok_script, "w") as f:
    f.write("#!/bin/sh\nprintf %s MECHANICAL-STDOUT-9f3a\n")
# Two more real allowlisted scripts under the pinned root for the positive
# shape checks the real relay actually emits.
for extra in ("claim.sh", "discover-sig.sh"):
    with open(os.path.join(canon, extra), "w") as f:
        f.write("#!/bin/sh\nprintf %s ok\n")

# Reload the module with the pinned root overridden to our controlled dir.
os.environ["MECHANICAL_PROXY_RELAY_ROOT"] = canon
mod = load()

# A separate attacker-controlled tree with the SAME basenames but a different
# (non-canonical) location — the identity pin must reject these.
atk_parent = tempfile.mkdtemp()
atk_dir = os.path.join(atk_parent, "relay", "scripts")
os.makedirs(atk_dir)
atk_script = os.path.join(atk_dir, name)
with open(atk_script, "w") as f:
    f.write("#!/bin/sh\nprintf %s ATTACKER-CONTENT\n")

# ── (a) model:"bash" + allowlisted relay command -> stdout, recognised ──────
ok_cmd = f"sh {ok_script}"
got = mod._mechanical_command(req("bash", [{"role": "user", "content": ok_cmd}]))
check(got == ok_cmd,
      f"(a) allowlisted relay command recognised for local run (got {got!r})")
out = mod._run_mechanical(ok_cmd)
check(out == "MECHANICAL-STDOUT-9f3a",
      f"(a) command run locally, stdout verbatim (got {out!r})")

# The reply builder embeds that stdout in a valid streaming turn.
class Sink:
    def __init__(self):
        self.buf = bytearray(); self.status = None; self.headers = {}
    def send_response(self, s): self.status = s
    def send_header(self, k, v): self.headers[k] = v
    def end_headers(self): pass
    class _W:
        def __init__(self, o): self.o = o
        def write(self, b): self.o.buf.extend(b)
        def flush(self): pass
    @property
    def wfile(self): return Sink._W(self)

sink = Sink()
mod._serve_mechanical_sse(sink, out, "bash")
raw = bytes(sink.buf).decode()
text = "".join(
    json.loads(l.strip()[5:].strip()).get("delta", {}).get("text", "")
    for l in raw.splitlines()
    if l.strip().startswith("data:")
    and json.loads(l.strip()[5:].strip()).get("type") == "content_block_delta"
)
check(sink.status == 200, f"(a) built reply status 200 (got {sink.status})")
check("text/event-stream" in sink.headers.get("Content-Type", ""),
      "(a) built reply is an SSE stream (Content-Type text/event-stream)")
check(text == "MECHANICAL-STDOUT-9f3a",
      f"(a) SSE deltas reconstruct the stdout (got {text!r})")
check('"end_turn"' in raw, "(a) stream ends with a clean end_turn stop")

# ── (b) allowlisted relay command that fails -> MECH-ERROR exit=<n> + stderr ─
with open(ok_script, "w") as f:
    f.write("#!/bin/sh\nprintf STDERR-MARK-7 1>&2\nexit 3\n")
bad_cmd = f"sh {ok_script}"
got = mod._mechanical_command(req("bash", [{"role": "user", "content": bad_cmd}]))
check(got == bad_cmd, "(b) failing allowlisted command is still recognised (it runs, then errors)")
out = mod._run_mechanical(bad_cmd)
check(out.startswith("MECH-ERROR exit=3"), f"(b) 'MECH-ERROR exit=3' prefix (got {out!r})")
check("STDERR-MARK-7" in out, f"(b) stderr relayed verbatim (got {out!r})")
# restore deterministic stdout for later positive checks
with open(ok_script, "w") as f:
    f.write("#!/bin/sh\nprintf %s MECHANICAL-STDOUT-9f3a\n")

# ── (c) model:"sonnet" -> NOT mechanical -> fail-open (None) ─────────────────
got = mod._mechanical_command(
    req("sonnet", [{"role": "user", "content": ok_cmd}]))
check(got is None, f"(c) non-bash model NOT mechanical -> fail-open (got {got!r})")

# ── (d) model:"bash" but no extractable command / malformed -> fail-open ────
check(mod._mechanical_command(
        req("bash", [{"role": "assistant", "content": "no user turn"}])) is None,
      "(d) bash body with no user command -> fail-open")
check(mod._mechanical_command(b"{not json") is None,
      "(d) malformed JSON body -> fail-open")
check(mod._mechanical_command(
        req("bash", [{"role": "user", "content": "   "}])) is None,
      "(d) whitespace-only command -> fail-open")

# ── (e) SECURITY: model:"bash" with a NON-allowlisted command -> refused ────
# A command that is not a known relay invocation is never run locally; the gate
# returns None so the caller relays it to the real model.
for bad in [
    "rm -rf /tmp/x",                                   # destructive, non-relay
    "curl http://example.invalid/x",                   # network egress, non-relay
    "whoami",                                          # arbitrary non-relay
    f"sh {ok_script} ; rm -rf /tmp/x",                 # chained: relay + non-relay -> refused
    f"sh {ok_script} $(rm -rf /tmp)",                  # command substitution -> refused
    f"sh {canon}/not-a-relay-script.sh",               # under pinned root, unknown basename
]:
    check(mod._command_allowed(bad) is False,
          f"(e) NON-allowlisted command refused: {bad!r}")
    check(mod._mechanical_command(
            req("bash", [{"role": "user", "content": bad}])) is None,
          f"(e) model:bash + non-allowlisted -> fail-open (not run): {bad!r}")

# ── (e+) positive allowlist shapes the real relay actually emits ────────────
# Now keyed to the pinned canonical root (the real files created above).
check(mod._command_allowed(f"{canon}/claim.sh peek") is True,
      "(e+) real relay invocation (pinned claim.sh peek) is allowed")
check(mod._command_allowed(
        "echo '{\"repos\":[]}' | " + f"{canon}/discover-sig.sh") is True,
      "(e+) piped plumbing + allowlisted relay script (echo | discover-sig.sh) is allowed")

# ── (f) IDENTITY PIN: look-alike path outside the canonical root -> refused ──
# Basename is allowlisted but the file lives under an attacker directory (or is a
# relative/foreign path). The old gate matched on basename and ran the attacker's
# file; the pin now rejects anything that does not realpath to <canon>/<name>.
for bad in [
    f"sh {atk_script}",                                # /tmp/<attacker>/relay/scripts/<name>
    f"sh ../../../tmp/relay/scripts/{name}",           # relative escape, basename allowlisted
    f"sh /home/attacker/relay/scripts/{name}",         # absolute foreign path
]:
    check(mod._command_allowed(bad) is False,
          f"(f) non-canonical look-alike path refused: {bad!r}")
    check(mod._mechanical_command(
            req("bash", [{"role": "user", "content": bad}])) is None,
          f"(f) model:bash + non-canonical path -> fail-open (not run): {bad!r}")

# ── (g) PROCESS SUBSTITUTION -> refused, and never executed ─────────────────
psub_marker = os.path.join(canon_parent, f"PWNED_psub_{os.getpid()}")
for bad in [
    f"sh {ok_script} <(touch {psub_marker})",
    f"sh {ok_script} >(touch {psub_marker})",
]:
    check(mod._command_allowed(bad) is False,
          f"(g) process substitution refused: {bad!r}")
    check(mod._mechanical_command(
            req("bash", [{"role": "user", "content": bad}])) is None,
          f"(g) model:bash + process substitution -> fail-open (not run): {bad!r}")
check(not os.path.exists(psub_marker),
      "(g) process-substitution side effect NOT executed (no marker file)")

# ── (h) REDIRECTION -> refused, and never executed ──────────────────────────
clobber = os.path.join(canon_parent, f"CLOBBER_{os.getpid()}")
for bad in [
    f"{canon}/claim.sh > {clobber}",
    f"{canon}/claim.sh >> {clobber}",
    f"{canon}/claim.sh 2> {clobber}",
    f"{canon}/claim.sh &> {clobber}",
    f"sh {ok_script} < {clobber}",
]:
    check(mod._command_allowed(bad) is False,
          f"(h) redirection refused: {bad!r}")
    check(mod._mechanical_command(
            req("bash", [{"role": "user", "content": bad}])) is None,
          f"(h) model:bash + redirection -> fail-open (not run): {bad!r}")
check(not os.path.exists(clobber),
      "(h) redirection target NOT created (never executed)")

import shutil
shutil.rmtree(canon_parent, ignore_errors=True)
shutil.rmtree(atk_parent, ignore_errors=True)

if failures:
    print(f"\n{len(failures)} assertion(s) failed")
    sys.exit(1)
print("\nALL PASS: mechanical-proxy classifier + allowlist + identity-pin + "
      "no-procsub/redirect + fail-open + SSE synthesis (id:176f)")
PYEOF
