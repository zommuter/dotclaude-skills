#!/usr/bin/env bash
# roadmap:9fdb — `append.sh inbox-done XXXX` must REFUSE (exit non-zero, delete nothing)
# unless the target repo already carries the durable `routed:XXXX` twin in its committed
# TODO.md or ROADMAP.md. The inbox is a LOCAL-ONLY, unversioned store and inbox-done is
# vanish-on-resolve (destructive); deleting a line whose twin never landed loses the item
# irrecoverably (id:9fdb, meeting 2026-07-11 D4).
#
# Hermetic: fixture inbox + fake target repos in mktemp -d, driven via RELAY_INBOX +
# SRC_DIR / RELAY_TOML injection. Never touches the real inbox or ~/.claude.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SH="$ROOT/meeting/append.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$SH" ]] || fail "append.sh not found at $SH"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

make_inbox() {
  # $1 = path, $2 = target-name, $3 = token
  cat > "$1" <<EOF
# Cross-project inbox

- [ ] [$2] some routed work item (from meeting, note) <!-- routed:$3 -->
EOF
}

# --- Case 1: NO twin → REFUSE, line survives ----------------------------------
INBOX="$TMP/inbox1.md"
SRC="$TMP/src1"; mkdir -p "$SRC/targetrepo"
: > "$SRC/targetrepo/TODO.md"          # target repo exists but has NO routed:aaaa twin
make_inbox "$INBOX" targetrepo aaaa
if RELAY_INBOX="$INBOX" SRC_DIR="$SRC" "$SH" inbox-done aaaa 2>/dev/null; then
  fail "inbox-done SUCCEEDED with no twin present — must REFUSE"
fi
grep -q 'routed:aaaa -->' "$INBOX" || fail "inbox-done deleted the line despite refusing (no twin)"
pass "no-twin: inbox-done refused (non-zero) and preserved the line"

# --- Case 2a: twin in TODO.md → SUCCEEDS, line deleted ------------------------
INBOX="$TMP/inbox2a.md"
SRC="$TMP/src2a"; mkdir -p "$SRC/targetrepo"
cat > "$SRC/targetrepo/TODO.md" <<'EOF'
# TODO
- [ ] [INBOUND routed:bbbb from meeting] work item <!-- id:1111 -->
EOF
make_inbox "$INBOX" targetrepo bbbb
RELAY_INBOX="$INBOX" SRC_DIR="$SRC" "$SH" inbox-done bbbb || fail "inbox-done refused despite TODO.md twin"
if grep -q 'routed:bbbb -->' "$INBOX"; then
  fail "inbox-done did not delete the line despite TODO.md twin"
fi
pass "TODO.md-twin: inbox-done succeeded and deleted the line"

# --- Case 2b: twin in ROADMAP.md → SUCCEEDS, line deleted ---------------------
INBOX="$TMP/inbox2b.md"
SRC="$TMP/src2b"; mkdir -p "$SRC/targetrepo"
: > "$SRC/targetrepo/TODO.md"          # empty TODO, twin only in ROADMAP
cat > "$SRC/targetrepo/ROADMAP.md" <<'EOF'
# ROADMAP
- [ ] [INBOUND routed:cccc from meeting] work item <!-- id:2222 -->
EOF
make_inbox "$INBOX" targetrepo cccc
RELAY_INBOX="$INBOX" SRC_DIR="$SRC" "$SH" inbox-done cccc || fail "inbox-done refused despite ROADMAP.md twin"
if grep -q 'routed:cccc -->' "$INBOX"; then
  fail "inbox-done did not delete the line despite ROADMAP.md twin"
fi
pass "ROADMAP.md-twin: inbox-done succeeded and deleted the line"

# --- Case 3: target resolved via RELAY_TOML # path: override → twin found -----
INBOX="$TMP/inbox3.md"
TOMLDIR="$TMP/toml"; mkdir -p "$TOMLDIR"
REPO="$TMP/elsewhere/oddname"; mkdir -p "$REPO"      # NOT under SRC_DIR
cat > "$REPO/TODO.md" <<'EOF'
# TODO
- [ ] [INBOUND routed:dddd from meeting] work item <!-- id:3333 -->
EOF
cat > "$TOMLDIR/relay.toml" <<EOF
[repos.oddname]
classification = "own"
# path: $REPO
EOF
make_inbox "$INBOX" oddname dddd
# SRC_DIR points nowhere useful — resolution MUST come from RELAY_TOML # path:
RELAY_INBOX="$INBOX" SRC_DIR="$TMP/nonexistent-src" RELAY_TOML="$TOMLDIR/relay.toml" \
  "$SH" inbox-done dddd || fail "inbox-done refused despite twin reachable via RELAY_TOML # path:"
if grep -q 'routed:dddd -->' "$INBOX"; then
  fail "inbox-done did not delete the line despite RELAY_TOML-resolved twin"
fi
pass "RELAY_TOML # path: override resolved the target and found the twin"

# --- Case 4: unresolvable target → REFUSE (destructive-safe) ------------------
INBOX="$TMP/inbox4.md"
SRC="$TMP/src4"; mkdir -p "$SRC"           # no repo dir at all
make_inbox "$INBOX" ghostrepo eeee
if RELAY_INBOX="$INBOX" SRC_DIR="$SRC" RELAY_TOML="$TMP/no-such.toml" \
     "$SH" inbox-done eeee 2>/dev/null; then
  fail "inbox-done SUCCEEDED with an unresolvable target — must REFUSE"
fi
grep -q 'routed:eeee -->' "$INBOX" || fail "inbox-done deleted the line for an unresolvable target"
pass "unresolvable-target: inbox-done refused and preserved the line"

echo "ALL PASS"
