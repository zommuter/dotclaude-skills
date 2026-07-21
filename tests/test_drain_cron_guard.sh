#!/usr/bin/env bash
# roadmap:23d8 — cron-safety guard for the apex-drain entry.
#
# Spec (meeting docs/meeting-notes/2026-07-21-0911-relay-drain-apex-tasklist.md D6;
# TODO id:23d8, children-of:2b23): the apex-drain entry must REFUSE to start when it is
# not attached to an interactive terminal (`! test -t 0`) UNLESS an explicit override is
# passed — an enforce-not-document guard so a stray cron/at invocation of the supervised
# apex drain fails loudly instead of running blind.
#
# Contract of relay/scripts/drain-cron-guard.sh:
#   - stdin IS a tty                         → exit 0 (proceed)
#   - stdin NOT a tty, no override            → exit nonzero + LOUD stderr (names the override)
#   - stdin NOT a tty, `--allow-cron` flag    → exit 0 (proceed)
#   - stdin NOT a tty, DRAIN_ALLOW_CRON=1 env  → exit 0 (proceed)
#
# Hermetic: no repo, no network, no ~/.claude. The tty branch is exercised with a real
# pty allocated via python3's pty module (a harness dependency); the non-tty branches
# redirect stdin from /dev/null.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GUARD="$SRC_DIR/relay/scripts/drain-cron-guard.sh"

pass=0 fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); return 0; }
bad() { echo "BAD: $*"; fail=$((fail+1)); return 0; }

[[ -f "$GUARD" ]] || { echo "FAIL: drain-cron-guard.sh not found at $GUARD"; exit 1; }
[[ -x "$GUARD" ]] || bad "23d8: guard is not executable (chmod +x)"

# Run the guard with a REAL pty on stdin (fd 0 is a tty).
run_tty() { # extra args...
  python3 - "$GUARD" "$@" <<'PY'
import os, pty, sys
status = pty.spawn(["bash", *sys.argv[1:]])
sys.exit(os.waitstatus_to_exitcode(status))
PY
}

# ── (1) non-tty, no override → refuse (nonzero) + loud stderr ──
err="$(bash "$GUARD" </dev/null 2>&1 1>/dev/null || true)"
rc=$(bash "$GUARD" </dev/null >/dev/null 2>/dev/null; echo $?)
[[ "$rc" -ne 0 ]] && ok "23d8: non-tty without override exits nonzero (rc=$rc)" \
                  || bad "23d8: non-tty without override exited 0 — must refuse"
grep -qiE 'tty|terminal|cron|--allow-cron|override' <<<"$err" \
  && ok "23d8: refusal names the override / tty condition on stderr" \
  || bad "23d8: refusal stderr not loud/actionable. Output: $err"

# ── (2) non-tty WITH --allow-cron flag → proceed (exit 0) ──
rc=$(bash "$GUARD" --allow-cron </dev/null >/dev/null 2>&1; echo $?)
[[ "$rc" -eq 0 ]] && ok "23d8: non-tty with --allow-cron proceeds (exit 0)" \
                  || bad "23d8: --allow-cron did not proceed (rc=$rc)"

# ── (3) non-tty WITH DRAIN_ALLOW_CRON=1 env → proceed (exit 0) ──
rc=$(DRAIN_ALLOW_CRON=1 bash "$GUARD" </dev/null >/dev/null 2>&1; echo $?)
[[ "$rc" -eq 0 ]] && ok "23d8: non-tty with DRAIN_ALLOW_CRON=1 proceeds (exit 0)" \
                  || bad "23d8: DRAIN_ALLOW_CRON=1 did not proceed (rc=$rc)"

# ── (4) interactive tty (no override) → proceed (exit 0) ──
if run_tty >/dev/null 2>&1; then
  ok "23d8: interactive tty proceeds without an override"
else
  bad "23d8: interactive tty was refused — must proceed (rc=$?)"
fi

echo "---- $pass ok, $fail bad ----"
[[ "$fail" -eq 0 ]] || exit 1
echo "ALL PASS: drain cron-safety guard (roadmap:23d8)"
