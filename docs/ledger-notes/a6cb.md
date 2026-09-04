# id:a6cb

Relocated from the ledger by `tools/ledger-shrink.py`. Conventions, the verbatim
claim and backlinks: `docs/ledger-notes/README.md`.

## From TODO

— observed 2026-06-16. A parallel `/meeting` session implemented id:689c (relay-loop.js orphan-park, D1) — it committed the RED spec (`tests/test_relay_orphan_park.sh`, 8044d2a) but ENDED leaving the matching `relay-loop.js` impl change UNCOMMITTED in the working tree. A sibling session found it dirty and committed it on its behalf (796e275) after verifying spec-green + structure-green. So /meeting's Class 1 dispatch (D7, "work as a /relay executor: append RELAY_LOG + commit") and/or the global post-prompt git-diary-workflow obligation did NOT commit the impl — only the spec landed. Possible causes: (a) Class 1 inline implementation didn't run git-diary-workflow before the session ended; (b) the session was interrupted between the spec-commit and the impl-commit; (c) the end-of-meeting steps don't assert a clean tree. WANTED: an end-of-meeting / end-of-turn guard that refuses to finish with un-committed working-tree changes the session itself made (or at least surfaces them loudly). Especially important for SHARED repos — a /meeting leaving dotclaude-skills dirty strands work for sibling sessions and risks a relay pool committing a half-finished spec file. Relates to the git-diary-workflow parallelity bug (claude-diary TODO) and the shared-repo attribution discipline (global CLAUDE.md Step 1c). <!-- id:a6cb -->
