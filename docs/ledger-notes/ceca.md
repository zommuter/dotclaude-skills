# id:ceca

Authored directly, not relocated by `tools/ledger-shrink.py`. Conventions:
`docs/ledger-notes/README.md`.

## From ROADMAP

**The parked `id:4d65` attempt is one assertion short of green, and the failing assertion is
a REGRESSION it introduces, not an unimplemented half.** Found 2026-09-07 during a
`/relay reconcile --all` sweep, on the parked branch
`relay/orphan/relay-20260905-113859-5807-execute-repo-0` (commit `e3762d03`, a `id:f272`
commit-and-park "WIP UNVERIFIED residue" auto-commit: `relay/scripts/ratify-queue.sh` +77
lines, plus a new 193-line `tests/test_ratify_queue_self_verify.sh`).

**Measured** by running that test file in a detached worktree of the branch: **11 assertions
PASS, 1 FAILS.** The suite completes normally (no hang, unlike the sibling residue in
`id:be51`).

The passing set is substantive and covers `id:4d65`'s acceptance closely: a self-verified
landed entry is excluded from the default pending listing; a still-unpushed neighbour still
reports pending; the pending COUNT reflects only the genuinely-outstanding entry; `list --all`
still shows the landed entry and distinguishes it as self-verified LANDED; `list --tsv` emits
no box for it; **the queue file is byte-identical after `list`/`list --all`/`list --tsv`** (the
no-mutation invariant `id:4d65` insists on); the landed entry's stored status is STILL
`pending`, so `resolve` remains the only writer; and `resolve` still succeeds afterwards.

The one failure:

```
FAIL: list --tsv lost the genuinely-pending neighbour: beta ... ratification_pending
      [RATIFY id:4d44] ... (merged=8da29e395408 ckpt=relay-ckpt-20260902-1100
      ids=id:aaaa,id:bbbb bump=none age=4d): closed the thing
```

**Read the direction of that failure carefully, because it inverts the item's purpose.**
`id:4d65` asks `list` to stop reporting an *already-landed* entry as pending. The branch's
`--tsv` path instead drops a **genuinely-pending** entry -- the one case that must always be
reported. A ratification queue that silently omits an outstanding push is worse than one that
over-reports, because the entry's whole function is to be the reminder that an owner push is
still owed. `--tsv` is the machine-readable surface, so a consumer would see a clean queue.

**Why this is worth a ledger line rather than only a commit message.** The branch is the only
artifact carrying both the 193-line test and this measurement, and it is parked pending a
park-or-discard call. The test is reusable independently of whether the +77 lines of
implementation are: it encodes `id:4d65`'s acceptance, including the no-mutation invariant,
as executable assertions.

**What this does NOT establish.** No root cause -- the failing `--tsv` filter was not read or
localized. Nothing was checked about the branch's behaviour against a real remote (the test
drives fixtures). And the 11 passes were not independently re-derived against the original
`id:4d65` acceptance text; they are the branch author's own assertions passing, which is
exactly the "one agent wrote both code and test" shape that does not by itself constitute
verification.

**Acceptance**: `ratify-queue.sh list --tsv` emits every genuinely-pending entry (no
regression on the neighbour above) while still omitting a remote-confirmed landed one, and
the queue file stays byte-identical across all `list` forms. **Done-check**:
`bash tests/test_ratify_queue_self_verify.sh` reports 12 PASS / 0 FAIL.

**Context**: `relay/scripts/ratify-queue.sh`, `tests/test_ratify_queue_self_verify.sh`; the
parked branch above, if it still exists (`git branch -a --list 'relay/orphan/*'`).

## CORRECTION 2026-09-08 -- the finding above is REFUTED; `--tsv` never dropped anything

Edited after authoring, which the header's "reproduced verbatim" convention requires be
declared: everything above is retained unchanged and this section is appended. Raised by the
`/relay reconcile --all` sweep of 2026-09-08 while disposing of this note's own subject branch.

**The claim that `list --tsv` drops a genuinely-pending entry is false.** The entry is
present. Re-run of `bash tests/test_ratify_queue_self_verify.sh` at `e3762d03` in a detached
worktree reproduces 11 PASS / 1 FAIL exactly as recorded -- and the failure message itself
prints the supposedly-missing row:

```
FAIL: list --tsv lost the genuinely-pending neighbour: beta  /tmp/…/beta  ratification_pending
      [RATIFY id:4d44] … (merged=40d3dda04ffd ckpt=relay-ckpt-20260902-1100 …): closed the thing
```

`beta`, `ratification_pending`, right there in the output offered as proof of its absence.

**The cause is the assertion, not the code.** The test sets `M2="$(git -C "$R2" rev-parse
HEAD)"` -- a full 40-char sha (line 111) -- and greps the TSV for it. But `ratify-queue.sh`
renders that field as `${merged:0:12}`, a 12-char abbreviation, and **it does so on `main`
already**, at lines 442 and 445, unchanged by the branch. So `grep -q "$M2"` could never have
matched, on any revision. The assertion was wrong the day it was written.

**Consequences for the two things this note asserted.**

- The direction-of-failure reading -- "it inverts the item's purpose", "a ratification queue
  that silently omits an outstanding push is worse than one that over-reports" -- rests
  entirely on the entry being absent. It is not. Nothing inverts.
- The surviving twin branch `relay-20260907-100619-27900-execute-repo-0` differs from this
  one by exactly this line, `grep -q "${M2:0:12}"`. Read against this note it looks like a
  test weakened to accept broken output; it is the opposite -- the correct repair of a
  mis-written assertion. That reading mattered: the twin was the one retained.

**How this note reached a wrong conclusion, since the shape recurs.** It says plainly under
*What this does NOT establish* that "the failing `--tsv` filter was not read or localized" --
and then draws a strong severity claim anyway. Localizing it costs two greps. The captured
output contradicting the headline was quoted in the note itself and read past. This is the
CLAUDE.md derived-doc rule applied to one's own evidence: a claim about code behaviour must be
checked against the code, and a failing assertion says only that a string did not match, never
why.

**Status.** This note's subject branch was discarded 2026-09-08 (owner-directed, as
verified-superseded by the surviving twin); the commit `e3762d03` survives only as an
unreferenced object. The item's stated acceptance -- "`list --tsv` emits every
genuinely-pending entry" -- was already satisfied and is not work anyone needs to do.
**Recommend closing `id:ceca` as refuted**; that is the owner's call, not this note's. The
live red state of the surviving twin is tracked separately at `id:95a3`.
