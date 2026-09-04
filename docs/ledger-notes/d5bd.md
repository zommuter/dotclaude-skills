# id:d5bd

Relocated from the ledger by `tools/ledger-shrink.py`. Conventions, the verbatim
claim and backlinks: `docs/ledger-notes/README.md`.

## From TODO

— split out 2026-07-31 (owner-decided, `/relay human`) from id:82c4, whose "ZERO mismatches / flip-gate MET" body was stale by ~281 mismatches. **State**: `relay-doctor.sh .` reports **95663 rounds / 281 mismatches (~0.29%)** in `~/.claude/logs/relay-core-shadow.jsonl`, up from 88436/253 days earlier — so the divergence is ACCRUING, not a settled historical artifact. **Nothing is broken in production**: the shadow is report-only and the bash path stays authoritative, which is precisely the design working. **What to do**: classify the 281 by failure shape — are they one systematic serializer/ordering difference (cheap, likely a single fix) or a long tail of genuine logic divergence (expensive, and a real signal about the Lean port)? The distinction is the whole point: a single systematic cause would make the flip gate re-achievable, a long tail would not, and *nobody currently knows which it is*. Bucket by input class and diff shape before proposing any fix. **Out of scope — explicitly NOT this item**: the flip decision itself, which stays the owner's call at the island-2 go/no-go (**id:ebdb**); do not record a GO/NO-GO here. The Lean substrate lives in the sibling repo `~/src/relay-core`, so a fix may land there rather than here. Relates `id:82c4`, `id:23ab`, `id:ebdb`. <!-- id:d5bd -->
