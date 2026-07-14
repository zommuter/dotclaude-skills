#!/usr/bin/env bash
# roadmap:411d — `append.sh inbox-done XXXX` must delete ONLY the inbox item whose OWN
# routed marker is `routed:XXXX`, never a sibling item that merely CITES that token in its
# prose. The current predicate (`needle in l and l.lstrip().startswith("- [")`, needle =
# f"routed:{token}") is a substring test, not an anchor: an item whose prose legitimately
# references a sibling's token is a checkbox line containing the needle, so resolving the
# sibling silently deletes the citing item too. The inbox is local-only and never
# committed, so a wrongly-deleted item is UNRECOVERABLE.
#
# RED until inbox-done anchors on the item's own routed marker. Hermetic: builds a fixture
# inbox in mktemp -d and drives append.sh via the RELAY_INBOX injection point.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SH="$ROOT/meeting/append.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$SH" ]] || fail "append.sh not found at $SH"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
INBOX="$TMP/todo-inbox.md"

# Two conforming inbox items. The FIRST cites the second's token (4fa9) in its prose;
# its OWN routed marker is 1234. The SECOND is the item actually being resolved (4fa9).
cat > "$INBOX" <<'EOF'
# Cross-project inbox

- [ ] [chidiAI] praise case — the contrast with routed:4fa9 is the signal (from meeting, note) <!-- routed:1234 -->
- [ ] [chidiAI] offender case — model degradation repro (from meeting, note) <!-- routed:4fa9 -->
EOF

# The twin-check guard (id:9fdb) now REFUSES to delete unless the target repo already
# carries the durable `routed:<token>` breadcrumb. Provide it: a fake chidiAI repo under
# a temp SRC_DIR whose TODO.md contains routed:4fa9. Without this the anchored-delete
# below would (correctly) be blocked by the guard, not by any anchoring regression.
SRC="$TMP/src"; mkdir -p "$SRC/chidiAI"
cat > "$SRC/chidiAI/TODO.md" <<'EOF'
# TODO — chidiAI
- [ ] [INBOUND routed:4fa9 from meeting] model degradation repro <!-- id:abcd -->
EOF

RELAY_INBOX="$INBOX" SRC_DIR="$SRC" "$SH" inbox-done 4fa9 || fail "inbox-done exited nonzero"

# The resolved item (own marker routed:4fa9) must be gone.
if grep -q 'routed:4fa9 -->' "$INBOX"; then
  fail "inbox-done did not delete the item whose OWN marker is routed:4fa9"
fi
pass "inbox-done deleted the target item (own marker routed:4fa9)"

# The citing item (own marker routed:1234, prose mentions 4fa9) MUST survive.
if ! grep -q 'routed:1234 -->' "$INBOX"; then
  fail "inbox-done wrongly deleted the sibling item that only CITES routed:4fa9 in prose (own marker routed:1234) — unrecoverable data loss (id:411d)"
fi
pass "inbox-done preserved the prose-citing sibling (own marker routed:1234)"

echo "ALL PASS"
