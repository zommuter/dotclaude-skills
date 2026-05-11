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

# Only run SSH agent setup on machines with ssh-askpass (not fievel/Raspbian)
if [[ "$(hostname)" != "fievel" ]]; then
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

# Read from file if -f provided, then delete it
if [[ -z "$entry" && -n "$entry_file" ]]; then
  entry="$(cat "$entry_file")"
  rm -f "$entry_file"
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
  echo "WARNING: diary lock timeout after 30s. Entry saved to $pending" >&2
  exec 9>&-
  exit 0
fi

# Replay any entries that were saved due to previous lock timeouts
for _pending in "$DIARY_DIR"/.diary-pending-*; do
  [ -f "$_pending" ] || continue
  cat "$_pending" >> "$DIARY_FILE"
  rm -f "$_pending"
done

git pull --rebase

printf '\n%s\n%s\n' "$header" "$entry" >> "$DIARY_FILE"
git add DIARY.md
git commit -m "$commit_msg"
git push

exec 9>&-
