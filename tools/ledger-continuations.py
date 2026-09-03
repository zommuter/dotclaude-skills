#!/usr/bin/env python3
"""ledger-continuations.py -- relocate a ledger's INDENTED CONTINUATION LINES into
`docs/ledger-notes/<id>.md`, leaving the item's head line untouched but for a pointer.

WHY A SECOND TOOL. `tools/ledger-shrink.py` splits HEAD LINES: `plan()` skips any item
whose `len(it.head) < min_chars`, so an item with a 191-char head and a 6,825-char
continuation block is invisible to it. That is the whole of `id:b048`'s finding -- ROADMAP.md
carries 44,754 head-line bytes against 178,299 continuation bytes, so a head-keyed shrinker
recovers 216 chars (0.09%) from it. Under the `id:b048` ledger LINE GRAMMAR a continuation
line is not merely large, it is INVALID: the grammar admits a blank line, a heading, or an
item line, and nothing else. This tool moves them. It is `id:40c0`.

Everything shared with the head-line shrinker is IMPORTED from it, never retyped:
`pointer_for`, `has_pointer`, `section_heading`, `note_file_text`, `_atomic_write`, `_Lock`.

WHAT A BLOCK IS. The head line, then the maximal run of immediately-following NON-BLANK
INDENTED lines. A blank line, a heading, a top-level prose line or the next item all
terminate it. This is deliberately NARROWER than `ledger_shrink.parse_items`, whose span
runs to the next item or heading and therefore swallows top-level blockquote preambles that
belong to a SECTION, not to an item. Those are `grammar-line` findings with no owning id and
this tool refuses them.

REFUSALS (a refusal is always safe; a wrong cut is not):
  no-id        the head line carries no anchored `<!-- id:XXXX -->` of its own.
  foreign-id   the block carries ANOTHER item's id marker. `ledger-shrink.py` refuses this
               for the same reason: loderite's sweep silently dropped four ids (89f9, a5b6,
               ba07, ed26) whose body survived in a note while the ADDRESS did not.
  unowned      an indented line that follows no item at all (e.g. the continuation lines of
               a multi-line top-level HTML comment).
  cited-body   a LIVE consumer greps that item's body OUT OF the ledger file itself, so
               relocating it turns the consumer red. Listed in REFUSE_IDS with its reason
               and found the only way it can be found: by running the suite. This is the
               id:2ee1 / id:1608 class -- "every consumer that reads an item's BODY breaks
               when the body moves" -- and the honest response is to refuse the item, not
               to weaken the consumer.

FLEET-RULE EDITS, DECLARED. Per the CLAUDE.md "Detail notes are EDITABLE, and an edit is
DECLARED in the note's header" rule, banned dashes in the relocated prose are FIXED in the
note and the note's HEADER says so. The edit is confined to text OUTSIDE backtick code
spans: a backticked span in this corpus quotes a lane tag, a heading, a path:line range or
live tool output, and rewriting a quotation makes it false. En dashes are converted
everywhere, backticks included, because every one of them was inspected and is a numeric or
identifier RANGE, not a quotation of a character.

LANE VOCABULARY IS NOT TOUCHED. A lane tag occurrence is DECLARATIVE (it IS an item's lane,
routing dispatch) or REFERENTIAL (prose MENTIONING the vocabulary -- a narrated retag, a
mapping table, a quotation). Only a declarative tag may be rewritten. Every lane tag inside
a continuation block is prose, inside backticks, so none is converted; the note declares it.

Usage:
  tools/ledger-continuations.py --file ROADMAP.md --dry-run
  tools/ledger-continuations.py --file ROADMAP.md --apply

Dry-run is the DEFAULT. Nothing is written without an explicit `--apply`.
"""

from __future__ import annotations

import argparse
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from importlib import import_module

_ls = import_module("ledger-shrink")

NOTES_DIR = _ls.NOTES_DIR
pointer_for = _ls.pointer_for
has_pointer = _ls.has_pointer
section_heading = _ls.section_heading
note_file_text = _ls.note_file_text
_atomic_write = _ls._atomic_write
_Lock = _ls._Lock

TOP_ITEM_RE = _ls.TOP_ITEM_RE
ID_RE = _ls.ID_RE

EM = "—"
EN = "–"
BACKTICK_RUN_RE = re.compile(r"`+")
SECTION_RE = re.compile(r"^## ", re.M)


def code_spans(line):
    """CommonMark code-span extents on ONE line: a run of N backticks is closed by the
    next run of EXACTLY N.

    A naive `` `[^`]*` `` pairs across a closing backtick and the next opening one whenever
    a line's backtick count is odd, which mis-reads ordinary prose as quoted code. Three
    lines in this corpus are odd (they carry ```` ``` ```` fences and `` `` `` spans), and
    on the first run that bug reported 24 protected em dashes where only 14 exist.
    """
    runs = [(m.start(), m.end()) for m in BACKTICK_RUN_RE.finditer(line)]
    spans = []
    i = 0
    while i < len(runs):
        s, e = runs[i]
        width = e - s
        j = i + 1
        while j < len(runs) and (runs[j][1] - runs[j][0]) != width:
            j += 1
        if j < len(runs):
            spans.append((s, runs[j][1]))
            i = j + 1
        else:
            i += 1
    return spans


# ------------------------------------------------------------------ dash normalisation

def normalise_dashes(text):
    """Return (fixed_text, em_fixed, em_left_in_code, en_fixed).

    Em dashes are replaced with `--` only OUTSIDE backtick code spans. En dashes are
    replaced with `-` everywhere. Counts are reported so the note header can declare them.
    """
    em_left = 0
    em_fixed = 0
    fixed_lines = []
    for line in text.split("\n"):
        spans = code_spans(line)
        out = []
        pos = 0
        for s, e in spans:
            chunk = line[pos:s]
            em_fixed += chunk.count(EM)
            out.append(chunk.replace(EM, "--"))
            em_left += line[s:e].count(EM)
            out.append(line[s:e])
            pos = e
        chunk = line[pos:]
        em_fixed += chunk.count(EM)
        out.append(chunk.replace(EM, "--"))
        fixed_lines.append("".join(out))
    fixed = "\n".join(fixed_lines)
    en_fixed = fixed.count(EN)
    fixed = fixed.replace(EN, "-")
    return fixed, em_fixed, em_left, en_fixed


# Items whose BODY a live consumer reads out of the ledger file directly. Each entry is a
# measured failure, not a precaution: the id was relocated, the suite went red, and the
# block was put back. Never add one speculatively, and never remove one without re-running
# the named consumer.
# REFUSE_IDS -- items whose BODY is read by a live consumer, so relocating the body breaks it.
# The id:2ee1 / id:1608 class. An entry here is a statement about a CONSUMER, so it becomes
# STALE the moment that consumer is re-anchored: re-verify before trusting one.
#
# id:6b35 was listed here and the entry is now LIFTED (2026-09-03). Both of its consumers were
# re-anchored to the LEDGER + NOTES UNION, which is what each of them asked for in its own
# words: `roadmap-lint.sh`'s SCOPE-TABLE-DRIFT parser now reads docs/ledger-notes/*.md
# alongside the ledger (and its empty-result branch FAILS LOUDLY instead of the silent
# `return 0` that made a vanished table indistinguishable from a repo that never had one --
# the id:d35a class), and `tests/test_roadmap_scope_table_consistency_c480.sh` greps the same
# union. Refusing forever would have parked ~6.7 KB in the ledger permanently to avoid a
# one-line change to each consumer.
REFUSE_IDS = {}

LANE_MENTION_RE = re.compile(r"\[(?:HARD|INPUT)\s*[-" + EN + EM + r"]\s*[^]\n]{1,24}\]")


def lane_mentions(text):
    return [m.group(0) for m in LANE_MENTION_RE.finditer(text)]


# ------------------------------------------------------------------------- block scan

class Block:
    def __init__(self, index, item_id, head, cont):
        self.index = index
        self.id = item_id
        self.head = head
        self.cont = cont


def scan(lines):
    """Return (blocks, refusals). `lines` is the file split on newlines."""
    blocks = []
    refused = []
    i = 0
    n = len(lines)
    cur_owner = None
    while i < n:
        line = lines[i]
        if TOP_ITEM_RE.match(line):
            cur_owner = i
            j = i + 1
            cont = []
            while j < n and lines[j].strip() and re.match(r"^[ \t]", lines[j]):
                cont.append(lines[j])
                j += 1
            if cont:
                idm = ID_RE.search(line)
                if not idm:
                    refused.append(("no-id", i + 1, line[:90]))
                else:
                    body = "\n".join(cont)
                    foreign = sorted(set(ID_RE.findall(body)) - {idm.group(1)})
                    if foreign:
                        refused.append(("foreign-id", i + 1,
                                        "block carries id(s) " + ",".join(foreign)))
                    elif idm.group(1) in REFUSE_IDS:
                        refused.append(("cited-body", i + 1,
                                        "id:{} -- {}".format(idm.group(1),
                                                             REFUSE_IDS[idm.group(1)])))
                    else:
                        blocks.append(Block(i, idm.group(1), line, cont))
            i = j
            continue
        if line.strip() and re.match(r"^[ \t]", line):
            refused.append(("unowned", i + 1, line.strip()[:80]))
        i += 1
    return blocks, refused


# ------------------------------------------------------------------------- note edits

DECLARATION_MARK = "**EDITED ON RELOCATION"


def build_declaration(item_id, em_fixed, em_left, en_fixed, lanes):
    """The header paragraph that keeps the note's verbatim claim honest."""
    if not (em_fixed or en_fixed or em_left or lanes):
        return ""
    parts = []
    parts.append(
        "{} (2026-09-02, `id:40c0`) -- the verbatim claim above is amended\n"
        "for the PROSE THIS PASS APPENDED to `## From ROADMAP`, and for nothing else. Any\n"
        "prose already in that section arrived by an earlier pass and is untouched here.**"
        .format(DECLARATION_MARK)
    )
    fixes = []
    if em_fixed:
        fixes.append("{} punctuation em dash{} became `--`".format(
            em_fixed, "" if em_fixed == 1 else "es"))
    if en_fixed:
        fixes.append("{} range en dash{} became `-`".format(
            en_fixed, "" if en_fixed == 1 else "es"))
    if fixes:
        parts.append(
            " Fleet-rule violations found in the relocated\nprose were FIXED here rather than parked: "
            + "; ".join(fixes) + ".")
    else:
        parts.append(
            " NOTHING in the relocated prose was rewritten -- it carried no\n"
            "banned dash outside a quotation. The amendment is only about what is DECLARED\n"
            "below as deliberately left.")
    parts.append(
        " Nothing else changed: no word, figure, marker or line break was\n"
        "altered, and the appended text is otherwise the ROADMAP.md block verbatim, indentation\n"
        "included.\n"
    )
    left = []
    if em_left:
        left.append(
            "{} em dash{} inside BACKTICK code spans {} NOT converted. A backticked span here\n"
            "quotes something whose spelling is the point -- a lane tag, a heading that still\n"
            "carries that character, a `path:line-range`, or live tool output -- so rewriting it\n"
            "would make the quotation false.".format(
                em_left, "" if em_left == 1 else "es",
                "is" if em_left == 1 else "are"))
    if lanes:
        uniq = sorted(set(lanes))
        left.append(
            "The lane tag{} {} {} NOT converted, neither delimiter nor name. Every lane tag in\n"
            "this section is REFERENTIAL -- prose MENTIONING the vocabulary, inside backticks --\n"
            "not the DECLARATIVE lane of any item, which stays on the ledger line. Rewriting a\n"
            "referential tag corrupts a record of what a past run classified or of which\n"
            "spelling a migration is about.{}".format(
                "" if len(uniq) == 1 else "s",
                ", ".join("`{}`".format(x) for x in uniq),
                "is" if len(uniq) == 1 else "are",
                (" `[HARD - hands]` is never auto-converted in any case:\n"
                 "`relay/scripts/lane-convert.sh` fragments it across four destinations by\n"
                 "per-item human judgment." if any("hands" in x for x in uniq) else "")))
    text = "".join(parts)
    if left:
        text += "\nDELIBERATELY LEFT, declared rather than silently kept. " + "\n".join(left) + "\n"
    return text


def insert_declaration(note_text, declaration):
    """Put the declaration in the note's HEADER -- before the first `## ` section."""
    if not declaration:
        return note_text
    m = SECTION_RE.search(note_text)
    if not m:
        return note_text.rstrip("\n") + "\n\n" + declaration
    return note_text[:m.start()] + declaration + "\n" + note_text[m.start():]


def append_into_section(note_text, heading, body):
    """Append `body` at the END of an existing `heading` section, or add the section.

    Never duplicates the heading: 18 of this repo's ROADMAP notes already carry a
    `## From ROADMAP` half from an earlier head-line split, and a second heading of the
    same name splits one item's detail into two places a reader must find separately.
    """
    if body.strip() and body.strip() in note_text:
        return note_text, False
    idx = note_text.find(heading + "\n")
    if idx < 0:
        sep = "\n" if note_text.endswith("\n") else "\n\n"
        return note_text + sep + heading + "\n\n" + body + "\n", True
    nxt = SECTION_RE.search(note_text, idx + len(heading))
    cut = nxt.start() if nxt else len(note_text)
    before = note_text[:cut].rstrip("\n")
    return before + "\n\n" + body + "\n\n" + note_text[cut:], True


def plant_pointer(head, item_id):
    """Insert the `-- detail:` pointer before the trailing marker run. Idempotent."""
    if has_pointer(head, item_id):
        return head, False
    m = re.search(r"\s*<!--", head)
    ptr = pointer_for(item_id)
    if not m:
        return head.rstrip() + ptr, True
    return head[:m.start()] + ptr + head[m.start():], True


# ------------------------------------------------------------------------------ main

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--file", required=True)
    ap.add_argument("--root", default=".")
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    root = os.path.abspath(args.root)
    path = os.path.join(root, args.file)
    raw = open(path, encoding="utf-8").read()
    lines = raw.split("\n")

    blocks, refused = scan(lines)
    heading = section_heading(args.file)

    # ---- ORPHAN PRECONDITION: every id addressable before must be addressable after.
    ids_before = set(ID_RE.findall(raw))
    print("== {} ==".format(args.file))
    print("items with a continuation block : {}".format(len(blocks)))
    print("continuation lines to relocate  : {}".format(sum(len(b.cont) for b in blocks)))
    print("id markers in the ledger before : {}".format(len(ids_before)))
    for kind in ("no-id", "foreign-id", "cited-body", "unowned"):
        hits = [r for r in refused if r[0] == kind]
        print("REFUSED {:<11} : {}".format(kind, len(hits)))
        for _, ln, why in hits:
            print("    line {}: {}".format(ln, why))

    item_bytes_before = sum(len(l) for l in lines if TOP_ITEM_RE.match(l) or
                            (l.strip() and re.match(r"^[ \t]", l)))

    plans = []
    for b in blocks:
        body = "\n".join(b.cont)
        fixed, em_fixed, em_left, en_fixed = normalise_dashes(body)
        lanes = lane_mentions(body)
        # HARD ASSERTION, not a hope: a lane tag is a routing surface, and the dash pass
        # must not have touched one. If the multiset of lane tags differs before/after,
        # a delimiter was migrated on a REFERENTIAL tag -- which corrupts a record of what
        # a past run classified, or of which spelling a migration is about.
        if sorted(lanes) != sorted(lane_mentions(fixed)):
            print("REFUSING: dash pass altered a lane tag in id:{} ({} -> {})".format(
                b.id, sorted(lanes), sorted(lane_mentions(fixed))), file=sys.stderr)
            return 3
        decl = build_declaration(b.id, em_fixed, em_left, en_fixed, lanes)
        keep, planted = plant_pointer(b.head, b.id)
        plans.append({"b": b, "body": fixed, "decl": decl, "keep": keep,
                      "planted": planted, "em": em_fixed, "em_left": em_left,
                      "en": en_fixed, "lanes": lanes})

    print("pointers to plant               : {}".format(sum(1 for p in plans if p["planted"])))
    print("em dashes fixed / left in code  : {} / {}".format(
        sum(p["em"] for p in plans), sum(p["em_left"] for p in plans)))
    print("en dashes fixed                 : {}".format(sum(p["en"] for p in plans)))
    print("lane tags left (all referential): {}".format(sum(len(p["lanes"]) for p in plans)))

    if not args.apply:
        print("\nDRY RUN -- nothing written. Pass --apply to perform the move.")
        return 0

    drop = set()
    out = list(lines)
    with _Lock(path):
        os.makedirs(os.path.join(root, NOTES_DIR), exist_ok=True)
        for p in plans:
            b = p["b"]
            note_path = os.path.join(root, NOTES_DIR, b.id + ".md")
            with _Lock(note_path):
                if os.path.exists(note_path):
                    existing = open(note_path, encoding="utf-8").read()
                else:
                    existing = note_file_text(b.id, "", heading).replace(
                        "`tools/ledger-shrink.py`", "`tools/ledger-continuations.py`")
                    # note_file_text emits an empty section; drop it, append_into_section
                    # re-adds it with the real body.
                    existing = existing[:existing.find(heading)].rstrip("\n") + "\n"
                text, changed = append_into_section(existing, heading, p["body"])
                if changed:
                    text = insert_declaration(text, p["decl"])
                _atomic_write(note_path, text)
            out[b.index] = p["keep"]
            for k in range(len(b.cont)):
                drop.add(b.index + 1 + k)
        new_lines = [l for i, l in enumerate(out) if i not in drop]
        _atomic_write(path, "\n".join(new_lines))

    # ---- ORPHAN ASSERTION, run against what is actually on disk now.
    after_raw = open(path, encoding="utf-8").read()
    ids_after = set(ID_RE.findall(after_raw))
    notes_ids = set()
    for fn in os.listdir(os.path.join(root, NOTES_DIR)):
        if fn.endswith(".md"):
            notes_ids.add(fn[:-3])
            notes_ids |= set(ID_RE.findall(
                open(os.path.join(root, NOTES_DIR, fn), encoding="utf-8").read()))
    lost = ids_before - ids_after - notes_ids
    print("\nid markers in the ledger after  : {}".format(len(ids_after)))
    print("ids reachable in notes           : {}".format(len(ids_before & notes_ids)))
    if lost:
        print("ORPHAN CHECK FAILED -- lost ids: {}".format(sorted(lost)), file=sys.stderr)
        return 2
    print("ORPHAN CHECK PASSED -- all {} pre-existing ids still addressable".format(
        len(ids_before)))
    item_bytes_after = sum(len(l) for l in new_lines if TOP_ITEM_RE.match(l) or
                           (l.strip() and re.match(r"^[ \t]", l)))
    print("item bytes {} -> {} ({:+})".format(
        item_bytes_before, item_bytes_after, item_bytes_after - item_bytes_before))
    return 0


if __name__ == "__main__":
    sys.exit(main())
