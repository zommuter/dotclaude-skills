#!/usr/bin/env bash
# relay-log-archive.sh — rotate OLDER session entries out of RELAY_LOG.md into
#   RELAY_LOG.archive.md, so the live file stays small.
#
# Usage: relay-log-archive.sh [<repo-root>]   (default: git rev-parse --show-toplevel)
#
# WHY THIS EXISTS: RELAY_LOG.md is one of the ledgers a `review` unit's dispatch
# prompt is sized on (`countedLedgersFor`, relay-loop.js, id:7c5f) and has no
# rotator anywhere in relay/scripts/ — it only grows. Measured 2026-08-27: loderite's
# copy is 1.25 MB / 15,188 lines and drives the majority of that repo's prompt-size
# estimate against the review budget.
#
# ── merge=union HAZARD (READ BEFORE CHANGING THE POLICY BELOW) ─────────────────
# RELAY_LOG.md is declared `merge=union` in .gitattributes because concurrent
# worktrees/branches routinely APPEND new entries at the *same* position (end of
# file) — union merge concatenates both sides' additions instead of conflicting.
# Union merge does NOT protect a DELETION: if this script removes lines from one
# branch while another branch's concurrent diff touches the SAME lines (e.g. an
# in-flight `git merge` that hasn't landed a pending append yet, or a manual
# conflict resolution mid-flight), a 3-way merge can drop content that a plain
# rotation never anticipated, and union merge offers no dedup-based recovery for
# a line one side deleted and the other kept. The failure mode is a *silently
# thinner* RELAY_LOG.md, which is hard to notice because thinner is presented as
# the goal.
#
# The policy below is deliberately conservative so this can run unattended without
# depending on merge timing:
#   1. AGE GATE — only entries whose header date is >= $ARCHIVE_AFTER_DAYS days old
#      (default 30, matching archive-done.sh/roadmap-archive.sh's convention) are
#      candidates. A brand-new append from a run that's still landing across
#      worktrees is, by construction, far too young to qualify — there is no
#      window in which this script and a concurrent append can race over the
#      SAME entry.
#   2. TAIL FLOOR — the most recent $KEEP_TAIL_ENTRIES entries (default 20) are
#      NEVER rotated regardless of age, so the live file always keeps a runway of
#      recent history for a reviewer/executor to scan without opening the archive,
#      and so a mis-set clock on one entry can't strip the whole live tail.
#   3. SIZE FLOOR — if RELAY_LOG.md is under $MIN_LINES lines (default 500), skip
#      entirely: a small log gains nothing from rotation and the risk is not worth
#      it. (Mirrors archive-done.sh's 50-line gate, scaled up: RELAY_LOG entries
#      run much longer per-entry than TODO lines.)
#   4. UNPARSEABLE HEADER — an entry whose header doesn't start with `## YYYY-MM-DD`
#      is left in place untouched (conservative, matches archive-done.sh's
#      "no parseable date -> left in place" rule). Two such headers exist in this
#      repo's own RELAY_LOG.md today (embedded date in prose, not at header start).
#   5. The file's own H1 title line (with the `merge=union` doctrine comment) is
#      never touched or moved.
# Idempotent: entries already rotated out of RELAY_LOG.md are gone, so a second
# run with the same thresholds finds nothing further to move.
#
# Flock-guarded like the sibling archivers (archive-closed.sh, roadmap-archive.sh).
# --dry-run prints what WOULD move and mutates nothing.

set -euo pipefail

DRY_RUN=0
ROOT=""
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        *) ROOT="$arg" ;;
    esac
done

if [[ -z "$ROOT" ]]; then
    ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
        echo "relay-log-archive: no <repo-root> given and not in a git repo" >&2; exit 1; }
fi
[[ -d "$ROOT" ]] || { echo "relay-log-archive: $ROOT is not a directory" >&2; exit 1; }

LOG_FILE="$ROOT/RELAY_LOG.md"
ARCHIVE_FILE="$ROOT/RELAY_LOG.archive.md"
LOCK_FILE="$ROOT/.relay-log-archive.lock"

ARCHIVE_AFTER_DAYS="${ARCHIVE_AFTER_DAYS:-30}"
KEEP_TAIL_ENTRIES="${KEEP_TAIL_ENTRIES:-20}"
MIN_LINES="${MIN_LINES:-500}"

if [[ ! -f "$LOG_FILE" ]]; then
    echo "relay-log-archive: $LOG_FILE not found — skipping." >&2
    exit 0
fi

line_count=$(wc -l < "$LOG_FILE")
if (( line_count < MIN_LINES )); then
    echo "relay-log-archive: $LOG_FILE has $line_count lines (<$MIN_LINES) — skipping." >&2
    exit 0
fi

# flock-guard the entire operation (fd 9) — mirrors roadmap-archive.sh.
exec 9>"$LOCK_FILE"
if ! flock -n 9 2>/dev/null; then
    echo "relay-log-archive: another instance is running (lock held by $LOCK_FILE) — skipping." >&2
    exit 0
fi
trap 'rm -- "$LOCK_FILE"' EXIT   # created by `exec 9>` above ⇒ exists; no -f needed

cutoff=$(date -d "${ARCHIVE_AFTER_DAYS} days ago" '+%Y-%m-%d')

python3 - "$LOG_FILE" "$ARCHIVE_FILE" "$cutoff" "$KEEP_TAIL_ENTRIES" "$DRY_RUN" <<'PYEOF'
import sys, re
from pathlib import Path
from datetime import date

log_path     = Path(sys.argv[1])
archive_path = Path(sys.argv[2])
cutoff       = date.fromisoformat(sys.argv[3])
keep_tail    = int(sys.argv[4])
dry_run      = sys.argv[5] == '1'

ENTRY_RE = re.compile(r'^## ')
DATE_RE  = re.compile(r'^## (\d{4}-\d{2}-\d{2})\b')

lines = log_path.read_text().splitlines(keepends=True)

# Preamble: everything before the first `## ` entry header (the H1 title line
# plus any blank/lead-in lines). Always kept, never touched.
preamble = []
i = 0
n = len(lines)
while i < n and not ENTRY_RE.match(lines[i]):
    preamble.append(lines[i])
    i += 1

# Parse entries: each spans from one `## ` header to the line before the next
# `## ` header (or EOF). Record (header_date_or_None, block_lines).
entries = []
while i < n:
    header = lines[i]
    block = [header]
    j = i + 1
    while j < n and not ENTRY_RE.match(lines[j]):
        block.append(lines[j])
        j += 1
    m = DATE_RE.match(header)
    entry_date = date.fromisoformat(m.group(1)) if m else None
    entries.append((entry_date, block))
    i = j

total = len(entries)
# Indices eligible for the tail floor: the LAST `keep_tail` entries, in document
# order, are protected regardless of age.
protected_tail_start = max(0, total - keep_tail)

kept = []
archived = []
for idx, (entry_date, block) in enumerate(entries):
    eligible_by_age = entry_date is not None and entry_date <= cutoff
    eligible_by_tail = idx < protected_tail_start
    if eligible_by_age and eligible_by_tail:
        archived.append(block)
    else:
        kept.append(block)

if dry_run:
    moved = sum(len(b) for b in archived)
    print(f"relay-log-archive: would move {len(archived)} entr{'y' if len(archived)==1 else 'ies'} "
          f"({moved} lines) -> {archive_path.name}", file=sys.stderr)
    sys.exit(0)

if not archived:
    print("relay-log-archive: nothing to archive.", file=sys.stderr)
    sys.exit(0)

if archive_path.exists():
    existing = archive_path.read_text()
    if existing and not existing.endswith('\n'):
        existing += '\n'
else:
    existing = "# Relay log archive <!-- merge=union; append-only — never edit or reorder past entries -->\n"

for block in archived:
    existing += '\n'
    existing += ''.join(block)
archive_path.write_text(existing)

new_content = ''.join(preamble) + ''.join(l for block in kept for l in block)
# Ensure single trailing newline, no trailing blank-line pileup.
new_content = new_content.rstrip('\n') + '\n'
log_path.write_text(new_content)

print(f"relay-log-archive: archived {len(archived)} entr{'y' if len(archived)==1 else 'ies'} "
      f"-> {archive_path.name}", file=sys.stderr)
PYEOF
