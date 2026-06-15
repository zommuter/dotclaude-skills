#!/usr/bin/env bash
# orphan-scan.sh — sibling to append.sh, cost-of.sh
# Usage: orphan-scan.sh [--reverse|-r | --cross-ledger|-x] [<root-dir>]
# Forward (default): scans <root>/docs/meeting-notes/*.md for ID-bearing unchecked action items
#   whose <!-- id:XXXX --> token is absent from the union of TODO.md + TODO.archive.md + ROADMAP.md.
# Reverse (--reverse): finds ID-bearing checked ([x]) or inline lines absent from the TODO union
#   — the forward scan's blind spot (Step 5b skipped, items completed in-session).
# Cross-ledger (--cross-ledger): single-id-two-views guard (D2, meeting note
#   2026-06-15-0715-meeting-fables-interaction.md). Flags any <!-- id:XXXX --> token
#   present in BOTH the TODO union (TODO.md + TODO.archive.md) AND ROADMAP.md whose
#   checkbox state ([ ] vs [x]) DISAGREES across the two ledgers — i.e. work closed in
#   ROADMAP but left open in TODO (or vice versa). A duplicate id with matching state is
#   the intended single-id-two-views shape and is NOT flagged; a duplicate is only
#   detectable once promotion reuses the id, so this guard also enforces that contract.
# Un-IDed lines are skipped (clean cutover; legacy notes stay frozen).
# Prints candidate lines to stdout; writes one log line to ~/.claude/logs/meeting-orphan-scan.log.
set -euo pipefail

mode="forward"
if [[ "${1:-}" == "--reverse" || "${1:-}" == "-r" ]]; then
  mode="reverse"
  shift
elif [[ "${1:-}" == "--cross-ledger" || "${1:-}" == "-x" ]]; then
  mode="cross-ledger"
  shift
fi

ROOT="${1:-$(git rev-parse --show-toplevel)}"
NOTES_DIR="$ROOT/docs/meeting-notes"
LOG="$HOME/.claude/logs/meeting-orphan-scan.log"
mkdir -p "$(dirname "$LOG")"

limit="${ORPHAN_SCAN_LIMIT:-10}"
start_ms=$(date +%s%3N)
# Union ledger: TODO + archive + relay ROADMAP (a note item mirrored to
# ROADMAP.md instead of TODO.md is not an orphan).
todo="$(cat "$ROOT/TODO.md" "$ROOT/TODO.archive.md" "$ROOT/ROADMAP.md" 2>/dev/null || true)"
notes=0
id_lines=0
candidates=0
output_lines=()

if [[ "$mode" == "cross-ledger" ]]; then
  # Build token→state maps for the TODO union and for ROADMAP separately, then
  # flag tokens present in both whose checkbox state disagrees. A line may carry
  # multiple <!-- id:XXXX --> tokens (all share that line's state).
  declare -A todo_state roadmap_state
  while IFS= read -r l; do
    st=' '; [[ "$l" == "- [x] "* || "$l" == "- [X] "* ]] && st='x'
    while read -r tk; do
      [[ -z "$tk" ]] && continue
      todo_state["$tk"]="$st"
    done < <(grep -oP '(?<=<!-- id:)[0-9a-f]{4}(?= -->)' <<<"$l" || true)
  done < <(grep -hE '^- \[[ xX]\] ' "$ROOT/TODO.md" "$ROOT/TODO.archive.md" 2>/dev/null || true)
  while IFS= read -r l; do
    st=' '; [[ "$l" == "- [x] "* || "$l" == "- [X] "* ]] && st='x'
    while read -r tk; do
      [[ -z "$tk" ]] && continue
      roadmap_state["$tk"]="$st"
    done < <(grep -oP '(?<=<!-- id:)[0-9a-f]{4}(?= -->)' <<<"$l" || true)
  done < <(grep -hE '^- \[[ xX]\] ' "$ROOT/ROADMAP.md" 2>/dev/null || true)
  for tk in "${!todo_state[@]}"; do
    [[ -n "${roadmap_state[$tk]:-}" ]] || continue
    id_lines=$((id_lines+1))
    if [[ "${todo_state[$tk]}" != "${roadmap_state[$tk]}" ]]; then
      candidates=$((candidates+1))
      output_lines+=("id:$tk — TODO:[${todo_state[$tk]}] ROADMAP:[${roadmap_state[$tk]}] (checkbox state disagrees across ledgers)")
    fi
  done
else
for f in $(ls -r1 "$NOTES_DIR"/*.md 2>/dev/null); do
  [[ -f "$f" ]] || continue
  [[ "$(basename "$f")" == "meeting-style.md" ]] && continue
  notes=$((notes+1))
  if [[ "$mode" == "forward" ]]; then
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
  else
    # Reverse mode: all ID-bearing lines EXCEPT unchecked action items (forward scan's domain)
    while IFS=: read -r lineno text; do
      # Skip unchecked action items — covered by the forward scan
      [[ "${text:0:6}" == "- [ ] " ]] && continue
      token=$(echo "$text" | grep -oP '(?<=<!-- id:)[0-9a-f]{4}(?= -->)' || true)
      [[ -z "$token" ]] && continue
      id_lines=$((id_lines+1))
      if ! grep -qF "id:$token" <<<"$todo"; then
        candidates=$((candidates+1))
        if [[ "${text:0:6}" == "- [x] " ]]; then
          state="[x]"
        else
          state="inline"
        fi
        output_lines+=("$(basename "$f"):$lineno  $state $text")
      fi
    done < <(grep -n '<!-- id:[0-9a-f]\{4\} -->' "$f" || true)
  fi
done
fi

runtime_ms=$(( $(date +%s%3N) - start_ms ))
printf '%s\t%s\tmode=%s\tnotes=%d\tid_lines=%d\tcandidates=%d\truntime_ms=%d\n' \
  "$(date -Iseconds)" "$(basename "$ROOT")" "$mode" "$notes" "$id_lines" "$candidates" "$runtime_ms" \
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
