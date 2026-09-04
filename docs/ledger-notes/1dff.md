# id:1dff

Relocated from the ledger by `tools/ledger-shrink.py`. Conventions, the verbatim
claim and backlinks: `docs/ledger-notes/README.md`.

## From TODO

— pilot run relay-20260612-2304: 13 execute units consumed the entire quota budget; all 7 review units were quota-deferred, so the anti-gaming window (D3's whole point: review ranks above fresh handoff to keep unaudited work short-lived) stays open across the run. Execute-first is correct *within* abundant quota, but under a binding quota the last units dispatched should not all be executes. Candidate designs: (a) reserve a review quota slice (e.g. stop dispatching executes at threshold−N pp so reviews fit); (b) interleave classes round-robin after the first pool fill; (c) cap executes per run at POOL_WIDTH×k when reviews are queued. Judgment call on D3 semantics — design before the next fleet-wide run, ideally via `/meeting`. <!-- id:1dff -->
