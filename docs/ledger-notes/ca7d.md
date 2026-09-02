# id:ca7d

Detail relocated out of the ledger by `tools/ledger-shrink.py`. The item line keeps
its title, lane tag, `id:` anchor, every gate marker and a pointer back here.
**Nothing was deleted** -- the prose below is reproduced verbatim.

See `docs/ledger-notes/BACKLINKS.md` for meetings that cite this id.

## From TODO

(owner-ruled 2026-08-21) — a line with no `<!-- id:XXXX -->` but with a cross-reference in its prose (`id:f508`, `ids db29+e69c`, a backticked `routed:0d2c`) is refused as "non-canonical inline id", because the tool cannot tell an OWN id from a reference to another repo's item. Observed on loderite TODO.md lines 365/398, which sat untracked and invisible to every ledger tool; migrating them needed a HAND de-prefixing of the prose before the tool would mint (loderite `5d6e4eb`). THE RULE TO TEACH — it is already banked and used elsewhere: **an item's own id is the LAST `<!-- id:XXXX -->` comment on the line, never the first, and never a bare token in prose** (this is exactly the id:d7727be own-id dedup fix in `/relay human`). So: consider ONLY `<!-- id: -->`-wrapped markers when deciding whether a line is tracked; ignore prose mentions entirely; mint when no wrapped marker exists. ALSO worth fixing in the same pass: the repo's `` `routed:XXXX` `` backtick convention does NOT protect against `scan-routed`'s twin check — backticks are not a grep boundary — so either make the twin check anchor on `<!-- routed:XXXX -->` markers only (the real fix, and the same own-id-marker principle), or document a placeholder form that actually works. Note the 2026-08-14 loss (id:c97c, 3 inbox items drained unfiled) was this same root: bare tokens in prose vs marker-anchored scanning. Relates [[inbox twin-check false-resolve]], [[relay-human-gather-underreport]], id:9fdb. <!-- id:ca7d -->
