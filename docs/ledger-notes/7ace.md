# id:7ace

Relocated from the ledger by `tools/ledger-shrink.py`. Conventions, the verbatim
claim and backlinks: `docs/ledger-notes/README.md`.

## From TODO

— `gather-human-backlog.sh` re-derives gated items by grepping ROADMAP every run (nothing goes stale), and the relay pool's `discover-sig.sh` re-classifies on signature change — but there is NO active "external gate now satisfied → surface as actionable" detection. Gates that resolve *outside* the repo change nothing in-repo, so they keep re-emitting as "needs a /meeting" until a human notices: chidiai id:1e77 (≥50 outcome rows accumulate), proton-moresync id:5cc5 (first external user), zomni id:7cf2 (an OOM-kill / PSI-full stall fires), ai-codebench id:efc2 (the 244b GPU matrix run finishes). **Fix directions**: a per-item machine-checkable gate predicate the collector/discovery evaluates (flips gated_hard→actionable when met), or a periodic gate-recheck pass. Surfaced as the user's side-question during the 2026-06-18 cross-gated-HARD triage. See `docs/meeting-notes/2026-06-18-1219-cross-gated-hard-triage.md`. <!-- id:7ace -->
