#!/usr/bin/env bash
# roadmap:c057 — capped-run.sh runs a command under a cgroup scope and FAILS CLOSED.
#
# Hermetic: never runs a real benchmark, never touches ~/.config or the network. The
# systemd-run cases are SKIPPED (not failed) when systemd-run is unavailable, so the suite
# stays green on a host without a user manager; the refusal case is the one that must hold
# everywhere, and it is tested by hiding systemd-run behind a stub PATH.
set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/relay/scripts/capped-run.sh"
fails=0
ok()   { echo "ok: $*"; }
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }

[ -x "$SCRIPT" ] || { echo "ERROR: capped-run.sh not executable at $SCRIPT"; exit 3; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- (a) FAILS CLOSED: no systemd-run on PATH => exit 3, never a bare uncapped run --------
# This is the single most important assertion in the file. A silent fallback to `bash -c`
# would restore the uncapped-recipe bug invisibly, which is exactly what capped-run exists
# to prevent -- so "refuses loudly" matters more than "runs".
# Invoke through `bash "$SCRIPT"` rather than executing it, so an empty PATH cannot break
# the `#!/usr/bin/env bash` shebang lookup and make this fail for the wrong reason (it did,
# first time: exit 127 "env: 'bash': No such file or directory", which would have been a
# green-looking non-zero that proved nothing about the refusal).
out="$(PATH="" "$BASH" "$SCRIPT" -t 10 -- /bin/true 2>&1)"; rc=$?
if [ "$rc" -eq 3 ]; then ok "(a) refuses with exit 3 when systemd-run is absent"
else fail "(a) expected exit 3 without systemd-run, got $rc"; fi
case "$out" in
  *REFUSING*) ok "(a) refusal names itself on stderr" ;;
  *) fail "(a) refusal message did not say REFUSING (got: $out)" ;;
esac

# --- (b) argument validation ------------------------------------------------------------
"$SCRIPT" -t 10 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "(b) no command => exit 2" || fail "(b) expected exit 2 for no command, got $rc"

"$SCRIPT" -t notanumber -- /bin/true >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "(b) non-numeric -t => exit 2" || fail "(b) expected exit 2 for bad -t, got $rc"

"$SCRIPT" -t 0 -- /bin/true >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "(b) zero -t => exit 2" || fail "(b) expected exit 2 for -t 0, got $rc"

# --- (c) live cgroup behaviour (skipped when systemd-run is unavailable) -----------------
if ! command -v systemd-run >/dev/null 2>&1 || ! systemd-run --user --scope -q true >/dev/null 2>&1; then
  echo "skip: systemd-run --user unavailable here; (c) live-scope cases not run"
else
  "$SCRIPT" -t 30 -- /bin/true >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 0 ] && ok "(c) success passes through exit 0" || fail "(c) expected 0, got $rc"

  "$SCRIPT" -t 30 -- bash -c 'exit 42' >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 42 ] && ok "(c) exit code passes through unchanged" || fail "(c) expected 42, got $rc"

  # The wall-clock ceiling fires. GNU timeout reports 124.
  "$SCRIPT" -t 1 -- sleep 20 >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 124 ] && ok "(c) wall-clock ceiling fires with 124" || fail "(c) expected 124 on timeout, got $rc"

  # The memory cap fires and the kill is CONTAINED. 137 = 128+SIGKILL.
  # Run in a subshell with job-control messages suppressed: the kernel OOM kill makes the
  # PARENT shell print "Killed", which is noise in the suite output, not a test result.
  rc=0
  { ( "$SCRIPT" -m 200M -t 60 -- python3 -c '
x = bytearray(600*1024*1024)
for i in range(0, len(x), 4096): x[i] = 1
' >/dev/null 2>&1 ) || rc=$?; } 2>/dev/null
  [ "$rc" -eq 137 ] && ok "(c) memory cap kills the scope with 137" || fail "(c) expected 137 on cap breach, got $rc"
fi

# --- (d) the daemon calls it, rather than a bare `bash -c` -------------------------------
DAEMON="$(dirname "$SCRIPT")/mechanical-daemon.sh"
if grep -qE '^\s*if\s+bash -c "\$cmd_str"' "$DAEMON" 2>/dev/null; then
  fail "(d) mechanical-daemon.sh still runs the recipe as a bare 'bash -c' -- the cap is bypassed"
else
  ok "(d) mechanical-daemon.sh no longer runs a bare 'bash -c'"
fi
grep -q 'CAPPED=' "$DAEMON" && ok "(d) daemon references capped-run.sh" \
  || fail "(d) daemon does not reference capped-run.sh"
grep -q 'failed=\$failed' "$DAEMON" && ok "(d) daemon reports a failed= count" \
  || fail "(d) daemon summary omits failed= (a cap kill would be invisible)"

[ "$fails" -eq 0 ] && { echo "PASS test_capped_run_c057"; exit 0; }
echo "$fails assertion(s) failed"; exit 1
