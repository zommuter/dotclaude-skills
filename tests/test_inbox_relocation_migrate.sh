#!/usr/bin/env bash
# roadmap:9fdb — the cross-project inbox store relocates from the legacy
# $HOME/.claude/todo-inbox.md into the git-tracked private sessions worktree
# $HOME/.claude/projects/todo-inbox.md (free history/recovery, stays private). The
# resolver performs a ONE-TIME, idempotent, race-safe `mv` migration on first use when
# RELAY_INBOX is UNSET. With RELAY_INBOX set the injected path is authoritative and NO
# migration happens (hermetic tests rely on that) — so this test drives the default
# branch by pointing HOME at a temp dir and leaving RELAY_INBOX unset (id:9fdb, D4).
#
# Hermetic: temp HOME, no network, no real ~/.claude. The temp projects dir need NOT be a
# git repo — the resolver only does `mv`.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SH="$ROOT/meeting/append.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$SH" ]] || fail "append.sh not found at $SH"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME/.claude/projects"

LEGACY="$HOME/.claude/todo-inbox.md"
NEW="$HOME/.claude/projects/todo-inbox.md"

cat > "$LEGACY" <<'EOF'
# Cross-project inbox

- [ ] [somerepo] pre-existing routed item (from meeting, note) <!-- routed:9999 -->
EOF
ORIG="$(cat "$LEGACY")"

# Drive resolve_inbox via the `-t inbox` append path. RELAY_INBOX MUST be unset so the
# default (migrating) branch runs. `env -u` guarantees it even if the outer env set it.
env -u RELAY_INBOX "$SH" -t inbox -e "- [ ] [otherrepo] appended item (from test, note) <!-- routed:8888 -->" \
  || fail "append.sh -t inbox exited nonzero"

# Legacy path must be gone; new path must exist.
[[ ! -f "$LEGACY" ]] || fail "legacy inbox still present after migration: $LEGACY"
[[ -f "$NEW" ]] || fail "new inbox not created at $NEW"
pass "migration moved legacy → $NEW"

# Original content must be preserved (plus the freshly appended line).
grep -q 'routed:9999 -->' "$NEW" || fail "pre-existing content lost during migration"
grep -q 'routed:8888 -->' "$NEW" || fail "appended line missing from migrated inbox"
pass "content preserved (pre-existing routed:9999 + appended routed:8888)"

# Snapshot after first migration+append.
AFTER1="$(cat "$NEW")"

# Second invocation must be a no-op migration (legacy is gone) and must NOT clobber.
env -u RELAY_INBOX "$SH" -t inbox -e "- [ ] [thirdrepo] second append (from test, note) <!-- routed:7777 -->" \
  || fail "second append.sh -t inbox exited nonzero"
[[ ! -f "$LEGACY" ]] || fail "legacy inbox reappeared on second invocation"
grep -q 'routed:9999 -->' "$NEW" || fail "second invocation clobbered pre-existing content"
grep -q 'routed:8888 -->' "$NEW" || fail "second invocation clobbered first appended line"
grep -q 'routed:7777 -->' "$NEW" || fail "second appended line missing"
pass "second invocation is idempotent (no re-migrate, no clobber)"

# Idempotence of the pure migration: recreate a legacy file alongside an existing new
# file — the resolver must NOT overwrite the new store (condition is `! -f new`).
cat > "$LEGACY" <<'EOF'
# stale legacy that must NOT clobber the relocated store
- [ ] [stalerepo] MUST NOT WIN (from test) <!-- routed:0000 -->
EOF
env -u RELAY_INBOX "$SH" -t inbox -e "- [ ] [fourthrepo] fourth append (from test, note) <!-- routed:6666 -->" \
  || fail "append with stale legacy present exited nonzero"
if grep -q 'routed:0000 -->' "$NEW"; then
  fail "stale legacy clobbered the relocated store (migration overwrote existing new file)"
fi
[[ -f "$LEGACY" ]] || fail "resolver moved a legacy file even though new store exists (should be left untouched)"
pass "existing new store not clobbered by a stale legacy file (migration guarded on '! -f new')"

echo "ALL PASS"
