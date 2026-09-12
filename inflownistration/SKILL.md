---
name: inflownistration
description: Surface the inflownistration concept and its docs, check a claim against its ratified source for drift, or file a new instance or worked example. Invoked bare, it audits the preceding context and RECOMMENDS one of those three, never acts. Trigger on "inflownistration", "information flow administration", "is this claim still what was ratified", "drift check", "file this instance". Keywords: inflownistration, information flow, drift, ratified source, restatement, instance, grammar, provenance.
---

# inflownistration skill

Three modes over one concept, plus a parameter-less router.

The concept has a **home repo** that holds its origin, its evidence, its instance
inventory and its provenance chain. That repo is PRIVATE; this skill is PUBLIC. The
split is deliberate and it shapes every rule below: this skill carries pointers and
procedure, never the concept's content, and never any instance's name.

## The one inviolable rule

**Audit, then RECOMMEND. Never act.** This is the `/chidilog` and no-argument
`/meeting` shape. A bare invocation performs no write, runs no mode to completion, and
decides nothing. It names what it would do and stops. Every mode inherits the rule in
its own form: mode (b) is report-only, and mode (c) is propose-then-confirm.

## Router (no arguments)

Invoked with no argument, inspect the PRECEDING CONTEXT of the session and offer
exactly one mode, with a one-line reason. Then stop and wait.

| What the preceding context contains | Offer | Because |
|---|---|---|
| a CLAIM that restates a ratified decision (it cites an `id:XXXX`, or asserts that something "was decided"/"was ratified"/"per the meeting") | **(b) drift check** | a restatement is the thing that rots; check it against its source |
| a described SYSTEM, tool or pipeline whose components are worth recording | **(c) file an instance** | the inventory is the point of the home repo |
| neither, or nothing to go on | **(a) surface** | the cheapest useful answer is the concept plus where to read it |

Two rules on the router itself:

- It never chains. Offering (b) does not run (b). The user picks.
- When the context is genuinely ambiguous, say so and offer (a), rather than guessing
  between (b) and (c). Guessing here costs a wrong read of the user's intent; (a) costs
  a few lines.

Modes are addressed explicitly: `/inflownistration surface`, `/inflownistration drift
<id>`, `/inflownistration file`. **There is no `/infln` alias, and none is to be
added** -- a second spelling of a skill name is a second thing to keep in sync, and
this one buys four characters.

## Mode (a): surface

Print the concept in one short paragraph, then point at the home repo's four topical
docs by their path:

- `docs/provenance.md` -- where the word came from, and what is ratified versus merely
  restated
- `docs/grammar.md` -- what the idea actually claims, stated honestly, and what it is
  not
- `docs/instances.md` -- which systems implement which components, and how completely
- `docs/prior-art.md` -- prior art, and the standing cutoff caveat on any novelty claim

Those four are the reading surface. The verbatim origin document sits under
`docs/origin/` and each of the four cites it; point there rather than reproducing it.

**Mode (a) POINTS, it does not restate.** Do not summarize the grammar's components,
do not reproduce any row of the instance inventory, and do not paraphrase a ratified
decision into this file or into your answer as if it were the source. The reason is
the concept's own: a restatement living in a second repo drifts away from its ratified
source, silently, toward whatever the restating author was already doing. Mode (b)
exists to catch exactly that shape, so mode (a) must not manufacture new instances of
it.

### Absent-repo degradation (required, non-fatal)

The home repo is private, so on any machine that does not have it, or in any session
without read access, mode (a) must still work.

1. Resolve the repo path: `$INFLOWNISTRATION_REPO` if set, else `~/src/inflownistration`.
2. If that path does not exist, print a STATED message naming the situation, then
   continue with the pointer list above as relative paths:

   > The inflownistration home repo is not present at `<path>` (it is private and not
   > cloned on this machine). Surfacing the concept and the doc layout only; the docs
   > themselves cannot be read from here.

3. This is a DEGRADED SUCCESS, not an error: report it and exit 0. Never fail, never
   ask to clone anything, and never reconstruct the missing content from memory -- a
   reconstruction is an unratified restatement, which is the failure this whole concept
   is about.

## Mode (b): drift check -- report only

Locate a claim's ratified source by `id:XXXX` grep and diff the restatement against it
verbatim, hunting three named mutations: a disjunctive rule silently becoming
conjunctive (or the reverse), a criterion swapped under the same name, and a criterion
lifted out of a recorded-not-adopted or rejected-alternative section.

Constraints that hold whatever the implementation:

- **Report only.** It writes nothing, anywhere.
- **Fail LOUD when no ratified source is found**, rather than guessing one. A guessed
  source produces a confident diff against the wrong text.
- **It does NOT read the per-component marks** in the instance inventory to cross-check
  a claim (owner ruling 2026-09-10).
- **Every report states its coverage limit**: it sees only id-anchored claims, so a
  clean pass is never "no drift", only "no drift among the claims I could anchor".

Not built by this seam. See `ROADMAP.md` `id:d846`.

## Mode (c): file an instance or worked example

Draft the row plus its evidence prose, propose each per-component mark with a one-line
reason, show a diff, and write ONLY on explicit owner confirmation. The marks are the
owner's: a skill that assigns them violates the very component of the grammar it
catalogues. Under `--afk` or pool dispatch it REFUSES AND SURFACES rather than
default-writing, because there is no owner present to confirm.

Its consumption boundary is FORMAT-PARSING for row insertion only, never semantic
consumption of a mark's value.

Not built by this seam. See `ROADMAP.md` `id:a187`.

## Public-source rule

This skill's own source is published. It must carry **no instance name** and **no
populated table schema** -- a structural or empty table only. Anything that identifies
a specific system in the inventory belongs in the private home repo, not here.
