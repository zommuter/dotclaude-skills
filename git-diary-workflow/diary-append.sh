#!/usr/bin/env bash
# diary-append.sh — Append an entry to DIARY.md with flock-based concurrency.
#
# Usage:
#   diary-append.sh -m "diary: description" -p ~/src/project -e "entry text"
#   diary-append.sh -m "diary: description" -p ~/src/project -f entry.txt
#   diary-append.sh -m "diary: description" -p ~/src/project < entry.txt
#
# Options:
#   -m MSG   Git commit message (required)
#   -p PATH  Project path (required, used in header)
#   -e TEXT  Entry body (if omitted, reads from -f or stdin)
#   -f FILE  Read entry from file (deleted after reading)
#   -s SID   Session ID (overrides CLAUDE_SESSION_ID env var)
#
# The script auto-generates the header line:
#   ## YYYYMMDD-HHMMSS hostname:session project/path

set -euo pipefail

DIARY_DIR="${DIARY_REPO_DIR:-$HOME/src/claude-diary}"
DIARY_FILE="$DIARY_DIR/DIARY.md"

# --- SSH agent setup ---
_own_agent=false

ensure_ssh_agent() {
  # Already have a working agent with keys?
  if ssh-add -l &>/dev/null; then
    return 0
  fi

  # Agent running but no keys loaded? Just add.
  if [[ -n "${SSH_AUTH_SOCK:-}" ]]; then
    SSH_ASKPASS=/usr/lib/ssh/ssh-askpass SSH_ASKPASS_REQUIRE=prefer ssh-add
    return 0
  fi

  # No agent at all — start one.
  eval "$(ssh-agent -s)" >/dev/null
  _own_agent=true
  SSH_ASKPASS=/usr/lib/ssh/ssh-askpass SSH_ASKPASS_REQUIRE=prefer ssh-add
}

cleanup_ssh_agent() {
  if [[ "$_own_agent" == true && -n "${SSH_AGENT_PID:-}" ]]; then
    eval "$(ssh-agent -k)" >/dev/null 2>&1 || true
  fi
}
trap cleanup_ssh_agent EXIT

# Only run SSH agent setup on machines with ssh-askpass (not fievel/Raspbian).
# DIARY_SKIP_SSH=1 is a test seam: hermetic tests use a file:// remote and must
# not touch a real ssh-agent.
if [[ "$(hostname)" != "fievel" && -z "${DIARY_SKIP_SSH:-}" ]]; then
  ensure_ssh_agent
fi

# --- Args ---
commit_msg=""
entry=""
entry_file=""
project_path=""
session_id=""

while getopts "m:e:f:p:s:" opt; do
  case "$opt" in
    m) commit_msg="$OPTARG" ;;
    e) entry="$OPTARG" ;;
    f) entry_file="$OPTARG" ;;
    p) project_path="$OPTARG" ;;
    s) session_id="$OPTARG" ;;
    *) echo "Usage: $0 -m 'commit message' -p 'project/path' [-e 'entry text' | -f file]" >&2; exit 1 ;;
  esac
done

if [[ -z "$commit_msg" ]]; then
  echo "Error: -m 'commit message' is required" >&2
  exit 1
fi

if [[ -z "$project_path" ]]; then
  echo "Error: -p 'project path' is required" >&2
  exit 1
fi

# Resolve any relative -f path to absolute before any cd changes the working dir.
if [[ -n "$entry_file" ]]; then
  entry_file="$(readlink -f "$entry_file")"
fi

# Read from file if -f provided. Do NOT delete it yet — it is only consumed
# (rm'd) after commit+push SUCCEEDS. On any failure it is moved to a `.failed/`
# quarantine instead (see on_failure below) so the entry is never silently lost
# (id:f8df / id:4347 silent-swallow class).
if [[ -z "$entry" && -n "$entry_file" ]]; then
  entry="$(cat "$entry_file")"
fi

# Read from stdin if neither -e nor -f provided
if [[ -z "$entry" ]]; then
  entry="$(cat)"
fi

if [[ -z "$entry" ]]; then
  echo "Error: no entry content provided (use -e or pipe to stdin)" >&2
  exit 1
fi

cd "$DIARY_DIR"

# Use fd-based flock so we can run arbitrary shell inside the lock.
# git pull --rebase is inside the lock so two sessions can't interleave
# pull+push and produce a non-fast-forward failure.
_git_dir="$(git rev-parse --git-dir)"
exec 9>"$_git_dir/diary.lock"

# Compute header before acquiring lock (date/hostname don't need git state)
timestamp=$(date +%Y%m%d-%H%M%S)
host=$(hostname)
session="${session_id:-${CLAUDE_SESSION_ID:-no-session}}"
header="## $timestamp $host:$session $project_path"

if ! flock -x -w 30 9; then
  # Lock timeout — save entry to a pending file so it's never lost.
  # The next diary-append.sh invocation will replay it inside the lock.
  pending="$DIARY_DIR/.diary-pending-$timestamp"
  printf '\n%s\n%s\n' "$header" "$entry" > "$pending"
  [[ -n "$entry_file" ]] && rm -f "$entry_file"
  echo "WARNING: diary lock timeout after 30s. Entry saved to $pending" >&2
  exec 9>&-
  exit 0
fi

# --- Failure quarantine ---
# Anything that goes wrong from here on (pull/rebase conflict, commit, push)
# must NOT lose the entry: quarantine it to a loudly-announced `.failed/` file
# instead of letting it vanish with the -f temp file. `.diary-pending-*` (lock
# timeouts) and `.failed/*` (this) share the same replay loop below, so a
# quarantined entry is appended exactly once on the next successful run.
on_failure() {
  git rebase --abort >/dev/null 2>&1 || true
  mkdir -p "$DIARY_DIR/.failed"
  local dest="$DIARY_DIR/.failed/entry-$timestamp-$$"
  printf '\n%s\n%s\n' "$header" "$entry" > "$dest"
  [[ -n "$entry_file" ]] && rm -f "$entry_file"
  echo "ERROR: diary-append failed (pull/commit/push). Entry quarantined at: $dest" >&2
  echo "It will be replayed automatically on the next successful diary-append.sh run." >&2
  exec 9>&- 2>/dev/null || true
  exit 1
}

# Pull FIRST, on the still-clean tree, BEFORE replaying anything. Replaying a
# quarantined entry appends to DIARY.md and thus DIRTIES the tree; if that ran
# before the pull, `git pull --rebase` would refuse ("cannot pull with rebase:
# You have unstaged changes") and strand the replayed text uncommitted forever
# (deadlock observed 2026-07-12, roadmap:1b18). So: pull first, then replay +
# the current entry ride the SAME commit below.
#
# Pin the explicit branch/refspec: a bare `git pull --rebase` can hit
# "Cannot rebase onto multiple branches" under a fetch config with several
# refspecs / no configured upstream when a concurrent commit races in
# (observed 2026-07-08, id:f8df). Resolve the current branch and pull from
# `origin <branch>` explicitly instead of relying on ambient tracking config.
_branch="$(git symbolic-ref --short HEAD)"
# Only rebase onto the remote branch when it actually exists. On the very first
# push of a new branch the remote ref is absent and `git pull --rebase origin
# <branch>` fails with "couldn't find remote ref" — that is "nothing upstream
# to rebase onto", not a real failure, so proceed straight to commit+push below
# rather than quarantining a perfectly good entry. (>/dev/null drops ls-remote's
# matched-ref stdout; we only consult its --exit-code status.)
if git ls-remote --exit-code --heads origin "$_branch" >/dev/null; then
  if ! git pull --rebase origin "$_branch"; then
    on_failure
  fi
fi

# Replay any entries saved by previous lock timeouts or failures, then append
# the current entry — all into DIARY.md for a SINGLE commit. The quarantine
# files are NOT removed yet: they're consumed (rm'd) only AFTER the commit
# succeeds, so a failed commit leaves them on disk to be replayed next run
# (exactly-once).
_replayed=()
for _pending in "$DIARY_DIR"/.diary-pending-* "$DIARY_DIR"/.failed/entry-*; do
  [ -f "$_pending" ] || continue
  cat "$_pending" >> "$DIARY_FILE"
  _replayed+=("$_pending")
done

printf '\n%s\n%s\n' "$header" "$entry" >> "$DIARY_FILE"
git add DIARY.md
if ! git commit -m "$commit_msg"; then
  # Restore DIARY.md to HEAD so the replayed+current text never strands as a
  # dirty tree; the current entry is quarantined by on_failure and the replay
  # files (untouched above) remain on disk for the next run.
  git checkout HEAD -- DIARY.md || true
  on_failure
fi

# Commit succeeded: the replayed entries are now in committed history, so their
# quarantine files are safe to consume (exactly-once).
for _done in ${_replayed[@]+"${_replayed[@]}"}; do
  rm -f "$_done"
done

if ! git push origin "$_branch"; then
  # The entries are already committed locally, so they are NOT lost — the next
  # successful run pulls (rebasing this commit) and pushes it. Re-quarantining
  # here would double-append, so we do not call on_failure; just fail loudly.
  echo "ERROR: diary-append committed locally but push failed. The commit is safe" >&2
  echo "and will be pushed on the next successful diary-append.sh run." >&2
  [[ -n "$entry_file" ]] && rm -f "$entry_file"
  exec 9>&- 2>/dev/null || true
  exit 1
fi

# Success: the -f temp file (if any) is now safe to consume.
[[ -n "$entry_file" ]] && rm -f "$entry_file"

exec 9>&-
