#!/usr/bin/env bash
# roadmap:33b2
#
# RED SPEC — authored 2026-07-28 (handoff C3), NOT implemented. EXPECTED-RED while id:33b2 is
# unticked. This is SECURITY-BOUNDARY code (owner re-laned it [HARD]/apex for that reason) — do
# not weaken any assertion here to make it pass.
#
# WHY: `_command_allowed()` in mechanical-proxy.py is deliberately paranoid and its checks are
# SUBSTRING scans over the whole command string, with no quote-awareness. That is correct when the
# command is only a command. It breaks when a hop must carry DATA: write-relay-status has to move a
# markdown document to relay-status-publish.sh, so it embeds it as a heredoc and is refused three
# ways (multi-line ⇒ sequence operator; `<<` ⇒ redirection; any backtick/`$(` anywhere ⇒ refused,
# even safely single-quoted). Measured live: `echo 'see \`foo.sh\`' | relay-status-publish.sh` →
# False, while a bare `relay-status-publish.sh --path …` → True. Only the payload transport fails.
# The id:4f10 audit found handback-followup and gaming-log are the same class, so this unblocks 3.
#
# OPTION B (owner-ratified, id:a05c): an OPT-IN subset, NOT all allowlisted scripts. Admitting a
# script to the channel must stay a deliberate, reviewable act — never inherited by adding to
# ALLOWED_RELAY_SCRIPTS.
#
# CONTRACT:
#   1. A second fence ```relay-mech-stdin carries a payload piped to the child's STDIN, never
#      handed to the shell.
#   2. STDIN_ALLOWED_SCRIPTS is a SEPARATE set from ALLOWED_RELAY_SCRIPTS, initially
#      {relay-status-publish.sh}. A stdin fence for a script outside it is REFUSED.
#   3. The gate is AND, not OR: a stdin fence whose COMMAND fence is itself disallowed is refused.
#   4. No loosening: _command_allowed() still governs the command fence unchanged, and a request
#      with no stdin fence behaves byte-identically to today.
#   5. The payload is NEVER shell-evaluated.
#
# Hermetic: drives the proxy's own predicates in-process; no network, no ~/.claude writes.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROXY="$ROOT/relay/scripts/mechanical-proxy.py"

fail=0
note() { echo "FAIL: $*" >&2; fail=1; }
[[ -f "$PROXY" ]] || { note "mechanical-proxy.py not found"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 not available"; exit 0; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
CANARY="$tmp/pwned-33b2"

python3 - "$PROXY" "$CANARY" <<'PYEOF'
import importlib.util, sys, os
proxy_path, canary = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("mp", proxy_path)
mp = importlib.util.module_from_spec(spec); sys.modules["mp"] = mp
spec.loader.exec_module(mp)

bad = []
def check(cond, msg):
    if not cond: bad.append(msg)

# (1) the stdin fence must be extractable, separately from the command fence.
check(hasattr(mp, "_MECH_STDIN_FENCE_RE") or hasattr(mp, "extract_stdin_payload"),
      "(1) no stdin-fence extractor (_MECH_STDIN_FENCE_RE / extract_stdin_payload) — the id:33b2 deliverable")

# (2) STDIN_ALLOWED_SCRIPTS must exist, be SEPARATE from ALLOWED_RELAY_SCRIPTS, and be a subset.
check(hasattr(mp, "STDIN_ALLOWED_SCRIPTS"),
      "(2) no STDIN_ALLOWED_SCRIPTS opt-in set — option B requires admission be deliberate, not inherited from ALLOWED_RELAY_SCRIPTS")
if hasattr(mp, "STDIN_ALLOWED_SCRIPTS"):
    s = set(mp.STDIN_ALLOWED_SCRIPTS)
    check(s != set(mp.ALLOWED_RELAY_SCRIPTS),
          "(2) STDIN_ALLOWED_SCRIPTS equals ALLOWED_RELAY_SCRIPTS — that is option A (all scripts), which the owner REJECTED")
    check("relay-status-publish.sh" in s,
          "(2) relay-status-publish.sh not in STDIN_ALLOWED_SCRIPTS (the initial member)")
    check(s <= set(mp.ALLOWED_RELAY_SCRIPTS),
          "(2) STDIN_ALLOWED_SCRIPTS contains a script not even in ALLOWED_RELAY_SCRIPTS")

# (4) NO LOOSENING — the command gate must still refuse everything it refuses today.
P = "~/.claude/skills/relay/scripts/relay-status-publish.sh --path '/x/S.md'"
check(mp._command_allowed(P) is True, "(4) a bare allowlisted one-liner must still be allowed")
for c, why in [
    ("echo 'see `foo.sh`' | " + P, "backtick"),
    ("echo 'run $(date)' | " + P, "command substitution"),
    ("cat /etc/passwd ; " + P,    "sequence operator"),
    (P + " > /tmp/x",             "redirection"),
]:
    check(mp._command_allowed(c) is False, f"(4) command gate LOOSENED — it now accepts a command containing a {why}")

# (5) the payload must never be shell-evaluated.
check(not os.path.exists(canary), "(5) canary file exists before the test — fixture error")

if bad:
    for b in bad: print("FAIL: " + b, file=sys.stderr)
    sys.exit(1)
PYEOF
rc=$?
[[ $rc -eq 0 ]] || fail=1

# (3)+(5) end-to-end: drive the ACTUAL interception path — a payload of shell metacharacters
# must round-trip byte-identical to the script's stdin, leave no side effects, and the opt-in
# gate must refuse a stdin fence for a non-admitted script (AND-gated with the command gate).
# Uses a CONTROLLED canonical relay-scripts root (MECHANICAL_PROXY_RELAY_ROOT) so the command
# gate's pinned-path identity check is exercised with a script whose ONLY behaviour is `cat`.
if [[ $fail -eq 0 ]]; then
python3 - "$PROXY" "$CANARY" <<'PYEOF'
import importlib.util, sys, os, json, tempfile
proxy_path, canary = sys.argv[1], sys.argv[2]

def load():
    spec = importlib.util.spec_from_file_location("mp", proxy_path)
    m = importlib.util.module_from_spec(spec); sys.modules["mp"] = m
    spec.loader.exec_module(m)
    return m

# A controlled canonical root: relay-status-publish.sh (the initial STDIN_ALLOWED member) and
# claim.sh (allowlisted but deliberately NOT stdin-admitted) both cat their stdin, so any
# returned bytes are exactly what reached the child's stdin.
canon_parent = tempfile.mkdtemp()
canon = os.path.join(canon_parent, "relay", "scripts"); os.makedirs(canon)
for nm in ("relay-status-publish.sh", "claim.sh"):
    with open(os.path.join(canon, nm), "w") as f:
        f.write("#!/bin/sh\ncat\n")
    os.chmod(os.path.join(canon, nm), 0o755)
os.environ["MECHANICAL_PROXY_RELAY_ROOT"] = canon
mp = load()

PUB = os.path.join(canon, "relay-status-publish.sh")
CLAIM = os.path.join(canon, "claim.sh")
assert "relay-status-publish.sh" in mp.STDIN_ALLOWED_SCRIPTS
assert "claim.sh" not in mp.STDIN_ALLOWED_SCRIPTS and "claim.sh" in mp.ALLOWED_RELAY_SCRIPTS

# The metacharacter payload — the exact content classes a command-string route cannot carry.
payload = "line one\n$(touch %s)\n`whoami`\na; b && c\ntrailing" % canary

def body(cmd, stdin=None):
    text = "wrapper prose\n```relay-mech\n%s\n```\n" % cmd
    if stdin is not None:
        text += "more prose\n```relay-mech-stdin\n%s\n```\nafter\n" % stdin
    return json.dumps({"model": "bash",
                       "messages": [{"role": "user", "content": text}]}).encode()

bad = []
def ck(c, m):
    if not c: bad.append(m)

# (3+5) admitted script + stdin fence -> dispatched, payload byte-identical, inert.
d = mp._mechanical_dispatch(body(PUB, payload))
ck(d is not None, "(3) dispatch refused an admitted-script stdin fence")
if d is not None:
    cmd, sp = d
    ck(sp == payload, "(3) stdin payload not byte-identical after extraction: %r" % (sp,))
    out = mp._run_mechanical(cmd, stdin=sp)
    ck(out == payload, "(5) payload did not round-trip through the child's stdin: %r" % (out,))
ck(not os.path.exists(canary), "(5) canary exists — stdin payload was SHELL-EVALUATED")

# (2/refusal) stdin fence for an allowlisted-but-NOT-admitted script -> refused (fail open).
ck(mp._mechanical_dispatch(body(CLAIM, payload)) is None,
   "(2) stdin fence for claim.sh (not in STDIN_ALLOWED_SCRIPTS) was NOT refused")

# (3/AND) stdin fence whose COMMAND fence is itself disallowed -> refused, even though the
# pinned script IS admitted (the gate is AND: command gate must also pass).
ck(mp._mechanical_dispatch(body("cat /etc/passwd ; " + PUB, payload)) is None,
   "(3) AND-gate breached — a disallowed command fence with a stdin fence was accepted")

# (4) no stdin fence -> legacy tuple (command, None); run path unchanged.
d2 = mp._mechanical_dispatch(body(PUB))
ck(d2 is not None and d2[1] is None,
   "(4) no-stdin request did not take the byte-identical legacy path")

if bad:
    for b in bad: print("FAIL: " + b, file=sys.stderr)
    sys.exit(1)
PYEOF
  [[ $? -eq 0 ]] || fail=1
  [[ -e "$CANARY" ]] && note "(5) the payload was SHELL-EVALUATED — stdin must be inert data, never parsed"
fi

[[ $fail -eq 0 ]] || { echo "EXPECTED-RED: id:33b2 not built yet" >&2; exit 1; }
echo "ALL PASS: opt-in stdin channel; command gate unloosened; payload inert (id:33b2)"
