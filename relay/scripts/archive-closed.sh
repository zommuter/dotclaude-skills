#!/usr/bin/env bash
# archive-closed.sh — TWIN-SAFELY archive closed `- [x]` items from BOTH
#   TODO.md and ROADMAP.md into their `*.archive.md` siblings. Also archives
#   REVIEW_ME.md -> REVIEW_ME.archive.md as a third source; REVIEW_ME items are
#   NOT cross-ledger twins, so REVIEW_ME archiving uses an empty twin map and is
#   decided purely by the item's own [x]/[ ] state (no open-twin protection).
#
# Usage: archive-closed.sh [--dry-run] [--only todo|roadmap|review_me] [<repo-root>]
#   <repo-root> defaults to `git rev-parse --show-toplevel`.
#
# --only <ledger> (id:046a) restricts the run to ONE source ledger. The DEFAULT is
# unchanged — all three — so every existing caller and test behaves exactly as before.
#
# WHY THE FLAG EXISTS: integrate.sh step 6c invokes this archiver automatically, and it
# must invoke it as `--only review_me`. Two independent reasons, both measured:
#   • ROADMAP.md is ALREADY archived one step earlier (step 6b, roadmap-archive.sh). Running
#     both over the same ledger in the same integrate is a second archiver with its own stub
#     grammar over the same lines — the collision id:fdc4 says to look at BEFORE either is
#     wired anywhere.
#   • The measured relief says REVIEW_ME is the only ledger worth it: REVIEW_ME 30.3–91.0%,
#     TODO 2.7–56.1%, ROADMAP −0.5% to +3.0% — NET-NEGATIVE for two repos, because the
#     id:cd9c stub reproduces the header line verbatim, so a single-line item's stub is
#     LONGER than what it replaced. ROADMAP.md structurally cannot shrink via archiving.
# TODO.md is likewise left to its own owner-facing path (todo-update/archive-done.sh); it is
# the ledger the owner hand-edits most, and this script's un-age-gated policy is not the one
# ratified for it.
# The TWIN-SAFE rule below is unaffected: the twin STATE MAPS are always computed from BOTH
# ledgers' original content regardless of --only, so scoping can never turn a twin-open skip
# into an archive.
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
#
# id:2eba (owner-ratified 2026-09-03) SUPERSEDES id:cd9c: NO STUB IS LEFT BEHIND on
# ANY ledger. An archived item is removed from its live ledger entirely, so all three
# sources now behave identically (before this, ROADMAP.md alone got a stub).
#
# The stub used to double as the idempotency guard. It is REPLACED, not deleted: the
# test is now ARCHIVE MEMBERSHIP — "is this id already a `- [x]` item line in the
# matching *.archive.md?" — which is a pure read of the archive and cannot be defeated
# by the stub being absent. It lives in ONE place, shared with roadmap-archive.sh:
# relay/scripts/lib-archive-idempotency.py (id:4983 — make one source serve both).
# Applying it to all three ledgers (not just ROADMAP) is a strict gain: it is what stops
# a re-added closed item duplicating its body into TODO.archive.md / REVIEW_ME.archive.md.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

DRY_RUN=0
ROOT=""
ONLY=all
want_only=0
for arg in "$@"; do
    if [[ $want_only -eq 1 ]]; then ONLY="$arg"; want_only=0; continue; fi
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --only)    want_only=1 ;;
        --only=*)  ONLY="${arg#--only=}" ;;
        *)         ROOT="$arg" ;;
    esac
done
[[ $want_only -eq 0 ]] || { echo "archive-closed: --only needs a value (todo|roadmap|review_me)" >&2; exit 2; }
case "$ONLY" in
    all|todo|roadmap|review_me) : ;;
    *) echo "archive-closed: --only must be todo|roadmap|review_me (got '$ONLY')" >&2; exit 2 ;;
esac

if [[ -z "$ROOT" ]]; then
    ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
        echo "archive-closed: no <repo-root> given and not in a git repo" >&2; exit 1; }
fi
[[ -d "$ROOT" ]] || { echo "archive-closed: $ROOT is not a directory" >&2; exit 1; }

python3 - "$ROOT" "$DRY_RUN" "$ONLY" "$SCRIPT_DIR" <<'PYEOF'
import sys, re, bisect, os, importlib.util
from pathlib import Path

root    = Path(sys.argv[1])
dry_run = sys.argv[2] == '1'
only    = sys.argv[3] if len(sys.argv) > 3 else 'all'
script_dir = sys.argv[4]

# ── THE idempotency test, in ONE place (id:2eba / id:4983). Loaded by path because this
#    is a heredoc with no __file__ — the same idiom lib-pool-runs.py uses. A failure to
#    load is NOT swallowed: an archiver without its idempotency test duplicates bodies.
_spec = importlib.util.spec_from_file_location(
    "relay_lib_archive_idempotency",
    os.path.join(script_dir, "lib-archive-idempotency.py"))
_ai = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_ai)

ID_RE      = re.compile(r'<!-- id:([0-9a-f]{4}) -->')
HEADING_RE = re.compile(r'^#{1,6}\s')
# Top-level (indent 0) checkbox bullet only.
TOPBULLET  = re.compile(r'^- \[([ xX])\] ')

# id:2eba — the already-archived test. This file USED to carry its own hand-mirrored
# copy of STUB_SUFFIX / STUB_LINE_RE, and that copy had silently dropped the
# load-bearing `.*` between the id marker and the suffix (cartulary 2026-08-14,
# routed:4a12), re-archiving 24 stubs across the 6 own repos in a single run on
# 2026-08-26. That is precisely the "hand-mirrored in N places" defect id:4983 closed
# for the lane grammar, so the definition now lives in ONE file, shared with
# roadmap-archive.sh: relay/scripts/lib-archive-idempotency.py. Do not re-inline it.
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

def strip_trailing_blanks(block):
    b = list(block)
    while len(b) > 1 and b[-1].strip() == '':
        b.pop()
    return b

def plan(blocks, other_ids, archived):
    """Build an ordered `entries` list preserving document order, plus the
    twin-skip set and per-owning-heading archived counts. Entry kinds:
      ('kh', [line], orig_idx)      kept heading line
      ('ko', [lines])               kept other content (prose/blank)
      ('kb', [block_lines])         kept top-level bullet block (open or twin-skipped)
      ('arch', [block_lines], owning_heading_orig_idx)   archived item block
    A top-level closed [x] block is archived unless it carries an id whose
    cross-ledger twin (in `other_ids`) is still open ' ', or its own id is already
    present in `archived` (the id set of the matching *.archive.md — id:2eba)."""
    heading_indices = [start for kind, payload, start in blocks
                        if kind == 'other' and HEADING_RE.match(payload[0])]
    entries = []
    skipped = []           # ids skipped for twin-open protection
    already = []           # ids left in place because the archive already holds them
    moved = 0              # archived item count
    archived_count_by_heading = {}
    heading_line = {}      # orig idx -> heading line text
    for kind, payload, start in blocks:
        if kind != 'block':
            line = payload[0]
            if HEADING_RE.match(line):
                entries.append(('kh', [line], start))
                heading_line[start] = line
            else:
                entries.append(('ko', payload))
            continue
        state, block = payload
        if state != 'x':
            entries.append(('kb', block))
            continue
        if _ai.already_archived(block[0], archived):
            # Already in the archive (or a pre-id:2eba stub) — keep as-is, never
            # re-archive. Reported LOUDLY by the caller; never a silent skip.
            already.append(_ai.item_id(block[0]))
            entries.append(('kb', block))
            continue
        tk = first_id(block)
        if tk is not None and other_ids.get(tk) == ' ':
            # Twin still open in the other ledger — MUST NOT archive.
            skipped.append(tk)
            entries.append(('kb', block))
            continue
        slot = bisect.bisect_right(heading_indices, start) - 1
        owning = heading_indices[slot] if slot >= 0 else -1
        entries.append(('arch', block, owning))
        if tk is not None:
            # Guard against the SAME id appearing twice in one live ledger: the second
            # occurrence now reads as already-archived within this same run.
            archived.add(tk)
        moved += 1
        archived_count_by_heading[owning] = archived_count_by_heading.get(owning, 0) + 1
    return entries, skipped, already, moved, archived_count_by_heading, heading_indices, heading_line

def report_already(name, arch_path, already, stream):
    """LOUD report for closed live items the archive already holds (id:2eba). A silent
    skip is the same defect class wearing a different coat (id:4347)."""
    if not already:
        return
    names = ' '.join(f"id:{t}" if t else "id:?" for t in already)
    print(f"archive-closed[{name}]: {len(already)} closed item(s) are ALREADY present in "
          f"{arch_path.name} and were LEFT IN PLACE rather than archived a second time: "
          f"{names} — these are either pre-id:2eba archive stubs (safe to delete by hand) "
          f"or a genuinely duplicated id; this script never deletes a live line it did not "
          f"archive.", file=stream)


def apply_and_report(name, src_path, blocks, other_ids):
    if blocks is None:
        return
    arch_path = src_path.with_name(src_path.stem + '.archive.md')
    # id:2eba — the archived-id set is read from the archive BEFORE this run appends.
    archived = _ai.archived_ids(arch_path)
    entries, skipped, already, moved, archived_count_by_heading, heading_indices, heading_line = plan(blocks, other_ids, archived)

    if dry_run:
        print(f"archive-closed[{name}]: would move {moved} item(s) -> {arch_path.name}")
        if skipped:
            for tk in skipped:
                print(f"archive-closed[{name}]: SKIP id:{tk} — cross-ledger twin still OPEN; not archiving")
        report_already(name, arch_path, already, sys.stdout)
        return

    if moved == 0:
        print(f"archive-closed[{name}]: nothing to archive.", file=sys.stderr)
        if skipped:
            for tk in skipped:
                print(f"archive-closed[{name}]: skipped id:{tk} (twin open)", file=sys.stderr)
        report_already(name, arch_path, already, sys.stderr)
        return

    # Which non-protected headings did this run EMPTY of all top-level items?
    # A heading moves iff non-protected AND ≥1 item archived under it this run
    # AND no top-level bullet survives under it (in the kept stream).
    surviving_bullet = {}
    cur_h = -1
    for e in entries:
        if e[0] == 'kh':
            cur_h = e[2]
        elif e[0] == 'kb':
            surviving_bullet[cur_h] = True
    moved_headings = set()
    for H in heading_indices:
        if is_protected(heading_line[H]):
            continue
        if archived_count_by_heading.get(H, 0) == 0:
            continue  # nothing archived under it this run (incl. already-empty)
        if surviving_bullet.get(H):
            continue  # items remain under this heading — leave it
        moved_headings.add(H)

    # Stream kept + archived content in ORIGINAL document order. A moved heading
    # (and any residual section content beneath it) routes to the archive; its
    # archived item blocks follow it there, keeping the heading adjacent to its
    # items (grouping context preserved).
    keep_out = []
    arch_out = []
    last_appended_heading = False
    cur_moved = False
    for e in entries:
        if e[0] == 'kh':
            line = e[1][0]
            if e[2] in moved_headings:
                arch_out.append('\n')
                arch_out.append(line)
                last_appended_heading = True
                cur_moved = True
            else:
                keep_out.append(line)
                cur_moved = False
        elif e[0] in ('ko', 'kb'):
            payload = e[1]
            if cur_moved:
                # residual section content under a moved heading → archive it,
                # dropping pure-blank lines so the heading stays adjacent to its item.
                for l in payload:
                    if l.strip() != '':
                        arch_out.append(l)
            else:
                keep_out.extend(payload)
        else:  # ('arch', block, owning)
            # id:2eba — NOTHING is left behind in the live ledger, on any of the three
            # sources. The whole block moves.
            block = strip_trailing_blanks(e[1])
            if last_appended_heading:
                arch_out.extend(block)
            else:
                arch_out.append('\n')
                arch_out.extend(block)
            last_appended_heading = False

    # Append archived content under the archive header.
    if arch_path.exists():
        existing = arch_path.read_text()
        if existing and not existing.endswith('\n'):
            existing += '\n'
    else:
        existing = f"# {src_path.stem} archive\n"
    for l in arch_out:
        existing += l if l.endswith('\n') else l + '\n'
    arch_path.write_text(existing)

    new_src = ''.join(keep_out).rstrip('\n') + '\n'
    src_path.write_text(new_src)
    hn = len(moved_headings)
    extra = f", moved {hn} emptied heading(s)" if hn else ""
    print(f"archive-closed[{name}]: archived {moved} item(s){extra} -> {arch_path.name}", file=sys.stderr)
    for tk in skipped:
        print(f"archive-closed[{name}]: skipped id:{tk} (twin open)", file=sys.stderr)
    report_already(name, arch_path, already, sys.stderr)

# --only (id:046a) gates only the WRITE step. `todo_ids`/`road_ids` above are still built
# from BOTH ledgers' original content, so a scoped run makes exactly the same twin-safe
# decisions a full run would — narrowing the scope can never turn a twin-open SKIP into an
# archive.
if only in ('all', 'todo'):
    apply_and_report('TODO',      todo_path,   todo_blocks,   road_ids)
if only in ('all', 'roadmap'):
    apply_and_report('ROADMAP',   road_path,   road_blocks,   todo_ids)
# REVIEW_ME items are NOT cross-ledger twins — pass an empty id map so no twin
# can ever block or skip an archive decision; archiving is based purely on the
# item's own [x]/[ ] state.
if only in ('all', 'review_me'):
    apply_and_report('REVIEW_ME', review_path, review_blocks, {})
PYEOF
