#!/usr/bin/env bash
# commit-ledger.sh — atomic, flock-guarded, SCOPED commit of a relay ledger edit
# in a repo's MAIN checkout (id:2147).
#
# Why: the relay's gate-detection (id:3801) and the LLM-prose steps of
# `/relay review` / `/relay human` write ROADMAP/TODO/REVIEW_ME annotations
# (lane back-fill, ROADMAP re-derivation, gate notes) directly in the main
# checkout (id:15d5, NOT a worktree). When a run ends/dies before committing
# (mid-run API error, session kill, or simply no per-edit commit step), the
# modified-but-uncommitted ledger becomes dirty residue that trips the
# dirty-guard (id:aa93): every later pool run DEFERS the repo to avoid data
# loss, so the residue can never be cleared by the very review that would
# commit it — a self-perpetuating dirty backlog. This helper makes each such
# write commit ATOMICALLY per-repo so an interruption can never strand a
# dirty-uncommitted ledger.
#
# Discipline (the load-bearing guarantees, all tested):
#   - Stages ONLY the named ledger paths (`git add -- <path>`), NEVER `git add -A`
#     (id:debf precedent) — a concurrent edit to an UNRELATED file is left alone.
#   - flock-serialized on the repo's `.git-lock-push.lock` (the repo-wide push
#     serializer, so a concurrent integrator/push can't interleave), 30s timeout.
#   - NEVER `git stash` / `git checkout --` / `git reset --hard` / `git clean`
#     (id:aa93) — it only ADDS and COMMITS; foreign-dirty paths it was not asked
#     to commit are never touched.
#   - COMMIT-ONLY: it does NOT push (relay children must never push; the
#     foreground strong/human session pushes via its normal end-of-turn path or
#     git-lock-push.sh --ff-only). A local commit alone clears the dirty-guard,
#     which is the whole point — push is a separate, later concern.
#   - Clean no-op: if none of the named paths have staged changes, it makes NO
#     commit and exits 0 (idempotent; safe to call when nothing changed).
#
# Usage:
#   commit-ledger.sh <repo-root> -m <msg> <ledger-path> [<ledger-path> ...]
#   ledger-paths may be absolute or relative to <repo-root>.
# Exit: 0 = committed (or clean no-op); 2 = misuse; 1 = git failure.
#
# Short stdout; details to ~/.claude/logs/relay-commit-ledger.log.

set -euo pipefail

export GIT_TERMINAL_PROMPT=0

LOG="${HOME}/.claude/logs/relay-commit-ledger.log"
mkdir -p "$(dirname "$LOG")"
log() { printf '%s %s\n' "$(date -Is)" "$*" >> "$LOG" 2>/dev/null || true; }

die() { echo "ERROR: $*" >&2; exit 2; }

repo="${1:-}"
[[ -n "$repo" ]] || die "usage: commit-ledger.sh <repo-root> -m <msg> <ledger-path>..."
shift

msg=""
paths=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -m) shift; msg="${1:-}" ;;
    -m*) msg="${1#-m}" ;;
    --) shift; while [[ $# -gt 0 ]]; do paths+=("$1"); shift; done; break ;;
    -*) die "unknown flag: $1" ;;
    *) paths+=("$1") ;;
  esac
  shift || true
done

[[ -n "$msg" ]] || die "-m <commit-message> is required"
[[ ${#paths[@]} -gt 0 ]] || die "at least one ledger-path is required"

repo="$(cd "$repo" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)" \
  || die "not a git repo: ${1:-}"

# Resolve each path to a repo-relative path; reject anything outside the repo.
rel_paths=()
for p in "${paths[@]}"; do
  if [[ "$p" = /* ]]; then abs="$p"; else abs="$repo/$p"; fi
  # normalize without requiring the file to exist yet (it always should here)
  rel="$(cd "$repo" && realpath -m --relative-to="$repo" "$abs")"
  case "$rel" in
    ../*|/*) die "ledger path escapes repo root: $p" ;;
  esac
  rel_paths+=("$rel")
done

lock_file="$repo/.git-lock-push.lock"
exec 8>"$lock_file"
if ! flock -x -w 30 8; then
  echo "WARNING: could not acquire ledger lock after 30s; ledger NOT committed." >&2
  log "LOCK-TIMEOUT repo=$repo paths=${rel_paths[*]}"
  exec 8>&-
  exit 0   # non-fatal — caller may retry; nothing was mutated
fi

cd "$repo"

# Stage ONLY the named paths — never `git add -A`. A path with no change stages
# to nothing, which is fine.
for rel in "${rel_paths[@]}"; do
  git add -- "$rel"
done

# Did our scoped stage actually capture anything? If not, clean no-op.
if git diff --cached --quiet -- "${rel_paths[@]}"; then
  log "NOOP repo=$repo paths=${rel_paths[*]} (nothing staged)"
  exec 8>&-
  exit 0
fi

if git commit -m "$msg" -- "${rel_paths[@]}" >>"$LOG" 2>&1; then
  short="$(git rev-parse --short HEAD)"
  echo "committed ${#rel_paths[@]} ledger file(s) @ $short"
  log "COMMIT repo=$repo sha=$short paths=${rel_paths[*]} msg=$msg"
  exec 8>&-
  exit 0
else
  echo "ERROR: git commit failed (see $LOG)" >&2
  log "COMMIT-FAIL repo=$repo paths=${rel_paths[*]}"
  exec 8>&-
  exit 1
fi
