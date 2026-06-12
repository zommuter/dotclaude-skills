#!/usr/bin/env bash
set -euo pipefail

SUMMARY=0
while [[ $# -gt 0 && "$1" == --* ]]; do
  case "$1" in
    --summary) SUMMARY=1; shift ;;
    *) echo "unknown flag: $1" >&2; exit 1 ;;
  esac
done

ROOT="${1:-$(git rev-parse --show-toplevel)}"
GATE="${CTX_BUDGET_GATE:-2000}"

total=0
over=0

while IFS= read -r path; do
  relpath="${path#"$ROOT"/}"
  bytes=$(wc -c < "$path")
  est=$(( bytes / 4 ))
  if (( est > GATE )); then
    status="WARN"
    over=$(( over + 1 ))
  else
    status="OK"
  fi
  total=$(( total + 1 ))
  if [[ $SUMMARY -eq 0 || "$status" == "WARN" ]]; then
    printf '%s\t%d\t%d\t%s\n' "$relpath" "$est" "$GATE" "$status"
  fi
done < <(find "$ROOT" -name "SKILL.md" | sort)

if [[ $SUMMARY -eq 1 ]]; then
  echo "total: $total files, $over over gate"
fi
