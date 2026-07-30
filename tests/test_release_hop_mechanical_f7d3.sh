#!/usr/bin/env bash
# roadmap:f7d3
# RED SPEC for id:f7d3 — "Mechanize the `release:` hop — haiku -> two `model:'bash'`
# dispatches (no proxy change needed)".
#
# Defect: releaseLease() in relay/scripts/relay-loop.js used to spend one Haiku call
# running TWO (or three, with the intensive branch) `&&`-joined commands
# (`claim.sh release ...` [`&& claim.sh release resource:... `] `&& heartbeat.sh beat ...`).
# `mechanical-proxy.py`'s `_command_allowed()` refuses any unquoted sequence operator
# (`&&`/`;`/newline), so that bundled prompt could never pass a single `model:'bash'`
# fence — a refused command fails OPEN to the real model, and `"bash"` is not a real
# model (id:6b35 fail-CLOSED hazard: this would 404 every release).
#
# Fix: split into SEPARATE model:'bash' dispatches, one fenced command each. This spec
# asserts (1) the dispatch sites in relay-loop.js are `model: 'bash'`, not `haiku`; (2) each
# fenced command string is, standalone, ACCEPTED by the real `_command_allowed()` predicate
# (driven directly, mirroring tests/test_mechanical_proxy.sh); (3) the intensive branch emits
# its own separate dispatch rather than an `&&`-joined command.
#
# RED until id:f7d3 lands: today releaseLease() dispatches ONE `model:'haiku'` call whose
# body is a multi-command `&&` bundle.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOOP="$ROOT/relay/scripts/relay-loop.js"
MODULE="$ROOT/relay/scripts/mechanical-proxy.py"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$LOOP" ]]   || fail "relay-loop.js not found: $LOOP"
[[ -f "$MODULE" ]] || fail "mechanical-proxy.py not found: $MODULE"

# --- (1) STRUCTURAL: every release:-labelled dispatch in releaseLease() must be model:'bash' ---
# Extract the releaseLease() function body (from its `async function releaseLease` header to
# the next top-level `async function` / `function` declaration) and check every `label:
# `release:` dispatch inside it declares model:'bash'.
body="$(awk '/^async function releaseLease\(/{flag=1} flag{print} flag && /^async function [A-Za-z]/ && !/releaseLease/{if(NR>1 && seen) exit} /^async function releaseLease\(/{seen=1}' "$LOOP")"
[[ -n "$body" ]] || fail "(1) could not locate releaseLease() in $LOOP"

label_lines="$(printf '%s\n' "$body" | grep -nE "label:.*release:" || true)"
[[ -n "$label_lines" ]] || fail "(1) no release: labelled dispatch found inside releaseLease()"

while IFS= read -r line; do
  printf '%s\n' "$line" | grep -qE "model: *MECH_MODEL" \
    || fail "(1) a release: dispatch is not model: MECH_MODEL (id:4239 bash-by-default) — line: $line"
done <<< "$label_lines"
pass "(1) every release:-labelled dispatch in releaseLease() is model:'bash'"

# --- (1b) no single dispatch bundles claim.sh release AND heartbeat.sh beat via && ---------------
printf '%s\n' "$body" | grep -qE '&&.*heartbeat\.sh|heartbeat\.sh.*&&' \
  && fail "(1b) found an && -joined claim.sh/heartbeat.sh bundle — must be separate dispatches" \
  || pass "(1b) claim.sh release and heartbeat.sh beat are not && -joined in one command"

# --- (1c) the intensive resource release is its own dispatch, not && -chained onto the repo release
printf '%s\n' "$body" | grep -qE 'resource:.*&&|&&.*resource:' \
  && fail "(1c) intensive resource release is && -chained onto another command" \
  || pass "(1c) intensive resource release (if present) is not && -chained"

# --- (2) each fenced command, standalone, passes the real _command_allowed() predicate ----------
python3 - "$MODULE" <<'PYEOF'
import importlib.util
import sys

path = sys.argv[1]
spec = importlib.util.spec_from_file_location("mechanical_proxy", path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

cmds = [
    "~/.claude/skills/relay/scripts/claim.sh release myrepo --run relay-20260728-1000-1",
    "~/.claude/skills/relay/scripts/claim.sh release resource:local-llm --run relay-20260728-1000-1",
    "~/.claude/skills/relay/scripts/heartbeat.sh beat relay-20260728-1000-1",
]
failures = []
for c in cmds:
    if not mod._command_allowed(c):
        failures.append(c)
    else:
        print(f"PASS: (2) _command_allowed accepts standalone fence: {c!r}")

if failures:
    for c in failures:
        print(f"FAIL: (2) _command_allowed refused a standalone release/heartbeat fence: {c!r}")
    sys.exit(1)
PYEOF

echo "ALL PASS: release: hop mechanized to separate model:'bash' dispatches (id:f7d3)"
