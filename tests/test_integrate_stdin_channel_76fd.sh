#!/usr/bin/env bash
# roadmap:76fd — route the integrate hop's FREE-TEXT fields (--summary/--label) through the
# `relay-mech-stdin` payload channel instead of embedding them as inline shell arguments.
#
# WHY (owner decision 2026-08-26, "sanitize now, migrate durably"): the sanitize half landed as
# `17b4e4e0` — `mechArg()` neutralises backtick / `$(` / `<(` / `>(` so a markdown-backticked
# executor summary can no longer 404 its own integrate (id:2e7a root cause). That is explicitly a
# WORKAROUND. The structural problem is that free-text prose is embedded as a shell argument at
# all, so the NEXT free-text field added to a fenced command reintroduces the bug — failing OPEN to
# the real API and 404ing on `model:"bash"`, which reads as an unrelated integrator-parsing bug
# (it cost the 2026-08-26 session's first analysis a wrong diagnosis).
#
# The ratified answer already exists: `relay-mech-stdin` / `STDIN_ALLOWED_SCRIPTS` (id:a05c
# "Option B"). `relay-status-publish.sh` is the reference member — copy that pattern.
#
# DO NOT loosen `_command_allowed()`. That was attempted 2026-08-26 and reverted; it breaks
# `tests/test_mech_stdin_channel_33b2.sh`, and the paranoia is the contract, not the defect.
#
# Assertion map — (1) and (2) are the RED spec; (3) and (4) are GREEN REGRESSION-GUARDS that must
# STAY green through the change (they are why this item is safe to land, not what it builds):
#   (1) RED   — `integrate.sh` is a member of STDIN_ALLOWED_SCRIPTS (scope (b)).
#   (2) RED   — relay-loop.js emits the integrate hop's free text through a ```relay-mech-stdin
#               fence, and no longer passes --summary as an inline mechArg() argument (scope (c)).
#   (3) GUARD — INERTNESS (scope (a)): integrate.sh must never eval/source what arrives on stdin.
#               This is the standing obligation on EVERY STDIN_ALLOWED_SCRIPTS member and the
#               reason admission is a deliberate act. Green today only because integrate.sh does
#               not read stdin at all; it must remain green once it does.
#   (4) GUARD — mechArg() keeps its sanitisation as defence-in-depth AFTER this lands, so a future
#               caller that forgets the channel degrades to cosmetic loss, not a silent 404.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROXY="$ROOT/relay/scripts/mechanical-proxy.py"
LOOP="$ROOT/relay/scripts/relay-loop.js"
INT="$ROOT/relay/scripts/integrate.sh"

fails=0
ok()  { echo "PASS: $*"; }
bad() { echo "FAIL: $*"; fails=$((fails + 1)); }

for f in "$PROXY" "$LOOP" "$INT"; do
  [ -f "$f" ] || { echo "missing $f"; exit 1; }
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ── (1) integrate.sh is admitted to the stdin payload channel ───────────────────────────────
# Anchored to the frozenset body, not a bare file-wide grep: "integrate.sh" appears dozens of
# times in the proxy's prose and allowlist, so an unanchored match would pass vacuously.
stdin_block="$(python3 - "$PROXY" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
m = re.search(r'STDIN_ALLOWED_SCRIPTS\s*=\s*frozenset\(\[(.*?)\]\)', src, re.S)
print(m.group(1) if m else '')
PY
)"
if [ -z "$stdin_block" ]; then
  bad "(1) could not locate the STDIN_ALLOWED_SCRIPTS frozenset in mechanical-proxy.py — the anchor is wrong, so (1) would pass vacuously"
elif grep -q '"integrate\.sh"' <<<"$stdin_block"; then
  ok "76fd (1) integrate.sh is a member of STDIN_ALLOWED_SCRIPTS"
else
  bad "76fd (1) integrate.sh is NOT in STDIN_ALLOWED_SCRIPTS — the stdin fence for this hop is refused by the proxy (scope (b) not done)"
fi

# ── (2) the integrate hop carries its free text on stdin, not as an inline argument ──────────
# The hop is built at relay-loop.js's integrate() — it currently emits a bare ```relay-mech fence
# with --summary <quoted prose> inline. After this item it must emit the ```relay-mech-stdin DATA
# fence alongside, and must NOT pass the free-text summary as a shell argument.
if grep -q 'relay-mech-stdin' "$LOOP"; then
  hop="$(python3 - "$LOOP" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
# The integrate hop's emission region: from the integrateArgs construction to the fence it builds.
m = re.search(r'integrateArgs\s*=\s*\[(.{0,4000}?)integrate\.sh', src, re.S)
print(m.group(1) if m else '')
PY
)"
  if [ -z "$hop" ]; then
    bad "(2) could not locate the integrate hop's integrateArgs..fence region in relay-loop.js — the anchor is wrong, so (2) would pass vacuously"
  elif grep -q "'--summary', mechArg(" <<<"$hop"; then
    bad "76fd (2) the integrate hop still passes --summary as an inline mechArg() shell argument — free-text prose is still embedded in the fenced command (scope (c) not done)"
  else
    ok "76fd (2) the integrate hop no longer passes --summary inline"
  fi
else
  bad "76fd (2) relay-loop.js contains no relay-mech-stdin fence at all — the payload channel is not wired for any hop here (scope (c) not done)"
fi

# ── (3) GREEN REGRESSION-GUARD — integrate.sh treats stdin as INERT DATA ─────────────────────
# Behavioural: feed a payload whose text contains a command substitution and a backtick command,
# and assert nothing executed. integrate.sh is invoked with no arguments so it fails fast at its
# own arg validation — which is precisely the window in which an eval-on-startup would fire.
SENTINEL="$TMP/pwned"
payload='summary: normal prose $(touch '"$SENTINEL"') and `touch '"$SENTINEL"'` embedded'
printf '%s\n' "$payload" | timeout 30 "$INT" >/dev/null 2>&1
if [ -e "$SENTINEL" ]; then
  bad "76fd (3) INERTNESS VIOLATED — a command substitution arriving on integrate.sh's stdin EXECUTED (sentinel created). integrate.sh must not be in STDIN_ALLOWED_SCRIPTS until this is false."
else
  ok "76fd (3) stdin payload with \$(...) and backticks did not execute (inert)"
fi

# Static companion: no stdin-derived variable is eval'd or sourced. integrate.sh's existing
# `eval "v=\${$req}"` (arg validation, internal names only) and `. "$LIB_PRIVATE_REMOTE"` (a
# literal library path) are both legitimate and are NOT stdin-derived — this check targets the
# specific hazard of routing stdin into eval/source.
if grep -nE '(eval|source|^[[:space:]]*\.)[^#]*\$\{?(stdin|STDIN|payload|PAYLOAD|summary_in|SUMMARY_IN)' "$INT" >/dev/null 2>&1; then
  bad "76fd (3b) a stdin-derived variable reaches eval/source in integrate.sh"
else
  ok "76fd (3b) no stdin-derived variable reaches eval/source in integrate.sh"
fi

# ── (4) GREEN REGRESSION-GUARD — mechArg keeps its sanitisation ──────────────────────────────
# Defence-in-depth per the owner's decision: KEEP this even after the channel lands.
marg="$(python3 - "$LOOP" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
m = re.search(r'const mechArg\s*=(.*?\.trim\(\))', src, re.S)
print(m.group(1) if m else '')
PY
)"
if [ -z "$marg" ]; then
  bad "(4) could not locate mechArg's definition in relay-loop.js — the anchor is wrong, so (4) would pass vacuously"
else
  # Match the REGEX LITERALS as they appear in the JS source (`<(` is written `/<\(/g` there),
  # not the raw two-character sequences — those never appear literally and would always "miss".
  missing=""
  for tok in '/`/g' '/\$\(/g' '/<\(/g' '/>\(/g'; do
    grep -qF -- "$tok" <<<"$marg" || missing="$missing $tok"
  done
  if [ -n "$missing" ]; then
    bad "76fd (4) mechArg no longer neutralises:$missing — the id:2e7a sanitisation was removed instead of kept as defence-in-depth"
  else
    ok "76fd (4) mechArg still neutralises backtick, \$(, <( and >( (defence-in-depth retained)"
  fi
fi

[ "$fails" -eq 0 ] || { echo "$fails assertion(s) failed"; exit 1; }
echo "All integrate-stdin-channel tests passed (76fd)."
