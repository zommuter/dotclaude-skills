# id:dda0

Relocated from the ledger by `tools/ledger-shrink.py`. Conventions, the verbatim
claim and backlinks: `docs/ledger-notes/README.md`.

## From TODO

— it currently collision-scans only `$ROOT`, so cross-repo 4-hex collisions form continuously: measured **98 colliding tokens of 3581** (104 pairs vs 97.8 expected by the birthday model), growing ~4–5/day. Scan the relay.toml own-set via `lib-own-repos.sh` where visible, with a LOUD fallback to local-only on partial visibility (never a silent degrade). Cuts the collision flow at its SOURCE — one check at mint time replaces unbounded qualification labour downstream. Ratified 2026-08-13 (from cartulary, `docs/meeting-notes/2026-08-13-1646-storage-topology-and-fleet-marker-namespace.md`, `--fabled` finding 5) <!-- routed:ed25 --> <!-- id:dda0 -->
