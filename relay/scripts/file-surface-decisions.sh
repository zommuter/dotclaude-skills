#!/usr/bin/env bash
# relay/scripts/file-surface-decisions.sh — mechanical surface→decision-queue filer (id:5eb3)
#
# Relocates the case-g surface-item filing OUT of the Opus handoff apex and into a
# forced, logged, tested mechanical step that relay-loop.js calls when the classifier
# emits verdict=human (promote==0 ∧ surface>0).
#
# Behaviour:
#   1. Runs unpromoted-scan.sh on <repo-root> to get the current surface set.
#   2. For each surface-disposition item, calls decision-queue.sh add with --source-id.
#      Items with an existing OPEN decision-queue record are SKIPPED (idempotent).
#   3. LOGS the filing count to stdout (LOUD — never a silent no-op).
#   4. Exits 0 always (surface filing is best-effort; individual item failure is
#      logged to stderr but does not abort the batch).
#
# Anti-gaming invariant (id:47f1): decision-queue.sh --source-id + unpromoted-scan's
# exclusion of filed tokens means a filed item drops out of the scan on the next run,
# so the human verdict stops re-firing once all surface items are filed.
#
# Usage:
#   file-surface-decisions.sh <repo-root>
#
# Conventions: set -euo pipefail; short stdout; individual filing errors to stderr.

set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNPROMOTED="$SCRIPT_DIR/unpromoted-scan.sh"
DQUEUE="$SCRIPT_DIR/decision-queue.sh"

[[ -x "$UNPROMOTED" ]] || die "unpromoted-scan.sh not found or not executable: $UNPROMOTED"
[[ -x "$DQUEUE"     ]] || die "decision-queue.sh not found or not executable: $DQUEUE"

REPO_ROOT="${1:-}"
[[ -n "$REPO_ROOT" ]] || die "usage: file-surface-decisions.sh <repo-root>"
[[ -d "$REPO_ROOT" ]] || die "repo-root does not exist: $REPO_ROOT"

REPO_NAME="$(basename "$REPO_ROOT")"

# Run unpromoted-scan; capture TSV output (repo\tid\tdisposition\ttitle)
# Note: unpromoted-scan exits 0 even with findings; only MISUSE exits nonzero.
SCAN_OUT="$("$UNPROMOTED" "$REPO_ROOT" 2>&1)" || {
  echo "ERROR: unpromoted-scan.sh failed for $REPO_ROOT — aborting surface filing" >&2
  exit 1
}

# Count surface-disposition items
filed=0
skipped=0
errors=0

while IFS=$'\t' read -r _repo token disposition title; do
  [[ "$disposition" == "surface" ]] || continue
  # Skip items with no token (untracked) — they have no id to key on
  [[ "$token" != "----" ]] || continue

  # Idempotency: check if an OPEN record already exists for this source-id.
  # decision-queue.sh list returns matching open records (one JSON per line).
  existing="$("$DQUEUE" list --repo "$REPO_NAME" 2>/dev/null | python3 -c "
import sys, json
token = $(printf '%s' "$token" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read().strip()))')
for line in sys.stdin:
    try:
        r = json.loads(line.strip())
    except Exception:
        continue
    if r.get('source_id') == token and r.get('status','open') == 'open':
        print('found')
        break
" 2>/dev/null || true)"

  if [[ "$existing" == "found" ]]; then
    skipped=$((skipped + 1))
    continue
  fi

  # File a new decision-queue record for this surface item
  if "$DQUEUE" add \
      --repo "$REPO_NAME" \
      --kind lane-triage \
      --question "Assign a lane to TODO id:${token}: ${title}" \
      --source-id "$token" \
      >/dev/null 2>&1; then
    filed=$((filed + 1))
  else
    echo "WARNING: failed to file decision-queue record for id:${token} (${title})" >&2
    errors=$((errors + 1))
  fi

done <<< "$SCAN_OUT"

# LOUD output: never a silent no-op (anti-gaming invariant, id:5eb3)
total_surface=$(echo "$SCAN_OUT" | awk -F'\t' '$3=="surface" && $2!="----"' | wc -l)
echo "file-surface-decisions: repo=${REPO_NAME} surface_items=${total_surface} filed=${filed} skipped_already_open=${skipped} errors=${errors}"

if [[ $errors -gt 0 ]]; then
  echo "WARNING: ${errors} item(s) failed to file — check stderr for details" >&2
fi
