#!/usr/bin/env bash
# orphan-scan.sh — sibling to append.sh, cost-of.sh
# Usage: orphan-scan.sh [<root-dir>]
# Scans <root>/docs/meeting-notes/*.md for unchecked action items not found in <root>/TODO.md.
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
unchecked=0
cand4=0
cand5=0
output_lines=()

for f in $(ls -r1 "$NOTES_DIR"/*.md 2>/dev/null); do
  [[ -f "$f" ]] || continue
  [[ "$(basename "$f")" == "meeting-style.md" ]] && continue
  notes=$((notes+1))
  while IFS=: read -r lineno text; do
    unchecked=$((unchecked+1))
    stripped="$(echo "$text" | sed 's/^- \[ \] //; s/\*\*//g')"
    key4="$(echo "$stripped" | awk '{print $1,$2,$3,$4}')"
    key5="$(echo "$stripped" | awk '{print $1,$2,$3,$4,$5}')"
    if ! grep -qiF "$key4" <<<"$todo"; then
      cand4=$((cand4+1))
      output_lines+=("$(basename "$f"):$lineno  $text")
    fi
    grep -qiF "$key5" <<<"$todo" || cand5=$((cand5+1))
  done < <(grep -n '^- \[ \] ' "$f" || true)
done

runtime_ms=$(( $(date +%s%3N) - start_ms ))
printf '%s\t%s\tnotes=%d\tunchecked=%d\tcand4=%d\tcand5=%d\truntime_ms=%d\n' \
  "$(date -Iseconds)" "$(basename "$ROOT")" "$notes" "$unchecked" "$cand4" "$cand5" "$runtime_ms" \
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
