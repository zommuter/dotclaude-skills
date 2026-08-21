#!/usr/bin/env bash
# roadmap:74e7 — Makefile's RELAY_QUOTA_DECAY_7D default must agree with relay/SKILL.md's
# RISING-schedule doctrine (START < END), and `make install-relay-env` must apply it only
# into a caller-supplied SETTINGS_JSON, never the real ~/.claude/settings.json.
#
# Why this exists: Makefile:210 pinned a FALLING schedule (0.30:0.08, dated "user policy
# 2026-06-16"), while relay/SKILL.md's knob table documents a RISING schedule as correct
# (weekly quota is use-it-or-lose-it; a falling cap false-stopped a healthy run at 24%
# 7d-util with ~22h to reset on 2026-06-22, forfeiting 76%). Every `make install` on every
# machine re-applies the Makefile default via install-relay-env, so a stale falling default
# silently regresses a machine that had already been hand-corrected.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MK="$SRC_DIR/Makefile"
SKILL="$SRC_DIR/relay/SKILL.md"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$MK" ]] || fail "Makefile not found at $MK"
[[ -f "$SKILL" ]] || fail "relay/SKILL.md not found at $SKILL"

# ── extract RELAY_QUOTA_DECAY_7D=START:END from the Makefile's RELAY_ENV_DEFAULTS ──
mk_pair="$(head -1 < <(grep -oE 'RELAY_QUOTA_DECAY_7D=[0-9.]+:[0-9.]+' "$MK") || true)"
[[ -n "$mk_pair" ]] || fail "could not find RELAY_QUOTA_DECAY_7D=START:END in Makefile"
mk_val="${mk_pair#RELAY_QUOTA_DECAY_7D=}"
mk_start="${mk_val%%:*}"
mk_end="${mk_val##*:}"
pass "Makefile RELAY_QUOTA_DECAY_7D=$mk_start:$mk_end"

# START < END — a falling (or equal) schedule fails loudly.
awk -v s="$mk_start" -v e="$mk_end" 'BEGIN { exit !(s < e) }' \
  || fail "Makefile schedule is NOT rising (START=$mk_start, END=$mk_end) — must satisfy START < END"
pass "Makefile schedule is RISING (START < END)"

# ── SKILL.md doctrine must still document the RISING direction ──
grep -q "RISE toward reset" "$SKILL" \
  || fail "relay/SKILL.md no longer documents the RISING-toward-reset doctrine (drifted from Makefile default)"
grep -qE '\bSTART < END\b' "$SKILL" \
  || fail "relay/SKILL.md no longer states the START < END rule explicitly"
pass "relay/SKILL.md still documents the RISING (START < END) doctrine"

# ── Makefile comment names the supersession, so a reader sees the old policy was
# deliberately overridden rather than silently overwritten ──
grep -q "SUPERSEDED" "$MK" || fail "Makefile RELAY_ENV_DEFAULTS comment does not name a supersession"
grep -q "id:74e7" "$MK" || fail "Makefile RELAY_ENV_DEFAULTS comment does not cite id:74e7"
pass "Makefile comment names the supersession + id:74e7"

# ── behavioural: `make DEST_DIR=<tmp> install-relay-env` writes the rising default into a
# STAGED settings file, never the real ~/.claude/settings.json ──
TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT
STAGED_SETTINGS="$TMPDIR_TEST/settings.json"
echo '{}' > "$STAGED_SETTINGS"

REAL_SETTINGS="$HOME/.claude/settings.json"
real_hash_before=""
[[ -f "$REAL_SETTINGS" ]] && real_hash_before="$(sha256sum "$REAL_SETTINGS" | awk '{print $1}')"

make -C "$SRC_DIR" SETTINGS_JSON="$STAGED_SETTINGS" install-relay-env >/tmp/74e7-install-relay-env.$$.log 2>&1 \
  || fail "make install-relay-env failed against staged settings: $(cat /tmp/74e7-install-relay-env.$$.log)"
rm -f "/tmp/74e7-install-relay-env.$$.log"

staged_val="$(python3 -c "import json,sys; print(json.load(open('$STAGED_SETTINGS'))['env'].get('RELAY_QUOTA_DECAY_7D',''))")"
[[ "$staged_val" == "$mk_val" ]] || fail "staged settings.json got RELAY_QUOTA_DECAY_7D=$staged_val, expected $mk_val"
pass "make DEST_DIR-style SETTINGS_JSON override wrote RELAY_QUOTA_DECAY_7D=$staged_val into the STAGED file"

if [[ -f "$REAL_SETTINGS" ]]; then
  real_hash_after="$(sha256sum "$REAL_SETTINGS" | awk '{print $1}')"
  [[ "$real_hash_before" == "$real_hash_after" ]] || fail "the REAL ~/.claude/settings.json was modified — must never happen in a hermetic test"
fi
pass "real ~/.claude/settings.json untouched"

echo "ALL PASS: id:74e7 quota-decay default agrees with SKILL.md, hermetic install-relay-env verified"
