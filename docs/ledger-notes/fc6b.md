# id:fc6b

Relocated from the ledger by `tools/ledger-shrink.py`. Conventions, the verbatim
claim and backlinks: `docs/ledger-notes/README.md`.

## From TODO

— observed live 2026-08-21 in the tracker meeting. The hook (`hooks/meeting-question-guard.py`, routed:29bc / id:2419) BLOCKED a turn at 4,798 chars of transcript prose with no `AskUserQuestion`, then did NOT fire on a later same-session turn of comparable length and shape (~3,000+ chars of persona transcript, no tool call, meeting note not yet written), and DID fire again on a third. The threshold is documented as ≥800 chars, so all three should have blocked. A guard that catches one instance and not the next is worse than none: it trains the reader to trust that silence means compliance (the id:4347 no-silent-swallow shape, inverted). Investigate whether the arming state is consumed by the first block, whether transcript-detection misclassifies a turn that reports background-agent results alongside transcript, or whether the char count excludes some block types. Contract a test would verify: three successive same-session turns each ≥800 chars of meeting prose with no AskUserQuestion each block. <!-- id:fc6b -->
