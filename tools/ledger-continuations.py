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
               relocating it turns the consumer red. COMPUTED EVERY RUN from the tree under
               `--root`, never remembered: see "THE CITED-BODY PREDICATE" below. This is the
               id:2ee1 / id:1608 class -- "every consumer that reads an item's BODY breaks
               when the body moves" -- and the honest response is to refuse the item, not
               to weaken the consumer.

THE CITED-BODY PREDICATE (id:9ce0). This check used to be a hand-maintained `REFUSE_IDS`
dict of `id -> reason`. That dict WAS the mechanism, so emptying it (2026-09-03, when its
one entry went stale) left the `REFUSED cited-body` counter reporting 0 unconditionally,
for every ledger, forever: a check that structurally cannot fail, the id:0b70 vacuous-check
class. An id-keyed list is the wrong SHAPE regardless -- it is the id:cb3e grandfathering
trap, and it cannot know about a consumer minted tomorrow. So the list is gone and the
predicate is recomputed on every invocation:

  READER SET. A file under `--root` is a reader when it (a) names a LIVE ledger path and
  (b) contains a content-matching construct over what it read. The ledger set is FOUR, not
  three (routed:42c9): TODO.md, ROADMAP.md, REVIEW_ME.md and the `.archive.md` siblings --
  distrust any docstring that says three. The DETECTOR set is part of the reader set:
  `relay/scripts/roadmap-lint.sh` (its hop-table parser is the motivating case),
  `relay/scripts/todo-conformance.sh`, `meeting/orphan-scan.sh`, `tools/ledger-shrink.py`
  and the whole `tests/` tree read as infrastructure rather than as consumers, and omitting
  them is precisely the bug.

  UNION-ANCHORED READERS DO NOT REFUSE. A reader that also reads `docs/ledger-notes/` sees
  the ledger + notes UNION, so relocation cannot break it. That, and only that, is why
  `id:6b35` is no longer refused: both of its consumers were re-anchored. Revert
  `roadmap-lint.sh`'s parser to read `ROADMAP.md` alone and the refusal returns by itself.

  NO GRAMMAR SHORTCUT. "Every reader here anchors on `^- \\[ \\]`, therefore no reader reads
  bodies" is true of THIS repo only because its bodies live in `docs/ledger-notes/`, and it
  is vacuous in a repo whose body IS the item line. Patterns are matched against the actual
  body text, with the reader's own anchors honoured as written.

  UNANALYSABLE READERS FAIL LOUD. A search pattern built at run time or held in a variable
  cannot be statically extracted. It is counted and printed as UNANALYSABLE, never scored
  as "no match" -- silent success is the failure mode being repaired.

  SELF-TEST. `selftest_predicate()` runs before every scan: a fixture reader plus a fixture
  body that MUST be refused, a body that must NOT be, and a construct that must be reported
  unanalysable. If the fixture is not refused the tool exits non-zero, so the next refactor
  cannot re-vacuum the counter the way this one was vacuumed.

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
import warnings

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


# ------------------------------------------------- the computed cited-body predicate
#
# THERE IS NO `REFUSE_IDS` AND THERE MUST NEVER BE ONE AGAIN. Everything below is
# recomputed from the tree on every invocation. An id-keyed or token-keyed allow list
# cannot know about a consumer minted tomorrow (id:cb3e), and the one this replaces
# decayed into a counter that could only ever print 0 (id:9ce0).
#
# NOTHING HERE NAMES A FILE. `roadmap-lint.sh`, `todo-conformance.sh`, `orphan-scan.sh`
# and `ledger-shrink.py` are WORKED EXAMPLES of what this computation must find -- proof
# obligations, not a list. If this predicate ever needs one of those names hardcoded to
# work, the predicate has failed and the honest move is to say so, not to type the name.
# Likewise there is no per-repo and no per-grammar branch: a predicate that needs to know
# which repo it is running in is wrong.

# FOUR ledgers, not three (routed:42c9): the archives count. Matched as a BASENAME,
# deliberately, because every real detector COMPOSES the basename onto a variable root
# (`"$root/TODO.md"`, `"$_rl_dir/TODO.archive.md"`) and is invoked through a
# `~/.claude/skills/` symlink, so no resolved path is ever present in the source.
LEDGER_BASENAME_RE = re.compile(r"\b(?:TODO|ROADMAP|REVIEW_ME)(?:\.archive)?\.md\b")

# A reader that ALSO reads the notes directory sees the ledger+notes UNION, so relocating
# a body cannot break it. This, and only this, is what lifts a refusal -- which makes it
# the one place a mistake is UNSAFE (a spurious union verdict hides a real consumer, while
# a missed one only produces an extra refusal, and a refusal is always safe). So it demands
# EVIDENCE OF A READ, not a mention: a bare `ledger-notes` occurrence is usually a comment
# or a message string. `todo-conformance.sh` and `orphan-scan.sh` mention the directory and
# never read it; scoring them union on the mention alone silently cleared the two readers
# whose strip-then-match bodies matter most.
NOTES_READ_RES = (
    # a traversal or read whose target is the notes directory
    re.compile(r"(?:glob|iglob|os\.walk|listdir|scandir|opendir|readdir|open\s*\(|"
               r"\bcat\b|\bfind\b|\bls\b|grep\s+-[A-Za-z]*r)[^\n]*ledger-notes"),
    re.compile(r"ledger-notes[^\n]*\*\.md"),
    # a plain variable bound to the notes directory (it exists to be read from)
    re.compile(r"^[ \t]*(?:local|export|readonly|declare)?[ \t]*"
               r"[A-Za-z_][A-Za-z0-9_]*[ \t]*=[ \t]*[^\n]*ledger-notes"),
)


def reads_notes(text):
    for line in text.split("\n"):
        stripped = line.lstrip()
        if stripped.startswith("#") or stripped.startswith("//"):
            continue
        if "ledger-notes" not in line:
            continue
        if any(r.search(line) for r in NOTES_READ_RES):
            return True
    return False

READER_EXTS = (".sh", ".bash", ".py", ".js", ".mjs", ".cjs", ".awk", ".pl")
READER_SKIP_DIRS = {".git", "docs", "__pycache__", "node_modules", ".claude", "worktrees"}

# Content-matching constructs. `sed`'s `s/PAT/REPL/` is INCLUDED, not skipped: several
# readers strip a leading run and then match over the REMAINDER
# (`todo-conformance.sh`'s `head_refusable`, `roadmap-lint.sh`'s backtick-stripping pass).
# Scoring those as "anchor-only, body cleared" is the repo-shaped trap: here the remainder
# is chrome, in a repo whose body IS the item line the same code matches the body.
CONSTRUCT_RE = re.compile(
    r"(?P<kind>"
    r"\b(?P<grep>grep|egrep|fgrep|zgrep|rg)\b"
    r"|\b(?P<sedawk>sed|awk|gawk|mawk)\b"
    r"|(?P<py>re\.(?:search|match|fullmatch|compile|findall|finditer|sub|subn|split)\s*\()"
    r"|(?P<js>\.(?:includes|startsWith|endsWith|match|matchAll|test|search)\s*\()"
    r"|(?P<pyattr>\.(?:startswith|endswith|find|index|count)\s*\()"
    r")")

# `'LITERAL' in text` -- Python's substring test, e.g. roadmap-lint's `'CONVERTIBLE' in line`.
IN_TEST_RE = re.compile(
    r"""(?:r?'((?:[^'\\]|\\.)*)'|r?"((?:[^"\\]|\\.)*)")\s+in\s+(?![\[(])""")

QUOTED_RE = re.compile(r"""(?:r?'((?:[^'\\]|\\.)*)'|r?"((?:[^"\\]|\\.)*)")""")

# `NAME = re.compile(<literal>)` -- the same one-level fold, for the receiver form
# `NAME.search(line)`. Without it every module-level compiled regex in the tree
# (`md-merge.py`'s `_CHECKBOX_RE`, `archive-done.sh`'s `date_re`) is a FALSE loud failure.
PY_COMPILE_RE = re.compile(
    r"""^[ \t]*(?P<name>[A-Za-z_][A-Za-z0-9_]*)[ \t]*=[ \t]*re\.compile\([ \t]*"""
    r"""(?:r?'(?P<sq>(?:[^'\\]|\\.)*)'|r?"(?P<dq>(?:[^"\\]|\\.)*)")""")
RECEIVER_RE = re.compile(
    r"\b(?P<name>[A-Za-z_][A-Za-z0-9_]*)"
    r"\.(?:match|search|fullmatch|findall|finditer|sub|subn|split)\s*\(")

# A ledger PATH argument grabbed where a pattern was expected. Anchored on the WHOLE
# literal: `'(archived -- see ROADMAP.archive.md)'` is a genuine search pattern that
# merely mentions a ledger, and calling it a path is how a real consumer goes missing.
PATH_ARG_RE = re.compile(r"^\S*(?:TODO|ROADMAP|REVIEW_ME)(?:\.archive)?\.md$")
JS_REGEX_RE = re.compile(r"/((?:[^/\\\n]|\\.)+)/[gimsuy]*")

# One-level constant fold. A pattern held in a variable is analysable when that variable
# has EXACTLY ONE assignment in the file and that assignment is a literal -- which is the
# shape of `todo-conformance.sh`'s `LENGTH_MUST_KEEP_RE`. Reporting that UNANALYSABLE
# would be a FALSE loud failure, and a loud failure nobody can act on only moves where the
# information dies. UNANALYSABLE is reserved for genuine runtime composition.
ASSIGN_RE = re.compile(
    r"""^[ \t]*(?:local|declare|export|readonly|typeset)?[ \t]*"""
    r"""(?P<name>[A-Za-z_][A-Za-z0-9_]*)[ \t]*=[ \t]*"""
    r"""(?:'(?P<sq>(?:[^'\\]|\\.)*)'|"(?P<dq>(?:[^"\\]|\\.)*)")[ \t]*$""")

VAR_REF_RE = re.compile(r"\$\{(?P<b>[A-Za-z_][A-Za-z0-9_]*)\}|\$(?P<p>[A-Za-z_][A-Za-z0-9_]*)")
# A `$` that is an ANCHOR (end of line / end of pattern) is not an expansion.
EXPANSION_RE = re.compile(r"\$[A-Za-z_{(0-9]")
# Shell-only, and only inside DOUBLE quotes: command substitution.
RUNTIME_MARK_RE = re.compile(r"\$\(|`")
# Python/JS interpolation. `{4}` is a regex quantifier and deliberately NOT here.
FMT_MARK_RE = re.compile(r"\{\}|%s|\$\{")


class Pattern:
    """One statically extracted search pattern belonging to one reader."""

    def __init__(self, path, lineno, rx, raw, snippet):
        self.path = path
        self.lineno = lineno
        self.rx = rx
        self.raw = raw
        self.snippet = snippet

    def where(self):
        return "{}:{}".format(self.path, self.lineno)


class Unanalysable:
    """A reader construct whose pattern cannot be extracted statically.

    `site` is the ASSIGNMENT site when the pattern came from a variable, because a bare
    count leaves the caller exactly where the vacuous counter did.
    """

    def __init__(self, path, lineno, snippet, why, site=None):
        self.path = path
        self.lineno = lineno
        self.snippet = snippet
        self.why = why
        self.site = site

    def render(self):
        head = "{}:{}: {}".format(self.path, self.lineno, self.snippet.strip()[:100])
        tail = self.why if not self.site else "{} (assigned at {})".format(self.why, self.site)
        return head + "  <- " + tail


def _literal_assignments(text):
    """name -> (value, lineno) for names assigned EXACTLY ONCE, to a literal.

    A name assigned twice, or assigned anything non-literal even once, is absent: that is
    runtime composition and must stay loud.
    """
    seen = {}
    poisoned = set()
    for n, line in enumerate(text.split("\n"), 1):
        if "=" not in line:
            continue
        m = ASSIGN_RE.match(line)
        if not m:
            # An assignment we cannot read as a literal still POISONS the name.
            bad = re.match(r"^[ \t]*(?:local|declare|export|readonly|typeset)?[ \t]*"
                           r"([A-Za-z_][A-Za-z0-9_]*)[ \t]*=", line)
            if bad:
                poisoned.add(bad.group(1))
            continue
        name = m.group("name")
        val = m.group("sq") if m.group("sq") is not None else m.group("dq")
        if name in seen:
            poisoned.add(name)
        seen[name] = (val, m.group("dq") is not None, n)
    return {k: v for k, v in seen.items() if k not in poisoned}


def _fold(raw, assigns):
    """One-level constant fold. Returns (folded, site) or (None, site) if not foldable.

    A SINGLE-quoted shell assignment is literal text: `LENGTH_MUST_KEEP_RE='...`?@(...)`?...'`
    carries backticks that are regex, not command substitution. Rejecting it would be the
    false loud failure this fold exists to prevent.
    """
    site = None
    out = raw
    for m in list(VAR_REF_RE.finditer(raw)):
        name = m.group("b") or m.group("p")
        if name not in assigns:
            return None, None
        val, dq, ln = assigns[name]
        if dq and (EXPANSION_RE.search(val) or RUNTIME_MARK_RE.search(val)):
            return None, "line {}".format(ln)
        site = "line {}".format(ln)
        out = out.replace(m.group(0), val)
    return out, site


def _compile(pat, literal, flags=0):
    """Best effort. A pattern that will not compile is treated as a fixed string, which
    is the conservative reading: a refusal is always safe, a missed consumer is not."""
    if literal:
        return re.compile(re.escape(pat), flags)
    # A grep BRE such as `[[:space:]]` makes Python emit a "possible nested set"
    # FutureWarning. It still compiles and still matches; the warning is noise from
    # analysing someone else's dialect, so it is silenced rather than printed 30 times.
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", FutureWarning)
        try:
            return re.compile(pat, flags)
        except re.error:
            try:
                return re.compile(re.escape(pat), flags)
            except re.error:
                return None


def _sed_patterns(literal):
    """Content-matching pieces of a sed/awk program: `/ADDR/` and `s/PAT/REPL/`."""
    found = []
    for m in re.finditer(r"s/((?:[^/\\]|\\.)*)/(?:[^/\\]|\\.)*/[a-zA-Z0-9]*", literal):
        if m.group(1):
            found.append(m.group(1))
    for m in re.finditer(r"(?<!s)/((?:[^/\\]|\\.)+)/\s*(?![^/]*/)", literal):
        if m.group(1) and m.group(1) not in found:
            found.append(m.group(1))
    return found


def _compiled_regex_vars(text):
    """name -> (pattern, dq, lineno) for `NAME = re.compile(<literal>)`, assigned once."""
    seen = {}
    dup = set()
    for n, line in enumerate(text.split("\n"), 1):
        m = PY_COMPILE_RE.match(line)
        if not m:
            continue
        name = m.group("name")
        if name in seen:
            dup.add(name)
        val = m.group("sq") if m.group("sq") is not None else m.group("dq")
        seen[name] = (val, m.group("dq") is not None, n)
    return {k: v for k, v in seen.items() if k not in dup}


def extract_patterns(path, text):
    """Return (patterns, unanalysables) for ONE reader file.

    Quote kind is load-bearing. In a shell script a SINGLE-quoted string is literal text:
    its `$`, its backticks and its `{n}` are regex syntax, not expansions. Only a
    DOUBLE-quoted shell string can interpolate. Ignoring that reported every
    backtick-stripping `sed -E 's/`[^`]*`//g'` -- the Amendment-B strip-then-match shape --
    as runtime composition, which is a false loud failure over the exact readers that
    matter most.
    """
    is_shell = path.endswith((".sh", ".bash"))
    assigns = _literal_assignments(text)
    compiled = _compiled_regex_vars(text)
    pats = []
    unan = []

    def analyse(n, line, raw, dq, literal, flags, sedawk, site=None):
        if is_shell and dq:
            # Anything OUTSIDE the variable references must be plain text; a folded
            # value is literal by construction and is not re-scanned for expansions.
            residual = VAR_REF_RE.sub("", raw)
            if EXPANSION_RE.search(residual) or RUNTIME_MARK_RE.search(residual):
                unan.append(Unanalysable(path, n, line,
                                         "pattern composed at run time", site))
                return
            if VAR_REF_RE.search(raw):
                folded, fsite = _fold(raw, assigns)
                if folded is None:
                    unan.append(Unanalysable(path, n, line,
                                             "pattern composed at run time", fsite or site))
                    return
                raw = folded
        elif not is_shell and FMT_MARK_RE.search(raw):
            unan.append(Unanalysable(path, n, line,
                                     "pattern interpolated at run time", site))
            return
        if PATH_ARG_RE.match(raw.strip()):
            # We grabbed the FILE argument, not the pattern: say so, do not guess.
            unan.append(Unanalysable(path, n, line,
                                     "could not tell pattern from path argument", site))
            return
        if not raw.strip():
            return
        for cand in (_sed_patterns(raw) if sedawk else [raw]):
            rx = _compile(cand, literal, flags)
            if rx:
                pats.append(Pattern(path, n, rx, cand, line))

    for n, line in enumerate(text.split("\n"), 1):
        stripped = line.lstrip()
        if stripped.startswith("#") or stripped.startswith("//"):
            continue
        for m in IN_TEST_RE.finditer(line):
            lit = m.group(1) if m.group(1) is not None else m.group(2)
            if lit:
                rx = _compile(lit, True)
                if rx:
                    pats.append(Pattern(path, n, rx, lit, line))
        if not is_shell:
            for rm in RECEIVER_RE.finditer(line):
                name = rm.group("name")
                if name in ("re", "self"):
                    continue
                if name in compiled:
                    val, dq, ln = compiled[name]
                    analyse(n, line, val, dq, False, 0, False, "line {}".format(ln))
                elif name.isupper() or name.lower().endswith("_re") or name.endswith("Re"):
                    unan.append(Unanalysable(
                        path, n, line, "pattern held in a variable this pass cannot fold"))
        for cm in CONSTRUCT_RE.finditer(line):
            rest = line[cm.end():]
            qm = QUOTED_RE.search(rest)
            jm = JS_REGEX_RE.search(rest) if cm.group("js") else None
            if jm and (not qm or jm.start() < qm.start()):
                raw, dq, literal, opts = jm.group(1), False, False, rest[:jm.start()]
            elif qm:
                raw = qm.group(1) if qm.group(1) is not None else qm.group(2)
                dq = qm.group(2) is not None
                opts = rest[:qm.start()]
                literal = bool(cm.group("js") or cm.group("pyattr")
                               or re.search(r"(?<![A-Za-z])-[A-Za-z]*F", opts))
            else:
                unan.append(Unanalysable(path, n, line, "no extractable pattern literal"))
                continue
            if cm.group("grep") and re.search(r"(?<![A-Za-z])-[A-Za-z]*f(?![A-Za-z])", opts):
                unan.append(Unanalysable(path, n, line, "pattern read from a file (grep -f)"))
                continue
            flags = re.I if (cm.group("grep") and
                             re.search(r"(?<![A-Za-z])-[A-Za-z]*i", opts)) else 0
            analyse(n, line, raw, dq, literal, flags, bool(cm.group("sedawk")))
    return pats, unan


def find_readers(root):
    """Compute the live reader set under `root`. Returns a dict of everything measured."""
    ledger_only = []
    union = []
    pats = []
    unan = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in READER_SKIP_DIRS]
        for fn in sorted(filenames):
            if not fn.endswith(READER_EXTS):
                continue
            full = os.path.join(dirpath, fn)
            rel = os.path.relpath(full, root)
            try:
                text = open(full, encoding="utf-8", errors="replace").read()
            except OSError:
                continue
            if not LEDGER_BASENAME_RE.search(text):
                continue
            fpats, funan = extract_patterns(rel, text)
            if not (fpats or funan):
                continue          # names a ledger but never content-matches: not a reader
            if reads_notes(text):
                union.append(rel)
                continue          # reads the ledger+notes UNION: relocation cannot break it
            ledger_only.append(rel)
            pats.extend(fpats)
            unan.extend(funan)
    return {"ledger_only": ledger_only, "union": union,
            "patterns": pats, "unanalysable": unan}


def cited_by(body_lines, patterns, elsewhere_lines=()):
    """EVERY (pattern, body index) whose reader BREAKS if this block's body is relocated,
    one per consumer site, in file order.

    "Breaks" is the whole point, and it is stricter than "matches". A reader is broken by
    the move only when its pattern matches something INSIDE the block and matches NOTHING
    in what the ledger still holds afterwards: a pattern that also matches surviving text
    finds the same thing before and after, so relocating this body changes nothing for it.
    Without that second half the predicate answers "yes" for every reader whose pattern is
    `\\s+` -- 232 of them on this repo's ROADMAP -- which is a different way of being
    useless from the constant it replaces, not a fix. `elsewhere_lines` is the ledger
    minus this block; pass it, or every generic pattern reads as a consumer.

    Known and deliberate residue: a reader that COUNTS occurrences (`grep -c`) rather than
    testing for presence can still be perturbed by a move this predicate clears. That is
    reported by the suite, not by this check.

    All of them, not the first: a refusal has to be able to NAME the consumer that
    motivated it, and a single-hit answer lets an unrelated reader shadow the one the
    caller is checking for.

    Matched against the RAW body text, anchors and all. No shortcut of the form "every
    reader anchors on the item line, therefore no reader reads bodies" -- that is true
    here only because this repo's bodies live in `docs/ledger-notes/`, and vacuous in a
    repo whose body IS the item line.
    """
    hits = []
    seen = set()
    for p in patterns:
        key = (p.path, p.lineno)
        if key in seen:
            continue
        for k, bl in enumerate(body_lines):
            if p.rx.search(bl):
                if any(p.rx.search(o) for o in elsewhere_lines):
                    break                     # still satisfied after the move: not broken
                seen.add(key)
                hits.append((p, k))
                break
    return hits


SELFTEST_TOKEN = "ZZ-ledger-continuations-selftest-token-ZZ"


def selftest_predicate():
    """A fixture reader plus a body that MUST be refused. Without this the counter can be
    silently re-vacuumed by the next refactor exactly as it was by the last one."""
    reader = "\n".join([
        "#!/usr/bin/env bash",
        "PAT_VAR='" + SELFTEST_TOKEN + "'",
        'roadmap="$root/ROADMAP.md"',
        'grep -q "${PAT_VAR}" "$roadmap"',
        'grep -q "$RUNTIME_ONLY" "$roadmap"',
    ])
    pats, unan = extract_patterns("selftest-reader.sh", reader)
    problems = []
    if not pats:
        problems.append("no pattern extracted from the fixture reader")
    if not any(p.raw == SELFTEST_TOKEN for p in pats):
        problems.append("one-level constant fold did not resolve PAT_VAR")
    if not unan:
        problems.append("a runtime-composed pattern was not reported UNANALYSABLE")
    if not cited_by(["  - a body line mentioning " + SELFTEST_TOKEN + " inline"], pats):
        problems.append("a cited body was NOT refused")
    if cited_by(["  - a body line that nothing reads"], pats):
        problems.append("an uncited body was refused (predicate matches everything)")
    body = ["  - a body line mentioning " + SELFTEST_TOKEN + " inline"]
    if cited_by(body, pats, ["- an item line also carrying " + SELFTEST_TOKEN]):
        problems.append("a body whose text SURVIVES the move elsewhere was refused")
    if not reads_notes("notes_dir = 'docs/ledger-notes'"):
        problems.append("a genuine notes read was not recognised as union-anchored")
    if reads_notes("# the prose belongs in docs/ledger-notes instead"):
        problems.append("a COMMENT mention of the notes dir was scored union-anchored")
    return problems


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


def scan(lines, patterns=None):
    """Return (blocks, refusals). `lines` is the file split on newlines.

    `patterns` is the COMPUTED reader-pattern set (see find_readers); an empty/None set
    means no live consumer was found, never "assume none".
    """
    patterns = patterns or []
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
                    else:
                        rest = lines[:i + 1] + lines[j:]
                        hits = cited_by(cont, patterns, rest)
                        if hits:
                            # EVERY consumer, never a truncated head. The consumer that
                            # motivates a refusal is frequently not the first one found,
                            # and a reason that omits it cannot be acted on.
                            named = "".join(
                                "\n        {} matches body line {} (pattern `{}`)".format(
                                    p.where(), i + 2 + k, p.raw)
                                for p, k in hits)
                            refused.append((
                                "cited-body", i + 1,
                                "id:{} -- body read by {} live consumer site(s):{}".format(
                                    idm.group(1), len(hits), named)))
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

    problems = selftest_predicate()
    if problems:
        print("SELF-TEST FAILED -- the cited-body predicate is not working; its counter "
              "would be meaningless (id:9ce0):", file=sys.stderr)
        for p in problems:
            print("  - " + p, file=sys.stderr)
        return 4

    readers = find_readers(root)

    blocks, refused = scan(lines, readers["patterns"])
    heading = section_heading(args.file)

    # ---- ORPHAN PRECONDITION: every id addressable before must be addressable after.
    ids_before = set(ID_RE.findall(raw))
    print("== {} ==".format(args.file))
    print("items with a continuation block : {}".format(len(blocks)))
    print("continuation lines to relocate  : {}".format(sum(len(b.cont) for b in blocks)))
    print("id markers in the ledger before : {}".format(len(ids_before)))
    print("ledger-only readers (computed)   : {}".format(len(readers["ledger_only"])))
    print("union-anchored readers (notes)   : {}".format(len(readers["union"])))
    print("reader patterns extracted        : {}".format(len(readers["patterns"])))
    print("UNANALYSABLE reader constructs   : {}".format(len(readers["unanalysable"])))
    for u in readers["unanalysable"]:
        print("    " + u.render())
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
