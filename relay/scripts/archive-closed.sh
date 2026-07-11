#!/usr/bin/env bash
# archive-closed.sh — TWIN-SAFELY archive closed `- [x]` items from BOTH
#   TODO.md and ROADMAP.md into their `*.archive.md` siblings.
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
# Headings are never moved/pruned (an emptied section keeps its heading).
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
import sys, re
from pathlib import Path

root    = Path(sys.argv[1])
dry_run = sys.argv[2] == '1'

ID_RE      = re.compile(r'<!-- id:([0-9a-f]{4}) -->')
HEADING_RE = re.compile(r'^#{1,6}\s')
# Top-level (indent 0) checkbox bullet only.
TOPBULLET  = re.compile(r'^- \[([ xX])\] ')

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
    """Yield (kind, payload). kind='block' payload=(state_or_None, [lines]);
    kind='other' payload=[lines]. Top-level closed/open bullets become 'block';
    everything else (headings, prose, nested content) stays 'other'."""
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
            out.append(('block', (state, block)))
            i = j
        else:
            out.append(('other', [line]))
            i += 1
    return out

def id_state_map(blocks):
    """id -> 'x'|' ' for top-level bullets that carry an id (first-wins)."""
    m = {}
    for kind, payload in blocks:
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

todo_lines = load(todo_path)
road_lines = load(road_path)

todo_blocks = parse_blocks(todo_lines) if todo_lines is not None else None
road_blocks = parse_blocks(road_lines) if road_lines is not None else None

# Cross-ledger twin state, computed from the ORIGINAL content of each ledger.
todo_ids = id_state_map(todo_blocks) if todo_blocks is not None else {}
road_ids = id_state_map(road_blocks) if road_blocks is not None else {}

def plan(blocks, other_ids):
    """Split blocks into (kept_lines, archived_blocks, skipped_ids).
    A top-level closed [x] block is archived unless it carries an id whose
    cross-ledger twin (in `other_ids`) is still open ' '."""
    kept = []
    archived = []          # list of [lines]
    skipped = []           # list of ids skipped for twin-open protection
    moved = 0
    for kind, payload in blocks:
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
    return kept, archived, skipped, moved

def strip_trailing_blanks(block):
    b = list(block)
    while len(b) > 1 and b[-1].strip() == '':
        b.pop()
    return b

def apply_and_report(name, src_path, blocks, other_ids):
    if blocks is None:
        return
    kept, archived, skipped, moved = plan(blocks, other_ids)
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
    arch_path.write_text(existing)

    new_src = ''.join(kept).rstrip('\n') + '\n'
    src_path.write_text(new_src)
    print(f"archive-closed[{name}]: archived {moved} item(s) -> {arch_path.name}", file=sys.stderr)
    for tk in skipped:
        print(f"archive-closed[{name}]: skipped id:{tk} (twin open)", file=sys.stderr)

apply_and_report('TODO',    todo_path, todo_blocks, road_ids)
apply_and_report('ROADMAP', road_path, road_blocks, todo_ids)
PYEOF
