# id:9ceb

Relocated from the ledger by `tools/ledger-shrink.py`. Conventions, the verbatim
claim and backlinks: `docs/ledger-notes/README.md`.

## From TODO

(a) Flag any open 🚧-DECOMPOSED item LACKING `@container` — the emitter-omission case, i.e. the lint that makes `routed:5d10`/`id:d7c7` self-detecting rather than found by hand a fourth time. (b) Flag any open line where a live 🚧 co-occurs with `✅ GATE CLEARED` / `DISPATCHABLE` **without a gate-id binding each ✅ to what it cleared** — reported endemic in loderite (`ROADMAP.md:268/269/505/638`). Class (b) is the more valuable one: an unbound ✅ next to a live 🚧 is unreadable to both a human and a scanner, and silently invites treating a still-gated item as open. **Acceptance**: fixtures for both classes flag; a 🚧-DECOMPOSED item WITH `@container`, and a ✅ carrying an explicit gate id, both pass clean. Check this repo for class-(b) instances in the same pass — several items here carry ✅/🚧 prose. Source: `docs/meeting-notes/2026-08-14-1338-empty-dispatch-container-and-vocab.md`. <!-- id:9ceb -->
