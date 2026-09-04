# id:2cfe

Relocated from the ledger by `tools/ledger-shrink.py`. Conventions, the verbatim
claim and backlinks: `docs/ledger-notes/README.md`.

## From TODO

(owner-decided 2026-08-11). The contract already makes a sized-out child return `route=hard-split | decision-gate | human`; `id:3801` collapses all of them onto a human gate, so "too big for one turn" becomes "needs a human decision" — and the pool stops trying at exactly the items that wanted a bigger budget. FIX: map the routes faithfully — `hard-split` becomes a DECOMPOSITION request that stays **pool-eligible** (the seams get worked, not parked), and only `decision-gate`/`human` reach the human lists. `id:3801`'s anti-respin purpose is preserved: the parent is still re-tagged so the identical un-doable unit is never re-dispatched unchanged. Context: `id:4b64` already made the emitted tag canonical (`[INPUT — decision]`), which moved auto-gated size-outs from the meeting list to the human-decision list and made this conflation MORE visible. Contract: a fixture handback with `route=hard-split` yields pool-eligible seams and NO human-lane item; one with `route=decision-gate` yields exactly one human-lane item; neither re-dispatches the unchanged parent. <!-- children-of:3801 --> <!-- id:2cfe -->
