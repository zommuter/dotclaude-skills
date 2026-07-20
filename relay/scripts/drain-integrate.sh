#!/usr/bin/env bash
# drain-integrate.sh — one-writer-to-main SERIAL integrator for the drain
# driver (id:2062, id:ebbe child, meeting 2026-07-19-2035 D5 + D4
# merge-time re-enforcement).
#
# Executors produce code in their OWN worktree branches only; this single
# driver merges each branch --no-ff SERIALLY into main and is the ONLY
# writer to main. At merge time the disjoint-path rule (id:5367) is
# RE-ENFORCED via disjoint-greenlight.sh merge-check: the incoming
# branch's touched paths are checked against everything already merged
# this round (the --merged-so-far file). A non-empty intersection is a
# HANDBACK (no merge attempted, branch left intact), never an
# auto-resolve. A textual merge conflict likewise aborts cleanly
# (git merge --abort) and hands back. NO force/destructive git flags.
#
# Usage:
#   drain-integrate.sh --repo <main-checkout> --branch <br> --merged-so-far <file>
#
# Exit codes:
#   0  merged --no-ff; the branch's touched paths were APPENDED to <file>.
#   2  usage / environment error.
#   4  overlap handback — branch touches a path already in <file>; NO
#      merge attempted; overlapping path(s) printed on stdout; branch intact.
#   5  conflict handback — merge attempted, conflicted, cleanly aborted;
#      tree left clean; main unmoved.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GREENLIGHT="$SCRIPT_DIR/disjoint-greenlight.sh"

err() { echo "ERROR: $*" >&2; }

REPO="" BRANCH="" MERGED=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)          REPO="$2"; shift 2 ;;
    --branch)        BRANCH="$2"; shift 2 ;;
    --merged-so-far) MERGED="$2"; shift 2 ;;
    *) err "unknown argument: $1"; exit 2 ;;
  esac
done

[[ -n "$REPO" && -n "$BRANCH" && -n "$MERGED" ]] || {
  err "usage: drain-integrate.sh --repo <dir> --branch <br> --merged-so-far <file>"
  exit 2
}
[[ -d "$REPO/.git" || -e "$REPO/.git" ]] || { err "not a git repo: $REPO"; exit 2; }
git -C "$REPO" rev-parse -q --verify "$BRANCH" >/dev/null 2>&1 || {
  err "branch not found: $BRANCH"; exit 2; }
[[ -f "$MERGED" ]] || { err "merged-so-far file not found: $MERGED"; exit 2; }
[[ -x "$GREENLIGHT" ]] || { err "disjoint-greenlight.sh not found/executable: $GREENLIGHT"; exit 2; }

# Touched paths = diff of the branch against its merge-base with the
# current HEAD (main). Fail-closed: if we cannot compute a merge-base or
# the diff, treat it as an environment error rather than merging blind.
BASE="$(git -C "$REPO" merge-base HEAD "$BRANCH" 2>/dev/null)" || {
  err "cannot compute merge-base of HEAD and $BRANCH"; exit 2; }

TOUCHED_FILE="$(mktemp)"
trap 'rm -f "$TOUCHED_FILE"' EXIT
git -C "$REPO" diff --name-only "$BASE" "$BRANCH" > "$TOUCHED_FILE" || {
  err "cannot compute touched paths for $BRANCH"; exit 2; }

# --- D4 merge-time re-enforcement: overlap → exit 4 handback, NO merge ---------
overlaps="$("$GREENLIGHT" merge-check --touched "$TOUCHED_FILE" --merged "$MERGED")"
mc_rc=$?
if [[ $mc_rc -ne 0 ]]; then
  if [[ -n "$overlaps" ]]; then
    # Overlap handback — name the intersecting paths on stdout, leave main
    # and the branch untouched (never auto-resolve).
    printf '%s\n' "$overlaps"
    err "overlap handback: $BRANCH touches path(s) already merged this round"
    exit 4
  fi
  # merge-check errored for another reason (bad input) — environment error.
  err "merge-check failed (rc=$mc_rc)"
  exit 2
fi

# --- serial --no-ff merge; textual conflict → clean abort, exit 5 -------------
if git -C "$REPO" -c user.email=relay@local -c user.name=relay-integrator \
     merge --no-ff -m "drain-integrate: $BRANCH" "$BRANCH" >/dev/null 2>&1; then
  # Success — append this branch's touched paths to the merged-so-far set.
  cat "$TOUCHED_FILE" >> "$MERGED"
  exit 0
fi

# Merge failed — abort cleanly (no force) and hand back.
git -C "$REPO" merge --abort >/dev/null 2>&1 || true
err "conflict handback: $BRANCH did not merge cleanly; aborted"
exit 5
