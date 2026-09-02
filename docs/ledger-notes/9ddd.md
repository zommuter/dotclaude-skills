# id:9ddd

Detail relocated out of the ledger by `tools/ledger-shrink.py`. The item line keeps
its title, lane tag, `id:` anchor, every gate marker and a pointer back here.
**Nothing was deleted** -- the prose below is reproduced verbatim.

See `docs/ledger-notes/BACKLINKS.md` for meetings that cite this id.

## From TODO

The stop was issued FOR loderite and was consumed by the OTHER pool. Timeline: sentinel written 14:28; consumed 14:32:01 per the consume log; loderite RE-CLAIMED its repo at 14:34:08 and went on to checkpoint relay-ckpt-20260729-1412 / 1423 / 1433, so loderite demonstrably never stopped; meanwhile dotclaude-skills' claim froze at 14:28:10 with its last commit at 14:20 and last checkpoint at 1255 — i.e. the pool the operator did NOT target is the one that wound down. The operator therefore lost an unrelated running pool AND still had the pool they meant to stop running. Note the consume log records path and content but no runId, so even post-hoc attribution required cross-referencing claim timestamps against checkpoint tags in two repos. <!-- id:9ddd -->
