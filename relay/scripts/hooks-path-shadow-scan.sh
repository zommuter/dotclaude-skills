#!/usr/bin/env bash
# hooks-path-shadow-scan.sh — mechanical detector for repo-local `core.hooksPath`
# SHADOWING the global hook dir, across the relay own-set (id:2bc6, TODO twin id:2bc6).
#
# WHY: the two global hooks this fleet relies on (pre-push privacy gate, pre-commit
# lane-vocab ratchet) are wired via `git config --global core.hooksPath`. A LOCAL
# `core.hooksPath` set inside one own repo REPLACES the global setting for that repo
# rather than layering on top of it (git has no hook-dir search path) — so that repo
# silently loses BOTH global hooks with no error anywhere. On 2026-08-18 this held for
# 7 of 51 own repos, one of them pointing at a *different repo's* hook directory (a
# rename residue). The condition recurs on every clone/move/rename, so a one-off manual
# sweep rots; this is the recurring check id:293f's sweep is gated on.
#
# READ-ONLY: `git config` reads + a directory listing. NEVER writes, NEVER unsets a
# repo-local core.hooksPath — classification is a human call (see below), not this
# script's to act on.
#
# Consumes the canonical own-set primitive (lib-own-repos.sh's own_repos, honoring
# `# path:` overrides) — NEVER a `~/src` glob, never a re-derived repo list (id:7877).
#
# Classification per repo carrying a LOCAL core.hooksPath:
#   EMPTY-SHADOW  the configured dir has no real (non-`.sample`) hook file — the global
#                 gates are silently hollowed with nothing to show for it. Actionable:
#                 unset the local core.hooksPath (a human call, not this script).
#   DELIBERATE    the configured dir DOES carry real hook file(s) — a repo that
#                 deliberately wants repo-local hooks. Still loses the global gates, but
#                 fixing it means MERGING the global hooks in, not blindly unsetting —
#                 an owner call, out of scope here.
# A repo with NO local core.hooksPath (the correct/default state) gets no row at all —
# report only what's actionable or needs a decision, never a clean bill of health per repo.
#
# Usage:
#   hooks-path-shadow-scan.sh [--all]
#     (only mode today: scans every relay.toml `classification = "own"` repo — same
#     default every other fleet-wide scan in this dir uses; --all is accepted as a
#     no-op alias so the flag reads the same as its siblings)
#   Reads $RELAY_TOML (default ~/.config/relay/relay.toml) and $SRC_DIR (default
#   ~/src), like every other own-set consumer here.
#   Unknown flag = LOUD reject (nonzero exit). Report-only otherwise: exit 0 even with
#   findings — only misuse exits nonzero.
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="${SRC_DIR:-$HOME/src}"
RELAY_TOML="${RELAY_TOML:-$HOME/.config/relay/relay.toml}"
LOG="${HOOKS_PATH_SHADOW_LOG:-$HOME/.claude/logs/hooks-path-shadow-scan.log}"

# shellcheck source=./lib-own-repos.sh
source "$SCRIPTS_DIR/lib-own-repos.sh"

log() { mkdir -p "$(dirname "$LOG")" 2>/dev/null || true; printf '%(%Y-%m-%dT%H:%M:%S%z)T %s\n' -1 "$*" >>"$LOG" 2>/dev/null || true; }

for arg in "$@"; do
  case "$arg" in
    --all) ;; # default/only mode; accepted as a no-op for flag-symmetry with siblings
    *)
      echo "hooks-path-shadow-scan.sh: unknown argument '$arg' (only --all is accepted)" >&2
      exit 1
      ;;
  esac
done

# resolve a possibly-relative core.hooksPath the way git does: relative to the
# WORKING TREE top-level (not the .git dir) when the repo has a working tree.
resolve_hooks_dir() {
  local repo="$1" hp="$2"
  case "$hp" in
    /*) printf '%s\n' "$hp" ;;
    "~"|"~/"*) printf '%s\n' "${hp/#\~/$HOME}" ;;
    *) printf '%s\n' "$repo/$hp" ;;
  esac
}

# a "real" hook: a regular file in the dir that does NOT end in .sample. Executable
# bit is not required — git only cares that the file exists (and would fail to run a
# non-executable one, which is itself worth surfacing as DELIBERATE-but-broken, not
# silently reclassified as EMPTY-SHADOW).
has_real_hook() {
  local dir="$1"
  [[ -d "$dir" ]] || return 1
  local f
  for f in "$dir"/*; do
    [[ -e "$f" ]] || continue
    [[ -f "$f" ]] || continue
    [[ "$f" == *.sample ]] && continue
    return 0
  done
  return 1
}

if ! own="$(own_repos)"; then
  echo "hooks-path-shadow-scan.sh: relay.toml exists but failed to parse ($RELAY_TOML)" >&2
  exit 1
fi

empty_shadow=0
deliberate=0
scanned=0

if [[ -n "$own" ]]; then
  while IFS=$'\t' read -r name path; do
    [[ -n "$name" ]] || continue
    scanned=$((scanned + 1))
    if [[ ! -d "$path/.git" && ! -f "$path/.git" ]]; then
      echo "SKIP $name — not a git repo on disk ($path)" >&2
      continue
    fi
    hp="$(git -C "$path" config --local --get core.hooksPath 2>/dev/null || true)"
    [[ -n "$hp" ]] || continue
    dir="$(resolve_hooks_dir "$path" "$hp")"
    if has_real_hook "$dir"; then
      deliberate=$((deliberate + 1))
      echo "DELIBERATE $name core.hooksPath=$hp (resolved: $dir) — real repo-local hook(s) present; owner call to merge global hooks in, not to unset"
    else
      empty_shadow=$((empty_shadow + 1))
      echo "EMPTY-SHADOW $name core.hooksPath=$hp (resolved: $dir) — no non-sample hook file; global gates (pre-push privacy, pre-commit lane-vocab) are silently hollowed here"
    fi
  done <<<"$own"
fi

echo "hooks-path-shadow-scan: $scanned own repo(s) scanned, $empty_shadow EMPTY-SHADOW, $deliberate DELIBERATE"
log "scanned=$scanned empty_shadow=$empty_shadow deliberate=$deliberate"
exit 0
