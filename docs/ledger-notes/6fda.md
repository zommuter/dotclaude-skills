# id:6fda -- a skill that turns open ledger decisions into BRIEF + RECOMMENDATION + `AskUserQuestion`

Owner-requested 2026-09-10, out of the observation that the pattern was being performed by hand,
repeatedly, in one session: gather the decisions that are genuinely the owner's, brief each one,
recommend with weaknesses stated, and put them as a batched question rather than prose.

## The problem it solves

Owner-blocking decisions accumulate in the ledgers and then sit, because surfacing one properly is
expensive: it means finding the item, reading its note, reading the ratified source behind it,
working out what actually changed, forming a recommendation, and stating the recommendation's
weaknesses. Done well that is minutes per decision; done badly it is a prose dump that the owner has
to re-derive from. So decisions that nobody has budget to brief stay unmade, which is the
`id:4d8e` detection-with-no-op-resolution shape applied to human judgment.

Measured instance from the session that prompted this: `id:32c3`'s scope was ratified 2026-08-21 and
it sat ~3 weeks; `id:9d06`, `id:79a9`, `routed:16e3` and others have waited longer. None was blocked
on analysis -- each was blocked on nobody having packaged the question.

## Shape

Mine the ledgers for items whose lane is `[INPUT - decision]` (and `[INPUT - meeting]` for the
meeting-worthy ones), plus any item whose note records an explicit unresolved owner question. For
each, produce:

* **the question**, in one sentence, answerable without reading the note;
* **the brief** -- what changed, what is measured versus assumed, and the one fact that makes the
  decision non-obvious;
* **a recommendation WITH its weaknesses** -- never a bare preference, and never a rubber stamp;
* **what it blocks**, so the owner can triage by consequence rather than by age.

Then batch them into ONE `AskUserQuestion` call (the fleet rule is one call with a `questions`
array, not several calls), at most 4 per pass, highest-consequence first.

## Non-negotiables, each of which has already gone wrong somewhere in this fleet

* **RECOMMEND, never decide.** The verdict is the owner's. A skill that records its own
  recommendation as settled is the delegated-verdict failure (chidiai case
  `2026-07-15-delegated-verdict-settled-without-owner-ratification`), and it would be worse here
  because this skill's whole output looks authoritative by construction.
* **Never write the answer back without confirmation.** Propose-then-confirm, like
  `/inflownistration` mode (c) (`id:32c3`), and REFUSE-AND-SURFACE under `--afk`/pool rather than
  default-writing.
* **Check the ratified source, do not trust the item's restatement.** The item text is a derived
  doc and drifts toward whatever its last author was doing. This is CLAUDE.md's own
  derived-doc-versus-ratified-source rule, and today it caught a case where the two 2026-08-21
  restatements of one rule contradicted each other (`id:32c3`).
* **A consumed pre-registration is not an answer.** Before presenting "this was already decided",
  verify the trigger names the artifact in question and has not already fired and been overridden.
* **State coverage honestly.** It finds what the ledgers express; a clean pass is never "no
  decisions pending". Say so in the output, the way `/inflownistration` mode (b) must.

## Open questions for whoever builds it

1. **Where does it live and what is it called?** `/decide`? A mode of `/relay human`, which already
   gathers human-lane backlog and would avoid a second collector? The second is cheaper and reuses
   `gather-human-backlog.sh`, but `/relay human` currently under-reports (`id:9d06` has it showing
   zero `review_me` rows), so it would inherit a known defect.
2. **How does it avoid re-asking a question the owner already answered?** An answered decision
   should be recorded on the item, which suggests it needs a write path -- and a write path is what
   the propose-then-confirm rule above constrains. Possibly the answer is that it only ever drafts
   the recording and the owner's confirmation commits it.
3. **Does it rank by consequence, and can it?** "What this blocks" is a gate-graph question;
   `relay/scripts/lib-typed-edges.sh` has `children:`/`gated-on:` but most items carry neither.

## Related

`id:9d06` (`/relay human` under-reporting), `id:4d8e` (detection with a no-op resolution),
`id:32c3` (the propose-then-confirm precedent, and today's drift instance), `id:c3f6` (mechanize the
keystone-unblock triage as a `/relay human` view -- overlaps this, check before building),
`id:95c8` (`control-board.sh` under-counts human-lane items, so the existing counters are not
trustworthy input yet).
