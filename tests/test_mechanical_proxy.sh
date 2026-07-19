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
spec = importlib.util.spec_from_file_location("mechanical_proxy", path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

failures = []
def check(cond, msg):
    if cond:
        print(f"PASS: {msg}")
    else:
        print(f"FAIL: {msg}")
        failures.append(msg)

def req(model, messages):
    return json.dumps({"model": model, "messages": messages}).encode()

# A hermetic stand-in for an allowlisted relay script: a temp relay/scripts/<name>
# whose basename is on the allowlist, so the allowlist accepts it, but whose body we
# control for deterministic output (no real relay side effects, no relay env needed).
tmp = tempfile.mkdtemp()
scripts_dir = os.path.join(tmp, "relay", "scripts")
os.makedirs(scripts_dir)
name = sorted(mod.ALLOWED_RELAY_SCRIPTS)[0]  # any allowlisted basename
assert name.endswith(".sh")
ok_script = os.path.join(scripts_dir, name)
with open(ok_script, "w") as f:
    f.write("#!/bin/sh\nprintf %s MECHANICAL-STDOUT-9f3a\n")

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
    f"sh {tmp}/relay/scripts/not-a-relay-script.sh",   # relay/scripts path, unknown basename
]:
    check(mod._command_allowed(bad) is False,
          f"(e) NON-allowlisted command refused: {bad!r}")
    check(mod._mechanical_command(
            req("bash", [{"role": "user", "content": bad}])) is None,
          f"(e) model:bash + non-allowlisted -> fail-open (not run): {bad!r}")

# ── (e+) positive allowlist shapes the real relay actually emits ────────────
check(mod._command_allowed("~/.claude/skills/relay/scripts/claim.sh peek") is True,
      "(e+) real relay invocation (claim.sh peek) is allowed")
check(mod._command_allowed(
        "echo '{\"repos\":[]}' | ~/.claude/skills/relay/scripts/discover-sig.sh") is True,
      "(e+) piped plumbing + allowlisted relay script (echo | discover-sig.sh) is allowed")

import shutil
shutil.rmtree(tmp, ignore_errors=True)

if failures:
    print(f"\n{len(failures)} assertion(s) failed")
    sys.exit(1)
print("\nALL PASS: mechanical-proxy classifier + allowlist + fail-open + SSE synthesis (id:176f)")
PYEOF
