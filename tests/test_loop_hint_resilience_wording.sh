#!/usr/bin/env bash
# roadmap:bde8 — the /relay loop-hint nudge must NOT claim unattended OUTAGE/session-kill
# resilience for /loop. /loop (and an in-session cron) dies WITH the session: it is resilient
# only to relay's OWN early-exit (quota/seatbelt) within a LIVE session, not to the session or
# process being killed (the exact failure a "babysitter" exists to guard — see
# docs/meeting-notes/2026-06-22-1546-relay-outage-resilience.md, id:98f0/e149). The pre-fix
# nudge promised "unattended multi-hour resilience" and "a tick missed during an outage is
# recovered by the next one" — false for a session/process kill. This test is RED until the
# wording is corrected (id:bde8). Hermetic: forces the print path with a stale stamp under
# mktemp; never touches ~/.config or the network.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HINT="$SRC_DIR/relay/scripts/loop-hint.sh"
pass=0 fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); return 0; }
bad() { echo "BAD: $*"; fail=$((fail+1)); return 0; }
[[ -x "$HINT" ]] || { echo "FAIL: loop-hint.sh missing/not executable"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# Force the print branch: first run in a fresh state dir (no prior stamp → looks standalone).
out="$(RELAY_STATE_DIR="$TMP/state" "$HINT" 2>&1 || true)"
[[ -n "$out" ]] && ok "nudge prints on a standalone (first) run" || bad "nudge printed nothing on first run"

# Correctness property: the nudge must not imply /loop survives an outage / session kill.
if grep -qiE 'recover|recovered|resilien|survive|missed during an outage' <<<"$out"; then
  bad "nudge still claims outage/session-kill resilience for /loop (id:bde8): $(grep -iE 'recover|recovered|resilien|survive|missed during an outage' <<<"$out" | head -1)"
else
  ok "nudge no longer claims /loop is outage/session-kill resilient (id:bde8)"
fi

# It should still positively mention that /loop only helps with relay's own early-exit
# (quota/seatbelt) within a LIVE session — so the nudge stays useful, not just deleted.
if grep -qiE 'quota|seatbelt|early.?exit|within a live session|same session' <<<"$out"; then
  ok "nudge correctly scopes /loop to relay's own early-exit within a live session"
else
  bad "nudge does not state the corrected scope (early-exit within a live session) (id:bde8)"
fi

echo "test_loop_hint_resilience_wording: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
