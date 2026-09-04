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
#
# 40 -> 25, owner-approved 2026-09-02, and 25 is where the DISTRIBUTION ends rather than a
# taste call. MEASURED on the post-wave-3 ledgers by re-planning at each threshold: 40
# yields 0 further items, 25 yields 11, and 20 and 10 also yield 11. Nothing sits between
# 10 and 25, so lowering past 25 buys literally nothing and only invites relocating
# fragments too small to be worth an indirection.
#
# Worth stating plainly because an earlier claim of mine overstated this knob: the residue
# distribution on the remaining prose-carrying items has median 125 chars, and only 28% sit
# under 40. This threshold was never the ceiling. Of 283 items still carrying prose, 190
# are refused for want of a defensible CUT POINT and only 64 for residue size -- so the
# titling rule, not this number, is what bounds the shrink from here.
MIN_MOVED_CHARS = 25

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
#
# id:4983 -- the dash-lane alternation used to accept ANY word after the dash
# (`[A-Za-z0-9 _./-]+`), so it recognised undeclared tokens like `[HARD - kitchen]` that
# `relay/scripts/classify-repo.sh`'s hand-enumerated `LANE_TAGS`/`HUMAN_GATES` tuple never
# would -- a silent divergence `tests/test_lane_grammar_ssot.sh` pins. The sub-lane names
# below are exactly `relay/references/hard-lanes.md`'s declared set (mirrored from
# classify-repo.sh's own HUMAN_GATES tuple, "## The three lanes" + the INPUT table): pool /
# meeting / hands / decision gate under [HARD], meeting / decision / access / author under
# [INPUT]. `[INTENSIVE]` is deliberately excluded -- the SSOT states it is an orthogonal
# resource-axis modifier, never a lane, and a consumer that anchors on it is a defect.
_HARD_SUBNAMES = ("pool", "meeting", "hands", "decision gate")
_INPUT_SUBNAMES = ("meeting", "decision", "access", "author")


def _dash_lane_re(cls, subnames):
    return re.compile(
        r"\[" + cls + r"\s*" + _DASH + r"\s*(?:"
        + "|".join(re.escape(n) for n in subnames)
        + r")\]"
    )


_LANE_PATTERNS = [
    re.compile(r"\[(?:ROUTINE|HARD|MECHANICAL)\]"),
    _dash_lane_re("HARD", _HARD_SUBNAMES),
    _dash_lane_re("INPUT", _INPUT_SUBNAMES),
]

# The retired VENUE-KEYED spellings the fleet is migrating away from (lane-convert.sh's
# mapping, meeting 2026-07-02-1924 D2). Only the `[HARD <dash> venue]` family is retired --
# `[INPUT <dash> venue]` is the NEW vocabulary and is untouched by the ratchet.
_RETIRED_LANE_RE = re.compile(r"\[HARD\s*" + _DASH + r"\s*[A-Za-z0-9 _./-]+\]")

# The prose separator find_cut's fallback cuts on. One or two dashes, in any of the three
# spellings the fleet is mid-migration between, spaced on both sides. See find_cut.
_SEP_RE = re.compile(r" " + _DASH + r"{1,2} ")

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
    # CASE-INSENSITIVE, and the punctuated forms too (loderite finding, 2026-09-02).
    # `classify-repo.sh:359` and `gather-repo-state.sh:602-604` exclude an item from
    # dispatch on unanchored `blocked on` / `blocked (` / `blocked:` / `blocked -` without
    # regard to case, while this keep-list matched two fixed spellings. Two loderite items
    # are gated by a lowercase form ALONE, so relocating it makes them executor-ready --
    # the failure direction is OVER-DISPATCH, not a missed lint.
    re.compile(r"(?i)blocked(?:\s+on\b|\s*[(:-])"),
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
    # The DETAIL POINTER itself. Needed once re-splitting is allowed (below): on a second
    # pass the pointer sits in the moved region, and without this it would be relocated
    # INTO the note it points at -- severing the line from its own body.
    re.compile(r"-{1,2}\s*detail:\s*`?[A-Za-z0-9_./-]*/[0-9a-f]{4}\.md`?"),
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


def _first_lane(text: str):
    """(offset, token) of the FIRST lane tag on the line, or None.

    Mirrors classify-repo.sh:286 `min([(ln.find(t), t) for t in LANE_TAGS ...])` -- the
    id:4da4 PRIMARY-LANE anchoring rule. Deliberately no backtick handling: classify-repo
    does not strip backticks either (its id:4da4 note says first-occurrence is what makes it
    robust *where a backtick-strip is not*), so masking here would make this tool disagree
    with the detector it exists to keep honest.
    """
    hits = []
    for rx in _LANE_PATTERNS:
        m = rx.search(text)
        if m:
            hits.append((m.start(), m.group(0)))
    return min(hits) if hits else None


def _protected_spans(text: str):
    """Character ranges a cut may never land inside: HTML comments, code spans, brackets.

    BRACKET RUNS were added with the dash-spelling fallback below, and they are what makes
    that fallback safe rather than merely wider. A lane tag CONTAINS the separator the
    fallback cuts on -- `[HARD <dash> decision gate]`, `[INPUT <dash> meeting]` -- so an
    unbackticked lane tag mentioned in prose offers the dash rule a cut point INSIDE itself.
    MEASURED on `id:2884` here: its body says ``lane tags ... -> valid [HARD <dash> <lane>]``
    with no backticks, and the first spaced dash on that line sits at offset 163, between
    `[HARD` and `<lane>]`. Cutting there leaves an unbalanced `[HARD` on the head line and
    carries the rest of the tag into the note -- a mangled control surface, which is worse
    than the long line it was fixing. No cut ever wants to land inside a bracket group
    anyway: brackets here are lane tags, `[INBOUND ...]` provenance and `[HIGH PRIORITY]`
    flags, none of which is a title boundary.
    """
    spans = []
    for m in re.finditer(r"<!--.*?-->", text):
        spans.append((m.start(), m.end()))
    for m in re.finditer(r"`[^`]*`", text):
        spans.append((m.start(), m.end()))
    for m in re.finditer(r"\[[^\[\]]*\]", text):
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
    make. The fallback cut is the earlier of the first spaced dash separator (`_SEP_RE`, any
    of the three dash spellings) and the first sentence boundary; neither may land inside an
    HTML comment, a code span or a bracket group.
    """
    spans = _protected_spans(head)

    # THE TITLE CANNOT FOLLOW THE ANCHOR (id:931c, found 2026-09-03).
    #
    # The bold-run rule assumes the bold run IS the title, near the START of the line. That
    # is false for the `grammar-item-after-id` shape -- `title <!-- id:XXXX --> **annotation**`
    # -- where the item's real title is unbolded text BEFORE the marker and the only bold run
    # is a trailing annotation appended after it. Measured on ROADMAP.md:58 (id:931c, 994
    # chars): the marker is at offset 102, the first bold run starts at 119, so the cut landed
    # at 994 and the tool declared "too-little-to-move" with 0 residue -- while treating an
    # 875-char annotation as title. The line then sits over budget forever, and nothing
    # reports why.
    #
    # An item's own id marker is its ANCHOR, so no cut may land after it: whatever follows is
    # annotation, which is exactly what should move. Everything below is clamped to it.
    anchor = None
    _am = re.search(r"<!--\s*id:[0-9a-f]{4}\s*-->", head)
    if _am and not _inside(_am.start(), spans):
        anchor = _am.start()

    def _ok(off):
        return anchor is None or off <= anchor

    m = re.search(r"\*\*[^*]+\*\*", head)
    if m and not _inside(m.end(), spans) and _ok(m.end()):
        return m.end()

    body_start = TOP_ITEM_RE.match(head)
    start = body_start.end() if body_start else 0
    candidates = []
    # THE SEPARATOR IS SPELLED THREE WAYS, and reading only one of them is the same defect
    # this module already fixed for its keep-patterns (`_DASH`, above): the fleet is
    # mid-migration off the em/en dash, the detectors match BOTH spellings when READING, and
    # this fallback matched ASCII alone. MEASURED here 2026-09-03 on the 63 open TODO.md
    # items that carry no detail pointer: 42 offered find_cut NO candidate at all -- no bold
    # run, no ASCII ` -- `, and no sentence boundary, because their periods sit inside
    # filenames (`SKILL.md documents`, `archive-done.sh`). 39 of those 42 have a spaced em
    # dash exactly where their title ends. They are historical `[INBOUND routed:...]` prose
    # written before the ban, so the ASCII-only rule refused precisely the population it was
    # most needed for. Nothing is REWRITTEN by this: the dash itself travels with the body
    # into the note, verbatim, and the head keeps only the text left of it.
    for sep in re.finditer(_SEP_RE, head):
        if sep.start() > start and not _inside(sep.start(), spans) and _ok(sep.start()):
            candidates.append(sep.start())
            break
    for sent in re.finditer(r"(?<=[a-z0-9\)\]])[.!?](?=\s)", head):
        if sent.start() > start and not _inside(sent.end(), spans) and _ok(sent.end()):
            candidates.append(sent.end())
            break
    if candidates:
        return min(candidates)

    # LAST RESORT for the after-id shape: cut AT the anchor. The prefix is then the real
    # title, and the marker itself is a MUST_KEEP token, so it is lifted out of the moved
    # residue and re-emitted on the head line -- the id never leaves the ledger. Only taken
    # when a genuine title precedes the anchor; the caller's own `len(title) < 8` and
    # MIN_MOVED_CHARS checks still apply and still refuse if either half is too thin.
    if anchor is not None and anchor > start:
        return anchor
    return None


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
    # RE-SPLIT IS ALLOWED (id:6546). Wave 1 refused any line that already carried a
    # pointer, so an item was split exactly ONCE, ever -- and whatever prose sat left of
    # that first cut stayed forever. MEASURED after wave 1: 140 of this repo's 460
    # prose-carrying lines are in exactly that state, and loderite measured 57 of its 86
    # over-long ROADMAP items the same way (its `hasPointer` guard returns null on a second
    # pass, which is why `--min-chars 1000` there extracts ZERO). apply_plan() has appended
    # to existing notes since wave 1 (11 appends, 0 overwrites), so the destination already
    # handles this; only the guard stood in the way. The pointer is in MUST_KEEP_PATTERNS,
    # so a second cut carries it back onto the line rather than into the note.
    already_pointered = has_pointer(head, item_id)

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
        # A REFUSAL COUNTER THAT GIVES THE WRONG REASON IS THE id:4347 SHAPE (id:a580):
        # loud detection, silently wrong resolution. `too-little-to-move` reads as "there
        # was a body and it was too small to bother with", and this module's own docstring
        # already calls that message "true and completely misleading" in a different
        # context. For `43dc`, `8254` and `dda3` here it is exactly that: their residue is
        # not SMALL, it is EMPTY of prose. The first bold run runs all the way to the id
        # anchor -- boldend 1406 against anchor 1407 on `43dc`, 891/892 on `8254`,
        # 911/933 on `dda3` with only a `routed:` marker in between -- so find_cut's PRIMARY
        # rule returns at the end of that run and the dash/sentence FALLBACKS are never
        # reached. Everything right of the cut is markers.
        #
        # The remedy differs from the one `too-little-to-move` implies, which is why the
        # reason has to differ: lowering MIN_MOVED_CHARS buys nothing at all here (the
        # residue is 0), and the actual fix is a cut point INSIDE the bold run -- i.e. the
        # item's whole title is bolded and needs a human or a titling rule, not a knob.
        _bold = re.search(r"\*\*[^*]+\*\*", head)
        if _bold is not None and _bold.end() == cut and not residue.strip():
            return None, None, "bold-run-to-anchor"
        return None, None, "too-little-to-move"

    # LANE HANDLING IS INVARIANCE, NOT INFERENCE. Two wrong answers preceded this one, so
    # the question is stated precisely: not "what is this item's lane" (unknowable from a
    # line) but "what does classify-repo COMPUTE as its lane, and does the shrink change
    # it?" That is mechanical. id:4da4 defines it -- the FIRST recognised lane token on the
    # line, wherever it sits (classify-repo.sh:279, `min(_found)`).
    #
    # So the rule falls out with no judgement anywhere:
    #   * a token that is NOT first sets nothing and no detector reads it -> it is prose,
    #     and it travels with the body like all other prose. Keeping it on the line drags
    #     prose back onto a control surface (and made the shrunk line an ADDED line with an
    #     old-vocabulary tag, which the pre-commit ratchet correctly BLOCKED).
    #   * a token that IS first already IS the computed lane. Preserving it means keeping it
    #     FIRST, which after the cut means the leading run. That is not inventing a lane, it
    #     is stopping the shrink from REMOVING one.
    #
    # Round 1 promoted everything and moved three OPEN loderite items into pool-carrying
    # lanes. Round 2 promoted "when unambiguous" and invented lanes here. Both were guesses;
    # this is not. The invariant is asserted below and a violation REFUSES the split.
    #
    # NOTE what this deliberately does NOT do: it does not mask backticks. All three
    # affected items here carry a BACKTICKED or foreign-id prose mention as their first
    # token, so they already have a de-facto lane today that they should not have. That is
    # a pre-existing classify-repo defect. A formatting migration must neither silently fix
    # it nor silently cement it -- so the lane is preserved exactly as computed today, and
    # the item is REPORTED for a human to place deliberately.
    seen = set()
    tail_parts = []
    lane_parts = []
    primary = _first_lane(head)
    primary_in_prefix = primary is not None and primary[0] < len(prefix)
    for _, txt in _keep_matches(rest):
        if txt in seen:
            continue
        seen.add(txt)
        if any(rx.fullmatch(txt) for rx in _LANE_PATTERNS):
            if primary_in_prefix or primary is None or txt != primary[1]:
                continue                      # prose by id:4da4 -- travels with the body
            lane_parts.append(txt)            # this token IS the computed primary lane
        else:
            tail_parts.append(txt)

    head_prefix = prefix
    if lane_parts:
        m_top = TOP_ITEM_RE.match(prefix)
        at = m_top.end() if m_top else 0
        head_prefix = prefix[:at] + " " + lane_parts[0] + prefix[at:]
    lane_in_body = sorted(set(lane_parts))

    tail = " ".join(tail_parts)
    # Do not plant a SECOND pointer on a re-split line: the existing one is carried back by
    # the keep-matches above, and two pointers to the same note is a grammar violation the
    # shape check would report.
    ptr = "" if already_pointered else pointer_for(item_id)
    keep = head_prefix + ptr + ((" " + tail) if tail else "")
    # THE INVARIANT, asserted rather than trusted: the lane classify-repo computes for this
    # line must be identical before and after. A violation is a REFUSAL, never a warning --
    # a shrink that silently re-lanes an item is the over-dispatch failure this whole rule
    # exists to prevent, and refusing costs only a line left long.
    _pb, _pa = _first_lane(head), _first_lane(keep)
    if (_pb[1] if _pb else None) != (_pa[1] if _pa else None):
        return None, None, "lane-would-change"

    # THE HEAD MUST ACTUALLY SHRINK, and by the same margin the residue check demands.
    # MIN_MOVED_CHARS was measured on the wrong side of the trade: it asks how much prose
    # LEAVES, and says nothing about what the split COSTS. The pointer is ~45 chars, so a
    # 46-char move is a wash and a 40-char move makes the line LONGER. Both were produced
    # against the live TODO.md on 2026-09-03 -- `id:625a` went 349 -> 355 and `id:cb1c`
    # 356 -> 356, each buying an indirection for no byte win and no title win. A split that
    # does not shrink the head is pure cost: the reader loses the prose from the line and
    # the ledger keeps the length. Refuse it here rather than leave the caller to filter,
    # so every consumer of split_head gets the same answer.
    if len(head) - len(keep) < MIN_MOVED_CHARS:
        return None, None, "no-net-shrink"

    # RETIRED VOCABULARY: refuse rather than plant it. Preserving an item's computed lane
    # can mean lifting a venue-keyed `[HARD <dash> venue]` tag into the leading run, and the
    # pre-commit vocabulary ratchet correctly BLOCKS an added line carrying one -- it is
    # mid-migration to the capability-keyed spelling (`relay/scripts/lane-convert.sh`:
    # `[HARD - pool]` -> `[HARD]`, `[HARD - meeting]` -> `[INPUT - meeting]`).
    #
    # Cooperating with the guard beats fighting it. The alternatives were --no-verify
    # (routing around a guard) or hand-swapping a delimiter, which the fleet rule forbids
    # precisely because a lane tag whose delimiter stops matching its detector is invisible
    # to dispatch. So: refuse this ONE item, report it, and let the canonical converter
    # migrate the tag as its own deliberate act. Refusing costs a line left long.
    if lane_parts and _RETIRED_LANE_RE.fullmatch(lane_parts[0]):
        return None, None, "lane-retired-vocab:" + lane_parts[0]

    reason = "split:lane-in-body=" + ",".join(lane_in_body) if lane_in_body else "split"
    return keep, rest.strip(), reason


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
        "**This note is EDITABLE** (owner-ratified 2026-09-02). If a fleet rule is violated\n"
        "in the prose below -- retired vocabulary, a lane delimiter, a banned token -- FIX IT\n"
        "HERE and amend the line above to say what was changed. Notes are not immutable: an\n"
        "unfixable violation keeps its guard red forever, and this prose gets copied back out\n"
        "into new items. An undeclared edit makes the verbatim claim above a lie.\n\n"
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

def plan(lines, min_chars, path, open_only=False):
    """Pure decision: which head lines to slim, and what each becomes. No file I/O."""
    items = parse_items(lines)
    actions = []
    refused = {}
    skipped_no_id = []
    lane_in_body = []
    considered = 0
    for it in items:
        # CLOSED `[x]` items are in scope (owner ruling 2026-09-02). Wave 1 skipped them,
        # which is nearly all of ROADMAP.md's shortfall against the no-prose bar -- 65 of
        # its 116 prose-carrying lines, because that file is mostly history. History is
        # never dispatched and never sliced, so shrinking it is pure byte win at no risk
        # to any detector that reads open items. Opt out with --open-only.
        if open_only and not it.open:
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
        if reason.startswith("split:lane-in-body="):
            lane_in_body.append((it.id, reason.split("=", 1)[1]))
    return {"actions": actions, "refused": refused, "skipped_no_id": skipped_no_id,
            "lane_in_body": lane_in_body,
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
    "pointer-exists": "already has a pointer (idempotent)",  # unreachable since id:6546
    "no-cut-point": "no defensible cut point",
    "too-little-to-move": "under {} chars would move".format(MIN_MOVED_CHARS),
    "bold-run-to-anchor": "the first bold run reaches the id anchor, so the primary cut "
                          "leaves ONLY markers (the fallback cut rules are never reached; "
                          "not a size problem -- lowering the threshold buys nothing)",
    "no-net-shrink": "the head would not shrink by {} chars (the pointer costs more than "
                     "the split saves)".format(MIN_MOVED_CHARS),
    "foreign-id": "block carries ANOTHER item's id marker (would orphan it)",
    "lane-would-change": "the split would CHANGE the item's computed lane (id:4da4)",
    "lane-retired-vocab": "preserving the lane would plant RETIRED venue-keyed vocabulary; "
                          "migrate the tag with relay/scripts/lane-convert.sh first",
}


def main(argv=None):
    global NOTES_DIR
    ap = argparse.ArgumentParser(prog="ledger-shrink.py", add_help=True,
                                 description="Slim over-long ledger head lines into "
                                             "docs/ledger-notes/<id>.md.")
    ap.add_argument("--file", default="TODO.md", help="ledger to process (default TODO.md)")
    ap.add_argument("--min-chars", type=int, default=DEFAULT_MIN_CHARS,
                    help="head-line length at or above which an item is a candidate "
                         "(default {})".format(DEFAULT_MIN_CHARS))
    ap.add_argument("--root", default=None, help="repo root (default: the file's repo)")
    ap.add_argument("--dry-run", action="store_true", help="report only (the default)")
    ap.add_argument("--open-only", action="store_true",
                    help="skip closed [x] items (wave-1 behaviour; the owner ruled closed "
                         "items IN scope on 2026-09-02, so this is now opt-in)")
    ap.add_argument("--notes-dir", default=None,
                    help="directory for per-id detail files (default {}). Set it for a repo "
                         "that spells the path differently -- loderite uses "
                         "docs/roadmap-notes.".format(NOTES_DIR))
    ap.add_argument("--apply", action="store_true", help="actually move the prose")
    args = ap.parse_args(argv)

    if args.notes_dir:
        # Rebind the module constant so pointer_for/has_pointer/note_file_text/apply_plan
        # all agree. A per-repo directory is a PARAMETER, not a fork of the tool -- but see
        # roadmap-lint.sh's item_detail_path: readers DERIVE the dir from the pointer rather
        # than trusting config, because an unset parameter and a wrong default are
        # indistinguishable in the output (id:d35a).
        NOTES_DIR = args.notes_dir.strip("/")

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

    planned = plan(lines, args.min_chars, rel, open_only=args.open_only)
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
    if planned["lane_in_body"]:
        # SURFACED, never acted on. These items carry a lane token outside their leading
        # run. It may be the item's real lane sitting in the wrong place, or it may be prose
        # mentioning a lane -- and nothing mechanical can tell them apart (loderite's
        # ROADMAP has a literal `[HARD - decision gate|hands|meeting|pool]` enumeration that
        # is one well-formed token by any regex and pure prose by meaning). The tag is KEPT
        # on the line either way; only a human can decide whether it belongs in the leading
        # run, so the tool reports and leaves it.
        print("  LANE TOKEN OUTSIDE THE LEADING RUN (kept, never promoted -- a human "
              "decides): {}".format(len(planned["lane_in_body"])))
        for _id, lanes in planned["lane_in_body"][:12]:
            print("    id:{}  {}".format(_id, lanes))

    if not args.apply:
        print("  (dry run -- nothing written)")
        return 0

    created, appended = apply_plan(root, rel, lines, planned)
    print("  note files: {} created, {} appended to (0 overwritten, by construction)"
          .format(created, appended))
    return 0


if __name__ == "__main__":
    sys.exit(main())
