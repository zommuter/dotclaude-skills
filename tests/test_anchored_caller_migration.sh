#!/usr/bin/env bash
# roadmap:3743
# RED spec (authored by /relay handoff 2026-07-20, apex) for the id:3add follow-up:
# migrate the hand-rolled anchored-token extraction callers onto the shared
# lib-anchored-id.sh shape-B primitives. HIGHEST-VALUE caller pinned here:
# `meeting/append.sh inbox-done`'s twin check is a bare `grep -qsF "routed:$token"`
# — a real anchoring bug against a DESTRUCTIVE, local-only store:
#
#   • FALSE TWIN: a longer hex run sharing the 4-char prefix (`routed:aaaa9…`)
#     substring-matches, so inbox-done deletes an inbox line whose durable twin
#     never landed — the unrecoverable id:411d/9fdb wrong-delete class.
#   • MISSED TWIN: a target that adopted the item under an anchored `<!-- id:XXXX -->`
#     marker (scan-routed.sh's twin semantics accept `(routed|id):XXXX`) is not
#     recognized, so the inbox line lingers forever.
#
# The shared primitive `token_marker_in_files` (lib-anchored-id.sh, id:3add) fixes
# both: `(routed|id):$tok` + a trailing token boundary. The other family callers
# (unpromoted-scan inline grep, roadmap-lint id_re, md-merge.py's Python-side match)
# migrate under suite-green + the item's per-caller notes; this spec pins the one
# caller with observable behaviour change.
#
# Hermetic: fixture inbox + fake target repos in mktemp -d via RELAY_INBOX +
# SRC_DIR / RELAY_TOML injection (the test_inbox_done_twin_guard.sh pattern).
# EXPECTED-RED while roadmap:3743 is unticked (does not fail the suite).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SH="$ROOT/meeting/append.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$SH" ]] || fail "append.sh not found at $SH"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export RELAY_TOML="$TMP/relay.toml"; : > "$RELAY_TOML"

make_inbox() {  # $1=path $2=target $3=token
  cat > "$1" <<EOF
# Cross-project inbox

- [ ] [$2] some routed work item (from meeting, note) <!-- routed:$3 -->
EOF
}

# ── (a) FALSE TWIN: longer hex run sharing the prefix must NOT satisfy the check ──
INBOX="$TMP/inbox_a.md"; SRC="$TMP/src_a"; mkdir -p "$SRC/targetrepo"
cat > "$SRC/targetrepo/TODO.md" <<'EOF'
# TODO
- [ ] unrelated follow-up (supersedes the old routed:aaaa9 draft note) <!-- id:1111 -->
EOF
make_inbox "$INBOX" targetrepo aaaa
if RELAY_INBOX="$INBOX" SRC_DIR="$SRC" "$SH" inbox-done aaaa 2>/dev/null; then
  fail "(a) inbox-done ACCEPTED a substring false-twin (routed:aaaa matched inside routed:aaaa9) — must REFUSE (anchored boundary)"
fi
grep -q 'routed:aaaa -->' "$INBOX" \
  || fail "(a) inbox-done DELETED the line on a substring false-twin — unrecoverable wrong-delete"
pass "(a) substring false-twin (routed:aaaa9) refused, inbox line preserved"

# ── (b) MISSED TWIN: an anchored <!-- id:XXXX --> adoption IS a twin ──────────
INBOX="$TMP/inbox_b.md"; SRC="$TMP/src_b"; mkdir -p "$SRC/targetrepo"
cat > "$SRC/targetrepo/TODO.md" <<'EOF'
# TODO
- [ ] the adopted work item, tracked under its own marker <!-- id:bbbb -->
EOF
make_inbox "$INBOX" targetrepo bbbb
RELAY_INBOX="$INBOX" SRC_DIR="$SRC" "$SH" inbox-done bbbb 2>/dev/null \
  || fail "(b) inbox-done REFUSED despite an anchored <!-- id:bbbb --> twin in the target (shape-B accepts (routed|id):XXXX)"
if grep -q 'routed:bbbb -->' "$INBOX"; then
  fail "(b) inbox-done did not delete the resolved line despite the id-marker twin"
fi
pass "(b) anchored id-marker twin accepted, inbox line resolved"

# ── (c) regression: the INBOUND-stub twin form still works ────────────────────
INBOX="$TMP/inbox_c.md"; SRC="$TMP/src_c"; mkdir -p "$SRC/targetrepo"
cat > "$SRC/targetrepo/TODO.md" <<'EOF'
# TODO
- [ ] [INBOUND routed:cccc from meeting] work item <!-- id:2222 -->
EOF
make_inbox "$INBOX" targetrepo cccc
RELAY_INBOX="$INBOX" SRC_DIR="$SRC" "$SH" inbox-done cccc 2>/dev/null \
  || fail "(c) inbox-done refused the INBOUND-stub twin form (regression: boundary after token is a space)"
grep -q 'routed:cccc -->' "$INBOX" && fail "(c) INBOUND-stub twin: line not deleted"
pass "(c) INBOUND-stub twin form still resolves (regression control)"

# ── (d) no twin at all → still refuses (id:9fdb guard unchanged) ──────────────
INBOX="$TMP/inbox_d.md"; SRC="$TMP/src_d"; mkdir -p "$SRC/targetrepo"
: > "$SRC/targetrepo/TODO.md"
make_inbox "$INBOX" targetrepo dddd
if RELAY_INBOX="$INBOX" SRC_DIR="$SRC" "$SH" inbox-done dddd 2>/dev/null; then
  fail "(d) inbox-done accepted with NO twin present — the id:9fdb refusal must be unchanged"
fi
grep -q 'routed:dddd -->' "$INBOX" || fail "(d) no-twin refusal must preserve the line"
pass "(d) no-twin refusal unchanged (id:9fdb guard intact)"

# ── (e) structural: the caller actually uses the shared primitive ─────────────
grep -q 'token_marker_in_files\|lib-anchored-id' "$SH" \
  || fail "(e) meeting/append.sh does not use the shared lib-anchored-id.sh shape-B primitive — the migration is the point of id:3743"
pass "(e) append.sh migrated onto the shared anchored primitive"

# The shipped primitive suite must stay green alongside the migration.
bash "$ROOT/tests/test_lib_anchored_token.sh" >/dev/null 2>&1 \
  || fail "(f) tests/test_lib_anchored_token.sh regressed — the primitive itself must stay green"
pass "(f) shared-primitive suite still green"

echo "OK: all anchored-caller-migration assertions passed"
