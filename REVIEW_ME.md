# Human review queue <!-- budget: 15 min -->

Judgment calls encoded in red tests — confirm or correct the interpretation.
Max ~10 open boxes; the reviewer prunes resolved ones each review turn.

- [ ] **id:a286 — `make test` is RED: id:34c2's integration (febb0c3) introduced a bare `rm -f`
  in `meeting/append.sh:384` that trips the repo's own `check-no-bare-rm-f.sh --enforce` lint
  (baseline 0), so the `lint` tier of `make test` now FAILS for every consumer** (review
  2026-07-17). The unit test tier is fully green (256 passed, 0 failed) — this is purely the
  new lint violation. The line is `rm -f -- "$tmp_check"` where `tmp_check` is a known-present
  `mktemp` file, so the CLAUDE.md destructive-op-hygiene fix is a one-liner: `rm -- "$tmp_check"`
  (or annotate `# force-ok: <reason>`). Filed as ROADMAP `[ROUTINE]` id:a286 (this pass could
  not fix it — the review's safety constraint bars touching `meeting/*.sh`). Root cause is a
  spec/lint gap in the id:34c2 handoff: the RED spec did not gate on the lint tier passing.

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
- [ ] **id:b780 — a review child FIXED a flaky test in-flight; confirm that was in scope.**
  `tests/test_isolation_gate_wired.sh` intermittently failed (measured 1/25 idle, 22/40 under
  CPU load) via a >64 KB `printf | grep -q` SIGPIPE race under `pipefail` — grep matched
  (PIPESTATUS=[0]) but printf died 141 and pipefail promoted it to a failure. I fixed it here
  rather than only filing it, because the flake red-lights `make test` — the definition-of-done
  gate every execute unit depends on — and it indicts the id:7612 isolation gate, which is
  exactly the wrong signal. Mutation-tested (3/3 broken-gate variants still caught) so the spec
  is intact. **If you'd rather review children never touch non-ledger code, say so** and this
  becomes a [ROUTINE] item instead; the fix + evidence are in the commit either way.
- [ ] **id:521f / routed:f1f5 + id:1312 — same defect class, possibly one fix.** Both are
  unanchored token greps over prose-bearing ledger lines (roadmap-lint's first-match `id_re`;
  unpromoted-scan's bare `grep -qF`). `scan-routed.sh` already anchors correctly. This is the
  4th instance of the family (with `inbox-done`'s substring match and md-merge's fail-open
  append, id:1b1a). **Worth one shared anchored-extraction helper + its own test rather than a
  third hand-rolled copy?** That's a design call, not a review verdict — hence a box, not a
  ROADMAP decision. Related: the id:2c94 duplication linter would flag the copies mechanically.
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
