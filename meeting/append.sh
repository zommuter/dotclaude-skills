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

# new-id subcommand: emit a collision-free random 4-hex token for meeting action items.
# Usage: append.sh new-id [<root-dir>]
if [[ "${1:-}" == "new-id" ]]; then
  ROOT="${2:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  existing=$(grep -rho 'id:[0-9a-f]\{4\}' \
    "$ROOT/docs/meeting-notes" \
    "$ROOT/TODO.md" \
    "$ROOT/TODO.archive.md" 2>/dev/null || true)
  while true; do
    token=$(python3 -c 'import secrets; print(secrets.token_hex(2))')
    if ! grep -qF "id:$token" <<< "${existing}"; then
      echo "$token"
      exit 0
    fi
  done
fi

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
