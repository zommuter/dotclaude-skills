#!/usr/bin/env bash
# migrate-state-dirs.sh — one-time, idempotent migration of the relay state dirs
# from the legacy fables-turn naming to the canonical relay naming (id:10c0):
#
#     ~/.config/fables-turn  →  ~/.config/relay   (+ symlink old→new)
#     ~/.cache/fables-turn    →  ~/.cache/relay     (+ symlink old→new)
#
# These are LIVE dirs an in-flight relay pool reads/writes (relay.toml registry,
# RELAY_STATUS.md, relay-events.jsonl, quota-samples.jsonl, fable-probe.json,
# claims/, worktrees/, …). The migration must therefore (a) refuse to run while a
# pool looks active, and (b) leave a permanent symlink old→new so any straggler
# process, cross-session lease, un-updated ref, or older checkout still resolves
# the OLD path. The symlink is the load-bearing back-compat net (design call
# RESOLVED 2026-06-17 via /relay human — see ROADMAP id:10c0): there is no window
# where old-path access fails (the only non-atomic gap is between `mv` and the
# symlink — sub-second, and the idle precondition covers it).
#
# Idempotent: once each old dir is a symlink to its new dir, a re-run is a no-op.
#
# Order per dir:
#   1. PRECONDITION: refuse unless no relay pool is active
#      (no fresh RELAY_STATUS.md touch within RELAY_ACTIVE_SECS AND claim.sh peek
#       shows no live holder).
#   2. mkdir -p the new dir.
#   3. mv the OLD dir's contents into the new dir (skip names that already exist
#      in new — a partial prior run is resumable).
#   4. replace the now-empty old dir with a symlink old→new.
#
# Overrides (for hermetic tests):
#   HOME                 root for ~/.config and ~/.cache
#   RELAY_ACTIVE_SECS    staleness window for the RELAY_STATUS.md touch (default 1800)
#   RELAY_STATUS_PATH    path checked for freshness (default ~/.config/<old>/RELAY_STATUS.md,
#                        falling back to the new path if old is already a symlink)
#   CLAIM_BASE           passed through to claim.sh peek (default ~/.config/<old or new>)
#   MIGRATE_SKIP_GUARD   if "1", skip the idle precondition (tests of the mv/symlink path)
#   MIGRATE_FORCE_ACTIVE if "1", force the guard to treat the pool as active (refuse) —
#                        used by tests to assert the guard refuses; never set in prod.
set -euo pipefail

OLD_NAME="fables-turn"
NEW_NAME="relay"
CONFIG_OLD="$HOME/.config/$OLD_NAME"
CONFIG_NEW="$HOME/.config/$NEW_NAME"
CACHE_OLD="$HOME/.cache/$OLD_NAME"
CACHE_NEW="$HOME/.cache/$NEW_NAME"

RELAY_ACTIVE_SECS="${RELAY_ACTIVE_SECS:-1800}"
LOG="${MIGRATE_LOG:-$HOME/.claude/logs/relay-migrate.log}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$(dirname "$LOG")"
log() { printf '%s migrate-state-dirs.sh %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >>"$LOG" 2>/dev/null || true; }

# pool_active: true (exit 0) if a relay pool looks active right now.
#   (a) RELAY_STATUS.md touched within RELAY_ACTIVE_SECS, OR
#   (b) claim.sh peek emits at least one live claim line.
pool_active() {
  [ "${MIGRATE_FORCE_ACTIVE:-0}" = "1" ] && return 0

  # (a) RELAY_STATUS.md freshness — check the configured path, else the old, else the new.
  local status_file now mt age
  status_file="${RELAY_STATUS_PATH:-}"
  if [ -z "$status_file" ]; then
    if [ -e "$CONFIG_OLD/RELAY_STATUS.md" ]; then status_file="$CONFIG_OLD/RELAY_STATUS.md"
    elif [ -e "$CONFIG_NEW/RELAY_STATUS.md" ]; then status_file="$CONFIG_NEW/RELAY_STATUS.md"
    fi
  fi
  if [ -n "$status_file" ] && [ -e "$status_file" ]; then
    now="$(date +%s)"
    mt="$(stat -c %Y "$status_file" 2>/dev/null || echo 0)"
    age=$((now - mt))
    if [ "$age" -lt "$RELAY_ACTIVE_SECS" ]; then
      log "guard: RELAY_STATUS.md fresh (${age}s < ${RELAY_ACTIVE_SECS}s) — pool looks active"
      return 0
    fi
  fi

  # (b) live claim registry — point claim.sh at whichever base resolves.
  local claim_sh claim_base
  claim_sh="$SCRIPT_DIR/claim.sh"
  if [ -x "$claim_sh" ]; then
    claim_base="${CLAIM_BASE:-}"
    if [ -z "$claim_base" ]; then
      if [ -e "$CONFIG_OLD/claims" ] || [ -e "$CONFIG_OLD" ]; then claim_base="$CONFIG_OLD"
      else claim_base="$CONFIG_NEW"; fi
    fi
    local live
    live="$(CLAIM_BASE="$claim_base" "$claim_sh" peek 2>/dev/null | grep -c . || true)"
    if [ "${live:-0}" -gt 0 ]; then
      log "guard: claim.sh peek shows $live live holder(s) — pool looks active"
      return 0
    fi
  fi

  return 1
}

# migrate_dir <old> <new>: idempotent mv + symlink. No-op if old is already a symlink.
migrate_dir() {
  local old="$1" new="$2"

  # Already migrated: old is a symlink (idempotent no-op).
  if [ -L "$old" ]; then
    log "no-op: $old is already a symlink → $(readlink "$old")"
    return 0
  fi

  mkdir -p "$new"

  # Move contents of old → new (only if old exists as a real dir).
  if [ -d "$old" ]; then
    # Move each entry (including dotfiles), skipping any that already exist in new
    # so a partial prior run is resumable.
    local entry base
    shopt -s dotglob nullglob
    for entry in "$old"/*; do
      base="$(basename "$entry")"
      if [ -e "$new/$base" ] || [ -L "$new/$base" ]; then
        log "skip existing in new: $base"
        continue
      fi
      mv "$entry" "$new/$base"
    done
    shopt -u dotglob nullglob
    # Remove the now-(should-be-)empty old dir; refuse loudly if not empty.
    if ! rmdir "$old" 2>/dev/null; then
      log "WARN: $old not empty after mv — leaving in place, NOT symlinking"
      echo "migrate-state-dirs.sh: $old not empty after migration; resolve manually" >&2
      return 1
    fi
  fi

  # Replace old with a permanent symlink → new (the back-compat net).
  ln -s "$new" "$old"
  log "migrated: $old → symlink to $new"
}

main() {
  if [ "${MIGRATE_SKIP_GUARD:-0}" != "1" ]; then
    if pool_active; then
      echo "migrate-state-dirs.sh: a relay pool looks active — refusing to migrate. Re-run when idle." >&2
      log "REFUSED: pool active"
      exit 1
    fi
  fi

  migrate_dir "$CONFIG_OLD" "$CONFIG_NEW"
  migrate_dir "$CACHE_OLD" "$CACHE_NEW"

  echo "migrate-state-dirs.sh: state dirs migrated to canonical relay naming (symlinks kept)."
  log "done"
}

main "$@"
