#!/usr/bin/env bash
# roadmap:482d — deterministic STOP-sentinel handling: relay/scripts/stop-sentinel.sh
# implements the discover-prelude's step-8 semantics (check / countdown / consume) as
# ONE atomic script call, and logs a timestamped line when it consumes the sentinel.
#
# WHY (TODO id:482d, observed 2026-07-01): consumption lived as prose instruction 8 of
# the prelude prompt, so the `rm` landed at whatever point the agent reached it — a
# fired user-stop was observed still on disk minutes after the workflow returned; a
# next pool launched in that lag would be false-stopped. One script call dissolves the
# timing-variance class; the consume log is the observe-instrumentation the item's
# OBSERVE downgrade asked for.
#
# RED until stop-sentinel.sh lands and the prelude references it. Hermetic: mktemp
# sentinel + log paths, no ~/.config touch.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SENTINEL_SH="$REPO_ROOT/relay/scripts/stop-sentinel.sh"
LOOP_JS="$REPO_ROOT/relay/scripts/relay-loop.js"

pass=0; fail=0
ok() { echo "  PASS: $1"; pass=$((pass+1)); }
fail_msg() { echo "  FAIL: $1"; fail=$((fail+1)); }

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
stopfile="$tmpdir/STOP"
logfile="$tmpdir/consume.log"

if [[ ! -x "$SENTINEL_SH" ]]; then
  echo "FAIL: relay/scripts/stop-sentinel.sh missing or not executable"
  exit 1
fi

run_check() { RELAY_STOP_SENTINEL_LOG="$logfile" "$SENTINEL_SH" check --path "$stopfile"; }

json_field() {  # json_field <json> <field> → python-printed value
  python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get(sys.argv[2]))' "$1" "$2"
}

# ── Test 1: absent file → stopRequested false ─────────────────────────────────
echo "Test 1: absent sentinel"
out="$(run_check)"
if [[ "$(json_field "$out" stopRequested)" == "False" ]]; then
  ok "absent → stopRequested:false"
else
  fail_msg "absent file: expected stopRequested:false, got: $out"
fi

# ── Test 2: countdown N≥1 → decrement, keep file, no stop ─────────────────────
echo "Test 2: countdown decrement"
printf '3' > "$stopfile"
out="$(run_check)"
if [[ "$(json_field "$out" stopRequested)" == "False" ]]; then
  ok "countdown → stopRequested:false"
else
  fail_msg "countdown: expected stopRequested:false, got: $out"
fi
if [[ -f "$stopfile" && "$(cat "$stopfile")" == "2" ]]; then
  ok "countdown 3 → file rewritten to 2"
else
  fail_msg "countdown: file should hold '2', has '$(cat "$stopfile" 2>/dev/null || echo GONE)'"
fi
rm -f "$stopfile"

# ── Test 3: plain stop (empty file) → consume + timestamped log ───────────────
echo "Test 3: plain-stop consume"
: > "$stopfile"
out="$(run_check)"
if [[ "$(json_field "$out" stopRequested)" == "True" ]]; then
  ok "empty sentinel → stopRequested:true"
else
  fail_msg "empty sentinel: expected stopRequested:true, got: $out"
fi
if [[ ! -e "$stopfile" ]]; then
  ok "sentinel consumed (file gone) in the same call"
else
  fail_msg "sentinel still on disk after a fired stop (the id:482d lag class)"
fi
# ISO-8601-ish timestamp (YYYY-MM-DDTHH:MM) in the consume log
if [[ -f "$logfile" ]] && grep -qE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}' "$logfile"; then
  ok "consume logged with a timestamp"
else
  fail_msg "no timestamped consume line in $logfile"
fi

# ── Test 4: stale '0' → consume (stop-now semantics) ──────────────────────────
echo "Test 4: '0' content consumes"
printf '0' > "$stopfile"
out="$(run_check)"
if [[ "$(json_field "$out" stopRequested)" == "True" && ! -e "$stopfile" ]]; then
  ok "'0' → stopRequested:true + consumed"
else
  fail_msg "'0': expected consume+stop, got: $out (file present: $([[ -e "$stopfile" ]] && echo yes || echo no))"
fi

# ── Test 5: prelude step 8 delegates to the script ────────────────────────────
echo "Test 5: relay-loop.js prelude references stop-sentinel.sh"
if grep -q 'stop-sentinel.sh' "$LOOP_JS"; then
  ok "prelude step delegates sentinel handling to stop-sentinel.sh"
else
  fail_msg "relay-loop.js does not reference stop-sentinel.sh (step 8 still prose-only)"
fi

echo ""
echo "Results: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
