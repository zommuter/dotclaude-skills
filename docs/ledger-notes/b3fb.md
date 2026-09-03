# id:b3fb

**EDITED 2026-09-03 (`id:64f9`, title rewrite) -- declared, per the notes-are-editable
convention in `CLAUDE.md`.** This item's ledger TITLE in `TODO.md` was rewritten to fit
`LEDGER_ITEM_TITLE_MAX`. Nothing else on the item line changed: lane tags, typed-edge and
`id:` markers, the detail pointer and the checkbox are all untouched. The ORIGINAL title is
reproduced VERBATIM in the final section of this note, so no wording was deleted -- it moved
here. The relocated prose below is otherwise unchanged.

Detail relocated out of the ledger by `tools/ledger-shrink.py`. The item line keeps
its title, lane tag, `id:` anchor, every gate marker and a pointer back here.
**Nothing was deleted** -- the prose below is reproduced verbatim.

See `docs/ledger-notes/BACKLINKS.md` for meetings that cite this id.

## From TODO

Every load-bearing caller gets this right (relay-doctor.sh:118, claim.sh:22, archive-closed.sh:14, resource-claims.md:20, review.md:287) — only the two SKILL.md lines drop the prefix, and their surrounding context names relay scripts, so a reader resolves the bare name against relay/scripts/ and gets 'no such file'. Hit live 2026-08-22 during /relay human . on mathematical-writing. Fix: add the meeting/ prefix at both lines; consider the ambiguous bare refs at human.md:320, handoff.md:68, review.md:297 too. <!-- id:b3fb -->

## Original title (verbatim, before the `id:64f9` rewrite)

relay/SKILL.md:60 and :890 name the cross-ledger drift checker as a bare `orphan-scan.sh --cross-ledger`, but no such script exists in relay/scripts/ — it lives in the meeting skill as `meeting/orphan-scan.sh` (the only one supporting --cross-ledger; mechanical-orphan-scan.sh has none).
