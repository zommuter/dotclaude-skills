# id:ccad

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

Real impact: id:3f7e is open in BOTH ledgers, so consumers id:659c/id:c3f6 see a dependency on a nonexistent id. NOT a ledger.py defect — the ROADMAP spec mandates skipping FENCED code and is silent on inline spans, and non-hex tokens are ratified + pinned by test_gated_on_keeps_non_hex_token_verbatim; owner chose option (b) fix-the-prose over (a) widen-the-parser on 2026-08-11 (relay review project_manager). project_manager's own site is already fixed. <!-- id:ccad -->

## Original title (verbatim, before the `id:64f9` rewrite)

Reword 2 inline gated-on marker EXAMPLES that ledger.py harvests as live edges: TODO.md id:3f7e / ROADMAP.md:1455 (backticked marker example -> phantom token 'id') and record id:382a (-> phantom token 'X').
