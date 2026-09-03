#!/usr/bin/env python3
"""lib-archive-idempotency.py (id:2eba) — THE single definition of "has this ledger
item already been archived?", shared by BOTH generic archivers:

  * relay/scripts/roadmap-archive.sh
  * relay/scripts/archive-closed.sh

WHY ONE FILE. Until 2026-09-03 the idempotency test was "does this live line carry the
literal stub suffix?", and that literal plus its regex were spelled INDEPENDENTLY in both
scripts (`STUB_SUFFIX`/`stub_line_re` at roadmap-archive.sh:114/:122 and
`STUB_SUFFIX`/`STUB_LINE_RE` at archive-closed.sh:107/:123). One copy had silently dropped
the load-bearing `.*` and re-archived 24 stubs across the fleet in a single run before
anyone noticed. `id:4983` closed exactly this shape for the lane grammar ("the lane grammar
is hand-mirrored in three places; make ONE source serve both the actor and the checker"),
and adding a third copy for the checker would have recreated it. So the definition lives
here and both consumers import it.

WHAT CHANGED, AND WHY THE OLD TEST HAD TO GO (id:2eba, owner-ratified 2026-09-03).
The archivers used to leave a one-line STUB behind in the live ledger for every item they
moved (`id:cd9c`), and that stub doubled as the idempotency guard: a line carrying the
suffix classified `keep`, so the archiver did not eat its own successor's output. The owner
ruled the stub out entirely — 62 stub lines were 26,101 bytes, 36% of this repo's
ROADMAP.md, all of them closed work already sitting in ROADMAP.archive.md.

Removing the stub removes the guard, so the guard is REPLACED rather than deleted. The new
test is ARCHIVE MEMBERSHIP:

    is this item's id already present as a `- [x]` item line in the archive file?

That is a pure read of the archive, it cannot be defeated by the stub being absent, and it
dissolves the problem instead of guarding it. It is also STRICTLY STRONGER than the suffix
test, which is not a theoretical claim: measured in this repo 2026-09-03, SIX closed live
ROADMAP.md items (`1a03`, `098a`, `2065`, `55c7`, `71d6`, `ee31` — the em-dash migration
seams) sit in ROADMAP.archive.md with NO stub suffix on their live line, and each already
appears TWICE in the archive. The suffix test is blind to them and every further archiver
run would have appended a third copy. Membership catches them.

BACKWARD COMPATIBILITY. `LEGACY_STUB_LINE_RE` is retained as a SECOND, OR-ed keep signal —
never as a writer. Stubs written before this change still exist in this repo and across the
fleet (other repos run their own archivers, and loderite's tools/archive-roadmap.mjs still
emits the old convention), and a legacy stub whose id is somehow NOT in the archive must
still not be re-archived. Recognising it costs nothing and cannot cause a duplicate.

DO NOT hand-fix the em dash inside `LEGACY_STUB_SUFFIX`. It is SYNTAX, not prose: it is the
literal that fleet-mirrored archivers on both sides wrote, and changing it in isolation
silently stops matching real stubs — the `id:d35a` no-op class. It migrates only when every
mirrored copy migrates together.

Consumers load this by path (there is no package to import from — both callers are
`python3 - <<EOF` heredocs with no `__file__`):

    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "relay_lib_archive_idempotency", os.path.join(script_dir, "lib-archive-idempotency.py"))
    mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)

Same loading idiom as `lib-pool-runs.py` (id:6f62). Import failure is NOT swallowed: an
archiver that cannot load its idempotency test must fail loudly rather than run without one.
"""

import re

__all__ = [
    "ID_MARKER_RE",
    "TOP_DONE_RE",
    "LEGACY_STUB_SUFFIX",
    "LEGACY_STUB_LINE_RE",
    "item_id",
    "archived_ids",
    "already_archived",
]

# An anchored ledger id marker. Deliberately the SAME shape both archivers already used.
ID_MARKER_RE = re.compile(r'<!--\s*id:([0-9a-f]{4})\s*-->')

# A top-level (indent-0) DONE checkbox item line. Indent 0 is load-bearing: a closed
# checkbox nested inside another item's body is evidence, not an archived item, and must
# not seed the archived-id set.
TOP_DONE_RE = re.compile(r'^- \[[xX]\] ')

# ── LEGACY ONLY — no writer emits this any more (id:2eba). Read half retained. ──────────
LEGACY_STUB_SUFFIX = " (archived — see ROADMAP.archive.md)"
# The `.*` between the id marker and the suffix is LOAD-BEARING (cartulary 2026-08-14,
# routed:4a12): an item line may carry prose AFTER its own `<!-- id:XXXX -->` marker.
# NOT end-anchored, also deliberately: real stubs carry trailing annotations past the
# suffix (live examples bfb3/3d6c/a10c each carry a `**⚠ …`).
LEGACY_STUB_LINE_RE = re.compile(
    r'^- \[x\] .*<!--\s*id:[0-9a-f]{4}\s*-->.*' + re.escape(LEGACY_STUB_SUFFIX))


def item_id(line):
    """The anchored `<!-- id:XXXX -->` token on `line`, or None."""
    m = ID_MARKER_RE.search(line)
    return m.group(1) if m else None


def archived_ids(archive_path):
    """The set of ids that already own a top-level `- [x]` item line in `archive_path`.

    `archive_path` may be a str or a pathlib.Path. A missing or unreadable archive yields
    an EMPTY set, which is the correct fail-open answer: nothing has been archived yet, so
    nothing is a duplicate. (Fail-CLOSED here would refuse to archive anything the first
    time an archive file is created.)
    """
    ids = set()
    try:
        with open(str(archive_path), encoding='utf-8') as fh:
            text = fh.read()
    except (FileNotFoundError, IsADirectoryError, NotADirectoryError, PermissionError,
            UnicodeDecodeError):
        return ids
    for line in text.splitlines():
        if TOP_DONE_RE.match(line):
            tok = item_id(line)
            if tok:
                ids.add(tok)
    return ids


def already_archived(line, archived):
    """True when this live `- [x]` header line must NOT be archived (again).

    Two OR-ed signals:
      1. ARCHIVE MEMBERSHIP — the line's id already owns a `- [x]` line in the archive.
         This is the primary test and the only one that survives the stub's removal.
      2. LEGACY STUB — the line carries the pre-2026-09-03 stub suffix. Kept so a stub
         written by an older run (here, or by another repo's archiver) is never re-archived
         even if the archive somehow lost its copy.

    An item with NO id falls through to False on signal 1 by construction — it has no
    identity to look up, so it is archived on its own `- [x]` state, exactly as before.
    """
    if LEGACY_STUB_LINE_RE.match(line):
        return True
    tok = item_id(line)
    return tok is not None and tok in archived
