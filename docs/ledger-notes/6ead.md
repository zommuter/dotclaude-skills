# id:6ead

Relocated from the ledger by `tools/ledger-shrink.py`. Conventions, the verbatim
claim and backlinks: `docs/ledger-notes/README.md`.

## From TODO

The owner declined to pick a fix until the blast radius is known. Background: the typed-edge engine reads `<!-- children: -->` while 88% of the corpus writes `<!-- children-of: -->`, and the two encode INVERSE directions, so child-edge closure is a no-op across most of the corpus today. **Deliverable is a NUMBER, not a fix:** with both spellings resolved in their correct directions, how many parents become closure-eligible that are not today, and how many currently-closed items would no longer qualify? Report both directions -- a fix that silently CLOSES a batch of items is the more dangerous one, and it is the direction nobody has looked at. Do NOT apply a fix in this item; `id:cf7a` remains open and the owner chooses the mechanism once the number exists. <!-- relates:cf7a --> <!-- id:6ead -->
