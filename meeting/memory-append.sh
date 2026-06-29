#!/usr/bin/env bash
# memory-append.sh — flock-guarded pointer append to a MEMORY.md index
#
# Usage:
#   memory-append.sh <memory-md-path> <pointer-line>
#
# Appends a single pointer line to the given MEMORY.md under an exclusive
# flock, preventing lost-update races when two concurrent sessions both try
# to update the shared index.  The individual per-fact files (same directory)
# are uniquely named and have no contention; only the shared index does.
#
# Lock file: <memory-md-path>.lock  (matches "*.lock" in .gitignore)
# Creates <memory-md-path> and its parent directory if they do not exist.
#
# Related: meeting/append.sh (discoveries/personas/inbox); id:6f61

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <memory-md-path> <pointer-line>" >&2
  exit 1
fi

dest="$1"
pointer="$2"

if [[ -z "$dest" ]]; then
  echo "Error: <memory-md-path> must not be empty" >&2
  exit 1
fi
if [[ -z "$pointer" ]]; then
  echo "Error: <pointer-line> must not be empty" >&2
  exit 1
fi

# Resolve to an absolute path so the lock file is stable regardless of cwd.
dest="$(readlink -f -- "$dest" 2>/dev/null || realpath -- "$dest" 2>/dev/null || { echo "$dest"; })"

lock_file="${dest}.lock"

# Create parent directory and file if absent (outside the lock — harmless race,
# the file is only guaranteed complete after the lock is acquired below).
mkdir -p "$(dirname "$dest")"
[[ -f "$dest" ]] || touch "$dest"

(
  flock -x 9
  # Ensure trailing newline before appending so the pointer starts on its own line.
  if [[ -s "$dest" ]]; then
    last_char="$(tail -c1 "$dest")"
    if [[ "$last_char" != $'\n' && "$last_char" != "" ]]; then
      printf '\n' >> "$dest"
    fi
  fi
  printf '%s\n' "$pointer" >> "$dest"
) 9>"$lock_file"
