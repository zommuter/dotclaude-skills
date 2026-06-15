#!/usr/bin/env bash
# roadmap:da26 — probe-fable.sh: Fable-availability probe cache manager.
# Hermetic: mktemp cache, PROBE_CACHE override, no network/model. Verifies the four
# states the front door (SKILL.md step 0) reads: fresh-available, fresh-unavailable,
# stale (>2h), absent — plus the exit-code contract (0 = fresh decision, 1 = re-probe).

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$SRC_DIR/fables-turn/scripts/probe-fable.sh"
TMPDIR_T="$(mktemp -d)"
export PROBE_CACHE="$TMPDIR_T/fable-probe.json"
trap 'rm -rf "$TMPDIR_T"' EXIT

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SCRIPT" ]] || fail "probe-fable.sh not found/executable at $SCRIPT"

# check_expect DESC EXPECTED_OUTPUT EXPECTED_RC
check_expect() {
  local desc="$1" expout="$2" exprc="$3"
  local out rc
  out="$("$SCRIPT" check 2>/dev/null)" && rc=0 || rc=$?
  if [[ "$out" == "$expout" && "$rc" -eq "$exprc" ]]; then
    pass "$desc"
  else
    fail "$desc (expected '$expout' rc=$exprc, got '$out' rc=$rc)"
  fi
}

# ── absent: no cache file yet → re-probe ──
rm -f "$PROBE_CACHE"
check_expect "absent cache → absent / exit 1" "absent" 1

# ── fresh-available: cache <2h old, available=true → skip probe, use Fable ──
"$SCRIPT" set true "$(date -Iseconds)" >/dev/null
check_expect "fresh available (now) → fresh-available / exit 0" "fresh-available" 0

# ── fresh-unavailable: cache <2h old, available=false → skip probe, use Opus ──
"$SCRIPT" set false "$(date -Iseconds)" >/dev/null
check_expect "fresh unavailable (now) → fresh-unavailable / exit 0" "fresh-unavailable" 0

# ── boundary: just under 2h still fresh ──
"$SCRIPT" set true "$(date -Iseconds -d '110 minutes ago')" >/dev/null
check_expect "110 min old → still fresh-available / exit 0" "fresh-available" 0

# ── stale: cache >2h old → re-probe ──
"$SCRIPT" set true "$(date -Iseconds -d '3 hours ago')" >/dev/null
check_expect "3h old → stale / exit 1" "stale" 1

# ── malformed cache → treated as absent (re-probe), never a crash ──
echo 'not json' > "$PROBE_CACHE"
check_expect "malformed cache → absent / exit 1" "absent" 1

# ── set persists the available bool + timestamp verbatim ──
"$SCRIPT" set false "2026-06-15T08:00:00+02:00" >/dev/null
grep -q '"available": false' "$PROBE_CACHE" || fail "set false did not write available=false"
grep -q '2026-06-15T08:00:00' "$PROBE_CACHE" || fail "set did not persist the supplied timestamp"
pass "set writes {available, checked} with the supplied timestamp"

# ── set rejects a non-boolean value (exit 2) ──
rc=0; "$SCRIPT" set maybe 2>/dev/null || rc=$?
[[ "$rc" -eq 2 ]] || fail "set with non-boolean should exit 2, got $rc"
pass "set rejects non-boolean value (exit 2)"

# ── unknown subcommand → usage (exit 2) ──
rc=0; "$SCRIPT" bogus 2>/dev/null || rc=$?
[[ "$rc" -eq 2 ]] || fail "unknown subcommand should exit 2, got $rc"
pass "unknown subcommand exits 2"
