#!/usr/bin/env bash
# roadmap:10c0 — migrate-state-dirs.sh: one-time, idempotent migration of the relay
# state dirs from the legacy fables-turn naming to the canonical relay naming, with a
# permanent old→new symlink as the back-compat net and an idle-precondition guard that
# refuses while a relay pool looks active.
#
# Covers (acceptance 1/2/5 from ROADMAP id:10c0):
#   - idle guard refuses while a pool looks active (fresh RELAY_STATUS.md / live claim)
#   - successful migration: contents moved, old dir becomes a symlink → new dir
#   - idempotency: a re-run after migration is a no-op (no error, symlink preserved)
#   - the 13 executable files no longer hardcode the legacy fables-turn default

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SH="$SRC_DIR/relay/scripts/migrate-state-dirs.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SH" ]] || fail "migrate-state-dirs.sh not found/executable at $SH"

# ── Hermetic HOME ──
H="$(mktemp -d)"
trap 'rm -rf "$H"' EXIT

seed_dirs() {
  rm -rf "$H/.config" "$H/.cache"
  mkdir -p "$H/.config/fables-turn/claims" "$H/.cache/fables-turn/worktrees"
  printf 'token-content\n'      > "$H/.config/fables-turn/relay.toml"
  printf '## RELAY status\n'    > "$H/.config/fables-turn/RELAY_STATUS.md"
  printf '{"kind":"x"}\n'       > "$H/.config/fables-turn/relay-events.jsonl"
  printf 'wt-marker\n'          > "$H/.cache/fables-turn/worktrees/marker.txt"
}

run_migrate() { HOME="$H" "$@" "$SH"; }

# ── (1) idle guard refuses while a pool looks active (MIGRATE_FORCE_ACTIVE) ──
seed_dirs
# make RELAY_STATUS.md stale so only the forced-active flag drives the refusal
touch -d '2000-01-01' "$H/.config/fables-turn/RELAY_STATUS.md"
if HOME="$H" RELAY_STATUS_PATH="$H/.config/fables-turn/RELAY_STATUS.md" MIGRATE_FORCE_ACTIVE=1 "$SH" 2>/dev/null; then
  fail "guard: migration should REFUSE while a pool looks active"
fi
# nothing migrated: old dir is still a real dir, new dir absent
[[ -d "$H/.config/fables-turn" && ! -L "$H/.config/fables-turn" ]] || fail "guard: old config dir disturbed by a refused run"
[[ ! -e "$H/.config/relay" ]] || fail "guard: new config dir created by a refused run"
pass "idle guard refuses migration while a pool looks active (forced)"

# ── (1b) idle guard refuses while RELAY_STATUS.md is fresh ──
seed_dirs
touch "$H/.config/fables-turn/RELAY_STATUS.md"  # now()
if HOME="$H" RELAY_ACTIVE_SECS=1800 RELAY_STATUS_PATH="$H/.config/fables-turn/RELAY_STATUS.md" "$SH" 2>/dev/null; then
  fail "guard: migration should REFUSE while RELAY_STATUS.md is fresh"
fi
[[ ! -L "$H/.config/fables-turn" ]] || fail "guard(fresh): old dir was migrated despite fresh status"
pass "idle guard refuses while RELAY_STATUS.md is fresh within RELAY_ACTIVE_SECS"

# ── (2) successful migration: contents moved, old → symlink to new ──
seed_dirs
touch -d '2000-01-01' "$H/.config/fables-turn/RELAY_STATUS.md"  # stale → idle
HOME="$H" RELAY_ACTIVE_SECS=1800 RELAY_STATUS_PATH="$H/.config/fables-turn/RELAY_STATUS.md" "$SH" >/dev/null \
  || fail "migration: clean idle run should succeed"

# old config dir is now a symlink → new
[[ -L "$H/.config/fables-turn" ]] || fail "config: old dir is not a symlink after migration"
[[ "$(readlink "$H/.config/fables-turn")" == "$H/.config/relay" ]] || fail "config: symlink target wrong"
[[ -L "$H/.cache/fables-turn" ]] || fail "cache: old dir is not a symlink after migration"
[[ "$(readlink "$H/.cache/fables-turn")" == "$H/.cache/relay" ]] || fail "cache: symlink target wrong"

# contents live under the NEW path
[[ "$(cat "$H/.config/relay/relay.toml")" == "token-content" ]] || fail "migration: relay.toml content lost"
[[ "$(cat "$H/.config/relay/relay-events.jsonl")" == '{"kind":"x"}' ]] || fail "migration: events lost"
[[ -d "$H/.config/relay/claims" ]] || fail "migration: claims/ subdir lost"
[[ "$(cat "$H/.cache/relay/worktrees/marker.txt")" == "wt-marker" ]] || fail "migration: worktree marker lost"

# old path still resolves the content through the symlink (back-compat net)
[[ "$(cat "$H/.config/fables-turn/relay.toml")" == "token-content" ]] || fail "back-compat: old path does not resolve via symlink"
pass "migration moves contents to relay/ and replaces old dirs with back-compat symlinks"

# ── (3) idempotency: a re-run is a no-op (no error, symlink preserved) ──
HOME="$H" RELAY_ACTIVE_SECS=1800 RELAY_STATUS_PATH="$H/.config/relay/RELAY_STATUS.md" "$SH" >/dev/null \
  || fail "idempotency: re-run should succeed (no-op)"
[[ -L "$H/.config/fables-turn" ]] || fail "idempotency: symlink removed on re-run"
[[ "$(cat "$H/.config/relay/relay.toml")" == "token-content" ]] || fail "idempotency: content disturbed on re-run"
pass "re-run after migration is an idempotent no-op (symlinks + content preserved)"

# ── (4) executable files read the new canonical relay default, not the legacy name ──
# Acceptance (2): the legacy fables-turn default path must not survive as a hardcoded
# default in the executable files. (Comments / historical prose may still mention it,
# but a `:-$HOME/.config/fables-turn` style default must be gone.)
legacy_defaults="$(grep -rn 'fables-turn' \
  "$SRC_DIR/relay/scripts/claim.sh" \
  "$SRC_DIR/relay/scripts/discover-repos.sh" \
  "$SRC_DIR/relay/scripts/discover-sig.sh" \
  "$SRC_DIR/relay/scripts/gather-human-backlog.sh" \
  "$SRC_DIR/relay/scripts/inject.sh" \
  "$SRC_DIR/relay/scripts/loop-hint.sh" \
  "$SRC_DIR/relay/scripts/probe-fable.sh" \
  "$SRC_DIR/relay/scripts/relay-burn.sh" \
  "$SRC_DIR/relay/scripts/relay-state-write.sh" \
  "$SRC_DIR/statusline/statusline-command.sh" \
  | grep -E ':-\$HOME/\.(config|cache)/fables-turn' || true)"
[[ -z "$legacy_defaults" ]] || fail "executable default still uses legacy fables-turn path:
$legacy_defaults"
pass "executable env-var defaults point at the canonical relay path (no legacy default)"

echo "ALL PASS: migrate-state-dirs.sh (id:10c0)"
