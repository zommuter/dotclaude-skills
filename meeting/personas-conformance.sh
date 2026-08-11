#!/usr/bin/env bash
# personas-conformance.sh — fail loudly when meeting/personas.md carries a duplicate
# persona name. id:069b: .gitattributes sets `personas.md merge=union`, which can never
# reconcile a re-registration on its own — this check is the backstop that keeps the
# registry from silently re-accreting duplicates a merge cannot dedup.
#
# Usage: personas-conformance.sh <personas.md>
# Exit 0: clean, no name appears twice.
# Exit 1: at least one name is duplicated — names printed on stderr, one per line.
set -euo pipefail

FILE="${1:?usage: personas-conformance.sh <personas.md>}"
[[ -f "$FILE" ]] || { echo "Error: not found: $FILE" >&2; exit 1; }

dups="$(grep -oE '\*\*[A-Za-z]+\*\*' "$FILE" | tr -d '*' | sort | uniq -d)"

if [[ -n "$dups" ]]; then
  echo "personas-conformance: duplicate persona name(s) found in $FILE (id:069b — merge=union cannot reconcile a re-registration, only the writer path can):" >&2
  echo "$dups" >&2
  exit 1
fi

exit 0
