# id:cbee

AUTHORED note, not relocated by `tools/ledger-shrink.py` -- the verbatim-reproduction claim
does not apply to it (see the "Authored notes" section of `docs/ledger-notes/README.md`).

## From TODO

**`empty permitted-id set (id:c076)` is BACK: 4 execute handbacks across 3 repos in one run,
after `id:677b` banked the fix as working.**

## What was observed

Run `relay-20260912-191938-25818` (`--afk --exclude unidle`, 7 rounds, 679 agents). Four execute
children handed back with `actionable_routine_ids was absent or unusable at dispatch`:

| repo | handbacks |
|---|---|
| dotclaude-skills | 1 |
| loderite | 1 |
| mathematical-writing | 2 |

Each child self-classified it the same way -- **a classifier/queue wiring fault, not an absence
of work** -- and each correctly refused to survey `ROADMAP.md` and pick something that merely
looked open. The fail-closed directive held in all four. That is the system behaving as designed
around a fault, not four independent judgement calls.

## Why this is a REGRESSION signal rather than a new discovery

`id:677b` records the immediately preceding run `relay-20260911-103808-7255` producing
`item=b437 eligible=1` on this repo, and says in terms that "the id:c076 fix worked -- where the
previous run produced an empty permitted set and a 650k refusal". `id:c076` itself was CLOSED on
the owner's dissolved-enough ruling on 2026-09-11.

So one of two things is true, and they have different fixes:

1. **A second path into the same empty set** that the unified predicate does not cover. The
   09-11 handover already names an unfixed one: `id:c076` Cause A, the RECHAIN path at
   `relay-loop.js:4744`, which pushes a hand-built 7-field unit literal that never went through
   the classifier (`sig:""` on every one). That was explicitly left out of scope, and it is the
   first candidate to check.
2. **A partial fix** -- the predicate was unified but some caller still reads a looser copy.
   `id:c076` Cause B was exactly this shape (a fourth looser copy of the open-`[ROUTINE]`
   predicate) and was fixed; a fifth is possible.

## How to start, and what NOT to do

**Do NOT re-fix from the handback text alone.** Those children saw only the dispatch-time
condition that was handed to them in their own task prompt; none of them ever saw the classifier
that produced it. Their reports are evidence that the guard fired, not evidence about why the set
was empty. Diagnosing from them is the `id:4d8e` shape -- treating a loud detection as if it
were a diagnosis.

Start from the run's discovery objects and establish WHICH of the two cases above it is.
`~/.config/relay/relay-events.jsonl` is the durable record; note the field is `kind`, **not**
`event` (the 09-11 handover records getting this wrong), and note that a rechain unit is
identifiable by `sig:""`.

## Scale, for prioritisation

4 of 16 execute children this run never got a workable id at all. That is a **larger** loss than
the 5 that died `Prompt is too long` in the same run, and unlike those deaths it costs nothing to
observe -- the children exit cleanly and the run reports a handback rather than an error.

**Relations.** `id:c076` (the closed parent). `id:677b` (banked the fix as working; also the
mid-run-context-death item). `id:3846` (the `Prompt is too long` arm of the same run).
