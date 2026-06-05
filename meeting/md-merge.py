#!/usr/bin/env python3
"""
md-merge.py — flock'd key-based in-place merge for markdown files.

Prevents concurrent sessions from clobbering each other's edits by
re-reading the file under an exclusive flock before applying this
session's delta.

Usage:
    # Replace lines by <!-- id:XXXX --> token (for TODO.md)
    python3 md-merge.py update-ids --file <path>
    stdin: {"updates": [{"id": "XXXX", "line": "replacement line text"}]}

    # Replace ## section blocks by heading text (for user-profile.md)
    python3 md-merge.py update-sections --file <path>
    stdin: {"sections": [{"heading": "## Trait name", "content": "full replacement text incl heading"}]}

Both subcommands:
- Acquire an exclusive flock on <path>.lock before reading/writing.
- Re-read the file under lock (picks up concurrent writes since delta was prepared).
- Write back atomically via tmp+rename.
- IDs / headings not found are appended at end of file.

Contract: two sessions editing different items/sections both survive;
same-item serializes with last-under-lock winning without clobbering others.
"""
import argparse
import fcntl
import json
import re
import sys
from pathlib import Path


def _atomic_write(path: Path, text: str) -> None:
    tmp = path.with_suffix(path.suffix + '.tmp')
    tmp.write_text(text)
    tmp.replace(path)


def update_ids(file_path: Path, updates: list) -> None:
    """Replace lines containing <!-- id:XXXX --> with new text, under flock."""
    lock_path = file_path.with_suffix(file_path.suffix + '.lock')
    id_map = {u['id']: u['line'].rstrip('\n') for u in updates}

    with open(lock_path, 'w') as lock_fd:
        fcntl.flock(lock_fd, fcntl.LOCK_EX)

        lines = file_path.read_text().splitlines(keepends=True)
        found = set()
        result = []

        for line in lines:
            m = re.search(r'<!--\s*id:([0-9a-f]{4})\s*-->', line)
            if m and m.group(1) in id_map:
                item_id = m.group(1)
                found.add(item_id)
                result.append(id_map[item_id] + '\n')
            else:
                result.append(line)

        for item_id, new_line in id_map.items():
            if item_id not in found:
                result.append(new_line + '\n')

        _atomic_write(file_path, ''.join(result))


def update_sections(file_path: Path, sections: list) -> None:
    """Replace ## section blocks by heading, under flock."""
    lock_path = file_path.with_suffix(file_path.suffix + '.lock')
    # Normalise: heading key stripped, content ends with exactly one newline
    section_map = {
        s['heading'].strip(): s['content'].rstrip('\n') + '\n'
        for s in sections
    }

    with open(lock_path, 'w') as lock_fd:
        fcntl.flock(lock_fd, fcntl.LOCK_EX)

        lines = file_path.read_text().splitlines(keepends=True)
        found = set()
        result = []
        i = 0

        while i < len(lines):
            line = lines[i]
            m = re.match(r'^(#{2,})\s+(.+)', line.rstrip('\n'))
            if m:
                heading = m.group(1) + ' ' + m.group(2).strip()
                # Collect body up to next ## heading or EOF (j points at next heading)
                j = i + 1
                while j < len(lines) and not re.match(r'^#{2,}\s+', lines[j]):
                    j += 1
                if heading in section_map:
                    found.add(heading)
                    new_content = section_map[heading]
                    result.append(new_content)
                    # Preserve blank line before next heading if the replacement doesn't end with one
                    if j < len(lines) and not new_content.endswith('\n\n'):
                        result.append('\n')
                else:
                    result.extend(lines[i:j])
                i = j
            else:
                result.append(line)
                i += 1

        for heading, new_content in section_map.items():
            if heading not in found:
                if result and not result[-1].endswith('\n'):
                    result.append('\n')
                result.append('\n' + new_content)

        _atomic_write(file_path, ''.join(result))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='cmd')

    p_ids = sub.add_parser('update-ids', help='Replace lines by <!-- id:XXXX --> (for TODO.md)')
    p_ids.add_argument('--file', required=True, help='Path to the markdown file')

    p_sec = sub.add_parser('update-sections', help='Replace ## section blocks by heading (for user-profile.md)')
    p_sec.add_argument('--file', required=True, help='Path to the markdown file')

    args = parser.parse_args()

    try:
        delta = json.load(sys.stdin)
    except json.JSONDecodeError as e:
        print(f'md-merge: invalid JSON on stdin: {e}', file=sys.stderr)
        sys.exit(1)

    if args.cmd == 'update-ids':
        update_ids(Path(args.file), delta.get('updates', []))
    elif args.cmd == 'update-sections':
        update_sections(Path(args.file), delta.get('sections', []))
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == '__main__':
    main()
