# Human review queue — repo-alpha (fixture) <!-- budget: 15 min -->

- [ ] **Anchored box** — attaches to the id:3333 ledger item via its roadmap marker, so it sets review_status on THAT item rather than minting a second one. <!-- roadmap:3333 -->
- [ ] **Unanchored box** — no id/roadmap marker at all; imported as a standalone untracked review_box, never silently skipped.
- [x] **Resolved unanchored box** — review_status=done.
