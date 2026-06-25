# TODO conversion policies <!-- relay conversion-policies v1 -->

The canonical playbook for converting a non-conforming `TODO.md` to the relay
**items-only** format (id:3441 / c095 / handoff C2). `todo-conformance.sh` is the
DETECTOR; this is how a strong/handoff/review turn (or a conversion agent) RESOLVES
each finding. Owner-approved 2026-06-26 from the 41-repo conversion sweep — the 33
deferred judgment calls clustered into the four policies P1–P4 below, all ratified.

## The format (what a conforming TODO.md may contain)
- markdown headers, incl. `### ` subsections
- well-formed checkbox items `- [ ] <text> <!-- id:XXXX -->` / `- [x] …`
- heading-as-items `## [LANE] Title <!-- id:XXXX -->` with `- [ ] Open` / `- [x] Done`
  status sub-lines (the heading owns the lane+id — c095; never flagged)
- HTML-comment lines
**No prose.** Everything else is relocated/converted per P1–P4. `todo-conformance.sh`
reports the two classes the policies key off: `missing-id` and `orphan`.

## P1 — non-canonical ids (a `missing-id` line that DOES carry an id somewhere)
The canonical token is a TRAILING `<!-- id:XXXX -->` (4-hex). Resolve by ROLE:
- inline `(id:X)` / `id:X` that IS this item's own token → migrate to `<!-- id:X -->`
  (reuse the same X).
- the line only "see id:X" / cross-references ANOTHER item's (e.g. ROADMAP) id → that
  xref is NOT this item's identity → mint a FRESH own id (`append.sh new-id`), keep the
  "see id:X" prose as context.
- id on a CONTINUATION line (indented, under the `- [ ]`) → move it up onto the item's
  first line, THEN `--fix` (so no duplicate is minted).
- item with `<!-- routed:X -->` but no `<!-- id:X -->` → mint and append a fresh id
  (keep the routed token).
- genuinely id-less well-formed items → `todo-conformance.sh --fix` (it SAFELY skips any
  line already carrying an inline id — the duplicate-mint guard).

## P2 — stale / duplicate prose (`orphan`)
- prose you can VERIFY (grep) is already in `ARCHITECTURE.md` or `RELAY_LOG.md` → DELETE
  the TODO copy (it survives in the other file + git history).
- a `[~]` in-progress/cancelled marker → `- [x]` if done, or delete if cancelled.
- a "placeholder" / empty Done stub → delete.
- NOT verified-duplicate → do not delete; treat under P3.

## P3 — relocate prose by type (`orphan`)
- design rationale / decision-records ("Decision (owner…)", "D1/D2/D3 …") → append to
  `ARCHITECTURE.md` under a labeled section.
- meeting-citation prose already captured in `RELAY_LOG.md` → delete (verify first).
- a bug-ledger / definitions TABLE → keep IN PLACE, annotate `<!-- lint-ok: <reason> -->`
  (a structured table is not prose-noise).
- a one-line file/section preamble → keep as ONE line `<!-- lint-ok: file-purpose preamble -->`.

## P4 — status-as-task (an open `- [ ]` whose text is not work)
- a `- [ ]` that is a PAST-TENSE status / relay snapshot ("v0 scaffold landed", "Relay:
  N open ROADMAP items") → `- [x]` if genuinely done, OR move the narrative to
  `RELAY_LOG.md` and drop the checkbox.
- a genuine forward-flag / cross-ref NOTE with no action → `<!-- lint-ok: forward-flag note -->`.
- only actual remaining WORK stays an open `- [ ]`.

## FLAG, don't guess (the residual)
When applying a policy would require guessing the owner's intent — a genuine
task-existence / same-or-sibling-id ambiguity you cannot resolve from context — LEAVE the
line untouched and SURFACE it: a `REVIEW_ME.md` box (handoff/review) or the `/relay human`
"fix at source" list. Never fabricate a task, never delete unverified, never auto-pick a
canonical id when two items might be the same. (Example from the sweep: zkWhale's
"Salt on the zk signature — … see id:b4fe" — same item as b4fe, or a sibling? → owner call.)

## Mechanical vs judgment
P1's continuation-line-move / routed-mint / `--fix` are MECHANICAL (safe to automate).
P2/P3/P4 and P1's own-vs-xref split are JUDGMENT — apply them in a handoff/review turn or a
conversion agent that can read context, never in a blanket bash `--fix`. This is why the
sweep AUTO-did the safe subset and DEFERRED these to owner-approved policies.
