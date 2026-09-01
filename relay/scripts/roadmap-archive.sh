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
# routed:71ed -- AMBIGUOUS-BODY DEFERRAL. That block rule silently RE-ATTRIBUTES an open
# item's body when a new item line is INSERTED between an existing header and its own
# indented bullets: the bullets then follow the insertee, and archiving the insertee sweeps
# them into ROADMAP.archive.md under the wrong id. Observed live (it-infra 090247f, repaired
# by hand at 3f49174): an OPEN [INPUT - access] item lost its Why, gate history and whole
# Acceptance criterion to a closed neighbour, and nothing failed. The shape is ambiguous
# LOCALLY -- it is character-identical to a closed item that genuinely owns the bullets --
# so this script does NOT guess. When an archived item's body is contiguous with a top-level
# bullet that STAYS LIVE, it archives the header line only, LEAVES the body verbatim in
# ROADMAP.md, and says so on stderr naming the id. See the guard below.
#
# id:cd9c: a one-line STUB is left behind in the LIVE ROADMAP.md for every moved
# item — the header line verbatim plus " (archived — see ROADMAP.archive.md)" — so
# the id keeps resolving from the live ledger alone. Only the header line becomes
# the stub; the rest of the block (continuations/body) moves to the archive only.
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
trap 'rm -- "$LOCK_FILE"' EXIT   # created by `exec 9>` above ⇒ exists; no -f needed

cutoff=$(date -d '30 days ago' '+%Y-%m-%d')

# Get the set of lines that were already [x] in the PRIOR commit (HEAD).
PRIOR_DONE_FILE=$(mktemp)
trap 'rm -- "$PRIOR_DONE_FILE"; rm -- "$LOCK_FILE"' EXIT   # both known to exist; no -f needed

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
# ── Archived-stub guard (routed:f833 / loderite id:2ab3-B) ──────────────────────────
# A stub left behind for an already-archived item is BY CONSTRUCTION `- [x]` + an id, and it
# is present in the prior commit — so without this guard the archiver eats its own successor's
# output: it deletes the stub from ROADMAP.md and re-appends the body to ROADMAP.archive.md,
# duplicating ids there and re-blinding `orphan-scan --cross-ledger` (which reads ONLY the
# live file). Reproduced in the fleet: loderite id:154a restored 59 stubs at 1dc91f6, and
# c9059f0 — the SAME relay run, 12 minutes later — deleted 58 of them.
# Grammar mirrors loderite's reference implementation (tools/archive-roadmap.mjs STUB_SUFFIX
# / STUB_LINE_RE). NOT end-anchored, deliberately: real stubs carry trailing annotations past
# the suffix (live: bfb3/3d6c/a10c each carry a `**⚠ …`), and an end anchor would re-archive
# exactly those — the very defect this guard exists for.
STUB_SUFFIX = " (archived — see ROADMAP.archive.md)"
# The `.*` between the id marker and the suffix is LOAD-BEARING (cartulary 2026-08-14,
# routed:4a12): an item line may carry prose AFTER its own `<!-- id:XXXX -->` marker —
# ledger write-backs from `/relay human` and `/meeting` routinely append rationale there.
# Without it the suffix had to follow the marker IMMEDIATELY, so every such stub read as
# un-stubbed and was re-archived + re-stubbed EVERY round: cartulary accumulated up to 9
# duplicate bodies per id in ROADMAP.archive.md and stub suffixes repeated 3x on one line.
# Still NOT end-anchored, for the reason stated above (trailing annotations past the suffix).
stub_line_re = re.compile(r'^- \[x\] .*<!--\s*id:[0-9a-f]{4}\s*-->.*' + re.escape(STUB_SUFFIX))
# Regex for a ## or deeper section heading (matches H1 too — H1 is protected separately).
heading_re  = re.compile(r'^#{1,6}\s')

PROTECTED_TEXTS = {'items', 'current', 'done', 'backlog'}

# ── Ambiguous-body deferral (routed:71ed) ───────────────────────────────────────────
# Set False to restore the pre-fix block rule verbatim (the negative case in
# tests/test_roadmap_archive_block_attribution_71ed.sh mutates exactly this line).
AMBIGUITY_GUARD = True

id_re = re.compile(r'<!--\s*id:([0-9a-f]{4})\s*-->')

def id_of(line):
    m = id_re.search(line)
    return m.group(1) if m else None

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
# entry = ('keep', line, orig_idx) | ('arch', [block_lines], owning_heading_idx, ambiguous)
entries = []
archived_count_by_heading = {}   # owning heading orig idx (-1 = none) -> #items archived
disposition = {}                 # orig idx of a TOP-LEVEL BULLET -> 'keep' | 'arch'
deferred = []                    # (archived id or None, owner id or None) for the stderr report
n = len(lines)
i = 0

def body_is_ambiguous(idx, unit):
    """True when this archived item's continuation body cannot be attributed to it with
    certainty, because it is contiguous with a top-level bullet that SURVIVES in the live
    ledger and carries no body of its own -- the shape an inserted line creates
    (routed:71ed). Deliberately narrow:
      * an EMPTY body is never ambiguous (nothing to lose);
      * an already-archived STUB above cannot own a body -- its body moved on an earlier
        run -- so a stub never triggers the guard;
      * a preceding bullet that THIS run also archives is excluded: both halves land in the
        archive, so no live item loses anything, and firing there would multiply the
        false-positive rate by roughly ten for no gain in safety.
    Measured against 385 historical archiver inputs across 46 repos (13131 archived items),
    this predicate fires on 12 -- one of them the live it-infra incident."""
    if not AMBIGUITY_GUARD:
        return False
    if len(unit) <= 1 or not any(l.strip() for l in unit[1:]):
        return False
    k = idx - 1
    if k < 0:
        return False
    prev = lines[k]
    if not top_bullet_re.match(prev) or stub_line_re.match(prev):
        return False
    return disposition.get(k) == 'keep'
while i < n:
    line = lines[i]
    # An already-archived stub is classified `keep`, never `arch` (routed:f833) — it falls
    # through to the else-branch below and stays in place, one line, exactly as written.
    if top_done_re.match(line) and not stub_line_re.match(line):
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
            disposition[i] = 'arch'
            ambiguous = body_is_ambiguous(i, unit)
            if ambiguous:
                deferred.append((id_of(line), id_of(lines[i - 1])))
            entries.append(('arch', unit, owning, ambiguous))
            archived_count_by_heading[owning] = archived_count_by_heading.get(owning, 0) + 1
            i = j
        else:
            # Same-run tick — leave it in place.
            disposition[i] = 'keep'
            entries.append(('keep', line, i))
            i += 1
    else:
        if top_bullet_re.match(line):
            disposition[i] = 'keep'
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
    else:  # ('arch', block, owning, ambiguous)
        block = e[1]
        ambiguous = e[3]
        # id:cd9c — leave a one-line stub behind in the LIVE ledger so the item's
        # id keeps resolving from ROADMAP.md alone (orphan-scan --cross-ledger
        # reads only the live file). The stub is the header line verbatim plus the
        # ratified suffix; the reader half (stub_line_re, above) already classifies
        # this exact grammar as `keep` on every subsequent run.
        header = block[0].rstrip('\n')
        keep_out.append(header + STUB_SUFFIX + '\n')
        if ambiguous:
            # routed:71ed -- ownership of this body cannot be decided locally, so it is NOT
            # moved. The header is archived and stubbed as usual; the body stays verbatim in
            # the live ledger, directly beneath the stub, exactly where it already was. A
            # one-line note goes into the archive in its place so the missing body is
            # explained where a reader would otherwise go looking for it. Stable across
            # runs: the stub classifies `keep` from here on, so the body is never revisited.
            keep_out.extend(block[1:])
            out_block = [block[0],
                         '  - (roadmap-archive routed:71ed: continuation body RETAINED in '
                         'ROADMAP.md, attribution was ambiguous. See the live ledger.)\n']
        else:
            out_block = block
        if last_appended_heading:
            # First item directly under a just-moved heading — no separator, so
            # the heading and its item are adjacent in the archive.
            arch_out.extend(out_block)
        else:
            arch_out.append('\n')
            arch_out.extend(out_block)
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

# ── LOUD report for every deferral (routed:71ed). Never a silent skip: an unannounced
#    deferral is the same defect class wearing a different coat (id:4347). Exit stays 0 so
#    the rest of the run still archives; integrate.sh reads a non-zero exit as EX_ARCHIVE.
for arch_id, owner_id in deferred:
    a = f"id:{arch_id}" if arch_id else "an item with no id"
    o = f"id:{owner_id}" if owner_id else "the item with no id above it"
    print(
        f"roadmap-archive: AMBIGUOUS BODY ATTRIBUTION for {a}. Its continuation body is\n"
        f"  contiguous with {o}, which stays LIVE and has no body of its own, so the body may\n"
        f"  belong to either. Archived the header line ONLY; the body was LEFT IN PLACE in\n"
        f"  ROADMAP.md. Move it under its real owner by hand (this is the routed:71ed shape:\n"
        f"  a new item line inserted between an existing header and its own bullets).",
        file=sys.stderr)

archived_count = sum(archived_count_by_heading.values())
noun = 'item' if archived_count == 1 else 'items'
hn = len(moved)
hnoun = 'heading' if hn == 1 else 'headings'
extra = f", moved {hn} emptied {hnoun}" if hn else ""
print(f"roadmap-archive: archived {archived_count} {noun}{extra} → {archive_path}", file=sys.stderr)
PYEOF
