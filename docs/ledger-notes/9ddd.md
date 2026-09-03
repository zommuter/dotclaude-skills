# id:9ddd

**EDITED 2026-09-03 (`id:64f9`, title rewrite) -- declared, per the notes-are-editable
convention in `CLAUDE.md`.** This item's ledger TITLE in `TODO.md` was rewritten to fit
`LEDGER_ITEM_TITLE_MAX`. Nothing else on the item line changed: lane tags, typed-edge and
`id:` markers, the detail pointer and the checkbox are all untouched. The ORIGINAL title is
reproduced VERBATIM in the final section of this note, so no wording was deleted -- it moved
here. The relocated prose below is otherwise unchanged.

Detail relocated out of the ledger by `tools/ledger-shrink.py`. The item line keeps
its title, lane tag, `id:` anchor, every gate marker and a pointer back here.
**Nothing was deleted** -- the prose below is reproduced verbatim.

See `docs/ledger-notes/BACKLINKS.md` for meetings that cite this id.

## From TODO

The stop was issued FOR loderite and was consumed by the OTHER pool. Timeline: sentinel written 14:28; consumed 14:32:01 per the consume log; loderite RE-CLAIMED its repo at 14:34:08 and went on to checkpoint relay-ckpt-20260729-1412 / 1423 / 1433, so loderite demonstrably never stopped; meanwhile dotclaude-skills' claim froze at 14:28:10 with its last commit at 14:20 and last checkpoint at 1255 — i.e. the pool the operator did NOT target is the one that wound down. The operator therefore lost an unrelated running pool AND still had the pool they meant to stop running. Note the consume log records path and content but no runId, so even post-hoc attribution required cross-referencing claim timestamps against checkpoint tags in two repos. <!-- id:9ddd -->

## Original title (verbatim, before the `id:64f9` rewrite)

/relay stop CANNOT TARGET A POOL: the STOP sentinel is a single shared path (~/.config/relay/STOP, RELAY_STOP_PATH) carrying only a round COUNT and no run id, so with N live pools it stops whichever reaches a round boundary first — an arbitrary one, not the one the operator meant. Same root cause hits RELAY_STATUS.md, also a single shared path: a second pool REWRITES it and destroys the first pool's progress view. Observed live 2026-07-29 with two concurrent pools (loderite relay-20260729-112410-25861 and dotclaude-skills relay-20260729-142725-13077): the second reset the shared status file to round=1 completed=0 while the first had 8 completed, making the first pool unobservable; then a stop intended for loderite sat as a global sentinel either pool could consume. It happened to hit loderite, by timing luck, not by design. This is NOT an edge case the design disallows — the id:11c6 singleton guard EXPLICITLY EXEMPTS --afk and scoped/directed runs so they CAN run in parallel, so the system deliberately permits N pools while two of its control and observability surfaces remain singletons. Asks: (1) scope the sentinel per run — accept a run id in the file or use a per-run path like STOP.<runId>, and have the prelude ignore a sentinel naming a different run; (2) make /relay stop take an optional run/repo target and default to LOUD-refusing when more than one pool is live rather than silently stopping an arbitrary one; (3) scope RELAY_STATUS.md per run, or have each pool merge into a shared file rather than overwrite it. Related: the stop consume log records path and content but NOT which run consumed it, so post-hoc attribution is impossible too **CONFIRMED OCCURRED, not hypothetical — same session, 30 minutes later.**
