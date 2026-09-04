# id:abe7

Relocated from the ledger by `tools/ledger-shrink.py`. Conventions, the verbatim
claim and backlinks: `docs/ledger-notes/README.md`.

**EDITED 2026-09-03 (`id:64f9`, title rewrite) -- declared, per the notes-are-editable
convention in `CLAUDE.md`.** This item's ledger TITLE in `TODO.md` was rewritten to fit
`LEDGER_ITEM_TITLE_MAX`. Nothing else on the item line changed: lane tags, typed-edge and
`id:` markers, the detail pointer and the checkbox are all untouched. The ORIGINAL title is
reproduced VERBATIM in the final section of this note, so no wording was deleted -- it moved
here. The relocated prose below is otherwise unchanged.

## From TODO

Q: how do we make pre-committed gates MECHANICALLY hard to relax or violate regardless of which model tier is running (a lower-tier executor OR a silently-downgraded reviewer)? Candidate directions: (a) encode gate criteria as machine-checked assertions (an irreversible flip may not ship while its own acceptance gate is RED, and may not delete its shadow comparator until the gate passes — cf. routed:2809); (b) promote the decide-then-do-it lint to a hard block on 2nd occurrence (routed:8f84); (c) a gate-relaxation-requires-explicit-re-ratification record; (d) detect serving tier at decision points and require stronger confirmation when a gate is being waived by a downgraded/lower tier. Root motivation: silent Fable-to-Opus refusal-fallback altered outcomes on ~40 percent of a decision batch; gate discipline should not depend on the serving tier <!-- id:abe7 -->

## Original title (verbatim, before the `id:64f9` rewrite)

Design tier-robust gate-discipline mechanisms (for a Fable session to consider): the 2026-07-02 Fable un-downgraded re-review found the Opus-downgraded meeting session softened 3/8 decisions, all toward relaxing pre-agreed gates / defer-and-track (kept a gate-violating irreversible flip live D3; decide-then-do-it bypass D4; deferred a cheap mechanical guard D7).
