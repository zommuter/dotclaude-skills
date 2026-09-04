# id:1ffc

Relocated from the ledger by `tools/ledger-shrink.py`. Conventions, the verbatim
claim and backlinks: `docs/ledger-notes/README.md`.

## From TODO

— today `income = true/false` is a single boolean used only for slot-contention tiebreaking. Richen it so income-relevant repos can be ranked/scheduled by more than a flag: e.g. estimated success **chance**, expected **value**, and **timeline/deadline** (a repo shipping for a fixed date should outrank an open-ended one), or a small set of **tags**. Decide the schema (structured sub-table vs tags), how the scheduler consumes it (weighting within the income class), and keep it back-compatible with the existing boolean. Motivating case: yinyang-puzzle (Tesserene wood puzzle) + puzzle-pwa both flagged income with a hard Christmas-2026 ship goal — a boolean can't express "funded, deadline-driven, high-value" vs "someday-maybe income". <!-- id:1ffc -->
