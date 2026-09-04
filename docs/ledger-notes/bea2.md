# id:bea2

Relocated from the ledger by `tools/ledger-shrink.py`. Conventions, the verbatim
claim and backlinks: `docs/ledger-notes/README.md`.

## From TODO

`[HARD — pool]` (meeting 2026-07-19-1152, af48 child C2) — flag `@manual` items that look executor-doable (heuristic: a linked host-runnable test exists, the repo ships an e2e harness, the item references a call-site/wiring). **Fails toward `@manual`** (under-dispatch is safe per `classify-repo:128`; a wrong `@wire` could dispatch a hardware check to an executor — the unsafe direction) and **NEVER auto-converts** — surfaces candidates for per-repo handoff judgment ([[conformance-pilot]]). <!-- children-of:af48 --><!-- gated-on:ac7f --><!-- id:bea2 -->
