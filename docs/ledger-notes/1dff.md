# id:1dff

Detail relocated out of the ledger by `tools/ledger-shrink.py`. The item line keeps
its title, lane tag, `id:` anchor, every gate marker and a pointer back here.
**Nothing was deleted** -- the prose below is reproduced verbatim.

See `docs/ledger-notes/BACKLINKS.md` for meetings that cite this id.

## From TODO

— pilot run relay-20260612-2304: 13 execute units consumed the entire quota budget; all 7 review units were quota-deferred, so the anti-gaming window (D3's whole point: review ranks above fresh handoff to keep unaudited work short-lived) stays open across the run. Execute-first is correct *within* abundant quota, but under a binding quota the last units dispatched should not all be executes. Candidate designs: (a) reserve a review quota slice (e.g. stop dispatching executes at threshold−N pp so reviews fit); (b) interleave classes round-robin after the first pool fill; (c) cap executes per run at POOL_WIDTH×k when reviews are queued. Judgment call on D3 semantics — design before the next fleet-wide run, ideally via `/meeting`. <!-- id:1dff -->
