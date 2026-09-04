# id:b7de

Relocated from the ledger by `tools/ledger-shrink.py`. Conventions, the verbatim
claim and backlinks: `docs/ledger-notes/README.md`.

## From TODO

`classify-repo.sh`'s byte accounting (`id:f3d2`) matches the path `docs/ledger-notes/<name>.md` ANYWHERE in a ledger, so an item that merely MENTIONS such a path in prose is counted too, and if that file does not exist it is charged 32,768 B with a warning. Safe in the over-count direction and consistent with the contract, but it is a false-positive channel worth closing once `id:0d7c` fixes the canonical spelling. <!-- gated-on:0d7c --> <!-- id:b7de -->
