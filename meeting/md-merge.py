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

    # Optionally commit the file atomically under the same flock (id:148b):
    python3 md-merge.py update-ids --file <path> --commit "<commit message>"

Both subcommands:
- Acquire an exclusive flock on <path>.lock before reading/writing.
- Re-read the file under lock (picks up concurrent writes since delta was prepared).
- Write back atomically via tmp+rename.
- IDs / headings not found are appended at end of file.
- With --commit MSG (id:148b): while STILL holding the flock, commit just this file
  (scoped `git add -- <file>` + `git commit -- <file>`, never `git add -A`, never
  stash/reset — mirrors relay/scripts/commit-ledger.sh id:2147). Closes the scoop
  window: no modified-but-uncommitted ledger is left in the main checkout. Opt-in,
  idempotent (clean no-op when unchanged), and non-fatal on any git error (the write
  already succeeded).

Contract: two sessions editing different items/sections both survive;
same-item serializes with last-under-lock winning without clobbering others.
"""
from __future__ import annotations

import argparse
import fcntl
import json
import re
import subprocess
import sys
from pathlib import Path


def _atomic_write(path: Path, text: str) -> None:
    tmp = path.with_suffix(path.suffix + '.tmp')
    tmp.write_text(text)
    tmp.replace(path)


def _commit_ledger(file_path: Path, msg: str) -> None:
    """Scoped, idempotent commit of JUST <file_path> in its repo's main checkout.

    Closes the scoop window (id:148b): without this the ledger is written but left
    modified-but-uncommitted, a window in which a relay integrator could scoop it (now
    also guarded by id:debf) or an interrupted run could strand dirty residue that trips
    the dirty-guard (id:aa93). Called WHILE the caller still holds the <file>.lock flock,
    so the write+commit pair is atomic w.r.t. other md-merge writers of the same file.

    Discipline mirrors relay/scripts/commit-ledger.sh (id:2147) — the load-bearing rules:
      - Stages ONLY this one file (`git add -- <file>`), NEVER `git add -A` (id:debf) —
        a concurrent edit to an UNRELATED file is left untouched.
      - NEVER `git stash` / `git checkout --` / `git reset` / `git clean` — it only ADDs
        and COMMITs the named file; foreign-dirty paths are never disturbed (id:aa93).
      - COMMIT-ONLY: never pushes (push is the caller's separate, later concern).
      - Clean no-op: if the named file has no staged change, makes NO commit (idempotent).
    Non-fatal: any git failure (not a repo, index lock, etc.) prints a warning to stderr
    and returns — the atomic write already succeeded, so the ledger edit is never lost.
    """
    file_path = file_path.resolve()

    def _git(*args: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            ['git', '-C', str(file_path.parent), *args],
            capture_output=True, text=True,
        )

    top = _git('rev-parse', '--show-toplevel')
    if top.returncode != 0:
        print(f'md-merge: --commit skipped — {file_path} is not in a git repo '
              '(write succeeded, left uncommitted)', file=sys.stderr)
        return
    repo = Path(top.stdout.strip())
    try:
        rel = str(file_path.relative_to(repo))
    except ValueError:
        rel = str(file_path)

    add = _git('add', '--', rel)
    if add.returncode != 0:
        print(f'md-merge: --commit skipped — git add failed for {rel}: '
              f'{add.stderr.strip()} (write succeeded, left uncommitted)', file=sys.stderr)
        return

    # Clean no-op if nothing staged for this file (idempotent).
    if _git('diff', '--cached', '--quiet', '--', rel).returncode == 0:
        return

    commit = _git('commit', '-m', msg, '--', rel)
    if commit.returncode != 0:
        print(f'md-merge: --commit failed for {rel}: {commit.stderr.strip()} '
              '(write succeeded, left uncommitted)', file=sys.stderr)


# id:14d0 — archive-class headings a brand-new (not-found) id must never land under.
# A NEW item is open work; appending it at EOF misfiles it under a trailing Done/
# Archive/Icebox section. Matched case-insensitively against `##`+ headings.
_ARCHIVE_HEADING_RE = re.compile(r'^#{2,}\s+(done|archive|icebox)\b', re.IGNORECASE)


def _first_archive_heading_index(result: list) -> int | None:
    """Index into `result` of the first archive-class heading line, or None."""
    for i, line in enumerate(result):
        if _ARCHIVE_HEADING_RE.match(line.rstrip('\n')):
            return i
    return None


def update_ids(file_path: Path, updates: list, commit_msg: str | None = None) -> None:
    """Replace lines containing <!-- id:XXXX --> with new text, under flock."""
    lock_path = file_path.with_suffix(file_path.suffix + '.lock')
    id_map = {u['id']: u['line'].rstrip('\n') for u in updates}

    try:
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

            new_lines = [new_line + '\n' for item_id, new_line in id_map.items()
                         if item_id not in found]
            if new_lines:
                # id:14d0 — anchor brand-new ids BEFORE the first archive-class
                # heading (Done/Archive/Icebox); EOF append is the fallback only
                # when no such heading exists. Existing-id replacements above are
                # untouched (in-place, position preserved).
                anchor = _first_archive_heading_index(result)
                if anchor is None:
                    result.extend(new_lines)
                else:
                    result[anchor:anchor] = new_lines

            _atomic_write(file_path, ''.join(result))
            # id:148b — atomic write+commit under the SAME flock (scoop-window close).
            if commit_msg is not None:
                _commit_ledger(file_path, commit_msg)
    finally:
        lock_path.unlink(missing_ok=True)


def update_sections(file_path: Path, sections: list, commit_msg: str | None = None) -> None:
    """Replace ## section blocks by heading, under flock."""
    lock_path = file_path.with_suffix(file_path.suffix + '.lock')
    # Normalise: heading key stripped, content ends with exactly one newline
    section_map = {
        s['heading'].strip(): s['content'].rstrip('\n') + '\n'
        for s in sections
    }

    try:
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
            # id:148b — atomic write+commit under the SAME flock (scoop-window close).
            if commit_msg is not None:
                _commit_ledger(file_path, commit_msg)
    finally:
        lock_path.unlink(missing_ok=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='cmd')

    p_ids = sub.add_parser('update-ids', help='Replace lines by <!-- id:XXXX --> (for TODO.md)')
    p_ids.add_argument('--file', required=True, help='Path to the markdown file')
    p_ids.add_argument('--commit', metavar='MSG',
                       help='id:148b — after the write, commit JUST this file under the same '
                            'flock with MSG (scoped `git add -- <file>`, never `git add -A`). '
                            'Opt-in; idempotent (clean no-op if unchanged); non-fatal on git error.')

    p_sec = sub.add_parser('update-sections', help='Replace ## section blocks by heading (for user-profile.md)')
    p_sec.add_argument('--file', required=True, help='Path to the markdown file')
    p_sec.add_argument('--commit', metavar='MSG',
                       help='id:148b — after the write, commit JUST this file under the same flock '
                            'with MSG (scoped add). Opt-in; idempotent; non-fatal on git error.')

    args = parser.parse_args()

    try:
        delta = json.load(sys.stdin)
    except json.JSONDecodeError as e:
        print(f'md-merge: invalid JSON on stdin: {e}', file=sys.stderr)
        sys.exit(1)

    if args.cmd == 'update-ids':
        update_ids(Path(args.file), delta.get('updates', []), getattr(args, 'commit', None))
    elif args.cmd == 'update-sections':
        update_sections(Path(args.file), delta.get('sections', []), getattr(args, 'commit', None))
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == '__main__':
    main()
