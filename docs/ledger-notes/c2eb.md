# id:c2eb

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

Rationale: the writer logs sha256sum of assembled.json and never the input, so NO divergence past or future is replayable — provenance answers 'which build', never 're-run it'. A bounded-size copy was considered and rejected: a truncated input cannot re-hash against input_hash, and the bound bites exactly on the largest inputs <!-- id:c2eb -->

## Original title (verbatim, before the `id:64f9` rewrite)

Amend id:5578 (TODO.md:635) from binary-provenance to INPUT CAPTURE in classify-repo.sh's shadow writer: store the full assembled input on MISMATCH only (416 in 137,319 rounds — negligible), hash-only on match; binary provenance retained as a secondary field.
