#!/usr/bin/env bash
# roadmap:bbd2 — migrate-state-dirs.sh: complete the id:10c0 state-dir rename
# (fables-turn → relay) with idle-guarded, data-preserving reconciliation and a
# permanent back-compat symlink (old → new). Fixes the half-done split-brain.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$SRC_DIR/relay/scripts/migrate-state-dirs.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

# Fresh OLD/NEW pair under the temp root for one scenario.
# Usage: setup <name> ; sets CFG_OLD CFG_NEW CACHE_OLD CACHE_NEW
setup() {
  local n="$1"
  CFG_OLD="$T/$n/cfg-old"; CFG_NEW="$T/$n/cfg-new"
  CACHE_OLD="$T/$n/cache-old"; CACHE_NEW="$T/$n/cache-new"
  rm -rf "$T/$n"; mkdir -p "$CFG_OLD" "$CFG_NEW" "$CACHE_OLD" "$CACHE_NEW"
}

run() {  # run the migration over the current CFG_*/CACHE_* pair
  RELAY_CFG_OLD="$CFG_OLD" RELAY_CFG_NEW="$CFG_NEW" \
  RELAY_CACHE_OLD="$CACHE_OLD" RELAY_CACHE_NEW="$CACHE_NEW" \
  RELAY_MIGRATE_ASSUME_IDLE=1 "$SCRIPT" "$@"
}

[[ -x "$SCRIPT" ]] || fail "script missing or not executable: $SCRIPT"

# ── 1. relay.toml present ONLY in OLD → moved to NEW, OLD becomes a symlink ──
setup t1
printf 'registry = true\n' > "$CFG_OLD/relay.toml"
run
[[ -L "$CFG_OLD" ]] || fail "t1: OLD config dir should be a symlink after migration"
[[ "$(readlink -f "$CFG_OLD")" == "$(readlink -f "$CFG_NEW")" ]] || fail "t1: OLD should resolve to NEW"
[[ -f "$CFG_NEW/relay.toml" ]] || fail "t1: relay.toml should be in NEW"
grep -q 'registry = true' "$CFG_NEW/relay.toml" || fail "t1: relay.toml content lost"
# back-compat: reading via the OLD path still works (through the symlink)
grep -q 'registry = true' "$CFG_OLD/relay.toml" || fail "t1: OLD-path read (via symlink) broken"
pass "relay.toml only-in-old migrated; old→new symlink; back-compat read works"

# ── 2. append-only *.jsonl present in BOTH → NEW = union (no log lines lost) ──
setup t2
printf '%s\n' '{"e":1}' '{"e":2}' '{"e":3}' > "$CFG_OLD/relay-events.jsonl"
printf '%s\n' '{"e":3}' '{"e":4}' > "$CFG_NEW/relay-events.jsonl"
run
for e in 1 2 3 4; do
  grep -q "{\"e\":$e}" "$CFG_NEW/relay-events.jsonl" || fail "t2: event $e missing from merged jsonl"
done
# deduped: {"e":3} appears once
[[ "$(grep -c '{"e":3}' "$CFG_NEW/relay-events.jsonl")" -eq 1 ]] || fail "t2: jsonl not deduped"
pass "append-only jsonl merged as union (dedup, no loss)"

# ── 3. snapshot file in BOTH → newer mtime wins ──
setup t3
printf 'OLD-status\n' > "$CFG_OLD/RELAY_STATUS.md"
printf 'NEW-status\n' > "$CFG_NEW/RELAY_STATUS.md"
touch -d '2020-01-01' "$CFG_NEW/RELAY_STATUS.md"   # NEW is OLDER
touch -d '2020-06-01' "$CFG_OLD/RELAY_STATUS.md"   # OLD is NEWER → should win
run
grep -q 'OLD-status' "$CFG_NEW/RELAY_STATUS.md" || fail "t3: newer (old) snapshot should have won"
pass "snapshot file: newer mtime wins"

# ── 4. only-in-old subdirectory with content → moved into NEW ──
setup t4
mkdir -p "$CFG_OLD/inject.done"
printf 'x\n' > "$CFG_OLD/inject.done/unit-aaaa.json"
run
[[ -f "$CFG_NEW/inject.done/unit-aaaa.json" ]] || fail "t4: only-in-old dir content not migrated"
pass "only-in-old subdirectory migrated into NEW"

# ── 5. directory present in BOTH → union (old-only children moved in) ──
setup t5
mkdir -p "$CFG_OLD/claims.done" "$CFG_NEW/claims.done"
printf 'old\n' > "$CFG_OLD/claims.done/a.json"
printf 'new\n' > "$CFG_NEW/claims.done/b.json"
run
[[ -f "$CFG_NEW/claims.done/a.json" ]] || fail "t5: old-only child not unioned in"
[[ -f "$CFG_NEW/claims.done/b.json" ]] || fail "t5: new child clobbered"
pass "directory in both: unioned"

# ── 6. lock files are NOT migrated (ephemeral) but OLD still collapses cleanly ──
setup t6
printf '' > "$CFG_OLD/.claim.lock"
printf 'registry\n' > "$CFG_OLD/relay.toml"
run
[[ -L "$CFG_OLD" ]] || fail "t6: OLD should still become a symlink despite lock files"
[[ ! -e "$CFG_NEW/.claim.lock" ]] || fail "t6: lock file should not be migrated"
pass "lock files skipped; old still collapses to symlink"

# ── 7. idempotent: OLD already a symlink → no-op, exit 0 ──
setup t7
printf 'registry\n' > "$CFG_NEW/relay.toml"
rm -rf "$CFG_OLD"; ln -s "$CFG_NEW" "$CFG_OLD"
run
[[ -L "$CFG_OLD" ]] || fail "t7: symlink should remain"
grep -q 'registry' "$CFG_NEW/relay.toml" || fail "t7: NEW content disturbed on no-op"
pass "idempotent when OLD already a symlink"

# ── 8. idle guard: ASSUME_BUSY → refuses (exit 3), NO mutation ──
setup t8
printf 'registry\n' > "$CFG_OLD/relay.toml"
rc=0
RELAY_CFG_OLD="$CFG_OLD" RELAY_CFG_NEW="$CFG_NEW" \
RELAY_CACHE_OLD="$CACHE_OLD" RELAY_CACHE_NEW="$CACHE_NEW" \
RELAY_MIGRATE_ASSUME_BUSY=1 "$SCRIPT" || rc=$?
[[ "$rc" -eq 3 ]] || fail "t8: busy guard should exit 3 (got $rc)"
[[ -d "$CFG_OLD" && ! -L "$CFG_OLD" ]] || fail "t8: busy guard must not mutate (OLD still a real dir)"
[[ -f "$CFG_OLD/relay.toml" ]] || fail "t8: busy guard must not move data"
pass "idle guard refuses when busy (exit 3, no mutation)"

# ── 9. cache pair (worktrees) migrated the same way ──
setup t9
mkdir -p "$CACHE_OLD/worktrees/repoX"
printf 'wt\n' > "$CACHE_OLD/worktrees/repoX/file"
run
[[ -L "$CACHE_OLD" ]] || fail "t9: OLD cache dir should be a symlink"
[[ -f "$CACHE_NEW/worktrees/repoX/file" ]] || fail "t9: cache worktree content not migrated"
pass "cache dir migrated + symlinked like config"

# ── 10. jsonl merge where SRC lacks a trailing newline → no record fusion/loss ──
# (audit id:401c HIGH: `cat src dest` would fuse src's last line onto dest's first.)
setup t10
printf '{"e":1}\n{"e":2}' > "$CFG_OLD/relay-events.jsonl"   # NO trailing newline
printf '{"e":3}\n{"e":4}\n' > "$CFG_NEW/relay-events.jsonl"
run
for e in 1 2 3 4; do
  grep -qx "{\"e\":$e}" "$CFG_NEW/relay-events.jsonl" || fail "t10: record {\"e\":$e} missing/fused (no-trailing-newline src)"
done
[[ "$(wc -l < "$CFG_NEW/relay-events.jsonl")" -eq 4 ]] || fail "t10: expected exactly 4 lines, got $(wc -l < "$CFG_NEW/relay-events.jsonl")"
pass "jsonl merge: src without trailing newline → no fusion, all records intact"

# ── 11. snapshot in BOTH, NEW newer → NEW kept (the other half of newest-wins) ──
setup t11
printf 'OLD-status\n' > "$CFG_OLD/RELAY_STATUS.md"
printf 'NEW-status\n' > "$CFG_NEW/RELAY_STATUS.md"
touch -d '2020-01-01' "$CFG_OLD/RELAY_STATUS.md"   # OLD older
touch -d '2020-06-01' "$CFG_NEW/RELAY_STATUS.md"   # NEW newer → should win
run
grep -q 'NEW-status' "$CFG_NEW/RELAY_STATUS.md" || fail "t11: newer (new) snapshot should have been kept"
pass "snapshot file: NEW newer → NEW kept"

# ── 12. type mismatch (OLD entry is a dir, NEW same name is a file) → exit 1, no mutation ──
setup t12
mkdir -p "$CFG_OLD/relay.toml"                      # dir in OLD
printf 'x\n' > "$CFG_OLD/relay.toml/inner"
printf 'file\n' > "$CFG_NEW/relay.toml"             # file in NEW (same name)
rc=0
run || rc=$?
[[ "$rc" -ne 0 ]] || fail "t12: type-mismatch should make migration exit non-zero (got 0)"
[[ -d "$CFG_OLD" && ! -L "$CFG_OLD" ]] || fail "t12: OLD must NOT be symlinked on unresolved mismatch"
[[ -f "$CFG_OLD/relay.toml/inner" ]] || fail "t12: OLD data must be left intact on mismatch"
pass "type mismatch: refuses (exit≠0), leaves OLD intact, does not symlink"

echo "ALL PASS (test_migrate_state_dirs.sh)"
