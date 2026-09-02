# id:cce9

Detail relocated out of the ledger by `tools/ledger-shrink.py`. The item line keeps
its title, lane tag, `id:` anchor, every gate marker and a pointer back here.
**Nothing was deleted** -- the prose below is reproduced verbatim.

See `docs/ledger-notes/BACKLINKS.md` for meetings that cite this id.

## From TODO

Found 2026-09-01 while verifying the id:6958 archive migration; 3 real instances, all in `TODO.archive.md`, of the form `- [x] [INBOUND routed:XXXX from <repo>] [HARD - pool] ...` (verified: `grep -cE '^\s*- \[[ xX]\] \[INBOUND[^]]*\] *\[(HARD|INPUT|INTENSIVE) *-' TODO.archive.md` returns 3, with the em-dash spelling). **Mechanism:** the detector walks the CONTIGUOUS leading bracket run and stops at the first bracket that is not lane vocabulary. `[INBOUND routed:... from ...]` is a provenance prefix, not a lane, so the run stops there and the REAL `[HARD - pool]` behind it is never examined. Same shape for 4 further lines in `ROADMAP.archive.md` (3x `[HARD - strong model]`, 1x `[INPUT - decision - SUPERSEDED 2026-07-21]`) whose lane words are absent from `hard-lanes.md` vocabulary -- those may be deliberate non-vocabulary and are the weaker case. **WHY IT MATTERS:** the S9 seam (id:6958) closes on this scan returning nothing, and it now does -- but that is a statement about what the detector can SEE, not about what the ledgers contain. S10's strictness flip will have to carve these out or fix the detector, and a detector that under-reports is the id:d35a silent-no-op class. **Contract:** the leading-bracket walk skips a known provenance prefix (`[INBOUND ...]`) rather than terminating on it; a fixture pins the 3 TODO.archive.md lines; and the ROADMAP.archive.md non-vocabulary cases are reported as a distinct class rather than silently included. Relates id:6958 (S9), id:d0aa (the migration), id:2065 (the archive carve-out). <!-- id:cce9 -->
