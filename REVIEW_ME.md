# Human review queue <!-- budget: 15 min -->

Judgment calls encoded in red tests — confirm or correct the interpretation.
Max ~10 open boxes; the reviewer prunes resolved ones each review turn.

(All prior boxes — the 8 confirmed 2026-06-12, the 2026-06-21 flaky-test decision,
the two 2026-06-29 inbox dead-letters routed:6976/routed:4097 (ingested →
TODO id:319b / id:8567), and the two 2026-07-01 boxes id:8e3e (zero-commit
checkpoint fix confirmed+implemented) / id:0a3b (relay.toml one-time correction
done; durable fix stays open as ROADMAP id:0a3b) — were resolved and pruned;
latest prune by the 2026-07-02 review.)

- [ ] id:d51c — inbox dead-letter (relay-doctor/scan-routed finding, 2026-07-02 review):
  `~/.claude/todo-inbox.md:8` carries `routed:d51c → [zomni]` ("Remove `cp -i` alias from
  zsh config on zomni (or switch to bash)", from claude-organizer), but "zomni" is a
  MACHINE (this laptop), not a repo on disk — scan-routed can never resolve it (no
  `[repos.zomni]` block, no `# path:` override). Human call: it's a 1-minute shell-config
  edit — do it by hand and `append.sh inbox-done d51c`, or retarget the line to a repo
  that owns machine config.
- [ ] id:dff8 — JUDGMENT in the red spec (2026-07-02 handoff): the git-lock-push id:aa93
  dirty-guard fix is specced as "UNTRACKED-only porcelain → proceed; ANY tracked
  modification → keep refusing" (rationale: `--autostash` never stashes untracked paths,
  so they carry no stash-reapply data-loss risk; a rebase that would overwrite one aborts
  loudly on its own). Consequence: `~/.claude`'s TRACKED runtime churn (`.last-cleanup`,
  `history.jsonl`) will STILL refuse — that residual half is claude-diary's gitignore
  decision (TODO dff8 option (a)), deliberately out of scope here. Confirm the split.
- [ ] id:482d — JUDGMENT (2026-07-02 handoff): the STOP-sentinel item was downgraded to
  OBSERVE ("reproduce the timing in a fixture before building anything"), but the spec
  mechanizes instead: prelude step 8's check/countdown/consume becomes ONE atomic
  `stop-sentinel.sh` call + a timestamped consume log. Rationale: the delay class IS the
  LLM performing the `rm` at an uncontrolled point in its turn — one script call
  dissolves the variance structurally (prefer dissolving over observing a hazard we
  already understand), and the consume log still delivers the observe-instrumentation.
  Confirm mechanize-over-observe was the right call.
- [ ] id:fb7f — JUDGMENT (2026-07-02 handoff): the `unpromoted-scan primary_lane` fix
  fixtures require an item with NO genuine lane tag to read `surface` even when BARE
  (un-backtick'd) `[ROUTINE]` appears mid-body (the b8ae case). The suggested mechanism
  ("tag must sit immediately after the bold-title close, first-tag fallback for non-bold
  items") is ONE defensible interpretation — the fixtures are the contract, the mechanism
  is the executor's choice. Sanity-check the fixtures don't over-constrain (e.g. a
  legitimate tag placed after a long un-bolded title).
- [ ] handoff 2026-07-02 lane-triage + one evidence-based close — confirm: (a) scan-mislabeled
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
- [ ] relay-doctor finding (2026-07-02 Fable recheck review): inbox dead-letter
  `routed:d51c → [zomni]` — the target names the MACHINE zomni, not a repo, so
  `scan-routed.sh` can never resolve it ("no repo named 'zomni' found on disk").
  The item ("remove `cp -i` alias from zsh config on zomni") is machine-config /
  human-action work: either re-target it to the repo that owns zomni shell config
  (it-infra?) or resolve it by hand and `append.sh inbox-done d51c`. Human's call —
  report-only here. (Also: 3 twinned-resolvable inbox items are drainable via
  `scan-routed.sh --apply`, id:678e.)
