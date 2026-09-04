# id:c0bc

Relocated from the ledger by `tools/ledger-shrink.py`. Conventions, the verbatim
claim and backlinks: `docs/ledger-notes/README.md`.

## From TODO

— user request 2026-06-17. The Claude Code statusline cost figure appears to count only the main loop, not the tokens spent by spawned `Agent`/Workflow subagents — so a session that fans out many background agents (observed: a directed `/relay --afk` run spawned ~16 background Opus children) badly UNDERcounts true spend. WANTED: the statusline reflects total spend = main loop + all spawned agents + workflows, either (a) folded into the existing `$` cost number, or (b) shown as a second segment (e.g. `$<main> +$<agents>` or `Σ$<total>`). Note the relay already has a live statusline segment (id:15bd: `🔁<round> ✓<done> ⚙<in-flight> Δ$<burn>/h` from RELAY_STATUS.md) and `relay-burn.sh`/`relay-econ.py` already attribute per-agent cost from `profile-run.sh` records — so the data exists; this is about surfacing the AGGREGATE in the always-on statusline, not just during relay runs. Design qs: where the per-agent token usage is readable for the statusline script (agent JSONL transcripts? a running tally file?); main-loop-only vs session-total semantics; how it composes with the existing relay segment so they don't double-count. (user request 2026-06-17) <!-- id:c0bc -->
