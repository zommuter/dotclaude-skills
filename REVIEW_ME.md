# Human review queue <!-- budget: 15 min -->

Judgment calls encoded in red tests — confirm or correct the interpretation.
Max ~10 open boxes; the reviewer prunes resolved ones each review turn.

- [ ] **`roadmap-lint` WARN: DECIDED-LEFT-OPEN on id:de4e (review 2026-07-11 1236).**
  `- [ ] [INPUT — meeting] DEFERRED (decided 2026-06-17): Distributed relay orchestrator — multi-machine,
  dynamic membership <!-- id:de4e -->` carries a decided/deferred marker but is still an open checkbox, so
  `roadmap-lint.sh` warns every pass (exit 0, non-blocking). The item is a genuine long-horizon deferral,
  not stalled work. **Decision for the human:** either **tick it** with a "DEFERRED — reopen if multi-machine
  ever needed" done-note (closes the box; the deferral rationale stays in the line), OR drop the DEFERRED
  marker and re-lane it as a live `[INPUT — meeting]` candidate. Pre-existing; not a session-batch defect.

- [ ] **Do NOT auto-close the inbox-rehaul umbrella id:9fdb just because its child id:411d shipped (review 2026-07-10 1710).**
  `orphan-scan --shipped` now reports id:9fdb `UMBRELLA-READY (all children [x])` because its only
  typed child edge is `<!-- children:411d -->` and I ticked id:411d this pass. But id:9fdb is a
  `[HARD — meeting]` design decision — its body weighs multiple structural directions ("make manual
  `inbox-done` refuse unless the target twin exists", back the inbox with an existing private git
  repo, non-destructive move-to-archive resolve, a conformance rule) and explicitly says "Directions
  to weigh (decide the ordering)… Evaluate FIRST." id:411d delivered only direction (d), the cheap
  interim anchor guard, which the item itself flagged "do this regardless." The umbrella's real work
  (dissolve-vs-guard, decide the ordering) is undischarged. **Action:** either narrow the
  `children:` edge / re-scope id:9fdb so it no longer reads as ready, or run `/meeting` on it — but
  do NOT tick it on the strength of the interim guard alone.

- [ ] **Installed `~/.claude/skills/relay/scripts/` is stale — re-run `make install-relay` (review 2026-07-08 1625).**
  `relay/scripts/lib-own-repos.sh` was added this cycle and IS listed in the Makefile's
  `relay_FILES` (Makefile:63), so the SOURCE is correct — but the installed tree has no
  symlink for it, so the INSTALLED `relay-doctor.sh` aborts at line 89
  (`source "$SCRIPTS_DIR/lib-own-repos.sh": No such file or directory`, exit 1) — `/relay
  health` is broken for the live install until `make install-relay` re-runs. Running from the
  source/worktree tree works (this review's doctor ran green from there). Not a code defect —
  a reinstall. This resolves inbox dead-letters `routed:ecee` + `routed:9571` (both are
  source-resolved: the lib is shipped and installer-listed). **Action:** run `make
  install-relay` (or `make install`).

- [x] **`roadmap-lint` flags 3 heading-as-item MISSING-id violations on descriptive `## [LANE]` section headers (audit Run 70, 2026-07-06).** — OWNER DECISION: human 2026-07-11 (relay human): DECIDED refine c095 detection — only flag a `## [LANE]` heading when its children are bare status markers (no own tag+id); adding an id would duplicate the child's + break single-id-two-views. Impl filed as ROADMAP id:dfe4 ([ROUTINE] + RED test).
  `roadmap-lint.sh` flags 3 "heading-as-item MISSING its id" violations on the 2026-07-03
  relay-handoff SECTION headers `## [MECHANICAL] lane-anchor hotfix …`, `## [MECHANICAL] recipe
  explicit-success-marker doctrine …`, `## [ROUTINE] case-c bare-only lane count …` (ROADMAP.md
  ~L2861/2883/2911). These are NOT the id:c095 "heading-as-item" shape (a heading owning the
  lane+id whose child `- [ ]` lines are BARE status markers) — each groups a SINGLE already-`[x]`
  child that carries its OWN `[ROUTINE]` tag + `<!-- id:XXXX -->` (0d58/fd37/9078). The detector
  treats ANY `## …[LANE]…` heading as a work-item heading, so a section title that merely contains
  a lane-shaped bracket is demanded to carry an id it should not have (adding one would duplicate
  the child's id, breaking single-id-two-views). **Decision for the human:** (a) refine c095
  detection to only treat a `## [LANE]` heading as a heading-item when its children are BARE status
  markers (no own class tag + id) — the robust fix, has its own test surface; OR (b) drop the
  decorative `[MECHANICAL]`/`[ROUTINE]` bracket from these 3 handoff-section headers (loses the
  at-a-glance lane, zero-risk); OR (c) archive the 3 completed sections. Report-only today
  (relay-doctor/roadmap-lint both exit 0). NOT a session-batch defect — pre-existing c095 tension
  surfaced by the in-window handoff headers.

- [x] **A3 (id:b3d0) mechanical-daemon does NOT host-gate — latent safety gap (wave-2a review 2026-07-02).** — OWNER DECISION: human 2026-07-11 (relay human): DECIDED add the host-gate to mechanical-daemon.sh — skip+defer any recipe whose .host != uname -n (defense-in-depth vs mistaken copy / future shared-transport de31/b444). Impl filed as ROADMAP id:26c2 ([ROUTINE] + RED test).
  The recipe schema's `host` field is documented as "which host the recipe is bound to
  (mirrors the `[host:<name>]` ROADMAP tag)" (recipe-manifest.md:51) and `recipe-validate.sh`
  REQUIRES it non-empty — i.e. every recipe names a target host. But `mechanical-daemon.sh`
  reads `est_wall`/`resource`/`cmd`/`artifact` and **never reads `.host` nor compares it to
  `$(uname -n)`**, so it would auto-EXECUTE a recipe bound to a *different* host. Today the
  drop-dir (`~/.config/relay/recipes/pending/`) is per-host so a mismatched recipe can only
  arrive by mistaken copy or a future shared-transport (de31/b444) — hence not a live bug —
  but the review contract's own §2c host-gate treats a host mismatch as *unrunnable*, and the
  daemon auto-runs shell commands, so this reads as an accidental gap, not a deliberate
  narrowing (no comment says "host is advisory / drop-dir is per-host"). The test never
  exercises it (`write_recipe` always sets `host=$(uname -n)`). **Decision for the human:** add
  a one-line host-gate (skip+defer, or reject, a recipe whose `host` ≠ this host) OR record the
  "per-host drop-dir ⇒ host advisory" rationale in the daemon + recipe-manifest. Filed as a
  follow-on, NOT reopening b3d0 (its tested contract + meeting decision-3 launch-gate all hold).

(All prior boxes — the 8 confirmed 2026-06-12, the 2026-06-21 flaky-test decision,
the two 2026-06-29 inbox dead-letters routed:6976/routed:4097 (ingested →
TODO id:319b / id:8567), and the two 2026-07-01 boxes id:8e3e (zero-commit
checkpoint fix confirmed+implemented) / id:0a3b (relay.toml one-time correction
done; durable fix stays open as ROADMAP id:0a3b) — were resolved and pruned;
latest prune by the 2026-07-02 review.)

- [x] id:d51c — inbox dead-letter (relay-doctor/scan-routed finding, 2026-07-02 review): — OWNER DECISION: unalias cp added to ~/.zshrc (2026-07-02); it-infra twin id:9e82 closed as done (relay human 2026-07-02)
  `~/.claude/todo-inbox.md:8` carries `routed:d51c → [zomni]` ("Remove `cp -i` alias from
  zsh config on zomni (or switch to bash)", from claude-organizer), but "zomni" is a
  MACHINE (this laptop), not a repo on disk — scan-routed can never resolve it (no
  `[repos.zomni]` block, no `# path:` override). Human call: it's a 1-minute shell-config
  edit — do it by hand and `append.sh inbox-done d51c`, or retarget the line to a repo
  that owns machine config.
- [x] id:dff8 — JUDGMENT in the red spec (2026-07-02 handoff): the git-lock-push id:aa93 — confirmed: untracked-only-proceed matches --autostash semantics (untracked never stashed; overwrite aborts loudly); tracked-churn residual stays claude-diary's TODO dff8 option (a) (relay human 2026-07-02)
  dirty-guard fix is specced as "UNTRACKED-only porcelain → proceed; ANY tracked
  modification → keep refusing" (rationale: `--autostash` never stashes untracked paths,
  so they carry no stash-reapply data-loss risk; a rebase that would overwrite one aborts
  loudly on its own). Consequence: `~/.claude`'s TRACKED runtime churn (`.last-cleanup`,
  `history.jsonl`) will STILL refuse — that residual half is claude-diary's gitignore
  decision (TODO dff8 option (a)), deliberately out of scope here. Confirm the split.
- [x] id:482d — JUDGMENT (2026-07-02 handoff): the STOP-sentinel item was downgraded to — confirmed: mechanize-over-observe was right — atomic stop-sentinel.sh dissolves the understood timing-variance class and its timestamped consume log delivers the OBSERVE half (relay human 2026-07-02)
  OBSERVE ("reproduce the timing in a fixture before building anything"), but the spec
  mechanizes instead: prelude step 8's check/countdown/consume becomes ONE atomic
  `stop-sentinel.sh` call + a timestamped consume log. Rationale: the delay class IS the
  LLM performing the `rm` at an uncontrolled point in its turn — one script call
  dissolves the variance structurally (prefer dissolving over observing a hazard we
  already understand), and the consume log still delivers the observe-instrumentation.
  Confirm mechanize-over-observe was the right call.
- [x] id:fb7f — JUDGMENT (2026-07-02 handoff): the `unpromoted-scan primary_lane` fix — confirmed: fixtures pin only unambiguous cases; non-bold/late-tag path stays unpinned (first-tag fallback); residual mislabels degrade to conservative surface (relay human 2026-07-02)
  fixtures require an item with NO genuine lane tag to read `surface` even when BARE
  (un-backtick'd) `[ROUTINE]` appears mid-body (the b8ae case). The suggested mechanism
  ("tag must sit immediately after the bold-title close, first-tag fallback for non-bold
  items") is ONE defensible interpretation — the fixtures are the contract, the mechanism
  is the executor's choice. Sanity-check the fixtures don't over-constrain (e.g. a
  legitimate tag placed after a long un-bolded title).
- [x] handoff 2026-07-02 lane-triage + one evidence-based close — confirm: (a) scan-mislabeled — confirmed: all 5 lane tags verified consistent with item bodies; 22ef close re-verified (shard deleted by a0b6; relay-loop.js:733/849 pinned haiku) (relay human 2026-07-02)
  untagged items lane-tagged in TODO.md: 33c2 (owner-ratification contract change), a505
  (auth-queue design qs), 7b23 (gated /batch audit), d0da (tag-taxonomy, sequenced after
  72cc/962a) → `[HARD — meeting]`; b8ae (verify review→execute chaining = observe the next
  qualifying pool run) → `[HARD — hands]`. (b) id:22ef closed as overtaken-by-events with
  evidence (LLM discovery shard deleted by a0b6; residual discovery agents pinned haiku at
  relay-loop.js:733/849) — reopen if you think a residual "pin it cheap" half survives.
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
- [x] relay-doctor finding (2026-07-02 Fable recheck review): inbox dead-letter — OWNER DECISION: same as REVIEW_ME:13 — unalias done, it-infra 9e82 closed; duplicate collapses at next reviewer prune (relay human 2026-07-02)
  `routed:d51c → [zomni]` — the target names the MACHINE zomni, not a repo, so
  `scan-routed.sh` can never resolve it ("no repo named 'zomni' found on disk").
  The item ("remove `cp -i` alias from zsh config on zomni") is machine-config /
  human-action work: either re-target it to the repo that owns zomni shell config
  (it-infra?) or resolve it by hand and `append.sh inbox-done d51c`. Human's call —
  report-only here. (Also: 3 twinned-resolvable inbox items are drainable via
  `scan-routed.sh --apply`, id:678e.)
- [ ] Human-sprint 80/20 checklist (2026-07-02 Fable consulting session): pre-triaged
  tier-1 (minutes-each) + tier-2 (session-each) [HARD — hands] tasks across the fleet,
  ranked by unlock-per-minute — lanes already decided, context linked per item. Lives in
  the PRIVATE diary repo (fleet enumeration must not land in this public file):
  `~/src/claude-diary/docs/2026-07-02-human-sprint-8020.md`. Next `/relay human` should
  present it as the "you run these" checklist and tick items THERE; close this box when
  that doc is fully worked or superseded.
- [x] Capability-taxonomy slice-A handoff (2026-07-02, meeting 2026-07-02-1924) — three
  executor judgment calls RESOLVED at the 2026-07-02 review (all three confirmed sane;
  the four slice-A implementations verified GENUINE, not gamed — tests byte-identical to
  their ced7343 RED versions, impl scripts all absent at RED):
  (1) **A4 (id:e407) resource→tier mapping** — CONFIRMED. `HEAVY_RESOURCES=(gpu local-llm
  local-model llama)`, everything else (cpu/ram/net/disk) light. The heavy set is exactly the
  OOM-risky GPU/local-model class the meeting cited (the workloads that killed six sessions);
  ram sits "light" in the *permit-window* tier while still hardware-gated live by
  `resource-probe.sh` (`RESOURCE_PROBE_RAM_MIN_MB`) — the two gates are orthogonal, so a big
  RAM job is not under-guarded. Mapping is sane.
  (2) **A1 (id:7616) `mechanical` verdict priority rank** — CONFIRMED rank 6 (just above idle
  7, below human 5). Correct: mechanical is pool-inert (non-dispatchable, like human/idle), so
  a surface-only backlog (human, rank 5) rightly out-prioritizes "noting daemon work exists".
  `intensive` stays `""` on it (id:5ac6 invariant `intensive!="" => verdict in {execute,hard}`
  intact). Matches "pool-inert, daemon consumes". No external consumer pins numeric rank 6/7.
  (3) **A5 (id:68dc) default thresholds** — CONFIRMED on the real zomni host (this review ran
  there): `nvidia-smi` is ABSENT → `resource-probe.sh gpu` degrades gracefully to
  `available:false` + a stated reason, exit 1, NO crash (not just the env-stubbed test path).
  `ram` default 2048MB → available (10163MB free); `LOAD_MAX` default = nproc = 8 is sane for
  the 8-core host. All host-tuning defaults are conservative and env-overridable.
- [x] **id:758e purity-helper handoff (2026-07-07): NO contract-version bump for the new convention note.** — REVIEWER VERDICT (2026-07-08 review, id:758e closed): UPHOLD no-bump. The `### Purity-test-as-contract` note changes no artifact format an in-flight executor writes (ROADMAP/RELAY_LOG) nor any of the 5 core rules; it is a test-authoring convention triggered only when authoring a read-only component, and executors load `/relay executor` fresh each turn so they see it without a version signal. A v6→v7 bump would churn every managed repo's CLAUDE.md pointer for zero in-flight-behaviour delta. Contract stays v6; pointer unchanged.
  The RED spec (`tests/test_purity_helper.sh`) requires a `### Purity-test-as-contract`
  note in `relay/references/executor-contract.md` but instructs the executor NOT to bump
  the `v6` version marker — judgment: an additive test-authoring convention is a
  "clarification that doesn't change behaviour" per §Maintenance (no in-flight executor
  behaves differently mid-item), and a bump would churn every managed repo's CLAUDE.md
  pointer. If you read the convention as a genuine new RULE (executors must now ship
  purity tests with read-only components), overrule: bump v6→v7 + refresh the pointer.
