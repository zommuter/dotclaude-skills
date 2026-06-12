#!/usr/bin/env bash
# append.sh — append a line or block to a meeting-skill registry file
#
# Usage:
#   append.sh -t {discoveries|personas|inbox} -e "line text"
#   append.sh -t {discoveries|personas|inbox} -f entry.txt
#   echo "line" | append.sh -t {discoveries|personas|inbox}
#   append.sh inbox-done <4-hex-token>   — mark a routed inbox item as adopted
#   append.sh new-id [<root>] | new-ids N [<root>]  — mint collision-free token(s)
#   append.sh scan-ids [<root>]          — list every existing token (sorted unique)
#
# No git operations — the caller (git-diary-workflow) commits the result.

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")" && pwd)"

# inbox-done <token>: flip "- [ ]" → "- [x]" on the line containing routed:<token>.
# No-op exit 0 if the token is not found or the line is already checked.
if [[ "${1:-}" == "inbox-done" ]]; then
  token="${2:-}"
  if [[ -z "$token" ]]; then
    echo "Usage: $0 inbox-done <4-hex-token>" >&2; exit 1
  fi
  inbox="$HOME/.claude/todo-inbox.md"
  [[ -f "$inbox" ]] || exit 0
  (
    flock -x 9
    python3 - "$inbox" "$token" <<'PYEOF'
import sys, pathlib
path, token = pathlib.Path(sys.argv[1]), sys.argv[2]
lines = path.read_text().splitlines(keepends=True)
needle = f"routed:{token}"
new_lines = []
for line in lines:
    if needle in line and line.lstrip().startswith("- [ ]"):
        line = line.replace("- [ ]", "- [x]", 1)
    new_lines.append(line)
path.write_text("".join(new_lines))
PYEOF
  ) 9>"${inbox}.lock"
  exit 0
fi

# Ledger: the file set scanned for existing id:XXXX tokens. Any file class that
# ORIGINATES tokens must be listed here (TODO ledger, meeting notes, relay
# ROADMAP). Files that only cite existing tokens (RELAY_LOG.md, REVIEW_ME.md,
# tests' `# roadmap:` comments) are deliberately excluded.
scan_ids() {
  local root="$1"
  grep -rho 'id:[0-9a-f]\{4\}' \
    "$root/docs/meeting-notes" \
    "$root/TODO.md" \
    "$root/TODO.archive.md" \
    "$root/ROADMAP.md" 2>/dev/null || true
}

# scan-ids: print every existing token (bare 4-hex, one per line, sorted unique).
# Usage: append.sh scan-ids [<root-dir>]
if [[ "${1:-}" == "scan-ids" ]]; then
  ROOT="${2:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  scan_ids "$ROOT" | sed 's/^id://' | sort -u
  exit 0
fi

# new-id / new-ids: emit collision-free random 4-hex token(s) for meeting action items.
# Usage: append.sh new-id  [<root-dir>]     — emit 1 token
#        append.sh new-ids N [<root-dir>]   — emit N tokens, one per line (single scan)
if [[ "${1:-}" == "new-id" || "${1:-}" == "new-ids" ]]; then
  if [[ "${1}" == "new-ids" ]]; then
    COUNT="${2:-1}"; ROOT="${3:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  else
    COUNT=1;        ROOT="${2:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  fi
  existing=$(scan_ids "$ROOT")
  emitted=0
  while (( emitted < COUNT )); do
    token=$(python3 -c 'import secrets; print(secrets.token_hex(2))')
    if ! grep -qF "id:$token" <<< "${existing}"; then
      echo "$token"
      existing+=$'\nid:'"$token"  # guard against duplicates within this batch
      (( ++emitted ))
    fi
  done
  exit 0
fi

target=""
entry=""
entry_file=""

while getopts "t:e:f:" opt; do
  case "$opt" in
    t) target="$OPTARG" ;;
    e) entry="$OPTARG" ;;
    f) entry_file="$OPTARG" ;;
    *) echo "Usage: $0 -t {discoveries|personas|inbox} [-e text | -f file]" >&2; exit 1 ;;
  esac
done

case "$target" in
  discoveries) dest="$SKILL_DIR/discoveries.md" ;;
  personas)    dest="$SKILL_DIR/personas.md" ;;
  inbox)       dest="$HOME/.claude/todo-inbox.md" ;;
  "")          echo "Error: -t is required" >&2; exit 1 ;;
  *)           echo "Error: -t must be 'discoveries', 'personas', or 'inbox'" >&2; exit 1 ;;
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
# flock prevents concurrent calls from interleaving lines
(
  flock -x 9
  printf '\n%s\n' "$entry" >> "$dest"
) 9>"${dest}.lock"
