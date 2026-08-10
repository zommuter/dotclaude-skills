# TODO — repo-alpha (fixture)

Fixture ledger for TODO id:2bb1. Exercises every construct `tracker/SCHEMA.md` claims
a mapping or an explicit loud-lossy policy for. Not a real repo.

## ledger substrate

- [ ] [HARD] Item OPEN in TODO, DONE in ROADMAP — the cross-ledger drift case <!-- children-of:4a5c --> <!-- id:1111 -->
  - **Acceptance** both statuses survive the round-trip
  - **Tests** tests/test_tracker_schema_drift_roundtrip.sh
- [x] [ROUTINE] Item DONE in TODO, OPEN in ROADMAP — drift in the other direction <!-- id:2222 -->
- [ ] [HARD] Item open in both ledgers, no drift <!-- gated-on:1111 --> <!-- id:3333 -->
- [x] [ROUTINE] Item done in both ledgers <!-- id:4444 -->
- [ ] [INPUT — meeting] Lives only in TODO — roadmap_status must be `absent`, not `open` <!-- id:5555 -->
- [ ] [MECHANICAL] [INTENSIVE — local-llm] [host:zomni] Composed capability + resource + host tags <!-- id:6666 -->
- [ ] [HARD — hands] Legacy venue-keyed lane with NO 1:1 successor — must map to input:unresolved-hands and be REPORTED <!-- id:7777 -->
- [ ] [HARD — pool] Legacy pool lane — 1:1 rename to [HARD] <!-- children:3333,4444 --> <!-- id:8888 -->
- [ ] [ROUTINE] @manual @needs-auth Human must run it AND supply a secret <!-- id:9999 -->
- [x] [ROUTINE] @owner-accepted:2026-08-01 Owner-granted acceptance receipt <!-- id:aaaa -->
- [ ] [ROUTINE] 🚧 BLOCKED on an upstream decision <!-- id:bbbb -->
- [ ] [ROUTINE] Cross-repo routed item — the token also exists in repo-beta <!-- routed:cafe --> <!-- id:cccc -->
- [ ] [ROUTINE] Locally-minted `cafe` — the SAME bare token repo-beta also minted, and repo-alpha routes to it: class-B ambiguous reference <!-- id:cafe -->
- [ ] Id-less TODO line — no anchored marker at all, must import as identity=untracked
- [ ] [FOO] @bogus-marker Unknown tag and unknown marker — both reported, neither silently dropped <!-- id:dddd -->

## Done
