# id:ae4f

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

Evidence (loderite 2026-08-10, VERIFIED from the failed agent transcript, not inferred): 4 `Prompt is too long` execute-tier failures across 2 items (`0295` x3, `eac0` x1) while 5 narrower items in the same wave landed first try. The transcript shows NO single big read — 522 KB over 239 entries, largest single entry 40 KB, i.e. cumulative accretion from 90 tool results totalling 161 KB. Top consumers: `docs/perf-budget.md` 36 KB (the item contract REQUIRES documenting in it), `src/bench-suite.ts` 17 KB (the file it must change), the executor contract itself 14 KB, and a ROADMAP offset-read 13.7 KB. Proposal (a): at handoff C2/C3, sum the byte sizes of the files/docs an item contract names and lane it `[HARD]` above a threshold — cheap, mechanical, uses data already on disk. Proposal (b): lint per-ITEM ROADMAP line length — the executor followed the `grep -n` + offset-read guidance CORRECTLY and still paid 13.7 KB because single item lines had grown to 2902 chars (`eac0`) and 4246 chars (`0295`); verbose per-item annotation is a direct tax on every executor that reads that item, invisible to total-ledger-size thinking. Note the failure mode is silent: the pool just reports the item undone and re-dispatches. <!-- id:ae4f -->

## Original title (verbatim, before the `id:64f9` rewrite)

Lane-assign on an item's READ FOOTPRINT: a `[ROUTINE]` whose contract requires reading large docs/files is ctx-expensive BY CONSTRUCTION, and that is knowable at handoff time instead of after N burned dispatches.
