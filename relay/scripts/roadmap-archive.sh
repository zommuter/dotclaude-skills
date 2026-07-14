#!/usr/bin/env bash
# roadmap-archive.sh — move done [x] items from ROADMAP.md into ROADMAP.archive.md.
# Usage: roadmap-archive.sh [repo-root]  (default: git rev-parse --show-toplevel)
#
# Conservative gate (mirrors archive-done.sh):
#   - Items done in a PRIOR commit (i.e., [x] in HEAD's ROADMAP.md), OR
#   - Items whose first line carries a trailing "done YYYY-MM-DD[.]" that is ≥30 days old.
# Items ticked only in the working tree (same-run) are NEVER archived.
#
# Moves each top-level "- [x] …" line PLUS its WHOLE block — every line up to the
# next top-level bullet ("- [") or any heading (#..######) — as one unit, preserving
# the <!-- id:XXXX --> token and original text verbatim. This also captures column-0
# prose paragraphs and "> " blockquotes in the item's body (not just indented lines).
#
# NEVER touches open "- [ ]" items or the file preamble. A grouping heading (##/###/…)
# that this run EMPTIES of all top-level items is MOVED into the archive with it,
# UNLESS it is protected: the H1 title, or a heading whose text is exactly one of
# Items/Current/Done/Backlog (case-insensitive). A heading already empty on arrival
# is left untouched. Idempotent; flock-guarded; nothing-to-archive is a clean no-op.

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
import sys, re, bisect
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
# Regex for a ## or deeper section heading (matches H1 too — H1 is protected separately).
heading_re  = re.compile(r'^#{1,6}\s')

PROTECTED_TEXTS = {'items', 'current', 'done', 'backlog'}

def heading_info(line):
    """Return (level, text) for a heading line, text stripped of a trailing
    HTML comment and surrounding whitespace. None if not a heading."""
    m = re.match(r'^(#{1,6})\s+(.*)', line)
    if not m:
        return None
    level = len(m.group(1))
    text = m.group(2).rstrip('\n')
    text = re.sub(r'<!--.*?-->\s*$', '', text).strip()
    return level, text

def is_protected(line):
    info = heading_info(line)
    if info is None:
        return True  # be conservative — shouldn't happen for a heading_re match
    level, text = info
    if level == 1:
        return True
    return text.lower() in PROTECTED_TEXTS

def is_boundary(line):
    """A block ends at the next top-level bullet OR any heading."""
    return top_bullet_re.match(line) is not None or heading_re.match(line) is not None

# Heading line indices in the ORIGINAL file, in document order.
heading_indices = [idx for idx, l in enumerate(lines) if heading_re.match(l)]

# ── Pass 1: build an ordered list of entries, tagging each original line as
#    kept-in-place or an archived item block. Entries preserve document order. ──
# entry = ('keep', line, orig_idx) | ('arch', [block_lines], owning_heading_idx)
entries = []
archived_count_by_heading = {}   # owning heading orig idx (-1 = none) -> #items archived
n = len(lines)
i = 0
while i < n:
    line = lines[i]
    if top_done_re.match(line):
        # Gather the block: header + everything up to the next boundary.
        unit = [line]
        j = i + 1
        while j < n and not is_boundary(lines[j]):
            unit.append(lines[j])
            j += 1
        # Trim trailing blank lines from the block (they belong to the gap, not the item).
        while len(unit) > 1 and unit[-1].strip() == '':
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
            slot = bisect.bisect_right(heading_indices, i) - 1
            owning = heading_indices[slot] if slot >= 0 else -1
            entries.append(('arch', unit, owning))
            archived_count_by_heading[owning] = archived_count_by_heading.get(owning, 0) + 1
            i = j
        else:
            # Same-run tick — leave it in place.
            entries.append(('keep', line, i))
            i += 1
    else:
        entries.append(('keep', line, i))
        i += 1

if not archived_count_by_heading:
    print("roadmap-archive: nothing to archive.", file=sys.stderr)
    sys.exit(0)

# ── Pass 2: decide which non-protected headings this run EMPTIED (so they move
#    into the archive with their block). A heading moves iff: non-protected AND
#    ≥1 item under it was archived this run AND no top-level bullet survives
#    under it (in the kept stream). ──
surviving_bullet = {}   # heading orig idx -> True if a kept top-level bullet remains
cur_h = -1
for e in entries:
    if e[0] == 'keep':
        line = e[1]
        if heading_re.match(line):
            cur_h = e[2]
        elif top_bullet_re.match(line):
            surviving_bullet[cur_h] = True

moved = set()
for H in heading_indices:
    if is_protected(lines[H]):
        continue
    if archived_count_by_heading.get(H, 0) == 0:
        continue  # nothing archived under it this run (incl. already-empty)
    if surviving_bullet.get(H):
        continue  # items remain under this heading — do not move it
    moved.add(H)

# ── Pass 3: stream keep-lines and archive-lines in ORIGINAL document order.
#    A moved heading (and any residual section content beneath it) is routed to
#    the archive; its archived item blocks follow it there, preserving grouping
#    context (heading line then its items, adjacent). ──
keep_out = []
arch_out = []                 # list of lines
last_appended_heading = False  # was the previous arch-append a moved-heading line?
cur_moved = False              # are we currently under a moved heading?
for e in entries:
    if e[0] == 'keep':
        line = e[1]
        if heading_re.match(line):
            if e[2] in moved:
                arch_out.append('\n')     # blank separator before the group
                arch_out.append(line)
                last_appended_heading = True
                cur_moved = True
            else:
                keep_out.append(line)
                cur_moved = False
        else:
            if cur_moved:
                # residual section content under a moved heading → archive it,
                # but drop pure-blank residual so the heading stays adjacent to
                # its item block.
                if line.strip() != '':
                    arch_out.append(line)
            else:
                keep_out.append(line)
    else:  # ('arch', block, owning)
        block = e[1]
        if last_appended_heading:
            # First item directly under a just-moved heading — no separator, so
            # the heading and its item are adjacent in the archive.
            arch_out.extend(block)
        else:
            arch_out.append('\n')
            arch_out.extend(block)
        last_appended_heading = False

# Append archived content to ROADMAP.archive.md (create if absent).
if not archive_path.exists():
    archive_path.write_text('# ROADMAP Archive\n')

with archive_path.open('a') as af:
    for bl in arch_out:
        af.write(bl if bl.endswith('\n') else bl + '\n')

# Write the surviving lines back to ROADMAP.md.
# Preserve the original content exactly (no blank-line collapsing — ROADMAP
# has structural gaps between items that must be preserved).
roadmap_path.write_text(''.join(keep_out))

archived_count = sum(archived_count_by_heading.values())
noun = 'item' if archived_count == 1 else 'items'
hn = len(moved)
hnoun = 'heading' if hn == 1 else 'headings'
extra = f", moved {hn} emptied {hnoun}" if hn else ""
print(f"roadmap-archive: archived {archived_count} {noun}{extra} → {archive_path}", file=sys.stderr)
PYEOF
