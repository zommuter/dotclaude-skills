# id:ee2e

Relocated from the ledger by `tools/ledger-shrink.py`. Conventions, the verbatim
claim and backlinks: `docs/ledger-notes/README.md`.

## From TODO

— it reads the item's first line only, sees no id, and appends a freshly-minted one, so the item ends up carrying two. This is the exact P1/P2 duplicate-id anti-pattern the relay guards against, produced by the tool meant to prevent it, and it fires silently under `--fix` (reported as a normal "auto-fixed N missing-id item(s)"). **Minimal repro**: two-item `TODO.md` where item 2 spans 3 lines with its id on the last → `--fix` injects a second id onto line 1. **Observed 2026-08-18** on csgebra's 4D north-star item (already `id:0502`, got `id:02b4` appended); reverted by hand. **Fix direction**: scan the whole item block (up to the next checkbox/heading) for an id before classifying it missing-id, matching how `resolve-gates`/`lib-typed-edges` anchor on comment markers. Note the "own id is the LAST id-comment" convention when picking which id wins. <!-- routed:c3f7 --> <!-- id:ee2e -->
