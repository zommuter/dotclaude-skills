# id:ecd0

Detail relocated out of the ledger by `tools/ledger-shrink.py`. The item line keeps
its title, lane tag, `id:` anchor, every gate marker and a pointer back here.
**Nothing was deleted** -- the prose below is reproduced verbatim.

See `docs/ledger-notes/BACKLINKS.md` for meetings that cite this id.

## From TODO

Observed loderite 2026-08-01**: `/relay reconcile .` correctly reported "no parked orphans" while `relay/handoff/savegame-migration` (13 days old, +340 lines including a 230-line RED spec `tests/savegame-migration.test.ts`, id:290e) and 21 merged `relay/*` branches sat unreachable by it. **Fix direction (the reporter's, preserved)**: make the CONSUME side ALSO enumerate unmerged `relay/*` branches outside the orphan namespace, or make parking branch-driven rather than worktree-driven. **Carve-out that must survive the fix**: `relay/exec/25c6` is NOT this bug — a `contract_met=false` HANDBACK is held by design (SKILL.md invariant 5) and must stay OUT of the orphan namespace. <!-- routed:47da --> <!-- id:ecd0 -->
