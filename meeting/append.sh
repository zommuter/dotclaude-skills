#!/usr/bin/env bash
# append.sh — append a line or block to a meeting-skill registry file
#
# Usage:
#   append.sh -t {discoveries|personas|inbox} -e "line text"
#   append.sh -t {discoveries|personas|inbox} -f entry.txt
#   echo "line" | append.sh -t {discoveries|personas|inbox}
#   append.sh inbox-done <4-hex-token>   — REMOVE a routed inbox item once adopted
#   append.sh new-id [<root>] | new-ids N [<root>]  — mint collision-free token(s)
#   append.sh scan-ids [<root>]          — list every existing token (sorted unique)
#
# No git operations — the caller (git-diary-workflow) commits the result.

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")" && pwd)"

# inbox-done <token>: DELETE the routed checkbox line containing routed:<token>
# (vanish-on-resolve, user decision 2026-06-30). The inbox is a LOCAL-ONLY transient
# routing queue; the durable record is the `routed:<token>` breadcrumb in the TARGET
# repo's committed TODO/ROADMAP, so once adopted the inbox copy is pure redundancy —
# keeping a "- [x]" log only bloats the file (and was the source of the bare-token
# substring false-match in scan-routed). No-op exit 0 if the token is not found.
if [[ "${1:-}" == "inbox-done" ]]; then
  token="${2:-}"
  if [[ -z "$token" ]]; then
    echo "Usage: $0 inbox-done <4-hex-token>" >&2; exit 1
  fi
  # Honor RELAY_INBOX injection (the inbox path is local-only; never hardcode it as the
  # sole path — same convention scan-routed.sh uses, and required for hermetic tests now
  # that inbox-done is destructive).
  inbox="${RELAY_INBOX:-$HOME/.claude/todo-inbox.md}"
  [[ -f "$inbox" ]] || exit 0
  (
    flock -x 9
    python3 - "$inbox" "$token" <<'PYEOF'
import re, sys, pathlib
path, token = pathlib.Path(sys.argv[1]), sys.argv[2]
lines = path.read_text().splitlines(keepends=True)
# Anchor on the item's OWN trailing marker `<!-- routed:XXXX -->` (optional whitespace),
# not a bare substring — a sibling item's prose may legitimately CITE this token (e.g.
# "the contrast with routed:4fa9 is the signal") while its own marker is different. A
# substring test would delete that citing item too; the inbox is local-only and
# destructive (vanish-on-resolve), so a wrong match is unrecoverable (id:411d).
own_marker = re.compile(r'<!--\s*routed:' + re.escape(token) + r'\s*-->\s*$')
# Vanish: drop the routed checkbox line entirely (any "- [ ]" / "- [x]") whose OWN
# marker matches. Non-checkbox prose / sibling citations are left untouched.
new_lines = [l for l in lines
             if not (own_marker.search(l.rstrip('\n')) and l.lstrip().startswith("- ["))]
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

# new-children: mint N collision-free child tokens for a parent SPLIT and, in the same
# call, emit the parent's typed `children:` marker so the corpus stops accruing umbrella
# blindspots (id:06e3, typed-ledger-edges 2026-07-10). Prints each child token one per
# line (identical to new-ids), THEN a final line with the marker to attach at the
# parent's terminal id comment — form C: `<!-- children:t1,t2,…,tN --> <!-- id:PARENT -->`.
# Emit-only: writing the marker INTO TODO.md goes through md-merge.py (line-scoped, under
# flock); append.sh never edits ledgers, so no flock is taken here (mint only reads).
# Usage: append.sh new-children N [<root-dir>]
if [[ "${1:-}" == "new-children" ]]; then
  COUNT="${2:-1}"; ROOT="${3:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  existing=$(scan_ids "$ROOT")
  emitted=0; toks=()
  while (( emitted < COUNT )); do
    token=$(python3 -c 'import secrets; print(secrets.token_hex(2))')
    if ! grep -qF "id:$token" <<< "${existing}"; then
      echo "$token"
      toks+=("$token")
      existing+=$'\nid:'"$token"  # guard against duplicates within this batch
      (( ++emitted ))
    fi
  done
  csv="$(IFS=,; echo "${toks[*]}")"
  printf '<!-- children:%s -->\n' "$csv"
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
