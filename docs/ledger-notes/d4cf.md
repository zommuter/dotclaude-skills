# id:d4cf

Relocated from the ledger by `tools/ledger-shrink.py`. Conventions, the verbatim
claim and backlinks: `docs/ledger-notes/README.md`.

## From TODO

VERIFIED 2026-08-22: lodelore/lean/lean-toolchain pins leanprover/lean4:v4.32.2 while mathematical-writing, toesnail/verify and relay-core all pin v4.30.0-rc2 (all three derived from toesnail's vendored Mathlib, which is itself v4.30.0-rc2). A /relay health run that day printed 'pins agree: leanprover/lean4:v4.30.0-rc2' — true for the pair it checks, and read as a global all-clear while a real divergence sat one repo over. The only automated guard for this drift class cannot see the drift it exists to catch. Fix: enumerate lean-toolchain files across the relay.toml own-set (honoring '# path:') instead of hardcoding a two-repo pair, and report any pin that differs from the majority rather than comparing a fixed pair; note lodelore's lives at lean/lean-toolchain and toesnail's at verify/lean-toolchain, so a repo-root-only glob misses both. Consumers of the answer: mathematical-writing id:de24 (align-or-not decision) and id:40f6/id:6ab8 (ingest lodelore as a corpus, which hits the divergence immediately). <!-- id:d4cf -->
