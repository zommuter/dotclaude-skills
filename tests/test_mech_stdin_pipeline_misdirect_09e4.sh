#!/usr/bin/env bash
# roadmap:09e4
#
# RED SPEC -- authored 2026-09-08 (relay review, run relay-20260908-174448-4421), NOT
# implemented. EXPECTED-RED while ROADMAP id:09e4 is unticked. This file is the executable
# specification; do not weaken it to make it pass.
#
# WHY -- the stdin opt-in gate and the stdin DELIVERY disagree about which pipeline stage
# receives the payload, verified at HEAD by reading both:
#
#   relay/scripts/mechanical-proxy.py:689  `pinned = _last_stage_relay_script(command)`
#       -> admission keys off the script leading the LAST pipeline stage.
#   relay/scripts/mechanical-proxy.py:723  `subprocess.run([MECH_SHELL,'-c',command],
#                                            input=stdin, ...)`
#       -> the payload reaches the SHELL's stdin, i.e. the FIRST stage of the pipeline.
#
# So `echo x | relay-status-publish.sh` with a ```relay-mech-stdin fence is ADMITTED on the
# strength of the admitted last stage, and then delivers the payload to `echo` (which ignores
# it) while the admitted script reads `x` off the pipe. Silent wrong-bytes delivery: nothing
# fails, nothing logs, the payload is simply lost.
#
# NOT an active vulnerability (id:09e4 rates it LOW): the command is constructed by
# relay-loop.js (trusted) and the only admitted member is invoked bare today. It is LATENT --
# the documented design intent is "a single bare allowlisted script invocation" and the gate
# does not enforce that shape, so the first piped use silently misdelivers.
#
# CONTRACT (the fix id:09e4 specifies):
#   1. When a ```relay-mech-stdin fence is present, the command must be a SINGLE stage. A
#      multi-stage pipeline is REFUSED (fail open, return None) -- never run with the payload
#      handed to the wrong stage.
#   2. The refusal is LOUD, not silent: a `mechanical_stdin_refused` log entry whose reason
#      names the pipeline shape (id:4347 no-silent-swallow).
#   3. No loosening anywhere else: a bare admitted invocation WITH a fence still dispatches,
#      and a multi-stage command with NO fence is completely unaffected.
#
# TRIANGULATION / ORDER: (A) and (D) are the negative controls that must stay green both
# before and after the fix -- they are what stops the fix being "refuse everything". (B) is
# the flagship refusal and (C) its loudness. This file uses the repo's non-exiting accumulator
# idiom, so `# fails-against-assertion:` below names the LAST FAIL line, per CLAUDE.md
# section Testing.
#
# Hermetic: drives the proxy's own predicates in-process via importlib. No network, no
# subprocess execution of the command, no ~/.claude writes (MECH_LOG is redirected into the
# scratch dir before any dispatch runs).

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROXY="$ROOT/relay/scripts/mechanical-proxy.py"

fail=0
note() { echo "FAIL: $*" >&2; fail=1; }
[[ -f "$PROXY" ]] || { echo "FAIL: mechanical-proxy.py not found at $PROXY" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 not available"; exit 0; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

out="$tmp/out.txt"
python3 - "$PROXY" "$tmp" >"$out" 2>&1 <<'PYEOF'
import importlib.util, json, sys, os

proxy_path, scratch = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("mp09e4", proxy_path)
mp = importlib.util.module_from_spec(spec); sys.modules["mp09e4"] = mp
spec.loader.exec_module(mp)

# Keep every _log write inside the scratch dir -- this test must never touch ~/.claude.
logfile = os.path.join(scratch, "mech.jsonl")
redirected = False
for name in ("LOG_FILE", "MECH_LOG", "MECH_LOG_PATH", "LOG_PATH"):
    if hasattr(mp, name):
        setattr(mp, name, logfile)
        redirected = True
if not redirected:
    print("FAIL: (setup) cannot redirect the proxy's log file -- refusing to run rather "
          "than write into the real log")
    sys.exit(1)

bad = []
def check(cond, msg):
    if not cond:
        bad.append(msg)

# The one script admitted to the DATA plane today; the spec is written against whatever the
# module actually declares rather than a hardcoded name, so admitting a second member later
# does not silently retarget this file.
admitted = sorted(getattr(mp, "STDIN_ALLOWED_SCRIPTS", []))
if not admitted:
    print("FAIL: (setup) STDIN_ALLOWED_SCRIPTS is empty -- id:33b2's opt-in set is the "
          "premise of this spec")
    sys.exit(1)
# `_token_is_relay_script` pins by filesystem IDENTITY against CANONICAL_RELAY_SCRIPTS_ROOT
# (mechanical-proxy.py:469-492), so a BARE script name is never allowed and a worktree-
# relative path is not the pinned file. Build the command from the module's own canonical
# root, and pick an admitted script the COMMAND gate actually accepts -- not every DATA-plane
# member is a bare-invocable command-plane member, and picking one the command gate refuses
# would make every assertion below fire for the wrong reason: a fixture-sanity failure
# masquerading as the defect.
root = getattr(mp, "CANONICAL_RELAY_SCRIPTS_ROOT", None)
if not root:
    print("SKIP: CANONICAL_RELAY_SCRIPTS_ROOT not defined; cannot build a pinned invocation")
    sys.exit(0)
SCRIPT = None
for cand in admitted:
    path = os.path.join(root, cand)
    if mp._command_allowed("%s --path /dev/null" % path):
        SCRIPT, SCRIPT_PATH = cand, path
        break
if SCRIPT is None:
    print("SKIP: no member of STDIN_ALLOWED_SCRIPTS resolves to a pinned file under %s "
          "(relay not installed here); the stdin channel cannot be exercised" % root)
    sys.exit(0)

def body(command, payload=None):
    text = "```relay-mech\n%s\n```" % command
    if payload is not None:
        text = "```relay-mech-stdin\n%s\n```\n%s" % (payload, text)
    return json.dumps({
        "model": mp.MECH_MODEL,
        "messages": [{"role": "user", "content": [{"type": "text", "text": text}]}],
    }).encode()

def logsize():
    try:
        return os.path.getsize(logfile)
    except OSError:
        return 0

BARE = "%s --path /dev/null" % SCRIPT_PATH
PIPED = "echo seedbytes | %s --path /dev/null" % SCRIPT_PATH

# --- (A) NEGATIVE CONTROL: a bare admitted invocation WITH a fence still dispatches --------
a = mp._mechanical_dispatch(body(BARE, "PAYLOAD"))
check(a is not None and a[1] == "PAYLOAD",
      "(A) negative control broken: a BARE admitted invocation with a stdin fence must still "
      "dispatch and carry its payload -- got %r. A fix that refuses this refuses the channel "
      "itself." % (a,))

# --- (D) NEGATIVE CONTROL: a multi-stage command with NO fence is unaffected ---------------
d = mp._mechanical_dispatch(body(PIPED, None))
check(d is not None and d[1] is None,
      "(D) negative control broken: a multi-stage command with NO stdin fence must dispatch "
      "byte-identically to before this channel existed -- got %r. The single-stage rule is "
      "conditioned on the FENCE being present, not on the command shape alone." % (d,))

# --- (C) the refusal must be LOUD -- checked before (B) so both fire on their own merits ---
before = logsize()
b = mp._mechanical_dispatch(body(PIPED, "PAYLOAD"))
after = logsize()
entries = []
if os.path.exists(logfile):
    with open(logfile) as fh:
        for ln in fh:
            ln = ln.strip()
            if not ln:
                continue
            try:
                entries.append(json.loads(ln))
            except Exception:
                pass
refusals = [e for e in entries if e.get("event") == "mechanical_stdin_refused"]
check(after > before and refusals,
      "(C) the refusal is SILENT: no `mechanical_stdin_refused` entry was logged for a stdin "
      "fence on a multi-stage pipeline. id:4347 -- a gate that refuses without saying so is "
      "indistinguishable from a broken model downstream.")
if refusals:
    reason = " ".join(str(refusals[-1].get("reason", "")).lower().split())
    check("pipeline" in reason or "single stage" in reason or "multi-stage" in reason,
          "(C) the logged refusal reason does not name the PIPELINE shape (%r) -- it reads as "
          "the id:a05c not-admitted refusal, so an operator cannot tell the two apart." % reason)

# --- (B) FLAGSHIP: a stdin fence on a multi-stage pipeline must be REFUSED -----------------
check(b is None,
      "(B) a ```relay-mech-stdin fence on a MULTI-STAGE pipeline was ADMITTED (returned %r). "
      "The payload would reach the SHELL's stdin -- the FIRST stage (`echo`) -- while "
      "admission was granted on the strength of the LAST stage (%s), which instead reads the "
      "pipe. Silent wrong-bytes delivery: mechanical-proxy.py:689 keys admission off "
      "_last_stage_relay_script while :723 feeds subprocess.run([MECH_SHELL,'-c',command], "
      "input=stdin)." % (b, SCRIPT))

for m in bad:
    print("FAIL: " + m)
sys.exit(1 if bad else 0)
PYEOF
rc=$?

cat "$out"
[[ $rc -eq 0 ]] || fail=1

if [[ $fail -eq 0 ]]; then
  echo "PASS test_mech_stdin_pipeline_misdirect_09e4"
fi
exit $fail
