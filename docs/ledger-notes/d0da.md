# id:d0da

Relocated from the ledger by `tools/ledger-shrink.py`. Conventions, the verbatim
claim and backlinks: `docs/ledger-notes/README.md`.

## From TODO

(user 2026-06-15) — add `[HUMAN]` (trivial human input: confirm / yes-no / run an @manual scenario) and `[MEETING]` (non-trivial design judgment) to the `[ROUTINE]`/`[HARD]` family, completing the actor↔tag↔surface map (HUMAN→`/relay human` tier-A/B, MEETING→`/meeting --cross` tier-C). Closes the untagged-open-item-invisible-to-classifier gap (untagged → lint / reverse-handoff trigger; a repo whose only open work is HUMAN/MEETING stops reading `idle`). **HINTS not gates**: `/relay human` answerability triage still refines (a stale `[HUMAN]` may auto-resolve; a `[MEETING]` may demote to a batch yes/no). `@manual` ⊂ `[HUMAN]` (run-flavored, never auto-tick); REVIEW_ME membership is already an implicit HUMAN signal, so tags matter mainly on ROADMAP/TODO. Multi-file contract change: classify.sh, relay-loop.js discovery, review.md §5b reverse-handoff (assign HUMAN/MEETING, not force-HARD), executor-contract docs, `/relay human`. Sequence AFTER id:72cc (/relay human) + id:962a land. <!-- id:d0da -->
