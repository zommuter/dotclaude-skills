#!/usr/bin/env bash
# roadmap-archive.sh — move done [x] items from ROADMAP.md into ROADMAP.archive.md.
# Usage: roadmap-archive.sh [repo-root]  (default: git rev-parse --show-toplevel)
#
# Conservative gate (mirrors archive-done.sh):
#   - Items done in a PRIOR commit (i.e., [x] in HEAD's ROADMAP.md), OR
#   - Items whose first line carries a trailing "done YYYY-MM-DD[.]" that is ≥30 days old.
# Items ticked only in the working tree (same-run) are NEVER archived.
#
# Moves each top-level "- [x] …" line PLUS all its indented continuation lines (the
# block up to the next top-level bullet or ## heading) as one unit, preserving the
# <!-- id:XXXX --> token and original text verbatim.
#
# NEVER touches open "- [ ]" items, "## " section headers, or the file preamble.
# Headers that become empty are LEFT (no section pruning — ROADMAP headers are structural).
# Idempotent; flock-guarded; re-running with nothing to archive is a clean no-op.

set -euo pipefail

REPO_ROOT="${1:-$(git rev-parse --show-toplevel)}"
ROADMAP_FILE="$REPO_ROOT/ROADMAP.md"
ARCHIVE_FILE="$REPO_ROOT/ROADMAP.archive.md"
LOCK_FILE="$REPO_ROOT/.roadmap-archive.lock"
LOG_DIR="$HOME/.claude/logs"
LOG_FILE="$LOG_DIR/roadmap-archive.log"

mkdir -p "$LOG_DIR"

if [[ ! -f "$ROADMAP_FILE" ]]; then
    echo "roadmap-archive: $ROADMAP_FILE not found — skipping." >&2
    exit 0
fi

# flock-guard the entire operation (fd 9)
exec 9>"$LOCK_FILE"
if ! flock -n 9 2>/dev/null; then
    echo "roadmap-archive: another instance is running (lock held by $LOCK_FILE) — skipping." >&2
    exit 0
fi
trap 'rm -f "$LOCK_FILE"' EXIT

cutoff=$(date -d '30 days ago' '+%Y-%m-%d')

# Get the set of lines that were already [x] in the PRIOR commit (HEAD).
PRIOR_DONE_FILE=$(mktemp)
trap 'rm -f "$PRIOR_DONE_FILE"; rm -f "$LOCK_FILE"' EXIT

REPO_ABS=$(realpath "$REPO_ROOT")
ROADMAP_ABS=$(realpath "$ROADMAP_FILE")
ROADMAP_REL=$(realpath --relative-to="$REPO_ABS" "$ROADMAP_ABS")

if git -C "$REPO_ABS" show "HEAD:$ROADMAP_REL" 2>/dev/null \
   | grep -E '^- \[x\]' > "$PRIOR_DONE_FILE"; then
    : # populated
else
    : # empty — no prior-commit done items (also fine)
fi

python3 - "$ROADMAP_FILE" "$ARCHIVE_FILE" "$cutoff" "$PRIOR_DONE_FILE" <<'PYEOF'
import sys, re
from pathlib import Path
from datetime import date

roadmap_path = Path(sys.argv[1])
archive_path = Path(sys.argv[2])
cutoff       = date.fromisoformat(sys.argv[3])
prior_file   = Path(sys.argv[4])

# Load the set of lines that were [x] in the prior commit (stripped, for lookup).
prior_done = set()
if prior_file.exists():
    for ln in prior_file.read_text().splitlines():
        prior_done.add(ln.strip())

lines = roadmap_path.read_text().splitlines(keepends=True)

# Regex to detect a top-level bullet (no leading whitespace) that is done.
top_done_re = re.compile(r'^- \[x\]')
# Regex for "done YYYY-MM-DD[.]" anywhere on the first line of a done item.
# Does NOT require end-of-line — items may carry trailing <!-- id:XXXX --> comments.
date_re     = re.compile(r'\bdone (\d{4}-\d{2}-\d{2})\.?', re.IGNORECASE)
# Regex for any top-level bullet (open or done) — no leading whitespace, starts "- [".
top_bullet_re = re.compile(r'^- \[')
# Regex for a ## or deeper section heading.
heading_re  = re.compile(r'^#{1,6}\s')

def is_continuation(line):
    """A line is a continuation of the preceding top-level bullet if:
    - it is blank, OR
    - it is indented (leading whitespace), AND not a new top-level bullet/heading.
    """
    if line.strip() == '':
        return True
    if top_bullet_re.match(line) or heading_re.match(line):
        return False
    # Any indented line is a continuation.
    return line[0] == ' ' or line[0] == '\t'

keep    = []
to_arch = []  # list of [line, ...] blocks

i = 0
n = len(lines)
while i < n:
    line = lines[i]
    if top_done_re.match(line):
        # Gather the block: header + all continuation lines.
        unit = [line]
        j = i + 1
        while j < n and is_continuation(lines[j]):
            unit.append(lines[j])
            j += 1
        # Trim trailing blank lines from the block (they belong to the gap, not the item).
        while len(unit) > 1 and unit[-1].strip() == '':
            j -= 1
            unit.pop()

        # Apply conservative gate:
        # 1. Was the header line already [x] in the prior commit?
        header_stripped = line.strip()
        in_prior = header_stripped in prior_done

        # 2. Does the header carry a "done YYYY-MM-DD" ≥30 days old?
        aged_ok = False
        dm = date_re.search(line)
        if dm:
            try:
                d = date.fromisoformat(dm.group(1))
                if d <= cutoff:
                    aged_ok = True
            except ValueError:
                pass

        if in_prior or aged_ok:
            to_arch.append(unit)
            i = j
        else:
            # Same-run tick — leave it in place.
            keep.append(line)
            i += 1
    else:
        keep.append(line)
        i += 1

if not to_arch:
    print("roadmap-archive: nothing to archive.", file=sys.stderr)
    sys.exit(0)

# Append archived blocks to ROADMAP.archive.md (create if absent).
if not archive_path.exists():
    archive_path.write_text('# ROADMAP Archive\n')

with archive_path.open('a') as af:
    for block in to_arch:
        af.write('\n')
        for bl in block:
            af.write(bl if bl.endswith('\n') else bl + '\n')

# Write the surviving lines back to ROADMAP.md.
# Preserve the original content exactly (no blank-line collapsing — ROADMAP
# has structural gaps between items that must be preserved).
roadmap_path.write_text(''.join(keep))

archived_count = len(to_arch)
noun = 'item' if archived_count == 1 else 'items'
print(f"roadmap-archive: archived {archived_count} {noun} → {archive_path}", file=sys.stderr)
PYEOF
