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
