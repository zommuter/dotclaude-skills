# id:c2eb

Detail relocated out of the ledger by `tools/ledger-shrink.py`. The item line keeps
its title, lane tag, `id:` anchor, every gate marker and a pointer back here.
**Nothing was deleted** -- the prose below is reproduced verbatim.

See `docs/ledger-notes/BACKLINKS.md` for meetings that cite this id.

## From TODO

Rationale: the writer logs sha256sum of assembled.json and never the input, so NO divergence past or future is replayable — provenance answers 'which build', never 're-run it'. A bounded-size copy was considered and rejected: a truncated input cannot re-hash against input_hash, and the bound bites exactly on the largest inputs <!-- id:c2eb -->
