# id:ad9d

Detail relocated out of the ledger by `tools/ledger-shrink.py`. The item line keeps
its title, lane tag, `id:` anchor, every gate marker and a pointer back here.
**Nothing was deleted** -- the prose below is reproduced verbatim.

See `docs/ledger-notes/BACKLINKS.md` for meetings that cite this id.

## From TODO

— observed 2026-06-26 in a kienzler-homepage session (Opus 4.8): the statusline `💸` cost read **~$8.10**, then **$12.89** later in the same session, while an independent recompute from the transcript via `~/.claude/skills/meeting/cost-of.sh` + Opus 4.8 list pricing (in $5 / out $25 / cache-read $0.50 / cache-write-5m $6.25 per MTok) came to **≈$16.70** (cache-read dominated: ~18.4M cache-read tokens). The two disagree by ~2×. Hypothesis: the statusline reports a **subscription-effective / amortised** rate (Max-plan / fast-mode), not pay-as-you-go list price — but this is unconfirmed. **Action:** (a) find where `statusline/statusline-command.sh` sources the cost number (the `/api/oauth/usage` object on stdin? a `cost_usd` field? a local multiplier?); (b) determine whether it's list-price or plan-effective, and document which in the statusline docs so the figure isn't mistaken for billable API spend; (c) if it IS list-price, reconcile why it undercounts cache-read-heavy sessions by ~2× (cache-tier rate applied wrong? output-only?); (d) consider exposing both numbers or a tooltip/legend. Relates the id:81cb model-readable state-file (same cost source) and `cost-of.sh`. <!-- id:ad9d -->
