# Human review queue <!-- budget: 15 min -->

Judgment calls encoded in red tests — confirm or correct the interpretation.
Max ~10 open boxes; the reviewer prunes resolved ones each review turn.

- [x] **id:a286 — `make test` is RED: id:34c2's integration (febb0c3) introduced a bare `rm -f`
  in `meeting/append.sh:384` that trips the repo's own `check-no-bare-rm-f.sh --enforce` lint
  (baseline 0), so the `lint` tier of `make test` now FAILS for every consumer** (review
  2026-07-17). The unit test tier is fully green (256 passed, 0 failed) — this is purely the
  new lint violation. The line is `rm -f -- "$tmp_check"` where `tmp_check` is a known-present
  `mktemp` file, so the CLAUDE.md destructive-op-hygiene fix is a one-liner: `rm -- "$tmp_check"`
  (or annotate `# force-ok: <reason>`). Filed as ROADMAP `[ROUTINE]` id:a286 (this pass could
  not fix it — the review's safety constraint bars touching `meeting/*.sh`). Root cause is a
  spec/lint gap in the id:34c2 handoff: the RED spec did not gate on the lint tier passing.
  **RESOLVED 2026-07-19 (relay human, verified):** the bare `rm -f` is gone from `meeting/append.sh` (grep clean), `tools/check-no-bare-rm-f.sh --enforce` = 0 violations within baseline, full suite 262/0/3-xred green. The root-cause lesson (a RED spec not gating on the lint tier) is exactly what the freshly-prepared **id:66d4** tier-coverage checkpoint gate enforces.

- [ ] **relay-doctor findings (review 2026-07-17, report-only, non-blocking).** Four are the
  cross-ledger drift this review RESOLVED in-pass by ticking the TODO twins of the integrated
  items (id:34c2, id:de36, id:1735, id:1102 — ROADMAP `[x]`, TODO was `[ ]`). Remaining, for a
  human's call: (1) **one parked orphan branch** `relay/orphan/blind-e02a-spec` in the loderite
  repo (a blind RED spec, `2c03545`) — cross-repo, not this repo's disposition; (2) **one inbox
  report-only finding** — a `[lodelore]` ORIGIN-MYTH item (`orphan 132`) whose `routed:` marker
  is a literal `$ID` placeholder, so it is not routable; a cross-project inbox line, not a
  dead-letter here. Neither blocks. relay-doctor otherwise clean (roadmap-lint clean, TODO
  conformance clean, main-checkout residue clean, last_ckpt resolves, no mechanical orphans).
- [ ] id:6e02 — LIVE-worktree sweep incident (2026-07-01 ~22:56): this review's own
  explicitly-created worktree + branch were deleted ~1 min after creation, mid-test-run,
  WHILE ~/.config/relay/claims/dotclaude-skills.json held a live claim (22:55:01). The
  child recovered (recreated + marker commit so tip≠main). No relay-loop was running
  (events end 20:45); reconcile log shows nothing at 22:5x — most consistent with an
  orchestrator-side cleanup treating a zero-commit branch (tip==main, `branch -d`-able)
  as an integrated leftover. Filed as TODO id:6e02 [HARD — meeting] (sweeps must honor
  claims; child setup should marker-commit first). Orchestrator: please confirm/deny
  running a worktree cleanup at ~22:56 so the finding pins the actual actor.
  ORCHESTRATOR ANSWER 2026-07-01: NOT the orchestrator (this session ran no cleanup at
  22:5x). Actor pinned by the bugfix child: run relay-20260701-225242-28925's dotclaude-skills
  integrator (dispatched 22:52:45, lease-refused handback ~22:56) applied its "tip-is-ancestor
  ⟹ integrated leftover" cleanup to a branch it didn't create, AFTER releasing the lease.
  Cleanup is now scoped to own-runId artifacts only (relay-loop.js, merged 2026-07-01); the
  remaining DESIGN CALL — destructive cleanup under-the-lease vs release-first (id:ebfb
  ordering) — is TODO id:6613 [HARD — meeting]. Box stays open only for that meeting call.
- [ ] Human-sprint 80/20 checklist (2026-07-02 Fable consulting session): pre-triaged
  tier-1 (minutes-each) + tier-2 (session-each) [HARD — hands] tasks across the fleet,
  ranked by unlock-per-minute — lanes already decided, context linked per item. Lives in
  the PRIVATE diary repo (fleet enumeration must not land in this public file):
  `~/src/claude-diary/docs/2026-07-02-human-sprint-8020.md`. Next `/relay human` should
  present it as the "you run these" checklist and tick items THERE; close this box when
  that doc is fully worked or superseded.
- [x] **id:b780 — a review child FIXED a flaky test in-flight; confirm that was in scope.**
  `tests/test_isolation_gate_wired.sh` intermittently failed (measured 1/25 idle, 22/40 under
  CPU load) via a >64 KB `printf | grep -q` SIGPIPE race under `pipefail` — grep matched
  (PIPESTATUS=[0]) but printf died 141 and pipefail promoted it to a failure. I fixed it here
  rather than only filing it, because the flake red-lights `make test` — the definition-of-done
  gate every execute unit depends on — and it indicts the id:7612 isolation gate, which is
  exactly the wrong signal. Mutation-tested (3/3 broken-gate variants still caught) so the spec
  is intact. **If you'd rather review children never touch non-ledger code, say so** and this
  becomes a [ROUTINE] item instead; the fix + evidence are in the commit either way.
  **RULED 2026-07-19 (relay human): OUT OF SCOPE.** A review pass returns a verdict; it does not mutate non-ledger code — a verifier that can fix the artifact it verifies can launder its verdict (chidiai `a-relay-review-sub-agent-scoped`; reviewer-read-only, now load-bearing in id:0c86/077d). The already-committed fix STAYS (correct + mutation-tested), but going forward such a fix is a HANDBACK / separate execute unit, not a review action — enforced structurally via id:077d/0c86.
- [x] **id:521f / routed:f1f5 + id:1312 — same defect class, possibly one fix.** Both are
  unanchored token greps over prose-bearing ledger lines (roadmap-lint's first-match `id_re`;
  unpromoted-scan's bare `grep -qF`). `scan-routed.sh` already anchors correctly. This is the
  4th instance of the family (with `inbox-done`'s substring match and md-merge's fail-open
  append, id:1b1a). **Worth one shared anchored-extraction helper + its own test rather than a
  third hand-rolled copy?** That's a design call, not a review verdict — hence a box, not a
  ROADMAP decision. Related: the id:2c94 duplication linter would flag the copies mechanically.
  **DECIDED 2026-07-19 (relay human): BUILD one shared anchored-extraction helper + test** (dedup the 4th instance of the family; route roadmap-lint's first-match `id_re`, unpromoted-scan's `grep -qF`, and the copies through it — model it on `scan-routed.sh`, which already anchors correctly). Filed as `[ROUTINE]` id:3add.
- [ ] **Repo-wide: is the `printf "$big" | grep -q` + `pipefail` pattern worth a lint?** id:b780
  was one instance; 23 files pair `pipefail` with an early-exiting reader on a pipe. Only
  payloads >64 KB (the pipe buffer) can bite, so today `relay-loop.js` (91 KB) is plausibly the
  sole live case — I did NOT sweep or "fix" the others, per observe-before-preventing. Recorded
  so the decision is yours: leave it, or add a check to `tools/` if it recurs. Note any such
  lint must run under real `bash` — under `zsh` the race does not reproduce at all.
- [ ] **id:de31 — `orphan-scan --shipped` says TICK-READY; I verified it and did NOT tick.**
  The scan is right that `tests/test_decision_queue.sh` is green with no gating lexeme, but the
  test's own header declares a NARROWER scope than the item: "In scope here: the record format
  + the flock'd add/list/resolve helper." C7 (id:de31) additionally requires *the forced-
  resolution WRITE at the lane-triage point (case g/h can never silently no-op)* and *the
  conservative inline lane-triage sub-agent* — neither is exercised. Ticking on the green test
  would freeze the item's harder half as "done". Recorded so the next review doesn't re-litigate
  the same advisory hit. **The generalizable point**: TICK-READY correlates an item to a linked
  test but cannot see that the test's declared scope is a SUBSET of the item's acceptance — so
  a partially-specced item reads as shippable. That is inherent to the heuristic (it is advisory
  by design, which is why §5 mandates this manual verify), but if this recurs it argues for
  scope-declaring test headers being machine-read, or splitting C7's remaining halves into their
  own ids. Your call — no ledger change made.
- [ ] **id:eb46 — promoted [ROUTINE], but its lane may need to flip to [INPUT — user].** The
  handoff promoted the "relay children need a failing askpass (`SUDO_ASKPASS=/bin/false`) so a
  sub-process `sudo` can't pop a GUI prompt" item as `[ROUTINE]` with a built-in BAILOUT GUARD:
  if the ONLY reachable env-injection point turns out to be `~/.claude/settings.json` `env`, the
  executor must STOP and re-lane `[INPUT — user]` rather than edit settings.json from a worktree
  (that file is deliberately relay-untouched). The judgment call for the human/reviewer: is there
  an in-repo/pool-launch injection point at all, or is this really a settings.json change (hence
  `[INPUT — user]`, not executor-pool work)? `relay-loop.js` spawns children via the Workflow
  `agent()` API with no reachable `process.env` inside the sandbox (L1907), so the env is set at
  pool launch OUTSIDE the repo — which makes the settings.json outcome plausible. Recorded so the
  next executor's bailout (or the reviewer's re-lane) isn't re-litigated. No fresh RED test (the
  fix's location, not its logic, is the open question). <!-- roadmap:eb46 -->
- [x] **id:ac7f — handoff-authored interface for the `drained` render-alias.** The RED spec pins a NEW `relay/scripts/render-verdict.sh` (stdin classify-verdict JSON → label; `idle`→`drained`, else verbatim) as the D1 render-alias home. D1 mandates "render-alias, no new enum" but names no script — this interface is the handoff author's choice among defensibles (a separate script vs. a flag on an existing renderer vs. a reviewer-prose convention). Confirm the separate-script shape is what you want before the executor builds it. — **CONFIRMED 2026-07-19 (relay human): separate `render-verdict.sh` is the intended shape.** As-built matches; no change. <!-- roadmap:ac7f -->
- [x] **id:66d4 — tier-enumeration + toolchain-marker heuristics chosen by the spec.** `test_review_gate_tier_coverage.sh` exercises ONE declared-tier source (package.json `scripts` keys containing "test") and ONE toolchain-presence marker (populated `<dir>/node_modules`). The item also names Makefile targets / CI config / `~/.cache/ms-playwright` — the executor may add them, but the spec only proves the package.json+node_modules path. Judgment: is that enough coverage for the gate's first cut, or must the RED spec also pin a Makefile-tier fixture? — **RULED 2026-07-19 (relay human): NOT enough — the RED spec MUST also pin a Makefile-tier fixture.** The shipped `review-gate.sh` already enumerates Makefile `test`-named targets, but the test only proves the package.json path, so that code path is unspecced. Follow-up filed → TODO id:050b (add a Makefile-tier fixture to the RED spec). <!-- roadmap:66d4 -->
- [x] **id:78df — consumer-enum is a content-grep listing aid, not import-graph analysis.** `test_consumer_enum.sh` pins `consumer-enum.sh <artifact>` = "every file whose CONTENT references the token, .git excluded, exit 0 always". It does NOT resolve real import/read edges (a false positive on a mention-in-a-comment is accepted — it is a surfacing aid, per D6/id:78df "listing aid, not a gate"). Confirm the plain-grep semantics are the intended aid. — **RULED 2026-07-19 (relay human): NOT the intended endpoint — it should resolve real import/read edges, not text mentions.** The shipped content-grep aid stands as the first cut; the upgrade to import-graph analysis is filed as follow-up → TODO id:494f. <!-- roadmap:78df -->
- [ ] **The "promote backlog" is mostly PHANTOM/mis-classified — only id:798d was a real promotion this handoff (run relay-20260719-132549-15264).** `unpromoted-scan.sh` reported 7 `promote` items; on inspection only **id:798d** was clean executor work (promoted with RED spec `tests/test_unpromoted_scan_gated_twin.sh`). The other 6 each carry a lane/scope/identity question a handoff must NOT resolve by guessing (owner-decision territory) — surfaced here, deliberately NOT re-laned or promoted:
  - **id:659c, id:401c — 798d-bug PHANTOMS.** Both already have a ROADMAP twin, but their `<!-- id -->` marker is followed by a trailing gate/DONE note, so the end-of-line-strict twin check (the exact 798d bug) misses them and re-reports the TODO source as `promote`. **Shipping id:798d drains these two automatically** — no separate action.
  - **id:d5e0 — an audit-summary line, not a task.** It is the rolling "Relay: N open ROADMAP items" summary maintained by id:401c's audits; its removal is already owned by **id:1de1** ("drop the count prose once `proj relay`/the id:2840 index is the count authority") and id:4d8e case-(3) explicitly names it as a summary line the classifier should SKIP. It is mis-tagged `[ROUTINE]` → mis-classified `promote`. Do NOT promote; the real fix is the classifier skipping audit lines (id:4d8e) — deliberately retained until id:1de1 ships.
  - **id:2e6d — a mostly-SHIPPED umbrella.** Its core dissolution shipped 2026-07-10 (`tools/memory-index.py` now GENERATES the index; `--check` is the enforcing lint; `hooks/memory-index-sync.py` PostToolUse shipped). Residual = child **id:7d97** (add `user:`-prefix/emphasis invariants to `--check`) + a `[INPUT — user]` settings.json hook install. The umbrella is open+`[ROUTINE]` so it reads `promote`, but there is no fresh executor work in the parent itself — it should be `@container`/closed, a judgment for you.
  - **id:02c7 — OS-ACL access work mis-tagged `[ROUTINE]`.** "Per-directory named POSIX ACLs on `~/.config/relay`" is `setfacl` OS provisioning, part of the os-users design ([[os-users]] — nothing provisioned; needs credential/consent). This is `[INPUT — access]`, not worktree-buildable executor routine.
  - **id:3add — a refactor that reopens a recorded decision.** "Shared anchored-extraction helper + test" (relay human 2026-07-19) wants to migrate the 4 hand-rolled extractors onto one helper — but `relay/scripts/lib-anchored-id.sh`'s header (id:521f, lines 14-26) explicitly RECORDS a decision NOT to unify `unpromoted-scan.sh`/`scan-routed.sh` onto it (different problem shape: presence-check vs extract-unknown-id). Promoting 3add requires reconciling with that recorded rationale, and it is a behaviour-preserving refactor (id:108e — unverifiable by a classic RED test; belongs to `/relay refactor`, id:22da). Not a blind `[ROUTINE]` promote. NB: id:798d fixes ONE instance (unpromoted-scan's twin check) of the family 3add would unify — sequence 798d first, then let 3add subsume the pattern.
  - **id:2d20 — targets sandbox-gated `relay-loop.js`.** "Pool busy-loops re-dispatching un-doable HARD units" is a `relay-loop.js` fix; that file runs only in the Workflow sandbox ([[sandbox-2ec4]] — no in-repo mechanical dispatch), so a RED spec cannot be verified from a worktree. Needs the sandbox-testability question answered before it is executor-promotable.
  **Net**: this repo's apparent promote backlog is an artifact of the id:798d bug (2 phantoms) + known classifier gaps (id:4d8e audit-line skip) + three mis-tagged/umbrella items — not undispatched executor work. Ship id:798d; then a human re-lane pass (or id:4d8e's classifier) should stop the pool re-dispatching handoffs here. No ledger re-lanes made (owner's call). <!-- handoff:relay-20260719-132549-15264 -->
