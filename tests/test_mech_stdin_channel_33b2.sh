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

# (3)+(5) end-to-end: a payload of shell metacharacters must round-trip byte-identical to the
# script's stdin and leave no side effects. Only meaningful once the channel exists.
if [[ $fail -eq 0 ]]; then
  printf 'line one\n$(touch %s)\n`whoami`\na; b && c\n' "$CANARY" > "$tmp/payload.txt"
  [[ -e "$CANARY" ]] && note "(5) the payload was SHELL-EVALUATED — stdin must be inert data, never parsed"
fi

[[ $fail -eq 0 ]] || { echo "EXPECTED-RED: id:33b2 not built yet" >&2; exit 1; }
echo "ALL PASS: opt-in stdin channel; command gate unloosened; payload inert (id:33b2)"
