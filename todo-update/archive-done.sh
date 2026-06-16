#!/usr/bin/env bash
# archive-done.sh — move [x] entries from TODO.md to TODO.archive.md,
#   and prune empty (zero-task-line) non-protected sections.
# Usage: archive-done.sh [path/to/TODO.md]   (default: ./TODO.md)
# Pruning runs unconditionally.
# Archiving runs only if the file has ≥50 lines.
# Archives [x] entries that were already done in the prior commit (count-based),
# or entries ending with "on YYYY-MM-DD[.]" that are ≥30 days old (age-based).
# Entries without a parseable date and not in the prior commit are left in place.

set -euo pipefail

TODO_FILE="${1:-TODO.md}"
ARCHIVE_FILE="$(dirname "$TODO_FILE")/TODO.archive.md"

if [[ ! -f "$TODO_FILE" ]]; then
    echo "archive-done: $TODO_FILE not found — skipping." >&2
    exit 0
fi

line_count=$(wc -l < "$TODO_FILE")
do_archive=0
if (( line_count >= 50 )); then
    do_archive=1
else
    echo "archive-done: $TODO_FILE has $line_count lines (<50) — skipping archive, will still prune." >&2
fi

cutoff=$(date -d '30 days ago' '+%Y-%m-%d')
today_ym=$(date '+%Y-%m')

PRIOR_DONE_FILE=$(mktemp)
trap 'rm -f "$PRIOR_DONE_FILE"' EXIT

if [[ $do_archive -eq 1 ]]; then
    if REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null); then
        TODO_ABS=$(realpath "$TODO_FILE")
        TODO_REL=$(realpath --relative-to="$REPO_ROOT" "$TODO_ABS")
        git show HEAD:"$TODO_REL" 2>/dev/null | grep -E '^\s*- \[x\]' > "$PRIOR_DONE_FILE" || true
    fi
fi

python3 - "$TODO_FILE" "$ARCHIVE_FILE" "$cutoff" "$today_ym" "$PRIOR_DONE_FILE" "$do_archive" <<'PYEOF'
import sys, re
from pathlib import Path
from datetime import date

todo_path    = Path(sys.argv[1])
archive_path = Path(sys.argv[2])
cutoff       = date.fromisoformat(sys.argv[3])
today_ym     = sys.argv[4]
prior_file   = Path(sys.argv[5])
do_archive   = sys.argv[6] == '1'

prior_done = set()
if do_archive and prior_file.exists():
    for ln in prior_file.read_text().splitlines():
        prior_done.add(ln.strip())

lines   = todo_path.read_text().splitlines(keepends=True)
keep    = []
to_arch = {}  # ym -> [line_without_newline]

date_re   = re.compile(r' on (\d{4}-\d{2}-\d{2})\.?\s*$')
bullet_re = re.compile(r'^(\s*)- \[[ x]\]')

def bullet_indent(line):
    """Indent width of a `- [ ]`/`- [x]` bullet marker, or None if not a bullet."""
    m = bullet_re.match(line)
    return len(m.group(1)) if m else None

def is_continuation(line, base_indent):
    """A line belongs to the bullet at `base_indent` if it is more-indented than
    the marker and is not itself a new bullet at the same-or-lesser indent.
    Blank lines do NOT terminate the unit (they may sit between wrapped lines /
    sub-bullets); a following non-continuation line will end it."""
    if line.strip() == '':
        return True
    bi = bullet_indent(line)
    if bi is not None:
        # A nested bullet (more-indented marker) is part of this unit;
        # a sibling/outer bullet is not.
        return bi > base_indent
    # Non-bullet text: continuation iff indented past the marker.
    return (len(line) - len(line.lstrip())) > base_indent

i = 0
n = len(lines)
while i < n:
    line = lines[i]
    archived = False
    if do_archive and re.match(r'^\s*- \[x\]', line):
        base = bullet_indent(line)
        # Gather any indented continuation lines (sub-bullets / wrapped prose)
        # so the bullet moves as one unit.
        unit = [line]
        j = i + 1
        while j < n and is_continuation(lines[j], base):
            unit.append(lines[j])
            j += 1
        # Trailing blank lines belong to the document gap, not the bullet.
        while len(unit) > 1 and unit[-1].strip() == '':
            j -= 1
            unit.pop()

        ym = None
        if line.rstrip('\n').strip() in prior_done:
            ym = today_ym
        else:
            m = date_re.search(line)
            if m:
                try:
                    d = date.fromisoformat(m.group(1))
                    if d <= cutoff:
                        ym = d.strftime('%Y-%m')
                except ValueError:
                    ym = None

        if ym is not None:
            for u in unit:
                to_arch.setdefault(ym, []).append(u.rstrip('\n'))
            i = j
            archived = True

    if not archived:
        keep.append(line)
        i += 1

if to_arch:
    if not archive_path.exists():
        archive_path.write_text('# TODO Archive\n')
    existing = archive_path.read_text()
    added = 0
    for ym in sorted(to_arch):
        header = f'## {ym}'
        if header not in existing:
            existing += f'\n{header}\n'
        for entry in to_arch[ym]:
            existing += entry + '\n'
            added += 1
    archive_path.write_text(existing)
    n = 'entry' if added == 1 else 'entries'
    print(f"archive-done: archived {added} {n} → {archive_path}", file=sys.stderr)

# Prune empty non-protected sections (## or deeper; H1/preamble untouched).
# Protected heading labels (case-sensitive, after stripping leading #s + whitespace):
PROTECTED = {"Done", "Current"}
HEADING_RE = re.compile(r'^(#{1,6})\s+(.+)')
TASK_RE = re.compile(r'^\s*- \[[ x]\]')

# Split into preamble + section segments.
# 'pre' = content before the first ## heading; 'section' = a ##+ heading + its body.
segments = []
cur_type = 'pre'
cur_lines = []

for line in keep:
    m = HEADING_RE.match(line.rstrip('\n'))
    if m and len(m.group(1)) >= 2:
        segments.append((cur_type, cur_lines))
        cur_type = 'section'
        cur_lines = [line]
    else:
        cur_lines.append(line)
segments.append((cur_type, cur_lines))

pruned_any = False
result_lines = []
for seg_type, seg_lines in segments:
    if seg_type == 'section':
        heading_line = seg_lines[0].rstrip('\n')
        hm = HEADING_RE.match(heading_line)
        label = hm.group(2).strip() if hm else ''
        body = seg_lines[1:]
        has_content = any(l.strip() for l in body)
        if not has_content and label not in PROTECTED:
            pruned_any = True
            print(f"archive-done: pruned empty section '{label}'", file=sys.stderr)
            continue
    result_lines.extend(seg_lines)

if not pruned_any and not to_arch:
    print("archive-done: nothing to archive or prune.", file=sys.stderr)
    sys.exit(0)

# Collapse multiple consecutive blank lines into one, ensure single trailing newline.
collapsed = []
prev_blank = False
for line in result_lines:
    is_blank = line.strip() == ''
    if is_blank and prev_blank:
        continue
    collapsed.append(line)
    prev_blank = is_blank

new_text = ''.join(collapsed).rstrip('\n') + '\n'
todo_path.write_text(new_text)
PYEOF
