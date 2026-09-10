#!/usr/bin/env python3
"""review-box-tick.py -- the REVIEW_ME section-composer (id:7c75).

WHY THIS EXISTS
---------------
`/relay human` section 3(a) mandates an apply step its own tooling could not perform.
`meeting/md-merge.py` addresses a line only two ways:

  * `update-ids`      -- by an ANCHORED `<!-- id:XXXX -->` marker on the line, or
  * `update-sections` -- by a `## ` heading, replacing that section WHOLESALE.

Most repos' REVIEW_ME boxes carry no marker on the checkbox line, so `update-ids` has no
grip. `update-sections` does have a grip wherever a `## ` heading exists, but its unit is
the whole section -- and the common shape is ONE coarse heading over MANY boxes (csgebra
`## Open` over 7, jobAI 3 headings over 9, toesnail 12 in one section). Hand-composing that
replacement text is exactly where a wrong box gets ticked silently, so agents (correctly)
refused to do it and reached for nothing at all -- `Edit` bypasses the flock precisely as
`sed -i` does.

This tool is the missing composer. It extracts the enclosing section VERBATIM, flips
EXACTLY ONE checkbox inside it, appends the caller's re-checkable rationale to that one
line, and hands the whole rewritten section to `md-merge.py update-sections`, so the write
still happens under md-merge's flock. It never writes a ledger itself.

THE ONE-BOX GUARANTEE IS THE WHOLE VALUE
----------------------------------------
Every refusal below exists because flipping the wrong box in a 12-box section is silent
damage. In particular a selector that matches 0 boxes and one that matches 2+ get
DIFFERENT messages and DIFFERENT exit codes, because the remedies are opposite: narrow the
selector, versus the box is not there at all. This mirrors the id:6d7e ruling on
`self-transcript.sh` -- a multi-match is an unresolved identity, not a tie to break;
refusing costs a verdict, guessing costs a wrong answer that looks authoritative.

DRY-RUN IS INERT BY CONSTRUCTION, NOT BY A RE-CHECKED FLAG
----------------------------------------------------------
`relay/scripts/scan-routed.sh` (id:f563) documents that `--dry-run` "writes NOTHING" and
then really deletes inbox lines, because `DRY_RUN` is consulted at one call site while a
second write branch guards on `APPLY` alone. The lesson taken here: the dry run does not
guard the writer, it never gives the writer the real path. `_run_md_merge()` is the ONE
function in this file that can write anything, it has exactly ONE call site, and that call
site receives its target path from a single `if args.dry_run:` fork in which the dry branch
passes a COPY in a private temp dir. The real ledger path is unreachable from the dry
branch. As a side benefit the printed diff is produced by running the REAL md-merge over
the copy, so it shows the byte-exact result rather than a re-implementation of md-merge's
whitespace handling.

USAGE
-----
    review-box-tick.py --file <REVIEW_ME.md> --match '<exact substring>' \
        --rationale 'ANSWERED 2026-09-10: option (a); see <evidence>' [--dry-run]
    review-box-tick.py --file <REVIEW_ME.md> --line 42 --rationale '...' [--dry-run]
    ... [--commit 'review: tick <box>']   # passed through to md-merge, same flock

EXIT CODES (every non-zero refusal prints NOTHING on stdout)
    0  applied, or a clean no-op (box already ticked), or a dry run
    1  usage / IO / bad input
    2  SELECTOR MATCHED NOTHING     -- the box is not in this file
    3  SELECTOR MATCHED 2+ BOXES    -- unresolved identity; narrow the selector
    4  NO `## ` HEADING ABOVE THE BOX -- `update-sections` has no anchor here at all
    5  THE HEADING REPEATS IN THE FILE -- see "REPEATED HEADINGS" below
    6  THE FILE CHANGED under us between read and hand-off
    7  INTERNAL INVARIANT: the composed section did not flip exactly one box
    8  md-merge.py itself failed (its own status is NOT propagated -- its exit 3 means
       LedgerCommitError, which would collide with the ambiguous-selector code here)

REPEATED HEADINGS: WE REFUSE (exit 5)
-------------------------------------
`md-merge.py update-sections` keys purely on heading text and rewrites EVERY section whose
heading matches. If `## Open` occurs twice, handing it one section body would overwrite
both -- duplicating our section and destroying the other one. There is no line-anchored
heading form in md-merge to fall back on, so the only safe answer is to refuse and name
both line numbers. Do not "fix" this by taking the first occurrence.

HEADING GRAMMAR IS MIRRORED FROM md-merge ON PURPOSE
----------------------------------------------------
md-merge's section scanner matches `^#{2,}\\s+`, so a level-1 `# Human review queue` does
NOT open or close a section for it. This file uses the identical regex for both the upward
search and the section end, so the block we extract is exactly the block md-merge will
replace. If md-merge's grammar ever changes, change `HEADING_RE` here in the same commit.
"""
from __future__ import annotations

import argparse
import contextlib
import difflib
import hashlib
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

# Mirrors meeting/md-merge.py update_sections(). Keep in lockstep -- see module docstring.
HEADING_RE = re.compile(r'^(#{2,})\s+(.+)')
# A box HEAD is a checkbox at column 0. An indented checkbox is a sub-item of the box
# above it, never a box in its own right, so `--match` never resolves to one. `--line`
# may still name one deliberately.
BOX_HEAD_RE = re.compile(r'^- \[([ xX])\]')
ANY_CHECKBOX_RE = re.compile(r'^(\s*- \[)([ xX])(\])')
# A trailing run of HTML comment markers (`<!-- id:XXXX -->`, `<!-- routed:XXXX -->`, ...).
# The rationale is inserted BEFORE this run so an anchored marker stays line-final, which
# is what the anchored-id readers (orphan-scan, lib-anchored-id.sh) expect.
TRAILING_MARKERS_RE = re.compile(r'((?:\s*<!--[^>]*-->)+)\s*$')
DASH_RE = re.compile(r'[–—]')


class Refusal(Exception):
    def __init__(self, code: int, message: str) -> None:
        super().__init__(message)
        self.code = code


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _heading_key(match: re.Match) -> str:
    """Normalise exactly as md-merge.py does, so the key it looks up is the key we send."""
    return match.group(1) + ' ' + match.group(2).strip()


def _box_blocks(lines: list[str]) -> list[tuple[int, int]]:
    """(head_index, end_index_exclusive) for every column-0 checkbox block."""
    heads = [i for i, ln in enumerate(lines) if BOX_HEAD_RE.match(ln)]
    blocks = []
    for n, head in enumerate(heads):
        end = len(lines)
        for j in range(head + 1, len(lines)):
            if BOX_HEAD_RE.match(lines[j]) or HEADING_RE.match(lines[j]):
                end = j
                break
        # A following heading may sit before the next head; the loop above already stops
        # at whichever comes first.
        if n + 1 < len(heads):
            end = min(end, heads[n + 1])
        blocks.append((head, end))
    return blocks


def resolve_target(lines: list[str], match_text: str | None, line_no: int | None) -> int:
    """Return the 0-based index of the ONE checkbox line to flip, or refuse loudly."""
    if line_no is not None:
        idx = line_no - 1
        if idx < 0 or idx >= len(lines):
            raise Refusal(1, f'--line {line_no} is outside the file (1..{len(lines)})')
        if not ANY_CHECKBOX_RE.match(lines[idx]):
            raise Refusal(
                2,
                f'--line {line_no} is not a checkbox line. It reads:\n'
                f'    {lines[idx].rstrip()}\n'
                'Point --line at a `- [ ]` / `- [x]` line.',
            )
        return idx

    hits = []
    for head, end in _box_blocks(lines):
        if any(match_text in lines[k] for k in range(head, end)):
            hits.append(head)

    if not hits:
        raise Refusal(
            2,
            f'--match found NO box containing {match_text!r} in this file.\n'
            'This is "the box is not here", not "the selector is too broad": nothing was\n'
            'matched at all. Check the file, or check the text (it is an exact substring,\n'
            'not a regex, and it is matched against the box HEAD line and its continuation\n'
            'lines).',
        )
    if len(hits) > 1:
        listing = '\n'.join(f'    line {h + 1}: {lines[h].rstrip()[:110]}' for h in hits)
        raise Refusal(
            3,
            f'--match {match_text!r} is AMBIGUOUS: it matched {len(hits)} boxes.\n'
            f'{listing}\n'
            'REFUSING. A multi-match is an unresolved identity, not a tie to break (id:6d7e)\n'
            '-- ticking the wrong box in a shared section is silent damage. Narrow --match\n'
            'to text unique to one box, or address the box by --line <N>.',
        )
    return hits[0]


def enclosing_heading(lines: list[str], target: int) -> tuple[int, int, str]:
    """(heading_index, section_end_exclusive, heading_key) for the section holding target."""
    head_idx = None
    for i in range(target, -1, -1):
        if HEADING_RE.match(lines[i]):
            head_idx = i
            break
    if head_idx is None:
        raise Refusal(
            4,
            'NO `## ` heading above this box, so `md-merge.py update-sections` has no\n'
            'anchor for it and this tool cannot compose a write. (md-merge matches\n'
            '`^#{2,}` -- a level-1 `# Human review queue` title does NOT count.)\n'
            'This file needs either a `## ` heading around its boxes, or an anchored\n'
            '`<!-- id:XXXX -->` marker on the checkbox line so `update-ids` can address it.\n'
            'Neither is this tool\'s job to mint.',
        )

    end = len(lines)
    for j in range(head_idx + 1, len(lines)):
        if HEADING_RE.match(lines[j]):
            end = j
            break

    key = _heading_key(HEADING_RE.match(lines[head_idx]))
    dupes = [i + 1 for i, ln in enumerate(lines)
             if HEADING_RE.match(ln) and _heading_key(HEADING_RE.match(ln)) == key]
    if len(dupes) > 1:
        raise Refusal(
            5,
            f'The heading {key!r} occurs {len(dupes)} times in this file '
            f'(lines {", ".join(map(str, dupes))}).\n'
            'REFUSING. `md-merge.py update-sections` keys on heading TEXT and rewrites EVERY\n'
            'matching section, so applying here would duplicate this section into all of them\n'
            'and destroy the others. Give the sections distinct headings, or address the box\n'
            'through an anchored `<!-- id:XXXX -->` marker with `md-merge.py update-ids`.',
        )
    return head_idx, end, key


def tick_line(line: str, rationale: str) -> str:
    """`- [ ] foo <!-- id:x -->` -> `- [x] foo -- <rationale> <!-- id:x -->`."""
    m = ANY_CHECKBOX_RE.match(line)
    flipped = line[:m.start(2)] + 'x' + line[m.end(2):]
    newline = '\n' if flipped.endswith('\n') else ''
    body = flipped[:-1] if newline else flipped
    body = body.rstrip()
    tail = ''
    tm = TRAILING_MARKERS_RE.search(body)
    if tm:
        tail = tm.group(1).strip()
        body = body[:tm.start()].rstrip()
    parts = [body, f'-- {rationale}']
    if tail:
        parts.append(tail)
    return ' '.join(parts) + newline


def compose(lines: list[str], target: int, head_idx: int, end: int, rationale: str) -> str:
    """Return the rewritten section text. Verbatim except for the ONE flipped line."""
    section = lines[head_idx:end]
    rel = target - head_idx
    new_section = list(section)
    new_section[rel] = tick_line(section[rel], rationale)

    # The one-box invariant, checked rather than asserted in prose.
    differing = [i for i in range(len(section)) if section[i] != new_section[i]]
    unticked_before = sum(1 for ln in section if ANY_CHECKBOX_RE.match(ln)
                          and ANY_CHECKBOX_RE.match(ln).group(2) == ' ')
    unticked_after = sum(1 for ln in new_section if ANY_CHECKBOX_RE.match(ln)
                         and ANY_CHECKBOX_RE.match(ln).group(2) == ' ')
    if differing != [rel] or unticked_after != unticked_before - 1:
        raise Refusal(
            7,
            'INTERNAL INVARIANT VIOLATED: the composed section did not flip exactly one '
            f'box (changed lines {differing}, open boxes {unticked_before} -> '
            f'{unticked_after}). Nothing was written.',
        )
    return ''.join(new_section)


def _run_md_merge(md_merge: Path, target_file: Path, heading: str, content: str,
                  commit_msg: str | None) -> None:
    """THE ONLY WRITER IN THIS FILE, and it has exactly ONE call site (see main()).

    Inertness of --dry-run is a property of WHICH PATH this function is GIVEN, never of a
    flag re-checked inside it: one fork picks the target path, the dry side of it picks a
    copy in a private temp dir, and there is no second write branch a missed flag check
    could slip through. See the module docstring (id:f563).
    """
    payload = json.dumps({'sections': [{'heading': heading, 'content': content}]})
    cmd = [sys.executable, str(md_merge), 'update-sections', '--file', str(target_file)]
    if commit_msg:
        cmd += ['--commit', commit_msg]
    proc = subprocess.run(cmd, input=payload, text=True, capture_output=True)
    if proc.stderr:
        sys.stderr.write(proc.stderr)
    if proc.returncode != 0:
        # Deliberately NOT re-raised as md-merge's own status: exit 3 there means
        # LedgerCommitError, exit 3 here means an ambiguous selector.
        raise Refusal(8, f'md-merge.py failed (exit {proc.returncode})')


def main() -> int:
    p = argparse.ArgumentParser(
        description='Tick exactly one REVIEW_ME box through md-merge.py update-sections.',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    p.add_argument('--file', required=True, help='Path to REVIEW_ME.md (or any ledger).')
    sel = p.add_mutually_exclusive_group(required=True)
    sel.add_argument('--match', help='Exact substring identifying ONE box (head or continuation).')
    sel.add_argument('--line', type=int, help='1-based line number of the checkbox line.')
    p.add_argument('--rationale', required=True,
                   help='Re-checkable rationale appended to the ticked line.')
    p.add_argument('--dry-run', action='store_true',
                   help='Print the unified diff and write NOTHING. Runs the real md-merge '
                        'over a temp COPY, so the diff is byte-exact.')
    p.add_argument('--commit', metavar='MSG',
                   help='Passed to md-merge --commit: commit just this file under the same '
                        'flock. Ignored (never forwarded) in --dry-run.')
    p.add_argument('--md-merge', default=None,
                   help='Path to meeting/md-merge.py (default: resolved from this script).')
    args = p.parse_args()

    md_merge = (Path(args.md_merge) if args.md_merge
                else Path(__file__).resolve().parents[2] / 'meeting' / 'md-merge.py')
    if not md_merge.is_file():
        raise Refusal(1, f'md-merge.py not found at {md_merge}')

    path = Path(args.file)
    if not path.is_file():
        raise Refusal(1, f'no such file: {path}')

    rationale = args.rationale.strip()
    if not rationale:
        raise Refusal(1, '--rationale is empty; the tick must carry a re-checkable reason.')
    if '\n' in args.rationale.strip('\n'):
        raise Refusal(1, '--rationale must be a single line (it is appended to one line).')
    if DASH_RE.search(rationale):
        raise Refusal(1, '--rationale contains an em/en dash, which is banned fleet-wide. '
                         'Use `--` or restructure.')

    before = path.read_text()
    digest = hashlib.sha256(before.encode()).hexdigest()
    lines = before.splitlines(keepends=True)

    target = resolve_target(lines, args.match, args.line)

    if ANY_CHECKBOX_RE.match(lines[target]).group(2) in ('x', 'X'):
        print(f'no-op: line {target + 1} is already ticked; nothing to do.')
        print(f'    {lines[target].rstrip()}')
        return 0

    head_idx, end, heading = enclosing_heading(lines, target)
    content = compose(lines, target, head_idx, end, rationale)

    # Narrow the TOCTOU window: md-merge re-reads under its own flock, and an unmatched
    # heading is APPENDED at EOF rather than refused, so a section that vanished under us
    # would be silently duplicated at the end of the file. Refuse instead.
    if _sha256(path) != digest:
        raise Refusal(6, f'{path} changed between read and hand-off. Nothing was written; '
                         're-run so the section is composed from current content.')

    # ONE fork, ONE writer call site. The dry branch substitutes the TARGET PATH, it does
    # not guard the writer -- so there is no second write branch for a re-checked flag to
    # miss (the id:f563 defect shape). See the module docstring.
    with contextlib.ExitStack() as stack:
        if args.dry_run:
            td = stack.enter_context(tempfile.TemporaryDirectory(prefix='review-box-tick-'))
            write_target = Path(td) / path.name
            shutil.copyfile(path, write_target)
            commit_msg = None
        else:
            write_target = path
            commit_msg = args.commit

        _run_md_merge(md_merge, write_target, heading, content, commit_msg)

        if args.dry_run:
            after = write_target.read_text()

    if args.dry_run:
        diff = difflib.unified_diff(
            before.splitlines(keepends=True), after.splitlines(keepends=True),
            fromfile=f'a/{path}', tofile=f'b/{path} (proposed)', n=2)
        sys.stdout.writelines(diff)
        print(f'DRY RUN: nothing written. Target was line {target + 1} '
              f'under heading {heading!r}.')
        return 0

    print(f'ticked line {target + 1} under heading {heading!r} in {path}')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Refusal as r:
        print(f'review-box-tick: {r}', file=sys.stderr)
        sys.exit(r.code)
