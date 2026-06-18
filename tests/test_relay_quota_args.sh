#!/usr/bin/env bash
# roadmap:b841 — relay-loop.js must normalize a NESTED quota-threshold arg so a per-bucket
# override isn't silently dropped. Static-structural, matching test_relay_loop_structure.sh.
#
# Bug (observed 2026-06-18): the front door passed quota caps as a nested object
#   args.quotaThresholds = { SEVEN_DAY: 0.70, SEVEN_DAY_SONNET: 0.70 }
# but relay-loop.js only forwards FLAT keys (RELAY_QUOTA_THRESHOLD_SEVEN_DAY[_SONNET])
# into the gate env (envPairs near line ~901). The nested map was never read, so a user
# "raise 7d cap to 70%" directive had ZERO effect twice and the standing decay cap governed.
#
# Fix: in the args-normalization block (near `const A =`, where fableDown is normalized),
# accept a nested `quotaThresholds` map and fold each entry into the corresponding flat
# RELAY_QUOTA_THRESHOLD_<BUCKET> key (flat key wins if both present). Then envPairs forwards it.
#
# RED until id:b841 is implemented (checkbox in ROADMAP.md still unticked → EXPECTED-RED).

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JS="$SRC_DIR/relay/scripts/relay-loop.js"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$JS" ]] || fail "relay-loop.js not found at $JS"
pass "relay-loop.js exists"

# (1) The nested map name must be referenced at all (the normalization reads A.quotaThresholds).
grep -q "quotaThresholds" "$JS" \
  || fail "relay-loop.js never references args.quotaThresholds — nested override still silently dropped (id:b841)"
pass "quotaThresholds nested map referenced"

# (2) The fold must map each nested bucket entry into the flat RELAY_QUOTA_THRESHOLD_<BUCKET>
#     key. Assert the flat-key prefix is constructed from the nested entry (not just the five
#     literal flat keys already in envPairs). We look for the canonical flat-key prefix being
#     built dynamically near a quotaThresholds reference.
awk '
  /quotaThresholds/ { window = 12 }
  window > 0 {
    if (/RELAY_QUOTA_THRESHOLD_/) found = 1
    window--
  }
  END { exit found ? 0 : 1 }
' "$JS" \
  || fail "no RELAY_QUOTA_THRESHOLD_<bucket> fold near the quotaThresholds read — nested map not normalized to flat keys (id:b841)"
pass "nested quotaThresholds entries folded into flat RELAY_QUOTA_THRESHOLD_<bucket> keys"

# (3) Flat key wins if both present (explicit per-bucket override beats the nested default and
#     the decay). The fold must NOT clobber an already-set flat key. We assert the fold is
#     guarded (writes only when the flat key is unset), via an `=== undefined` / `?? ` /
#     `!(... in ...)` style guard appearing in the same window as the fold.
awk '
  /quotaThresholds/ { window = 14 }
  window > 0 {
    if (/=== undefined/ || /!== undefined/ || /\?\?/ || / in A/ || /in A\)/) guarded = 1
    window--
  }
  END { exit guarded ? 0 : 1 }
' "$JS" \
  || fail "fold does not guard against clobbering an explicit flat key (flat must win over nested, id:b841)"
pass "fold guards the flat key (explicit per-bucket override wins over nested)"
