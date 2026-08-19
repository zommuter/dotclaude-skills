#!/usr/bin/env python3
"""
md-merge.py — flock'd key-based in-place merge for markdown files.

Prevents concurrent sessions from clobbering each other's edits by
re-reading the file under an exclusive flock before applying this
session's delta.

Usage:
    # Replace lines by <!-- id:XXXX --> token (for TODO.md)
    python3 md-merge.py update-ids --file <path>
    stdin: {"updates": [{"id": "XXXX", "line": "replacement line text"}]}
    # id:0af4 — or APPEND to the existing line instead of replacing it:
    stdin: {"updates": [{"id": "XXXX", "append": "text to add"}]}
    # id:f26d — or an in-lock REGEX_SUB transform (TOCTOU-free: applied to the line
    # as read UNDER the lock, not a literal composed before it):
    stdin: {"updates": [{"id": "XXXX", "regex_sub": {"pattern": "foo", "repl": "bar"}}]}
    # id:f26d — or INSERT a brand-new item beside an existing anchor id (fails loud,
    # no EOF fallback, if the anchor id is not found):
    stdin: {"updates": [{"id": "XXXX", "insert_after": "- [ ] new item <!-- id:YYYY -->"}]}
    stdin: {"updates": [{"id": "XXXX", "insert_before": "- [ ] new item <!-- id:YYYY -->"}]}

    # Replace ## section blocks by heading text (for user-profile.md)
    python3 md-merge.py update-sections --file <path>
    stdin: {"sections": [{"heading": "## Trait name", "content": "full replacement text incl heading"}]}

    # Optionally commit the file atomically under the same flock (id:148b):
    python3 md-merge.py update-ids --file <path> --commit "<commit message>"

Both subcommands:
- Acquire an exclusive flock on <path>.lock before reading/writing.
- Re-read the file under lock (picks up concurrent writes since delta was prepared).
- Write back atomically via tmp+rename.
- IDs / headings not found are appended at end of file.
- With --commit MSG (id:148b): while STILL holding the flock, commit just this file
  (scoped `git add -- <file>` + `git commit -- <file>`, never `git add -A`, never
  stash/reset — mirrors relay/scripts/commit-ledger.sh id:2147). Closes the scoop
  window: no modified-but-uncommitted ledger is left in the main checkout. Opt-in,
  idempotent (clean no-op when unchanged). PRE-staging git errors (not a repo, `git add`
  failed) are non-fatal — nothing was staged, so the write simply stays uncommitted.
  A FAILED COMMIT of an already-STAGED file is different (id:4b64): the write AND the
  staging are ROLLED BACK and md-merge exits non-zero, LOUDLY. A staged-and-abandoned
  ledger write is strictly worse than no write — it wedges the repo silently, because
  every later relay round's dirty-guard (id:aa93) defers a dirty main checkout.

Contract: two sessions editing different items/sections both survive;
same-item serializes with last-under-lock winning without clobbering others.
"""
from __future__ import annotations

import argparse
import fcntl
import json
import re
import subprocess
import sys
from pathlib import Path


def _atomic_write(path: Path, text: str) -> None:
    tmp = path.with_suffix(path.suffix + '.tmp')
    tmp.write_text(text)
    tmp.replace(path)


class LedgerCommitError(RuntimeError):
    """The --commit step STAGED the ledger but could NOT commit it (id:4b64).

    Raised only AFTER the write and the staging have been rolled back, so the repo is left
    exactly as it was found. LOUD by construction: md-merge exits non-zero.
    """


def _commit_ledger(file_path: Path, msg: str, pre_text: str | None = None) -> None:
    """Scoped, idempotent commit of JUST <file_path> in its repo's main checkout.

    Closes the scoop window (id:148b): without this the ledger is written but left
    modified-but-uncommitted, a window in which a relay integrator could scoop it (now
    also guarded by id:debf) or an interrupted run could strand dirty residue that trips
    the dirty-guard (id:aa93). Called WHILE the caller still holds the <file>.lock flock,
    so the write+commit pair is atomic w.r.t. other md-merge writers of the same file.

    Discipline mirrors relay/scripts/commit-ledger.sh (id:2147) — the load-bearing rules:
      - Stages ONLY this one file (`git add -- <file>`), NEVER `git add -A` (id:debf) —
        a concurrent edit to an UNRELATED file is left untouched.
      - NEVER `git stash` / `git checkout --` / `git reset` / `git clean` — it only ADDs
        and COMMITs the named file; foreign-dirty paths are never disturbed (id:aa93).
      - COMMIT-ONLY: never pushes (push is the caller's separate, later concern).
      - Clean no-op: if the named file has no staged change, makes NO commit (idempotent).
    PRE-staging git failures (not a repo, `git add` failed) are non-fatal: they print a
    warning and return — nothing was staged, so the atomic write simply stays uncommitted
    and the ledger edit is never lost.

    id:4b64 — a COMMIT that fails after a successful `git add` is NOT non-fatal. The file
    is then STAGED-but-uncommitted, and that residue silently wedges the repo: every later
    relay round's dirty-guard (id:aa93/id:2147) DEFERS a dirty main checkout, so the repo
    quietly stops being worked. Observed end-to-end in lodelore run
    relay-20260810-214130-15097, where the pre-commit lane-vocab ratchet rejected the
    handback auto-gate's old-vocab tag, `git commit` exited non-zero, and the run still
    reported `stopReason: drained`. So on a commit failure this function ROLLS BACK BOTH
    halves — the working-tree text (to `pre_text`, the content as of before this md-merge
    write) and the index entry (to the blob recorded before `git add`) — and then raises
    LedgerCommitError. Rollback restores a snapshot this process itself took while holding
    the flock; it never runs `git stash`/`checkout --`/`reset --hard`/`clean`, and never
    touches any path other than this one file.
    """
    file_path = file_path.resolve()

    def _git(*args: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            ['git', '-C', str(file_path.parent), *args],
            capture_output=True, text=True,
        )

    top = _git('rev-parse', '--show-toplevel')
    if top.returncode != 0:
        print(f'md-merge: --commit skipped — {file_path} is not in a git repo '
              '(write succeeded, left uncommitted)', file=sys.stderr)
        return
    repo = Path(top.stdout.strip())
    try:
        rel = str(file_path.relative_to(repo))
    except ValueError:
        rel = str(file_path)

    # Snapshot the PRE-`git add` index entry for this one path, so a failed commit can put
    # the index back exactly as it was (id:4b64). Empty output == the path was not in the
    # index at all (untracked) → the rollback un-stages it entirely.
    ls = _git('ls-files', '--stage', '--', rel)
    index_entry = ls.stdout.strip() if ls.returncode == 0 else ''

    add = _git('add', '--', rel)
    if add.returncode != 0:
        print(f'md-merge: --commit skipped — git add failed for {rel}: '
              f'{add.stderr.strip()} (write succeeded, left uncommitted)', file=sys.stderr)
        return

    # Clean no-op if nothing staged for this file (idempotent).
    if _git('diff', '--cached', '--quiet', '--', rel).returncode == 0:
        return

    commit = _git('commit', '-m', msg, '--', rel)
    if commit.returncode != 0:
        # id:4b64 — roll back BOTH halves, then fail LOUD. Never leave the ledger staged.
        rollback_notes = []
        if pre_text is not None:
            try:
                _atomic_write(file_path, pre_text)
            except OSError as e:                      # pragma: no cover — disk-level failure
                rollback_notes.append(f'working-tree restore FAILED: {e}')
        else:
            rollback_notes.append('working-tree text NOT restored (no pre-write snapshot '
                                  'passed by the caller)')
        if index_entry:
            # "<mode> <sha> <stage>\t<path>" → put that exact blob back in the index.
            head, _, entry_path = index_entry.partition('\t')
            parts = head.split()
            if len(parts) >= 2:
                undo = _git('update-index', '--cacheinfo',
                            f'{parts[0]},{parts[1]},{entry_path or rel}')
                if undo.returncode != 0:
                    rollback_notes.append(f'index restore FAILED: {undo.stderr.strip()}')
        else:
            # Not in the index before → drop the entry `git add` created. `update-index
            # --force-remove` touches ONLY the index (never the working tree), unlike
            # `git rm`, which also refuses on staged-vs-HEAD divergence.
            undo = _git('update-index', '--force-remove', '--', rel)
            if undo.returncode != 0:
                rollback_notes.append(f'un-stage FAILED: {undo.stderr.strip()}')
        note = ('; '.join(rollback_notes)) if rollback_notes else 'write + staging rolled back'
        raise LedgerCommitError(
            f'--commit failed for {rel}: {commit.stderr.strip() or commit.stdout.strip()} '
            f'({note}) — REFUSING to leave a staged-but-uncommitted ledger (id:4b64)')


# id:14d0 — archive-class headings a brand-new (not-found) id must never land under.
# A NEW item is open work; appending it at EOF misfiles it under a trailing Done/
# Archive/Icebox section. Matched case-insensitively against `##`+ headings.
_ARCHIVE_HEADING_RE = re.compile(r'^#{2,}\s+(done|archive|icebox)\b', re.IGNORECASE)

# id:0af4 — mirrors relay/scripts/lib-anchored-id.sh's ANCHORED_ID_MARKER_RE
# ('<!--[[:space:]]*id:([0-9a-fA-F]{4})[[:space:]]*-->') so a REPLACEMENT line's
# own id marker is recognised with the exact same grammar the rest of the relay
# tooling uses — do not invent a looser/stricter pattern here.
_ID_MARKER_RE = re.compile(r'<!--\s*id:([0-9a-fA-F]{4})\s*-->')


class AmbiguousOwnId(Exception):
    """A line carries MORE THAN ONE `<!-- id:XXXX -->` marker, so its own id cannot be
    resolved under the current grammar. Raised instead of guessing (id:6059)."""


def _own_id_match_of_line(line: str) -> "re.Match | None":
    """The re.Match for the line's OWN `<!-- id:XXXX -->` marker, or None if it has none.

    Raises AmbiguousOwnId when the line carries several. id:cc7e / id:6059 — this used to
    be `_ID_MARKER_RE.search(...)`, i.e. a silent FIRST-match guess, and last-match is no
    better: `<!-- id:X -->` means BOTH "this line IS X" and "this line REFERS to X" with
    identical syntax, and the two shapes put the own id at OPPOSITE ends —

      body QUOTES a marker  → own id LAST  (this repo: TODO.md's `id:f346` item)
      TRAILING reference    → own id FIRST (loderite ROADMAP.md L211/L229/L628,
                              routed:3ad9: three OPEN items ending
                              `<!-- id:XXXX --> <!-- id:50f3 -->`, 50f3 CLOSED)

    Either positional rule silently mis-attributes one shape, and on `update-ids` — a
    WRITE path — a mis-attribution rewrites the WRONG item with no error. So this refuses.
    A LOUD "ambiguous, refusing" is the correct outcome for such a line; the reported
    "unmatched id(s) not found in TODO.md: 7756" (2026-08-14) becomes an explicit
    ambiguity report instead. The durable fix is a define-vs-refer grammar (routed:20ce /
    cartulary id:344d), not decided here.

    Append mode (id:0af4) re-anchors around the marker's span, so it needs the match
    object, not just the token.
    """
    ms = list(_ID_MARKER_RE.finditer(line))
    if len(ms) > 1:
        raise AmbiguousOwnId(', '.join(m.group(1) for m in ms))
    return ms[0] if ms else None


def _own_id_of_line(line: str) -> str | None:
    """The line's OWN id token, or None. Raises AmbiguousOwnId (see above)."""
    m = _own_id_match_of_line(line)
    return m.group(1) if m else None

# A checkbox item line starts with `- [ ]` or `- [x]`/`- [X]`.
_CHECKBOX_RE = re.compile(r'^- \[[ xX]\]')


def _validate_replacement(item_id: str, target_line: str, new_line: str) -> str | None:
    """Return an error string if `new_line` is not a safe replacement for the
    line currently holding `<!-- id:<item_id> -->`, else None.

    id:0af4 — two guards, both required BEFORE anything is written:
      1. the replacement must carry that SAME id's own anchored marker (a
         replacement that silently drops/changes the marker orphans the item);
      2. if the target line is a checkbox item, the replacement must be one
         too (this is the exact shape of the 1400-char-wipe payload that
         motivated this item — a partial fragment passed as a full-line
         replacement for a checkbox item).
    The checkbox rule is conditional on the TARGET's shape only: a non-checkbox
    id-bearing line (e.g. a `## heading <!-- id:XXXX -->`) may still be replaced
    by another non-checkbox line.
    """
    # id:cc7e/id:6059 — the replacement is resolved by the SAME rule as the target line:
    # exactly one own marker, or a loud refusal. A replacement carrying two markers would
    # make the line it writes un-addressable on the next pass.
    try:
        nm = _own_id_of_line(new_line)
    except AmbiguousOwnId as amb:
        return (f'replacement for id:{item_id} carries several anchored id markers '
                f'({amb}) — the resulting line would be un-addressable (id:6059); '
                f'de-literalise the quoted marker or use a typed edge')
    if nm is None or nm.lower() != item_id.lower():
        return (f'replacement for id:{item_id} is missing that id\'s own '
                f'<!-- id:{item_id} --> marker')
    if _CHECKBOX_RE.match(target_line.rstrip('\n')) and not _CHECKBOX_RE.match(new_line):
        return (f'replacement for id:{item_id} targets a checkbox item '
                f'(- [ ]/- [x]) but the replacement is not one')
    return None


def _final_line_marker_error(where: str, final_line: str) -> str | None:
    """WRITE-SIDE guard (id:6059). Return an error string if `final_line` is a ledger
    ITEM line (`- [ ]` / `- [x]`) that would be written with a number of anchored
    `<!-- id:XXXX -->` markers other than exactly one, else None.

    This is the deliberate twin of the read-side refusal, not a duplicate of it: the
    read side refuses to INTERPRET an ambiguous line, this side refuses to CREATE one.
    Both are needed because `update-ids` is itself a path that echoes marker syntax into
    prose. Loderite reproduced exactly that on 2026-08-14 while trying to REPAIR the
    hazard: its de-ambiguation note QUOTED literal markers to describe the problem, so
    "fixed" lines went from 2 markers to 3 — a de-ambiguation annotation cannot safely
    quote the syntax it is de-ambiguating.

    ORDERING IS THE POINT: call this on the FINAL composed line, after any append/
    annotation has been spliced in. Loderite's guard checked the replacement line and
    THEN appended the note, so it passed while the written result was wrong.

    COUNT, never a set: loderite also carries a pre-existing `<!-- id:466d -->
    <!-- id:466d -->` — the SAME id twice. A dedup/set-based check calls that fine; a
    count catches it.

    Non-item lines (prose, headings, sub-bullets) are out of scope — they legitimately
    discuss markers.
    """
    stripped = final_line.rstrip('\n')
    if not _CHECKBOX_RE.match(stripped):
        return None
    ms = _ID_MARKER_RE.findall(stripped)
    if len(ms) == 1:
        return None
    if not ms:
        return (f'{where}: REFUSING to write a ledger item line with NO anchored '
                f'<!-- id:XXXX --> marker (id:6059) — the item would be unaddressable')
    return (f'{where}: REFUSING to write a ledger item line carrying {len(ms)} anchored '
            f'id markers ({", ".join(ms)}) (id:6059) — the written line would be '
            f'AMBIGUOUS ("this line IS X" vs "this line REFERS to X" are spelled the '
            f'same). A de-ambiguation note must NOT quote the marker syntax it '
            f'describes; de-literalise it or use a typed edge.')


def _append_to_line(line: str, marker_match: re.Match, append_text: str) -> str:
    """Append `append_text` to `line` (sans trailing newline), preserving every
    byte of the original content and re-anchoring the id marker as the LAST
    thing on the line (id:0af4 append mode)."""
    prefix = line[:marker_match.start()].rstrip()
    marker = marker_match.group(0)
    suffix = line[marker_match.end():]
    text = append_text.strip()
    body = f'{prefix} {text}' if text else prefix
    return f'{body} {marker}{suffix}'


def _first_archive_heading_index(result: list) -> int | None:
    """Index into `result` of the first archive-class heading line, or None."""
    for i, line in enumerate(result):
        if _ARCHIVE_HEADING_RE.match(line.rstrip('\n')):
            return i
    return None


def update_ids(file_path: Path, updates: list, commit_msg: str | None = None,
               allow_new: bool = False) -> None:
    """Replace (or append to, or in-lock-transform) lines containing
    <!-- id:XXXX -->, and/or insert new lines relative to an anchor id — under flock.

    id:1b1a — an id NOT found in the file is a fail-LOUD error by default (a typo'd
    UPDATE must never silently become a duplicate APPEND). Pass allow_new=True to
    opt back into the append behaviour for genuinely new items.

    Each update is one of:
      - REPLACE  {"id", "line"} — whole-line overwrite. TOCTOU-prone: the caller
        must compose `line` from a read taken OUTSIDE this lock, so a concurrent
        in-lock write to the SAME id between that read and this call is silently
        clobbered (last-under-lock wins). Prefer append/regex_sub below when the
        edit can be expressed as a transform instead of a fresh literal.
      - APPEND   {"id", "append"} (id:0af4) — preserves the existing line and adds
        text before its id marker. TOCTOU-free: computed from the line as read
        UNDER this lock.
      - REGEX_SUB {"id", "regex_sub": {"pattern", "repl"}} (id:f26d) — applies
        `re.sub(pattern, repl, line)` to the line as read UNDER this lock. The
        general in-lock transform: unlike REPLACE it never depends on a pre-lock
        read, so two concurrent regex_sub calls against the SAME id both apply,
        each against whatever the other already wrote, instead of the second
        clobbering the first.
      - INSERT   {"id": "<anchor id>", "insert_before"|"insert_after": "<new line>"}
        (id:f26d) — places a brand-new item line immediately before/after the line
        whose OWN id marker is <anchor id>. The anchor is looked up under this same
        lock (also TOCTOU-free). An anchor id not present in the file is a fail-LOUD
        error, same class as id:1b1a's unmatched-id guard — it never silently falls
        back to an EOF append, because EOF is the wrong place for a seam that must
        sit beside its siblings.
    """
    lock_path = file_path.with_suffix(file_path.suffix + '.lock')
    # id:5d7e — ops are held as an ORDERED LIST PER ID, never one dict per op-class.
    # The previous shape (replace_map / append_map / regex_sub_map + an if/elif/elif
    # chain) dropped work SILENTLY in two ways and still exited 0: across classes only
    # one bucket could win per id, and within a class a dict overwrite kept the last.
    # Observed live: a payload of 2 regex_sub ticks + 2 appends applied only the appends,
    # leaving two ledger lines that READ as done-and-annotated with an open checkbox.
    # Semantic: COMPOSE every op for an id, in payload order (see the fold below).
    ops_by_id = {}          # id -> ordered [(kind, payload), ...]
    replace_map = {}        # id -> line, for the --allow-new EOF path only
    regex_sub_ids = set()   # ids carrying >=1 regex_sub, for the unmatched guard
    insert_ops = []  # ordered [(anchor_id, 'before'|'after', new_line_text), ...]
    for u in updates:
        item_id = u['id']
        if 'insert_before' in u:
            insert_ops.append((item_id, 'before', u['insert_before'].rstrip('\n')))
            continue
        if 'insert_after' in u:
            insert_ops.append((item_id, 'after', u['insert_after'].rstrip('\n')))
            continue
        if 'append' in u:
            kind, payload = 'append', u['append']
        elif 'regex_sub' in u:
            kind, payload = 'regex_sub', u['regex_sub']
            regex_sub_ids.add(item_id)
        else:
            kind, payload = 'line', u['line'].rstrip('\n')
            replace_map[item_id] = payload
        ops_by_id.setdefault(item_id, []).append((kind, payload))
    # union, for the unmatched/new-item path below (insert anchors are tracked
    # separately — they name a POSITION, not an id to overwrite, and must fail
    # loud rather than fall into the --allow-new EOF-append path).
    id_map = {k: replace_map.get(k) for k in ops_by_id}
    insert_anchor_ids = {op[0] for op in insert_ops}

    try:
        with open(lock_path, 'w') as lock_fd:
            fcntl.flock(lock_fd, fcntl.LOCK_EX)

            pre_text = file_path.read_text()   # id:4b64 rollback snapshot (under lock)
            lines = pre_text.splitlines(keepends=True)
            found = set()
            found_anchor = set()
            anchor_index = {}   # anchor id -> index of its (post-edit) line in `result`
            result = []
            errors = []

            for lineno, line in enumerate(lines, start=1):
                # id:cc7e/id:6059 — a line carrying SEVERAL anchored id markers is
                # AMBIGUOUS under the current grammar (define vs refer are spelled
                # identically). Never guess a position. If any pending update names one
                # of its candidate ids, that is a refusal WITH the reason; otherwise the
                # line is simply not addressable and passes through untouched.
                try:
                    m = _own_id_match_of_line(line)
                except AmbiguousOwnId as amb:
                    cands = [c.lower() for c in str(amb).split(', ')]
                    hit = [c for c in cands if c in id_map or c in insert_anchor_ids]
                    if hit:
                        errors.append(
                            f'{file_path}:{lineno}: AMBIGUOUS own id — line carries '
                            f'{len(cands)} anchored id markers ({", ".join(cands)}) and '
                            f'the grammar cannot tell "this line IS X" from "this line '
                            f'REFERS to X"; REFUSING to update {", ".join(hit)} here '
                            f'(id:6059). De-literalise the quoted marker, or spell the '
                            f'reference as a typed edge, then retry.')
                    result.append(line)
                    continue
                if m is None:
                    # No anchored marker at all: this line addresses no id. It is not an
                    # error (most lines are prose) — it simply passes through, and `m` is
                    # never handed to a consumer that assumes a match.
                    result.append(line)
                    continue
                item_id = m.group(1).lower()
                if item_id in ops_by_id:
                    # id:5d7e — FOLD every op for this id, in payload order. `composed`
                    # carries forward, so a regex_sub sees what an earlier append wrote
                    # and vice versa. Validation runs ONCE, on the final text (id:6059:
                    # compose first, then validate what will actually be written — an
                    # appended annotation that quotes marker syntax is the exact way
                    # loderite manufactured a 3-marker line while "repairing" a 2-marker
                    # one, and checking any intermediate would pass while the written
                    # result was wrong).
                    found.add(item_id)
                    composed = line.rstrip('\n')
                    op_err = None
                    for kind, payload in ops_by_id[item_id]:
                        if kind == 'line':
                            # Full replacement is validated against the ORIGINAL line —
                            # that is what _validate_replacement's contract compares.
                            op_err = _validate_replacement(item_id, line, payload)
                            if op_err:
                                break
                            composed = payload
                        elif kind == 'append':
                            # Re-locate the marker on the CURRENT text: an earlier
                            # regex_sub may have shifted or rewritten it, so the match
                            # captured before the fold is stale.
                            try:
                                cm = _own_id_match_of_line(composed + '\n')
                            except AmbiguousOwnId as amb:
                                op_err = (f'append: composed line became ambiguous '
                                          f'({amb}) — refusing (id:6059)')
                                break
                            if cm is None:
                                op_err = ('append: composed line no longer carries its '
                                          'own id marker — refusing')
                                break
                            composed = _append_to_line(composed, cm, payload)
                        elif kind == 'regex_sub':
                            # id:f26d — TOCTOU-free in-lock transform: the input is the
                            # content as read UNDER this flock (or as composed by an
                            # earlier op here), never a caller-supplied literal computed
                            # before the lock.
                            try:
                                composed = re.sub(payload['pattern'], payload['repl'],
                                                  composed)
                            except re.error as e:
                                op_err = f'regex_sub: invalid pattern: {e}'
                                break
                    if op_err is None:
                        op_err = _final_line_marker_error(f'{file_path}:{lineno}', composed)
                    if op_err:
                        errors.append(f'id:{item_id}: {op_err}')
                        line_to_write = line  # placeholder; discarded, errors is non-empty
                    else:
                        line_to_write = composed + '\n'
                else:
                    line_to_write = line
                result.append(line_to_write)
                if item_id in insert_anchor_ids:
                    # id:f26d — anchor located under the SAME lock as everything else;
                    # position recorded post-edit so an insert lands beside the anchor's
                    # FINAL content, not a stale pre-lock snapshot of it.
                    found_anchor.add(item_id)
                    anchor_index[item_id] = len(result) - 1

            unmatched_regex_sub = sorted(regex_sub_ids - found)
            if unmatched_regex_sub:
                # regex_sub transforms an EXISTING line; there is no "new" line to
                # invent for a missing id, so this fails loud unconditionally —
                # --allow-new does not apply here (unlike replace/append, id:1b1a).
                errors.append(
                    'regex_sub id(s) not found (nothing to transform): '
                    f'{", ".join(unmatched_regex_sub)}')

            missing_anchors = sorted(a for a in insert_anchor_ids if a not in found_anchor)
            if missing_anchors:
                # id:f26d — an insert anchor that doesn't exist fails LOUD, exactly like
                # id:1b1a's unmatched-id guard: it must NEVER silently fall back to an
                # EOF append (that is the defect this item exists to close — a seam
                # inserted at EOF instead of beside its siblings).
                errors.append(
                    'insert anchor id(s) not found (no EOF fallback — insert requires '
                    f'a real anchor): {", ".join(missing_anchors)}')

            insert_errors = [
                e for e in (
                    _final_line_marker_error(
                        f'{file_path}:<insert {pos} id:{anchor_id}>', text)
                    for anchor_id, pos, text in insert_ops
                ) if e
            ]
            errors.extend(insert_errors)

            if errors:
                # id:0af4 — a malformed replacement is refused BEFORE anything is
                # written, exactly like id:1b1a's unmatched-id guard below: name every
                # offending id and what was wrong, write NOTHING.
                print(
                    'md-merge: update-ids: refusing malformed replacement(s) for '
                    f'{file_path}:\n  ' + '\n  '.join(errors),
                    file=sys.stderr,
                )
                sys.exit(1)

            if insert_ops:
                # id:f26d — compute each insertion's position against the PRE-insert
                # `result` (anchor_index), then apply left-to-right with a running
                # offset so earlier insertions shift later ones correctly, and ties
                # (same anchor+side) land in the order they were given rather than
                # reversed.
                targets = [
                    (anchor_index[anchor_id] + (1 if pos == 'after' else 0), i, text)
                    for i, (anchor_id, pos, text) in enumerate(insert_ops)
                ]
                offset = 0
                for at, _, text in sorted(targets, key=lambda t: (t[0], t[1])):
                    result[at + offset:at + offset] = [text + '\n']
                    offset += 1

            unmatched = [item_id for item_id in id_map if item_id not in found]
            if unmatched and not allow_new:
                # Fail LOUD, write NOTHING (id:1b1a) — a mistyped id must never
                # silently become a duplicate appended line.
                print(
                    'md-merge: update-ids: unmatched id(s) not found in '
                    f'{file_path}: {", ".join(sorted(unmatched))} '
                    '(pass --allow-new to append as new items)',
                    file=sys.stderr,
                )
                sys.exit(1)

            def _new_line_text(item_id: str) -> str:
                # id:5d7e — derive a brand-new item's text from its ordered ops: a full
                # `line` if one was given, else the first `append` payload (the pre-5d7e
                # behaviour). A regex_sub cannot invent a line, and an unmatched one has
                # already failed loud above, so it is never reached here.
                if item_id in replace_map:
                    return replace_map[item_id].rstrip('\n') + '\n'
                for kind, payload in ops_by_id.get(item_id, []):
                    if kind == 'append':
                        return payload.rstrip('\n') + '\n'
                return '\n'

            new_lines = [_new_line_text(item_id) for item_id in unmatched]
            # id:6059 — --allow-new appends brand-new item lines verbatim, so the
            # write-side guard applies here too: a NEW item may not be born ambiguous.
            new_errors = [
                e for e in (
                    _final_line_marker_error(f'{file_path}:<new item {item_id}>', nl)
                    for item_id, nl in zip(unmatched, new_lines)
                ) if e
            ]
            if new_errors:
                print(
                    'md-merge: update-ids: refusing new item line(s) for '
                    f'{file_path}:\n  ' + '\n  '.join(new_errors),
                    file=sys.stderr,
                )
                sys.exit(1)
            if new_lines:
                # id:14d0 — anchor brand-new ids BEFORE the first archive-class
                # heading (Done/Archive/Icebox); EOF append is the fallback only
                # when no such heading exists. Existing-id replacements above are
                # untouched (in-place, position preserved).
                anchor = _first_archive_heading_index(result)
                if anchor is None:
                    result.extend(new_lines)
                else:
                    result[anchor:anchor] = new_lines

            _atomic_write(file_path, ''.join(result))
            # id:148b — atomic write+commit under the SAME flock (scoop-window close).
            if commit_msg is not None:
                _commit_ledger(file_path, commit_msg, pre_text)
    finally:
        lock_path.unlink(missing_ok=True)


def update_sections(file_path: Path, sections: list, commit_msg: str | None = None) -> None:
    """Replace ## section blocks by heading, under flock."""
    lock_path = file_path.with_suffix(file_path.suffix + '.lock')
    # Normalise: heading key stripped, content ends with exactly one newline
    section_map = {
        s['heading'].strip(): s['content'].rstrip('\n') + '\n'
        for s in sections
    }

    try:
        with open(lock_path, 'w') as lock_fd:
            fcntl.flock(lock_fd, fcntl.LOCK_EX)

            pre_text = file_path.read_text()   # id:4b64 rollback snapshot (under lock)
            lines = pre_text.splitlines(keepends=True)
            found = set()
            result = []
            i = 0

            while i < len(lines):
                line = lines[i]
                m = re.match(r'^(#{2,})\s+(.+)', line.rstrip('\n'))
                if m:
                    heading = m.group(1) + ' ' + m.group(2).strip()
                    # Collect body up to next ## heading or EOF (j points at next heading)
                    j = i + 1
                    while j < len(lines) and not re.match(r'^#{2,}\s+', lines[j]):
                        j += 1
                    if heading in section_map:
                        found.add(heading)
                        new_content = section_map[heading]
                        result.append(new_content)
                        # Preserve blank line before next heading if the replacement doesn't end with one
                        if j < len(lines) and not new_content.endswith('\n\n'):
                            result.append('\n')
                    else:
                        result.extend(lines[i:j])
                    i = j
                else:
                    result.append(line)
                    i += 1

            for heading, new_content in section_map.items():
                if heading not in found:
                    if result and not result[-1].endswith('\n'):
                        result.append('\n')
                    result.append('\n' + new_content)

            _atomic_write(file_path, ''.join(result))
            # id:148b — atomic write+commit under the SAME flock (scoop-window close).
            if commit_msg is not None:
                _commit_ledger(file_path, commit_msg, pre_text)
    finally:
        lock_path.unlink(missing_ok=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='cmd')

    p_ids = sub.add_parser('update-ids', help='Replace lines by <!-- id:XXXX --> (for TODO.md)')
    p_ids.add_argument('--file', required=True, help='Path to the markdown file')
    p_ids.add_argument('--commit', metavar='MSG',
                       help='id:148b — after the write, commit JUST this file under the same '
                            'flock with MSG (scoped `git add -- <file>`, never `git add -A`). '
                            'Opt-in; idempotent (clean no-op if unchanged); non-fatal on git error.')
    p_ids.add_argument('--allow-new', action='store_true',
                       help='id:1b1a — opt in to appending ids not found in the file '
                            '(default: an unmatched id fails LOUD and writes nothing).')

    p_sec = sub.add_parser('update-sections', help='Replace ## section blocks by heading (for user-profile.md)')
    p_sec.add_argument('--file', required=True, help='Path to the markdown file')
    p_sec.add_argument('--commit', metavar='MSG',
                       help='id:148b — after the write, commit JUST this file under the same flock '
                            'with MSG (scoped add). Opt-in; idempotent; non-fatal on git error.')

    args = parser.parse_args()

    try:
        delta = json.load(sys.stdin)
    except json.JSONDecodeError as e:
        print(f'md-merge: invalid JSON on stdin: {e}', file=sys.stderr)
        sys.exit(1)

    # id:4b64 — a staged-but-uncommittable ledger is rolled back and reported LOUDLY here
    # (exit 3), never swallowed: the caller (e.g. handback-followup.py → relay-loop.js)
    # must see the failure instead of a silently wedged repo.
    try:
        if args.cmd == 'update-ids':
            update_ids(Path(args.file), delta.get('updates', []), getattr(args, 'commit', None),
                       getattr(args, 'allow_new', False))
        elif args.cmd == 'update-sections':
            update_sections(Path(args.file), delta.get('sections', []), getattr(args, 'commit', None))
        else:
            parser.print_help()
            sys.exit(1)
    except LedgerCommitError as e:
        print(f'md-merge: {e}', file=sys.stderr)
        sys.exit(3)


if __name__ == '__main__':
    main()
