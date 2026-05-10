#!/usr/bin/env bash
# append.sh — append a line or block to a meeting-skill registry file
#
# Usage:
#   append.sh -t {discoveries|personas} -e "line text"
#   append.sh -t {discoveries|personas} -f entry.txt
#   echo "line" | append.sh -t {discoveries|personas}
#
# No git operations — the caller (git-diary-workflow) commits the result.

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")" && pwd)"

target=""
entry=""
entry_file=""

while getopts "t:e:f:" opt; do
  case "$opt" in
    t) target="$OPTARG" ;;
    e) entry="$OPTARG" ;;
    f) entry_file="$OPTARG" ;;
    *) echo "Usage: $0 -t {discoveries|personas} [-e text | -f file]" >&2; exit 1 ;;
  esac
done

case "$target" in
  discoveries) dest="$SKILL_DIR/discoveries.md" ;;
  personas)    dest="$SKILL_DIR/personas.md" ;;
  "")          echo "Error: -t is required" >&2; exit 1 ;;
  *)           echo "Error: -t must be 'discoveries' or 'personas'" >&2; exit 1 ;;
esac

if [[ -n "$entry_file" ]]; then
  entry_file="$(readlink -f "$entry_file")"
  entry="$(cat "$entry_file")"
  rm -f "$entry_file"
fi

if [[ -z "$entry" ]]; then
  entry="$(cat)"
fi

if [[ -z "$entry" ]]; then
  echo "Error: no content provided (use -e, -f, or stdin)" >&2
  exit 1
fi

# Always prepend a blank line — defensive against missing trailing newline
printf '\n%s\n' "$entry" >> "$dest"
