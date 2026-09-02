# id:abe7

Detail relocated out of the ledger by `tools/ledger-shrink.py`. The item line keeps
its title, lane tag, `id:` anchor, every gate marker and a pointer back here.
**Nothing was deleted** -- the prose below is reproduced verbatim.

See `docs/ledger-notes/BACKLINKS.md` for meetings that cite this id.

## From TODO

Q: how do we make pre-committed gates MECHANICALLY hard to relax or violate regardless of which model tier is running (a lower-tier executor OR a silently-downgraded reviewer)? Candidate directions: (a) encode gate criteria as machine-checked assertions (an irreversible flip may not ship while its own acceptance gate is RED, and may not delete its shadow comparator until the gate passes — cf. routed:2809); (b) promote the decide-then-do-it lint to a hard block on 2nd occurrence (routed:8f84); (c) a gate-relaxation-requires-explicit-re-ratification record; (d) detect serving tier at decision points and require stronger confirmation when a gate is being waived by a downgraded/lower tier. Root motivation: silent Fable-to-Opus refusal-fallback altered outcomes on ~40 percent of a decision batch; gate discipline should not depend on the serving tier <!-- id:abe7 -->
