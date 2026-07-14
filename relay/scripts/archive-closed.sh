#!/usr/bin/env bash
# archive-closed.sh — TWIN-SAFELY archive closed `- [x]` items from BOTH
#   TODO.md and ROADMAP.md into their `*.archive.md` siblings. Also archives
#   REVIEW_ME.md -> REVIEW_ME.archive.md as a third source; REVIEW_ME items are
#   NOT cross-ledger twins, so REVIEW_ME archiving uses an empty twin map and is
#   decided purely by the item's own [x]/[ ] state (no open-twin protection).
#
# Usage: archive-closed.sh [--dry-run] [<repo-root>]
#   <repo-root> defaults to `git rev-parse --show-toplevel`.
#
# Rationale: closed items clutter both ledgers and get caught by lane migration.
# Unlike todo-update/archive-done.sh (TODO-only, age-gated), this archives ALL
# qualifying closed items from BOTH ledgers, un-age-gated — but SAFELY w.r.t.
# meeting/orphan-scan.sh --cross-ledger, which correlates TODO<->ROADMAP by
# `<!-- id:XXXX -->` token (single-id-two-views).
#
# TWIN-SAFE RULE: for an item bearing <!-- id:XXXX -->, only archive it when its
# cross-ledger twin is ALSO closed `[x]` OR absent. NEVER archive a closed item
# whose twin in the OTHER ledger is still open `- [ ]` — that is exactly the
# drift state orphan-scan --cross-ledger guards; archiving one side would hide
# it. An item with NO id has no twin → safe to archive from its own ledger.
#
# Only GENUINE top-level (indent-0) `- [x]` list items are considered. Closed
# items nested as evidence inside an open item's body are left untouched. A
# top-level item's block spans continuation lines until the next top-level
# checkbox bullet or heading; the WHOLE block moves as one unit.
#
# A grouping heading (##/###/…) that this run EMPTIES of all top-level items is
# MOVED into the archive with it, UNLESS it is protected: the H1 title, or a
# heading whose text is exactly one of Items/Current/Done/Backlog (case-insensitive).
# A heading already empty on arrival, or one that still has items under it after
# archiving, is left untouched.
# --dry-run prints a per-ledger summary and mutates NOTHING (the default posture
# to review before a real run). A second run is a no-op (idempotent).

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
        echo "archive-closed: no <repo-root> given and not in a git repo" >&2; exit 1; }
fi
[[ -d "$ROOT" ]] || { echo "archive-closed: $ROOT is not a directory" >&2; exit 1; }

python3 - "$ROOT" "$DRY_RUN" <<'PYEOF'
import sys, re, bisect
from pathlib import Path

root    = Path(sys.argv[1])
dry_run = sys.argv[2] == '1'

ID_RE      = re.compile(r'<!-- id:([0-9a-f]{4}) -->')
HEADING_RE = re.compile(r'^#{1,6}\s')
# Top-level (indent 0) checkbox bullet only.
TOPBULLET  = re.compile(r'^- \[([ xX])\] ')

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
        return True  # be conservative — shouldn't happen for a HEADING_RE match
    level, text = info
    if level == 1:
        return True
    return text.lower() in PROTECTED_TEXTS

def is_block_start(line):
    """A top-level `- [ ]`/`- [x]` bullet at indent 0 starts a new item block."""
    return TOPBULLET.match(line) is not None

def is_boundary(line):
    """A block ends at the next top-level checkbox bullet OR any heading."""
    return is_block_start(line) or HEADING_RE.match(line) is not None

def first_id(block_lines):
    for l in block_lines:
        m = ID_RE.search(l)
        if m:
            return m.group(1)
    return None

def parse_blocks(lines):
    """Yield (kind, payload, start_idx). kind='block' payload=(state_or_None, [lines]);
    kind='other' payload=[lines]. Top-level closed/open bullets become 'block';
    everything else (headings, prose, nested content) stays 'other'. start_idx is
    the ORIGINAL line index the entry begins at (used to attribute archived items
    to their owning heading)."""
    out = []
    i, n = 0, len(lines)
    while i < n:
        line = lines[i]
        if is_block_start(line):
            state = TOPBULLET.match(line).group(1).lower()  # ' ' or 'x'
            block = [line]
            j = i + 1
            while j < n and not is_boundary(lines[j]):
                block.append(lines[j])
                j += 1
            out.append(('block', (state, block), i))
            i = j
        else:
            out.append(('other', [line], i))
            i += 1
    return out

def id_state_map(blocks):
    """id -> 'x'|' ' for top-level bullets that carry an id (first-wins)."""
    m = {}
    for kind, payload, _start in blocks:
        if kind != 'block':
            continue
        state, block = payload
        tk = first_id(block)
        if tk is not None and tk not in m:
            m[tk] = state
    return m

def load(path):
    if not path.exists():
        return None
    return path.read_text().splitlines(keepends=True)

todo_path = root / 'TODO.md'
road_path = root / 'ROADMAP.md'
review_path = root / 'REVIEW_ME.md'

todo_lines = load(todo_path)
road_lines = load(road_path)
review_lines = load(review_path)

todo_blocks = parse_blocks(todo_lines) if todo_lines is not None else None
road_blocks = parse_blocks(road_lines) if road_lines is not None else None
review_blocks = parse_blocks(review_lines) if review_lines is not None else None

# Cross-ledger twin state, computed from the ORIGINAL content of each ledger.
todo_ids = id_state_map(todo_blocks) if todo_blocks is not None else {}
road_ids = id_state_map(road_blocks) if road_blocks is not None else {}

def plan(blocks, other_ids):
    """Split blocks into (kept_lines, archived_blocks, skipped_ids, moved,
    archived_count_by_heading). A top-level closed [x] block is archived unless
    it carries an id whose cross-ledger twin (in `other_ids`) is still open ' '.
    archived_count_by_heading maps the ORIGINAL start-line-index of the owning
    heading (-1 = none) to how many items under it were archived this run —
    used to decide which emptied headings should move into the archive too."""
    # Heading start indices, in document order (original line indices).
    heading_indices = [start for kind, payload, start in blocks
                        if kind == 'other' and HEADING_RE.match(payload[0])]

    kept = []
    archived = []          # list of [lines]
    skipped = []           # list of ids skipped for twin-open protection
    moved = 0
    archived_count_by_heading = {}
    for kind, payload, start in blocks:
        if kind != 'block':
            kept.extend(payload)
            continue
        state, block = payload
        if state != 'x':
            kept.extend(block)
            continue
        tk = first_id(block)
        if tk is not None and other_ids.get(tk) == ' ':
            # Twin still open in the other ledger — MUST NOT archive.
            skipped.append(tk)
            kept.extend(block)
            continue
        archived.append(block)
        moved += 1
        slot = bisect.bisect_right(heading_indices, start) - 1
        owning = heading_indices[slot] if slot >= 0 else -1
        archived_count_by_heading[owning] = archived_count_by_heading.get(owning, 0) + 1
    return kept, archived, skipped, moved, archived_count_by_heading

def strip_trailing_blanks(block):
    b = list(block)
    while len(b) > 1 and b[-1].strip() == '':
        b.pop()
    return b

def plan_heading_moves(kept, archived_count_by_heading, orig_heading_indices):
    """Identify non-protected headings in `kept` that this run emptied of all
    top-level items. Returns (new_kept, heading_blocks)."""
    keep_heading_positions = [idx for idx, l in enumerate(kept) if HEADING_RE.match(l)]
    assert len(keep_heading_positions) == len(orig_heading_indices)

    heading_blocks = []
    remove_ranges = []
    for slot, kpos in enumerate(keep_heading_positions):
        orig_idx = orig_heading_indices[slot]
        hline = kept[kpos]
        if is_protected(hline):
            continue
        if archived_count_by_heading.get(orig_idx, 0) == 0:
            continue  # nothing archived under it this run (incl. already-empty)
        body_start = kpos + 1
        body_end = keep_heading_positions[slot + 1] if slot + 1 < len(keep_heading_positions) else len(kept)
        body = kept[body_start:body_end]
        if any(TOPBULLET.match(l) for l in body):
            continue  # items remain under this heading — leave it
        block = strip_trailing_blanks([hline] + body)
        heading_blocks.append(block)
        remove_ranges.append((kpos, body_end))

    if not remove_ranges:
        return kept, heading_blocks

    new_kept = []
    ri, idx, kn = 0, 0, len(kept)
    while idx < kn:
        if ri < len(remove_ranges) and idx == remove_ranges[ri][0]:
            idx = remove_ranges[ri][1]
            ri += 1
            continue
        new_kept.append(kept[idx])
        idx += 1
    return new_kept, heading_blocks

def apply_and_report(name, src_path, blocks, other_ids):
    if blocks is None:
        return
    kept, archived, skipped, moved, archived_count_by_heading = plan(blocks, other_ids)
    arch_path = src_path.with_name(src_path.stem + '.archive.md')

    if dry_run:
        print(f"archive-closed[{name}]: would move {moved} item(s) -> {arch_path.name}")
        if skipped:
            for tk in skipped:
                print(f"archive-closed[{name}]: SKIP id:{tk} — cross-ledger twin still OPEN; not archiving")
        return

    if moved == 0:
        print(f"archive-closed[{name}]: nothing to archive.", file=sys.stderr)
        if skipped:
            for tk in skipped:
                print(f"archive-closed[{name}]: skipped id:{tk} (twin open)", file=sys.stderr)
        return

    orig_heading_indices = [start for kind, payload, start in blocks
                             if kind == 'other' and HEADING_RE.match(payload[0])]
    kept, heading_blocks = plan_heading_moves(kept, archived_count_by_heading, orig_heading_indices)

    # Append archived blocks under the archive header.
    if arch_path.exists():
        existing = arch_path.read_text()
        if existing and not existing.endswith('\n'):
            existing += '\n'
    else:
        existing = f"# {src_path.stem} archive\n"
    for block in archived:
        for l in strip_trailing_blanks(block):
            existing += l if l.endswith('\n') else l + '\n'
    for block in heading_blocks:
        for l in block:
            existing += l if l.endswith('\n') else l + '\n'
    arch_path.write_text(existing)

    new_src = ''.join(kept).rstrip('\n') + '\n'
    src_path.write_text(new_src)
    hn = len(heading_blocks)
    extra = f", moved {hn} emptied heading(s)" if hn else ""
    print(f"archive-closed[{name}]: archived {moved} item(s){extra} -> {arch_path.name}", file=sys.stderr)
    for tk in skipped:
        print(f"archive-closed[{name}]: skipped id:{tk} (twin open)", file=sys.stderr)

apply_and_report('TODO',      todo_path,   todo_blocks,   road_ids)
apply_and_report('ROADMAP',   road_path,   road_blocks,   todo_ids)
# REVIEW_ME items are NOT cross-ledger twins — pass an empty id map so no twin
# can ever block or skip an archive decision; archiving is based purely on the
# item's own [x]/[ ] state.
apply_and_report('REVIEW_ME', review_path, review_blocks, {})
PYEOF
