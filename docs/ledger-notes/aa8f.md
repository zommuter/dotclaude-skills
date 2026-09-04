# id:aa8f

Relocated from the ledger by `tools/ledger-shrink.py`. Conventions, the verbatim
claim and backlinks: `docs/ledger-notes/README.md`.

## From TODO

— blast-radius review. (1) **`priority_rank` scale mismatch**: `id:bc2b`'s demotion assigns from the JS `PRIORITY` map (execute:0, review:1) while classifier units carry the SHELL scale (execute:1, review:2), so a demoted unit reports a rank one lower than an identical undemoted one. Harmless for dispatch — the sort keys on `PRIORITY[a.verdict]`, not on `priority_rank` — but the emitted telemetry is inconsistent, and anything later built on that field inherits the inconsistency. Note separately that the non-monotonic cascade (`review` rank 2 above `execute` rank 1) is PRE-EXISTING and was introduced by `id:8123`, not by bc2b — independently confirmed against the pre-change script. (2) **`id:4a76` in-code comment is FALSE**: it claims adding `[INPUT — author]` to `HUMAN_GATES` was *"purely ADDITIVE … it wasn't in LANE_TAGS either"*, but `LANE_TAGS` is defined as `(...) + HUMAN_GATES`, so the addition DID land in `LANE_TAGS`. A line where `[INPUT — author]` precedes `[ROUTINE]` therefore flips from actionable to human. The DIRECTION is safe (fewer dispatches, never more) — only the comment is wrong, and a future reader trusting it would mis-reason about lane precedence. Relates id:bc2b, id:4a76, id:8123. <!-- id:aa8f -->
