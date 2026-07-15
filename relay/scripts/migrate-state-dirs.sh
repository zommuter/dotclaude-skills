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
# RESOLVED 2026-06-17 via /relay human — see ROADMAP id:10c0).
#
# RECONCILE, don't skip (id:bbd2). An earlier version skipped any name already
# present in NEW and then refused to symlink because OLD wasn't empty — which is
# exactly how the dirs went split-brain (a rename merged mid-flight left relay.toml
# in OLD and a divergent relay-events.jsonl in both). So on a collision we MERGE
# rather than strand:
#   • append-only logs (*.jsonl)  → union of lines (dedup, stable order); no log lost
#   • directories (claims/, claims.done/, inject.*/, worktrees/, …) → union children
#     (NEW wins on a name collision; OLD-only children are moved in)
#   • snapshots / other files (relay.toml, RELAY_STATUS.md, fable-probe.json, …)
#     → newest mtime wins
#   • lock files (*.lock) → dropped (ephemeral; never migrated)
# After reconciliation OLD is empty, so it is replaced by a symlink → NEW.
#
# Idempotent: once each old dir is a symlink to its new dir, a re-run is a no-op.
#
# Overrides (for hermetic tests):
#   HOME                       root for ~/.config and ~/.cache (default paths below)
#   RELAY_CFG_OLD/NEW          explicit config old/new dir (overrides HOME-derived)
#   RELAY_CACHE_OLD/NEW        explicit cache  old/new dir
#   RELAY_ACTIVE_SECS          staleness window for the RELAY_STATUS.md touch (default 1800)
#   RELAY_STATUS_PATH          path checked for pool freshness
#   CLAIM_BASE                 passed through to claim.sh peek
#   RELAY_MIGRATE_ASSUME_IDLE  "1" → skip the idle precondition (test the mv/symlink path)
#                              (alias: MIGRATE_SKIP_GUARD)
#   RELAY_MIGRATE_ASSUME_BUSY  "1" → force the guard to treat the pool as active (refuse)
#                              (alias: MIGRATE_FORCE_ACTIVE)
#
# Exit codes: 0 success/no-op · 3 refused (pool active) · 1 unexpected error.
set -euo pipefail

OLD_NAME="fables-turn"
NEW_NAME="relay"
CONFIG_OLD="${RELAY_CFG_OLD:-$HOME/.config/$OLD_NAME}"
CONFIG_NEW="${RELAY_CFG_NEW:-$HOME/.config/$NEW_NAME}"
CACHE_OLD="${RELAY_CACHE_OLD:-$HOME/.cache/$OLD_NAME}"
CACHE_NEW="${RELAY_CACHE_NEW:-$HOME/.cache/$NEW_NAME}"

RELAY_ACTIVE_SECS="${RELAY_ACTIVE_SECS:-1800}"
LOG="${MIGRATE_LOG:-$HOME/.claude/logs/relay-migrate.log}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ASSUME_IDLE="${RELAY_MIGRATE_ASSUME_IDLE:-${MIGRATE_SKIP_GUARD:-0}}"
ASSUME_BUSY="${RELAY_MIGRATE_ASSUME_BUSY:-${MIGRATE_FORCE_ACTIVE:-0}}"

mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
log() { printf '%s migrate-state-dirs.sh %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >>"$LOG" 2>/dev/null || true; }

# pool_active: true (exit 0) if a relay pool looks active right now.
pool_active() {
  [ "$ASSUME_BUSY" = "1" ] && { log "guard: ASSUME_BUSY"; return 0; }

  # (a) RELAY_STATUS.md freshness — configured path, else old, else new.
  local status_file now mt age
  status_file="${RELAY_STATUS_PATH:-}"
  if [ -z "$status_file" ]; then
    if [ -e "$CONFIG_OLD/RELAY_STATUS.md" ]; then status_file="$CONFIG_OLD/RELAY_STATUS.md"
    elif [ -e "$CONFIG_NEW/RELAY_STATUS.md" ]; then status_file="$CONFIG_NEW/RELAY_STATUS.md"
    fi
  fi
  if [ -n "$status_file" ] && [ -e "$status_file" ]; then
    now="$(date +%s)"; mt="$(stat -c %Y "$status_file" 2>/dev/null || echo 0)"; age=$((now - mt))
    if [ "$age" -lt "$RELAY_ACTIVE_SECS" ]; then
      log "guard: RELAY_STATUS.md fresh (${age}s < ${RELAY_ACTIVE_SECS}s) — pool looks active"; return 0
    fi
  fi

  # (b) live claim registry. FAIL CLOSED (assume active) if the tool errors — the
  # guard is the only gate before destructive mv/rm, so an unreadable registry must
  # not be mistaken for "no holders" (audit id:401c MED). Peek BOTH bases (a pool that
  # already migrated to NEW holds claims under NEW even while OLD still exists).
  local claim_sh bases b out rc
  claim_sh="$SCRIPT_DIR/claim.sh"
  if [ -x "$claim_sh" ]; then
    if [ -n "${CLAIM_BASE:-}" ]; then bases="$CLAIM_BASE"; else bases="$CONFIG_OLD $CONFIG_NEW"; fi
    for b in $bases; do
      out="$(CLAIM_BASE="$b" "$claim_sh" peek 2>/dev/null)"; rc=$?
      if [ "$rc" -ne 0 ]; then
        log "guard: claim.sh peek errored (rc=$rc, base=$b) — failing CLOSED (assume active)"; return 0
      fi
      if [ -n "$out" ]; then log "guard: live holder(s) at $b — pool active"; return 0; fi
    done
  fi
  return 1
}

# reconcile_entry <src-entry> <dest>: merge one OLD entry into NEW per policy.
reconcile_entry() {
  local src="$1" dest="$2" base
  base="$(basename "$src")"

  # Lock files are ephemeral — never migrate them.
  case "$base" in
    *.lock) rm -rf "$src"; log "drop lock: $base"; return 0 ;;
  esac

  if [ ! -e "$dest" ] && [ ! -L "$dest" ]; then
    mv "$src" "$dest"; return 0
  fi

  if [ -d "$src" ] && [ -d "$dest" ]; then
    # union: copy OLD children that don't already exist in NEW, then drop OLD —
    # but ONLY drop OLD if the copy fully SUCCEEDED. A swallowed partial cp (ENOSPC,
    # I/O error, unreadable child) followed by an unconditional rm -rf would silently
    # lose the un-copied children (audit id:401c MED). cp -n skipping is not an error.
    if cp -an "$src/." "$dest/" || cp -rn "$src/." "$dest/"; then
      rm -rf "$src"; log "union dir: $base"; return 0
    fi
    log "WARN: dir-union copy failed for $base — leaving src in place, NOT dropping"; return 1
  fi

  if [ -f "$src" ]; then
    case "$base" in
      *.jsonl)
        # append-only log → union of lines (stable, deduped). No history lost.
        # `awk 1` re-emits each input with a trailing ORS, so a src file missing its
        # final newline cannot fuse its last record onto dest's first (audit id:401c
        # HIGH — `cat` would have concatenated them into one corrupt line).
        local tmp; tmp="$(mktemp)"
        if awk 1 "$src" "$dest" | awk 'NF && !seen[$0]++' > "$tmp"; then
          chmod --reference="$dest" "$tmp" 2>/dev/null || true   # preserve dest perms (don't force 0600)
          mv "$tmp" "$dest"; rm -- "$src"; log "merge jsonl: $base"; return 0
        fi
        rm -- "$tmp"; log "WARN: jsonl merge failed for $base — leaving src in place"; return 1 ;;
      *)
        # snapshot / other file → newest mtime wins.
        if [ "$src" -nt "$dest" ]; then mv -f "$src" "$dest"; log "newer wins (old): $base"
        else rm -- "$src"; log "keep newer (new): $base"; fi
        return 0 ;;
    esac
  fi

  # type mismatch or other oddity — leave OLD's copy aside rather than destroy it.
  log "WARN: unhandled entry type for $base (src=$src dest=$dest) — leaving in place"
  return 1
}

# migrate_dir <old> <new>: idempotent reconcile + symlink. No-op if old is a symlink.
migrate_dir() {
  local old="$1" new="$2" rc=0

  if [ -L "$old" ]; then log "no-op: $old already a symlink → $(readlink "$old")"; return 0; fi

  mkdir -p "$new"

  if [ -d "$old" ]; then
    local entry
    shopt -s dotglob nullglob
    for entry in "$old"/*; do
      reconcile_entry "$entry" "$new/$(basename "$entry")" || rc=1
    done
    shopt -u dotglob nullglob
    if ! rmdir "$old" 2>/dev/null; then
      # Everything reconcilable was reconciled; any residue is unexpected.
      if [ "$rc" -ne 0 ] || [ -n "$(ls -A "$old" 2>/dev/null)" ]; then
        echo "migrate-state-dirs.sh: $old not empty after reconciliation; resolve manually" >&2
        log "WARN: $old not empty — NOT symlinking"; return 1
      fi
      rmdir "$old"
    fi
  fi

  ln -s "$new" "$old"
  log "migrated: $old → symlink to $new"
}

main() {
  if [ "$ASSUME_IDLE" = "1" ]; then
    # Loud stderr warning (not just the file log): this bypass is read from the ambient
    # env and is meant for hermetic tests — a stale exported var must not silently
    # disable the only live-pool protection on a real run (audit id:401c MED).
    echo "migrate-state-dirs.sh: WARNING — idle guard BYPASSED (RELAY_MIGRATE_ASSUME_IDLE/MIGRATE_SKIP_GUARD=1). Intended for tests only." >&2
    log "guard BYPASSED via ASSUME_IDLE"
  elif pool_active; then
    echo "migrate-state-dirs.sh: a relay pool looks active — refusing to migrate. Re-run when idle." >&2
    log "REFUSED: pool active"; exit 3
  fi

  migrate_dir "$CONFIG_OLD" "$CONFIG_NEW"
  migrate_dir "$CACHE_OLD" "$CACHE_NEW"

  echo "migrate-state-dirs.sh: state dirs migrated to canonical relay naming (symlinks kept)."
  log "done"
}

main "$@"
