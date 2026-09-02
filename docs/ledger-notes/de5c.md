# id:de5c

Detail relocated out of the ledger by `tools/ledger-shrink.py`. The item line keeps
its title, lane tag, `id:` anchor, every gate marker and a pointer back here.
**Nothing was deleted** -- the prose below is reproduced verbatim.

See `docs/ledger-notes/BACKLINKS.md` for meetings that cite this id.

## From TODO

(INBOUND from loderite, `docs/meeting-notes/2026-08-14-1338-empty-dispatch-container-and-vocab.md`) — the check (run the ORIGINAL specs against the NEW implementation) proves only that rejections **pinned by the original assertions** survived; a widening can flip an entirely UNPINNED rejection class and still return a clean 30/30. That is what happened on loderite `id:89ef`: the resurrection run was 30/30 green and honest, and the sentence written about it — *"zero rejections flipped to acceptances, the widening is strictly additive"* — was false, because the old code rejected permuted-order region pairs via an index-by-index comparison that no test asserted. **The check ran, the check was honest, and the SENTENCE ABOUT THE CHECK over-claimed** — no amount of re-running would have caught it; this is the claim-about-code-is-a-derived-doc rule in its subtlest form. **Suggested addition to §2b.1** (phrasing from the gate-C reviewer, quoted verbatim): *"A green resurrection run bounds the widening only over behaviour the original spec asserted. Before claiming 'strictly additive', separately enumerate the rejection classes the old implementation produced that no test pinned, and probe those directly."* **Fold in the earlier caveat on the same technique in the SAME revision**: a green run is not a pass/fail gate — legitimate contract tightenings produce expected reds, and the only finding is a rejection→acceptance flip. Contract: `relay/references/review.md` §2b.1 states both limits; no code change. <!-- routed:41c1 --> <!-- id:de5c -->
