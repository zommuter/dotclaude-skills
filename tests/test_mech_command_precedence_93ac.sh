#!/usr/bin/env bash
# roadmap:93ac
#
# SPEC — command-fence PRECEDENCE (id:93ac). SECURITY-BOUNDARY code (owner re-laned the
# stdin channel [HARD]/apex for that reason) — do not weaken any assertion here to make
# it pass.
#
# THE DEFECT (reproduced live 2026-08-11 against mechanical-proxy.py): the command
# extractor `_command_from_wrapped` searched the WHOLE user text for the first
# ```relay-mech fence, and nothing required the loop's real command fence to precede the
# ```relay-mech-stdin PAYLOAD. A payload that merely QUOTES a ```relay-mech block — which
# is ordinary content: this very repo's ROADMAP.md and relay/SKILL.md carry literal
# ```relay-mech fences — could therefore SUPPLY the dispatched command, winning on
# position over the loop's own out-of-payload fence. The reachable impact (both existing
# gates still apply: `_command_allowed()` AND the STDIN_ALLOWED_SCRIPTS opt-in) is
# argument-level redirection of one allowlisted script (`relay-status-publish.sh --path
# <attacker-chosen>`), not arbitrary execution — but it is a real precedence break.
#
# THE FIX (id:93ac, precedence-scoped): excise the stdin fence SPAN before extracting the
# command, so a payload is structurally unable to contribute a command. Reuses the two
# existing regexes; no third parser.
#
# CONTRACT (mirrors the item's tests a–d):
#   (a) a request whose PAYLOAD embeds a ```relay-mech fence dispatches the LOOP's command
#       (the out-of-payload fence) or refuses — NEVER the payload's command.
#   (b) a legit payload round-trips byte-identical: the fix does not perturb the payload
#       extraction path (extract_stdin_payload is untouched). Payloads carrying shell
#       metacharacters still reach the child's stdin exactly as authored.
#   (c) the id:33b2 suite stays green unchanged (asserted by the suite runner, and this
#       file re-exercises the canonical command-first + stdin request to prove it).
#   (d) a no-stdin-fence request is byte-identical to the legacy path.
#
# Hermetic: drives the proxy's own predicates in-process; no network, no ~/.claude writes.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROXY="$ROOT/relay/scripts/mechanical-proxy.py"

fail=0
note() { echo "FAIL: $*" >&2; fail=1; }
[[ -f "$PROXY" ]] || { note "mechanical-proxy.py not found"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 not available"; exit 0; }

python3 - "$PROXY" <<'PYEOF'
import importlib.util, sys, os, json, tempfile
proxy_path = sys.argv[1]

# A controlled canonical relay-scripts root so the command gate's pinned-path identity
# check runs against a script whose ONLY behaviour is `cat` — anything the child prints
# is exactly what reached its stdin. relay-status-publish.sh is the initial
# STDIN_ALLOWED member; claim.sh is allowlisted but NOT stdin-admitted.
canon_parent = tempfile.mkdtemp()
canon = os.path.join(canon_parent, "relay", "scripts"); os.makedirs(canon)
for nm in ("relay-status-publish.sh", "claim.sh"):
    p = os.path.join(canon, nm)
    with open(p, "w") as f:
        f.write("#!/bin/sh\ncat\n")
    os.chmod(p, 0o755)
os.environ["MECHANICAL_PROXY_RELAY_ROOT"] = canon

spec = importlib.util.spec_from_file_location("mp", proxy_path)
mp = importlib.util.module_from_spec(spec); sys.modules["mp"] = mp
spec.loader.exec_module(mp)

PUB = os.path.join(canon, "relay-status-publish.sh")
GOOD = PUB + " --path '/good/RELAY_STATUS.md'"
EVIL = PUB + " --path '/tmp/ATTACKER-CHOSEN'"

bad = []
def ck(c, m):
    if not c: bad.append(m)

def user_body(text):
    return json.dumps({"model": "bash",
                       "messages": [{"role": "user", "content": text}]}).encode()

# ── (a) PRECEDENCE: payload-first, with the payload QUOTING a full ```relay-mech block
# whose command differs from the loop's. This is the exact live-reproduced shape: the
# stdin fence (assembled from repo prose) precedes the loop's own command fence, and the
# payload's inner fence is a complete block carrying EVIL.
attack = (
    "```relay-mech-stdin\n"
    "prose quoting a fence:\n"
    "```relay-mech\n"
    + EVIL + "\n"
    "```\n"
    "\n"
    "```relay-mech\n"
    + GOOD + "\n"
    "```\n"
)
cmd = mp._command_from_wrapped(attack)
ck(cmd is not None and "/tmp/ATTACKER-CHOSEN" not in cmd,
   "(a) command extractor returned the PAYLOAD's command: %r" % (cmd,))
ck(cmd == GOOD, "(a) command extractor did not return the LOOP's command: %r" % (cmd,))

# Full dispatch path: must be the loop's command (never the payload's), and if it
# dispatches at all the stdin payload must be inert data, not a shell-evaluated command.
d = mp._mechanical_dispatch(user_body(attack))
if d is not None:
    dcmd, dsp = d
    ck("/tmp/ATTACKER-CHOSEN" not in dcmd,
       "(a) _mechanical_dispatch ran the PAYLOAD's command: %r" % (dcmd,))
    ck(dcmd == GOOD, "(a) _mechanical_dispatch did not run the LOOP's command: %r" % (dcmd,))

# ── (a') A payload-supplied command whose out-of-payload sibling is ABSENT must NOT
# fall through to RUNNING the payload's command — `_mechanical_dispatch` refuses
# (fail open → None). (The raw extractor may return the intact text as a would-be bare
# command, but `_command_allowed` then refuses that multi-line fenced blob; the
# load-bearing property is that dispatch never runs EVIL.)
attack_only = (
    "```relay-mech-stdin\n"
    "prose:\n"
    "```relay-mech\n"
    + EVIL + "\n"
    "```\n"
)
d_only = mp._mechanical_dispatch(user_body(attack_only))
ck(d_only is None or "/tmp/ATTACKER-CHOSEN" not in d_only[0],
   "(a') a lone payload-embedded fence was DISPATCHED as the command: %r" % (d_only,))

# ── (b) A legit payload round-trips byte-identical through the (unchanged) payload path.
# The metacharacter payload is the exact content classes a command-string route cannot
# carry; the fix must not perturb it.
payload = "line one\n$(touch /tmp/should-not-run-93ac)\n`whoami`\na; b && c\ntrailing"
canonical = (
    "wrapper prose\n"
    "```relay-mech\n"
    + GOOD + "\n"
    "```\n"
    "more prose\n"
    "```relay-mech-stdin\n"
    + payload + "\n"
    "```\n"
    "after\n"
)
sp = mp.extract_stdin_payload(canonical)
ck(sp == payload, "(b) legit payload not byte-identical after extraction: %r" % (sp,))
d3 = mp._mechanical_dispatch(user_body(canonical))
ck(d3 is not None, "(b) canonical admitted request was refused")
if d3 is not None:
    c3, s3 = d3
    ck(c3 == GOOD, "(b) canonical request command changed: %r" % (c3,))
    ck(s3 == payload, "(b) canonical request stdin not byte-identical: %r" % (s3,))
    out = mp._run_mechanical(c3, stdin=s3)
    ck(out == payload, "(b) payload did not round-trip through the child's stdin: %r" % (out,))
ck(not os.path.exists("/tmp/should-not-run-93ac"),
   "(b) canary exists — stdin payload was SHELL-EVALUATED")

# ── (c) The canonical command-first request still extracts the loop's command exactly
# (the id:33b2 happy path is unchanged by the precedence fix).
ck(mp._command_from_wrapped(canonical) == GOOD,
   "(c) canonical command-first extraction regressed: %r" % (mp._command_from_wrapped(canonical),))

# ── (d) A no-stdin-fence request is byte-identical to the legacy path: command extracted,
# stdin None, dispatch tuple (command, None).
legacy = "wrapper\n```relay-mech\n" + GOOD + "\n```\ntrailer\n"
ck(mp._command_from_wrapped(legacy) == GOOD, "(d) no-stdin command extraction changed")
ck(mp.extract_stdin_payload(legacy) is None, "(d) no-stdin request grew a stdin payload")
dl = mp._mechanical_dispatch(user_body(legacy))
ck(dl is not None and dl[1] is None,
   "(d) no-stdin request did not take the byte-identical legacy (command, None) path")

# ── A bare-command (no fence at all) request is unchanged: returns the text verbatim.
bare = GOOD
ck(mp._command_from_wrapped(bare) == bare, "(d) bare-command shape changed")

if bad:
    for b in bad: print("FAIL: " + b, file=sys.stderr)
    sys.exit(1)
PYEOF
rc=$?
[[ $rc -eq 0 ]] || fail=1

[[ $fail -eq 0 ]] || { echo "EXPECTED-RED: id:93ac not built yet" >&2; exit 1; }
echo "ALL PASS: command-fence precedence — payload cannot supply the command (id:93ac)"
