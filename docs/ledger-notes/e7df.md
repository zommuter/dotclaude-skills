# id:e7df

Detail relocated out of the ledger by `tools/ledger-shrink.py`. The item line keeps
its title, lane tag, `id:` anchor, every gate marker and a pointer back here.
**Nothing was deleted** -- the prose below is reproduced verbatim.

See `docs/ledger-notes/BACKLINKS.md` for meetings that cite this id.

## From TODO

(a) DEPENDENCY: loderite id:4c84 (gamepad menu control) was open and executor-actionable, but its own ROADMAP prose says it depends on id:ba3c's modality gap — dispatching both in one wave would have one child building on another's uncommitted worktree. Skipped 4c84 by hand. Items already state deps in prose ('gated on', 'depends on', 'sibling of', bare id refs) and some carry typed markers (gated-on:XXXX) — the classifier reads none of them, so actionable_routine_open can emit a unit whose dep is in flight THIS wave. (b) SALVAGE: loderite id:a78b's ROADMAP entry says its pure core is ALREADY implemented on branch relay/exec-a78b @13ce17b and only the fixture is wrong — a naive execute child would rewrite from scratch (the not-invented-here failure the global CLAUDE.md bans); the hand-run told the child to cherry-pick instead. WANTED: consume the existing gated-on:/typed-edge markers (cf. id:2041, id:625a ledger-index) for (a), and surface any branch named in an item's entry for (b). <!-- id:e7df -->
