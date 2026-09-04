#!/usr/bin/env python3
"""ONE definition of the negative-case header spelling, and of what `# roadmap:` MEANS
(TODO id:7c82; the id:4983 defect class -- make ONE source serve both the actor and the
checker).

WHY THIS MODULE EXISTS
----------------------
Two tools read the same three markers and used to carry their own regexes:

  * `tests/lint-vacuous-fixtures.py` -- mechanism (1): is a negative case ON RECORD?
  * `tests/verify-negative-cases.py` -- the runner: EXECUTE the declared case.

They drifted, exactly as duplicated patterns do. Measured 2026-09-03: the lint matched only
the BARE `# fails-against:` spelling, so the ratified `-rev:` / `-mutation:` forms were
invisible to it and every file using them was flagged as undeclared (11 flagged, 2 of them
false positives). Meanwhile the runner accepted those forms but CANCELLED them on any file
carrying a `# roadmap:` token. Neither tool was wrong about its own rule; the divergence was
the bug.

THE THREE MARKERS (grammar is CLAUDE.md §Testing; this module only spells them)
------------------------------------------------------------------------------
    # roadmap:XXXX                                    this file is the RED SPEC of that item
    # fails-against: <prose>                          mechanism (1): the case, on record
    # fails-against-rev: <rev> -- <path> [<path>…]    machine-readable case
    # fails-against-mutation: <shell command>         machine-readable case
    # fails-against-assertion: <substring>            which FAIL line must fire (a MODIFIER of
                                                      the case above it, never a declaration
                                                      on its own)

WHAT `# roadmap:` MEANS, and why the carve-out must EXPIRE
----------------------------------------------------------
`tests/run-tests.sh` grants EXPECTED-RED only while the item's checkbox is UNTICKED
(`run-tests.sh:78-83`, `item_open`). The runner's carve-out keyed on the token's mere
PRESENCE, so it never expired: once an item closed, `run-tests.sh` correctly stopped granting
EXPECTED-RED while the runner went on cancelling that file's declaration forever, silently.
`roadmap_item_open()` below is the SINGLE resolution both halves now agree on.

RESOLUTION SCOPE -- deliberately the LIVE `ROADMAP.md` only, and nothing else.
`item_open` in `run-tests.sh` greps exactly one file for exactly one shape, so "open" means
"an UNTICKED `- [ ]` line in the live ROADMAP.md carrying `<!-- id:XXXX -->`". Everything else
-- ticked, moved to `ROADMAP.archive.md`, tracked only in `TODO.md`, or never present at all
-- is NOT open, so the carve-out expires. That is a choice, and the alternative was
considered: the ledger set is FOUR files (`TODO.md`, `ROADMAP.md`, `REVIEW_ME.md`, archives,
per `routed:42c9`), and a token that resolves to nothing in the live file may well live in
`ROADMAP.archive.md`. Scanning those would make the carve-out expire on a DIFFERENT rule than
the one `run-tests.sh` applies -- a third opinion about the same marker, which is the very
drift `id:7c82` exists to close. An archived item is closed, and an item that is open in
TODO.md but absent from ROADMAP.md never earned EXPECTED-RED either. Fail direction on a
lookup miss is toward VERIFYING the declaration (loud), never toward silently skipping it.
"""
import os
import re

# --------------------------------------------------------------------------- the spelling
# `[0-9a-f]{4}` and not `\S+`: aligned with `tests/run-tests.sh:170`
# (`grep -oE '# roadmap:[0-9a-f]{4}'`), which is the harness's own rule.
ROADMAP_RE = re.compile(r'^\s*#\s*roadmap:([0-9a-f]{4})\b', re.MULTILINE)

# Mechanism (1): the case is ON RECORD. Prose form.
PROSE_RE = re.compile(r'^\s*#\s*fails-against:\s*\S', re.MULTILINE)

# The machine-readable case forms. Anchored per-line, matched line-by-line by the runner
# (which needs the groups), and used whole-text by the lint (which only asks "is one here?").
CASE_RE = re.compile(r'^\s*#\s*fails-against-(rev|mutation):\s*(.+?)\s*$')
CASE_ANY_RE = re.compile(r'^\s*#\s*fails-against-(?:rev|mutation):\s*\S', re.MULTILINE)

# A MODIFIER of the case above it. Deliberately NOT part of DECLARATION_RE: an
# `-assertion:` line with no case is a CONFIG ERROR in the runner, so it must not count as a
# declaration for the lint either.
ASSERT_RE = re.compile(r'^\s*#\s*fails-against-assertion:\s*(.+?)\s*$')

# "A negative case is declared" -- prose OR either machine-readable form. THE definition
# both tools now ask; neither carries its own copy.
DECLARATION_RE = re.compile(
    r'^\s*#\s*fails-against(?:-rev|-mutation)?:\s*\S', re.MULTILINE)

DECLARATION_SPELLINGS = (
    "# fails-against: <prose>",
    "# fails-against-rev: <rev> -- <path>…",
    "# fails-against-mutation: <shell command>",
)


def roadmap_token(text):
    """The FIRST `# roadmap:XXXX` token in `text`, or None.

    Whole-text by design, and FIRST by design: `run-tests.sh:170` takes `head -1` of a
    whole-file grep, and this must resolve to the same token that runner would use.
    """
    m = ROADMAP_RE.search(text)
    return m.group(1) if m else None


def roadmap_item_open(root, token):
    """True iff ROADMAP.md carries an UNTICKED item with `<!-- id:token -->`.

    The Python twin of `run-tests.sh`'s `item_open()`:
        grep -qE "^- \\[ \\] .*<!-- id:${token} -->" "$ROADMAP"
    A missing ROADMAP.md, a ticked box, or no such line at all all mean NOT open. See
    RESOLUTION SCOPE in the module docstring for why nothing else is consulted.
    """
    path = os.path.join(root, "ROADMAP.md")
    if not token or not os.path.exists(path):
        return False
    pat = re.compile(r'^- \[ \] .*<!-- id:%s -->' % re.escape(token), re.MULTILINE)
    try:
        text = open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return False
    return bool(pat.search(text))


def roadmap_carveout_applies(root, text):
    """True iff `text` is the RED SPEC of a still-OPEN roadmap item.

    This is the whole carve-out, in one place: presence of the token is NOT sufficient.
    """
    tok = roadmap_token(text)
    return bool(tok) and roadmap_item_open(root, tok)
