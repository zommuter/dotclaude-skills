# id:fee1

Relocated from the ledger by `tools/ledger-shrink.py`. Conventions, the verbatim
claim and backlinks: `docs/ledger-notes/README.md`.

**EDITED 2026-09-03 (`id:64f9`, title rewrite) -- declared, per the notes-are-editable
convention in `CLAUDE.md`.** This item's ledger TITLE in `TODO.md` was rewritten to fit
`LEDGER_ITEM_TITLE_MAX`. Nothing else on the item line changed: lane tags, typed-edge and
`id:` markers, the detail pointer and the checkbox are all untouched. The ORIGINAL title is
reproduced VERBATIM in the final section of this note, so no wording was deleted -- it moved
here. The relocated prose below is otherwise unchanged.

## From TODO

Resolve whether a background Sonnet agent should spawn the 3 stages as its own nested background agents vs. the parent driving them flat (sequential + verification-gated between stages favours flat) <!-- id:fee1 -->

## Original title (verbatim, before the `id:64f9` rewrite)

Make "do this TODO in background" auto-run the relay handoff→execute→review round with adequate models (Opus handoff/review, Sonnet executor) IFF the repo is /relay-enabled (has ROADMAP.md); consider a `/relay bg` subcommand.
