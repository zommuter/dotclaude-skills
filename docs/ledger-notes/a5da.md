# id:a5da

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

Motivating case: id:65f5/dee7106 added surfaced_open on 2026-07-20 with no bash-side test, the port lagged 22 days and 41,492 rounds, and 416 mismatches accrued before anyone noticed <!-- id:a5da -->

## Original title (verbatim, before the `id:64f9` rewrite)

File a port-drift detector for the 'bash gains a field, the Lean port lags silently' failure class: re-run relay-core's extract-fixtures.sh + parity-run.sh on any classify-verdict.sh change (relay-doctor or CI hook), and/or a field-name drift check diffing bash's data.get(...) key set against RelayCore/ClassifyVerdict.lean's getters.
