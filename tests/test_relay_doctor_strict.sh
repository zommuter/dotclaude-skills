#!/usr/bin/env bash
# roadmap:a883 — relay-doctor --strict (opt-in nonzero gate) + quota-config
# sanity check (RELAY_QUOTA_DECAY_7D direction, threshold bounds).
#
# Tests:
#   (1) relay-doctor.sh accepts --strict flag (no "unknown flag" error)
#   (2) Without --strict: exits 0 even when issues exist (report-only preserved)
#   (3) With --strict:    exits nonzero when issues exist
#   (4) With --strict:    exits 0 when no issues (clean fixture)
#   (5) quota-config sanity: RELAY_QUOTA_DECAY_7D with START >= END is flagged
#   (6) quota-config sanity: valid START:END (START < END, both in (0,1]) is clean
#   (7) quota-config sanity: unset RELAY_QUOTA_DECAY_7D → no complaint
#   (8) quota-config sanity: bad format → flagged

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SH="$ROOT/relay/scripts/relay-doctor.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$SH" ]] || fail "relay-doctor.sh not found at $SH"
[[ -x "$SH" ]] || fail "relay-doctor.sh not executable"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# --- build a fixture git repo that relay-doctor can scan ----------------------
REPO="$tmp/fixture"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email t@e.st
git -C "$REPO" config user.name t

# A clean ROADMAP (all items well-formed; cross-ledger agrees; no drift)
printf '# ROADMAP\n\n## Items\n\n- [ ] clean routine item [ROUTINE] <!-- id:aa01 -->\n' \
  > "$REPO/ROADMAP.md"
printf '# TODO\n\n## Current\n\n- [ ] clean routine item [ROUTINE] <!-- id:aa01 -->\n' \
  > "$REPO/TODO.md"
touch "$REPO/TODO.archive.md"
git -C "$REPO" add -A
git -C "$REPO" commit -qm init

# --- (1) --strict flag is recognized (no "unknown flag" error) -----------------
err="$(HOME="$tmp" "$SH" --strict "$REPO" 2>&1 || true)"
echo "$err" | grep -qiE 'unknown flag.*strict' \
  && fail "--strict must not be reported as unknown flag (got: $err)" || true
pass "--strict flag is recognized (no unknown-flag error)"

# --- (4) --strict + clean fixture → exit 0 ------------------------------------
rc=0
HOME="$tmp" RELAY_TOML="$tmp/relay.toml" "$SH" --strict "$REPO" >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 0 ]] || fail "--strict on a clean fixture must exit 0 (no issues found); got $rc"
pass "--strict + clean fixture exits 0"

# --- (2) Without --strict on dirty fixture: exit 0 (report-only preserved) ----
# Create a ROADMAP with a missing-id item (roadmap-lint will flag it)
DIRTY_REPO="$tmp/dirty"
mkdir -p "$DIRTY_REPO"
git -C "$DIRTY_REPO" init -q
git -C "$DIRTY_REPO" config user.email t@e.st
git -C "$DIRTY_REPO" config user.name t
# A ROADMAP item missing the id: token — roadmap-lint will reject it
printf '# ROADMAP\n\n## Items\n\n- [ ] bad item with no id token [ROUTINE]\n' \
  > "$DIRTY_REPO/ROADMAP.md"
printf '# TODO\n\n' > "$DIRTY_REPO/TODO.md"
touch "$DIRTY_REPO/TODO.archive.md"
git -C "$DIRTY_REPO" add -A
git -C "$DIRTY_REPO" commit -qm init

rc=0
HOME="$tmp" RELAY_TOML="$tmp/relay.toml" "$SH" "$DIRTY_REPO" >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 0 ]] \
  || fail "without --strict, relay-doctor must exit 0 even with issues (report-only); got $rc"
pass "without --strict, relay-doctor exits 0 even with issues (report-only preserved)"

# --- (3) With --strict on dirty fixture: exit nonzero -------------------------
rc=0
HOME="$tmp" RELAY_TOML="$tmp/relay.toml" "$SH" --strict "$DIRTY_REPO" >/dev/null 2>&1 || rc=$?
[[ "$rc" -ne 0 ]] || fail "--strict on a dirty fixture (linting issue) must exit nonzero; got 0"
pass "--strict on dirty fixture exits nonzero"

# --- (5) quota-config: START >= END is flagged --------------------------------
rc=0
out="$(HOME="$tmp" RELAY_QUOTA_DECAY_7D="0.90:0.30" "$SH" "$REPO" 2>&1)" || rc=$?
# Should still exit 0 (report-only, no --strict)
[[ "$rc" -eq 0 ]] || fail "quota-config issue without --strict must still exit 0; got $rc"
echo "$out" | grep -qiE 'WARN.*RELAY_QUOTA_DECAY_7D.*START.*>=.*END|backward' \
  || fail "quota-config START(0.90) >= END(0.30) must emit a WARN; got: $out"
pass "RELAY_QUOTA_DECAY_7D=0.90:0.30 (START>=END) emits WARN"

# With --strict, that same issue should exit nonzero
rc=0
HOME="$tmp" RELAY_QUOTA_DECAY_7D="0.90:0.30" "$SH" --strict "$REPO" >/dev/null 2>&1 || rc=$?
[[ "$rc" -ne 0 ]] || fail "--strict + START>=END quota config must exit nonzero; got 0"
pass "--strict + START>=END exits nonzero"

# --- (6) quota-config: valid START:END is clean --------------------------------
out="$(HOME="$tmp" RELAY_QUOTA_DECAY_7D="0.30:0.90" "$SH" "$REPO" 2>&1)"
echo "$out" | grep -qiE 'WARN.*RELAY_QUOTA_DECAY_7D' \
  && fail "valid RELAY_QUOTA_DECAY_7D=0.30:0.90 must NOT emit WARN; got: $out" || true
echo "$out" | grep -qiE 'direction OK|START<END' \
  || fail "valid 0.30:0.90 must confirm direction OK; got: $out"
pass "RELAY_QUOTA_DECAY_7D=0.30:0.90 (valid START<END) is clean"

# --- (7) quota-config: unset → no complaint ------------------------------------
out="$(HOME="$tmp" RELAY_QUOTA_DECAY_7D= "$SH" "$REPO" 2>&1)"
echo "$out" | grep -qiE 'WARN.*RELAY_QUOTA_DECAY_7D' \
  && fail "unset RELAY_QUOTA_DECAY_7D must not emit WARN; got: $out" || true
pass "unset RELAY_QUOTA_DECAY_7D produces no WARN"

# --- (8) quota-config: malformed format is flagged ----------------------------
out="$(HOME="$tmp" RELAY_QUOTA_DECAY_7D="not-a-number" "$SH" "$REPO" 2>&1)"
echo "$out" | grep -qiE 'WARN.*RELAY_QUOTA_DECAY_7D' \
  || fail "malformed RELAY_QUOTA_DECAY_7D must emit WARN; got: $out"
pass "malformed RELAY_QUOTA_DECAY_7D emits WARN"

# --- structural: --strict and id:a883 are referenced in relay-doctor.sh -------
grep -q '\-\-strict' "$SH" || fail "relay-doctor.sh must implement --strict flag"
grep -q 'a883' "$SH" || fail "relay-doctor.sh must reference id:a883"
pass "relay-doctor.sh implements --strict and references id:a883"

echo "ALL PASS: id:a883 relay-doctor --strict + quota-config sanity check"
