# id:fddb

Detail relocated out of the ledger by `tools/ledger-shrink.py`. The item line keeps
its title, lane tag, `id:` anchor, every gate marker and a pointer back here.
**Nothing was deleted** -- the prose below is reproduced verbatim.

See `docs/ledger-notes/BACKLINKS.md` for meetings that cite this id.

## From TODO

(meeting `docs/meeting-notes/2026-08-21-0803-combined-tracker-substrate-cb22-convergence.md`, D1-A; `--fabled` F2) — the pilot's pre-registered fail condition is 4 weeks from "first successful full import" measured against the `id:8066` control arm, and NOBODY could confirm the clock has started. The import exits 3 until `id:cb22`'s writes land, so the clock-start is downstream of `id:695d`. Until it exists the pilot cannot FAIL, which means "the pilot is alive" is vacuous AND `id:2840`'s fallback trigger can never fire. Write it when cb22 closes. Contract: a scanner answers "has the clock started, and when" without opening a meeting note. <!-- gated-on:695d --> <!-- id:fddb -->
