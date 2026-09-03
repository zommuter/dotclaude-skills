# id:2eba

Authored directly (not relocated by `tools/ledger-shrink.py`).

## From TODO

Measured 2026-09-03 while looking for the largest remaining trim in `ROADMAP.md`, after the
`id:0d7c` shrinker was found to be nearly exhausted at its ratified 500-char budget
(a full `--apply` pass recovered only 216 chars from `ROADMAP.md` and 4,727 from `TODO.md`).

### The measurement

`ROADMAP.md` is **71,572 bytes**. Of that, **62 archive-stub lines account for 26,101 bytes
-- 36% of the file.** Every one is a CLOSED item that has already been moved to
`ROADMAP.archive.md`, and the stub retains the item's full lane tag, title and detail pointer:

```
- [x] [ROUTINE] Review→execute chaining within a pool — **emit a `review→execute re-enqueue`
  EVENT into `relay-events.jsonl`** -- detail: `docs/ledger-notes/b8ae.md` <!-- id:b8ae -->
  (archived — see ROADMAP.archive.md)
```

A minimal stub carrying only what the machinery needs -- `- [x] <!-- id:XXXX --> (archived --
see ROADMAP.archive.md)`, roughly 58 bytes -- would still satisfy `roadmap-archive.sh`'s
`stub_line_re` (`^- \[x\] .*<!--\s*id:[0-9a-f]{4}\s*-->.*` + `STUB_SUFFIX`). At 62 stubs
averaging 421 bytes, that is **~22.5 KB, about 31% of `ROADMAP.md`**.

**This is the single largest remaining trim available in `ROADMAP.md`.**

### What this is NOT -- a claim I made and had to withdraw

I first characterised the stubs as byte-identical duplicates of their archived copies. **That
is false in general.** `id:5f34`'s live and archived lines are identical; `id:b8ae`'s are
not -- the archived copy is LONGER (281 vs 189 bytes), retaining a re-laning annotation the
stub drops. So the stubs are not redundant copies, and the saving is not "delete duplicated
bytes". It is a deliberate trade, which is why this is filed rather than done.

### The trade, stated honestly

**For shortening:** 31% of the execution queue is closed work. The `id:b048` grammar and the
`id:0d7c` ratchet both measure head lines, so this mass is counted against every budget while
carrying no open work.

**Against:** the stub's title is what a human scanning `ROADMAP.md` sees as "recently done".
Reducing it to a bare id means the live file no longer answers "what shipped lately" without
opening the archive. The archive stub exists precisely so archiving is not invisible.

**Also against, and this is the load-bearing one:** the stub is `roadmap-archive.sh`'s
IDEMPOTENCY GUARD (`:114`), not decoration -- see `id:d05d`. Any change to its shape touches
a regex that is deliberately mirrored into loderite's `tools/archive-roadmap.mjs`, so it is a
CROSS-REPO change and must land in both or the two archivers will re-archive each other's
output. `id:d05d` records the fleet incidents from getting this wrong (loderite `id:154a`:
59 stubs restored, 58 deleted 12 minutes later in the same run).

### Interaction with `id:d05d`, decided the same day

`d05d` ruled that the grammar EXEMPTS the stub suffix rather than moving it. That ruling is
about the suffix's POSITION and is unaffected by this item, which is about the stub's LENGTH.
They are independent and can land in either order -- but both touch the same mirrored regex,
so they should be planned together rather than discovered by whoever goes second.

### Alternative worth weighing

A third option neither shortens nor keeps: **stop leaving a stub at all**, and let
`orphan-scan --cross-ledger` read the archive. `d05d` records why that was rejected for the
suffix (the guard) -- but the guard could live in the archive file instead. Not proposed,
only noted so the option set is complete.

- **Acceptance**: a DECISION on whether the archive stub keeps its title. If shortened: the
  new shape, the migration of the 62 existing stubs, and the coordinated change in loderite's
  `tools/archive-roadmap.mjs`.

- **Done-check**: the decision is recorded; if shortened, `roadmap-archive.sh` and its
  loderite mirror agree, `tests/` pins the new shape, and re-running the archiver over an
  already-archived ledger is still a no-op (the idempotency property `d05d` protects).

## DECIDED 2026-09-03 -- owner-ratified: stop leaving a stub at all

**Header declaration: this section was APPENDED 2026-09-03; nothing above was altered. This
note was authored directly and carries no "reproduced verbatim" claim.**

The owner picked the third option this note listed as "not proposed, only noted so the option
set is complete". Delivered:

- **Both writers stop emitting the stub.** `relay/scripts/roadmap-archive.sh` and
  `relay/scripts/archive-closed.sh` now remove an archived item from its live ledger entirely.
  `archive-closed.sh`'s ROADMAP path no longer differs from its TODO / REVIEW_ME paths.
- **The idempotency guard was REPLACED before being removed.** The test is now ARCHIVE
  MEMBERSHIP -- "is this id already a `- [x]` item line in the matching `*.archive.md`?" --
  defined ONCE in `relay/scripts/lib-archive-idempotency.py` and imported by both writers
  (`id:4983`: one source, not a third hand-mirrored copy). The pre-2026-09-03 stub suffix is
  retained there as a second, OR-ed READ signal so legacy stubs are never re-archived.
- **Membership is strictly stronger than the suffix test, measured not asserted.** Six closed
  live `ROADMAP.md` items (`1a03 098a 2065 55c7 71d6 ee31`, the em-dash migration seams) sit
  in `ROADMAP.archive.md` with no stub on their live line and are ALREADY duplicated twice in
  the archive. The suffix test was blind to them; every further archiver run appended another
  copy. Membership catches them, refuses, and says so on stderr.
- **The 62 stub lines were deleted** after verifying, per id, that each is present as a
  `- [x]` line in `ROADMAP.archive.md` (62 of 62; none refused). `ROADMAP.md` 70,791 ->
  44,959 bytes.
- **`orphan-scan --cross-ledger` is unaffected**: `routed:42c9` already reads
  `ROADMAP.md` UNION `ROADMAP.archive.md` on every leg that matters. `roadmap-lint.sh`'s
  DEAD-GATE and ANSWER-SRC rules were NOT, and went blind the moment the stubs went (two
  false DEAD-GATE warnings, `6446`->`f391` and `8524`->`1608`); they gained the same widening.
- **The `routed:71ed` ambiguous-body deferral is now TOTAL.** It used to archive the header,
  stub it, and retain the body -- a split that relied on the stub to hold the retained body
  apart from the live bullet above it. Without a stub the body would silently re-attach to
  that neighbour, which is the guessing `71ed` exists to refuse, so the archiver now refuses
  the whole item and leaves header and body live. Still a fixed point, still loud.
