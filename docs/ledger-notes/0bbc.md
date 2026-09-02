# id:0bbc

Detail relocated out of the ledger by `tools/ledger-shrink.py`. The item line keeps
its title, lane tag, `id:` anchor, every gate marker and a pointer back here.
**Nothing was deleted** -- the prose below is reproduced verbatim.

See `docs/ledger-notes/BACKLINKS.md` for meetings that cite this id.

## From TODO

(third in the family after the privacy gate and the lane-vocab ratchet): block a newly-added bare prose `id:XXXX` reference, requiring the repo-qualified form. Scope is ALL new refs, not just colliding ones — the colliding-only variant was ratified then AMENDED away because deriving the list at gate time needs all 51 clones inside a pre-commit hook, which under-derives silently on Termux/partial clones. Two binding details: pick the qualified grammar EXPLICITLY (`repo:93fe` is invisible to existing scanners, `repo:id:93fe` still matches their bare-ref regex — neither is free) and update `cartulary/scripts/prose-tail-scan.py`'s regex in the same pass; and define "newly-added" as a FILE-LEVEL token-presence delta, never a diff-line test, or a reflowed grandfathered line reads as added and editing old prose needs `--no-verify`. Grandfathers the 35519-reference prose tail untouched. Ratified 2026-08-13 (from cartulary, same note, D5/D6 as amended by A3) <!-- routed:1c50 --> <!-- id:0bbc -->
