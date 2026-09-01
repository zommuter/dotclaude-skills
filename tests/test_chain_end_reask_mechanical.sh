#!/usr/bin/env bash
# Defect-fix test (no roadmap: header — failures always count).
#
# id:5552 (routed:c555) — the chain-end classifier re-ask was 100% DEAD for every repo.
# relay-loop.js dispatched `classify-repo.sh --emit unit | jq -c '…' | classify-verdict.sh`
# as a model:"bash" hop, but `jq` is not in mechanical-proxy.py's _SAFE_PLUMBING, so
# _command_allowed() returned False, the request fell OPEN to the real API, and model:"bash"
# 404'd ("There's an issue with the selected model (bash)"). Nobody noticed because a REFUSED
# mechanical command and a never-mechanical request both returned a silent None.
#
# Fix has two halves, both asserted here:
#   (a) classify-repo.sh owns chain_ended/chain_end_reason via --chain-ended, so the hop is two
#       pinned relay scripts and passes the gate (the jq stage is gone);
#   (b) mechanical-proxy.py LOGS the refusal (no-silent-swallow, id:4347) so the next instance
#       of this class names itself instead of costing a run.
#
# Hermetic: no network, no ~/.config writes; proxy is imported, never bound to a port.
# fails-against: rev 5e5784890306 -- the tree as it stood immediately before the commit that
#   added this test, i.e. the pre-fix relay/scripts/classify-repo.sh, relay/scripts/mechanical-proxy.py, relay/scripts/relay-loop.js. Derived + verified by tests/verify-negative-cases.py.
# fails-against-rev: 5e5784890306 -- relay/scripts/classify-repo.sh relay/scripts/mechanical-proxy.py relay/scripts/relay-loop.js
# fails-against-assertion: refused mechanical command is LOGGED with its text

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLASSIFY="$REPO_ROOT/relay/scripts/classify-repo.sh"
PROXY="$REPO_ROOT/relay/scripts/mechanical-proxy.py"
LOOP="$REPO_ROOT/relay/scripts/relay-loop.js"

pass=0; fail=0
ok() { echo "  PASS: $1"; pass=$((pass+1)); }
fail_msg() { echo "  FAIL: $1"; fail=$((fail+1)); }

tmpdir="$(mktemp -d)"; trap 'rm -rf "$tmpdir"' EXIT

# ── Test 1: the dispatched hop no longer contains a jq stage ──────────────────
echo "Test 1: chain-end hop is jq-free"
hop="$(head -5 < <(grep -n -- '--chain-ended' "$LOOP") )"
# Assert on a DISPATCHED pipeline, not on prose: the refused command had classify-repo.sh and
# jq on the SAME line. A comment that merely quotes the old stage (this fix's own rationale
# comment does) must not trip the guard — matching it would make the test unfixable-by-design.
if grep -q 'jq' < <(grep -n 'classify-repo\.sh' "$LOOP" | grep -v '^\s*[0-9]*:\s*//') ; then
  fail_msg "relay-loop.js still pipes the chain-end unit through jq (the refused stage)"
else
  ok "no jq stage on any classify-repo.sh pipeline line"
fi
if grep -q -- '--chain-ended' "$LOOP"; then
  ok "hop passes --chain-ended to classify-repo.sh"
else
  fail_msg "hop does not use --chain-ended: $hop"
fi

# ── Test 2: --chain-ended sets both fields ───────────────────────────────────
echo "Test 2: classify-repo.sh --chain-ended owns the fields"
out="$("$CLASSIFY" --repo dotclaude-skills --path "$REPO_ROOT" --emit unit --chain-ended 'drained: no actionable work' 2>/dev/null || true)"
if [[ -n "$out" ]] && python3 -c '
import json,sys
o=json.loads(sys.argv[1])
assert o.get("chain_ended") is True, "chain_ended not True"
assert o.get("chain_end_reason")=="drained: no actionable work", o.get("chain_end_reason")
' "$out" 2>/dev/null; then
  ok "chain_ended=true and chain_end_reason set verbatim"
else
  fail_msg "--chain-ended did not set the fields"
fi

# ── Test 3: without the flag the unit is unchanged (no new keys) ─────────────
echo "Test 3: default emit unchanged"
out2="$("$CLASSIFY" --repo dotclaude-skills --path "$REPO_ROOT" --emit unit 2>/dev/null || true)"
if [[ -n "$out2" ]] && python3 -c '
import json,sys
o=json.loads(sys.argv[1])
assert "chain_ended" not in o and "chain_end_reason" not in o, "chain_* leaked into a plain emit"
' "$out2" 2>/dev/null; then
  ok "plain --emit unit carries no chain_* keys"
else
  fail_msg "plain --emit unit changed shape"
fi

# ── Tests 4-6: the proxy gate + the refusal log ──────────────────────────────
echo "Tests 4-6: proxy gate and loud refusal"
while IFS= read -r line; do
  case "$line" in
    PASSPY\ *) ok "${line#PASSPY }" ;;
    FAILPY\ *) fail_msg "${line#FAILPY }" ;;
  esac
done < <(PROXY_PATH="$PROXY" LOGF="$tmpdir/proxy2.log" python3 - <<'PY'
import importlib.util, json, os, sys
spec = importlib.util.spec_from_file_location("mp", os.environ["PROXY_PATH"])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
m.LOG_FILE = os.environ["LOGF"]
S = "~/.claude/skills/relay/scripts/"
old = f"{S}classify-repo.sh --repo x --path /tmp --emit unit | jq -c '.' | {S}classify-verdict.sh"
new = f"{S}classify-repo.sh --repo x --path /tmp --emit unit --chain-ended 'r' | {S}classify-verdict.sh"
def body(cmd):
    return json.dumps({"model": m.MECH_MODEL,
                       "messages": [{"role": "user",
                                     "content": "run\n```relay-mech\n" + cmd + "\n```"}]}).encode()
out = []
out.append(("old jq pipeline is REFUSED by the gate", m._command_allowed(old) is False))
out.append(("new two-script pipeline is ALLOWED", m._command_allowed(new) is True))
m._mechanical_command(body(old))
logged = open(os.environ["LOGF"]).read() if os.path.exists(os.environ["LOGF"]) else ""
out.append(("refused mechanical command is LOGGED with its text",
            "mechanical_refused" in logged and "jq" in logged))
before = len(logged)
m._mechanical_command(json.dumps({"model": "claude-sonnet-5", "messages": []}).encode())
after = len(open(os.environ["LOGF"]).read()) if os.path.exists(os.environ["LOGF"]) else 0
out.append(("non-mechanical request logs NOTHING", after == before))
for n, g in out:
    print(("PASSPY " if g else "FAILPY ") + n)
PY
)

echo
echo "Results: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
