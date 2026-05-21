#!/usr/bin/env bash
# orphan-scan.sh — sibling to append.sh, cost-of.sh
# Usage: orphan-scan.sh [<root-dir>]
# Scans <root>/docs/meeting-notes/*.md for ID-bearing unchecked action items whose
# <!-- id:XXXX --> token is absent from the union of TODO.md + TODO.archive.md.
# Un-IDed lines are skipped (clean cutover; legacy notes stay frozen).
# Prints candidate orphan lines to stdout; writes one log line to ~/.claude/logs/meeting-orphan-scan.log.
set -euo pipefail

ROOT="${1:-$(git rev-parse --show-toplevel)}"
NOTES_DIR="$ROOT/docs/meeting-notes"
LOG="$HOME/.claude/logs/meeting-orphan-scan.log"
mkdir -p "$(dirname "$LOG")"

limit="${ORPHAN_SCAN_LIMIT:-10}"
start_ms=$(date +%s%3N)
todo="$(cat "$ROOT/TODO.md" "$ROOT/TODO.archive.md" 2>/dev/null || true)"
notes=0
id_lines=0
candidates=0
output_lines=()

for f in $(ls -r1 "$NOTES_DIR"/*.md 2>/dev/null); do
  [[ -f "$f" ]] || continue
  [[ "$(basename "$f")" == "meeting-style.md" ]] && continue
  notes=$((notes+1))
  while IFS=: read -r lineno text; do
    # Only consider lines that carry an <!-- id:XXXX --> token
    token=$(echo "$text" | grep -oP '(?<=<!-- id:)[0-9a-f]{4}(?= -->)' || true)
    [[ -z "$token" ]] && continue
    id_lines=$((id_lines+1))
    if ! grep -qF "id:$token" <<<"$todo"; then
      candidates=$((candidates+1))
      output_lines+=("$(basename "$f"):$lineno  $text")
    fi
  done < <(grep -n '^- \[ \] ' "$f" || true)
done

runtime_ms=$(( $(date +%s%3N) - start_ms ))
printf '%s\t%s\tnotes=%d\tid_lines=%d\tcandidates=%d\truntime_ms=%d\n' \
  "$(date -Iseconds)" "$(basename "$ROOT")" "$notes" "$id_lines" "$candidates" "$runtime_ms" \
  >> "$LOG"

total=${#output_lines[@]}
if [[ "$limit" -gt 0 && "$total" -gt "$limit" ]]; then
  printf '%s\n' "${output_lines[@]:0:$limit}"
  suppressed=$(( total - limit ))
  printf '# orphan-scan: %d more candidates suppressed (cap=%d); set ORPHAN_SCAN_LIMIT=0 for full output\n' \
    "$suppressed" "$limit"
else
  printf '%s\n' "${output_lines[@]:-}"
fi
