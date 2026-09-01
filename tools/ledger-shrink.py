#!/usr/bin/env python3
"""ledger-shrink.py -- move an over-long ledger item's PROSE BODY off its head line into
`docs/ledger-notes/<id>.md`, leaving a slim head plus a pointer.

Ratified format: `docs/meeting-notes/2026-09-01-2226-ledger-line-shrink-format.md` (id:0d7c),
INCLUDING its post-closure Amendment session. Ported from loderite's
`tools/extract-roadmap-notes.mjs` (`splitHead` / `MUST_KEEP_PATTERNS` / `--split-heads`),
stdlib-only because this repo is bash + stdlib python and does not carry node.

WHY. Measured here 2026-09-01: `TODO.md` carries 1,261,641 bytes on 674 item lines
(median 1,380, p90 3,690, max 28,617 -- one `grep` hit returning roughly 7k tokens).
An accumulation of such hits is what killed a relay child with `Prompt is too long`.

THE HARD CONSTRAINT. A head line is a CONTROL SURFACE, not prose. `classify-repo.sh`
matches gate markers as UNANCHORED SUBSTRINGS over the whole raw line, the lane tag routes
dispatch, and the `<!-- id:XXXX -->` anchor is what makes the item addressable at all.
Dropping any of them while slimming makes the item invisible to dispatch or silently
un-gates it: the id:d35a silent-no-op class. Hence KEEP-BY-PATTERN, never move-by-guess.
Anything matching MUST_KEEP stays on the line even if it sat mid-body; everything else is
relocated VERBATIM, so nothing is lost.

REFUSAL IS ALWAYS SAFE, A WRONG CUT IS NOT. Four refusals, each guarding a measured
failure: a pointer already present (idempotence); no defensible cut point; under 40 chars
would actually move; and -- the amendment's rule -- the item's block carries ANOTHER item's
`<!-- id:XXXX -->`. loderite's sweep silently dropped four ids (89f9, a5b6, ba07, ed26) that
way: the body survived in the note file, the ADDRESS did not, and nothing failed loudly.
`TODO.md` here carries 21 indented lines with their own id, so this rule is load-bearing.

Usage:
  tools/ledger-shrink.py --file TODO.md --dry-run [--min-chars N]   # report, write nothing
  tools/ledger-shrink.py --file TODO.md --apply    [--min-chars N]  # perform the move

Dry-run is the DEFAULT. Nothing is ever written without an explicit `--apply`.
"""

from __future__ import annotations

import argparse
import fcntl
import os
import re
import sys

NOTES_DIR = "docs/ledger-notes"

# The ratified ratchet budget (D4): 500 chars on the head line.
DEFAULT_MIN_CHARS = 500

# Minimum prose that must actually move for a split to be worth its risk.
MIN_MOVED_CHARS = 40

TOP_ITEM_RE = re.compile(r"^- \[([ xX])\]")
HEADING_RE = re.compile(r"^#{1,6}\s")
ID_RE = re.compile(r"<!--\s*id:([0-9a-f]{4})\s*-->")

# Legacy em dash / en dash still appear as lane DELIMITERS mid-migration; the detectors
# match both spellings, so the keep-patterns must too. Written as escapes so this source
# file itself contains no such character (fleet style rule).
_DASH = "[-" + "\u2013" + "\u2014" + "]"

# The lane tag, BY RULE rather than by position. The reference implementation preserves it
# only because it usually sits left of the cut point, which is luck, not a rule: any item
# whose lane bracket is not in the leading run loses it silently.
_LANE_PATTERNS = [
    re.compile(r"\[(?:ROUTINE|HARD|MECHANICAL|INTENSIVE)\]"),
    re.compile(r"\[(?:HARD|INPUT|INTENSIVE)\s*" + _DASH + r"\s*[A-Za-z0-9 _./-]+\]"),
]

# Tokens that MUST remain on the item line. Order-independent; each is re-appended in the
# order it appeared. Derived from `relay/scripts/classify-repo.sh`'s substring matches
# (HUMAN_GATES / LANE_TAGS / the @-marker family / the blocked lexemes) and
# `relay/references/hard-lanes.md`. A marker missing here is a marker that can be silently
# dropped -- see D2: this list is cross-checked, not trusted.
MUST_KEEP_PATTERNS = [
    # STRUCTURAL CATCH-ALL, and it must stay FIRST. In this ecosystem an HTML comment IS
    # structured metadata by construction -- item PROSE never uses one -- so every comment
    # on an item line is a marker, whether or not anyone remembered to enumerate it.
    #
    # This exists because the enumerated list below was NOT enough, caught by the id:0d7c
    # acceptance gate on the first real run against the live ledgers. Shrinking id:78ff's
    # TODO line dropped TWO markers that no pattern named:
    #   <!-- children:b466 -->   a TYPED EDGE (id:46f6); closure is computed from these, so
    #                            losing one silently detaches a child from its parent.
    #   <!-- xledger-ok: ... --> the marker that SUPPRESSES an orphan-scan --cross-ledger
    #                            drift report; losing it made a knowingly-accepted TODO/
    #                            ROADMAP divergence start firing as a new violation.
    # Both are the id:d35a silent-no-op class. Enumerating marker NAMES is precisely how
    # they were missed, and how the next one would be -- so the rule is now structural.
    # The specific patterns below are kept as documentation of WHY each matters; the
    # de-nesting step folds a match wholly contained in this one back to a single append.
    re.compile(r"<!--[^>]*-->"),
    # The anchor: without it the item is unaddressable to `md-merge update-ids` and
    # invisible to `orphan-scan`.
    re.compile(r"<!--\s*id:[0-9a-f]{4}\s*-->"),
    # The cross-repo inbox twin. `append.sh inbox-done` REFUSES (exit 3) unless this exact
    # form is present in the target repo's TODO/ROADMAP, so relocating one blocks a
    # resolution that should pass. MEASURED here: 59 such markers sit after the cut point
    # (48 TODO, 11 ROADMAP). The reference implementation omits this pattern entirely.
    re.compile(r"<!--\s*routed:[0-9a-f]{4}\s*-->"),
    re.compile(r"<!--\s*gated-on:[^>]*-->"),   # typed gate edges
    re.compile(r"gated-on:[0-9a-f]{4}"),       # bare gate edges
    re.compile("\U0001f6a7"),                  # the construction sign, matched bare
    re.compile(r"`?@manual`?"),
    re.compile(r"`?@owner-gated`?"),
    re.compile(r"`?@owner-answered:[0-9-]+`?"),
    re.compile(r"`?@owner-verify`?"),
    re.compile(r"`?@container`?"),
    re.compile(r"`?@wire`?"),
    re.compile(r"`?@needs-auth`?"),
    re.compile(r"BLOCKED on"),
    re.compile(r"blocked on"),
    # Both added after the marker-registry cross-check in tools/shrink-acceptance.py
    # reported them as the only remaining gaps against the real detectors.
    #
    # `⚠ SURFACED` is read by a RUNNABLE detector: classify-repo.sh:316 does
    # `is_surfaced = "⚠ SURFACED" in ln`, which excludes an open executor-lane item from
    # `actionable_routine_open` and counts it into `surfaced_open`, routing the repo to
    # handoff rather than execute (id:65f5 class 3). Relocating it silently converts a
    # no-RED-spec item into a dispatchable one -- the id:d35a class, inverted.
    re.compile(r"⚠ SURFACED"),
    # `@owner-accepted` is read by NO runnable detector -- it is the owner-only greppable
    # receipt that a @manual-acceptance item may be bump-closed (hard-lanes.md:185,
    # id:8089), enforced by review.md's gaming check as prose. That is exactly why it must
    # be kept: relocating it destroys the receipt with nothing mechanical left to notice.
    re.compile(r"`?@owner-accepted`?"),
] + _LANE_PATTERNS  # KEEP-LANE


def pointer_for(item_id: str) -> str:
    """The pointer planted on every slimmed line.

    ASCII dashes only. The reference implementation's `pointerFor` emits an em dash; this
    string lands on hundreds of lines in a repo mid-migration away from that character,
    adjacent to lane delimiters that detectors match by SPELLING, so it is stripped here.
    Gate-lexeme free by construction: `classify-repo.sh` matches gate lexemes as unanchored
    substrings, so a pointer merely MENTIONING one would silently re-impose a gate.
    """
    return " -- detail: `{}/{}.md`".format(NOTES_DIR, item_id)


def has_pointer(line: str, item_id: str) -> bool:
    """Idempotence guard. Keys on the note PATH, not on the pointer's punctuation."""
    return "{}/{}.md".format(NOTES_DIR, item_id) in line


def _protected_spans(text: str):
    """Character ranges a cut may never land inside: HTML comments and code spans."""
    spans = []
    for m in re.finditer(r"<!--.*?-->", text):
        spans.append((m.start(), m.end()))
    for m in re.finditer(r"`[^`]*`", text):
        spans.append((m.start(), m.end()))
    return spans


def _inside(pos: int, spans) -> bool:
    return any(a < pos < b for a, b in spans)


def find_cut(head: str):
    """Where to cut the head line. Returns an offset, or None to REFUSE.

    Primary rule, as the reference does it: the END of the first bold run. Everything up to
    it is title-ish and stays.

    Fallback, added here: items with NO bold run. Measured on this repo's ledgers, 150 of
    674 TODO items and 43 of 127 ROADMAP items have none, so without a fallback 193 items
    could never shrink at all and the ratchet (D4) would demand a cut the tool refuses to
    make. The fallback cut is the earlier of the first ` -- ` and the first sentence
    boundary; neither may land inside an HTML comment or a code span.
    """
    spans = _protected_spans(head)
    m = re.search(r"\*\*[^*]+\*\*", head)
    if m and not _inside(m.end(), spans):
        return m.end()

    body_start = TOP_ITEM_RE.match(head)
    start = body_start.end() if body_start else 0
    candidates = []
    for sep in re.finditer(r" -- ", head):
        if sep.start() > start and not _inside(sep.start(), spans):
            candidates.append(sep.start())
            break
    for sent in re.finditer(r"(?<=[a-z0-9\)\]])[.!?](?=\s)", head):
        if sent.start() > start and not _inside(sent.end(), spans):
            candidates.append(sent.end())
            break
    if not candidates:
        return None
    return min(candidates)


def _keep_matches(text: str):
    """Every must-keep token in `text`, de-nested and ordered by appearance.

    A match wholly contained in another (the bare `gated-on:XXXX` inside its typed
    `<!-- gated-on:... -->` comment) is dropped, so a token is re-appended once.
    """
    raw = []
    for rx in MUST_KEEP_PATTERNS:
        for m in rx.finditer(text):
            raw.append((m.start(), m.end(), m.group(0)))
    raw.sort(key=lambda t: (t[0], -(t[1] - t[0])))
    out = []
    for start, end, txt in raw:
        if any(s <= start and end <= e and (s, e) != (start, end) for s, e, _ in raw):
            continue
        out.append((start, txt))
    return out


def split_head(head: str, item_id: str, block: str = ""):
    """Split an over-long item line into a slim head plus the body to relocate.

    Returns ``None`` -- REFUSE, leave the line alone -- when the split is not defensible.
    `block` is the item's continuation text; it is inspected only for foreign id markers.

    Returns ``(keep, moved, reason)`` on success, or ``(None, None, reason)`` on refusal.
    """
    if has_pointer(head, item_id):
        return None, None, "pointer-exists"

    # The amendment's rule. Any `<!-- id:XXXX -->` in this block other than the item's own
    # means a split here can carry an ADDRESS off the ledger (or, if it sits in the head's
    # tail, drag a second id marker onto the head -- which `md-merge.py` REFUSES outright
    # per id:6059). Both are silent. Refuse and report.
    foreign = {i for i in ID_RE.findall(head + "\n" + block) if i != item_id}
    if foreign:  # FOREIGN-ID-GUARD
        return None, None, "foreign-id:" + ",".join(sorted(foreign))

    cut = find_cut(head)
    if cut is None:
        return None, None, "no-cut-point"
    prefix = head[:cut].rstrip()
    rest = head[cut:]

    # The title must survive as something a reader can identify the item by, once the
    # markers that are not prose are set aside.
    title = prefix
    for _, txt in _keep_matches(prefix):
        title = title.replace(txt, "", 1)
    title = TOP_ITEM_RE.sub("", title).strip()
    if len(title) < 8:
        return None, None, "no-cut-point"

    residue = rest
    for _, txt in _keep_matches(rest):
        residue = residue.replace(txt, "", 1)
    if len(residue.strip()) < MIN_MOVED_CHARS:
        return None, None, "too-little-to-move"

    seen = set()
    tail_parts = []
    for _, txt in _keep_matches(rest):
        if txt in seen:
            continue
        seen.add(txt)
        tail_parts.append(txt)
    tail = " ".join(tail_parts)
    keep = prefix + pointer_for(item_id) + ((" " + tail) if tail else "")
    return keep, rest.strip(), "split"


# --------------------------------------------------------------------------- parsing

class Item:
    __slots__ = ("id", "open", "head", "cont", "index")

    def __init__(self, item_id, is_open, head, index):
        self.id = item_id
        self.open = is_open
        self.head = head
        self.cont = []
        self.index = index


def parse_items(lines):
    """Locate top-level item lines and the continuation span each owns.

    A heading terminates a span and belongs to no item (the same rule the reference
    inherited from its archiver, after an early version swallowed headings into an item and
    corrupted the file).
    """
    items = []
    cur = None
    for i, line in enumerate(lines):
        m = TOP_ITEM_RE.match(line)
        if m:
            idm = ID_RE.search(line)
            cur = Item(idm.group(1) if idm else None, m.group(1) == " ", line, i)
            items.append(cur)
        elif HEADING_RE.match(line):
            cur = None
        elif cur is not None:
            cur.cont.append(line)
    return items


def logical_ledger(path: str) -> str:
    """`## From TODO` / `## From ROADMAP` / `## From REVIEW_ME`.

    Named by LOGICAL ledger, never by the physical path (D3, as amended): a physical name
    goes stale the moment `archive-done.sh` moves the line into `TODO.archive.md`, which is
    the same staleness that role-naming was rejected for.
    """
    return os.path.basename(path).split(".")[0]


def section_heading(path: str) -> str:
    return "## From " + logical_ledger(path)


def note_file_text(item_id: str, body: str, heading: str) -> str:
    return (
        "# id:{}\n\n"
        "Detail relocated out of the ledger by `tools/ledger-shrink.py`. The item line keeps\n"
        "its title, lane tag, `id:` anchor, every gate marker and a pointer back here.\n"
        "**Nothing was deleted** -- the prose below is reproduced verbatim.\n\n"
        "See `{}/BACKLINKS.md` for meetings that cite this id.\n\n"
        "{}\n\n{}\n"
    ).format(item_id, NOTES_DIR, heading, body)


def append_section(existing: str, body: str, heading: str):
    """Append a section to an EXISTING note, preserving every byte already there.

    Never overwrite: a note file may already hold another ledger's half of the same id
    (single-id-two-views). Re-running with the same body is a no-op, not a duplicating
    append.
    """
    if body.strip() and body.strip() in existing:
        return existing, False
    sep = "\n" if existing.endswith("\n") else "\n\n"
    return existing + sep + heading + "\n\n" + body + "\n", True


# --------------------------------------------------------------------------- planning

def plan(lines, min_chars, path):
    """Pure decision: which head lines to slim, and what each becomes. No file I/O."""
    items = parse_items(lines)
    actions = []
    refused = {}
    skipped_no_id = []
    considered = 0
    for it in items:
        if not it.open:
            continue
        if len(it.head) < min_chars:
            continue
        considered += 1
        if not it.id:
            skipped_no_id.append(it.head[:90])
            continue
        keep, moved, reason = split_head(it.head, it.id, "\n".join(it.cont))
        if keep is None:
            refused.setdefault(reason.split(":")[0], []).append(it.id)
            continue
        actions.append({"id": it.id, "line": it.index, "keep": keep, "moved": moved,
                        "before": len(it.head), "after": len(keep)})
    return {"actions": actions, "refused": refused, "skipped_no_id": skipped_no_id,
            "considered": considered, "items": len(items), "path": path}


# --------------------------------------------------------------------------- io

class _Lock:
    """Exclusive flock, released on exit. Ledger lock is taken BEFORE any detail lock.

    One id's detail file is a write target from two or three independently-locked ledgers,
    so per-ledger locking alone races (D5, as amended). The order here is fixed.
    """

    def __init__(self, path):
        self.path = path + ".lock"
        self.fh = None

    def __enter__(self):
        os.makedirs(os.path.dirname(self.path) or ".", exist_ok=True)
        fh = open(self.path, "a+")
        try:
            fcntl.flock(fh.fileno(), fcntl.LOCK_EX)
        except BaseException:
            # Do not leak the descriptor when the lock itself fails: __exit__ is
            # NOT called when __enter__ raises, so this is the only cleanup site.
            fh.close()
            raise
        self.fh = fh
        return self

    def __exit__(self, *_exc):
        fh, self.fh = self.fh, None
        if fh is None:
            return
        try:
            fcntl.flock(fh.fileno(), fcntl.LOCK_UN)
        finally:
            # Release the descriptor even if the unlock call fails, so a partial
            # failure cannot wedge later writers behind a still-open handle.
            fh.close()


def apply_plan(root, path, lines, planned):
    heading = section_heading(path)
    notes_dir = os.path.join(root, NOTES_DIR)
    created = appended = 0
    out = list(lines)
    with _Lock(os.path.join(root, path)):
        os.makedirs(notes_dir, exist_ok=True)
        for a in planned["actions"]:
            note_path = os.path.join(notes_dir, a["id"] + ".md")
            with _Lock(note_path):
                if os.path.exists(note_path):
                    with open(note_path, encoding="utf-8") as fh:
                        existing = fh.read()
                    text, changed = append_section(existing, a["moved"], heading)
                    if changed:
                        _atomic_write(note_path, text)
                        appended += 1
                else:
                    _atomic_write(note_path, note_file_text(a["id"], a["moved"], heading))
                    created += 1
            out[a["line"]] = a["keep"]
        _atomic_write(os.path.join(root, path), "\n".join(out))
    return created, appended


def _atomic_write(path, text):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(text)
    os.replace(tmp, path)


REFUSAL_LABELS = {
    "pointer-exists": "already has a pointer (idempotent)",
    "no-cut-point": "no defensible cut point",
    "too-little-to-move": "under {} chars would move".format(MIN_MOVED_CHARS),
    "foreign-id": "block carries ANOTHER item's id marker (would orphan it)",
}


def main(argv=None):
    ap = argparse.ArgumentParser(prog="ledger-shrink.py", add_help=True,
                                 description="Slim over-long ledger head lines into "
                                             "docs/ledger-notes/<id>.md.")
    ap.add_argument("--file", default="TODO.md", help="ledger to process (default TODO.md)")
    ap.add_argument("--min-chars", type=int, default=DEFAULT_MIN_CHARS,
                    help="head-line length at or above which an item is a candidate "
                         "(default {})".format(DEFAULT_MIN_CHARS))
    ap.add_argument("--root", default=None, help="repo root (default: the file's repo)")
    ap.add_argument("--dry-run", action="store_true", help="report only (the default)")
    ap.add_argument("--apply", action="store_true", help="actually move the prose")
    args = ap.parse_args(argv)

    if args.apply and args.dry_run:
        sys.stderr.write("ledger-shrink: --apply and --dry-run are mutually exclusive\n")
        return 2
    if args.min_chars <= 0:
        sys.stderr.write("ledger-shrink: --min-chars must be positive\n")
        return 2

    root = os.path.abspath(args.root) if args.root else os.getcwd()
    rel = args.file
    target = os.path.abspath(os.path.join(root, rel))
    if not target.startswith(root + os.sep):
        sys.stderr.write("ledger-shrink: REFUSING -- --file must stay inside the root\n")
        return 2
    if not os.path.exists(target):
        sys.stderr.write("ledger-shrink: no such file: {}\n".format(rel))
        return 2
    rel = os.path.relpath(target, root)

    with open(target, encoding="utf-8") as fh:
        text = fh.read()
    lines = text.split("\n")

    planned = plan(lines, args.min_chars, rel)
    before = len(text)
    delta = sum(a["before"] - a["after"] for a in planned["actions"])

    print("ledger-shrink: {} min-chars {}".format(rel, args.min_chars))
    print("  item lines            : {}".format(planned["items"]))
    print("  over-budget candidates: {}".format(planned["considered"]))
    print("  items to shrink       : {}".format(len(planned["actions"])))
    print("  ledger chars          : {} -> {} (-{})".format(before, before - delta, delta))
    for reason, ids in sorted(planned["refused"].items()):
        print("  REFUSED {:<50}: {}".format(REFUSAL_LABELS.get(reason, reason), len(ids)))
        if reason == "foreign-id":
            print("    ids: {}".format(" ".join(sorted(ids))))
    if planned["skipped_no_id"]:
        print("  SKIPPED (no id, never guessed): {}".format(len(planned["skipped_no_id"])))

    if not args.apply:
        print("  (dry run -- nothing written)")
        return 0

    created, appended = apply_plan(root, rel, lines, planned)
    print("  note files: {} created, {} appended to (0 overwritten, by construction)"
          .format(created, appended))
    return 0


if __name__ == "__main__":
    sys.exit(main())
