# id:d3bf

Detail relocated out of the ledger by `tools/ledger-shrink.py`. The item line keeps
its title, lane tag, `id:` anchor, every gate marker and a pointer back here.
**Nothing was deleted** -- the prose below is reproduced verbatim.

See `docs/ledger-notes/BACKLINKS.md` for meetings that cite this id.

## From TODO

-- its own message names those three -- and NEVER `ROADMAP.archive.md`, so a gate whose blocker is CLOSED AND ARCHIVED reads as a dangling target. Measured in it-infra: `id:63b0` is `gated-on:0001,3658`, both `- [x]` in `ROADMAP.archive.md`, yet lint reported DEAD-GATE twice and a reviewer wrote "blockers do not exist" into the ledger for a DISCHARGED gate. Same omission was already fixed once for `orphan-scan --cross-ledger` (routed:42c9 / id:1d6a) and not carried across. Check the ANSWER-SRC call site at `roadmap-lint.sh:511` too -- it names the identical three-file list. Acceptance: both call sites include `ROADMAP.archive.md`; a fixture with an archived-closed blocker produces no DEAD-GATE. <!-- id:d3bf -->
