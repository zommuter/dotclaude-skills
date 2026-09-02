# id:bf9d

Detail relocated out of the ledger by `tools/ledger-shrink.py`. The item line keeps
its title, lane tag, `id:` anchor, every gate marker and a pointer back here.
**Nothing was deleted** -- the prose below is reproduced verbatim.

See `docs/ledger-notes/BACKLINKS.md` for meetings that cite this id.

## From TODO

— reported against `todo-update/archive-done.sh:135-137`, where the archived block is appended unconditionally. **Observed**: zkWhale commit `5fa232b` moved 4 items but wrote 8 added / 4 removed, leaving 4 exact-duplicate `- [x]` lines in `TODO.archive.md`. **Not reproduced here** — this repo's `TODO.archive.md` and `ROADMAP.archive.md` both have 0 duplicate `- [x]` lines as of this review (`sort | uniq -d`), including after commit `f821ed4` archived 25 entries — so the trigger is a re-archive of an already-archived item, not every run. **Fix direction**: before appending, skip any block whose `<!-- id:XXXX -->` (or, for an untracked line, whose exact text) is already present in the archive file; a duplicate is silent and the archive is the durable record, so this is a data-integrity bug rather than cosmetics. Pairs with the id:f54d/`roadmap-archive.sh` sibling — check whether that archiver has the same append-without-dedupe shape before fixing only one. <!-- routed:cd7f --> <!-- id:bf9d -->
