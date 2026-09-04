# id:bbc2

Relocated from the ledger by `tools/ledger-shrink.py`. Conventions, the verbatim
claim and backlinks: `docs/ledger-notes/README.md`.

**EDITED 2026-09-03 (`id:64f9`, title rewrite) -- declared, per the notes-are-editable
convention in `CLAUDE.md`.** This item's ledger TITLE in `TODO.md` was rewritten to fit
`LEDGER_ITEM_TITLE_MAX`. Nothing else on the item line changed: lane tags, typed-edge and
`id:` markers, the detail pointer and the checkbox are all untouched. The ORIGINAL title is
reproduced VERBATIM in the final section of this note, so no wording was deleted -- it moved
here. The relocated prose below is otherwise unchanged.

## From TODO

Fix: format.md/SKILL.md must make 'append the just-presented transcript chunk to the plan file' an explicit step BEFORE the AskUserQuestion, not only emit it to chat. <!-- id:bbc2 -->

## Original title (verbatim, before the `id:64f9` rewrite)

Recurring meeting-skill bug: a transcript chunk emitted to chat at a decision point is NOT appended to the plan file before the next Edit, so the follow-up Edit anchoring on that text fails with 'String to replace not found' (hit again truncocraft 2026-06-29 pwa-commercialisation; also prior meetings).
