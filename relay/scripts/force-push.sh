#!/usr/bin/env bash
# force-push.sh — CONTROLLED, deliberate-human force-push for a single repo (id:de51).
#
# Context: on 2026-06-15 the fievel git server was hardened with
#   git config --global receive.denyNonFastForwards true
#   git config --global receive.denyDeletes true
# so any force/purge push is server-REJECTED. That also blocks the user's OCCASIONAL
# legitimate force-push. This script is the controlled override: it keeps
# accidental/automated force-pushes IMPOSSIBLE (a confirm gate that can never be set
# by the relay pool), but lets a DELIBERATE human briefly lift the guard for ONE repo,
# push with --force-with-lease, then re-arm the guard — even if the push fails.
#
# Usage:
#   FORCE_PUSH_CONFIRM=1 force-push.sh <repo-path> [<refspec>]
#     <repo-path>  Working repo to push FROM (its push remote/host are resolved).
#     <refspec>    Optional refspec to push (default: the repo's current branch).
#
# Safety design (why this can't run unattended):
#   - Requires FORCE_PUSH_CONFIRM=1 in the env. The relay pool/executors never set it,
#     so automated or accidental invocation refuses with exit 2 before touching anything.
#   - Uses --force-with-lease (NOT bare --force): refuses if the remote moved since the
#     last fetch, so it can't silently clobber someone else's push.
#   - Lifts the server guard PER-REPO only (the one bare repo), never --global.
#   - An EXIT trap ALWAYS restores receive.denyNonFastForwards=true so the guard is
#     re-armed whether the push succeeds, fails, or the script is interrupted.
#   - If the bare repo path can't be resolved, aborts WITHOUT touching server config.
#
# Log: ~/.claude/logs/relay-force-push.log
set -euo pipefail

LOG="${FORCE_PUSH_LOG:-$HOME/.claude/logs/relay-force-push.log}"
mkdir -p "$(dirname "$LOG")"
log() { printf '%s force-push.sh %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >>"$LOG" 2>/dev/null || true; }
say() { printf '==> %s\n' "$*"; log "$*"; }

# ---- 0. Confirm gate (checked FIRST, before any repo/server work) ------------------
if [ "${FORCE_PUSH_CONFIRM:-}" != "1" ]; then
  echo "REFUSED: force-push.sh requires explicit confirmation." >&2
  echo "  This is a deliberate, human-only operation — it can never run unattended." >&2
  echo "  Re-run with: FORCE_PUSH_CONFIRM=1 $0 <repo-path> [<refspec>]" >&2
  log "REFUSED (no FORCE_PUSH_CONFIRM) args=$*"
  exit 2
fi

# ---- 1. Args -----------------------------------------------------------------------
repo="${1:-}"
refspec="${2:-}"
if [ -z "$repo" ]; then
  echo "Usage: FORCE_PUSH_CONFIRM=1 $0 <repo-path> [<refspec>]" >&2
  exit 2
fi
if [ ! -d "$repo" ]; then
  echo "ERROR: repo path not found: $repo" >&2
  exit 2
fi

# ---- 2. Resolve remote, host, bare repo path --------------------------------------
remote="$(git -C "$repo" remote 2>/dev/null | head -1)"
[ -n "$remote" ] || { echo "ERROR: no git remote in $repo" >&2; exit 2; }

push_url="$(git -C "$repo" remote get-url --push "$remote")"
say "repo=$repo remote=$remote push-url=$push_url"

# Expected ssh form: <host>:<path>  e.g. fievel:src/dotclaude-skills.git
# Host = part before the first ':'; bare path = part after it.
if [[ "$push_url" != *:* ]]; then
  echo "ERROR: push url '$push_url' is not the expected <host>:<path> ssh form." >&2
  echo "  Cannot resolve the bare repo to lift its guard — aborting without touching server config." >&2
  exit 2
fi
host="${push_url%%:*}"
bare_path="${push_url#*:}"
# Guard against scp-style urls that still carry a user@ or extra path noise we can't trust.
if [ -z "$host" ] || [ -z "$bare_path" ]; then
  echo "ERROR: could not resolve host/bare-path from '$push_url' — aborting without touching server config." >&2
  exit 2
fi

# ---- 3. Refspec (default current branch) ------------------------------------------
if [ -z "$refspec" ]; then
  refspec="$(git -C "$repo" rev-parse --abbrev-ref HEAD)"
fi
say "host=$host bare=$bare_path refspec=$refspec"

# ---- 4. Lift guard for THIS bare repo only, restore on EXIT ------------------------
GUARD_LIFTED=0
restore_guard() {
  if [ "$GUARD_LIFTED" = "1" ]; then
    say "re-arming guard: ssh $host git -C $bare_path config receive.denyNonFastForwards true"
    if ssh "$host" "git -C '$bare_path' config receive.denyNonFastForwards true"; then
      say "guard re-armed on $host:$bare_path"
    else
      echo "WARNING: failed to re-arm receive.denyNonFastForwards on $host:$bare_path — RE-ARM MANUALLY:" >&2
      echo "  ssh $host \"git -C '$bare_path' config receive.denyNonFastForwards true\"" >&2
      log "FAILED to re-arm guard on $host:$bare_path"
    fi
  fi
}
trap restore_guard EXIT

say "lifting guard: ssh $host git -C $bare_path config receive.denyNonFastForwards false"
ssh "$host" "git -C '$bare_path' config receive.denyNonFastForwards false"
GUARD_LIFTED=1

# ---- 5. The force-push (--force-with-lease, NOT bare --force) ----------------------
say "pushing: git -C $repo push --force-with-lease $remote $refspec"
git -C "$repo" push --force-with-lease "$remote" "$refspec"
say "force-push complete"

# EXIT trap re-arms the guard from here.
