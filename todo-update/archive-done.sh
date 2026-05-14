#!/usr/bin/env bash
# archive-done.sh — move aged [x] entries from TODO.md to TODO.archive.md
# Usage: archive-done.sh [path/to/TODO.md]   (default: ./TODO.md)
# Skips if the file has fewer than 50 lines.
# Only archives lines ending with "on YYYY-MM-DD[.]" that are ≥30 days old.
# Lines without a parseable date are left in place (safe-default).

set -euo pipefail

TODO_FILE="${1:-TODO.md}"
ARCHIVE_FILE="$(dirname "$TODO_FILE")/TODO.archive.md"

if [[ ! -f "$TODO_FILE" ]]; then
    echo "archive-done: $TODO_FILE not found — skipping." >&2
    exit 0
fi

line_count=$(wc -l < "$TODO_FILE")
if (( line_count < 50 )); then
    echo "archive-done: $TODO_FILE has $line_count lines (<50) — skipping." >&2
    exit 0
fi

cutoff=$(date -d '30 days ago' '+%Y-%m-%d')

python3 - "$TODO_FILE" "$ARCHIVE_FILE" "$cutoff" <<'PYEOF'
import sys, re
from pathlib import Path
from datetime import date

todo_path   = Path(sys.argv[1])
archive_path = Path(sys.argv[2])
cutoff      = date.fromisoformat(sys.argv[3])

lines   = todo_path.read_text().splitlines(keepends=True)
keep    = []
to_arch = {}  # ym -> [line_without_newline]

date_re = re.compile(r' on (\d{4}-\d{2}-\d{2})\.?\s*$')

for line in lines:
    if re.match(r'^\s*- \[x\]', line):
        m = date_re.search(line)
        if m:
            try:
                d = date.fromisoformat(m.group(1))
            except ValueError:
                keep.append(line)
                continue
            if d <= cutoff:
                ym = d.strftime('%Y-%m')
                to_arch.setdefault(ym, []).append(line.rstrip('\n'))
                continue
    keep.append(line)

if not to_arch:
    print("archive-done: nothing old enough to archive.", file=sys.stderr)
    sys.exit(0)

todo_path.write_text(''.join(keep))

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
PYEOF
