# id:bad5

Relocated from the ledger by `tools/ledger-shrink.py`. Conventions, the verbatim
claim and backlinks: `docs/ledger-notes/README.md`.

**EDITED 2026-09-03 (`id:64f9`, title rewrite) -- declared, per the notes-are-editable
convention in `CLAUDE.md`.** This item's ledger TITLE in `TODO.md` was rewritten to fit
`LEDGER_ITEM_TITLE_MAX`. Nothing else on the item line changed: lane tags, typed-edge and
`id:` markers, the detail pointer and the checkbox are all untouched. The ORIGINAL title is
reproduced VERBATIM in the final section of this note, so no wording was deleted -- it moved
here. The relocated prose below is otherwise unchanged.

## From TODO

Answers must NOT be uniform: sometimes a direct pick of one option, sometimes free text consistent with the profile, e.g. "#2 but also with #3-s whatchamacallit-thing, maybe a spike first?" — the value is exercising the owner-s actual decision STYLE (hybrid picks, riders, spike-first hedges, challenges to the premise), not just filling a slot. ⚠ HARD GUARD, the reason this could do damage: a simulated owner-s verdict is still a DELEGATED verdict and must never be recordable as ratification — it looks exactly like the real thing in a ledger. Every artifact it writes must be marked simulated, and a real owner ratification checkpoint must remain mandatory (fleet CLAUDE.md "no quiet decisions" + the 2026-07-15 chidiai case where a delegated NO-GO was settled without the owner). Suggested shape: emit to the meeting NOTE only, never to TODO.md/ROADMAP.md, and prefix every simulated turn. Prereq/limit: depends on there BEING user-type memories — as of 2026-08-21 the it-infra store had exactly ONE (`owner-is-the-domain-expert`, the first ever; 7 feedback / 18 project / 4 reference / 0 user), so the persona would be thin today and the feature should degrade loudly rather than confabulate a personality. Also worth deciding: whether it reads `feedback`-type memories too (they encode how he wants work done, which is half the persona). <!-- id:bad5 -->

## Original title (verbatim, before the `id:64f9` rewrite)

`/meeting --simulate-me` — run a meeting on autopilot with an EMULATED owner persona built from the `type: user` memories (global, or project-only via a flag), so the meeting produces both the simulated `AskUserQuestion` options AND the simulated owner-s answers.
