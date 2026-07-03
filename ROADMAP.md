# Roadmap <!-- fables-turn roadmap v1 -->

Executor-facing task spec. Each item is sized for ONE Sonnet session. Items are
the single source of truth — TODO.md carries only a summary line. Executors tick
checkboxes; only the reviewer adds, removes, or re-scopes items.

Read `CLAUDE.md` (§Testing, §Gotchas, §Relay contract) before starting any item.
Done-check for every item: tick the item's checkbox below, then `make test` must
be fully green (see CLAUDE.md §Testing for the expected-red semantics).

## Items

<!-- 2026-07-02 handoff C2 (run relay-20260701-234115-26818): promoted from the open TODO backlog.
     unpromoted-scan reported 9 promote / 71 surface; 4 of the 9 (33c2/a505/7b23/b8ae) were
     prose-substring MISLABELS of untagged items (the id:fb7f bug class, live evidence recorded
     in that item) — they were lane-tagged in TODO.md instead (33c2/a505/7b23 → [HARD — meeting],
     b8ae → [HARD — hands]) so they become honest `surface` items for the mechanical filer.
     Single-id-two-views (D2): every id below reuses its open TODO.md twin. -->

<!-- 2026-07-03 handoff (relay): RED spec for shadow-log RED-row persistence + sig-fidelity fix (id:e833),
     the harden-forward that closes id:3134's instrument gap (3 disputed RED cases were un-adjudicable). -->

- [ ] [ROUTINE] `shadow-log.jsonl` per-repo RED-row persistence + close the sig-fidelity gap that manufactures FALSE RED (id:e833) <!-- id:e833 -->
  - **Why** (TODO id:e833, resolving id:3134 2026-07-03): the a0b6 classifier-flip tripwire (`backtest-verdict.py` → `~/.config/relay/shadow-log.jsonl`) showed `red>0` in several snapshots, but the entries store only the AGGREGATE count (`{"red":3,...}`) — so the 3 disputed RED cases (leAIrn2learn/yinyang-puzzle/zkm-threema) were **un-adjudicable post-hoc** and had to be hand-reconstructed from `relay-events.jsonl`. Root cause of those false REDs = a **sig-fidelity gap**: `discover-sig.sh` hashes HEAD/ckpt-tags/porcelain/upstream/worktrees/orphans/roadmap/dq but NOT the post-execute unaudited-commit flip (the `substantive_unaudited` axis / the audit-ckpt-tag's TARGET commit). So a legitimate `execute→review` advance leaves the discover-sig UNCHANGED, and the RED bucketer (fires when `dispatch_sig == cur_sig` but verdicts differ) mislabels that documented `substantive_unaudited→review` policy-delta as RED. Both halves make `red>0` finally mean "a real classifier defect", not noise.
  - **How / Design** (two parts, one item):
    1. **Persist per-repo RED rows.** `backtest-verdict.py` already computes per-repo `rows` (repo, live `verdict`, `last_mode`, `note`) and threads each RED's `dispatch_sig`/`cur_sig` through the e8ea bucketer. Add each RED row to the `--append-log` shadow-log entry as `red_rows`: a list of `{"repo","dispatch_verdict","classifier_verdict","sig"}` (dispatch_verdict = the last-dispatch mode; classifier_verdict = the live classify verdict; sig = the shared dispatch/current sig), with `len(red_rows) == entry["red"]`. Do NOT drop the aggregate `red` count — this is additive. (Rows for non-RED buckets are out of scope; keep the entry lean.)
    2. **Close the sig-fidelity gap — executor's choice, note which:** EITHER (2a) add the `substantive_unaudited` / unaudited-commit signal (equivalently the audit-checkpoint anchor's target) to `discover-sig.sh`'s hashed blob — over-invalidation is SAFE per the CLAUDE.md sig-cache note (under-invalidation is the only hazard), so err toward changing the sig; OR (2b) teach `backtest-verdict.py`'s RED bucketer to reclassify a same-sig `execute→review` advance as EXPECTED (mirroring `backtest-historical.py`'s `match_policy_delta` `substantive→review` rule). Prefer 2a: it fixes the fidelity at the SOURCE so every sig consumer benefits and no second policy-list has to be maintained; 2b only patches the one report. If 2a, add the new signal to `discover-sig.sh`'s blob ONLY (do not touch its fail-open contract), and remember the sig-cache superset rule.
  - **Acceptance**: `tests/test_backtest_red_row_persist.sh` (`# roadmap:e833`) green — one `backtest-verdict.py --json --append-log` run over two fixture repos asserts BOTH: (1) the shadow-log entry carries `red_rows` (a list of `{repo,dispatch_verdict,classifier_verdict,sig}`, `len==red`) with the genuine RED repo attributable (dispatch review / classifier execute / its sig), and the execute→review repo ABSENT from `red_rows`; (2) the `execute→review`-at-same-sig repo buckets EXPECTED, not RED (assertion is on the OUTCOME "not counted RED", satisfiable via EITHER 2a or 2b). Full `make test` green after ticking this item's checkbox (RED until then).

<!-- 2026-07-03 handoff (relay): RED spec for the tag-first-among-trailing-tags lint (id:ad8a). -->

- [x] [ROUTINE] `roadmap-lint.sh` tag-first rule — flag an open item whose genuine lane tag is NOT the first recognized lane-tag (a prose/backtick'd lane bracket precedes it) (id:ad8a) <!-- id:ad8a -->
  - **Why** (TODO id:ad8a, the "A" floor of the d259 A→C decision): the id:4da4/id:0d58 PRIMARY-LANE anchoring both `classify-repo.sh` and `gather-repo-state.sh` rely on assumes the genuine capability lane is the FIRST recognized lane-tag on the line — but `classify-repo.sh` anchors on the RAW first-position tag (`min()` over `LANE_TAGS`, NO backtick strip) while `gather-repo-state.sh::roadmap_primary_lane` anchors on the first tag AFTER stripping backtick-quoted spans (id:1bbd). When a prose/history lane bracket (typically a backtick'd mention) sits BEFORE the item's own bare tag, the two readers split-brain — `classify-repo` mis-anchors on the prose one. This is the c3f5/leAIrn2learn hazard the anchoring was built to survive; `roadmap-lint.sh` has no rule enforcing the invariant, so a violating line slips past the grammar (the sibling parser fix landed as id:fb7f; this is the lint counterpart).
  - **How / Design**: add a check to `roadmap-lint.sh` reusing the case-c (id:09a3) detection idiom + severity convention. For each open `- [ ]` item compute `raw_first` = first recognized lane-tag WITHOUT stripping backticks (classify-repo's `min()` view) and `genuine_first` = first recognized lane-tag AFTER stripping backtick spans (gather's `roadmap_primary_lane`, id:1bbd); FLAG when `genuine_first` exists but `raw_first != genuine_first`. Match the lane-tag SET exactly to `LANE_TAGS`/`roadmap_primary_lane` so the lint agrees with the classifier. A legitimately-first lane with a LATER prose bracket is compliant (`raw_first == genuine_first`) — do NOT over-flag. The diagnostic must name the ORDERING/anchoring (first/precede/anchor), distinct from case-c's "conflict/multiple lane brackets" wording, so the two rules are separable. To keep the c3f5 compliant shape fully clean, prefer also making case-c's lane-count backtick-aware (strip backtick spans before counting, mirroring id:1bbd) — otherwise it still false-positives that shape as a two-lane conflict.
  - **Severity**: default to a report-only **WARN** per "observe before preventing" (the dual-vocab migration window churns lane tags); the current ROADMAP.md/TODO.md are clean of THIS violation, so a hard ERROR (nonzero exit) is also safe if preferred. Wire whichever; the RED test is severity-agnostic (asserts the diagnostic is/ isn't SURFACED, not an exit code). Do NOT edit `roadmap-lint.sh`'s existing case-c severity contract beyond the backtick-awareness note above.
  - **Acceptance**: `tests/test_roadmap_lint_tag_first.sh` (`# roadmap:ad8a`) green — (a) an open item with a backtick'd/prose lane bracket BEFORE its genuine lane tag is flagged with a tag-first/ordering diagnostic; (b) a plain tag-first item is NOT flagged; (c) the id:0d58/fb7f/c3f5 shape (`[HARD — pool]` genuine-first, a backtick'd `[ROUTINE]` quoted LATER) is NOT flagged by the tag-first rule. Full suite green after ticking (RED until then).
  - **DONE 2026-07-03 (executor)**: tag-first WARN rule shipped (report-only, exit 0) — `first_lane_tag()` mirrors `roadmap_primary_lane`'s backtick-strip (strip=1) alongside a raw no-strip scan (strip=0, mirrors `classify-repo.sh`'s `min()`); flags when they diverge. **Case-c backtick-awareness NOT applied** — verified regression: stripping backticks before counting collapses `test_roadmap_lint_tagprose.sh`'s own case-c fixture (`[HARD — decision gate] … actually re-laned to `[HARD — pool]`…`) to a single bracket, silencing the genuine tag/prose ERROR that test requires. Both that fixture and the c3f5-compliant shape are structurally identical (genuine tag first, a different tag later in backticks) — only their PROSE semantics differ ("actually re-laned to" vs "quotes … as the rejected verdict"), which a bracket-counting grammar can't distinguish. Per the reviewer's explicit escape hatch, left case-c's existing (non-backtick-aware) counting untouched rather than weaken/break the tagprose test; the c3f5 shape still trips case-c's OLD "conflict" message as a known, pre-existing false-positive (harmless — a different message string, doesn't collide with the new tag-first diagnostic, and outside this test's assertions). Flagging for a follow-up id if the false-positive itself needs resolving later (likely needs a semantic cue beyond bracket-counting, or folds into the id:7df1/d259-C structural-reorder migration that deletes this anchoring reimplementation entirely).

- [x] [ROUTINE] `git-lock-push.sh` — id:aa93 dirty-guard: tolerate untracked-only churn + drop the "concurrent edit" causal guess <!-- id:dff8 --> done 2026-07-02 (executor): legacy/manifest pull-path refusal now classifies porcelain — untracked-only (`?? ` only) proceeds with the autostash-rebase, any tracked entry still refuses; refusal message states facts ("uncommitted tracked changes"), no more "(a concurrent edit?)" guess; `tests/test_git_lock_push_dirty_guard.sh` 1/1 green
  - **Why** (TODO id:dff8, recurring on `~/.claude`, user-confirmed 2026-06-30): the guard (`git-diary-workflow/git-lock-push.sh:128`) refuses the `pull --rebase --autostash` path on ANY `git status --porcelain` output. `~/.claude` is perpetually dirty with harness runtime churn — untracked `plans/`, `session-env/`, `sessions/`, `tasks/` — so every push needs the manual fallback, and the warning asserts an unverified cause ("a concurrent edit?"), actively misleading the operator. `--autostash` only stashes TRACKED changes; untracked paths carry no stash-reapply data-loss risk (a rebase that would overwrite an untracked file aborts loudly on its own, which is safe-and-loud).
  - **Acceptance**:
    1. Before refusing, classify the porcelain: **untracked-only** (every line `?? `) → PROCEED with the autostash-rebase (both legacy and manifest mode); ANY tracked modification/staged/renamed entry → keep refusing (the id:aa93 data-loss guard is untouched for tracked dirt).
    2. Reword the refusal per TODO option (c): state facts only — e.g. "working tree has uncommitted tracked changes; not autostash-rebasing (id:aa93)" — no "(a concurrent edit?)" causal guess.
    3. Out of scope: the TRACKED runtime churn half (`.last-cleanup`, `history.jsonl` are tracked in the `~/.claude` worktree and will still refuse) — that is claude-diary's gitignore decision (TODO id:dff8 option (a)). REVIEW_ME box records this judgment split.
  - **Tests**: `tests/test_git_lock_push_dirty_guard.sh` (`# roadmap:dff8`) — hermetic bare-remote + clone fixtures (idiom: `test_git_lock_push_ff_only.sh`): (a) legacy-mode push with residual untracked-only churn proceeds (new commit reaches the remote); (b) tracked modified file still refuses (exit 0, commit stays local-only, remote unchanged); (c) the refusal warning no longer contains "concurrent edit". RED until the fix lands.

- [x] [ROUTINE] STOP-sentinel check/countdown/consume → one deterministic script call + timestamped consume log (id:482d) <!-- id:482d --> done 2026-07-02 (executor): `relay/scripts/stop-sentinel.sh check --path <file>` implements the check/countdown/consume semantics atomically (absent→false; positive-int countdown→decrement; else→consume+timestamped log line); prelude step 8 delegates to it verbatim; registered in Makefile relay_FILES/EXEC/ALLOW; `tests/test_stop_sentinel_consume.sh` 8/8 green
  - **Why** (TODO id:482d, observed 2026-07-01 ~23:27): a fired user-stop left `~/.config/relay/STOP` present minutes AFTER the workflow returned (gone unaided by 23:41) — consumption happened but DELAYED. The check/countdown/consume logic lives as prose instruction 8 of the discover-prelude prompt (`relay-loop.js:732`), so the `rm` lands at whatever point the agent reaches it; the hazard window is a next pool launched during the lag being false-stopped. Mechanize-first: collapsing the whole step into ONE atomic script call structurally dissolves the timing-variance class, and the timestamped consume log is the observe-instrumentation the item's OBSERVE downgrade asked for (both halves in one bounded change).
  - **Acceptance**:
    1. New `relay/scripts/stop-sentinel.sh check [--path <file>]` implementing prelude step 8 semantics VERBATIM: file absent → `{"stopRequested":false}`; trimmed content a positive integer N≥1 → write N-1 back, `{"stopRequested":false}`; anything else (empty / non-numeric / "0" / negative) → `rm -f` the file and `{"stopRequested":true}`. On consume, append ONE ISO-timestamped line to a log (env-overridable path, default `~/.claude/logs/relay-stop-sentinel.log`) so any future delayed-consumption report has a real timeline. Registered in Makefile relay_FILES/EXEC/ALLOW.
    2. `relay-loop.js` prelude step 8 rewritten to run the script and return its JSON verbatim (still the only actor, once per round; countdown write-back semantics unchanged). ENGINE-EDIT CAUTION: prompt-string change only — `node --check` + `lint-workflow-templates.mjs` + the existing structure tests must pass (the a0b6 template-literal-lint hazard class); do this edit early-session, not tail-of-session.
  - **Tests**: `tests/test_stop_sentinel_consume.sh` (`# roadmap:482d`) — hermetic tmpdir: absent / countdown-decrement (3→2, file kept) / plain-stop consume (file GONE + log line ISO-timestamped) / stale-"0" consume; plus a structure assertion that the prelude step 8 text references `stop-sentinel.sh` (sibling of `test_relay_loop_structure.sh`). RED until landed.

- [x] [ROUTINE] lane-anchor the remaining two parsers: `gather-repo-state.sh` `open_hard_pool` + `unpromoted-scan.sh` `primary_lane` (id:fb7f) <!-- id:fb7f --> done 2026-07-02 (executor): `gather-repo-state.sh`'s `open_hard_pool` now anchors on `roadmap_primary_lane` (leftmost-tag-after-backtick-strip, mirroring classify-repo.sh:85 + gather-human-backlog.sh's id:1bbd backtick-strip) and excludes 🚧/BLOCKED-on pool items (mirrors classify-repo.sh:98); `unpromoted-scan.sh`'s `primary_lane` now requires a bold-titled TODO item's tag to sit immediately after the title's closing `**` — a bold item with no title-adjacent tag returns no lane (surface) even if its prose bare/backtick-quotes a lane tag elsewhere. `tests/test_gather_pool_count_anchor.sh` 6/6 green; full suite 163/163 green.
  - **Why** (TODO id:fb7f; it-infra phantom `hard` 2026-06-30): `gather-repo-state.sh:341-355` counts `open_hard_pool` by whole-line substring — an open item whose PROSE quotes `[HARD — pool]` (re-lane criteria) counts as pool work → phantom `hard` verdict → doomed Opus dispatch each intensive/opus round. Sibling fixes already shipped for `gather-human-backlog.sh` (id:1bbd, backtick-strip) and `classify-repo.sh` (id:4da4, first-tag position); this closes the remaining two spots. **LIVE EVIDENCE from THIS handoff (2026-07-02)**: `unpromoted-scan.sh::primary_lane` (leftmost recognized tag, no position bound) mislabeled 4 of 9 `promote` items — 33c2/a505/7b23/b8ae carry NO genuine lane tag, so a prose `[ROUTINE]` became leftmost and set disposition=promote (backtick'd in three of them; BARE in b8ae's "open [ROUTINE] count" — so backtick-strip ALONE is insufficient here).
  - **Acceptance**:
    1. `open_hard_pool` counts an open `- [ ]` item ONLY when its PRIMARY lane (id:4da4 first-tag parse, mirroring `classify-repo.sh:85`) is `[HARD — pool]`; keep the recurring-audit exemption unchanged. Also mirror the conservative gate exclusion (`classify-repo.sh:98`): an open pool item carrying `🚧` or `BLOCKED on` does not count (under-dispatch-safe; unblocks promoting dep-gated pool items without doomed dispatches).
    2. `unpromoted-scan.sh::primary_lane` must yield NO lane (→ disposition `surface`) for an item whose only lane-tag occurrences are prose — including a BARE un-backtick'd mention deep in the body. Candidate mechanism: the tag must sit immediately after the item's bold-title close (`**` + optional whitespace), with first-tag as the fallback for non-bold items — but the FIXTURES below are the contract; the mechanism is the executor's choice (REVIEW_ME box records the judgment).
    3. `classify-repo.sh` consumes the scan TSV downstream — verify `unpromoted.promote/surface` counts shift accordingly (no code change expected there). Cross-ref id:cb9b (label-SEMANTICS contract): this item fixes lane PARSE; cb9b pins label MEANING.
  - **Tests**: `tests/test_gather_pool_count_anchor.sh` (`# roadmap:fb7f`) — hermetic fixtures: (a) ROADMAP whose only `[HARD — pool]` occurrences are inside a hands/meeting item's prose → `open_hard_pool==0`; (b) genuine pool item → 1; (c) `🚧 GATED` pool item → 0; (d) TODO item with backtick'd prose `[ROUTINE]` and no genuine tag → `surface`; (e) TODO item with a BARE prose `[ROUTINE]` mid-body and no genuine tag → `surface`; (f) genuinely tagged `- [ ] **title** [ROUTINE] …` → `promote`. RED until landed.

- [x] [HARD — pool] `/relay next` routes 1/2a — "effectively-drained" predicate aligned with the shipped classifier semantics (id:9014) <!-- id:9014 --> done 2026-07-02 (handoff C5): SKILL.md route 1 now keys on executor-ACTIONABLE `[ROUTINE]` (the `actionable_routine_open` predicate, classify-repo.sh cited as the single source); route 2a fires on "no executor-actionable open item" incl. the @manual/human-lane-only effectively-drained case; anti-guess wording retained; drift-guard tests/test_next_actionable_predicate.sh 4/4 green (behavior itself already locked by test_classify_verdict_humanlane.sh — loop half had shipped via id:4da4/5eb3, verified in-source this handoff)
  - **Why** (TODO id:9014, user 2026-06-30 "something's fishy… was there no work left in truncocraft?"): a ROADMAP whose only open items are `@manual`/human-lane is not ZERO-open, so `/relay next` route 2a never fires the unpromoted-scan/handoff path — truncocraft's 35-item TODO backlog read as "needs human / idle". The LOOP half is ALREADY SHIPPED + test-locked (verified this handoff 2026-07-02): `classify-repo.sh:89-105` derives `actionable_routine_open`/`roadmap_actionable_open` with `@manual`/human-lane/blocked exclusions, and `classify-verdict.sh:91,112-123` gates execute on the actionable count and fires `handoff` on promote>0 regardless of open human-lane boxes (`tests/test_classify_verdict_humanlane.sh` green). Remaining: the `/relay next` doc predicate (`relay/SKILL.md:378-395`) still keys route 1 on bare "Open `[ROUTINE]` items" and route 2a on "no open `- [ ]` items".
  - **Acceptance**:
    1. SKILL.md route 1 keys on executor-ACTIONABLE open `[ROUTINE]` items (primary-lane, not `@manual`/human-gated, not `🚧`/`BLOCKED on`) — the `actionable_routine_open` semantics.
    2. Route 2a's trigger becomes "no executor-actionable open item" (zero open boxes OR only `@manual`/human-lane/blocked boxes remain = effectively drained) → run unpromoted-scan and route per its findings; keep the anti-guess wording (never auto-promote an untagged item with a guessed lane).
    3. Align-by-reference: NAME `classify-repo.sh` / `actionable_routine_open` as the predicate authority instead of re-defining it in prose (single-source, cf. id:415b).
    4. Drift-guard test asserting the route-1/2a text carries the actionable-predicate markers (weak wording test — acceptable as a drift guard; the behavior itself is locked by `test_classify_verdict_humanlane.sh`).
  - **Tests**: `tests/test_next_actionable_predicate.sh` (`# roadmap:9014`).

- [ ] [HARD — pool] Front-door first-class single-repo scope — `/relay <repo|.>` short-circuits discovery (routed:bc24) <!-- id:7633 -->
  - **Why** (TODO id:7633, inbound from truncocraft/loderite, observed 2026-06-29): a single-repo invocation (`/relay --afk . --quota-7d 90`) still enumerates + fully classifies the entire own-repo universe (40+ repos incl. `# path:` plugins), computing gating reasons that are all discarded to dispatch ONE repo; the workaround (hand-built 24-name `excludeRepos`) was incomplete because it missed `# path:`-relocated repos. Slow, overkill, and error-prone scoping.
  - **Acceptance**:
    1. A first-class single-repo scope (bare repo positional / `.` for cwd / `--only <repo>`): discovery classifies ONLY that repo — skip the own-repo enumeration + discover fan-out, but still run the SAME per-repo path (`discover-repo.sh` reconcile→classify→route; reuse, never fork the logic).
    2. The repo resolves against `relay.toml` (THE canonical own-repo set, honoring `# path:` — never a `~/src` glob); a repo not confirmed there is a LOUD reject, not a guess ([[feedback-use-existing-tools-not-improvise]]).
    3. `--exclude` filters the SAME canonical list BEFORE any classification work (verify, add a check if absent).
    4. `relay/SKILL.md` front-door documents the scope arg; decide in-item whether a bare `.` with open actionable `[ROUTINE]` work should route to `/relay next` semantics — record the decision in the done note.
    5. ENGINE-EDIT CAUTION: `pool-args.mjs` + `relay-loop.js` — `node --check` + `lint-workflow-templates.mjs` + structure tests green.
  - **Tests**: args-parse cases in the `pool-args.mjs` test surface + a structure test that the single-repo path bypasses the universe enumeration (same idiom as `test_relay_loop_structure.sh`). RED or structure-asserted per feasibility.

- [x] [ROUTINE] `classify-repo.sh` — gate the `standin` flag on `fable_rechecked` (perpetual Fable-recheck re-dispatch) (routed:f3d0) <!-- id:a42e --> done 2026-07-02 (executor): `standin` now requires `not fable_rechecked` — a checkpoint annotation that merely mentions "fable-standin" no longer re-elevates once the id:e030 watermark shows the recheck was already consumed; `tests/test_classify_repo_standin_gate.sh` 2/2 green
  - **Why** (inbound from the zkm relay review 2026-07-02; verified in-source this handoff): `classify-repo.sh` derives `standin = "fable-standin" in ckpt_msg` — a naive substring — so a GENUINE Fable recheck tag whose annotation merely MENTIONS the standin review it audited (zkm `relay-ckpt-20260701-2315`) re-triggers `standin`; `relay-loop.js` then ORs `u.standin || u.strongRecheckPending`, so an already-rechecked repo (`fable_rechecked` set ⇒ `strongRecheckPending=false`) re-elevates idle→review on EVERY Fable pool round. Observed: redundant zkm dispatch in run relay-20260701-234115 (empty window; the recheck was already consumed 2026-07-01).
  - **Acceptance**:
    1. The `standin` derivation becomes `("fable-standin" in ckpt_msg) and not fable_rechecked` — the durable id:e030 watermark is the gate. A genuinely NEW standin checkpoint still elevates, because writing `last_strong_ckpt` resets `fable_rechecked = false` (id:e030 shape); an already-consumed recheck never re-fires.
    2. No change to `strongRecheckPending` (already watermark-gated) or to the elevation OR itself.
  - **Tests**: `tests/test_classify_repo_standin_gate.sh` (`# roadmap:a42e`) — hermetic: (i) latest relay-ckpt annotation mentions `fable-standin` ∧ toml block has `fable_rechecked` set → `--emit unit` `standin==false`; (ii) same tag, `fable_rechecked` absent → `standin==true` (regression guard). RED until landed.

- [x] [ROUTINE] `relay-loop.js` — Fable-produced strong HANDOFF must not queue a bogus self-recheck; recheck reason must not hardcode "Opus stood in" (id:6856) <!-- id:6856 --> done 2026-07-02 (executor): `isFableRecheck` now drops the `verdict === 'review'` conjunct (any strong unit produced on a real-Fable session marks `fable_rechecked` with a dated watermark instead of `false`); elevation reason no longer hardcodes "Opus stood in for Fable" (neutral "strong checkpoint pending independent Fable audit" wording); `tests/test_fable_recheck_write_side.sh` 4/4 green, `node --check` + `lint-workflow-templates.mjs` + `test_fable_standin_marker.sh`/`test_relay_loop_structure.sh` all green
  - **Why** (found by the 2026-07-02 Fable recheck of relay-ckpt-20260702-0119 — which was itself the bogus dispatch): the integrator prompt gates the id:e030 consume side on `isFableRecheck = SESSION_IS_FABLE && unit.verdict === 'review'` (`relay-loop.js:1393`), so a strong checkpoint produced by REAL Fable via a **handoff** (or hard) unit falls to the else branch and records `fable_rechecked = false` — queuing a Fable-rechecks-Fable review the next pool round (this run: empty diff window, `strong_model = "claude-fable-5"`). The elevation reason (`relay-loop.js:~1046`) also hardcodes "Opus stood in for Fable" regardless of the recorded `strong_model`, so the dispatch reason was factually wrong (the [[feedback-ping-threshold-anomalies]] misconfiguration-smell class). Write-side sibling of id:a42e (read-side standin gate) — same perpetual/wasted-re-dispatch family, third mechanism (a42e substring, 25aa tag anchor, 6856 verdict conjunct).
  - **Acceptance**:
    1. `isFableRecheck` is true for ANY strong unit when the session's strong tier is real Fable (drop the `verdict === 'review'` conjunct) — a self-produced strong checkpoint has nothing pending, so it records a dated `fable_rechecked`, never `false`. The non-Fable (Opus-standin) branch keeps recording `false` (queue side unchanged).
    2. The strongRecheckPending elevation reason stops hardcoding "Opus stood in for Fable" — derive the wording from the recorded `strong_model` (or neutral "strong checkpoint pending independent Fable audit" phrasing). No behavior change to the elevation predicate itself (that is a42e/read-side territory).
    3. ENGINE-EDIT CAUTION: prompt-string edits — `node --check` + `lint-workflow-templates.mjs` + existing structure tests (`test_fable_standin_marker.sh`, `test_relay_loop_structure.sh`) stay green.
  - **Tests**: `tests/test_fable_recheck_write_side.sh` (`# roadmap:6856`) — static-grep structure spec (house idiom): (1) no `verdict === 'review'` conjunct on `isFableRecheck`; (2) no hardcoded "Opus stood in for Fable" literal; (3)+(4) regression guards: dated-watermark consume instruction + `fable_rechecked = false` queue instruction both survive. RED until landed (2 red / 2 green at promotion).

- [ ] [ROUTINE] `classify-repo.sh` — `strongRecheckPending` must be model-aware: a Fable-produced strong checkpoint never queues a Fable-rechecks-Fable review (routed:1c2b) <!-- id:5884 -->
  - **Why** (inbound from the chidiai relay review 2026-07-02, promoted by the 2026-07-02 review): `strong_recheck_pending = last_strong_ckpt set ∧ ¬fable_rechecked` (`classify-repo.sh:160`) is model-BLIND — a relay.toml entry whose `strong_model` is ALREADY a Fable model (e.g. chidiai `relay-ckpt-20260702-0048`, `strong_model = "claude-fable-5"`, `fable_rechecked = false`) elevates a same-tier second-opinion recheck (low value, wasted strong dispatch). The write-side fix (id:6856, shipped 2026-07-02) stops NEW Fable strong checkpoints from recording `false`, but pre-existing entries (and any written by non-pool paths, cf. id:0a3b) still carry the bogus-pending shape — the read side needs its own gate. Fourth mechanism in the perpetual/wasted-re-dispatch family (a42e substring, 25aa tag anchor, 6856 verdict conjunct, 5884 model-blind read).
  - **Acceptance**:
    1. `strong_recheck_pending` additionally requires the recorded `strong_model` NOT be a Fable model (case-insensitive `fable` substring on the parsed `strong_model` value): `last_strong_ckpt` set ∧ ¬`fable_rechecked` ∧ ¬fable-model → pending. A Fable-authored entry with a stale `fable_rechecked = false` is treated as ALREADY satisfied (nothing pending).
    2. Conservative default preserved: `strong_model` ABSENT/empty (legacy entry) keeps today's behavior (pending → optional recheck; the elevation is non-gating and cheap, so unknown-model errs toward the recheck).
    3. No change to the `standin` derivation (id:a42e territory) or to relay-loop.js's elevation OR.
  - **Tests**: `tests/test_classify_repo_fable_model_gate.sh` (`# roadmap:5884`) — hermetic (idiom: `test_classify_repo_standin_gate.sh`): (i) toml block `strong_model = "claude-fable-5"` + `fable_rechecked = false` → `--emit unit` `strongRecheckPending==false`; (ii) `strong_model = "claude-opus-4-8"` + `fable_rechecked = false` → `true` (regression guard); (iii) `strong_model` absent + `fable_rechecked = false` → `true` (legacy conservative default). RED until landed.

- [ ] [HARD — pool] Integrator `-c` anchor: tag the MERGED tip when a review/recheck branch carries commits (routed:37f0; second occurrence routed:20b2 = TODO id:962d) <!-- id:25aa -->
  - **Why** (inbound from the zkm-photo relay review 2026-07-02): the 2026-07-01 23:55 zkm-photo Fable-recheck checkpoint was anchored on the child's BASE commit although the branch had a merged commit (REVIEW_ME prune) plus its own RELAY_LOG commit — so the run's OWN commits sit permanently outside the audited window and classify-repo re-dispatches a "substantive unaudited commits" review forever (self-heals only when a later ckpt tags past the residue). Sibling of routed:f3d0/id:a42e (different mechanism, same perpetual-re-dispatch symptom); the carries-commits COMPLEMENT of shipped id:8e3e (zero-commit branch → tag the reviewed tip). **Second independent occurrence** (llm-from-scratch review 2026-07-02, routed:20b2/TODO id:962d): `relay-ckpt-20260702-0038` annotated with the Fable-recheck summary but pointing at the PREVIOUS checkpoint commit `64aa14d` instead of its own `27c53d7` — same fail-safe over-inclusion (next window double-audits already-checkpointed commits).
  - **Acceptance**: the integrate() `-c` computation in `relay-loop.js` picks: zero-commit branch → the reviewed tip (id:8e3e rule, unchanged); branch WITH commits → the POST-MERGE tip on main (the audited boundary must include the run's own merged commits). ENGINE-EDIT CAUTION (template-literal-lint hazard): `node --check` + `lint-workflow-templates.mjs` + structure tests green. OPTIONAL defensive half (from id:962d — executor's judgment on cost): a `ckpt-tag.sh` assert that when `-c` is given alongside a known integrated-branch tip, the tag target CONTAINS that tip (loud reject otherwise); and/or note a candidate relay-doctor invariant (latest ckpt tag anchored strictly behind commits its own annotation claims to audit) for the id:4da4 detector family — do NOT gold-plate, the `-c` computation fix is the deliverable. **Closing this item: also tick TODO id:962d** (folded second occurrence) and verify the fix against the llm-from-scratch signature.
  - **Tests**: structure test naming the merged-tip rule (idiom: `test_ckpt_tag_commit_target.sh`); hermetic behavioral fixture if feasible (branch with commits → tag lands on the post-merge tip, not the base).

- [ ] [ROUTINE] `scan-routed.sh --apply` — INBOUND stubs must land in an ACTIVE TODO section, never under `## Done` (found by the 2026-07-02 review) <!-- id:14d0 -->
  - **Why** (TODO id:14d0): the stub write path (`scan-routed.sh:280` → `md-merge.py update-ids`) appends new lines at EOF; this repo's `TODO.md` ends with the `## Done` section, so BOTH 2026-07-02 ingests (routed:1c2b → id:5884, routed:20b2 → id:962d) were misfiled as open `- [ ]` items under `## Done` — open work hidden in a done section (wrong for archive semantics, section-aware scanners, and human reading). Deterministic and recurring: every future `--apply` against a Done-terminated TODO misfiles the same way. The 2026-07-02 review relocated the two lines by hand; this item fixes the tool.
  - **Acceptance**:
    1. A newly-written INBOUND stub lands BEFORE the first `## Done` / archive-class heading (Done/Archive/Icebox), or in a dedicated inbound/active section — EOF append remains ONLY the fallback when no such heading exists. Mechanism is the executor's choice (an insertion anchor in `md-merge.py update-ids` for new ids, or scan-routed pre-computing an anchor line) — keep the flock'd atomic write path, never a raw append.
    2. Idempotency + existing behavior preserved: `test_scan_routed_apply.sh` and `test_md_merge*`/existing md-merge specs stay green; updating an EXISTING id keeps its line position (only NEW-id insertion moves).
  - **Tests**: `tests/test_scan_routed_stub_placement.sh` (`# roadmap:14d0`) — hermetic (idiom: `test_scan_routed_apply.sh`): target repo TODO.md ends with a `## Done` section → after `--apply`, the stub line appears BEFORE the `## Done` heading (and not after it); a TODO with no Done heading still gets the stub (EOF fallback). RED until landed.

- [ ] [HARD — pool] `review.md` step 3 — run-or-record-skip MANDATORY for every declared test tier (routed:49a0) <!-- id:f032 -->
  - **Why** (inbound from the isochrone Fable recheck 2026-07-02): isochrone's e2e tier was RED for 13 days (2026-06-17..30) across 5 reviews logging "suites green" — the worktrees lacked node_modules, playwright was silently absent, and the reviews ran only the unit tiers while claiming green for the suite. A green claim derived from a subset of tiers is the same class as C3's "a skipped or uncompiled test is NOT a pass".
  - **Acceptance**: `review.md` step 3 requires the reviewer to (a) ENUMERATE the repo's declared test tiers (package.json scripts / Makefile targets / CI config); (b) run each, or RECORD-THE-SKIP with the reason in RELAY_LOG + the returned summary; (c) NAME the tiers actually run in any green claim — "suites green" from a subset is banned wording. Keep it aligned with handoff C3's `unverified` doctrine (same file family, cite it).
  - **Tests**: a wording drift-guard over `review.md` step 3 (enumerate/record-skip/name-tiers markers) — weak but cheap; the behavioral enforcement is the Opus reviewer following its contract.

- [ ] [HARD — decision gate] Relay consumer of the id:2840 derived ledger index (cross-ledger / count / promotion) <!-- id:659c -->
  - 🚧 GATED — not dispatchable now: waits on the project_manager derived index (id:2840, `routed:1e99`) shipping its generated artifact + stable contract. When it lands, re-lane to `[HARD — pool]`: relay `review`/`human` + the TODO count line read the artifact instead of hand-grepping; retire the per-review TODO-twin close + the `orphan-scan --cross-ledger` hand-check; DROP the d5e0 count prose (folds in TODO id:1de1). Meeting: `docs/meeting-notes/2026-06-23-0803-ledger-drift-derived-index.md`. Promoted 2026-07-02 with the gate EXPLICIT so unpromoted-scan sees a ROADMAP twin (it re-surfaced as `promote` every round while the gate lives in another repo); tagged decision-gate (not pool) so `open_hard_pool` never dispatches it while gated.

- [x] [ROUTINE] `reconcile-repo.sh` — bounded side-effecting git reconciliation, split out of the LLM shard (flip step b, id:a0b6; meeting 2026-07-01-1904) <!-- id:5987 --> done 2026-07-01 (executor): implemented + registered in Makefile, tests/test_reconcile_repo.sh 7/7 PASS
  - **Why** (meeting `docs/meeting-notes/2026-07-01-1904-a0b6-step-b-engine-swap.md`, A1): the flip swaps the LLM discovery shard for the side-effect-free `classify-verdict`, but the shard ALSO does side-effecting git the classifier can never hold. `relay-loop.js` is a Workflow script (no subprocess) so this must be a script an agent runs. The dangerous op (orphan reap-vs-park `merge-base --is-ancestor` → force `worktree remove`) is exactly what needs a hermetic RED test — testability, not reuse, justifies the split.
  - **Acceptance**:
    1. `relay/scripts/reconcile-repo.sh --repo <name> --path <abs>` performs ONLY the bounded side-effecting git ops transcribed from `relay-loop.js:854-870`: behind-origin `merge --ff-only` (then leave state for a fresh gather), DIVERGED → no-op surface (never commit), stale-worktree reap (`worktree remove --force` + `branch -D`) when HEAD is an ancestor of main, orphan-park (`branch -m … relay/orphan/*` + `worktree remove --force`) when it carries unmerged commits, and the id:bae5 in-place `uv.lock` commit when `dirty_lock_only`. No verdict/classification logic (that stays `classify-repo.sh`). Registered in Makefile relay_FILES/EXEC/ALLOW.
    2. Emits a small JSON summary of what it reconciled (for the runner to fold into `surfaced`); deterministic reap-vs-park decision; no `find`/broad-tree hunting (id:612f).
    3. Runner contract: an agent runs `reconcile-repo.sh` THEN `classify-repo.sh` per repo — the two stay separate so `classify-repo.sh` remains hermetically testable in isolation.
  - **Tests**: `tests/test_reconcile_repo.sh` (`# roadmap:5987`) — hermetic mktemp git fixtures seeded from the REAL id:689c/3ac8/1f53/c3f7/bae5 states (behind-only ff, diverged block, stale-reap, orphan-park, uv.lock-only dirty). RED until it lands.

- [x] [ROUTINE] full-unit assembler — `classify-repo.sh --emit unit` (flip step b sub-component, id:a0b6; discovered 2026-07-01) done 2026-07-01 (executor): --emit unit merges gather passthrough + toml/ckpt-msg derivations + classify-verdict output into full DISCOVER_SCHEMA unit; default mode byte-unchanged <!-- id:3d61 -->
  - **Why**: the mechanical runner (a0b6) needs a COMPLETE `DISCOVER_SCHEMA` unit per repo (`relay-loop.js:351-435`: path/repo/verdict/reason + lastCkpt/income/hasRoutine/openHard/standin/is_finished/top_intensive/substantive_unaudited/work_sig/open_hard_pool/strongRecheckPending/intensive). The LLM shard assembled those from the gather JSON + relay.toml; `classify-repo.sh` today emits ONLY classify-verdict's `{verdict,reason,evidence,ambiguous}`. Without a deterministic assembler the runner would have to improvise the field mapping (the exact non-determinism the flip removes). Surfaced while mapping the a0b6 contract 2026-07-01.
  - **Acceptance**:
    1. `classify-repo.sh --emit unit --repo <name> --path <abs>` emits ONE full-unit JSON with EVERY DISCOVER_SCHEMA unit field. WITHOUT `--emit unit` the output is UNCHANGED (`{verdict,reason,evidence,ambiguous}` — `test_classify_repo.sh` stays green).
    2. Deterministic derivations (from the old shard prose `relay-loop.js:876-887`): `income` ⟵ relay.toml block `income = true`; `standin` ⟵ gather `latest_ckpt_msg` contains `fable-standin`; `strongRecheckPending` ⟵ block `last_strong_ckpt` set ∧ `fable_rechecked` false/absent; `lastCkpt` ⟵ gather `latest_ckpt`; `openHard`/`open_hard_pool`/`is_finished`/`top_intensive`/`substantive_unaudited`/`work_sig` verbatim from gather; `verdict`/`reason`/`intensive` from classify-verdict. SIDE-EFFECT-FREE.
  - **Tests**: `tests/test_classify_repo_unit.sh` (`# roadmap:3d61`) — hermetic fixtures assert the full field set, the derivations, income/standin/strongRecheckPending defaults, verdict parity with default mode, and the unchanged-default regression guard. RED until `--emit unit` lands.

- [x] [ROUTINE] `discover-repo.sh` — per-repo composition (reconcile → classify → route) (flip step b sub-component, id:a0b6; 2026-07-01) <!-- id:64b4 --> done 2026-07-01 (executor): implemented, composes reconcile-repo.sh + classify-repo.sh --emit unit, all 5 routing scenarios green
  - **Why**: to keep the `relay-loop.js` edit thin (agent runs ONE script per repo, pure transport), the per-repo reconcile+classify+ROUTE logic is itself a deterministic, testable script. It composes `reconcile-repo.sh` (id:5987) + `classify-repo.sh --emit unit` (id:3d61) and emits `{units,surfaced,skipped}` for one repo. Doing the routing in a script (not the agent prompt) keeps the mechanized path fully tested.
  - **Acceptance**:
    1. `discover-repo.sh --repo <name> --path <abs> [--runid <id>] [--live-claims <csv>] [--main-branch <name>]` emits ONE JSON `{units:[≤1],surfaced:[],skipped:[]}`. ROUTING: run reconcile-repo.sh; **if it surfaced anything → return those surfaced, no classify, no unit** (reconcile surfaces EXACTLY the don't-work cases: diverged/parked/in-flight — never double-surface). Else run `classify-repo.sh --emit unit` and route by verdict: `blocked`→surfaced(no unit); `AMBIGUOUS`→surfaced with a LOUD reason(no unit — dormant hook, NO LLM prompt resurrected); `idle`→unit + skipped rollup; else→unit.
    2. Only reconcile's bounded git ops mutate; the routing + classify are read-only.
  - **Tests**: `tests/test_discover_repo.sh` (`# roadmap:64b4`) — hermetic fixtures for all 5 routing branches (execute / diverged-surface-once / idle+skipped / dirty-blocked / uv.lock-relock→execute). RED until `discover-repo.sh` lands.

- [x] [HARD — pool] a0b6 remainder — the confined `relay-loop.js` verdict-source swap (flip step b; meeting 2026-07-01-1904) <!-- id:a0b6 --> done 2026-07-01 (supervised): shardPrompt (74-line LLM classifier) DELETED, replaced by a mechanical runner calling discover-repo.sh per repo; node --check + template-lint clean; nested-uv.lock fidelity + id:1f53 suppress-redispatch reimplemented in reconcile-repo.sh (found via failing structure tests); 11 structure tests repointed to the new script homes; suite 151/0. The LLM discovery shard is GONE — discovery is now fully deterministic (reconcile+classify+route), LLM confined to the dormant AMBIGUOUS surface.
  - **GATED on id:5987 (done ✓) + id:3d61 (done ✓) + id:64b4 green** (the runner invokes `discover-repo.sh`, which composes reconcile + classify --emit unit). Careful supervised engine work — the engine crashed the pool 3× on the template-literal-lint hazard; NOT a tail-of-session edit.
  - **Why** (same meeting, A3): DP1 (2026-06-30-1523) ratified Replace — classifier primary, LLM shard fires only on AMBIGUOUS. Step (a) reached verdict parity (id:e424); this is the engine edit that makes `classify-verdict` the primary verdict source.
  - **Acceptance**:
    1. Replace the `shardPrompt` builder + the `agent(shardPrompt(chunk), …)` call (`relay-loop.js:820-900`) with a runner-agent prompt: for EACH repo in the chunk run `discover-repo.sh --repo <repo> --path <path> --runid <runId> --live-claims <csv> --main-branch main` and CONCATENATE each repo's `{units,surfaced,skipped}`; run NOTHING else (id:612f NO-FILESYSTEM-HUNTING guard verbatim). Return the SAME `SHARD_SCHEMA` shape. (LLM judgment is confined to the dormant `AMBIGUOUS` path, which `discover-repo.sh` surfaces loudly — classify-verdict never emits it today, so the big shard prompt is DELETED, not kept.)
    2. HARD swap — old `shardPrompt` DELETED (not commented). Edit confined to `:820-900`; the downstream merge/backstop code (`:906-1063`) and `SHARD_SCHEMA` UNCHANGED. The four JS-side backstops (id:000d/9973/ad74/365b) stay (A2). Rollback = `git revert` of this commit; NO runtime fallback flag.
    3. NESTED-uv.lock fidelity (folded in from 5987 review): before the flip, reconcile-repo.sh's LOCK guard must commit a nested `plugins/*/uv.lock` too (currently a literal root-`uv.lock` porcelain match) — key it on gather's nested-aware `dirty_lock_only`, or the zkm cascade stays dirty-but-dispatched. Add a nested-lock fixture to `test_reconcile_repo.sh`.
    4. `tests/test_workflow_template_lint.sh` extended for the new prompt + a new `tests/test_relay_runner_swap.sh` structure test (runner call feeds the same schema the merge code reads) both green; `make test` fully green with THIS box ticked; one `/relay --once` smoke run on the drained portfolio (0 crashes, byte-compatible discovery, verdicts match the historical backtest) as the acceptance gate.
  - **Out of scope**: b444 lane-triage broker, inotify (id:0ee6), continuous dispatch (id:80b8), unpromoted-scan promote/surface semantics, and deleting any backstop (id:b50e).

- [ ] [HARD — decision gate] Delete the id:000d/9973/ad74 JS-side backstops once the LLM-RUNNER-transport-infidelity residual is proven constrained (flip follow-on; meeting 2026-07-01-1904) <!-- id:b50e -->
  - **REFRAMED 2026-07-03 (evidence-gate analysis): NO-GO, keep all three.** The original "AMBIGUOUS→LLM path" framing was imprecise: `classify-verdict.sh` can't emit AMBIGUOUS (hardcoded false) and the dormant `discover-repo.sh` hook is explicitly "NO LLM call" — so that literal path is unreachable, not merely constrained. What 000d/9973/ad74 ACTUALLY guard post-flip is an **unfaithful haiku discovery runner** (`relay-loop.js:862`, still an LLM relaying `discover-repo.sh` JSON) emitting a bogus execute/hard/handoff. That residual is NOT proven constrained: (1) **no fire-frequency data exists** — the guards only `log()` to sandbox stdout (id:854c files the instrumentation to fix this); (2) shadow-log shows RED>0 in 3/10 snapshots and is idle-dominated (drained portfolio barely exercises the acted-on states); (3) **open revert dispute id:3134** ("REVERT 0c9bcf9 NOW", still open) — deleting the classifier's safety nets while the classifier's correctness is under active challenge is backwards. The guards are ~30 cheap demote/promote-only lines. **GO criteria:** (a) id:854c instrumentation live, (b) id:3134 resolved (revert declined + 3 RED cases triaged non-defect, OR classifier hardened), (c) a window of NON-drained forward runs with 000d/9973/ad74 firing 0 times. DEP: id:854c, id:3134.
  - 🚧 GATED — not dispatchable now. After the flip (id:a0b6), 000d finished-demote / 9973 hard-pool-demote / ad74 INTENSIVE-promote only guard the residual `AMBIGUOUS`→LLM surface. When that surface is proven constrained (or itself removed), the three become vestigial and should be deleted (constraint-archaeology). **id:365b circuit breaker STAYS** — it is cross-round loop state the per-repo classifier cannot implement. Do NOT start before a0b6 ships + the AMBIGUOUS path is characterized.

<!-- id:4da4 part-2 invalid-state detector — meeting 2026-07-01-2142-relay-state-machine-invalid-state-detector.md.
     Model (artifact×actor×transition matrix + invariants I1–I9) lives in that note. C5 ratified report-only:
     every check below surfaces LOUDLY but NEVER auto-blocks a round; honor relay-doctor's existing --strict
     (id:a883) as an explicit opt-in only. C1–C3 land in parallel (no cross-dep). -->
- [x] [ROUTINE] relay-doctor check 9 — main-checkout residue detector (I1/I7) (id:4da4 pt2; meeting 2026-07-01-2142) <!-- id:8018 --> done 2026-07-01 (opus): check 9 reuses clean-tree-gate.sh, counts non-lock uncommitted entries as residue, lock-only=benign; report-only + --strict; test_relay_doctor_residue.sh 4/4
  - **Why**: seed invalid-state (i) — a gate-detection/handback path can strand an uncommitted ledger edit on the main checkout (loderite id:3801 residue). `clean-tree-gate.sh` enforces clean-or-lock-only only AT integrate, per-repo; there is no standing sweep. Report-only detection is the regression guard.
  - **Acceptance**: a new `check_repo` check in `relay-doctor.sh` (matching checks 1/2/6/7) that reuses `clean-tree-gate.sh` (id:9bec no-reimplement rule) to classify each own repo's main checkout; a non-lock-only dirty tracked file counts into `repo_issues`/`issues_total`; prints "clean" or the findings; report-only (nonzero only under the existing `--strict`). NO new auto-block.
  - **Tests**: `tests/test_relay_doctor_residue.sh` (`# roadmap:8018`) — hermetic: own repo with a foreign-dirty tracked ledger edit → reported; lock-only dirty → clean; `--strict` exits nonzero on a residue. RED until landed.
- [x] [ROUTINE] relay-doctor check 10 — verdict-invariant replay detector (I2/I4) (id:4da4 pt2; meeting 2026-07-01-2142) <!-- id:188c --> done 2026-07-01 (opus): classify-repo.sh --emit unit now exposes actionable_routine_open; check 10 asserts I2 (execute⟹aro>0) + I4 (intensive⟹verdict∈{execute,hard}) with honest coverage note; RELAY_DOCTOR_CLASSIFY_REPO override for the stub; test_relay_doctor_verdict_invariant.sh 4/4
  - **Why**: seed invalid-state (ii) — `execute` on a repo with no executor-actionable work. Part-1 PREVENTS it at source (`classify-verdict.sh:91` gates on `actionable_routine_open`); this is the standing regression guard that prevention lacks. Self-replay cross-checks the derived count (`classify-repo.sh`) against the verdict (`classify-verdict.sh`) — different scripts, so it catches the part-1 gate-wiring bug class.
  - **Acceptance**: a new check that runs `classify-repo.sh --emit unit` (side-effect-free) per own repo and asserts `verdict==execute ⟹ actionable_routine_open>0` AND `intensive!="" ⟹ verdict∈{execute,hard}` (id:5ac6). A violation is a LOUD issue. Print an HONEST coverage note: this guards verdict↔derivation CONSISTENCY, not derivation CORRECTNESS (a bug shared by derivation+gate is out of reach — the `relay-events.jsonl` real-dispatched-verdict read is the noted future upgrade). Report-only; honor `--strict`.
  - **Tests**: `tests/test_relay_doctor_verdict_invariant.sh` (`# roadmap:188c`) — hermetic: `@manual`-only `[ROUTINE]` repo (verdict≠execute → clean); a synthetic unit with `intensive!=""` ∧ verdict=review → flagged; `execute` ∧ `actionable_routine_open==0` → flagged. RED until landed.
- [x] [ROUTINE] relay-doctor check 11 — last_ckpt tag existence detector (I8) (id:4da4 pt2; meeting 2026-07-01-2142) <!-- id:333c --> done 2026-07-01 (opus): check 11 rev-parse --verify's each own repo's relay.toml last_ckpt (empty=clean, dangling=flagged); coverage-gap block now names I5 (id:e149) + I9 (id:b444); test_relay_doctor_last_ckpt.sh 4/4
  - **Why**: the integrator writes each own repo's `last_ckpt` (`relay-loop.js:1426`); a failed push / aborted tag can desync it from the actual tag set. A dangling `last_ckpt` is an invalid state a `rev-parse --verify` catches deterministically.
  - **Acceptance**: a new check that, for each own repo, parses `last_ckpt` from its relay.toml block (reuse the doctor's tomllib reader) and runs `git -C <path> rev-parse --verify refs/tags/<tag>`; a missing tag counts as an issue. Empty/absent `last_ckpt` is NOT an issue (a not-yet-checkpointed repo). Report-only; honor `--strict`. Also add I5 (gated id:e149 heartbeat) + I9 (gated id:b444 decision-queue schema) to the doctor's coverage-gap "checks NOT yet wired" honesty block (no build) so the report never looks falsely green.
  - **Tests**: `tests/test_relay_doctor_last_ckpt.sh` (`# roadmap:333c`) — hermetic: toml `last_ckpt` naming a non-existent tag → flagged; naming a real tag → clean; empty `last_ckpt` → clean; assert the coverage-gap block names I5/I9. RED until landed.
- [x] [HARD — pool] atomic main-write fix for id:3801 handback follow-up (seed invalid-state i) (id:4da4 pt2; meeting 2026-07-01-2142) <!-- id:e5e9 --> done 2026-07-01 (opus): handback-followup.py now passes --commit to md-merge (id:148b atomic write+commit under one flock), then legacy-mode git-lock-push of the already-committed HEAD — the write→commit stranding window is gone; HANDBACK_GIT_LOCK_PUSH override; death-sim test_handback_atomic_commit.sh 3/3 (dying push → clean tree). reconcile-repo.sh out of scope
  - **Why**: `handback-followup.py:173` runs `md-merge.py update-ids` WRITE-ONLY (no `--commit`) then `:194` runs `git-lock-push.sh` as a SEPARATE step — a death between them strands `ROADMAP.md` dirty on the main checkout (the exact loderite id:3801 residue that motivated id:4da4). The structural fix is to make the write+commit ONE flock'd op.
  - **Acceptance**: route `handback-followup.py`'s ROADMAP write+commit through the id:148b atomic path — pass `--commit "<msg>"` to the existing `md-merge.py` call so write+commit happen under the one flock (the subsequent `git-lock-push` becomes push-only of an already-committed change), OR fold the write through `commit-ledger.sh`. NO functional change to what gets written; the ONLY change is closing the write→commit window. `reconcile-repo.sh:86` (un-serialized but commits, never strands) is OUT of scope (meeting D-C4-scope; observe-first). Cross-ref id:148b, id:2147.
  - **Tests**: extend `tests/` with a hermetic case (`# roadmap:e5e9`) that simulates a death BETWEEN the md-merge write and the push (e.g. run the write step, then assert the tree is NOT left with an uncommitted ROADMAP.md — the write must already be committed under the flock). RED until the atomic path lands.

<!-- 2026-07-01 fable catch-up review findings (relay-machinery, evidence in relay-events.jsonl + git timestamps; TODO.md carries the full narrative under the same ids — single-id-two-views) -->
- [x] [HARD — pool] Integrator: distinguish a ZERO-COMMIT review branch from a duplicate dispatch — checkpoint the reviewed tip, never handback (found 2026-07-01, run relay-20260701-202806-14640; done 2026-07-01: relay-loop.js "Already up to date" ⇒ ckpt-tag `-c <reviewed-tip>`, destructive cleanup scoped to own artifacts; tests test_ckpt_tag_commit_target.sh + suite 158 green) <!-- id:8e3e -->
  - **Why**: a review child with nothing to write (clean window, ledger no-op) returns a branch whose tip == its base; if main advanced meanwhile (interactive commits), `merge --no-ff` says "Already up to date" and the integrator hands back "Duplicate dispatch" with NO checkpoint — the audited window never closes, so the next discovery re-dispatches a strong review of the same commits (unbounded strong-tier waste in an unattended pool). Verified 2026-07-01 20:36: child based on the TRUE then-HEAD 33169ee, zero commits; main moved to 65ce4ea (20:34:53) before integration.
  - **Acceptance**:
    1. The integrate() prompt (relay-loop.js:1415-1430 area) branches on `tip == base of the review branch ∧ tip is ancestor of main`: this is a CLEAN EMPTY REVIEW → run ckpt-tag.sh at the BRANCH TIP (the audited boundary — NOT current main HEAD, whose newer commits the review never saw and must not be marked audited), update relay.toml per step 6, remove worktree + branch; only a branch already merged by an earlier integrator of the SAME run is "duplicate dispatch".
    2. Careful supervised engine work (template-literal-lint hazard, same class as a0b6); node --check + template-lint green.
  - **Tests**: a structure test asserting the integrate prompt names the zero-commit/ckpt-at-tip rule (same idiom as test_workflow_template_lint.sh); hermetic behavioral fixture if feasible (zero-commit branch + advanced main → tag lands on branch tip, no handback).
- [x] [ROUTINE] `ckpt-tag.sh`: sync `[repos.<name>]` `last_ckpt` (+ `last_strong_ckpt`/`strong_model` when strong) in relay.toml via `relay-state-write.sh toml-set` (found 2026-07-01: tags 1948/2019/2110 minted by supervised sessions while relay.toml stayed at 1635; done 2026-07-01: flock'd sync at the choke-point, spec test_ckpt_tag_toml.sh GREEN) <!-- id:0a3b -->
  - **Why**: only the pool integrator writes relay.toml (relay-loop.js:1426); supervised/manual checkpoints via ckpt-tag.sh leave `last_ckpt`/`last_strong_ckpt` stale. Discovery is NOT mis-driven (gather-repo-state.sh:156 reads `git tag -l` — tags are the source of truth) but the id:e030 Fable-recheck queue misses strong checkpoints made outside the pool and relay-doctor check 11 validates a stale value.
  - **Acceptance**:
    1. After a successful tag, `ckpt-tag.sh` sets `last_ckpt = "<tag>"` for `[repos.<name>]` through the flock'd `relay-state-write.sh toml-set` single-writer — IFF the repo has a `[repos.<name>]` block (silently skip unmanaged repos; never create a block). When the annotation label records a strong model (`claude-opus-*` / Fable), also set `last_strong_ckpt`/`strong_model` per the id:e030 shape (do NOT touch `fable_rechecked` — the integrator owns its consume-side).
    2. Honor the existing `FABLES_CONFIG` env override (relay-state-write.sh's hermetic-test path) so tests never touch `~/.config/relay`; a missing/unreadable relay.toml is a logged no-op, never a failure of the tagging itself.
  - **Tests**: `tests/test_ckpt_tag_toml.sh` (`# roadmap:0a3b`) — hermetic: managed-repo fixture → last_ckpt updated under flock; strong-label fixture → last_strong_ckpt+strong_model set; unmanaged repo → toml untouched; toml absent → tag still succeeds. RED until landed.

- [x] [HARD — pool] `classify-verdict.sh` case-b split → `human` + mechanical surface-filer (meeting 2026-06-30-2238) <!-- id:5eb3 -->
  - **Why** (meeting `docs/meeting-notes/2026-06-30-2238-classifier-flip-prereqs-intensive-casebt.md`): `classify-verdict.sh:100` fires `handoff` on `promote>0 OR surface>0`. id:47f1 already broke the case-g loop (surface items file to the decision-queue once, then drop out), so this is a COST-TIER fix, not a correctness fix: a `promote==0 ∧ surface>0` repo has nothing an Opus `handoff` can promote — its only action is mechanical `decision-queue.sh add` per surface item. Burning the apex turn on filing-only is the over-tier the mechanize-first heuristic dissolves.
  - **Acceptance**:
    1. `classify-verdict.sh` splits the old case-b three ways: `promote>0 → handoff`; `promote==0 ∧ surface>0 → human` (priority_rank 5); `promote==0 ∧ surface==0 → idle` (unchanged). The `human` verdict must NOT outrank execute/review/hard (D3 order intact).
    2. The surface→decision-queue filing RELOCATES out of the Opus handoff handler (`handoff.md` case-g) into a FORCED, LOGGED, idempotent mechanical step wired where the loop consumes the `human` verdict (new `relay/scripts/file-surface-decisions.sh <repo>` or fold into `unpromoted-scan.sh --apply`; reuse `decision-queue.sh add --source-id <token>` + the id:47f1 exclusion). Anti-gaming invariant preserved: surface backlog is LOUD-surfaced and N decision-queue records are ACTUALLY written (a silent no-op here is the exact relay-2026-06-30 anti-pattern — must NOT recur). Update `handoff.md` so the handoff handler no longer files (the loop does).
    3. **RECONCILE**: the existing `tests/test_classify_verdict.sh:41` case (b) (roadmap:85df, TICKED) asserts surface-only → `handoff`; flip it to `human`. Full suite green requires it.
  - **Tests**: `tests/test_classify_verdict_humanlane.sh` (`# roadmap:5eb3`) — verdict-level three-way split (RED until landed) + a new hermetic filer test asserting N decision-queue records are written for a surface-only repo (no silent no-op). Plus the flipped case (b) in `test_classify_verdict.sh`.

- [x] [HARD — pool] INTENSIVE verdict-layer fail-safe: `intensive` flag + invariant + fail-closed dispatch assertion (SAFETY; meeting 2026-06-30-2238) <!-- id:5ac6 -->
  - **Why** (same meeting; SAFETY): `classify-verdict.sh` reads no intensive field, so `[HARD — pool] [INTENSIVE]` classifies as plain `hard` and `[ROUTINE] [INTENSIVE]` as plain `execute` — indistinguishable. The ONLY dispatch guard is loop-level `relay-loop.js` `ALLOW_INTENSIVE`, a single point of failure: a regression spawns an executor/apex child on resource-heavy work → stall or the [[oom-local-model-session-kills]] OOM-crash (Gemma-26B killed all 6 sessions).
  - **Acceptance**:
    1. `classify-verdict.sh` copies gather's `top_intensive` VERBATIM to an `intensive:"<resource>"` field beside an UNCHANGED `verdict` (a FLAG, never a new verdict value — `[INTENSIVE]` is an orthogonal resource axis operative only on dispatchable lanes; human-gated exclusion is inherited free because `top_intensive` is "" for human-gated items, id:a707). The field is always present (string, "" when none).
    2. Invariant `intensive != "" ⇒ verdict ∈ {execute, hard}` holds across the state space (test-locked).
    3. Add a FAIL-CLOSED pre-dispatch assertion in `relay-loop.js`: never spawn an executor/apex child on a unit with `intensive` set unless `ALLOW_INTENSIVE` — skip + surface loudly, never OOM-dispatch (third defense-in-depth layer; keep the existing partition + `resource:` claim).
  - **Tests**: `tests/test_classify_verdict_intensive.sh` (`# roadmap:5ac6`) — flag presence + verbatim copy + the verdict-coupling invariant (RED until landed). Extend `tests/test_relay_loop_intensive_emit.sh` (or a sibling) for the JS-side fail-closed assertion.

- [x] [ROUTINE] roadmap-lint case (d): realign INTENSIVE to operative-only-on-dispatchable-lanes (meeting 2026-06-30-2238) <!-- id:9062 -->
  - **Why** (same meeting; resolves the LIVE it-infra id:9321 false-positive surfaced by a parallel `/relay human` session): `roadmap-lint.sh:80` (comment "orthogonal, may co-occur") contradicts `:170` case (d) ("INTENSIVE valid ONLY on `[HARD — pool]`"), which also wrongly rejects `[ROUTINE] [INTENSIVE]`. gather's `top_intensive` is the operative source of truth (ROUTINE + HARD — pool; human-gated excluded).
  - **Acceptance**:
    1. `roadmap-lint.sh` case (d): ACCEPT `[INTENSIVE]` on `[ROUTINE]` or `[HARD — pool]` (operative); ACCEPT on human lanes (`hands`/`meeting`/`decision gate`/`@manual`) as advisory — NO violation; REJECT only `[INTENSIVE]` with no recognised lane (lane-less / underivable).
    2. Fix the contradictory `:80` comment + the db39 doc; restate the operative-only-on-dispatchable-lanes doctrine in `references/hard-lanes.md` (`[INTENSIVE]` operative on dispatchable lanes, advisory-inert on human lanes — NOT "amplification of HARD"; routine-intensive is operative).
    3. **RECONCILE**: this SUPERSEDES id:297b's case-d "pool-only" rule. `tests/test_roadmap_lint_tagprose.sh` (`# roadmap:297b`, TICKED) case (d) asserts `[HARD — meeting] [INTENSIVE]` must ERROR — flip it to the new rule (advisory-accept), or repoint that example at a genuinely lane-less item. Full suite green requires it. it-infra id:9321 keeps both tags — NO it-infra edit.
  - **Tests**: `tests/test_roadmap_lint_intensive_lanes.sh` (`# roadmap:9062`) — accept/reject matrix over operative + advisory + lane-less (RED until landed). Plus the reconciled case (d) in `test_roadmap_lint_tagprose.sh`.

- [x] [ROUTINE] `backtest-historical.py` — historical replay of past dispatch events against reconstructed ledger state (id:4d8e backtest cluster) <!-- id:0e57 --> done 2026-06-30 (executor): `relay/scripts/backtest-historical.py` [--since YYYY-MM-DD] [--limit N] [--json] [--append-log]; iterates `relay-events.jsonl` dispatch events, resolves each repo/timestamp to a historical commit via `git rev-list --before` (read-only), reconstructs `hasRoutine`/`roadmap_actionable_open`/`open_hard_pool`/`unpromoted`/`substantive_unaudited`/`is_finished` from `git show C:<file>` content, and pipes the reconstructed JSON to `classify-verdict.sh` → V'. Compares V' to event's `mode` (V): agree/diverge/new/crashes + per-mode agreement rates. Documented partial-fidelity boundary: `dirty=false`/`diverged=false` assumed (self-consistent: dispatch events were demonstrably not blocked); uv.lock and recurring-audit exemptions omitted. Historical diverges labelled "diverge" (CANDIDATE, not confirmed RED). Makefile relay_FILES/EXEC/ALLOW updated. `tests/test_backtest_historical.sh` (`# roadmap:0e57`) green; `relay/scripts/roadmap-lint.sh` exit 0; full suite green. FIDELITY PASS done 2026-06-30 (executor): (1) per-row `classifier_reason`+`classifier_evidence[]`+`reconstructed` input fields in every row; (2) tag-time filter applied (ckpt tags created after event ts excluded — fixes false-sub_unaudited-false for past events); (3) id:9973 recurring-audit gate applied (recurring-audit [HARD — pool] items excluded when sub_unaudited=false); (4) legacy-lane-vocab reconstruction gap (pre-id:78ff `[HARD — strong model]` etc. not counted as open_hard_pool, rows flagged `reconstruction-gap:legacy-lane-vocab`); (5) all-fields-empty reconstruction gap (commit-timestamp-boundary gap where ckpt commit at dispatch time is missed by strict `--before` filter); (6) 3-bucket diverge categorization (`candidate-classifier-worse` / `reconstruction-gap` / `classifier-better`); (7) output leads with `candidate-classifier-worse` count (quality signal, target 0) not agree%. `tests/test_backtest_fidelity.sh` (`# roadmap:0e57`) green. GUARDRAIL: agreement-with-shard is NOT a quality target; classifier-better divergences (shard was wrong) must be preserved, not erased. Over 767 real events: 0 crashes, 93 candidate-classifier-worse (surface for human review), 205 reconstruction-gap (legacy-lane-vocab:137, all-fields-empty:73, 9973:6), 66 classifier-better, 403 matches-shard.
  - **Why** (meeting 2026-06-30-1523 DP7, id:4d8e / id:9d2b): the live `backtest-verdict.py` (id:5f93) compares CURRENT-state classification to LAST-DISPATCHED-state, producing structural divergence because dispatching changes state. The historical mode reconstructs the ledger at the EXACT EVENT TIMESTAMP from git history, giving a meaningful (if partial-fidelity) agreement signal over the full dispatch corpus. Together with id:5f93 (live) and id:9d2b (forward-shadow), forms the three-layer pre-flip validation gate.
  - **Acceptance**:
    1. `relay/scripts/backtest-historical.py` reads each `kind=dispatch` event from `relay-events.jsonl`, resolves the repo path from `relay.toml` (honoring `# path:`), finds the commit as-of `ts` via `git rev-list -1 --first-parent --before=<ts> HEAD`, reconstructs the classifier input from `git show C:<file>` (ROADMAP.md + TODO.md), and calls `classify-verdict.sh` for V'.
    2. Non-own or missing repos: surfaced on stderr, counted in `skipped`, never silently swallowed (id:4e14).
    3. Repo younger than event (no commit before ts): counted as `new`, never crashes.
    4. `--json` emits `{summary: {events,crashes,agree,diverge,new,skipped,mode:"historical",per_mode_agreement,distribution_verdict,distribution_event_mode}, rows:[...]}`. Report-only, exit 0.
    5. NEVER uses `git checkout`, `git switch`, `git worktree add`, or any write op on a target repo. Only: `git -C <path> show`, `rev-list`, `tag`, `log`, `merge-base --is-ancestor`.
    6. Makefile: `backtest-historical.py` in relay_FILES, relay_EXEC, relay_ALLOW.
  - **Tests**: `tests/test_backtest_historical.sh` (`# roadmap:0e57`) — 3-commit temp repo + ckpt tags + fixture relay.toml/events; asserts: (a) agree=2/diverge=1 on known fixture events, 0 crashes; (b) `git worktree list` = 1 entry + branch set unchanged after run (read-only guard); (c) exit 0, plain mode works; bonus --since filter. Hermetic.

- [x] [ROUTINE] `gather-human-backlog.sh` — anchor the HARD-lane parse to the item's OWN bracket tag, ignoring a pool-lane token mentioned only in body prose <!-- id:1bbd --> done 2026-06-30 (executor): `emit_hard_lanes()` in `gather-human-backlog.sh` now strips backtick-quoted strings from the line before lane detection, so a prose mention like `` `[HARD — pool]` `` cannot shadow the item OWN bracket tag. `tests/test_gather_lane_anchor.sh` (roadmap:1bbd) green; `test_hard_lane_buckets.sh` unregressed; suite 135 green.
  - **Why** (inbox routed:6645 from it-infra relay HARD child relay-20260630-131714-19334): `emit_hard_lanes()` reads the lane by whole-line substring match with the **pool branch checked FIRST** (`gather-human-backlog.sh:197`), so any `[HARD — hands]`/`[HARD — meeting]` item whose body prose quotes the literal `` `[HARD — pool]` `` (e.g. a re-lane-criterion sentence) mis-buckets as `hard_pool`. Caused it-infra `open_hard_pool=2` false-positive → a wasted Opus HARD dispatch (it-infra ids 9321/c5e9 are genuinely `[HARD — hands]`). Confirmed reproduced this review.
  - **Acceptance**:
    1. The lane is read from the item's OWN bracket tag (the `[HARD — <lane>]` immediately after the title), not from a `[HARD — pool]` string anywhere on the line. Fix per the report: anchor the lane regex to the tag after the title, OR test hands/meeting before pool, OR strip prose past the title's lane tag.
    2. A `[HARD — hands]` item whose prose contains `` `[HARD — pool]` `` buckets as `hard_hands`; a `[HARD — meeting]` item with the same prose buckets as `hard_meeting`. A genuine `[HARD — pool]` item still buckets as `hard_pool` (no regression).
    3. `tests/test_hard_lane_buckets.sh` stays green (no regression to the existing lane-vocabulary contract).
  - **Tests**: `tests/test_gather_lane_anchor.sh` (`# roadmap:1bbd`) — a `[HARD — hands]` item with a `[HARD — pool]` prose mention must bucket as `hard_hands`; genuine pool item unaffected. RED until the fix lands.

- [x] [ROUTINE] `classify-verdict.sh` verdict-PARITY — `blocked` for dirty/diverged (flip step a, id:a0b6) <!-- id:e424 --> done 2026-06-30 (strong turn): added a rank-0 `blocked` verdict so the classifier reaches the shard's dispatch-or-not parity — DIVERGED (has_upstream ∧ ahead>0 ∧ behind>0) and DIRTY non-lock-only → `blocked` (surface, never dispatch), outranking every D3 verdict. NOT blocked: uv.lock-only dirty (id:bae5 exemption) and behind-only (shard ff-merges first). classify-verdict-ONLY change (classify-repo already passes the full gather JSON through). `tests/test_classify_verdict_parity.sh` (`# roadmap:e424`) green; existing classifier tests unregressed; suite 134 green. Remaining for the flip: the relay-loop.js swap (step b) — keeps the side-effecting reconciliation guards shard-side.

- [x] [ROUTINE] case-g loop-breaker — wire surface-item lane-triage to the decision-queue so `handoff` can never silently no-op (4d8e child g) <!-- id:47f1 --> done 2026-06-30 (strong turn): the live `/relay --afk` run surfaced the defect — the classifier CORRECTLY emits `handoff` on surface-only backlog (DoD case b), but the resolution silently no-op'd, so `unpromoted-scan` re-counted surface items every round → `handoff` re-fired forever (30-handoff cluster = this loop, NOT a classifier miscount). Fix (NOT the classifier): (1) `decision-queue.sh add --source-id <token>` records the originating TODO id; (2) `unpromoted-scan.sh` excludes a token with an OPEN decision-queue record → a filed surface item drops out of fresh backlog and `handoff` stops re-firing; a RESOLVED record re-surfaces it for promotion; (3) `handoff.md` C2 now documents the FILE-each-surface-item-to-the-queue step (the missing "below") with the load-bearing `--source-id`, and declares a handoff that leaves surface items neither promoted nor filed INCOMPLETE. `tests/test_unpromoted_decision_queue_exclusion.sh` (`# roadmap:47f1`) green; case-b/h classifier tests unregressed; suite 136 green. Remaining loud-failure surface (de31/b444): the conservative inline lane-triage sub-agent (confidence → enqueue) is the decision-queue's own scope, not this loop-breaker.
- [x] [ROUTINE] `decision-queue.sh` — durable file-backed human-decision-request queue (C7, DP4) <!-- id:de31 --> done 2026-06-30 (executor): implemented `relay/scripts/decision-queue.sh` with add/list/resolve subcommands; flock'd on `<queue>.lock`; JSON built via python3; `RELAY_DECISION_QUEUE` env-overridable; registered in Makefile relay_FILES/EXEC/ALLOW.
  - **Why** (meeting 2026-06-30-1523 DP4): when the loop hits a resolution it can't mechanically close (a forced lane-triage of N surface items, a "close 244b or drain?" call), it must APPEND a decision request to a durable store and keep working — never silently no-op (cases g/h). This is the "one home" (the substrate); the transport (broker vs FIFO vs file-tail) is the deferred sibling id:b444.
  - **Acceptance**:
    1. `relay/scripts/decision-queue.sh add --repo <r> --kind <k> --question <q> [--option <o>]… [--evidence <e>]` mints a decision id, appends ONE JSON record `{id,repo,kind,question,options[],evidence,requested_at,status:"open"}` to `$RELAY_DECISION_QUEUE` (default `~/.config/relay/decision-queue.jsonl`), and prints the id. Append-only; flock'd (mirror `append.sh`/`commit-ledger.sh`).
    2. `decision-queue.sh list [--repo <r>]` prints the OPEN records (default open-only); `--all` includes resolved.
    3. `decision-queue.sh resolve <id> --answer <a>` sets `status:"resolved"`, `answer`, `resolved_at` on that record (rewrite under flock); resolved records drop out of the default `list`.
    4. Side-effect-free beyond the queue file; the queue path is env-overridable (hermetic tests).
  - **Tests**: `tests/test_decision_queue.sh` (`# roadmap:de31`) — add → list → second add (append) → resolve → open-list excludes resolved. RED until the helper lands.

- [x] [ROUTINE] `backtest-verdict.py` — pre-flip validation gate (replay classify-repo vs last-dispatch verdicts) <!-- id:5f93 --> done 2026-06-30 (strong turn): productized the dogfood prototype into `relay/scripts/backtest-verdict.py` (report-only, exit 0 like relay-doctor; `--json`); calls `classify-repo.sh` per own repo, compares to the most-recent `relay-events.jsonl` dispatch verdict. Gate run: **0 crashes / 49 repos** (the hard gate); diverged=40 but all explainable (state evolved since last dispatch — repos dispatched execute/review now show review from the resulting unaudited commits, or handoff once drained-with-backlog: the case-b/h fix). FIDELITY: live-state comparison, not full git-reconstruction — the classifier's input depends on ephemeral state (substantive_unaudited / worktrees / claims) that is NOT git-recoverable (the meeting's own partial-fidelity flag), so live + forward-shadow (id:9d2b) are the practical gate. `tests/test_backtest_verdict.sh` (`# roadmap:5f93`) green.

- [x] [ROUTINE] Record discover-sig on dispatch event (f896) <!-- id:f896 --> done 2026-06-30 (executor): two additive lines in `relay-loop.js` — (1) unit cache loop stamps `u.sig = sigByRepo[u.repo] || ''` on every fresh unit; (2) `pushEvent('dispatch', …)` now includes `sig: unit.sig || ''`. Purely additive; no verdict authority / shard / reconciliation changes. Template-literal lint stays clean. `tests/test_dispatch_event_sig.sh` (`# roadmap:f896`) green; suite 139 green.
  - **Why** (id:9d2b / id:4d8e): `relay-events.jsonl` dispatch records carried only `{repo,mode,tier,round}` — no input hash — so `backtest-verdict.py` compared current-state classification to a STALE last-dispatch verdict, producing structural divergence (agree=5/50 even on a clean tree). Recording the discover-sig at dispatch lets the backtest replay on the exact input the shard saw, making divergence bucketing (id:e8ea) sound.
  - **Acceptance**:
    1. `relay-loop.js` unit cache loop sets `u.sig = sigByRepo[u.repo] || ''` on every freshly classified unit.
    2. `pushEvent('dispatch', …)` includes `sig: unit.sig || ''` — fail-open (absent/empty sig → empty string sentinel).
    3. Purely additive: no change to verdict authority, shard, or reconciliation (id:a0b6 scope).
    4. `tests/test_workflow_template_lint.sh` stays green (template-literal hazard guard).
  - **Tests**: `tests/test_dispatch_event_sig.sh` (`# roadmap:f896`) — static source-shape assertions on relay-loop.js (grep + linter). RED until the edit lands.

- [x] [ROUTINE] Auto-bucket backtest divergences: state-drift vs true-disagreement (e8ea) <!-- id:e8ea --> done 2026-06-30 (executor): `backtest-verdict.py` now reads the `sig` field from each dispatch event; for each diverged row, recomputes the current discover-sig via `discover-sig.sh` and buckets: same-dispatch-sig AND same-current-sig → `RED` (real disagreement); absent/changed sig → `EXPECTED` (state-drift/pre-f896 event). RED and EXPECTED counts added to summary and `--json` output. Fail-open: empty current-sig → EXPECTED, never crash. Summary line now reads `agree=N diverged=N red=N expected=N`. `tests/test_backtest_bucketing.sh` (`# roadmap:e8ea`) green; suite 139 green.
  - **Why** (id:9d2b / id:4d8e): with f896's captured sig, diverged rows can be labelled mechanically — shrinking the human triage from ~43 rows/run to the handful of RED rows. Turns the id:9d2b gate from manual eyeballing into a mechanical pass/fail.
  - **Acceptance**:
    1. `backtest-verdict.py`: for each diverged row, reads `sig` from the dispatch event; calls `discover-sig.sh` for the current sig; same-sig-different-verdict → `RED`; changed/absent-sig → `EXPECTED`. Agree rows stay `agree`.
    2. `--json` summary includes `red` and `expected` counts. Plain output summary line shows both.
    3. Fail-open: if current-sig computation fails → EXPECTED, exit 0 (never crash).
    4. Pre-f896 events (no sig field) → EXPECTED (backward compatible).
  - **Tests**: `tests/test_backtest_bucketing.sh` (`# roadmap:e8ea`) — four cases: same-sig→RED, different-sig→EXPECTED, no-sig→EXPECTED, agree→agree. Hermetic fixture with real discover-sig.sh call.

- [x] [ROUTINE] Persist + auto-run the shadow accumulation log (1324) <!-- id:1324 --> done 2026-06-30 (executor): `backtest-verdict.py --append-log [<path>]` (env `RELAY_SHADOW_LOG`, default `~/.config/relay/shadow-log.jsonl`) appends one JSON line `{agree,diverged,red,expected,new,crashes,distribution,timestamp}` per run. Wired in `relay/SKILL.md` step 4: the front door runs `backtest-verdict.py --append-log` post-drain so id:9d2b accrues mechanically. `tests/test_backtest_append_log.sh` (`# roadmap:1324`) green; suite 139 green.
  - **Why** (id:9d2b): `backtest-verdict.py` was stdout-only — no place for the gate to accrue. The front door runs it automatically at end of every `/relay` run so the accumulation gate fills without human remembering.
  - **Acceptance**:
    1. `--append-log [<path>]`: appends ONE JSON line with keys `{agree,diverged,red,expected,new,crashes,distribution,timestamp}` to the log path; report-only, exit 0.
    2. `RELAY_SHADOW_LOG` env override controls the default path (hermetic tests).
    3. `relay/SKILL.md` step 4 (Exit summary) documents the front door running `backtest-verdict.py --append-log` post-drain.
  - **Tests**: `tests/test_backtest_append_log.sh` (`# roadmap:1324`) — append writes parseable JSON with expected keys; two appends yield two lines; explicit path argument; combined with `--json`. Hermetic.

- [x] [ROUTINE] `gather-repo-state.sh` — fix the env-var `execve` overflow on a >128KB ROADMAP <!-- id:07be -->
  - **Why** (found 2026-06-30 dogfooding id:3f0f): `emit()` hands large field values (the ROADMAP content + porcelain/toml/worktrees) to `python3` via ENV VARS; a single env string over `MAX_ARG_STRLEN` (128KB) breaks `execve` ("Argument list too long"). Real repos survive today because the emitted `roadmap` field is a ~94KB subset — but dotclaude-skills is already at 94KB and growing, and crossing 128KB crashes gather AND the whole `classify-repo.sh` chain. Same class as the id:3f0f wrapper fix (which used temp files).
  - **Acceptance**:
    1. `gather-repo-state.sh` no longer passes large field values to `python3` via env/argv — use a temp file or stdin so no single string can exceed `MAX_ARG_STRLEN`. The wrapper/caller path then works on a repo with a >128KB ROADMAP.
    2. Output is **byte-identical** to today on all existing inputs (the field set, ordering, and encoding are unchanged). Every existing gather/discovery test stays green (`test_discover_sig.sh`, `test_relay_discovery_guards.sh`, `test_relay_discover_shard.sh`, `test_classify_repo*.sh`, …).
    3. The temp file (if used) is cleaned up; gather stays side-effect-free outside its own scratch.
  - **Tests**: `tests/test_gather_repo_state_large.sh` (`# roadmap:07be`) — a fixture repo with a >128KB ROADMAP; gather must emit valid JSON (not crash). RED until the fix lands.
- [x] [ROUTINE] `classify-repo.sh` — DP1 assembly wrapper: gather → derive → fold unpromoted-scan → classify-verdict, end-to-end per repo <!-- id:3f0f -->
  - **Why** (dogfood finding 2026-06-30, id:4d8e / id:5f93): `classify-verdict.sh` (id:85df) is a pure function with NO producer for its full input — the live dogfood proved `gather-repo-state.sh` does not emit `hasRoutine`/`roadmap_actionable_open` and there is no wrapper folding in `unpromoted-scan`. This wrapper is what makes the classifier usable end-to-end and is the prerequisite for the real backtest (id:5f93) and the cutover. Productizes the throwaway prototype `scratchpad/backtest_dogfood.py`.
  - **Acceptance**:
    1. `relay/scripts/classify-repo.sh --repo <name> --path <abs>` emits ONE `{verdict,reason,evidence,ambiguous}` JSON on stdout, assembling: `gather-repo-state.sh` + DERIVED `hasRoutine`/`roadmap_open`/`roadmap_actionable_open` from `<path>/ROADMAP.md` (actionable = open `[ROUTINE]`/`[HARD — pool]` and NOT human-gated `[HARD — hands|meeting|decision gate]`/`@manual`) + FOLDED `unpromoted-scan.sh` `{promote,surface}` counts → piped to `classify-verdict.sh`.
    2. SIDE-EFFECT-FREE: runs the read-only helpers, mutates nothing (no commit, no ledger write, no tag). Registered in the Makefile `relay_FILES`/`_EXEC`/`_ALLOW`.
    3. End-to-end verdicts correct: open `[ROUTINE]` → `execute`; drained-`@manual`-only ROADMAP + untagged TODO backlog (surface) with HEAD audited → `handoff` (the case-b/h fix); finished ROADMAP + nothing unpromoted → `idle`.
  - **Tests**: `tests/test_classify_repo.sh` (`# roadmap:3f0f`) — hermetic mktemp git-repo fixtures run through the whole chain (integration tier, DP3). RED until the wrapper lands.
- [x] [ROUTINE] `classify-verdict.sh` — deterministic verdict classifier, the PRIMARY discovery verdict source (replaces the LLM shard) <!-- id:85df -->
  - **Why** (meeting 2026-06-30-1523 `docs/meeting-notes/2026-06-30-1523-relay-loop-mechanical-classifier.md`, umbrella id:4d8e DP1): relay discovery currently lets an LLM `discover-shard` own the primary verdict by trusting tag/gate/lane states that don't match the ledger — one `/relay --afk` run surfaced 8 false verdicts, all "the shard trusted a state the deterministic layer would have caught." `gather-repo-state.sh` (id:11ad) already computes the deciding fields and `relay-loop.js:397–429` already has JS backstops; this item consolidates that into ONE tested pure function so the common path is mechanical (DP1 "Replace": the shard fires ONLY on `AMBIGUOUS`).
  - **Acceptance**:
    1. `relay/scripts/classify-verdict.sh` reads a gather-repo-state JSON object on stdin (with an `unpromoted` summary `{promote,surface}` folded in) and emits ONE JSON object `{verdict, reason, evidence[], ambiguous}` on stdout. `verdict ∈ {execute, review, hard, handoff, human, idle, AMBIGUOUS}`; `evidence` is a list of `{field,value,source}` pointers; `ambiguous` is a bool (`AMBIGUOUS` is the ONLY verdict that routes to the LLM — DP2).
    2. PURE FUNCTION + SIDE-EFFECT-FREE: a function of its JSON input only (no git, no fs writes, no ledger mutation, no lease/dispatch). Orchestration (gather→scan→classify) stays in the caller. A picker may call it many times per round.
    3. Verdict logic gets the corpus right — at minimum cases (a) `open_hard_pool=0` ≠ `hard`; (b) drained-`@manual`-only ROADMAP + unpromoted backlog → `handoff` (not idle/human); (h) `is_finished` BUT unpromoted `promote`/`surface` → `handoff` (the finished guard consults the scan). D3 verdict-class order holds (execute → review → hard → handoff).
    4. Emits the D3 priority-class rank alongside the verdict (so a streaming refill picker — id:80b8 — orders units without recomputing).
  - **Tests**: `tests/test_classify_verdict.sh` (`# roadmap:85df`) — pure JSON-in/verdict-out fixtures seeded from the real 2026-06-30 failures (a/b/h) + the output contract. RED until the script lands. (The full two-tier RED harness incl. integration fixtures + cases e/f/g is umbrella child id:ccd9 / follow-ons; this item is the foundation the others build on.)
- [x] [ROUTINE] `roadmap-lint.sh` — loud-ERROR on a tag/prose lane disagreement (case c) and a free-typed `[INTENSIVE]` (case d) <!-- id:297b -->
  - **Why** (meeting 2026-06-30-1523, id:4d8e DP2/DP3 cases c/d): (c) ai-codebench id:244b carried `[HARD — decision gate]` while its own prose said "re-laned to pool, runs under --intensive" — the disagreement was read as a silent gate, the item never ran, and the empty run was misread as "done." The TAG is authority; a tag/prose disagreement must fail LOUD. (d) it-infra c5e9/fd30 had `[INTENSIVE — local-llm]` free-typed onto a disk `rm` / a `/meeting` decision item — INTENSIVE must be derivable, not free-typed.
  - **Acceptance**:
    1. `roadmap-lint.sh` exits NONZERO with a stderr ERROR naming the violation when an open item's lane bracket disagrees with a lane claimed in its own prose (case c).
    2. It exits NONZERO with a stderr ERROR when `[INTENSIVE — <resource>]` is free-typed onto an item whose resource is not derivable (case d).
    3. No false positives: a conforming ROADMAP (plain `[ROUTINE]`/`[HARD — pool]` items) stays a clean zero-exit no-op. These are loud-fail checks (exit-code + stderr), NOT verdicts.
  - **Tests**: `tests/test_roadmap_lint_tagprose.sh` (`# roadmap:297b`) — asserts exit-code + stderr for cases c/d and a clean pass for a conforming ROADMAP. RED until both checks land.
- [x] [ROUTINE] `ckpt-tag.sh` must degrade gracefully when `.gitattributes` is unaddable — a repo that can't track the `merge=union` attr must still get its checkpoint <!-- id:a7a3 -->
  - **Why** (observed 2026-06-30 reviewing `kienzler-homepage`; reverse-handoff of TODO id:a7a3): the repo's `.gitignore` carried a `.*` dotfile catch-all that swallowed `.gitattributes`, so ckpt-tag's `git add -- RELAY_LOG.md .gitattributes` (`relay/scripts/ckpt-tag.sh:55`) exited non-zero and — under `set -euo pipefail` — aborted the WHOLE checkpoint inside the flock: no commit, no tag, and `RELAY_LOG.md` left STAGED as dirty residue. The `RELAY_LOG.md merge=union` attribute is a nicety (it only matters for parallel-relay merge conflicts), NOT essential to a checkpoint; a repo that cannot add it must still get its `RELAY_LOG.md` entry + tag. Manual workaround used that day: `git commit RELAY_LOG.md` + `git tag -a`, plus a `!.gitattributes` negation in kienzler's `.gitignore` — but ckpt-tag itself must not hard-fail.
  - **Acceptance**:
    1. When `.gitattributes` cannot be staged (ignored by `.gitignore`, or any `git add -- .gitattributes` failure), ckpt-tag.sh WARNs to stderr and PROCEEDS — it still commits `RELAY_LOG.md` and produces the annotated `relay-ckpt-*` tag. It exits 0.
    2. The normal path (where `.gitattributes` IS addable) is unchanged: the attr file is created/updated and committed alongside `RELAY_LOG.md` exactly as today.
    3. No `RELAY_LOG.md` staged-but-uncommitted residue is ever left behind, in EITHER path. The commit must stage `RELAY_LOG.md` (and `.gitattributes` only if it staged cleanly) — never abort mid-flock with the log staged.
    4. The flock, the same-minute `-2`/`-3` tag-collision suffixing, and the stdout tag-name contract are all preserved.
  - **Tests**: `tests/test_ckpt_gitattributes_degrade.sh` (`# roadmap:a7a3`) — sets up a repo whose `.gitignore` `.*` catch-all swallows `.gitattributes`, runs ckpt-tag.sh, and asserts exit 0 + a `relay-ckpt-*` tag + the `RELAY_LOG.md` entry committed + no staged residue. RED until the script tolerates the unaddable attr.
  - **Done-check**: `tests/run-tests.sh tests/test_ckpt_gitattributes_degrade.sh`, then tick this checkbox AND the TODO id:a7a3 line, and `make test` must be fully green.
  - **Context**: `relay/scripts/ckpt-tag.sh` (the `git add -- RELAY_LOG.md .gitattributes` at :55 and the `if ! git diff --cached --quiet` commit at :56–59). Likely shape: stage `.gitattributes` in its OWN tolerant `git add` (`|| warn`), then `git add -- RELAY_LOG.md`, then commit whatever is staged. Single-id-two-views: REUSE `<!-- id:a7a3 -->` (already in TODO.md); tick both ledgers when it closes.

- [x] [ROUTINE] Gate `claim.sh` `is_live` worktree-anchor on the run heartbeat — a dead-but-committed run must stop holding its claim forever <!-- id:33d3 --> done: heartbeat_alive_for_run gate in is_live; worktree clause only extends past mtime-TTL when heartbeat.sh status <runId>==alive; dead/absent → mtime-TTL fallback; fail-safe on heartbeat.sh error
  - **Why** (meeting 2026-06-29, `docs/meeting-notes/2026-06-29-1750-dead-but-live-claim-heartbeat-gate.md`; the id:9000 remainder after id:672b): `is_live` (`relay/scripts/claim.sh:124`) currently keeps a claim live when its mtime is fresh **OR** (id:7570) its `--worktree` has commits beyond main **OR** (id:1b11) its `--pid` is alive. The id:7570 `worktree_working` clause (`:89`) is a "has unmerged work" signal, NOT a liveness signal — committed git objects persist after the owning process dies, so a relay child that commits then dies before integration holds its claim **forever** (the truncocraft second-instance class). A parallel `/meeting` or pool then sees a held claim for abandoned work. `heartbeat.sh` (id:e149) already exists as the PURE ts+TTL run-liveness oracle built for exactly this — its header literally documents that the worktree clause "is exactly WRONG for detecting a dead LOOP." `is_live` just doesn't consult it yet. Fix: gate the worktree clause on the run heartbeat so the worktree anchor only EXTENDS liveness past mtime-TTL when a FRESH heartbeat backs it.
  - **Acceptance**:
    1. `is_live`'s `worktree_working` contribution is GATED on the claim's run heartbeat: the worktree clause keeps a claim live ONLY when `heartbeat.sh status <runId>` (the claim's recorded `.runId`) prints `alive`. (D1)
    2. NO-HEARTBEAT (`status` = `absent`) OR `dead` → the worktree clause does NOT extend liveness; the claim falls back to the ORDINARY mtime-TTL (live iff mtime fresh OR `pid_alive`). Net: the id:7570 worktree anchor only extends past mtime-TTL when a fresh heartbeat backs it. (D2)
    3. Reuse `heartbeat.sh`'s own TTL constant — introduce NO new knob/threshold in `claim.sh`. (D2)
    4. `claim.sh` MUST NOT touch the worktree — reclaim/reap free only the RESERVATION; the orphan worktree with its commits is disposed by the existing reconcile (id:a4e9 park / id:7809), never by `claim.sh`. (D3)
    5. Scope = ONLY this `is_live` clause-gate + the heartbeat consult. OUT: bilateral coordination channel (rest of id:9000), auto-integrating orphans, pid-reuse hardening for id:1b11, any new TTL knob. (D4)
    6. A meeting claim (no worktree) and a standalone `--pid` job (no worktree) are unaffected — they never enter the worktree clause. Single-id-two-views: REUSE `<!-- id:33d3 -->` (already in TODO.md); keep both ledgers' checkbox consistent when it closes.
  - **Tests**: `tests/test_relay_claim_liveness.sh` (`# roadmap:7570`, extended) — keep its existing cases; new DETERMINISTIC (stubbed-heartbeat-ts, never wall-clock-compared, per id:16e9) cases assert: (a) worktree-with-commits + FRESH heartbeat for the claim's run → claim LIVE (not stolen); (b) worktree-with-commits + STALE/dead heartbeat → claim RECLAIMABLE (another run's acquire succeeds / reap moves it); (c) worktree-with-commits + ABSENT heartbeat + stale mtime → reclaimable (mtime-TTL fallback); (d) mtime-fresh → live regardless of heartbeat. Fresh = `heartbeat.sh beat <runId>`; stale = write/age `heartbeats/<runId>.json` `ts` deterministically. These new cases are RED until `claim.sh` consults the heartbeat.
  - **Done-check**: `tests/run-tests.sh tests/test_relay_claim_liveness.sh`, then tick this checkbox and `make test` must be fully green.
  - **Context**: `relay/scripts/claim.sh` (`is_live` :124, `worktree_working` :89, `pid_alive` :116, `is_fresh` :74; records `.runId`), `relay/scripts/heartbeat.sh` (`status <runId>` → alive|dead|absent, its own `HEARTBEAT_TTL`). Relates id:e149 (heartbeat oracle), id:7570 (worktree anchor being gated), id:1b11 (`--pid` clause, unaffected), id:a4e9/7809 (orphan reconcile that disposes the worktree), id:9000 (parent; this is its cheapest half), id:672b (the prior shipped half). NOTE: this handoff makes NO edit to `claim.sh` — that is the executor's job.

- [x] [ROUTINE] Structured executor size-out signal — a sized-out `[ROUTINE]` item must hand back so the integrator gates it (stop the re-dispatch spin) <!-- id:08c0 -->
  - **Why** (observed truncocraft, relay-ckpt-20260629-1325 — routed:9a50; manually hard-split there into 9039/d9c1/5f6c): a cheap executor that sizes out a `[ROUTINE]` item as too-large-to-land-green has no handback→gate path. It only has the SOFT notes — a `friction:` commit line (contract rule 4) / a `BLOCKED:` RELAY_LOG line (rule 3). The integrator's durable handback follow-up (`handback-followup.py`, id:3801) reads ONLY the STRUCTURED return fields (`contract_met`/`handback_item`/`route`/`proposed_split`) — it never parses the soft notes. So the sized-out item stays a plain open `[ROUTINE]`; the executor commits a checkpoint with `contract_met=true`, the repo signature changes (defeating the discover cache), and the next discovery round re-dispatches the SAME un-doable item to another executor. The HARD-execute child already has this discipline (relay-loop.js line ~1277, id:8b1f); the `[ROUTINE]` execute child does not.
  - **The integrator GATE already exists and works** — `handback-followup.py`'s `gate_line` re-tags a `[ROUTINE]` parent to the classifier-excluded `[HARD — decision gate]` (`TIER_RE` matches `[ROUTINE]`; proven green by `tests/test_handback_followup.sh` "decision-gate re-tags a [ROUTINE] parent"), and `relay-loop.js` (`handbackFollowup`, ~line 1490) calls it for ANY handback regardless of verdict. The missing half is purely UPSTREAM: the executor must be TOLD to EMIT the structured size-out handback for a `[ROUTINE]` item.
  - **Design (decided in this handoff — NOT a meeting): reuse the existing gate, invent NO new tag.** The routed item floated `[ROUTINE — oversized, needs handoff split]`, but that tag would NOT stop the spin: the dispatch matcher `^- \[ \].*\[ROUTINE\]` (relay-loop.js openRoutine count + gather-repo-state.sh) and the HARD-lane exclude filter `\[HARD — (hands|meeting|decision gate)\]` would BOTH still let a `[ROUTINE — …]` line through. Re-tagging to `[HARD — decision gate]` via the existing id:3801 path is the only thing that actually excludes it from re-dispatch AND surfaces it for a handoff decomposition.
  - **Acceptance**:
    1. `relay/references/executor-contract.md` gains a SIZE-OUT rule: when an executor determines a `[ROUTINE]` item is too large to land green in one session AND cannot be partially advanced toward its green checkbox, it MUST NOT silently leave the item open — it returns the STRUCTURED handback: `contract_met=false`, `handback_item=<id>`, `route=hard-split` (with `proposed_split` seams) or `decision-gate`/`human`, plus a one-line `gate_reason`.
    2. That rule states explicitly that the soft `friction:`/`BLOCKED:` notes are NOT sufficient for this (the integrator's durable follow-up reads only the structured fields), names the re-dispatch spin it prevents, and points at the id:3801 gate so the executor trusts the integrator will durably re-tag the item to `[HARD — decision gate]` + append seams.
    3. The `relay-loop.js` EXECUTE-verdict child prompt (the `unit.verdict === 'execute'` segment, today just "never start an item you cannot finish") wires the size-out → structured-handback path for `[ROUTINE]` items, mirroring the HARD-execute child's id:8b1f discipline (size-out = CLEAN worktree, NO commit, rationale only in the returned `handback`/classification fields).
    4. The contract version is bumped `v5 → v6` (an in-flight executor must learn the new return obligation — contract maintenance rule), and the `## Relay contract <!-- relay-executor contract vN -->` pointer in `CLAUDE.md` is refreshed to match (the SKILL.md note auto-refreshes it, but verify).
    5. No new ROADMAP tag is introduced; the gate stays the existing `[HARD — decision gate]` path.
  - **Tests**: `tests/test_executor_sizeout_signal.sh` (`# roadmap:08c0`) — currently RED. Asserts (a) executor-contract.md documents the structured signal (size-out rule, `contract_met=false`, `handback_item`+route, soft-notes-insufficient rationale, id:3801 pointer), (b) contract version ≥ v6, (c) the relay-loop.js execute-verdict segment covers ROUTINE size-out → handback.
  - **Done-check**: `tests/run-tests.sh tests/test_executor_sizeout_signal.sh`, then tick this checkbox and `make test` must be fully green.
  - **Context**: `relay/references/executor-contract.md` (the lean Sonnet executor contract — the actual doc to edit); `relay/scripts/relay-loop.js` (execute-verdict prompt ~1276, HARD model at ~1277, `handbackFollowup` ~1490, return schema ~1285); `relay/scripts/handback-followup.py` + `tests/test_handback_followup.sh` (the gate, already green — do NOT change it); `CLAUDE.md` §"Relay contract" pointer. Relates id:3801 (durable handback gate), id:8b1f (HARD size-out clean-worktree discipline), id:365b (redispatch circuit breaker — a coarse backstop this makes precise), id:e107 (non-actionable ROUTINE exclusion). Source: shared-inbox routed:9a50 (from truncocraft).

- [x] [ROUTINE] `/meeting` setup-time advisory claim — acquire ONE claim at SETUP for relay-managed repos; release on every exit; inform-and-proceed on an existing claim <!-- id:672b -->
  - **Why** (decided 2026-06-24 meeting D3, `docs/meeting-notes/2026-06-24-1308-meeting-relay-classification-claim-compat.md`; reconciled 2026-06-29 with the just-shipped id:c144): `/meeting` closes the one-sided-lease asymmetry ([[meeting-pool-claim-asymmetry-incident]]) — today the pool claims at dispatch but `/meeting` takes no claim, so a live pool can re-derive off a stale base while a meeting edits the same ledgers. Fix: `/meeting` acquires ONE advisory repo claim at SETUP (the pool already honors claims via `claim.sh peek` → skips the repo for the meeting's duration), released at end. **c144 reconciliation:** id:c144 (shipped 2026-06-29) already REMOVED the old step-2a per-write-back acquire/DEFER and made ledger write-backs peek-and-warn-and-proceed under flock + atomic commit (id:148b `md-merge.py --commit`). So `/meeting` now holds exactly ONE claim (setup→end) and the 2b/2e write-backs happen UNDER that held claim + flock — do NOT re-introduce a second acquire at 2a.
  - **Acceptance**:
    1. In a relay-managed repo (`<root>/ROADMAP.md` exists), `/meeting` acquires an advisory claim at SETUP — `claim.sh acquire <root-basename> --run meeting-<captured session id> --mode meeting` — early in setup (after root resolution, near the existing 2a-replay area), BEFORE the design/decide phase.
    2. The claim is released at the END of the meeting on ALL exit paths (`claim.sh release <root-basename> --run meeting-<captured session id>`), with the claim mtime+TTL as the backstop if a path is missed.
    3. This setup claim REPLACES (does not duplicate) any per-write-back acquire: there is NO second `claim.sh acquire` at step 2a — the 2b/2e write-backs run under the ONE held claim + flock + atomic commit (id:c144/148b).
    4. On an EXISTING claim at setup (a live pool / another session already holds the repo): `/meeting` INFORMS the user and PROCEEDS as a NON-CONFLICTING session — the decide/design phase needs no claim so it proceeds; the ledger WRITE-BACK proceeds via peek-and-warn + flock + atomic commit (per c144/148b). It does NOT abort, and it is NOT worktree-per-meeting (rejected af04).
    5. The id:2c42 deferred-writeback is the flock-TIMEOUT FALLBACK only — NOT the default on a contended claim (this supersedes id:672b's original "write-back deferred+replayed" wording for the normal case, per c144).
    6. Non-relay repos (no `<root>/ROADMAP.md`) behave exactly as before: NO claim is acquired or released.
    7. Single-id-two-views: this item REUSES `<!-- id:672b -->` (already in TODO.md, the design ledger); keep the checkbox consistent across BOTH ledgers when it closes.
  - **Tests**: `tests/test_meeting_setup_claim.sh` (`# roadmap:672b`) — GREEN. Content-assertion against `meeting/SKILL.md`: (a) a setup-time advisory `claim.sh acquire … --mode meeting` gated on `ROADMAP.md`; (b) a release at end-of-meeting on all exit paths; (c) the existing-claim non-conflicting path (inform user + proceed; NOT abort, NOT worktree-per-meeting); (d) the c144 reconciliation (write-back proceeds under flock/peek-and-warn; id:2c42 = flock-timeout fallback); (e) non-relay repos unaffected.
  - **Done-check**: `tests/run-tests.sh tests/test_meeting_setup_claim.sh`, then tick this checkbox and `make test` must be fully green.
  - **Done 2026-06-29** (executor, Sonnet): added `2-setup-claim` step to `meeting/SKILL.md` Setup section documenting the advisory claim acquisition at setup, release on all exit paths, existing-claim non-conflicting path, TTL backstop, c144 reconciliation, and non-relay-repo no-op. Full suite green (122 passed, 0 failed). Ticked id:672b in ROADMAP.md + TODO.md (single-id-two-views).
  - **Context**: `meeting/SKILL.md` (Setup steps; the 2a peek-and-warn block, the 2a-replay block ~line 124, and the 2b/2e write-backs) — the executor edits SKILL.md; `relay/scripts/claim.sh` (acquire/release/peek interface, `--mode meeting`); relates id:c144 (peek-and-warn write-back, supersedes the d748 DEFER), id:148b (atomic scoped commit), id:2c42 (deferred-writeback = flock-timeout fallback), id:d748 (the removed lease hold), id:9000 (this is its cheapest half; richer notify-channel deferred), id:3536 (surface the claim in the cockpit, gated on this). NOTE: this handoff makes NO edit to SKILL.md — that is the executor's job.

- [x] [ROUTINE] Relay host-awareness — host-bound verification gate for multi-host config monorepos <!-- id:43b9 -->
  - **Why** (zomni meeting 2026-06-26, `consolidate-device-repos-monorepo` D7): the planned `it-infra` monorepo (`hosts/<hostname>/` + `shared/`) holds work items whose definition-of-done is HOST-BOUND — you cannot validate fievel's apt path or zomni's touchscreen udev rule on the wrong machine. *Editing* a config file is host-agnostic (any host writes it); only the `make install`/test VERIFICATION is host-bound. The relay had no notion of "this item belongs to host X", so an executor/reviewer on the wrong host would either run install/tests against a foreign config or falsely credit a green it never ran.
  - **Acceptance**:
    1. A ROADMAP item carries an OPTIONAL `[host:<name>]` tag (`[host:zomni]`/`[host:fievel]`/`[host:any]`); untagged ⇒ `host:any` ⇒ host-agnostic (verify anywhere).
    2. `relay/scripts/host-gate.sh '<item line>'` parses the tag vs the current `hostname` (override `RELAY_HOSTNAME`): exit 0 PROCEED (tag absent / `any` / matches), exit 3 DEFER (names a different host; prints `defer: needs host:<X> (current: <Y>)`), exit 2 misuse. Case-insensitive; reads text from `$1` or stdin.
    3. Editing stays host-agnostic; ONLY the verification step gates. On mismatch the conservative default is DEFER with a `needs host:<X>` note — NOT ssh-to-host execution (documented future option only).
    4. Enforced (not just documented): executor done-check (contract rule 2) and reviewer re-derivation (review §2c) consult the gate before verifying; SKILL.md `executor` section documents it; script registered in the Makefile manifest.
  - **Spec / test**: `tests/test_host_gate.sh` (`# roadmap:43b9`) — matching/mismatched/any/untagged/case-insensitive/stdin/misuse. Green.
  - **Done 2026-06-26** (strong turn, free-implemented — design fully decided by the meeting, bounded, no executor in loop): added `relay/scripts/host-gate.sh` + test (green); wired the gate into `references/executor-contract.md` rule 2 (DEFER on exit 3, leave checkbox unticked, append `DEFERRED: <id> needs host:<X>` to RELAY_LOG) + the item-format reference; `references/review.md` §2c (treat host-bound tests as unverified on a mismatched host, keep item open, never `contract_met` on unrun verification); `SKILL.md` executor section; bumped the executor contract v4→v5 (rule 2 gained a clause) across executor-contract.md / conventions.md / this repo's CLAUDE.md pointer (external managed repos auto-refresh on their next review §4); registered `host-gate.sh` in `relay_FILES`/`_EXEC`/`_ALLOW`/`_LOCAL`. The actual it-infra migration + ssh-to-host verification are out of scope (separate gated sessions). Resolves inbox `routed:ffe4`.
- [x] [ROUTINE] TODO/inbox conformance grammar — flag (and safely auto-fix) every non-conforming ledger entry so nothing slips through relay routing <!-- id:3441 -->
  - **Why** (user directive 2026-06-25, escalated twice): `/relay` is only reliable if NO work hides in a malformed ledger line. `roadmap-lint.sh` already enforces a positive grammar on open ROADMAP items, but `TODO.md` has NO grammar lint — a scan of THIS repo found a bare `placeholder` line (252) and a checkbox-less pointer bullet (185) that no tool sees; the shared inbox has ~12 token-less prose blocks. **At least one of handoff/review/human MUST notify of every non-conforming entry** (everything that is not a header, an HTML comment, or a well-formed `- [ ]/[x]` list item + id tag), and **auto-fix where applicable, NEVER block work that shouldn't be blocked** (user: "autofix instead if applicable … never block work that shouldn't be blocked").
  - **Acceptance**:
    1. `relay/scripts/todo-conformance.sh [--fix] [--inbox] [<path>]` — a POSITIVE grammar (mirrors `roadmap-lint.sh`). TODO mode (default): a top-level (non-indented) non-blank line is CONFORMING iff it is a markdown header, an HTML-comment-only line, OR a well-formed `- [ ]/[x]` item; an OPEN `- [ ]` item must additionally carry `<!-- id:XXXX -->` (4-hex). Indented continuation lines are NEVER linted (like roadmap-lint). EXEMPT: a line bearing `<!-- lint-ok: <reason> -->` or an intentional pointer `<!-- ref:XXXX -->`. Output `<class>\t<lineno>\t<text>` (`missing-id` = auto-fixable; `orphan` = surface-only). `--inbox` swaps in the inbox grammar (checkbox + `[target]` + `routed:XXXX`). Report-only (exit 0 with findings); `--strict` → nonzero. LOUD on unreadable path, no silent `2>/dev/null` swallow (id:415b/4e14).
    2. `--fix` AUTO-FIXES only the unambiguously-safe class: an open `- [ ]` item that is well-formed but missing an id → mint via `append.sh new-id` and append `<!-- id:XXXX -->` (flock'd, in place). It MUST NOT touch `orphan` lines (bare prose / checkbox-less bullets — intent unknowable; converting them would fabricate tasks). Prints what it fixed + what it surfaced.
    3. Wired into `relay-doctor.sh`, `/relay review` (→ REVIEW_ME box, never a hard block), `/relay human` (triage list), and handoff C2. **Never blocks** a routine/review/handoff turn — surfaces + auto-fixes, exit stays 0 (the `--strict` gate is opt-in only).
  - **Spec / red test**: `tests/test_todo_conformance.sh` (`# roadmap:3441`) — hermetic fixtures: (a) a clean TODO (headers + well-formed id'd items) → no findings; (b) an open item missing an id → `missing-id`, and `--fix` appends a minted id (re-lint clean); (c) a bare prose line + a checkbox-less bullet → `orphan`, and `--fix` leaves them UNTOUCHED (surfaced, never fabricated); (d) a `<!-- lint-ok -->` / `<!-- ref:XXXX -->` line → exempt; (e) `--inbox` flags a token-less inbox prose block but passes a conforming routed line. RED until the script + wiring land.
  - **Done-check**: tick + `make test` green; dogfood on this repo's TODO (auto-fix any missing-id; resolve the `placeholder`/pointer lines); relay-doctor shows the new check.
  - **Context**: `relay/scripts/roadmap-lint.sh` (the ROADMAP-side sibling — same positive-grammar pattern), `relay/scripts/unpromoted-scan.sh` (id:2dea — overlaps on the missing-id class), `meeting/append.sh new-id` (the mint path for --fix). Inbox AUTO-RECONCILE on cross-repo activity is the sibling id:678e. Deps: none.
- [x] [ROUTINE] Inbox auto-reconcile SLICE-2 auto-write — `scan-routed.sh --apply` (class-A idempotent INBOUND stub keyed on routed:XXXX/id-twin; resolve-by-EXISTENCE not relay.toml membership; claim.sh-peek skip; own commit-ledger.sh commit; mandatory --dry-run) on cross-repo sweeps (respect --exclude); folds id:3947; slice-1 detection SHIPPED <!-- id:678e -->
  - **Why** (user directive 2026-06-25): the shared cross-project inbox (`~/.claude/todo-inbox.md`) strands work — routed items whose target repo never ingested them + token-less prose entries no tool resolves (live: 12 + ~12 for this repo alone). User wants this handled **"more or less automatically on any cross-repo `/relay` or `/meeting` activity, but respecting relay's `--exclude` switch"** — i.e. not a passive surface but an active reconcile pass folded into the cross-repo sweeps, auto-fixing where applicable and surfacing the rest, never blocking.
  - **Why [HARD — meeting]**: genuine design judgment + irreversible auto-mutation of MULTIPLE PRIVATE repos. Open Qs: (a) what is unambiguously auto-fixable (a `routed:XXXX` with a clear `[target]` → append an `[INBOUND routed:XXXX]` stub into the target's TODO via flock'd `md-merge.py`; vs a token-less `<repo>:` prose block → mint a routed id only if the target parses, else surface); (b) the exact integration points (the autonomous pool / `/relay --all` / `/relay human --all` / `/meeting --cross`) and how each honors `--exclude`/`relay.toml paused`; (c) public/private coupling — the PUBLIC dotclaude-skills scripts must take the inbox path by injection, never hardcode the local file; (d) idempotency + the parallel-session claim (don't auto-file into a repo a pool worktree holds — cf. claim.sh / [[meeting-pool-claim-asymmetry-incident]]). Builds on id:3441's `--inbox` grammar (detection) and the id:3947 `scan-routed.sh` dead-letter proposal. Surfacing is cheap and ships with id:3441; the AUTO-FILE/auto-migrate mutation is the [HARD] part gated here.
  - **DECIDED 2026-06-25** (`docs/meeting-notes/2026-06-25-2335-inbox-auto-reconcile-cross-repo.md`): **detection-first, two slices.** SLICE 1 (build now) = `relay/scripts/scan-routed.sh`: report-only dead-letter detector (a conforming `routed:` item absent from its `[target]` repo's TODO+ROADMAP) + inbox-conformance (reuse `todo-conformance.sh --inbox`), printing the READY-TO-RUN file command; `RELAY_INBOX` default `~/.claude/todo-inbox.md`; once-per-sweep; honor `paused`/`--exclude`; wired into relay-doctor + /relay human + /meeting --cross + pool prelude. SLICE 2 (this item stays open for it) = auto-file the reversible additive INBOUND stub for **class A** (conforming token + resolvable target, incl. polyrepo `# path:`), gated on `claim.sh peek` skip + `routed:` idempotency. **Class B** (token-less prose / unresolvable target) = forever surface-only, never guessed. Reverses id:b30b's "no auto-write" ONLY at the slice-2 additive-stub boundary (re-justified: surface-only failed — 12 stranded items; the stub is additive/idempotent/reversible/claim-guarded, not a silent clobber).
  - **DECIDED 2026-06-29** (`docs/meeting-notes/2026-06-29-1116-inbox-reconcile-slice2-gate-open.md`): **slice-2 gate OPENED → re-tagged `[ROUTINE]`.** The slice-1 dogfood this session (4 class-A dead-letters hand-routed via scan-routed's emitted commands, zero resolution error) satisfies the "proven target-resolution" precondition. Slice-2 = `scan-routed.sh --apply`: class-A reversible INBOUND stub only, idempotent on `routed:XXXX` (grep target TODO for the routed token OR its minted `id:` twin before writing — survives promotion), `claim.sh peek` skip for relay-managed targets, own `commit-ledger.sh` commit (clean tree, never `git add -A`), **mandatory `--dry-run`/diff**. **Resolution axis revised (user): repo-EXISTENCE, not relay.toml membership** — TODO *routing* ≠ relay *management*; resolve `[target]` to a repo path (discover-repos.sh `own` + relay.toml `# path:` polyrepo central-ledger, b257; an own repo with no relay.toml block still resolves) and write into ITS TODO with NO onboarding; only a target matching no repo on disk is UNRESOLVED→class-B surface. The open Qs (a)-(d) above are resolved. **Out of scope:** auto-onboarding any repo; class-B auto-parse; the emit-time per-routed stub (id:3947 proposal-1, separate future item). Red-test cases: polyrepo→central TODO, non-relay-own→its TODO, nonexistent→UNRESOLVED, idempotent re-run=no-op, `--dry-run`=no write+diff.
  - **Spec / red test**: `tests/test_scan_routed.sh` (`# roadmap:678e`) covers slice 1 (dead-letter / clean-twin / token-less-prose / `--exclude` / misuse). Slice-2 auto-write spec follows once slice 1 + target-resolution land.
  - **Direction (user 2026-06-25)**: global `CLAUDE.md` now documents the inbox lifecycle
    (write via `append.sh -t inbox`, resolve via `inbox-done`, lint via `todo-conformance.sh
    --inbox`, reconcile on cross-repo activity respecting `--exclude`) — the doc half is DONE.
    The mechanized half MECHANIZES by extending the EXISTING small tools — `append.sh` inbox
    subcommands + `todo-conformance.sh --inbox` (detection, shipped) + a new `scan-routed.sh`
    dead-letter pass — NOT by adapting `claim.sh` (that is a repo *lease* / mutual-exclusion
    primitive, not a dead-letter router; the only claim relevance is the idempotency guard in
    open-Q (d): don't auto-file into a repo a pool worktree currently holds).
  - **Context**: id:3947 (this absorbs it), id:3441 (detection substrate), `relay/scripts/discover-repos.sh` + the `--exclude`/`paused` plumbing, `meeting/append.sh -t inbox`, [[meeting-relay-classification-claim-compat-2026-06-24]] (manual pool↔meeting coordination = `--exclude meeting-repo`).
  - **Why** (LIVE evidence 2026-06-25, truncocraft): `/relay next`/`review`/handoff decide "is there work?" from OPEN ROADMAP items + unaudited commits ONLY. truncocraft's ROADMAP was fully `[x]`-closed while `TODO.md` held FIVE open executable items (`b1e4` removal ghost, `a7d2`/`c3f7` HARD-pool, `a03c` HARD-meeting, plus the favicon redo) — so every prior `/relay` run read the repo as DRAINED and the apex turn even reported "handoff would be a no-op." The whole job of handoff C2 is to PROMOTE TODO→ROADMAP, but nothing detects the un-promoted backlog, so it sat idle for days. This is the **second instance** (id:78ff was the first: a `[HARD — pool]` filed TODO-only the pool couldn't see).
  - **Gap vs the existing d9b0 promotion-tracking note** (ROADMAP.md line ~142, under the *closed* `d9b0`): that check only flags a TODO item *already carrying* an executable lane (`[ROUTINE]`/`[HARD — pool]`) whose `id:` lacks a ROADMAP twin. truncocraft's stranded items carried **NO lane tag at all** in TODO (raw backlog prose) → they slip past that check entirely. d9b0 was ticked `[x]` but this sub-point never actually shipped as a routing-visible signal. Re-open it here with the broader, evidenced scope.
  - **Acceptance**:
    1. A mechanical check (extend `meeting/orphan-scan.sh` or a new `relay/scripts/unpromoted-scan.sh`) that lists every OPEN `TODO.md` `- [ ]` item whose `<!-- id:XXXX -->` has NO twin line in that repo's `ROADMAP.md` — **regardless of whether the TODO line carries a lane tag** (the gap that bit truncocraft). Output: `<repo>\t<id>\t<title>` TSV, report-only. Honor `# path:` overrides; LOUD on unreadable repo (no silent `2>/dev/null` swallow, per id:415b).
    2. Wire the count into `/relay next` + the `/relay review` + `relay-doctor.sh` (id:9bec) report so a closed-ROADMAP-but-open-TODO repo surfaces "N un-promoted TODO items — needs a handoff pass" INSTEAD of "drained / nothing to do." `/relay next`'s route-1/2/3 ladder gains a pre-check: open un-promoted TODO ids ⇒ route to **handoff** (promotion), not "human/idle."
    3. Distinguish genuinely-not-yet-actionable backlog (meeting topics, blocked-on-dep) from promotable executable work — when the lane is ambiguous (untagged), SURFACE for the strong turn to triage (handoff C2), never auto-promote with a guessed lane.
  - **Spec / red test**: `tests/test_unpromoted_scan.sh` (`# roadmap:2dea`) — hermetic: a fixture repo with (a) a closed ROADMAP + an open untagged TODO id with no twin → reported; (b) an open TODO id WITH a ROADMAP twin → clean; (c) a meeting-lane/blocked TODO → reported as "surface, not auto-promote". RED until the scanner + wiring land.
  - **Done-check**: tick + `make test` green; dogfood `relay-doctor.sh --all` shows the new line; a `/relay next` on a closed-ROADMAP/open-TODO repo routes to handoff.
  - **Context**: `meeting/orphan-scan.sh` (cross-ledger sibling), `relay/scripts/relay-doctor.sh` (id:9bec), `relay/SKILL.md` `## Next mode` (the route ladder), the d9b0 design note (ROADMAP ~142.1). Relates to id:2840 (derived ledger index models one-id-two-scope-rows natively — the eventual durable home) + id:3947 (cross-repo dead-letter routing, sibling class). Deps: none to start. **Filed as a ROADMAP item, not TODO-only — that IS the lesson.**

- [x] [ROUTINE] `relay-doctor.sh` — report-only relay-machinery health aggregator (cheap-first-slice of id:0907) <!-- id:9bec -->
  - **Why**: aggregates the already-built mechanical checks into one report so latent relay-plumbing defects don't depend on a human noticing (the 2026-06-23 six-defect session). Decided 2026-06-24 (`docs/meeting-notes/2026-06-24-1631-relay-doctor-scope.md`); its gate (id:09a3/69ef/000d) is met.
  - **Acceptance**: `relay/scripts/relay-doctor.sh` CALLS (never reimplements) orphan-scan.sh --cross-ledger, roadmap-lint.sh, the id:69ef refs-install check, relay-reconcile.sh --all; scope = cwd-default / `<dir>` / `--all` (relay.toml own); REPORT-ONLY (exit 0 with findings, only misuse exits nonzero); LISTS not-yet-wired checks (id:e149 claim-staleness, id:c3a6 discover-sig) for honest coverage (D4). `tests/test_relay_demote_guard_hard_pool.sh`… → `tests/test_relay_doctor.sh` (`# roadmap:9bec`) green; full suite green. (Dogfood: on first run it caught a real id:9973 TODO↔ROADMAP drift, now fixed.)
- [x] [ROUTINE] relay-doctor front-door wiring — `/relay health` mode + a `/relay review` sub-step surfacing findings to REVIEW_ME (never a hard block); child of id:0907 (D1), DEP id:9bec <!-- id:3eb5 -->
- [x] [ROUTINE] relay-doctor `--strict` (opt-in nonzero gate) + quota-config sanity check (RELAY_QUOTA_DECAY_7D direction, threshold bounds); child of id:0907 (D3/D4), DEP id:9bec <!-- id:a883 -->
- [x] [ROUTINE] Fix `orphan-scan.sh --cross-ledger` false-positive — it must correlate ONLY the line bearing `<!-- id:XXXX -->` (exact token), not a prose/substring match <!-- id:9221 -->
  - **Why**: dogfooding `relay-doctor.sh --all` (id:9bec) surfaced `id:f4a7 — TODO:[x] ROADMAP:[ ]` in isochrone, but f4a7's token line is `- [ ]` in BOTH ledgers (id also appears in prose on 3 `f4a7-A/B/C` child lines, all `[ ]`); `id:601e` in the same repo is reported correctly. So the cross-ledger check mis-attributes a checkbox to an id whose own token line agrees. This is the interim drift backstop id:2840 relies on + a relay-doctor input — phantom drift erodes trust in both.
  - **Acceptance**: hermetic test — (a) id whose `<!-- id:XXXX -->` lines AGREE but whose id is mentioned in prose on other (differently-checkboxed or same) lines → reported CLEAN; (b) genuine token-line disagreement → reported DRIFT. orphan-scan keys strictly on the token-bearing line.
  - **Done-check**: tick + `make test` green.
- [x] [HARD — pool] Workflow-script template-literal lint — catch unescaped backticks inside template literals before they reach the live Workflow parser (and fix any existing) (done 2026-06-24, relay HARD child id:da26) <!-- id:71f2 -->
  - **Why** (observed 2026-06-24): the id:9973 demote-guard edit added backtick-wrapped `` `hard` `` twice inside `relay-loop.js`'s `shardPrompt` template literal WITHOUT escaping the backticks (lines 763, 822). `node --check` AND `make test` both TOLERATED it, but the Workflow tool's stricter template-literal parser rejected the entire script (`Unexpected token (763:1527)`), so `/relay --afk` could not launch the pool at all (fixed ad-hoc in commit 178b8db). The lesson: `node --check` is NOT a sufficient gate — the live engine crashed on a script `node` accepts. [HARD — pool] because a robust check is parser/lexer-aware (a naive `grep` for backticks false-positives on `//` comments and the already-escaped `` \` `` cases), and it guards the relay engine's own CI surface.
  - **Acceptance**:
    1. A check (`relay/scripts/lint-workflow-templates.{sh,mjs}`) that, for every workflow JS script (`relay/scripts/relay-loop.js` plus any script containing `export const meta` / future `*.workflow.js`), detects a backtick INSIDE a template literal that is neither escaped (`` \` ``) nor the literal's own delimiter — via a real lexer pass that distinguishes template-literal context from `//` + `/* */` comments and ordinary `'`/`"` strings (NOT a line grep). It FAILS loudly (nonzero exit + offending `file:line`) on a violation.
    2. Wired into `make test` via `tests/test_workflow_template_lint.sh` so the suite goes RED on any reintroduction.
    3. Run against the current tree; fix any existing violation (none expected post-178b8db — verify). The cosmetic `` \`hard\` `` the ad-hoc fix left in a `//` comment at `relay-loop.js:419` is exempt (comments are not template literals) — the linter must NOT flag it.
  - **Spec / red test**: `tests/test_workflow_template_lint.sh` (`# roadmap:71f2`) — hermetic: a fixture script with an unescaped backtick inside a template literal → linter exits nonzero naming the line; a fixture with only escaped backticks + backticks inside comments/strings → exits zero. RED until the linter lands.
  - **Done 2026-06-24** (relay HARD child, id:da26): new `relay/scripts/lint-workflow-templates.mjs` — a single-pass CHARACTER LEXER (stdlib node, no deps) that tracks JS context (code / line-comment / block-comment / `'…'` / `"…"` / `` `…` `` template with `${…}` substitution nesting, AND regex literals `/…/` so a `/'/g` quote can't desync the string lexer) and flags ONLY an unescaped backtick that, in template-literal content, is immediately followed by an identifier char (`[A-Za-z0-9_$]`) — the `` `hard`` desync signature. Escaped `` \` ``, backticks in comments/strings, and `${…}` interpolation are all in the wrong lexer state and never reach the rule (the false-positive class a line grep can't avoid). Reproduced the original defect: ran against commit 178b8db^'s relay-loop.js → flags exactly lines 763 + 822 (`node --check` passed on that same file); current tree lints CLEAN. Targets `relay-loop.js` + any `relay/scripts/*.{js,mjs}` containing `export const meta` or named `*.workflow.js`; usage `lint-workflow-templates.mjs [file|repo-root …]`, exit 0 clean / 1 violation (`file:line:col`) / 2 misuse. Added to `relay_FILES`/`relay_EXEC`/`relay_ALLOW`/`relay_LOCAL` (id:69ef install-completeness). Spec `tests/test_workflow_template_lint.sh` (`# roadmap:71f2`) green; full suite green. The cosmetic `` \`hard\` `` in the `relay-loop.js:419` comment is correctly NOT flagged (comment state). Follow-up (not blocking): the linter is not yet wired into `make test` as a standalone target nor into `relay-doctor.sh` — the test invokes it directly; a `/relay review` wiring step can fold it into the health aggregator (id:0907 family).
- [x] [HARD — pool] `/relay stop` — first-class graceful (patient) operator wind-down for a running pool (no orphaning) <!-- id:c012 -->
  - **Why**: the self-feeding loop ended only on quota cap / 2 dry discoveries / `MAX_ROUNDS`, or a hard `TaskStop` that kills in-flight children + parks worktrees as `relay/orphan/*`. No VOLUNTARY "finish the current batch, don't re-discover, stop clean" signal existed (observed 2026-06-22 + 2026-06-24). Merged former id:3b1e (patient stop / `--once`) into this id. [HARD — pool] because it edits `relay-loop.js`'s live Workflow engine — the class the pool crashed on 3× (id:e37b).
  - **Acceptance**: (1) STOP sentinel at `STOP_PATH` (`~/.config/relay/STOP`, override `args.STOP_PATH`/`RELAY_STOP_PATH`) checked by the `discover-prelude` (the only actor with shell/FS each round) — content = integer "rounds remaining before stop" (empty/≤0 = stop now; `--after N` = N), prelude decrements N→N-1 and **consumes (rm)** on fire, returning `stopRequested` (added to `PRELUDE_SCHEMA`). (2) `runRound` short-circuits on `prelude.stopRequested === true` (strict, fail-safe — a dead prelude never stops): sets `stopReason='user-stop'`, returns a `userStop` marker WITHOUT dispatching a new wave (prior wave + integration debt already drained). (3) Outer loop breaks on `r.userStop` AND on the launch-time round cap `STOP_AFTER_ROUNDS` (`--once` = 1, `--after N` = N), both → `stopReason='user-stop'`. (4) `buildStopReasonLine` glosses `user-stop`. (5) SKILL.md `## Stop mode` documents `/relay stop`, `/relay stop --after N`, `/relay stop --now` (hard `TaskStop` path), `--once`, and the knobs table rows.
  - **Spec / red test**: `tests/test_relay_graceful_stop.sh` (`# roadmap:c012`) — static-structural over `relay-loop.js` + `SKILL.md` (the pool can't exercise the live Workflow), plus `node --check` and the Workflow-forbidden-API guard. Green.
  - **Done-check**: tick this checkbox, then `make test` fully green.
- [x] [ROUTINE] First-class per-run `--priority` / `--exclude` pool args — no relay.toml mutation, no `inject.sh` abuse <!-- id:d530 -->
  - **Acceptance**: `relay-loop.js` reads `args.excludeRepos` / `args.priorityRepos`. EXCLUDE drops those repos from the own-repo list BEFORE sharding (no unit emitted) + adds each to the `skipped` rollup `excluded for this run (--exclude)`; no relay.toml write. PRIORITY is a per-run ORDERING bump in the unit sort comparators — ahead of non-priority units WITHIN the same verdict class, above `income`, below injected-unit precedence + the D3 verdict-class order (never a verdict override, never a created/injected unit → can't double-dispatch, the id:d530 finding). Unknown/unconfirmed repo names are a LOUD reject (surfaced), never silent. Logic factored into the PURE helper `relay/scripts/pool-args.mjs` (byte-equivalent inline copies in `relay-loop.js`, pinned by a structural test, per the `redispatch-guard.mjs` precedent). SKILL.md front door documents both flags (run-scoped, never write relay.toml) + maps the natural-language forms onto `args.priorityRepos`/`args.excludeRepos`. `tests/test_relay_pool_args.sh` (`# roadmap:d530`) green; full suite green.
- [x] [ROUTINE] Deterministic `is_finished` guard — stop the classifier false-dispatching handoff/hard on finished repos <!-- id:000d -->
  - **Why** (incident 2026-06-23, run relay-20260623-083216): with the quota false-stop fixed (id:1d64) the pool ran longer and reached the lowest-priority `handoff` tier, where the LLM shard emitted `handoff`/`hard` verdicts for FINISHED repos (recurheb/echoAI/collaib — ROADMAP all `[x]`, 0 open items, clean tree, no unaudited commits). Children correctly no-op + auto-reap, but each burns a strong/opus dispatch; left unchecked it churns across rounds. **CONFIRMED not a discover-sig bug** (it hashes full ROADMAP content — checkbox flips invalidate correctly) and not a gather-state bug (it strips done `[x]` blocks). The shard over-applies `handoff` (whose definition requires "untracked new work exists") to a repo that should classify `idle`. Mechanize the judgment (id:415b: guard arguable LLM judgment with a deterministic check).
  - **Acceptance**:
    1. `relay/scripts/gather-repo-state.sh` emits a new bool field **`is_finished`** = `roadmap` is present/non-empty AND has ZERO open `- [ ]` items (after the existing open-item trim) AND `commits_since_ckpt` is empty AND `dirty` is false (the existing `dirty_lock_only` exemption still counts as not-finished-blocking → treat lock-only dirty as clean for this flag). A repo with NO roadmap stays `is_finished=false` (genuine first `handoff`). Add it through the existing `emit()` positional→env→JSON path.
    2. `relay/scripts/relay-loop.js` classifier consumes it as a **demote-only guard**: when `is_finished` is true, the repo is NEVER a `units` entry of verdict execute/hard/handoff — it goes to `surfaced` with reason `finished repo (0 open items, clean, no unaudited commits) — not dispatched (anti-false-handoff guard id:000d)`. The guard may only DEMOTE to idle/surfaced, never invent work; `review` is unaffected (review requires commits_since_ckpt, which makes is_finished false anyway).
  - **Spec / red test**: `tests/test_gather_is_finished.sh` (`# roadmap:000d`) — hermetic, reuses the shard-canary fixtures: idle→is_finished true; review/dirty/hard-gated/non-git→false. RED until gather emits the field. Also add a structural assertion to `tests/test_relay_loop_structure.sh` that the is_finished demote-guard is present in relay-loop.js.
  - **Done-check**: tick this checkbox, then `make test` fully green.
- [x] [ROUTINE] Deterministic HARD-pool demote-guard — stop the shard false-dispatching `hard` on a repo with NO open `[HARD — pool]` item <!-- id:9973 -->
  - **Why** (observed 2026-06-24): the discover-shard's `hard` verdict is an LLM judgment of whether an executable `[HARD — pool]` item exists, but only `[HARD — pool]` items are pool-dispatchable (`relay/references/hard-lanes.md`) — `[HARD — meeting]`/`[HARD — decision gate]`/`[HARD — hands]` are NOT. The judgment is non-deterministic: two repos whose only open HARD item was `[HARD — decision gate]` were wrongly classified `hard` and handed back as pre-start size-outs (burning Opus), though an earlier run that session correctly surfaced them as gated. Mechanize the judgment (id:415b) with a deterministic check, mirroring the id:000d `is_finished` guard.
  - **Acceptance**:
    1. `relay/scripts/gather-repo-state.sh` emits a new number field **`open_hard_pool`** = the count of open `- [ ]` ROADMAP items whose lane tag is exactly `[HARD — pool]`, EXCLUDING a `<!-- relay:recurring-audit -->`-marked item that has nothing to audit this round (reuse the id:365b `substantive_unaudited` logic — a vacuous recurring audit is not an executable pool item). Added through the existing `emit()` positional→env→JSON path. A repo with no roadmap / no pool-lane item stays `open_hard_pool=0`.
    2. `relay/scripts/relay-loop.js` consumes it as a **demote-only guard** (after the shard merge, alongside the id:000d guard): when a unit's verdict is `hard` and that repo's `open_hard_pool == 0`, DEMOTE it — remove from `units`, push to `surfaced` with reason `HARD backlog is gated — no open [HARD — pool] item (only meeting/hands/decision-gate lanes); not dispatched (deterministic demote-guard id:9973)`. DEMOTE-ONLY (only toward surfaced); injected units (`unit.injected`) are EXEMPT; `review`/`execute`/`handoff` untouched. The value reaches the unit via the DISCOVER_SCHEMA field + a shard-prompt copy-verbatim instruction (same wiring discipline as id:401c's is_finished fix).
  - **Workflow-sandbox constraint**: the JS guard is pure logic over already-gathered data — no `Date`/`process`/`require`/`fs`/`Math.random` (they crash the pool); `node --check` + `tests/test_relay_no_date_api.sh` stay green.
  - **Spec / red test**: `tests/test_relay_demote_guard_hard_pool.sh` (`# roadmap:9973`) — hermetic, static-structural: (a) gather emits `open_hard_pool` counting ONLY open `[HARD — pool]` items (decision-gate+hands→0; one pool→1; done [x]→0; vacuous recurring-audit→0); (b) relay-loop.js has the demote-guard wiring (hard + open_hard_pool==0 → surfaced, injected-exempt, demote-only). RED until both halves land.
  - **Done-check**: tick this checkbox, then `make test` fully green.
- [x] Relay: decouple --afk from intensive — --afk stays non-intensive, --intensive opts in (implies --afk) [ROUTINE] <!-- id:052c -->
  - **Why** (user 2026-06-23): auto-running OOM-risky `[INTENSIVE]` work *because* the user stepped away is backwards ([[oom-local-model-session-kills]]). `--afk` = unattended but SAFE; `--intensive` (synonym `--allow-intensive`) is the explicit opt-in and IMPLIES `--afk`.
  - **Acceptance**: `relay-loop.js` `ALLOW_INTENSIVE = !!A.allowIntensive` (no longer `|| A.afk`); the front door sets `args.allowIntensive` ONLY for `--intensive`/`--allow-intensive`, never a bare `--afk`; SKILL.md splits the two knob rows; skip messages say "needs --intensive"; `tests/test_relay_intensive.sh` asserts the decoupling. Suite green.
- [x] Relay intensive-emit human-gate carve-out — don't auto-dispatch a human-gated [INTENSIVE] item [ROUTINE] <!-- id:a707 -->
  - **Why** (incident 2026-06-23): with `--afk`, the id:ad74 INTENSIVE-EMIT-GUARD force-emitted a zomni `[HARD — hands] [INTENSIVE — local-llm]` GGUF-cleanup unit; it was dispatched but un-doable (needs live GPU/sudo) — [INTENSIVE] is an orthogonal resource axis (id:78ff), not an executor-eligibility override.
  - **Acceptance**: `gather-repo-state.sh` `top_intensive` is the resource of the top open [INTENSIVE] item that is NOT human-gated (`[HARD — hands]`/`[HARD — meeting]`/`[HARD — decision gate]`/`@manual`), "" when the only open [INTENSIVE] items are human-gated; the shard INTENSIVE-EMIT-GUARD prose carries the carve-out; `tests/test_intensive_human_gate.sh` green.
- [x] Relay anti-spin: recurring-audit gate + re-dispatch circuit breaker [ROUTINE] <!-- id:365b -->
  - **Why** (incident 2026-06-23, run relay-20260623-172446): the recurring strong-model audit (id:401c) never closes by design; once dotclaude-skills drained all other work it became the only open pool-dispatchable item, so the `hard` verdict re-selected it EVERY round, auditing only its own prior `relay: checkpoint` commit ("clean by vacuity") — ~13 vacuous rounds drove the 5h quota 98%→41% for zero output (the checkpoint churn also defeated the discover-sig cache). See TODO id:365b.
  - **Acceptance**: (1) `gather-repo-state.sh` emits `substantive_unaudited` (bool, FAIL-OPEN true — false iff every commit since the audit ref `last_strong_ckpt`/latest ckpt is a `relay:/fable: checkpoint` or uv.lock-only) and `work_sig` (string, stable across the pool's own checkpoint churn, changes when an item closes or a substantive commit lands). (2) Mechanism 1: id:401c carries a `<!-- relay:recurring-audit -->` marker; the discover-shard EXECUTABLE-HARD test excludes a marked item from `hard`/`openHard` when `substantive_unaudited` is false, surfacing "recurring audit idle …". (3) Mechanism 2: a deterministic JS circuit breaker (`redispatchGuard` + the pure helper `redispatch-guard.mjs`) suppresses any non-injected (repo,verdict) unit dispatched >3× in one run with an unchanged `work_sig`; injected units exempt; resets on a work_sig change.
  - **Spec / red tests**: `tests/test_recurring_audit_gate.sh` + `tests/test_redispatch_circuit_breaker.sh` (both `# roadmap:365b`). RED until implemented.
  - **Done-check**: tick this checkbox, then `make test` fully green.
- [x] [ROUTINE] Margin-aware quota-stop staleness — stop false-stopping a healthy pool when the cache is stale + unrefreshable <!-- id:1d64 --> (done 2026-06-23, executor)
  - **Why** (incident 2026-06-23, run relay-20260623-070136): the pool stopped with `stopReason=quota-stale-cache` at five_hour=**7%** / seven_day=**38%** / seven_day_sonnet=**25%** vs a 90% threshold — huge headroom. `quota-stop.sh`'s staleness fail-safe is MARGIN-BLIND: when the cache is older than `STALE_SECS` and the self-refresh fails (the `/api/oauth/usage` endpoint 429s aggressively — documented statusline gotcha; nothing keeps the cache fresh during an unattended `--afk` run), it does an UNCONDITIONAL `exit 2` (stop) regardless of the last-known reading. A stale reading is only dangerous if we might have CROSSED the threshold since it was taken. Same false-stop family the SKILL warns about for `RELAY_QUOTA_DECAY_7D`.
  - **Acceptance**: in the stale-path of `relay/scripts/quota-stop.sh`, replace the post-refresh-failure unconditional `exit 2` (~L82) with a margin check: if EVERY checked bucket for the tier has last-known util < (its `bucket_threshold`×100 − MARGIN), log `proceeding on stale-but-safe cache` and fall through to the normal `check_key` loop (→ exit 0); if any checked bucket is within MARGIN of its threshold OR missing, keep `exit 2`. `MARGIN = RELAY_QUOTA_STALE_MARGIN` points, **default 30**. A genuinely MISSING cache file still exits 2 (blind). No change to the seatbelt, the fresh-cache path, or the self-refresh attempt itself.
  - **Spec / red test**: `tests/test_quota_stop_stale_margin.sh` (`# roadmap:1d64`) — hermetic (temp cache aged past STALE_SECS + tokenless creds so refresh is skipped): stale+low-util → exit 0; stale+near-threshold bucket → exit 2; missing cache → exit 2; fresh+low-util → exit 0. RED until implemented.
  - **Done-check**: tick this checkbox, then `make test` fully green.
  - **Secondary (optional, NOT this item):** `quota-stop` should respect the existing `/tmp/claude-usage-backoff` instead of re-hitting the 429'd endpoint, and reuse the statusline's cache rather than competing for the token's ~5-req budget. Split to a follow-up if pursued.
- [x] [ROUTINE] Cheap quota PRE-GATE before the per-round discovery fan-out — don't spend N shards on a round that immediately quota-stops <!-- id:5c00 -->
  - **Why** (observed 2026-06-25, run relay-20260625-225111, `/relay --afk . --quota-7d 50`): round 1 ran the **DISCOVER_SHARDS fan-out (5 agents, ~94k tokens)** and only THEN hit the quota gate → `stopReason=quota-stale-cache`, 0 units dispatched. The stop itself was CORRECT (id:1d64 margin-aware fail-safe: 44% 7d-used vs a 50% cap = 6pt headroom < 30pt MARGIN under a stale cache), but the **ordering wasted the whole discovery wave** — the gate runs after the tokens are already spent. User: "what's the point of discover/shards before the quota check killing those discoveries?"
  - **Acceptance**: in `relay/scripts/relay-loop.js`, run the `quota-stop.sh` gate (or a cheap inline last-known-cache margin check) at the TOP of `runRound()` — BEFORE the `discover-prelude` + the DISCOVER_SHARDS fan-out — so a round that will stop returns immediately with the correct `stopReason` and **zero discovery agents**. The once-only prelude global work (runId, inject.take) and the per-round shard fan-out both move *after* the pre-gate. Keep the existing post-discovery/ pre-dispatch gate too (quota can cross mid-round); this just adds an early-exit. Round 1's pre-gate uses the existing cache (no extra refresh).
  - **Spec / red test**: `tests/test_relay_loop_structure.sh` (extend, `# roadmap:5c00`) — assert the round body calls the quota gate before the discovery fan-out (grep ordering in `runRound`), and a mocked over-threshold gate yields `rounds:0`-style early return with no shard dispatch.
  - **Done-check**: tick + `make test` green; a dry-run with a forced over-threshold cache dispatches 0 discovery shards.
  - **Context**: `relay/scripts/relay-loop.js` (`runRound`, the discover-prelude + shard fan-out ordering), `relay/scripts/quota-stop.sh`. Relates id:1d64 (the stale-cache margin fix — correct, but fires too late in the round). Deps: none.
- [x] [ROUTINE] Sync relay-loop.js classifier to the canonical `[HARD — pool]` lane token (close the id:78ff drift) <!-- id:3c0f -->
  - **Why** (audit 2026-06-23): id:78ff made `[HARD — pool]` the single canonical lane token (`hard-lanes.md`, `gather-human-backlog.sh`, project_manager `scan.py`) and back-filled this repo's only pool-executable HARD item (id:401c) to `[HARD — pool]` — but left `relay/scripts/relay-loop.js` keyed on the OLD bare `[HARD — strong model]`. Consequence: a `[HARD — pool]` item is HIDDEN from `/relay human` ("the pool runs it") yet the loop's EXECUTABLE-HARD test / `openHard` count / hard-child dispatch prompt look for a DIFFERENT literal, so the pool can compute `openHard=0` and never emit a `hard` verdict → the item falls in the crack between loop and human = **drained pool despite open work**. Latent landmine: `gather` LOUD-rejects `[HARD — strong model]` as untagged, so any own-repo using the loop's token would break `/relay human`.
  - **Acceptance**: in `relay-loop.js`, replace every operative `[HARD — strong model]` with the canonical `[HARD — pool]` (the verdict definition ~L623, the EXECUTABLE-HARD test ~L626, the `openHard` definition ~L661, the hard-child dispatch prompt ~L913, and the comment ~L304-305). The progress-meta title (L8) is already `[HARD — pool]` — leave it. NO behavioural change beyond the token; do not touch the EXECUTABLE-HARD gate logic.
  - **Spec / red test**: `tests/test_relay_loop_hard_token.sh` (`# roadmap:3c0f`) — static: asserts relay-loop.js carries NO `HARD — strong model` token, DOES reference `[HARD — pool]`, and that token is defined in `hard-lanes.md` (consumers cannot drift again). RED until synced.
  - **Done-check**: tick this checkbox, then `make test` fully green.
- [x] [ROUTINE] Add `references/hard-lanes.md` to the Makefile install manifest + guard every reference doc <!-- id:69ef -->
  - **Why** (audit 2026-06-23): `relay_FILES` in the Makefile is an EXPLICIT list, not a glob; `relay/references/hard-lanes.md` (added by id:78ff) was never added, so `make install-relay` does NOT symlink it into `~/.claude/skills/relay/references/` — it 404s at the install path while `gather-human-backlog.sh` error messages + `human.md` point readers to it. Generalize: a new reference doc must never be silently left un-installed.
  - **Acceptance**: add `references/hard-lanes.md` to `relay_FILES`; then `make install-relay` (the human/strong turn re-runs the live install once it lands). The test below guards that EVERY `relay/references/*.md` is in the manifest.
  - **Spec / red test**: `tests/test_relay_refs_install_complete.sh` (`# roadmap:69ef`) — static: asserts every `relay/references/*.md` appears in `relay_FILES`. RED until the Makefile line is added.
  - **Done-check**: tick this checkbox, then `make test` fully green.
  - **Note**: this item is itself `[HARD — pool]`, so the pool can only DISPATCH it once id:3c0f lands (the loop must recognize `[HARD — pool]`). id:3c0f is `[ROUTINE]` and pool-executable now → it self-bootstraps this one. Until then, build it via `/relay human` (hard_pool surface) or a manual strong turn.
- [x] [HARD — pool] `roadmap-lint.sh` — a GRAMMAR validator that LOUD-rejects any open ROADMAP item not matching the proper syntax; wire into `review` + `human` (done 2026-06-23, relay HARD child) <!-- id:09a3 -->
  - **Done 2026-06-23** (relay HARD child, id:da26): new `relay/scripts/roadmap-lint.sh [roadmap|repo-root]` (`set -euo pipefail`; defaults to cwd-repo ROADMAP.md; short stdout, details to `~/.claude/logs/relay-roadmap-lint.log`). POSITIVE grammar: an open top-level `- [ ]` item under an ACTIVE section must carry (1) a recognized class/lane tag — `[ROUTINE]` OR a `hard-lanes.md` lane (`[HARD — pool|meeting|hands|decision gate]`, optionally `[INTENSIVE — …]`) — AND (2) a 4-hex `id:` token; reports EVERY violation generically (offending line + id + which clause failed) and exits nonzero; a conforming ROADMAP is a clean zero-exit no-op. Lane vocabulary is READ from `hard-lanes.md` (single source — no second copy; fail-safe fallback if the doc is unreadable). Closed `[x]`, indented continuation lines, and gated/deferred/done/icebox/archive/parked sections are EXEMPT. Does NOT auto-rewrite — surfaces for the strong/human turn (id:78ff precedent). Wired into `references/review.md` §5 (runs on cwd repo, surfaces in return report) and `references/human.md` §2 (runs across own repos alongside gather). Added to `relay_FILES`/`relay_EXEC`/`relay_ALLOW` in the Makefile (id:69ef install-completeness precedent). Spec `tests/test_roadmap_lint.sh` (roadmap:09a3) green; live ROADMAP lints clean.
  - **Why** (audit 2026-06-23, user directive): instead of detecting a fixed list of SPECIFIC known issues, the relay should reject ANYTHING that doesn't match the proper open-item syntax (a positive grammar — extends 415b grammar-tightening-with-loud-rejection). `gather` already LOUD-rejects an untagged `[HARD]`, but is blind to (a) an open `- [ ]` item with NO class tag at all (e.g. meeting-rpg id:0951, a `[SEVERE]` item with no relay lane — invisible to BOTH the loop AND `/relay human`) and (b) a malformed/unknown lane outside the `[HARD]` family (e.g. truncocraft id:9a98 `[HARD — epic, post-MVP]`). A grammar catches every deviation, not just the ones we thought to look for.
  - **The grammar** (an open `- [ ]` item under an ACTIVE section must match ALL of): (1) a recognized class/lane tag — `[ROUTINE]` OR a `hard-lanes.md` lane (`[HARD — pool|meeting|hands|decision gate]`), optionally combined with `[INTENSIVE — <resource>]`; (2) an `id:XXXX` (4-hex) token. Items under a GATED / DEFERRED / DONE / ICEBOX / ARCHIVE heading are EXEMPT (explicitly parked). Closed `- [x]` items are never linted. Read the recognized lane set from `hard-lanes.md` (single source of truth — no second copy of the vocabulary).
  - **Acceptance**: new `relay/scripts/roadmap-lint.sh [roadmap-path | repo-root]` (`set -euo pipefail`; defaults to the cwd repo's `ROADMAP.md`; short stdout, details to `~/.claude/logs/`). Reports EVERY non-conforming active open item GENERICALLY (the offending line + id if present + which grammar clause failed) and exits nonzero when any are found; a fully conforming ROADMAP is a clean zero-exit no-op. Then wire it in: `references/review.md` §5 (re-derive ROADMAP) runs it on the cwd repo and surfaces violations in the return report; `references/human.md` §2 (collect) runs it across own repos alongside `gather`. Do NOT auto-rewrite items — surface for the strong/human turn to assign the lane (mirrors id:78ff's "back-fill belongs to each repo's next handoff/review/human" precedent).
  - **Spec / red test**: `tests/test_roadmap_lint.sh` (`# roadmap:09a3`) — hermetic fixture with one conforming item per class, a missing-class item, an unrecognized-lane item, a missing-id item, a gated-section exempt item, and a done item; asserts the three active violations are each reported, the conforming/exempt/done items are NOT, and a clean fixture exits zero. RED until the script exists + is wired in.
  - **Done-check**: tick this checkbox, then `make test` fully green.
- [x] [ROUTINE] Discover-shard must treat an open `[INTENSIVE — <res>]` item as WORK, never classify the repo idle <!-- id:ad74 -->
  - **Why** (observed 2026-06-23, run relay-20260623-112409, `/relay --afk`): ai-codebench had an open `[INTENSIVE — local-llm]` item (id:244b, ~15 model runs pending) and the run set `allowIntensive=true`, yet the discover-shard classified the repo `idle — in sync, no open work` and never emitted an intensive-tagged unit, so `relay-loop.js`'s INTENSIVE partition (~L877, `ALLOW_INTENSIVE ? intensiveUnits : intensiveDeferred`) never received a unit → the user's overnight ai-codebench drain (id:244b/8bea) was blocked. **Not a gather bug** (`gather-repo-state.sh --repo ai-codebench` correctly emits `is_finished=false` + the open `[INTENSIVE]` box + id:244b — verified this session). **Root cause = shard JUDGMENT**: the shard never sees the `--afk`/`allowIntensive` flag (it is a JS-level dispatch decision), and the repo's own ROADMAP convention prose ("a session finding only `[INTENSIVE]` items open reports 'no executor-eligible work' and stops" — written for generic/remote executors with no GPU) is read literally and reported as idle, short-circuiting the intended design (always emit an intensive unit; let the loop decide dispatch by `ALLOW_INTENSIVE`). This is the symmetric PROMOTE counterpart to the id:000d is_finished DEMOTE guard, and uses the same mechanize-the-judgment + JS-side-backstop pattern (id:415b).
  - **Acceptance**:
    1. **Shard-prompt instruction** (`relay/scripts/relay-loop.js`, the precedence/intensive block ~L644-679): add an explicit rule that an open `- [ ]` item carrying an `[INTENSIVE — <resource>]` modifier is ALWAYS executor-eligible WORK — the repo MUST emit a `units` entry with `intensive` set (parse the resource per the existing id:8d52 rule ~L674), and MUST NOT be classified `idle`/`skipped` on the strength of any repo-local "reports no executor-eligible work" convention prose. The auto-run-vs-defer decision stays with `relay-loop.js` (the existing INTENSIVE partition already surfaces deferred units as skipped when `!ALLOW_INTENSIVE`). The same `--afk`-blind reasoning as id:000d applies: a repo-local convention must not override the shard's emit.
    2. **JS-side backstop** (mirror the id:000d demote guard ~L722): after shard results are merged, a repo whose gathered state shows an open `[INTENSIVE — <res>]` item (carry the resource through `gather-repo-state.sh` / the DISCOVER_SCHEMA the same way `is_finished` is carried — a new `top_intensive` STRING field, empty when none) MUST NOT remain in `idle`/`skipped` with no unit; if the shard idled it, PROMOTE it to a `units` entry with `intensive` set (a PROMOTE-only guard — it may only move a repo toward a dispatch verdict for the intensive resource, never demote). This makes a shard that ignores instruction 1 self-correcting, exactly as id:000d's JS backstop corrects an over-classifying shard.
  - **Spec / red test**: `tests/test_relay_loop_intensive_emit.sh` (`# roadmap:ad74`) — static, hermetic: asserts (a) the shard prompt in `relay-loop.js` instructs that an open `[INTENSIVE]` item is never idle (a grep for the new rule marker, e.g. `id:ad74`), (b) the DISCOVER_SCHEMA declares the carried intensive field (`top_intensive: { type: 'string' }`), (c) a JS-side `[INTENSIVE] promote` backstop block referencing `id:ad74` is present, and (d) `gather-repo-state.sh` emits `top_intensive` (the resource of the top open `[INTENSIVE — <res>]` item, "" when none). Model on `tests/test_relay_loop_structure.sh` §id:000d/401c. RED until both halves land.
  - **Done-check**: tick this checkbox, then `make test` fully green.
  - **Note**: add an INTENSIVE-only fixture to the shard-canary corpus (`tests/shard-canary/intensive-only/` → expected a `units` intensive verdict, NOT idle) when the corpus is next exercised — non-blocking for this item (the canary harness is token-gated, not in the default sweep). Distinct from id:000d (the inverse: false-DISPATCH on FINISHED repos); a natural check to fold into the relay-health report id:0907.

- [x] [ROUTINE] relay-loop progress buckets — split the crowded `Dispatch` /workflows group into per-verdict phases (Execute/Review/Hard/Handoff) + a `Support` bucket for non-work agents (quota gate, lease release, inject-take) (done 2026-06-22, user request; display-only, zero behavioural change; `tests/test_relay_loop_structure.sh` locks the routing) <!-- id:7d1e -->

- [x] [ROUTINE] Relay ROADMAP archiver — `relay/scripts/roadmap-archive.sh` moves done `[x]` items out of the live ROADMAP <!-- id:6b67 -->
  - **Why**: a large ROADMAP overflows the executor-contract prompt → "Prompt is too long" blocks ALL execute/INTENSIVE dispatch on that repo (id:93cc, hit live 2026-06-22 on ai-codebench's ~400-line ROADMAP). Keep the live ROADMAP to OPEN items by archiving completed ones, mirroring how `todo-update/archive-done.sh` keeps TODO.md small.
  - **Acceptance**:
    - New `relay/scripts/roadmap-archive.sh [repo-root]` (defaults to `git rev-parse --show-toplevel`); `set -euo pipefail`; short stdout, details to `~/.claude/logs/`.
    - Moves each fully-done item — a top-level `- [x] …` line PLUS all its indented continuation lines (the block up to the next top-level `- [ ]`/`- [x]` or `## ` heading) — from `ROADMAP.md` into `ROADMAP.archive.md` (created if absent, appended newest-last), preserving the `<!-- id:XXXX -->` token and original text verbatim.
    - NEVER touches open `- [ ]` items, `## ` section headers, or the file preamble/conventions block. Headers that become empty are LEFT (no pruning — ROADMAP headers are structural, UNLIKE archive-done.sh).
    - Conservative gate (mirror archive-done.sh): only archive items done in a PRIOR commit (not the working tree) OR carrying a trailing "done YYYY-MM-DD" ≥30 days old — never archive a just-ticked item (so a same-run checkpoint isn't archived before review sees it). Gate must be explicit + tested.
    - Idempotent; flock-guarded on a `*.lock` (fd pattern per `append.sh`/`diary-append.sh`); re-running with nothing to archive is a clean no-op.
  - **Tests**: add `tests/test_roadmap_archive.sh` (`# roadmap:6b67`), hermetic (mktemp; no `~/.claude`/network): multi-line item-block capture, open-item + header preservation, the prior-commit/≥30d gate (NEGATIVE: a working-tree-ticked item is NOT archived), idempotent no-op, token preservation. Tick the checkbox so `make test` is green = done.
  - **Context**: model on `todo-update/archive-done.sh` (date/section logic) but ROADMAP-specific (no section pruning; multi-line blocks). This is fix-direction (b) of id:93cc; the separate (a) "executor contract passes only OPEN items to the child" stays in id:93cc.
- [x] [HARD — hands] Heartbeat liveness on the relay claim/lease — FOUNDATION for id:7809 + id:98f0; build FIRST. Extend the existing id:0902 claim/lease to write `runId` + `heartbeat_ts` + a TTL, with a single staleness-check helper (`heartbeat older than TTL ⇒ prior run died`) consumed by BOTH the auto-reconcile (id:7809) and the watchdog (id:98f0) — one source of truth, no separate `.relayactive` file. Acceptance: a test asserts a stale heartbeat reads "dead", a fresh one "alive". Files: `relay/scripts/claim.sh` (+ `heartbeat.sh` or equivalent) + a test. Design: **TODO id:e149** + `docs/meeting-notes/2026-06-22-1546-relay-outage-resilience.md`. <!-- id:e149 -->
- [x] [HARD — hands] Auto-reconcile-on-restart for the relay loop — DESIGN RESOLVED 2026-06-22 (`docs/meeting-notes/2026-06-22-1546-relay-outage-resilience.md`): `/relay reconcile --auto` (one code path with the human reconcile) loop-invoked at startup on a STALE heartbeat (id:e149 foundation, extends id:0902 — no new `.relayactive` file); SAFE auto-integrate = clean tree + mechanical `gaming-scan.sh` + full-suite-green + ledger-only/trivial diff; everything else (BLOCKED/partial/red/conflicting/needs-strong-judgment) → parked + surfaced via REVIEW_ME / `/relay human`; conservative classifier defaults to JUDGMENT, never a weaker bar than a human `/relay review`. Design + rationale: **TODO id:7809** (single-id-two-views). Build AFTER id:e149. <!-- id:7809 -->
- [x] [HARD — hands] Outage-resilient LOCAL relay loop — DESIGN RESOLVED 2026-06-22 (`docs/meeting-notes/2026-06-22-1546-relay-outage-resilience.md`): observe-first. Build a watchdog systemd `--user` timer (modelled on `quota-sample.timer`) that detects a dead loop via the SHARED heartbeat (id:e149) and NOTIFIES for one-tap restart (PushNotification→`notify-send` fallback) — NOT a headless `claude -p`, so it sidesteps the permission wall entirely; its outage-death log is the EVIDENCE GATE to re-open the deferred heavy build (curated allowlist / dedicated-OS-user scoped allowlist = id:2d01). Deferred-out-of-scope until evidence warrants: any `--dangerously-skip-permissions` use, the allowlist treadmill, the OS-user repo-access bridge. Cheap fixes split out: nudge id:bde8, upstream report id:0994. Design + rationale: **TODO id:98f0**. Build AFTER id:e149. (Billing note 2026-06-22: the deferred *heavy* path's headless `claude -p` would-bill-separately overhang is relieved — that Agent-SDK/`claude -p`→dedicated-credit cutover is deferred with advance notice, see memory `anthropic-agent-sdk-billing-deferred` / TODO id:00a5 — but the heavy path stays gated on the permission wall + evidence regardless.) <!-- id:98f0 -->
- [x] [ROUTINE] Fix the misleading `loop-hint.sh`/step-0a "unattended resilience" nudge — correct it to state `/loop`/cron dies WITH the session (resilient only to relay's own early-exit — quota/seatbelt — within a live session, NOT to a session/process kill). Pairs with id:888a/id:8602. Files: `relay/scripts/loop-hint.sh` + SKILL.md step 0a. Design: **TODO id:bde8** + `docs/meeting-notes/2026-06-22-1546-relay-outage-resilience.md`. <!-- id:bde8 -->
- [x] [HARD — hands] File `CronCreate durable:true` no-op upstream — FILED 2026-06-29 → https://github.com/anthropics/claude-code/issues/72238 (reproduced on Claude Code 2.1.195: `{durable:true,recurring:true}` returns `[session-only]`, writes no `~/.claude/scheduled_tasks.json`; the tool description now claims persistence → description↔behavior mismatch). Draft: `docs/upstream-reports/2026-06-29-croncreate-durable-noop.md`. Design: **TODO id:0994** + `docs/meeting-notes/2026-06-22-1546-relay-outage-resilience.md`. <!-- id:0994 -->
- [x] [HARD — hands] Fleet-quiescence drain — wind the pool down when all remaining work is gated/finished instead of spinning to MAX_ROUNDS re-confirming an already-drained fleet. SHIPPED 2026-06-29: pure `relay/scripts/drain.mjs` (`unitIsSubstantive` — a confirming-only review that reopened/added nothing is NOT progress; `classifyDrainBacklog` — buckets blocked repos finished/gated/circuit-broken/dirty + names the gated ones with a `/relay human`·`/meeting` pointer), byte-identical inline copies in `relay-loop.js` (dry-detector flips `produced→substantive`; wind-down logs the backlog summary). Subsumes the cwd self-review footgun (a no-op re-review no longer resets `dry`). `tests/test_relay_drain.sh` (`# roadmap:d58f`) — 15 assertions green; full suite green. Design + rationale: **TODO id:d58f**. <!-- id:d58f -->
- [x] [ROUTINE] Finer-grained `/workflows` phase buckets — SHIPPED 2026-06-29: split the two overloaded catch-alls so per-phase counts are meaningful. `meta.phases` + the `agent()` `phase:` opts in `relay-loop.js` now route `discover-shard`→**Classify** (split from the prelude's Discover), `write-relay-status`→**Status** (was flooding Integrate), `gaming-log`/`handback-followup`→**Logging**, `quota`→**Quota**, `release`→**Leases**; Integrate holds only the merge; Support keeps just injection/heartbeat/auto-reconcile. Purely display, zero behavioural change (id:7d1e precedent). `tests/test_relay_phase_buckets.sh` (`# roadmap:7c10`) green; full suite green. Design: **TODO id:7c10** (relates id:7d1e, id:de69). <!-- id:7c10 -->
- [x] [ROUTINE] Surface the ROADMAP/TODO `id:` a relay unit is/was working on — SHIPPED 2026-06-29. (a) dispatch-time label enrichment: a known-at-dispatch item id (injected `--item` or a hard unit's bounded item) is appended to the `/workflows` agent label → `execute:zkm-stt id:09a3`. (b) durable record: `REPORT_SCHEMA` gains `worked_ids` (children return the item id(s) they closed/created/promoted; review falls back to verified-green∪reopened), and the integrator propagates them into the ckpt-tag checkpoint message (`… [id:a,b]`), the RELAY_STATUS "Completed this run" line (`ids=…`), and the `relay-events.jsonl` integrate event — so plain execute/review units (which pick the item INSIDE the child) are traceable post-run. `tests/test_relay_worked_ids.sh` (`# roadmap:de69`) green; full suite green. Design: **TODO id:de69** (relates id:c8b6 events, id:7c10/7d1e display). <!-- id:de69 -->

- [x] [ROUTINE] `/meeting` deferred ledger write-back — breadcrumb + replay-on-next-invocation + log (done 2026-06-22, executor) <!-- id:2c42 -->
  - **Design + rationale: TODO id:2c42** (single-id-two-views) + meeting `docs/meeting-notes/2026-06-22-2139-meeting-worktree-writeback.md` (af04). The 2026-06-22 meeting REJECTED worktree-per-`/meeting` (D2 — inherits id:ca87's non-unionable-checkbox merge problem, contradicts `/meeting`=same-dir→flock + worktrees-are-code-only) and ruled step 2a's deferral is **working as designed** (D1 — no data loss). The only gap: a deferred write-back never auto-completes (it lags the note until the next `--cross-ledger` scan / manual `/todo-update`). Build the self-heal.
  - **Acceptance** (matches the meeting test contract):
    - On a **refused** step-2a claim (deferral), `meeting/SKILL.md` step 2a persists a **generic** `{target_file, helper, payload}` JSON breadcrumb to a gitignored drop path `<root>/.meeting-deferred-writeback.json` AND appends an event to `~/.claude/logs/meeting-deferred-writeback.log`. Payload format generic so it extends if another defer site appears, but WIRED IN only at step 2a (the sole site that defers today — `~/.claude` shared files are flock-safe, no pool there).
    - A **setup-phase replay check** in BOTH `/meeting` setup AND `/todo-update`: applies any pending payload via the named helper (`md-merge.py`/`append.sh`) under a **fresh** `claim.sh acquire`, then clears the drop file. Nothing is applied while the pool still holds the claim (replay re-defers on refusal).
    - Add `.meeting-deferred-writeback.json` to `.gitignore`.
    - **Also (bookkeeping):** add the af04 motivation as a cross-link note on id:3558 (no new structural build — id:3558 covers concurrent CODE writers, orthogonal to the foreground meeting's ledger tick) and record that the literal worktree-per-meeting option was REJECTED by this meeting.
  - **Spec / red test**: `tests/test_meeting_deferred_writeback.sh` (`# roadmap:2c42`) — static-structural (mirrors `test_meeting_claim_hold.sh`): asserts the breadcrumb+log on deferral, the generic payload shape, the replay check (fresh claim, clears drop file) in `/meeting` + `/todo-update`, the still-holds guard, and the gitignore entry. RED until implemented.
  - **Done-check**: tick this checkbox, then `tests/run-tests.sh tests/test_meeting_deferred_writeback.sh` and full `make test` green. Tick the TODO id:2c42 line too (single-id-two-views).

- [x] [HARD — pool] Explicit `[HARD]` lane tags + bucket the human-backlog HARD surface (done 2026-06-22, relay HARD child — relay/bash half) <!-- id:78ff -->
  - **Done 2026-06-22** (relay HARD child, id:da26): shipped the relay/bash half. (1) Lane vocabulary doc `relay/references/hard-lanes.md` — the single shared contract both `gather-human-backlog.sh` (id:78ff) and project_manager `scan.py` (id:b466) read: `[HARD — pool|meeting|hands]` lanes + `[HARD — decision gate]`/`🚧 route:meeting|human|decision-gate` as meeting-lane aliases (id:3801); `[INTENSIVE]` is the orthogonal resource axis, not a lane. (2) `gather-human-backlog.sh`: replaced `emit_gated_hard` (single `gated_hard` lump) with `emit_hard_lanes` — READS the explicit lane tag → emits per-lane kind `hard_pool`/`hard_meeting`/`hard_hands`; an open `[HARD]` with NO recognized lane prints a stderr `ERROR:` and forces a NONZERO exit (id:415b grammar-tightening-with-loud-rejection, never silently default). (3) `references/human.md` §2/§3/return-summary: the three buckets are now distinct call-to-actions (pool→FYI/`--afk`, meeting→`/meeting`, hands→"you run these"), not one /meeting firehose. (4) Back-filled THIS repo's bare `[HARD — strong model]` items: de4e→meeting, 401c→pool, 3346→meeting; dba3 left as its machine-managed `[HARD — decision gate]` alias. Acceptance test `tests/test_hard_lane_buckets.sh` (roadmap:78ff) green. **Residual (not this worktree's scope):** cross-repo back-fill of OTHER confirmed-own repos' bare `[HARD — strong model]` tags — a relay child works ONE repo's worktree; the per-repo lane back-fill belongs to each repo's next handoff/review or a `/relay human` sweep (the collector now LOUD-rejects any un-back-filled untagged HARD, so the gap is self-surfacing). project_manager id:b466 (Python half) consumes this same `hard-lanes.md` contract.
  - **Design + rationale: TODO id:78ff** (single-id-two-views — the "why" lives there). DECISION 2026-06-21 (user "obviously explicit"): every open `[HARD]` ROADMAP item declares a lane in its bracket tag — `[HARD — pool]` (this `--afk` pool runs it via the `hard` verdict, id:da26), `[HARD — meeting]` (≡ `[HARD — decision gate]`/`🚧 route:…`, id:3801 → `/meeting`), `[HARD — hands]` (hardware/sudo/secret/on-device/rehearsal → "you run these"). `[INTENSIVE — <resource>]` (id:8d52) is an ORTHOGONAL resource axis, not a lane.
  - **Scope (this is the relay/bash half; `proj relay` half = project_manager id:b466):**
    1. Document the lane vocabulary ONCE in `relay/references/` (the single source both tools read).
    2. `gather-human-backlog.sh`: replace the "emit every `[HARD]` as gated_hard" lump with reading the explicit lane tag → emit a `bucket` field (pool|meeting|hands); a `[HARD]` with NO lane tag is emitted as `untagged` and the script EXITS NONZERO / prints a LOUD warning (id:415b grammar-tightening-with-loud-rejection — never silently default).
    3. `references/human.md`: present the three buckets as distinct call-to-actions (pool→"run /relay --afk", meeting→/meeting, hands→checklist), not one "/meeting" firehose.
    4. Back-fill every existing bare `[HARD — strong model]` across all confirmed `own` repos to an explicit lane (use the 2026-06-21 manual re-bucketing in the diary as the starting classification).
  - **Acceptance:** a new `tests/test_hard_lane_buckets.sh` (`# roadmap:78ff`): a ROADMAP fixture with one item per lane + one untagged asserts gather-human-backlog emits the right `bucket` per item AND exits nonzero (loud) on the untagged one; the lane vocabulary doc exists; cross-check that the marker set matches project_manager's (id:b466). RED until implemented.
  - **Coupling:** ships its vocabulary doc BEFORE or WITH project_manager id:b466 (shared contract; keep them in sync). Relates id:3801/da26/8d52/9c92/415b.

- [x] [ROUTINE] Harden the flaky `test_relay_claim_liveness.sh` (hermeticity under parallel run) (done 2026-06-21, executor) <!-- id:6b91 -->
  - **Bug (observed 2026-06-21, /relay human):** `tests/test_relay_claim_liveness.sh` (roadmap:7570) flakes ~1/run under the **parallel** `tests/run-tests.sh` (1 fail), but passes on re-run and is green in isolation. It claims hermetic (`CLAIM_BASE` in a tmpdir) yet shows cross-test interference under concurrency. The feature (worktree-anchored claim liveness) is genuinely green — this is a TEST hermeticity defect, not a regression. Decision: harden, don't accept-as-known-flaky (a flaky test erodes the suite's signal).
  - **Fix:** identify the actual shared surface first (a default `claim.sh` registry path? a fixed `/tmp` lock the tmpdir `CLAIM_BASE` doesn't cover?), then give the test a fully private claim root per test process and/or serialize the claim tests if they share state the runner can't isolate.
  - **Acceptance:** `test_relay_claim_liveness.sh` passes across ≥20 consecutive full **parallel** `tests/run-tests.sh` runs (no intermittent fail); the leaking shared surface is documented in the fix commit.

- [x] [ROUTINE] Mechanize the TODO↔ROADMAP seam (promotion-tracking + derived count) (done 2026-06-21, executor; residual count-line derive-or-drop split to TODO id:1de1, gated on id:2840, 2026-06-22) <!-- id:d9b0 -->
  - **Design + rationale: TODO id:d9b0** (single-id-two-views). The split stays (TODO=why, ROADMAP=now); mechanize the hand-done SYNC. Three gaps that bit 2026-06-21:
    1. **Promotion-tracking:** add a check (extend `meeting/orphan-scan.sh` or `todo-update/`) that flags a TODO item carrying an executable lane (`[ROUTINE]`/`[HARD — pool]`) whose `id:` has NO twin in that repo's ROADMAP → "un-promoted, pool-invisible" (id:78ff was filed TODO-only and the pool couldn't see it).
    2. **Derived count:** the `Relay: N open ROADMAP items` TODO summary (id:d5e0 here, id:d1dc in project_manager) is hand-maintained prose the id:401c audit keeps re-fixing — `proj`/`scan.py` already compute it. Derive it (a generator/check) or drop the prose line and point at `proj relay`.
    3. **Scope-split false-positives in `--cross-ledger`** (measured `/relay review --all` 2026-06-21): `orphan-scan --cross-ledger` flags ANY checkbox disagreement as drift, but a reused `id:` legitimately spans a *closed ROADMAP decision* + an *open TODO action* with genuinely different states — re-flagged every review forever → alarm fatigue, the very seam pain this item must measure. 3 concrete instances this sweep: `zelegator 6c63` (eval closed / swap deferred), `yinyang-puzzle a202` (defer-decision closed / paid filing pending), `yinyang-puzzle cf89` (ROUTINE cross-link closed / broader TODO scope). The guard needs a way to mark a divergence INTENTIONAL (proposed: an inline `<!-- xledger-ok: <reason> -->` annotation on the open side, honored like `# swallow-ok:` in id:4347; empty reason still flags). Open design Q (→ which item owns it): a per-line annotation is the point-solution; 2840's derived index models it natively (one id → two scope rows, each its own state) — so this may be EVIDENCE FOR 2840 rather than more d9b0 scope.
  - **Acceptance:** `tests/test_ledger_seam.sh` (`# roadmap:d9b0`): a fixture repo with an executable-lane TODO item absent from ROADMAP is FLAGGED; a present one is not; the count line is derived (or its removal is asserted); and an `xledger-ok`-annotated scope-split is NOT flagged while an un-annotated divergence still is. Builds on `orphan-scan.sh --cross-ledger`. Relates id:962a/69f4/415b; the scope-split half is partly dissolved by the deferred id:2840 (derived-index vision).

- [x] [ROUTINE] Add `--all` to relay-reconcile.sh so `/relay reconcile --all` is a tested code path (done 2026-06-21, executor) <!-- id:4e14 -->
  - **Bug (observed 2026-06-21):** `relay-reconcile.sh` only operates on ONE repo (cwd or arg). `/relay reconcile --all` has no script support, so the strong turn improvised a cross-repo sweep with `git for-each-ref … 2>/dev/null`. Run in the sandbox (where `git -C <repo outside cwd>` fails), the `2>/dev/null` swallowed every error and the run reported "0 parked orphans / clean" — a FALSE negative — while `proj relay` correctly showed parked `relay/orphan/*` branches in isochrone, project_manager, and zkm-pdf. Swallowing git stderr + a directory-exists check that still passed = silent miscount as "no orphans". Root lesson: a cross-repo sweep belongs in a deterministic script, not improvised per-turn.
  - **Fix:** add a first-class `--all` flag to `relay-reconcile.sh` that enumerates relay.toml `classification = "own"` repos (honoring the `# path:` override + `RELAY_TOML`/`SRC_DIR`, exactly as `gather-human-backlog.sh`'s `own_repos()` does — reuse/copy that parser, do not re-roll it) and runs the LIST action across all of them, aggregating output. It must **NEVER** silently swallow a git read failure: an unreadable/missing repo path is SURFACED on stderr (a NOTE/ERROR line), never counted as "no orphans". `--all` is list-only (multi-repo); `--integrate`/`--discard` stay per-branch single-repo (a combination like `--all --integrate` should be rejected, not guessed).
  - **Also:** the relay SKILL.md reconcile section should document that `reconcile --all` is the cross-repo list (one canonical command), so no future turn hand-rolls a sweep. Note the relay.toml path discrepancy to verify while here: `gather-human-backlog.sh` defaults `RELAY_TOML` to `~/.config/relay/relay.toml` but the live file is `~/.config/relay/relay.toml` — resolve to whatever the rest of the relay scripts actually use (don't break the existing default; just make `--all` read the same file the pool reads).
  - **Acceptance:** `tests/test_relay_reconcile_all.sh` (`# roadmap:4e14`) — temp RELAY_TOML + temp git repos; asserts `--all` lists a parked orphan and names its repo, skips non-own repos, does NOT spuriously attribute an orphan to a clean repo, and (the core guard) SURFACES an unreadable repo path instead of swallowing it. RED until implemented.

- [x] [HARD — strong model] Integrator can DESTROY uncommitted edits in a repo's main checkout (data loss) (done 2026-06-18, strong-execute) <!-- id:aa93 -->
  - **Bug (observed 3× on 2026-06-18):** while the pool was integrating dotclaude-skills, a human/parallel-session's uncommitted edit to `relay/scripts/relay-loop.js` (tracked, unstaged) **vanished** — reflog showed `reset: moving to HEAD`, `git stash list` was EMPTY (i.e. real loss, not a recoverable autostash). The integrate step's "verify clean tree, abort if dirty" (relay-loop.js ~line 990) is an **LLM-agent prompt, not a deterministic gate** — the most likely mechanism is the integrator agent "cleaning" a foreign-dirty tree (`git stash`+drop / `git checkout -- <f>` / `reset --hard`) to proceed with its `--no-ff` merge, discarding changes it did not create. `git-lock-push.sh`'s non-ff path (`git pull --rebase --autostash`, line 116) is a second exposure: it autostash-resets a foreign-dirty tree outside any lock the editor respects (the flock serializes only the push, NOT working-tree safety).
  - **Impact:** silent, unrecoverable loss of a concurrent editor's work. Forced a `TaskStop` of the pool just to land an edit safely. This is the acute, fileable slice of the id:3558 shared-checkout hazard.
  - **Fix directions:** (1) make the clean-tree gate DETERMINISTIC + FAIL-SAFE in a non-agent wrapper: `git status --porcelain` before any merge/push; if the tree carries changes the run did not create → DEFER the repo and surface it, never force-clean. (2) The integrator must NEVER run `git stash` / `git checkout --` / `git reset --hard` / `git clean` on a main checkout to make room. (3) `git-lock-push.sh`: STRONGLY CONSIDER dropping `--autostash` from the non-ff path (line 116) entirely — under commit-first discipline the tree is clean at push time, so `--autostash` is a no-op EXCEPT when the tree is unexpectedly dirty, i.e. a foreign session's uncommitted work; its only real effect is to silently sweep that work into a rebase autostash (user call 2026-06-18: "autostash bad maybe?"). Replace with the SAME fail-loud/defer the `--ff-only` path already uses on divergence (warn, keep work committed locally, `exit 0` non-fatal) — never silently mutate a dirty tree. (4) Structural fix remains id:3558 (worktree-per-session merge), but (1)+(2)+(3) are the cheap interim guard. Acceptance must include a `git-lock-push` case: a foreign-dirty tree is DEFERRED (warned, not stashed/lost), tree unchanged.
  - **Acceptance:** `tests/test_integrator_foreign_dirty.sh` (`# roadmap:aa93`) — seed a tracked-file edit in a fake main checkout, run the integrate/clean-tree gate, assert the edit SURVIVES and the repo is deferred (not merged). RED until implemented.
  - **DONE 2026-06-18 (strong-execute, fixes (1)+(2)+(3); structural fix (4)=id:3558 stays open):**
    - New deterministic gate `relay/scripts/clean-tree-gate.sh` (modeled on sync-origin.sh): observes ONLY (`git status --porcelain`), NEVER stash/checkout/reset/clean. Clean (or all entries `--accept`-ed) → `clean`/exit 0; foreign-dirty → `dirty <N>` + offending porcelain lines/exit 2 (caller DEFERS). `--accept <path>` whitelists a declared-acceptable path (e.g. a relay.toml-commented build artifact).
    - relay-loop.js integrate **step 1** now runs `clean-tree-gate.sh ${unit.path}` and ABORTS (merged=false) on non-zero — replacing the LLM-only "verify clean tree" prompt — with an explicit NEVER-`git stash`/`checkout --`/`reset --hard`/`git clean` prohibition on the main checkout (id:aa93 marker in-file).
    - `git-diary-workflow/git-lock-push.sh`: the `--rebase --autostash` (non-ff) path now refuses a foreign-dirty tree (`git status --porcelain` guard) instead of autostash-resetting it — leaves work committed-locally-not-pushed (non-fatal, same as a flock timeout).
    - Makefile registers `clean-tree-gate.sh` in relay_FILES/_EXEC/_ALLOW. `tests/test_integrator_foreign_dirty.sh` green; full `make test` green.
- [x] [HARD — pool] Gate-detection (id:3801) must commit its main-checkout ROADMAP edits atomically — uncommitted residue is a self-blocking dirty backlog (done 2026-06-24, relay HARD child id:da26) <!-- id:2147 -->
  - **Why** (observed 2026-06-24, 5 repos at once): the relay's gate-detection (id:3801) — run by `/relay review`/`/relay human` per-repo, which write ROADMAP gate annotations + lane migrations + seam decompositions in the **main checkout** (id:15d5, NOT a worktree) — leaves those edits **uncommitted** when the run ends/dies before a commit (mid-run API error, session kill, or simply no per-edit commit step). The residue then trips the dirty-guard (id:aa93): every subsequent pool run DEFERS the repo to avoid data loss, so the residue can never be cleared by the very `review` that would commit it — a self-perpetuating backlog. Found `M ROADMAP.md`-only residue in trAIdBTC (id:b123 +seams 00cb/c666), zkm-ner (7b4e), proton-moresync (5cc5), puzzle-pwa (6bef), and a mixed ROADMAP+code residue in zkm-pdf (9475 +seams cd59/8aa4 + the cd59 impl). Memory [[relay-onboarding-vs-confirmation]] recorded the symptom ("commit the residue") 2026-06-21; this is the structural fix. Complement to id:aa93 (which stops the integrator DESTROYING foreign-dirty trees — this stops gate-detection CREATING the residue). Sibling of id:148b (atomic write+commit in `/meeting`'s md-merge.py).
  - **Acceptance**: identify every relay step that writes ROADMAP/TODO/REVIEW_ME in the **main checkout** (gate-detection id:3801 in `review.md`/`human.md`, the re-derive-roadmap step, lane back-fill) and make each write commit **atomically per-repo** — scoped `git commit <ledger-file>` under the flock'd `meeting/md-merge.py` path (the id:148b precedent), so an interruption can NEVER leave a modified-but-uncommitted ledger in main. After any gate-detection edit there is no dirty ledger left behind. Add a test that simulates a gate write + abort and asserts the tree is either clean-committed or untouched (never dirty-uncommitted). Relates id:aa93/148b/3558/15d5/415b(4); back-fill note: a `/relay review` of the 5 just-committed repos will adjudicate the freshly-committed seams' checkbox + versioning.
  - **Done 2026-06-24** (relay HARD child, id:da26): new deterministic `relay/scripts/commit-ledger.sh <repo-root> -m <msg> <ledger-path>…` — the reusable "commit your main-checkout ledger edit atomically" primitive. It flock-serializes on the repo's `.git-lock-push.lock`, stages ONLY the named ledger paths (`git add -- <path>`, NEVER `git add -A` — id:debf) and commits them with a scoped `git commit -- <path>`, so a concurrent edit to an UNRELATED file is left alone. It NEVER stashes/resets/cleans/`checkout --` a foreign-dirty tree (id:aa93 — only ADD+COMMIT). COMMIT-ONLY (never pushes — relay children don't push; a local commit alone clears the dirty-guard, which is the whole fix); a named file with no change is a clean no-op (idempotent). Rejects out-of-repo paths + loud-fails on missing `-m`. The AUTOMATED gate path (`handback-followup.py`, id:3801) already committed atomically via `git-lock-push --ff-only` + single-file manifest — the residue came from the **LLM-prose** steps, so wired commit-ledger.sh into `references/review.md` §5 (after the ROADMAP/TODO re-derivation + gate annotations) and `references/human.md` §5 (after each repo's `md-merge.py` flow-back — md-merge writes but does NOT commit, the exact gap). Registered in `relay_FILES`/`relay_EXEC`/`relay_ALLOW`/`relay_LOCAL` (id:69ef install-completeness). Spec `tests/test_relay_commit_ledger.sh` (`# roadmap:2147`) green (scoped-commit-leaves-foreign-dirty-alone, no-stash, multi-file, clean-no-op, abs-path, misuse, path-traversal-reject, prose+manifest wiring); full suite green (101). Note: this provides the helper + wiring; a future `/relay review` can additionally fold a `commit-ledger`/dirty-residue check into `relay-doctor.sh` (id:0907 family) for detection alongside this prevention.
  - **Done-check**: tick this checkbox, then `make test` fully green.
- [x] [HARD — pool] Standalone GPU/intensive background jobs must acquire a relay `resource:<name>` claim so `--intensive` can serialize against them (done 2026-06-25, relay HARD child id:da26) <!-- id:a643 -->
  - **Why** (observed 2026-06-24): `~/.claude/logs/ai-codebench-drain.sh` (the id:244b matrix drain) ran a local `llama-server -ngl 99` on the GPU for ~2h, fully detached (PPID 1) and OUTSIDE the relay. It holds **no** relay claim, so a concurrent `/relay --intensive` pool is **blind** to it: the relay's intensive child does `claim.sh acquire resource:<name>` and correctly stops if busy (relay-loop.js ~L1200), but nothing told it the GPU was already taken → had the pool dispatched an ai-codebench `[INTENSIVE — local-llm]`/GPU unit it would have spun up a SECOND llama-server concurrently = GPU OOM ([[oom-local-model-session-kills]], the Gemma-26B 6-session kill). The relay side already HONORS a held `resource:<name>` claim; the only missing half is the standalone job ACQUIRING it. Neighbour of id:2147 (both about state the relay can't see); resource axis is id:8d52.
  - **Acceptance**: (1) document a shared `resource:<name>` vocabulary (e.g. `resource:gpu` or the same `<resource>` token an `[INTENSIVE — <resource>]` lane tag uses) so a standalone job's claim and the relay's intensive-unit claim collide on the SAME key. (2) wrap `ai-codebench-drain.sh` (and provide a small reusable helper for future standalone intensive jobs) to `claim.sh acquire resource:<name> --run drain-<pid> --mode intensive` for its lifetime and `release` on exit, with the claim's mtime-TTL/PID-liveness covering a crash (a dead drain's claim auto-expires, never wedges the relay). (3) verify the relay's intensive `acquire` collides with the drain's claim (a test or documented manual check: drain holds `resource:gpu`, relay intensive `acquire resource:gpu` → busy → handback, not a second model load). Don't build a new lock — compose existing `claim.sh` (id:ebfb). Relates id:8d52/2147/244b; [[oom-local-model-session-kills]].
  - **Done-check**: tick this checkbox, then `make test` fully green.
  - **Done 2026-06-25** (relay HARD child, id:da26): composed the EXISTING `claim.sh` (id:ebfb) — built NO new lock. (1) `relay/references/resource-claims.md` — the shared `resource:<name>` vocabulary doc (single source both sides read): the resource token MUST be byte-identical to the item's `[INTENSIVE — <resource>]` tag (id:8d52) so the relay's intensive-child `claim.sh acquire resource:<res>` (relay-loop.js ~L1200) and a standalone job's claim COLLIDE on one key; table of `local-llm`/`gpu` tokens; crash-safety via claim.sh mtime-TTL+PID reap. (2) `relay/scripts/acquire-resource.sh <resource> [--run R] [-- ] <cmd…>` — the reusable wrapper for future standalone intensive jobs: acquires `resource:<res>` (mode=intensive), runs the command, and ALWAYS releases on exit (trap EXIT/INT/TERM); bare `--acquire`/`--release` forms for a job that manages its own lifetime; REFUSES (exit 1, no command run) when the resource is busy — exactly the relay-blind second-GPU-load the item exists to prevent. Registered in `relay_FILES`/`relay_EXEC`/`relay_ALLOW`/`relay_LOCAL` + the doc in `relay_FILES` (id:69ef install-completeness). Spec `tests/test_resource_claim.sh` (`# roadmap:a643`) green — incl. the core collision test: standalone holds `resource:gpu` → a relay `acquire resource:gpu` is REFUSED; release → relay acquire succeeds; full suite green. **Residual (NOT this worktree's scope):** the actual one-line wrap of `~/.claude/logs/ai-codebench-drain.sh` lives OUTSIDE this repo (a local un-versioned operator script a relay child cannot commit) — prefix its run with `acquire-resource.sh local-llm --run drain-$$ --` where that file lives. This repo ships the primitive + vocabulary + collision test (acceptance parts 1 + 3 + the reusable-helper half of 2); the per-job wrap is the operator's one-liner.
- [x] [HARD — pool] PID-anchored claim liveness for standalone long jobs + `--pid` adopt for an already-running drain (done 2026-06-25, strong turn) <!-- id:1b11 -->
  - **Why** (observed 2026-06-25, while wiring the a643 drain): a STANDALONE intensive job has NO worktree, so `claim.sh` liveness fell back to mtime-TTL ALONE (1800s/30min) — a multi-hour `ai-codebench-drain.sh` would go stale and be reaped mid-run, so a later `/relay --intensive` would no longer see the held `resource:local-llm` claim and could spin up a second GPU load (the exact a643 hazard, just delayed 30min). And a drain that is ALREADY running can't be wrapped retroactively — there was no way to adopt a running PID into a claim.
  - **Done 2026-06-25** (strong turn): added a THIRD liveness signal to `claim.sh` keyed on a DEDICATED `live_pid` field (NOT the incidental `.pid` = claim.sh's own `$$`): `pid_alive()` (`kill -0`) joins `is_fresh`/`worktree_working` in `is_live`, so a claim with an explicit `--pid` stays live while that process lives (past the TTL) and auto-expires the instant it dies. `acquire` gained `--pid PID`; the field is preserved on re-entrant heartbeat-refresh. `acquire-resource.sh` gained `--pid PID` (adopt an already-running job) and now defaults the wrapped (`cmd`) form's anchor to its OWN `$$` (alive for the command's lifetime under the trap), so wrapped long jobs are durable with no heartbeat. Backward-safe: no `--pid` → empty `live_pid` → zero behaviour change (no PID-reuse exposure on the default path). The running `ai-codebench-drain.sh` (PID 23282) was adopted live: `acquire-resource.sh local-llm --acquire --pid 23282 --run drain-23282`. Spec `tests/test_resource_claim_pid.sh` (`# roadmap:1b11`) green (live-pid survives TTL/steal-refused, peek+reap keep it, dead-pid reapable, no-pid legacy unchanged, acquire-resource adopt); full suite green (103).
  - **Done-check**: tick this checkbox, then `make test` fully green.

- [x] [ROUTINE] Stop discovery shards flailing on the filesystem (no-hunting guard) (done 2026-06-18, reviewer) <!-- id:612f -->
  - **Bug (observed live 2026-06-18):** in a running pool, discovery (a barrier over 6 parallel Sonnet shards) stalled >5 min. One shard hitting a repo with parked `orphan_refs` (dotclaude-skills, 2 refs) improvised instead of using the gather JSON: ran `find /home/tobias -name relay.toml` across ALL of $HOME, cat-ed session transcripts, hand-parsed ROADMAPs — **36 tool calls vs ~9** for a lean shard. Since the round can't proceed until the slowest shard merges, one flailer paced the whole round (and burned extra Sonnet, compounding the discover-on-Sonnet cost, id:c3a6).
  - **Fix (applied directly this turn):** added a NO-FILESYSTEM-HUNTING GUARD to the shard prompt — everything is already in the gather JSON (`toml_block` = the repo's relay.toml block, `roadmap` = its ROADMAP.md, `orphan_refs` = parked refs); the shard must NEVER `find` over $HOME, cat transcripts, or re-derive JSON-provided state; parse the orphan cost-hint runId from the ref basename; surface (don't hunt) on a genuinely-missing field. `node -c` clean; `tests/test_relay_loop_structure.sh` + `test_relay_discovery_guards.sh` + `test_relay_discover_shard.sh` green.
  - **Follow-up (not done):** hoist the per-shard orphan→ROADMAP binding (the `git show --stat` + checkbox resolve, lines ~610–613) into the once-only prelude so shards never touch orphan state at all — bigger refactor, deferred. Add a shard-canary corpus case asserting zero `find`/`cat`-transcript calls.

- [x] [ROUTINE] Normalize nested quota-threshold args in relay-loop.js so a per-bucket override isn't silently dropped <!-- id:b841 -->
  - **Bug (observed 2026-06-18):** the front door / caller passed quota caps as a nested `args.quotaThresholds = {SEVEN_DAY: 0.70, SEVEN_DAY_SONNET: 0.70}` object, but `relay-loop.js` only forwards FLAT keys (`A['RELAY_QUOTA_THRESHOLD_SEVEN_DAY']`, `..._SONNET`) into the gate env (lines ~901–904). The nested object was never read, so a user directive "raise 7d cap to 70%" silently had ZERO effect across two runs — the standing `RELAY_QUOTA_DECAY_7D` cap governed instead.
  - **Fix:** in the args-normalization block (near `const A =`, the same place `fableDown` is normalized), accept a nested `quotaThresholds` map and fold each entry into the corresponding flat `RELAY_QUOTA_THRESHOLD_<BUCKET>` key (flat key still wins if both present). Explicit per-bucket threshold beats the decay (quota-stop.sh §117), so this restores the user's ability to override.
  - **Also:** the SKILL.md front door should translate a "7d cap = X%" phrase into BOTH flat keys (`RELAY_QUOTA_THRESHOLD_SEVEN_DAY` + `_SONNET`), since executor/review children run on the Sonnet bucket. Document the arg shape in the config-knobs table.
  - **Acceptance:** a `tests/test_relay_quota_args.sh` (`# roadmap:b841`) asserting a nested `quotaThresholds` arg produces the same forwarded env as the flat keys. RED until implemented.
- [x] [ROUTINE] Fix relay quota stop-reason bucket attribution (`quota-exhausted:unknown` mislabel) <!-- id:2425 -->
  - **Bug (observed 2026-06-18):** when the gate stops, `relay-loop.js` (~line 936) names the culprit with a hardcoded `(v.buckets||[]).find(b => b.pctRemaining <= 10)` — the old 90%-cap assumption. A stop triggered by a *decayed* or *overridden* threshold below 90% utilization (e.g. `seven_day_sonnet=34% >= 0.3353`) matches no bucket → falls through to `quota-exhausted:unknown`, making real stops look mysterious.
  - **Fix:** have the quota agent / `quota-stop.sh` return the bucket that actually crossed its (possibly decayed/overridden) threshold plus the threshold value, and use THAT for `stopReason` (`quota-exhausted:<bucket>`), instead of the ≤10%-remaining heuristic. Keep the heuristic only as a last-resort fallback.
  - **Acceptance:** a `tests/test_relay_stop_reason.sh` (`# roadmap:2425`) feeding a below-90% decayed-threshold crossing and asserting `stopReason` names the crossed bucket, not `unknown`. RED until implemented.

- [ ] Opus quality-degradation investigation + standing model-probe deliverable [HARD — decision gate] — 🚧 GATED (auto, id:3801; route:human): Closure blocked: id:23e9 seed needs the claude-probe OS user (id:d0c0, useradd/sudo — forbidden for a relay child) + real Opus/Sonnet/Haiku token runs — needs /relay human <!-- id:dba3 -->
  - **Meeting held 2026-06-17** (`docs/meeting-notes/2026-06-17-0836-opus-degradation-investigation.md`). **Investigation expected inconclusive** (n=4 anecdotes, n=1 sessions, no prior baseline — self-anchored prior). Real deliverable = the standing probe. Close this item once id:2d01+c345+040a+23e9 land and the baseline is seeded.
  - **Evidence source:** memory `opus-quality-degradation-20260616.md`; 4 incidents from session `bf9dd9e5` (1213 lines / 2.4M tokens — very long; confound). Key hypotheses: long-context fatigue vs wall-clock duration (idle-gap / KV-cache rot) vs model-serving regression.
  - **Investigation steps (id:903a, e3c0, 241c):** three-axis turn-cluster (`context_depth`, `elapsed_wall_time`, `idle_gap_before_error`) on `bf9dd9e5` + yesterday's last `/relay` session; cold fixed-prompt probe re-posing incidents #2/#3; Anthropic status/version check.
  - **Durable deliverable (id:2d01, c345, 040a, 23e9, 6ffe):** `tools/model-probe.sh` + versioned `tools/model-probe.battery.jsonl` (~15–20 timeless items) + append-only log capturing resolved model-id-str + frontend metadata + tok_per_s; three-tier (Opus + Sonnet + Haiku); pre-registered acceptance band; 2-consecutive-miss alarm. Invocation path GATED on ToS pre-check (id:2d01). Cadence = on-demand seed now, cron deferred.
  - **Billing path REAFFIRMED 2026-06-22:** Anthropic's May plan to move `claude -p` / Agent SDK OFF subscription rate limits onto a dedicated monthly credit is **deferred** (email 2026-06-22 — subscription usage unchanged, advance notice promised before any cutover). Path A's "subscription quota, no per-token billing" rationale (id:2d01) **holds** — no new gate, no decision change; keep path B (API + `--bare`) as the advance-notice hedge. Memory `anthropic-agent-sdk-billing-deferred`; broader evaluation = TODO id:00a5.
  - **Detection rule:** flag only on **2 consecutive** out-of-band runs; tokens/sec is the weak silent-swap hedge (silent same-label swap near-unprovable without baseline; the probe is what makes the NEXT suspicion answerable).

- [x] ⭐ HIGH PRIORITY: cut relay status/overhead cost (~35% of spend, low-concurrency, on the critical path) [HARD — strong model] <!-- id:c3a6 -->
  - **DONE 2026-06-17** (Opus `/meeting`, `docs/meeting-notes/2026-06-17-0721-relay-status-overhead-cost.md`). Two changes, both in `relay/scripts/relay-loop.js` + new `relay/scripts/discover-sig.sh`; `make test` green (62), TDD `tests/test_discover_sig.sh` + `tests/test_discover_cache.sh`.
    - **D1** — pinned `discover-shard` (line 593) to `model:'sonnet'` (was inheriting the Opus session model; sibling prelude already sonnet). Sonnet not haiku: the shard prompt is logic-dense (EXECUTABLE-HARD test, orphan-park precedence) and Haiku is known to misclassify such tasks (`d6-builder-tier-decision`).
    - **D2 (tier audit — SATURATED)**: every other agent is already correctly tiered — work-units (1059–1060) pin execute→sonnet / review+handoff+hard→STRONG_MODEL; prelude+integrator are sonnet (logic-dense, Haiku-fail risk); status/quota/release/gaming are haiku. **No further safe tier downgrade exists.** Do NOT re-open this item to haiku-ify the integrator — that path was rejected with rationale.
    - **D3 (re-discovery redundancy)**: content-addressed discovery cache — `discover-sig.sh` hashes a SUPERSET of every classifier input (HEAD, ckpt tags + latest message, porcelain, upstream ahead/behind, worktree dirs, orphan refs, relay.toml block, ROADMAP hash, in-liveClaims flag); `runRound` reuses last round's verdict for unchanged repos, so an LLM shard fires only on churn. Fail-open (empty/sentinel sig → re-classify).
  - **Forward — D1 attribution RESOLVED (code read, no live data yet)**: `discover-shard`/`discover-prelude` agents carry `phase: 'Discover'` (relay-loop.js:537,627); `profile-run.sh` heuristic (line 140) maps that to `"discover"`; `relay-econ.py` `PHASE_CAT` (line 36) maps `"discover"` → **`"scaffold"`** bucket — NOT `"status"`. The pre-fix Opus spend on shards would show up in the `scaffold` column. Post-fix verification command: `python3 relay/scripts/relay-econ.py --json | python3 -c 'import json,sys; d=json.load(sys.stdin); print("scaffold $",d["cost"]["scaffold"],"| cost_by_model:",d["cost_by_model"])'` then diff scaffold $ and opus share vs prior run. No post-fix pool-run data exists yet — live confirmation still pending. <!-- id:9cb1 -->
  - **Forward — integrator frequency** (NOT tier): CLOSED 2026-06-17 (id:c563) — both levers exhausted: (1) 'skip no-op' lever does not exist (integrate() early-returns before Sonnet agent for null/contract_met=false — all 119 spawned integrators had genuine merges); (2) batching infeasible — per-repo integrations are one-per-round (each branch descends from prior ckpt, median ~100 min span), never co-ready; cross-repo batching reverses line-465 parallel design and worsens recovery for rounding-error sonnet token saving vs Opus-dominated spend. Re-open trigger: same-repo co-ready units in one wave. See meeting note docs/meeting-notes/2026-06-17-0812-relay-integrator-batching-close.md. <!-- id:c563 -->
  - **Evidence** (`relay-econ.py`, 2026-06-16, 5 runs / $633): `status` category = **$220.90 (34.9%)** of cost at only **2.2× mean concurrency** (serial-ish, on the critical path); `work` is $384.84 (60.7%). Model split: opus **78.2%**, sonnet 17%, haiku 4.5%. So a third of spend is overhead, not repo work.
  - **Prime suspect (quick win):** `discover-shard` agents in `relay/scripts/relay-loop.js:593` **omit `model:`**, so they inherit the *session* model — **Opus** when the pool is launched from an Opus session — and discovery **re-runs every round** (DISCOVER_SHARDS=6 × up to MAX_ROUNDS=30). The sibling `discover-prelude` (line 526) doing the same classification IS pinned to `model:'sonnet'`. Pin the shards to sonnet (or haiku) → likely large saving for zero quality loss. Verify the category mapping first (shards are phase `Discover`, not necessarily the econ `status` bucket — re-profile to attribute).
  - **Other leads:** per-repo integrator is a Sonnet agent ~1–2 min each, serialized per-repo (109 integrations on 2026-06-16) — see `relay-loop.js:455`; `RELAY_STATUS` writes + quota gates already run on Haiku off the critical path (line 245, NOT the target — leave them).
  - **Goal:** reduce overhead $ without losing work throughput. Measure before/after with `relay-econ.py`. Quick-win (shard model pin) is executor-sized; the broader "what else can downgrade safely" needs judgment → kept [HARD].
  - **Note:** `relay-burn.sh report` currently has **no samples** (`quota-samples.jsonl` empty) — the $/h-to-reset projection is blind until quota-gate sampling accumulates ≥2 points during a run; worth checking the sampler is actually firing (id:219b).

- [ ] DEFERRED (decided 2026-06-17): Distributed relay orchestrator — multi-machine, dynamic membership [HARD — meeting] <!-- id:de4e -->
  - **Meeting HELD 2026-06-17 — decided DEFERRED on quota economics (do NOT execute, no
    further `/meeting` owed).** Design-gate originally: choose the coordination substrate
    before any code. Captured 2026-06-16 from a working session; the gate was resolved by
    the 2026-06-17 meeting (see D1 below). Relabel per id:9c92 (review 2026-06-18) — the
    old "DECISION GATE / needs a /meeting" heading contradicted the resolved block below.
  - **Why**: leases (`claim.sh`) + `relay.toml` are flock-on-local-dir → single-host
    only, so concurrent `/relay` on zomni+fievel has NO cross-machine mutual exclusion
    (both fully work the same repo; slower one's `--ff-only` push strands). Also lifts
    the `min(16, cores-2)` per-workflow local-parallelism ceiling by spreading across
    machines.
  - **Seed brief** (start the meeting here): `docs/meeting-notes/2026-06-16-2257-distributed-relay-orchestrator-SEED.md`.
  - **⚠️ MEETING HELD 2026-06-17 — D1 constraints (reframed premise, do NOT build now):**
    - **GitHub-as-control-plane / ref-CAS REJECTED.** Serverless is the point; GitHub
      coordination dependency is a no-go.
    - **If ever built:** peer rendezvous (zomni ↔ fievel try to talk directly); if
      unreachable → degrade-to-solo (each assumes it is alone, no quorum). Rare
      split-brain (low-likelihood if both online but cloudflare tunnel fails) caught
      after the fact by `md-merge.py` line-scoped writes + `--ff-only` reject +
      `orphan-scan --cross-ledger`. Optimistic concurrency + merge backstop, NOT CAS.
    - **Deferred reason:** zomni alone exhausted the 7-day→daily quota share 2026-06-16;
      cross-machine throughput is moot until quota economics change.
    - See `docs/meeting-notes/2026-06-17-0953-k3s-parallelity-coordination-design.md`.
  - **Lead candidate**: ~~git-remote-as-control-plane (CAS ref-locks)~~ **REJECTED** —
    see D1 above. Future candidate: direct peer rendezvous + degrade-to-solo.
  - **Related**: id:ebfb / id:0902 (current single-host claim registry),
    `docs/meeting-notes/2026-06-15-1216-relay-dispatch-safety-cluster.md`.

- [x] [ROUTINE] Surface the REAL quota-stop reason in RELAY_STATUS + workflow log (visual feedback) (done 2026-06-15) <!-- id:8c35 -->
  - **Context**: 2026-06-15 — the relaunched pool (run relay-20260615-155151) reported
    `quotaStopped:true` and a big queued-not-dispatched backlog, but it had NOT hit any quota
    bucket (5h 43% / 7d 55% / Sonnet 81% remaining, all far from the 90%-used threshold). The
    real cause, only found by grepping the workflow log, was `quota-stop: cache stale (1404s >
    600s limit) and self-refresh unavailable/failed` — the conservative stale-cache-can't-refresh
    seatbelt (the `/api/oauth/usage` endpoint 429s aggressively). A refresh-failure stop and a
    real-exhaustion stop are reported IDENTICALLY ("quotaStopped"), making the stop opaque.
  - **Why**: user directive 2026-06-15 — "really needs more visual feedback". An operator should
    see WHY the pool stopped without grepping transcripts.
  - **Acceptance**: relay-loop.js's quotaGate captures the quota-stop verdict CATEGORY and detail
    (real exhaustion: which bucket + headroom%, vs stale-cache/refresh-failure vs seatbelt/budget)
    and (a) `log()`s it as the drain reason, and (b) writes it into RELAY_STATUS.md (e.g. a
    `## Stop reason` line or annotating the existing `## Quota remaining` section). The returned
    run result distinguishes `stopReason: "quota-exhausted:<bucket>" | "quota-stale-cache" |
    "budget" | "drained" | "max-rounds"`. quota-stop.sh already returns exit 2 for
    uncertain/stale vs exit 1 for at/above-threshold — surface that distinction instead of
    collapsing both to "quotaStopped". Hermetic test asserting the stale-cache path yields the
    stale-cache reason, not a bucket-exhaustion reason.
  - **Spec / red test**: `tests/test_relay_quota_stop_reason.sh` (`# roadmap:8c35`) — static-structural
    (matching `test_relay_loop_structure.sh`): asserts quotaGate branches on quota-stop.sh exit 2
    (stale-cache) vs exit 1 (exhaustion) instead of collapsing both to `quotaStopped`; a `stopReason`
    field is captured in the run result with the category vocabulary (`quota-stale-cache`,
    `quota-exhausted:<bucket>`); the drain-reason `log()` names the category; and RELAY_STATUS
    surfaces the stop reason alongside the existing `## Quota remaining` section. RED until implemented.
  - **Done-check**: `tests/run-tests.sh tests/test_relay_quota_stop_reason.sh` then full `make test`
    after ticking.

- [x] [ROUTINE] Harden relay-state-write.sh toml-set against awk -v / regex-key input (F1/F2) (done 2026-06-15) <!-- id:c8db -->
  - **Source**: id:401c strong-model audit 2026-06-15 (`docs/meeting-notes/2026-06-15-1520-strong-model-audit.md`),
    findings F1 + F2. Re-filed after the audit's own commit was discarded (stale base) — see that note's provenance header.
  - **F1**: `toml-set` passes the value via `awk -v val="$value"`, and awk's `-v` processes
    C-style backslash escapes — a value containing `\` would be silently mangled before it hits
    the file. **F2**: `key` is spliced into an awk *regex* (`kre="^" key "[ \t]*="`); a key with
    regex metacharacters would match/replace the wrong line.
  - **Risk today: zero** — every caller (relay-loop.js integrate step 6) passes only checkpoint
    tags, ISO dates, and bare tokens (`false`/`"active"`/`"handed-off"`); keys are fixed TOML
    identifiers. This is forward-robustness so a future caller passing an arbitrary value/key
    can't be corrupted. Low priority.
  - **Acceptance**: `toml-set` writes the value without awk `-v` escape processing (e.g. pass via
    env/ARGV or a literal-safe mechanism) and matches the key by literal compare (not regex);
    a test feeds a value with a backslash and a key-shaped edge and asserts a faithful round-trip.

- [x] [ROUTINE] Resolver pushes unblocked work to the pool via inject.sh (low-latency REVIEW_ME pickup) (done 2026-06-15) <!-- id:fb75 -->
  - **Context**: 2026-06-15 user observation — a parallel `/relay human` session resolved most
    REVIEW_ME boxes, but the running pool only reacts at its next discovery **round boundary**
    (after the current wave integrates), so a resolution that unblocks pool work waits minutes.
    The inject path already exists (id:baf1: `inject.sh add/take`, `inject.d/` inbox, injected
    units outrank every verdict class + skip the quota gate). Push beats watch here: the resolver
    knows *exactly* what it unblocked, so it should hand that item to the pool directly rather
    than have the pool (or an inotify watcher) re-derive it. (inotify rejected — the pool is a
    deterministic Workflow that can't consume an inotify event mid-run; a watcher→inject bridge
    is strictly more than calling inject.sh at resolution time, and fires on every blind tick.)
  - **Spec / red test**: `tests/test_relay_resolution_inject.sh` (`# roadmap:fb75`). It asserts
    `references/human.md` §5 write-back: (1) calls `inject.sh add`, (2) conditioned on the
    resolution UNBLOCKING pool work (not every tick), (3) passes `--item <id>` (targets the
    unblocked item, not a blind repo re-classify), (4) REUSES the existing id (single-id-two-views,
    no duplicate mint).
  - **Acceptance**: edit `references/human.md` §5 (and note the same step for the `/meeting`
    REVIEW_ME write-back, id:15d5) so that after a clean lease-held write-back that ticks a box
    unblocking a gated/blocked ROADMAP item, the resolver runs
    `~/.claude/skills/relay/scripts/inject.sh add <repo> --item <id> --verdict execute` (only when
    it unblocks work). Then `make test` green (fb75 ticked). No relay-loop.js change — this is the
    resolver contract only; the within-round-latency lever is id:6e9d.

- [x] [HARD — strong model] Freed lane pulls injections mid-round (free-slot immediacy, no round-boundary wait) (done 2026-06-15) <!-- id:6e9d -->
  - **Context (corrected 2026-06-15)**: the dispatch core is ALREADY a free-slot worker pool —
    `parallel()` spawns POOL_WIDTH lanes each looping `queue.shift()`, and there is precedent for
    pushing onto the LIVE queue mid-round (the review→execute re-enqueue at ~L782). The real gap:
    injections enter the queue ONLY at round-start discovery (`inject.sh take` runs inside the
    discovery agent). A lane that empties `queue` then EXITS (its `while (queue.length)` condition),
    so a freed slot idles until the round ends — and the round ends only when the SLOWEST current
    unit finishes. So a mid-round injection waits for unrelated long units (user report 2026-06-15:
    "injection should trigger when a slot is free, not wait for irrelevant tasks").
  - **Key constraint**: the Workflow script CANNOT run shell itself — `inject.sh take` only runs
    inside an `agent()`. So a lane cannot poll `inject.d` directly; it must spawn a tiny take-agent.
  - **Design (poll-once-on-drain, the cheap Pareto fix)**: when a lane finds `queue` empty (would
    otherwise exit), it spawns a small `inject.sh take` agent (resolves repo path via relay.toml
    `# path:`, returns injected unit objects). If it yields units → push onto the live `queue` +
    continue (the freed lane runs them immediately). If empty → the lane exits as today. So an
    injection is caught the moment the NEXT lane frees with the queue drained — for a cycling
    multi-unit pool that is ~one short-unit latency, vs. today's "wait for the whole round + integ
    drain + re-discovery". It does NOT preempt a running agent (impossible).
  - **Known residual (explicitly out of scope, by design)**: if ALL lanes are simultaneously busy
    on long units (e.g. end-of-backlog lone long tail), freed lanes have already exited, so the
    injection is caught only when that tail unit finishes → the round ends → the outer loop
    re-discovers (sub-second) and `take`s it. Fully closing that needs a poll-WHILE-busy lane, which
    taxes EVERY round's tail with repeated take-agents whether or not an injection ever arrives — a
    bad default (most rounds have no injection). Not taken; the poll-once fix is a strict
    Pareto-improvement (never worse than today, usually much better) without that standing cost.
  - **Races handled**: two lanes draining together both spawn take-agents — `inject.sh take` is
    atomic/flock'd, so each shard goes to exactly one lane (the other gets empty → exits; no loss).
    No busy-spin: a lane spawns the take-agent only when it would otherwise EXIT (queue empty), not
    every iteration. MAX_UNITS/quota gates still bound dispatch.
  - **Spec / red test**: `tests/test_relay_midround_inject.sh` (`# roadmap:6e9d`). Static-structural
    (matching test_relay_loop_structure.sh): assert relay-loop.js has a mid-round injection pickup
    (a take-agent spawned from the lane drain path, carrying `id:6e9d`), distinct from the
    discovery-time take. RED until implemented.
  - **No longer deferred**: user directive 2026-06-15 — free-slot immediacy is the wanted behavior,
    not a measure-first nicety. Complements id:fb75 (resolver pushes) — fb75 enqueues the unblocked
    item, 6e9d makes a free slot pull it without round-boundary latency.

- [x] relay-loop.js must auto-reap stale worktrees from dead runs (not treat them as in-flight) (done 2026-06-15) <!-- id:3ac8 -->
  - **Context**: observed 2026-06-15 — two crashed morning runs (`relay-…-1104-hard`,
    `relay-…-1152-hard`) left 17 worktrees on disk under `~/.cache/fables-turn/worktrees/`
    with NO live `claim.sh` shard. Discovery's worktree-aware guard (id:c3f7) treats a
    worktree directory's mere existence as "in-flight elsewhere — claimed by another relay
    run", so a later pool falsely SKIPPED 14 repos (all the HARD-eligible ones) and starved
    itself. `claim.sh` explicitly defers this case: "handback nuance for stale-with-live-worktree
    is the relay-loop's job, not this." The loop isn't doing it.
  - **Why HARD**: must distinguish a *dead-run* stale worktree (no live claim + claim/worktree
    mtime past TTL) from a genuinely live foreign-runId worktree, AND must NOT blind-prune — a
    worktree can hold an unmerged handback commit (RELAY_LOG/REVIEW_ME notes; 2 of the 17 did).
    Reconcile-then-reap: integrate any commits ahead of main (ff/union path) before removing.
  - **Acceptance**: relay-loop.js discovery, before classifying a repo "in-flight elsewhere",
    checks for a FRESH `claim.sh` shard; if none and the worktree branch is `--is-ancestor` of
    main (empty), prunes it + deletes the branch; if it carries commits ahead, surfaces it as a
    HANDBACK needing integration (never silently dropped). Hermetic test in `tests/` with a
    seeded stale worktree + empty claim registry asserting the repo is freed, not skipped.
  - **Manual cleanup already done 2026-06-15** (this is the durable fix): the 17 worktrees were
    hand-reaped, the 2 handback commits (rawrora id:9029 REVIEW_ME box, zkm-notmuch id:f103 log)
    ff-merged to main and pushed first.

- [x] Interactive relay modes (handoff/review/human) are claim-aware (done 2026-06-15) <!-- id:0902 -->
  - **Context**: post-cluster gap — the autonomous pool (id:ebfb), `/relay executor` (contract v4),
    and `/meeting` (id:d748) took the cross-session lease, but the INTERACTIVE orchestrator modes
    (`/relay handoff|review|human`) were claim-blind, so `/relay human --all` (or two `/relay review`s)
    could still collide with a live pool on shared ledgers / main checkouts.
  - **Done 2026-06-15**: SKILL orchestrator invariant 4 acquires `claim.sh acquire <repo> --run
    relay-<mode>-$CLAUDE_SESSION_ID` before fanning out each handoff/review child (refused → skip +
    surface, never spawn a colliding child); invariant 5 releases it run-scoped at integration.
    `references/human.md` §5 acquires the lease before each per-repo REVIEW_ME/ledger write-back and
    DEFERS on refusal (mirrors `/meeting` id:d748), releasing after. `tests/test_relay_interactive_claim.sh`.
    Every relay actor — pool, executor, meeting, and the interactive modes — now respects one lease.
  - **Concurrent-pool fix (same commit)**: the discovery runId was minute-granular
    (`relay-YYYYMMDD-HHMM`) — two no-args/`--all` pools started in the same minute shared a runId, so
    the lease's same-run re-entrancy AND the worktree-aware guard both false-passed → double-work. runId
    is now per-run unique (`relay-$(date +%Y%m%d-%H%M%S)-$RANDOM`), so two concurrent pools never collide.

- [x] Relay must sync local↔origin before working a repo (stale-clone / divergence guard) (done 2026-06-15) <!-- id:c3f7 -->
  - **Done 2026-06-15**: discovery SYNC-WITH-ORIGIN guard (fetch + ahead/behind; diverged→surface,
    behind-only→ff) in relay-loop.js; `relay/scripts/sync-origin.sh` testable helper (exit 0 ok/ff/
    no-upstream, 2 behind, 3 diverged) with a hermetic functional 2-clone test
    `tests/test_relay_sync_origin.sh`; integrator belt-and-suspenders calls sync-origin.sh and aborts
    on a diverged base (`tests/test_relay_discovery_guards.sh`). The ai-codebench incident cannot recur.
  - **Context**: 2026-06-15 near-catastrophe. The pool worked ai-codebench on a LOCAL clone that
    had been ~1 month behind origin (stale since 2026-05-13, missing 106 commits incl. the live
    GPU session done on zomni). Discovery classifies purely from LOCAL git state and never fetches,
    so for DAYS the pool built a doomed parallel relay timeline (9+ checkpoints) on the stale base
    that could never push (`--ff-only` correctly refused) — wasted work + divergence. A force-push
    "fix" would have destroyed the 106 origin commits. Fixed manually (reset local→origin, purged
    9 dangling stale-timeline tags, corrected relay.toml last_ckpt).
  - **Acceptance**: discovery (or a pre-dispatch step) runs `git -C <path> fetch origin` and compares
    local main to `origin/main`: (a) up-to-date → proceed; (b) behind & clean & no local-unique
    commits → fast-forward, then classify; (c) DIVERGED (local-unique AND origin-unique commits) →
    do NOT work it — surface in RELAY_STATUS "Blocked: <repo> diverged from origin (local N / origin M)
    — needs manual reconcile", never commit on top. Dirty tree still blocks as today. The integrator
    must also never create a checkpoint/commit on a base behind origin. Hermetic test with two scratch
    clones (behind→ff; diverged→surface).
  - **Pairs with**: server-side hardening — **APPLIED 2026-06-15**: `git config --global
    receive.denyNonFastForwards true` + `receive.denyDeletes true` on fievel, so any force/purge push is
    now server-rejected. A controlled-override path (for the user's occasional legitimate force-push) is
    tracked as TODO id:de51 (gerrit is overkill for a Pi).

- [x] Relay claim-registry + cross-session safety (cluster steps 1–4 + executor + single-writer) (done 2026-06-15) <!-- id:ebfb -->
  - ROADMAP execution view of TODO id:ebfb (single-id-two-views). Ratified design:
    `docs/meeting-notes/2026-06-15-1216-relay-dispatch-safety-cluster.md`.
  - **Shipped 2026-06-15**: (1) discovery WORKTREE-AWARE (skip a foreign-runId worktree → surfaced) +
    SYNC-WITH-ORIGIN guard (id:c3f7) in relay-loop.js — `tests/test_relay_discovery_guards.sh`;
    (2) `relay/scripts/claim.sh` — per-shard flock'd registry (`acquire`/`release`/`peek`/`reap`,
    mtime+TTL, resource-key safe; **same-run re-entrant**, **run-scoped release**) —
    `tests/test_relay_claim.sh`, registered in the Makefile;
    (3) **claim wired into the dispatch path (step 4)** — work children `claim.sh acquire <repo> --run
    <runId>` FIRST (refused → stop + "claimed by another relay run" handback); the integrator
    `claim.sh release <repo> --run <runId>` run-scoped; `writeRelayStatus` projects live claims via
    `claim.sh peek` into a `## Claims (live)` section — `tests/test_relay_claim_wiring.sh`.
  - **Also done 2026-06-15**: (4) `/relay executor` honors the lease — executor-contract **v4** rule 0
    (`claim.sh acquire/release`, markers synced across executor-contract.md / CLAUDE.md / conventions.md,
    `tests/test_relay_executor.sh`). Sibling cluster items `[INTENSIVE]` (id:8d52) + `/meeting` hold
    (id:d748) shipped.
  - **Also done 2026-06-15**: (5) cluster **step 2 — flock'd single-writer state**: `relay/scripts/
    relay-state-write.sh` (`toml-set <repo> <key> <value>` field-scoped + `status-write <abs-path>`,
    both flock'd + atomic temp-mv; `tests/test_relay_state_write.sh`). The integrator writes every
    relay.toml field via `toml-set`; `writeRelayStatus` writes via `status-write` — concurrent runs
    serialize on one lock, no torn/clobbered writes. (Per-runId RELAY_STATUS *display* sections were not
    needed — flock'd-atomic single-writer + the claim lease serializing per-repo work cover the cases.)
    All cluster steps 1–6 + executor-honoring + single-writer now shipped.

<!-- DESIGN CLUSTER: "safe concurrent + resource-aware relay dispatch" — RATIFIED 2026-06-15
     (meeting docs/meeting-notes/2026-06-15-1216-relay-dispatch-safety-cluster.md). The claim
     primitive + per-repo lease REUSE existing TODO id:ebfb (claim/reservation umbrella: worktree-
     aware discovery + single-writer relay.toml/RELAY_STATUS + per-shard claim registry) and id:3558
     (flock'd-merge = repo-lease enforcement). id:7b7a & id:8ac5 RETIRED as duplicates. Kept new:
     id:8d52 ([INTENSIVE], rescoped to claim-on-resource + run-alone), id:d748 (/meeting hold),
     id:baf1 (on-demand task injection). Build cheapest-first; dry-stall deferred+observe. -->

- [x] Task-claim primitive — RETIRED 2026-06-15: duplicate of TODO id:ebfb. The PM-board "claim" framing + per-shard registry (`~/.config/fables-turn/claims/<key>.json`) + item-keyed/repo-enforced design is ratified in `docs/meeting-notes/2026-06-15-1216-relay-dispatch-safety-cluster.md` and tracked under id:ebfb (claim/reservation) + id:3558 (flock'd-merge = repo-lease). <!-- id:8ac5 -->

- [x] Cross-session relay dispatch safety — RETIRED 2026-06-15: duplicate of TODO id:ebfb + id:3558. Worktree-aware discovery, single-writer relay.toml/RELAY_STATUS, claim registry → id:ebfb; per-repo lease enforcement → id:3558. Ratified design: `docs/meeting-notes/2026-06-15-1216-relay-dispatch-safety-cluster.md`. <!-- id:7b7a -->

- [x] `[INTENSIVE — <resource>]` tag: gate local-LLM/heavy work behind explicit permission (done 2026-06-15) <!-- id:8d52 -->
  - **Done 2026-06-15**: mechanism (discovery parse + never-auto-dispatch gate + `--allow-intensive`/
    `--afk` + serial run-alone + exclusive `resource:<name>` claim — `tests/test_relay_intensive.sh`)
    AND the tagging-criteria doc in `references/conventions.md` (when strong children tag
    `[INTENSIVE — local-llm]`, citing the OOM + TTFT — `tests/test_relay_intensive_criteria.sh`).
    Operational note: seed the coarse per-repo `intensive = "local-llm"` default into ai-codebench /
    zkm relay.toml blocks when convenient (skipped here — relay.toml was under concurrent write; the
    mechanism reads the flag if present, item-level tags override).
  - **Context**: 2026-06-15 user request. Local-LLM tasks (ai-codebench benchmarks, zkm embedding
    index) hammer GPU/RAM — memory `oom-local-model-session-kills`: Gemma 26B killed all 6 sessions;
    ~57s cold TTFT (cf id:642f). Run-1 already handed these back ad hoc ("hardware-gated for an
    unattended relay turn… never an unattended relay child" — zelegator id:462c, linguistic-unversals
    id:3071). This makes it a first-class, deterministic tag instead of per-child judgment.
  - **Shape**: a resource modifier ORTHOGONAL to the verdict axis (NOT a replacement for
    `[ROUTINE]`/`[HARD]`), two-part like the HARD tags so the gate knows which resource:
    `[ROUTINE] [INTENSIVE — local-llm]`, `[HARD — strong model] [INTENSIVE — local-llm]`.
  - **Acceptance**: (1) discovery parses the modifier; an `[INTENSIVE]` unit is NEVER auto-dispatched
    by the default unattended pool — surfaced in RELAY_STATUS "Queued — needs explicit permission"
    (extends `feedback-relay-unattended-default`: never run resource-doomed work unasked). (2) Global
    resource semaphore `~/.cache/relay/resources/<resource>.lock` — at most one local-llm task
    at a time; conservative default = it RUNS ALONE (pool pauses new dispatch / forces POOL_WIDTH=1
    while held) — this is the actual OOM fix. (3) Opt-in to run them: `/relay --allow-intensive`
    (flag) and an **AFK mode** `/relay --afk [duration]` ("I'm away, do something useful" — drains
    light work, then chews intensive items one-at-a-time within a time/quota budget, reports back).
    (4) Tagging: strong children tag per criteria in `conventions.md` (cite OOM + TTFT), PLUS a coarse
    per-repo default `[repos.ai-codebench] intensive = true` / `[repos.zkm] intensive = true` as a
    safety net; item-level tags override.
  - **RATIFIED 2026-06-15** (meeting 2026-06-15-1216): `[INTENSIVE — <resource>]` is a **claim on a
    resource key** (`~/.config/relay/claims/resource:local-llm.json`), exclusive; while held
    collapse `POOL_WIDTH→1` (RUN ALONE — the OOM fix); never auto-dispatched without `--allow-intensive`
    / `--afk`. Reuses the id:ebfb claim machinery — NOT a separate `resources/*.lock` semaphore (the
    earlier acceptance text above is superseded by this). Build step 5 of the cluster sequence.
  - **Shipped 2026-06-15 (mechanism)**: relay-loop.js — discovery reports `intensive` (resource
    string) from the `[INTENSIVE — <resource>]` item modifier OR a relay.toml `intensive` flag;
    `--allow-intensive`/`--afk` gate (`args.allowIntensive`, SKILL.md knobs); intensive units are
    PARTITIONED out of the parallel wave (never auto-run — surfaced "needs --allow-intensive") and,
    when allowed, run in a SERIAL run-alone phase after the wave, each holding an exclusive
    `resource:<name>` claim (acquire in unitPrompt, release in integrator). `tests/test_relay_intensive.sh`.
  - **Remaining (item stays open)**: the tagging *criteria* doc — `references/conventions.md` /
    handoff.md guidance for strong children on WHEN to tag an item `[INTENSIVE — local-llm]`
    (cite the OOM + ~57s TTFT facts) — plus seeding the coarse per-repo `intensive` defaults in
    relay.toml for ai-codebench / zkm.

- [x] `/meeting` ↔ relay-loop mutual hold (holdable meeting while a pool is live) (done 2026-06-15) <!-- id:d748 -->
  - **Shipped 2026-06-15**: `meeting/SKILL.md` step 2a "Relay-pool claim hold" — before the 2b/2e
    shared-ledger write-back (relay-managed repos only), `/meeting` acquires the repo claim
    (`claim.sh acquire <repo> --run meeting-<session> --mode meeting`), does the write + releases;
    on refusal (a live pool holds it) it DEFERS the write-back (the meeting note already records the
    decisions) and never forces a write under a live pool claim. Read/think + the note are never
    blocked. `tests/test_meeting_claim_hold.sh` (`# roadmap:d748`). Reuses the id:ebfb claim registry.
  - **Context**: 2026-06-15 user request. `/meeting` writes the shared ledgers (TODO/ROADMAP/REVIEW_ME)
    in the MAIN checkout while the relay pool merges worktree branches into the same files (D2
    single-id-two-views; CLAUDE.md already notes md-merge.py + `orphan-scan.sh --cross-ledger` for
    residual drift). A meeting started mid-pool can collide at integration. Need a mutual-hold so the
    two actors don't write the shared ledgers concurrently.
  - **Acceptance (design)**: decide the yield direction — (a) `/meeting` detects a live pool (lease/
    runlock from id:7b7a) and HOLDS/queues its ledger writes until a safe point, or (b) the pool
    yields a short window to an interactive meeting, or (c) both coordinate via the same per-repo lease
    keyed on dotclaude-skills. Likely reuses id:7b7a's lease + single-writer helper rather than a
    separate mechanism. Must keep meeting's read/think phase unblocked (only the WRITE-BACK holds).
  - **RATIFIED 2026-06-15** (meeting 2026-06-15-1216): `/meeting` is a **consumer of the id:ebfb claim
    registry** — it holds (or takes) the dotclaude-skills claim for its ledger WRITE-BACK only; read/think
    phase stays unblocked. Build step 6 (last). Reuses the claim machinery; no parallel lock.

- [x] Relay integrator bottleneck — per-repo serialization, cross-repo concurrency (done 2026-06-15, reviewer) <!-- id:bc9d -->
  - **Context**: 2026-06-15 — investigating "the pool only runs ~1-wide". Work agents
    (review/execute/hard) DO run concurrently (harness cap `min(16, cores-2)`; I/O-bound API
    calls, no mutual block). The apparent serialism was the **single global integrator**
    (`integrationChain` promise chain, relay-loop.js): every repo's integration ran one-at-a-time,
    and each is a full Sonnet agent running 4 deterministic commands (merge --no-ff → ckpt-tag.sh
    → git-lock-push.sh → worktree prune), ~1–2 min each. Checkpoints are stamped at integration,
    so tags landed ~1–2 min apart no matter how wide dispatch was — that even spacing is what
    *looked* like a 1-wide pool. (The per-unit quota-agent throttle in 82a2dda was a separate,
    minor win, NOT this.)
  - **Fix shipped**: replaced the single `integrationChain` with a per-repo chain map
    (`integrationChains: Map<repo, tailPromise>`, `enqueueIntegration(repo, fn)`). Same-repo
    integrations still serialize (preserving review→execute re-chain ordering into one main
    checkout); DISTINCT repos integrate concurrently — distinct remotes don't conflict, and
    git-lock-push.sh still flocks per-repo for the residual same-remote case. This restates the
    D5/D6 invariant from "one concurrent integration per POOL" to "one per REMOTE", which is the
    only thing safety actually requires. Checkpoint throughput now scales with dispatch width.
  - **Tests**: `tests/test_relay_integrator_per_repo.sh` (`# roadmap:bc9d`) — no global
    integrationChain; enqueueIntegration keyed by repo; per-repo map get/set; drain awaits all
    chains; integration still not wrapped in parallel(). `test_relay_loop_structure.sh` (3)
    updated to the per-repo assertion.
  - **Follow-up (deferred, not blocking)**: integration agent could be Haiku and/or BATCH several
    repos per call to further cut the ~1–2 min/repo agent overhead — left for a later pass; the
    per-repo concurrency above is the primary throughput lever.

- [x] On-demand high-priority executor-task injection into the running pool [ROUTINE] (done 2026-06-15) <!-- id:baf1 -->
  - **Shipped 2026-06-15**: `relay/scripts/inject.sh` (`add`/`peek`/`take`, flock'd per-shard
    inbox `~/.config/relay/inject.d/`, consumed → `inject.done/`). relay-loop.js discovery
    runs `inject.sh take`; injected units carry `injected:true` + `inject_token`/`inject_item`/
    `inject_prompt`, sort AHEAD of every verdict class (both the normal and `--fable-down`
    schedulers), and SKIP the quota gate (explicit user request). Makefile + allowlist registered
    (id:5f09 lesson). `tests/test_relay_inject.sh` (`# roadmap:baf1`) green. Usage:
    `inject.sh add <repo> [--item <id>] [--verdict execute] [--prompt "…"]` — picked up next round.
  - **Deferred follow-ups (not blocking)**: RELAY_STATUS `peek` projection of pending injections;
    within-round latency (a lane re-checking `inject.d` between units — MVP is next-round-boundary).
  - **Context**: 2026-06-15 user request — "inject this executor task next with highest priority."
    A live control-plane: drop a task and the running pool picks it up ahead of its normal
    verdict-class schedule (execute→review→hard→handoff, id:da26) on the next round.
  - **Design (rides the cluster registry pattern, id:ebfb)**: an **injection inbox** the pool
    polls at each round's discovery — per-shard files `~/.config/relay/inject.d/<token>.json`,
    each one unit spec `{repo, item_id?, verdict (default execute/sonnet), prompt?, requested_at}`.
    A flock'd allowlisted helper `inject.sh <repo> [--item id] [--verdict execute] [--prompt ...]`
    writes the shard (so a human/other session enqueues without hand-editing JSON). Discovery reads
    inject.d at round start, converts each to a unit, and the scheduler places injected units at the
    FRONT of the queue (ahead of the class order). **Consume-once**: dispatched → shard moved to
    `inject.done/` (reuse the claim machinery so it isn't re-injected every round). Surface injected
    units in RELAY_STATUS.
  - **Open (minor, decide at build)**: latency = next round-boundary (MVP) vs within-round (a lane
    re-checks inject.d between units); injectable verdicts (execute-only vs any); always-top vs a
    priority field. Does NOT need a full /meeting — it's a contained extension of the ratified
    registry pattern (`docs/meeting-notes/2026-06-15-1216-relay-dispatch-safety-cluster.md`).
  - **Why ROUTINE-with-care**: additive, but it touches the dispatch/PRIORITY ordering — reviewer
    should confirm an injected unit never starves the D3 review-after-execute invariant.
  - **Tests**: `tests/test_relay_inject.sh` — inject.sh writes a valid shard; discovery prepends it;
    consumed shard moves to inject.done and isn't re-dispatched. Hermetic.

- [x] Contract tests for relay install-completeness + quota-stop invocation (done 2026-06-15) <!-- id:5f09 -->
  - **Done 2026-06-15**: `tests/test_relay_install_manifest.sh` — (1) every `relay/scripts/*` is in
    the Makefile `relay_FILES` (and every `.sh` in `_EXEC`/`_ALLOW`), so a new helper can't ship
    un-symlinked; (2) relay-loop.js invokes `quota-stop.sh` with only its accepted flags
    (`--tier`/`--agents`/`--wall`, no bare positionals). Both 2026-06-15 contract gaps are now gated.
  - **Context**: On 2026-06-15 the default `/relay` autonomous pool was non-functional and
    the full suite was green. Two contract bugs shipped undetected: (1) the Makefile
    `relay_FILES`/`_EXEC`/`_ALLOW` lists omitted `scripts/quota-stop.sh` and
    `scripts/relay-loop.js`, so `make install` never symlinked the Workflow engine or the
    quota helper agents invoke by installed path; (2) `relay-loop.js`'s `quotaGate()` called
    `quota-stop.sh --tier T <agents> 0` with bare positionals, but the script only accepts
    `--tier/--agents/--wall` and exits 2 on anything else — tripping the fail-safe STOP on
    every gate check. Fixed in 5481502; tests did not catch either.
  - **Acceptance**: (1) a test asserts every `relay/scripts/*` file appears in the Makefile's
    `relay_FILES` (and every executable `.sh` in `relay_EXEC`/`relay_ALLOW`), so a new helper
    can't ship un-symlinked; (2) a test asserts the `quota-stop.sh` invocation string embedded
    in `relay-loop.js` uses only flags `quota-stop.sh` actually parses (`--tier/--agents/--wall`)
    — ideally by extracting the command and dry-running it, else by static flag-set match.
  - **Tests**: extend `tests/test_relay_loop_structure.sh` (quota-stop invocation) and add a
    Makefile-manifest check (new `tests/test_relay_install_manifest.sh` or fold into an existing
    install test); header `# roadmap:5f09`.
  - **Done-check**: tick this box, then full `make test` green.

- [x] De-fable checkpoint tags + durable model-tracked Fable-bonus-recheck queue [HARD — strong model] (done 2026-06-15, reviewer; merges id:e030) <!-- id:96a8 -->
  - **Acceptance**: `relay/scripts/ckpt-tag.sh` emits `relay-ckpt-YYYYMMDD-HHMM` annotated
    tags (not `fable-ckpt-*`); the RELAY_LOG.md append + the model+role annotation label are
    unchanged; existing `fable-ckpt-*` tags are never rewritten. `relay/scripts/relay-loop.js`
    finds the latest checkpoint / commit range / standin by matching BOTH prefixes
    (`git tag -l 'fable-ckpt-*' 'relay-ckpt-*' | sort | tail -1`), so a repo whose `last_ckpt`
    is still `fable-ckpt-*` keeps working across the boundary. `integrate()` writes a durable,
    model-tracked Fable-bonus-recheck queue into relay.toml on a STRONG (review/handoff/hard)
    checkpoint — `last_strong_ckpt`, `strong_model`, `fable_rechecked` — which an executor
    (sonnet) checkpoint never clears (masking fix, id:e030); the id:9821 elevation consults
    `strongRecheckPending` (un-rechecked strong ckpt) as an OPTIONAL, non-gating recheck
    candidate. The three relay.toml fields are documented in `relay/SKILL.md` (State) and
    `relay/references/conventions.md`.
  - **Tests**: `tests/test_relay_tag_scheme.sh` (`# roadmap:96a8`) — ckpt-tag.sh emits a
    `relay-ckpt-*` tag (hermetic run), label/RELAY_LOG unchanged; relay-loop.js dual-prefix
    matching + the three relay.toml fields + the strongRecheckPending consume wiring; docs
    mention the fields.
  - **Done-check**: `tests/run-tests.sh tests/test_relay_tag_scheme.sh` then full `make test`.

- [x] `/fables-turn human` mode — cross-repo human-backlog triage (the human as 3rd actor) [ROUTINE] (done 2026-06-15, reviewer) <!-- id:2892 -->
  - **Acceptance**: `fables-turn/SKILL.md` documents a `human` mode — the invocation
    block carries `/fables-turn human [repo-list | --all]`, a `## Human mode` section
    describes the 3-tier triage and points at `references/human.md`, frames Opus as apex,
    and notes it generalizes the planned `review_me`. `references/human.md` exists and
    specifies the 3 tiers (AUTO-ANSWERABLE / BATCH-DECIDABLE / CHEWY), the
    `@manual`-never-auto-tick rule, and the tier-C → `/meeting --cross` routing.
    `scripts/gather-human-backlog.sh` is a read-only helper (`set -euo pipefail`, optional
    repo args, hermetic via `SRC_DIR`/`RELAY_TOML` overrides) that scans relay.toml `own`
    repos' `REVIEW_ME.md` for open `- [ ]` boxes and emits a TSV
    (`repo path kind box_summary`, `kind=review_me|manual`), flagging `@manual` boxes
    (REVIEW_ME and ROADMAP) as `kind=manual`; closed `- [x]` boxes are never emitted. The
    helper joins the Makefile `fables-turn` FILES/EXEC/ALLOW.
  - **Tests**: `tests/test_fables_human.sh` (`# roadmap:2892`) — SKILL.md documents the
    mode + invocation; references/human.md exists and specifies the 3 tiers +
    @manual-never-auto-tick + tier-C→/meeting --cross; gather-human-backlog.sh emits the
    TSV and flags @manual (hermetic fixture).
  - **Done-check**: `tests/run-tests.sh tests/test_fables_human.sh` then full `make test`
    after ticking.
  - **Context**: TODO id:72cc — codifies a hand-run procedure. Interactive strong-turn
    PROCEDURE (uses AskUserQuestion, so NOT a Workflow); mirrors handoff.md/review.md as
    reference-doc procedures. Per-repo commit in the main checkout (the /meeting REVIEW_ME
    write-back path, id:15d5), not a worktree merge. Opus is apex; an auto-answer is a
    CLAIM the next review re-checks (anti-gaming, downgrade a→b when unsure).

- [x] HARD-execute verdict + tested Fable-probe cache helper for the autonomous pool [HARD — strong model] (done 2026-06-15, reviewer) <!-- id:da26 -->
  - **Why HARD**: touches the dispatch contract in relay-loop.js (a new verdict class
    with an apex-only gate that must never leak HARD work onto the Sonnet execute tier),
    and the steady-state scheduling invariant. Wrong gating dispatches a doomed strong
    unit on Fable, or — worse — runs unbounded HARD work on Sonnet.
  - **Acceptance**: relay-loop.js gains a `hard` verdict (in DISCOVER_SCHEMA's enum +
    an `openHard` count). The classifier emits `hard` when a repo has NO unaudited
    commits, NO open `[ROUTINE]`, but ≥1 open `[HARD` item (precedence
    review > execute > hard > handoff > idle). `PRIORITY = { execute:0, review:1, hard:2,
    handoff:3 }`. A `hard` unit is DISPATCHED only when `STRONG_MODEL === 'claude-opus-4-8'`
    (apex); on Fable / the `-d` defer path it is left for Fable handoff-C5/review-step6 and
    surfaced in RELAY_STATUS Queued. NEVER on the Sonnet execute tier. The hard child works
    ONE bounded `[HARD]` item under handoff-C5 "only-if-small-enough" discipline, ticks the
    box only if genuinely green, and returns the standard report. Integration uses a
    `strong-execute (<model>, fable-standin, relay-loop)` checkpoint label. `scripts/probe-fable.sh`
    manages the front door's 2 h Fable-probe cache (`check` → fresh-available/fresh-unavailable/
    stale/absent; `set <true|false> [ts]`), hermetically testable (PROBE_CACHE override, no model).
    SKILL.md documents the `hard` verdict + references the helper in step 0.
  - **Tests**: `tests/test_relay_loop_structure.sh` (`# roadmap:83c9` + da26 §18 checks:
    enum, PRIORITY order, opus-only gate, Sonnet-never-HARD, strong-execute label, refDoc),
    `tests/test_probe_fable.sh` (`# roadmap:da26`) — fresh-available/unavailable, stale (>2h),
    absent, malformed, set-persistence, bad-arg.
  - **Done-check**: `tests/run-tests.sh tests/test_probe_fable.sh tests/test_relay_loop_structure.sh`
    then full `make test` after ticking.
  - **Context**: TODO id:da26 (c) — ratified 2026-06-15 (user): accept Opus doing `[HARD]`
    work while Fable is out. Built on the Opus-apex pivot (f64c28b). Reuses handoff.md C5,
    `worktreePathFor`/`branchFor`, and the existing `standInSuffix` logic.

- [x] Add a batched `say` subcommand to broker-curl.sh and route broker-mode.md through it [ROUTINE] <!-- id:3b02 -->
  - **Acceptance**: `broker-curl.sh <port> <session> say` reads plain-text lines from
    stdin and POSTs **one `/event` per line** (per-line painting in the renderer must
    be preserved — never collapse lines into a single event). A `--opener` first-line
    flag marks the first stdin line with `"kind":"opener"` for TTFL logging. Text with
    apostrophes/quotes/backslashes survives intact (JSON built with `jq -n --arg`
    internally). stdout stays quiet on success (HTTP responses discarded); curl/HTTP
    failures still reach stderr and exit non-zero. Empty stdin lines are skipped.
    `meeting/broker-mode.md` §Discussion is updated so the per-persona-line example
    uses ONE `say` call per agenda item instead of one Bash call per line (this is
    the actual ctx win: ~25–35 tool-call records/meeting → ≤10). Existing endpoints
    (`status events event question await response`) are unchanged.
  - **Tests**: `tests/test_broker_say.sh` (`# roadmap:3b02`) (currently RED)
  - **Done-check**: `tests/run-tests.sh tests/test_broker_say.sh` then full `make test` after ticking
  - **Context**: `meeting/broker-curl.sh` (case-arm dispatch; keep the existing
    brace-default and quoting gotchas documented in CLAUDE.md §Gotchas),
    `meeting/broker-mode.md` (only the Discussion example block needs rewording —
    keep the "never batch into one event" semantics explicit). Mock broker fixture:
    `tests/fixtures/mock-broker.py`. TODO id:3b02 is the origin item — option (b)
    batching was chosen; do not also implement (a)/(c).

- [x] Add the Fable-class caveat to the γ-branch reference table in broker-mode.md [ROUTINE] <!-- id:44ba -->
  - **Acceptance**: in `meeting/broker-mode.md`, the `## γ-branch reference` section
    contains a visible Fable note attached to the table — either a `> **Fable note:**`
    blockquote directly under the table or a footnote marker on the three
    `AskUserQuestion` fallback rows (`MEETING_LIVE=0`, `subscribers=0`,
    `Broker unavailable`). The note must say that on Fable-class harnesses
    `AskUserQuestion` is replaced by inline-prose numbered prompts and point to
    `format.md §Interactive mode §Harness-class gate`. The `subscribers>0` row needs
    no caveat (broker routing makes the rendering limit irrelevant). Table content
    itself stays otherwise unchanged.
  - **Tests**: `tests/test_fable_caveat.sh` (`# roadmap:44ba`) (currently RED)
  - **Done-check**: `tests/run-tests.sh tests/test_fable_caveat.sh` then full `make test` after ticking
  - **Context**: TODO.md "broker-mode.md γ-branch table missing Fable caveat" item;
    `docs/meeting-notes/2026-06-12-0749-fable-harness-interactive-mode-fix.md`.
    Prose cross-refs already exist elsewhere in the file — the fix is specifically
    AT the table, which is what gets skimmed.

- [x] Cover fables-turn and projects skills in the Makefile installer [ROUTINE] <!-- id:1ec1 -->
  - **Acceptance**: `make install-fables-turn` and `make install-projects` exist and
    symlink the skills into `$(DEST_DIR)` (override-able, default `~/.claude/skills`).
    fables-turn installs `SKILL.md`, `references/{handoff,review,conventions,templates}.md`,
    and `scripts/{discover-repos,ckpt-tag}.sh` (scripts chmod +x), creating the
    nested `references/` and `scripts/` directories under the destination —
    extend the `SKILL_RULES` template with a `mkdir -p` of each file's dirname
    rather than flattening paths. projects installs `SKILL.md` only. Both skills are
    in `SKILLS` so `make install`, `make status`, `make uninstall` cover them, and
    `make help` lists them. fables-turn's two scripts join the allowlist generation
    (`fables-turn_ALLOW`). Neither skill has LOCAL files. `make status-fables-turn`
    reports nested files correctly.
  - **Tests**: `tests/test_makefile_skills.sh` (`# roadmap:1ec1`) (currently RED)
  - **Done-check**: `tests/run-tests.sh tests/test_makefile_skills.sh` then full `make test` after ticking
  - **Context**: `Makefile` (per-skill variable convention at top + `SKILL_RULES`
    define). The skill was hand-symlinked on 2026-06-12; the Makefile is the
    canonical installer and must not lag. Test with `DEST_DIR=$(mktemp -d)` —
    never the real `~/.claude`.

- [x] Add tools/ctx-budget.sh — per-skill SKILL.md token-budget audit [ROUTINE] <!-- id:32d6 -->
  - **Acceptance**: `tools/ctx-budget.sh [root]` (default: git toplevel) scans every
    `*/SKILL.md` in the repo and prints one TSV line per file:
    `<relpath>\t<est_tokens>\t<gate>\t<OK|WARN>`, where `est_tokens = bytes/4`
    (the repo's established chars/4 convention, same as cost-of.sh SIZE_KB/4) and
    `gate` is 2000 tokens by default, override via `CTX_BUDGET_GATE` env var.
    Files over gate get `WARN`; exit code is 0 either way (advisory logger, not a
    blocker — "observe before preventing"). A `--summary` flag prints only the WARN
    lines plus a final `total: N files, M over gate` line. Executable, `set -euo
    pipefail`, no dependencies beyond coreutils.
  - **Tests**: `tests/test_ctx_budget.sh` (`# roadmap:32d6`) (currently RED)
  - **Done-check**: `tests/run-tests.sh tests/test_ctx_budget.sh` then full `make test` after ticking
  - **Context**: TODO.md "git-diary-workflow SKILL.md size audit" item and the
    global "per-prompt ctx multipliers" heuristic — mandatory-after-every-prompt
    skills multiply their size by prompt count, so their SKILL.md size needs a
    cheap recurring check. ARCHITECTURE.md §9 for the advisory-only philosophy.

- [x] Show the session token total in the statusline context segment [ROUTINE] <!-- id:2520 -->
  - **Acceptance**: `statusline/statusline-command.sh` line 1 displays the context
    segment as `<pct>%(<tokens>)` where `<tokens>` is `TOTAL_TOKENS` (input+output,
    already computed) humanized: `<1000` → as-is, `≥1000` → `N.Nk` with one decimal
    truncated to `Nk` when ≥10k (e.g. `115000` → `115k`, `9500` → `9.5k`, `730` →
    `730`). Same color as the existing context percentage. No new network calls, no
    layout change elsewhere on the line. Script must still produce output when run
    with `HOME` pointing at an empty temp dir (no credentials → fetch skipped).
  - **Tests**: `tests/test_statusline_tokens.sh` (`# roadmap:2520`) (currently RED)
  - **Done-check**: `tests/run-tests.sh tests/test_statusline_tokens.sh` then full `make test` after ticking
  - **Context**: `statusline/statusline-command.sh` (CONTEXT_* block around line
    251–258; final echo at the bottom). Fixture stdin JSON:
    `tests/fixtures/statusline-input.json`. Origin: TODO.md "Statusbar: other
    cost-saving indicators" (this implements the first candidate; cache-read ratio
    is out of scope — it needs transcript parsing).

- [x] Extend the id-token ecosystem to ROADMAP.md (scan-ids, orphan-scan union, classify relay line) [HARD — strong model] <!-- id:de9c -->
  - **Why HARD**: cross-script invariant — three scripts must agree on what counts
    as the id-bearing ledger, and the wrong call silently reintroduces token
    collisions or orphan-scan false positives; also requires deciding how the
    classifier should treat relay-managed lines (judgment, not mechanics).
  - **Acceptance**: (1) `append.sh` gains a `scan-ids [<root>]` subcommand printing
    every existing `id:XXXX` token (one per line, sorted unique) from the ledger
    file set, which now includes `ROADMAP.md`; `new-id`/`new-ids` use the same scan
    so freshly minted tokens can never collide with roadmap ids. (2)
    `orphan-scan.sh` includes `ROADMAP.md` in the TODO-union read (forward and
    reverse modes): a meeting-note item whose token lives in ROADMAP.md is not an
    orphan. (3) `classify.sh` emits class `RELAY` for the TODO.md relay mirror line
    (`Relay: N open ROADMAP items`) so `/meeting` no-arg dispatch never proposes a
    meeting on it. Resolves TODO id:62f5 part (a).
  - **Tests**: `tests/test_id_ecosystem.sh` (`# roadmap:de9c`)
  - **Done-check**: `tests/run-tests.sh tests/test_id_ecosystem.sh`
  - **Context**: executed by the reviewer in this handoff turn (C5). See
    ARCHITECTURE.md §3.

- [x] Create the `fables-executor` skill: versioned SKILL.md + Makefile registration + test [ROUTINE] <!-- id:7691 -->
  - **Acceptance**: `fables-executor/SKILL.md` exists with `name`/`description` frontmatter
    and a `## Executor contract <!-- fables-executor contract v1 -->` heading carrying the
    5 rules verbatim + ROADMAP item format recap + RELAY_LOG conventions + Maintenance
    bump-rule note. `fables-executor` is in `Makefile` `SKILLS` with `_FILES := SKILL.md`
    and empty `_EXEC/_ALLOW/_LOCAL`. `dotclaude-skills/CLAUDE.md` `## Relay contract`
    section is the thin pointer (`<!-- fables-executor contract v1 -->`). Version-consistency
    grep: the `vN` in `fables-executor/SKILL.md` equals the `vN` in `CLAUDE.md`'s pointer.
    `fables-turn/references/conventions.md` no longer contains the fenced 5-rule block.
    `handoff.md` C1 and `review.md` step 4 reference the pointer, not the block.
  - **Tests**: `tests/test_fables_executor.sh` (`# roadmap:7691`)
  - **Done-check**: `tests/run-tests.sh tests/test_fables_executor.sh` then full `make test` after ticking
  - **Context**: meeting note `docs/meeting-notes/2026-06-12-1404-fables-executor-skill.md`;
    TODO id:fba6. The skill body + all reference-file edits may already exist from the
    review turn that wrote this item — verify before re-implementing.

- [ ] Strong-model audit: code review, security, and design coherence [HARD — pool] <!-- id:401c --> <!-- relay:recurring-audit -->
  - **Why HARD**: requires adversarial judgment — finding subtle bugs, security issues,
    and internal contradictions in design docs that a weaker model would miss or dismiss.
    Also requires holding the full design history in mind to spot feasibility gaps.
  - **Acceptance**: a meeting note documenting findings across three passes:
    (1) **Code review** — correctness bugs, error handling gaps, shell quoting issues,
    race conditions, unhandled edge cases in scripts and Python helpers;
    (2) **Security audit** — injection risks (command, path, jq), unvalidated inputs
    at system boundaries, secrets exposure, file permission assumptions;
    (3) **Design coherence** — check currently-unreviewed design decisions (anything
    added since last Fable turn) for sensibility, feasibility, and internal
    contradictions (e.g. a TODO gate that can never fire, a contract rule that
    contradicts another). Each finding is either fixed inline (if trivial), or
    becomes a new TODO/ROADMAP item with the finding quoted as context. No finding
    is silently dropped — if assessed as acceptable risk, say so explicitly.
  - **Tests**: none (audit output is the deliverable; follow-on items get their own tests)
  - **Done-check**: meeting note at `docs/meeting-notes/YYYY-MM-DD-HHMM-strong-model-audit.md`
    exists; every finding is either fixed, tracked, or explicitly accepted with rationale.
  - **Context**: run after each significant batch of Sonnet executor work or design changes.
    First run: covers all work since `fable-ckpt-20260612-1328`. Subsequent runs: diff
    against the most recent `fable-ckpt-*` tag (same window as review mode step 2).
  - **Run log** (recurring item — stays open by design):
    - Run 1 (2026-06-12-1811): `fable-ckpt-20260612-1328`..HEAD — see meeting note.
    - Run 2 (2026-06-15-1520): `fable-ckpt-20260612-1827`..HEAD (relay scripts surface) — F1/F2 → id:c8db.
    - Run 3 (2026-06-15-1745): `relay-ckpt-20260615-1559`..HEAD — **2 defects fixed inline**:
      `test_relay_executor.sh` asserted a stub commit 608800b removed (suite was 1-red on
      arrival, now 48/0); id:3826 gaming-flag logger was a dead feed (review dispatch prompt
      never requested its fields) — fixed + regression-guard added. See
      `docs/meeting-notes/2026-06-15-1745-strong-model-audit.md`.
    - Run 4 (2026-06-15-1759): `relay-ckpt-20260615-1748`..HEAD (1 commit: `bf70a52`
      statusline/check-deps.sh) — **clean**: no code/security defects. One **coherence drift
      fixed inline** — id:414a was still marked `GATED` on id:fa05+id:dfaf, both now shipped;
      updated the gate line to CLEARED so a future strong session isn't misled into skipping it.
      See `docs/meeting-notes/2026-06-15-1759-strong-model-audit.md`.
    - Run 5 (2026-06-15-1937): `relay-ckpt-20260615-1748`..HEAD (~270 lines / 10 files; code:
      relay-loop.js ×2 + 2 tests) — **clean**: no code/security defects, no inline fix needed.
      Verified the two pool-crash fixes (failed-shard surfacing via order-preserving `chunks[i]`;
      removal of `new Date()`/`process.env` forbidden in the Workflow sandbox) correct with genuine
      regression guards, and the cross-ledger state coherent (0 open ROUTINE / 3 open HARD; d5e0
      summary agrees). See `docs/meeting-notes/2026-06-15-1937-strong-model-audit.md`.
    - Run 6 (2026-06-15-1937b): `relay-ckpt-20260615-1937..HEAD` (only first-seen code:
      the 2-line `paused` filter in gather-human-backlog.sh, 7456e1f) — **clean**: no
      code/security/coherence defects. One forward-robustness gap **fixed inline** — the
      new `paused = true` sweep-skip filter shipped without a test; added a non-vacuous
      regression guard (repoD fixture) to `test_relay_human.sh`. Suite 50/0. See
      `docs/meeting-notes/2026-06-15-1937b-strong-model-audit.md`.
    - Run 7 (2026-06-15-2147): `relay-ckpt-20260615-2129..HEAD` (only first-seen code:
      the `warn_nested_worktrees` stale-checkout guard in gather-human-backlog.sh,
      83d8614) — **clean**: no code/security/coherence defects (`set -e`-safe grep
      guards, `-F` fixed-string prefix match with trailing-slash, stdout/stderr split all
      correct). One forward-robustness gap **fixed inline** (same class as Run 6) — the
      new warning shipped without a test; added a non-vacuous regression guard (section 4:
      real-git nested-worktree fixture + clean-repo negative control + stdout-clean
      assertion) to `test_relay_human.sh`. Suite 50/0. See
      `docs/meeting-notes/2026-06-15-2147-strong-model-audit.md`.
    - Run 8 (2026-06-16-0650): `relay-ckpt-20260615-2150..HEAD` (first-seen code: the
      profiler batch — `profile-run.sh` + `profile-runs-batch.sh` + their tests, id:a59e/
      id:08a3, ~615 lines) — **clean**: no code/security defects (pure-read, stdlib-only,
      `grep -- "$ARG"` option-safe, no injection/traversal/secrets). One coherence drift
      **fixed inline** — both scripts' header comments documented a one-wildcard search root
      (`projects/*/subagents/workflows`) while the code+real layout use two
      (`projects/*/*/...`); updated the comments to match. One cosmetic dead-code residue in
      profile-run.sh (empty-list loop + unused `at_cap_intervals`) flagged + explicitly
      accepted (no behavioural effect). Cross-ledger coherent (0 ROUTINE / 3 HARD, d5e0
      agrees). Suite 52/0. See `docs/meeting-notes/2026-06-16-0650-strong-model-audit.md`.
    - Run 9 (2026-06-16-0928): `relay-ckpt-20260616-0653..HEAD` (~586 lines / 14 files;
      observability id:c8b6 + drain/gated-HARD id:2d20 + quota-seatbelt id:4267 + new
      relay-burn.sh id:219b) — **clean**: no code/security defects. One doc/impl discrepancy
      **fixed inline** — `relay-state-write.sh` event-append header claimed "SAME flock" but
      correctly flocks the target events file (not the shared $LOCK); corrected the comment +
      Paths note + `--help` range. Three findings **accepted** w/ rationale: relay-burn.sh
      `date -d "$reset"` awk-shellout injection seam (LOW — `resets_at` is provider-controlled
      API data; filed as forward-robustness TODO id:287b), a dead tautology sub-condition in
      the segment reduce (cosmetic), and code-only sub-ids 15bd/cd19/03a5/219b (inline
      provenance for tracked parents, not ledger tokens). Cross-ledger coherent (0 ROUTINE /
      3 HARD, d5e0 agrees). Suite 53/0. See `docs/meeting-notes/2026-06-16-0928-strong-model-audit.md`.
    - Run 10 (2026-06-16-1247): `95d3d07..HEAD` (first-seen code since Run 9; ~944 lines /
      16 files: orphan-reconcile D1/D2/D3 + relay-econ.py + archive-done multiline +
      gather-human-backlog gated-HARD sweep) — **1 defect fixed inline**: `relay-reconcile.sh`
      `--integrate`/`--discard` with no branch arg died on a `set -e` `shift 2` count error
      BEFORE the friendly `<branch> required` guard; fixed to `shift; shift || true` + a
      non-vacuous behavioural regression guard in `test_relay_reconcile_mode.sh` (proven it
      fails on the reverted form). One **doc nit fixed inline** (relay-econ.py header field
      names). One **LOW accepted** (gather-human-backlog `awk -v`, id:c8db class). No security
      defects; cross-ledger coherent (0 ROUTINE / 3 HARD, d5e0 agrees). Suite 58/0. See
      `docs/meeting-notes/2026-06-16-1247-strong-model-audit.md`.
    - Run 11 (2026-06-16-1222): `5ab8c12..HEAD` (first-seen since Run 10, EXCLUDING Run 10's
      own already-audited merge d36208a) — **clean**: window was LEDGER-ONLY (TODO id:0547
      +1, RELAY_LOG ckpt +4; zero code/scripts/python). No code to review, no security
      surface. Coherence pass verified TODO id:0547's injected-unit-vs-discovery-unit race
      diagnosis against relay-loop.js (L71 invariant, L617 un-deduped injection merge, L808
      same-run re-entrant lease — all accurate; sound entry, no contradiction). Cross-ledger
      coherent (0 ROUTINE / 3 HARD, d5e0 agrees). Suite 58/0 (audit-only, no test changes).
      See `docs/meeting-notes/2026-06-16-1222-strong-model-audit.md`.
    - Run 12 (2026-06-16-1122): `d3ca7a9..HEAD` (first-seen since Run 11, EXCLUDING Run
      11's own already-audited merge `5914c72`) — **clean**: window was LEDGER-ONLY (sole
      first-seen change = the Run 11 checkpoint paragraph in RELAY_LOG.md +4; zero
      code/scripts/python — `git diff --name-only -- '*.sh' '*.py' '*.js'` empty). No code
      to review, no security surface, no new design decision/gate. Cross-ledger coherent
      (0 ROUTINE / 3 HARD; all three HARD ids `[ ]` in both ROADMAP+TODO, d5e0 agrees).
      Suite 58/0 (audit-only, no test changes). See
      `docs/meeting-notes/2026-06-16-1122-strong-model-audit.md`.
    - Run 13 (2026-06-17-1102): first-seen code since the last audit (`2026-06-16-1247`) —
      5 files: `discover-sig.sh` (88L), `relay-loop.js` diff (id:c3a6 cache integration, ~52L),
      `model-probe.sh` (241L), `settings-env.py` (90L), `model-probe.battery.jsonl`. **Clean —
      no inline fixes** (code clean to a high bar): discovery cache correctly hashes a superset
      of the 9 shard inputs, fail-open sound throughout; settings-env.py idempotent/non-clobbering;
      battery JSONL valid, no secrets. **2 LOW findings tracked**: id:4348 (discover-sig.sh
      `upstream` read without fetch → bounded origin-behind under-invalidation — needs a measured
      fetch-vs-accept decision) + id:b9b5 (model-probe.sh grade `echo`→`printf` robustness). 3
      findings explicitly accepted (awk -v repo-name = id:c8db-class zero-risk; review-range
      covered by HEAD+tag hashing; probe's no-`--model` = D6 observe-don't-assert by design). Run
      via `/relay . --afk` (Opus hard-execute). See `docs/meeting-notes/2026-06-17-1102-strong-model-audit.md`.
    - Run 14 (2026-06-17, via /relay human Pareto pick): `relay-ckpt-20260617-1326..HEAD` — first-seen
      code = the id:bbd2 `migrate-state-dirs.sh` rewrite (166L) + `test_migrate_state_dirs.sh` (new).
      Ran as a 3-pass adversarial audit (correctness / security / design-coherence) of THIS session's
      own work. **4 real defects fixed inline** (audit caught them in freshly-written code): (1) HIGH —
      jsonl merge `cat src dest | awk` fused two records into one corrupt line when src lacked a trailing
      newline (silent log loss); fixed with `awk 1 … | awk 'NF && !seen'` + a no-trailing-newline test.
      Verified the LIVE `relay-events.jsonl` was NOT corrupted (the appender always terminates lines → 0
      fused / 358 valid). (2) MED — dir-union swallowed a partial `cp` failure then `rm -rf`'d src → lost
      un-copied children; now drops src only on cp success, else refuses. (3) MED — idle guard failed OPEN
      on `claim.sh`/`stat` errors and peeked one base; now fails CLOSED and peeks both old+new. (4) MED —
      `ASSUME_IDLE` bypass now warns loudly on stderr. Test grew 9→12 cases (added no-trailing-newline,
      NEW-newer snapshot, type-mismatch refusal). Design/spec claims all independently re-verified TRUE
      (symlinks, 358 events, 48 gather). 1 LOW tracked: id:16e9 (pre-existing flaky `test_relay_claim_liveness.sh`,
      roadmap:7570 — unrelated to this change). Suite 66/66.
    - Run 15 (2026-06-19-2005): first-seen code since Run 14's own audit commit `61020a0`
      (`61020a0..HEAD`, ~1.9 kLOC / 9 prod files) — the L1/L2 token-skeleton + data-loss-fix
      batch (ids aa93 clean-tree-gate + git-lock-push autostash-refuse, 11ad gather-repo-state,
      0d31 relay-status-publish, c855 push-seed cache, 3801 handback-followup.py, b841 nested
      quotaThresholds fold, 2425 crossedBucket). **Clean** — no inline code/security fix needed.
      Verified: gather-repo-state.sh builds JSON via env vars (no injection), discover-sig.sh ⟷
      gather-repo-state.sh hash the SAME superset (no stale-verdict hazard for the c3a6/c855
      caches), push-seed seeds `idle` only at provably-drained 0/0 (no under-dispatch), handback
      follow-up POSIX-escapes every shell arg + fire-and-forget, git-lock-push/clean-tree-gate
      both refuse to force-clean a foreign-dirty tree, profile-run.sh rollup-needle removed.
      shard-canary corpus is the correct behavior-preservation net for the 11ad refactor.
      1 LOW tracked: id:05e8 (`test_git_lock_push_slash_branch.sh` flaked on the first full-suite
      run, green in isolation + on re-run — pre-existing fetch/push timing flake, id:16e9 class,
      NOT new /tmp contention; both tests isolate via mktemp). Suite 76/0 on a clean run. See
      `docs/meeting-notes/2026-06-19-2005-strong-model-audit.md`.
    - Run 16 (2026-06-19-2015): first-seen change since Run 15's own audit commit `36fb824`
      (`36fb824..HEAD`) — **clean: LEDGER-ONLY window**. Sole first-seen change = the Run 15
      strong-execute checkpoint paragraph in RELAY_LOG.md (+4 lines); `git diff --name-only
      36fb824..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No code to review, no security surface,
      no new design decision/gate. The RELAY_LOG paragraph is internally consistent (audit
      verdict + suite count + tracked-flake id) — no contradiction. Cross-ledger coherent
      (0 open ROUTINE / 3 HARD — dba3/401c/3346; the 4th `[ ]` HARD line is the DEFERRED
      design entry de4e, not executable; d5e0 agrees). Both pre-existing tracked flakes
      (id:16e9, id:05e8) did NOT recur. Suite 76/0 (audit-only, no test changes). See
      `docs/meeting-notes/2026-06-19-2015-strong-model-audit.md`.
    - Run 17 (2026-06-19-2017): first-seen change since Run 16's own audit commit `250613f`
      (`250613f..HEAD`) — **LEDGER-ONLY window** (Runs 11/12/16 class). Sole first-seen change
      = the Run 16 strong-execute checkpoint paragraph in RELAY_LOG.md (+4 lines); `git diff
      --name-only 250613f..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No code to review, no security
      surface, no new design decision/gate. **One coherence drift fixed inline** (Run 4/Run 8
      class) — TODO id:d5e0's hand-rolled "review 2026-06-16 1900" summary still listed the
      CLOSED id:10c0 (state-dir rename, `[x]` 2026-06-17 w/ completion id:bbd2) as an open HARD
      and OMITTED the open id:dba3; corrected the enumeration to the live ROADMAP set
      (dba3/401c/3346 + DEFERRED de4e). Cross-ledger coherent (0 open ROUTINE / 3 executable
      HARD — dba3/401c/3346; de4e DEFERRED non-executable; all three open in both ROADMAP+TODO).
      Both tracked flakes (id:16e9, id:05e8) did NOT recur. Suite 76/0. See
      `docs/meeting-notes/2026-06-19-2017-strong-model-audit.md`.
    - Run 18 (2026-06-19-2039): first-seen change since Run 17's own audit commit `c4c0fdc`
      (`c4c0fdc..HEAD`) — **LEDGER-ONLY window** (Runs 11/12/16/17 class). Sole first-seen
      change = the Run 17 strong-execute checkpoint paragraph in RELAY_LOG.md (+4 lines);
      `git diff --name-only c4c0fdc..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No code to
      review, no security surface, no new design decision/gate. The RELAY_LOG paragraph is
      internally consistent (verdict + inline-fix note + suite count). Cross-ledger coherent
      (0 open ROUTINE / 3 executable HARD — dba3/401c/3346; de4e DEFERRED non-executable;
      all three open in both ROADMAP+TODO; d5e0 summary agrees, Run 17's drift fix holds).
      Both tracked flakes (id:16e9, id:05e8) did NOT recur. Suite 76/0. See
      `docs/meeting-notes/2026-06-19-2039-strong-model-audit.md`.
    - Run 19 (2026-06-19-2117): first-seen change since Run 18's own audit commit `c4c0fdc`
      (`c4c0fdc..HEAD`) — **LEDGER-ONLY window** (Runs 11/12/16/17/18 class). All first-seen
      changes are Run 18's own ledger/doc artifacts (RELAY_LOG checkpoint paragraph +8,
      ROADMAP run-log line +10, the Run 18 meeting note +67, a 1-line TODO d5e0 touch);
      `git diff --name-only c4c0fdc..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No code to
      review, no security surface, no new design decision/gate. The two new RELAY_LOG
      paragraphs (Run 17 + Run 18) are internally consistent (verdict + suite count 76/0).
      Cross-ledger coherent (0 open ROUTINE / 3 executable HARD — dba3/401c/3346; de4e
      DEFERRED non-executable; all three open in both ROADMAP+TODO; d5e0 summary agrees,
      Run 17's drift fix holds). Both tracked flakes (id:16e9, id:05e8) did NOT recur.
      Suite 76/0. See `docs/meeting-notes/2026-06-19-2117-strong-model-audit.md`.
    - Run 20 (2026-06-19-2118): first-seen change since Run 19's own audit commit `f24b99e`
      (`f24b99e..HEAD`) — **LEDGER-ONLY window** (Runs 11/12/16/17/18/19 class). Sole first-seen
      change = the Run 19 strong-execute checkpoint paragraph in RELAY_LOG.md (+4 lines); `git diff
      --name-only f24b99e..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No code to review, no security
      surface, no new design decision/gate. The RELAY_LOG paragraph is internally consistent
      (verdict + no-inline-fix note + suite count 76/0). Cross-ledger coherent (0 open ROUTINE /
      3 executable HARD — dba3/401c/3346; de4e DEFERRED non-executable; all three open in both
      ROADMAP+TODO; d5e0 summary agrees, Run 17's drift fix holds). Both tracked flakes (id:16e9,
      id:05e8) did NOT recur. Suite 76/0. See `docs/meeting-notes/2026-06-19-2118-strong-model-audit.md`.
    - Run 21 (2026-06-19-2155): first-seen change since Run 20's own audit commit `39592e8`
      (`39592e8..HEAD`) — **LEDGER-ONLY window** (Runs 11/12/16/17/18/19/20 class). First-seen
      changes = the Run 20 strong-execute + review checkpoint paragraphs in RELAY_LOG.md and two
      newly-minted TODO design items (id:81cb statusline per-session ctx state file; id:daf0
      screenshots + README refresh) under a new `## docs & presentation` header; `git diff
      --name-only 39592e8..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No code to review, no security
      surface (the two specs are purely-local additive sketches; id:daf0 itself flags the
      capture-privacy hazard for the build pass). Both new items internally sound (id:81cb's
      `.session_id`/`$CLAUDE_SESSION_ID` key both sides agree on is correct — statusline parses only
      `.transcript_path` today; id:daf0's README-vs-SKILL.md boundary consistent). **One coherence
      drift fixed inline (Run 4/8/17 class)** — the TODO id:401c MIRROR line still read "Latest ✓
      Run 19"; Run 20 had since run (ledger-only); refreshed it to Run 21. Cross-ledger coherent
      (0 open ROUTINE / 3 executable HARD — dba3/401c/3346; de4e DEFERRED non-executable; all three
      open in both ROADMAP+TODO; d5e0 summary agrees, Run 17's drift fix holds). id:16e9 did NOT
      recur; id:05e8 flaked once (75/1) then green in isolation + full-suite rerun (76/0), exactly
      as id:05e8 predicts. Suite 76/0 on rerun. See `docs/meeting-notes/2026-06-19-2155-strong-model-audit.md`.
    - Run 22 (2026-06-21-1656): first-seen change since Run 21's own audit commit `b0b4076`
      (`b0b4076..HEAD`) — **LEDGER-ONLY window** (Runs 11/12/16/17/18/19/20 class).
      First-seen changes = Run 21's strong-execute checkpoint + the two 2026-06-21 review
      checkpoint paragraphs in RELAY_LOG.md, a REVIEW_ME box (flaky-claim-liveness note),
      two new TODO design items (id:ebd0 [HIGH PRIORITY — SECURITY] global pre-push privacy
      gate; id:d2cd [HIGH PRIORITY] lock-hygiene umbrella), the id:ebd0 privacy sanitization,
      and an archived done entry; `git diff --name-only b0b4076..HEAD -- '*.sh' '*.py' '*.js'`
      is EMPTY. No code to review, no security surface. gaming-scan clean (no DELETED_TEST/
      ADDED_SKIP/REMOVED_ASSERT). **One coherence drift fixed inline (Run 4/8/17/21 class)** —
      the TODO id:401c MIRROR line still read "Latest ✓ Run 21"; refreshed to Run 22. Design
      coherence verified on both new items: id:d2cd's 5 cited sub-ids (3b18/6366/bae5/d187/
      3558) all exist in the ledgers and the umbrella framing is sound; id:ebd0's sanitization
      (e886e6f) correctly moved leak specifics to private memory (no-leak-specifics directive).
      Cross-ledger coherent (0 open ROUTINE / 3 executable HARD — dba3/401c/3346; de4e DEFERRED
      non-executable; d5e0 summary agrees, Run 17's drift fix holds). Both tracked flakes
      (id:16e9, id:05e8) did NOT recur. Suite 76/0 on a clean run. See
      `docs/meeting-notes/2026-06-21-1656-strong-model-audit.md`.
    - Run 23 (2026-06-21-1713): first-seen change since Run 22's own audit merge `c40b20e`
      (`c40b20e..HEAD`) — **LEDGER-ONLY window** (Runs 11/12/16/17/18/19/20/21/22 class).
      Sole first-seen change = the Run 22 strong-execute checkpoint paragraph in RELAY_LOG.md
      (+4 lines); `git diff --name-only c40b20e..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No
      code to review, no security surface, no new design decision/gate. gaming-scan clean (no
      DELETED_TEST/ADDED_SKIP/REMOVED_ASSERT). The RELAY_LOG paragraph is internally consistent
      (Run 22 verdict + mirror-line drift fix + suite 76/0). **One coherence drift fixed inline
      (Run 4/8/17/21/22 class)** — the TODO id:401c MIRROR line still read "Latest ✓ Run 22";
      refreshed to Run 23. Cross-ledger coherent (0 open ROUTINE / 3 executable HARD —
      dba3/401c/3346; de4e DEFERRED non-executable; all three open in both ROADMAP+TODO; d5e0
      summary agrees, Run 17's drift fix holds). Both tracked flakes (id:16e9, id:05e8) did NOT
      recur. Suite 76/0 on a clean run. See `docs/meeting-notes/2026-06-21-1713-strong-model-audit.md`.
    - Run 24 (2026-06-21-1626): first-seen change since Run 23's own audit merge `b2db0bc`
      (`b2db0bc..HEAD`) — **LEDGER-ONLY window** (Runs 11/12/16/17/18/19/20/21/22/23 class).
      Sole first-seen change = the Run 23 strong-execute checkpoint paragraph in RELAY_LOG.md
      (+4 lines); `git diff --name-only b2db0bc..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No
      code to review, no security surface, no new design decision/gate. gaming-scan clean (no
      DELETED_TEST/ADDED_SKIP/REMOVED_ASSERT). The RELAY_LOG paragraph is internally consistent
      (Run 23 verdict + mirror-line drift fix + suite 76/0). **One coherence drift fixed inline
      (Run 4/8/17/21/22/23 class)** — the TODO id:401c MIRROR line still read "Latest ✓ Run 23";
      refreshed to Run 24. Cross-ledger coherent (0 open ROUTINE / 3 executable HARD —
      dba3/401c/3346; de4e DEFERRED non-executable; all three open in both ROADMAP+TODO; d5e0
      summary agrees, Run 17's drift fix holds). Both tracked flakes (id:16e9, id:05e8) did NOT
      recur. Suite 76/0 on a clean run. See `docs/meeting-notes/2026-06-21-1626-strong-model-audit.md`.
    - Run 25 (2026-06-21-1842): first-seen change since Run 24's own audit merge `99a1f2e`
      (`99a1f2e..HEAD`) — **LEDGER-ONLY window** (Runs 11/12/16–24 class). First-seen = three
      RELAY_LOG checkpoint paragraphs + a real ROADMAP design-state change (`01e54c4`): id:dba3
      auto-gated `[HARD — strong model]` → `[HARD — decision gate]` route:human. `git diff
      --name-only 99a1f2e..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY → no code/security surface.
      gaming-scan clean (no DELETED_TEST/ADDED_SKIP/REMOVED_ASSERT). **Design coherence: the
      id:dba3 gate change verified COHERENT** — closure genuinely needs the claude-probe OS user
      (id:d0c0, useradd/sudo — forbidden for an unattended relay child) + real Opus/Sonnet/Haiku
      token runs, so route:human is correct (consistent with the id:dba3 body, the open id:23e9
      seeding gate, and project memory; the gate will fire for a human, not silently — no
      can-never-fire gate). **One coherence drift fixed inline (Run 4/8/17/21/22/23/24 class)** —
      the TODO id:401c MIRROR line still read "Latest ✓ Run 24"; refreshed to Run 25. Cross-ledger
      coherent (0 open ROUTINE / 3 open HARD — dba3 now decision-gated, 401c, 3346 gated; de4e
      DEFERRED non-executable; d5e0 summary agrees, Run 17's drift fix holds). Both tracked flakes
      (id:16e9, id:05e8) did NOT recur. Suite 76/0 on a clean run. See
      `docs/meeting-notes/2026-06-21-1842-strong-model-audit.md`.
    - Run 26 (2026-06-21-1835): first-seen change since Run 25's own audit merge `cb83ad1`
      (`cb83ad1..HEAD`) — **LEDGER-ONLY window** (Runs 11/12/16–25 class). Sole first-seen
      change = the Run 25 strong-execute checkpoint paragraph in RELAY_LOG.md (+4 lines);
      `git diff --name-only cb83ad1..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No code to
      review, no security surface, no new design decision/gate. gaming-scan clean (no
      DELETED_TEST/ADDED_SKIP/REMOVED_ASSERT). The RELAY_LOG paragraph is internally
      consistent (Run 25 verdict + dba3-gate-coherent + mirror-line drift fix + suite 76/0).
      **One coherence drift fixed inline (Run 4/8/17/21/22/23/24/25 class)** — the TODO
      id:401c MIRROR line still read "Latest ✓ Run 25"; refreshed to Run 26. Cross-ledger
      coherent (0 open ROUTINE / 3 executable HARD — dba3 decision-gated / 401c / 3346;
      de4e DEFERRED non-executable; all three open in both ROADMAP+TODO; d5e0 summary
      agrees, Run 17's drift fix holds). Both tracked flakes (id:16e9, id:05e8) did NOT
      recur. Suite 76/0 on a clean run. See `docs/meeting-notes/2026-06-21-1835-strong-model-audit.md`.
    - Run 27 (2026-06-21-1903): first-seen change since Run 26's own audit merge `32f430d`
      (`32f430d..HEAD`) — **LEDGER-ONLY window** (Runs 11/12/16–26 class). Sole first-seen
      change = the Run 26 strong-execute checkpoint paragraph in RELAY_LOG.md (+4 lines);
      `git diff --name-only 32f430d..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No code to
      review, no security surface, no new design decision/gate. gaming-scan clean (no
      DELETED_TEST/ADDED_SKIP/REMOVED_ASSERT). The RELAY_LOG paragraph is internally
      consistent (Run 26 verdict + mirror-line drift fix + suite 76/0). **One coherence
      drift fixed inline (Run 4/8/17/21/22/23/24/25/26 class)** — the TODO id:401c MIRROR
      line still read "Latest ✓ Run 26"; refreshed to Run 27. Cross-ledger coherent (0 open
      ROUTINE / 3 executable HARD — dba3 decision-gated / 401c / 3346; de4e DEFERRED
      non-executable; all three open in both ROADMAP+TODO; d5e0 summary agrees, Run 17's
      drift fix holds). Both tracked flakes (id:16e9, id:05e8) did NOT recur. Suite 76/0 on
      a clean run. See `docs/meeting-notes/2026-06-21-1903-strong-model-audit.md`.
    - Run 28 (2026-06-21-1919): first-seen change since Run 27's own audit merge `8b82136`
      (`8b82136..HEAD`) — **LEDGER-ONLY window** (Runs 11/12/16–27 class). Sole first-seen
      change = the Run 27 strong-execute checkpoint paragraph in RELAY_LOG.md (+4 lines);
      `git diff --name-only 8b82136..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No code to
      review, no security surface, no new design decision/gate. gaming-scan clean (no
      DELETED_TEST/ADDED_SKIP/REMOVED_ASSERT). The RELAY_LOG paragraph is internally
      consistent (Run 27 verdict + mirror-line drift fix + suite 76/0). **One coherence
      drift fixed inline (Run 4/8/17/21/22/23/24/25/26/27 class)** — the TODO id:401c MIRROR
      line still read "Latest ✓ Run 27"; refreshed to Run 28. Cross-ledger coherent (0 open
      ROUTINE / 3 executable HARD — dba3 decision-gated / 401c / 3346; de4e DEFERRED
      non-executable; all three open in both ROADMAP+TODO; d5e0 summary agrees, Run 17's
      drift fix holds). Both tracked flakes (id:16e9, id:05e8) did NOT recur. Suite 76/0 on
      a clean run. See `docs/meeting-notes/2026-06-21-1919-strong-model-audit.md`.
    - Run 29 (2026-06-21-1935): first-seen change since Run 28's own audit merge `8016dfa`
      (`8016dfa..HEAD`) — **LEDGER-ONLY window** (Runs 11/12/16–28 class). Sole first-seen
      change = the Run 28 strong-execute checkpoint paragraph in RELAY_LOG.md (+4 lines);
      `git diff --name-only 8016dfa..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No code to
      review, no security surface, no new design decision/gate. gaming-scan clean (no
      DELETED_TEST/ADDED_SKIP/REMOVED_ASSERT). The RELAY_LOG paragraph is internally
      consistent (Run 28 verdict + mirror-line drift fix + suite 76/0). **One coherence
      drift fixed inline (Run 4/8/17/21/22/23/24/25/26/27/28 class)** — the TODO id:401c
      MIRROR line still read "Latest ✓ Run 28"; refreshed to Run 29. Cross-ledger coherent
      (0 open ROUTINE / 3 executable HARD — dba3 decision-gated / 401c / 3346; de4e DEFERRED
      non-executable; all three open in both ROADMAP+TODO; d5e0 summary agrees, Run 17's
      drift fix holds). Both tracked flakes (id:16e9, id:05e8) did NOT recur. Suite 76/0 on
      a clean run. See `docs/meeting-notes/2026-06-21-1935-strong-model-audit.md`.
    - Run 30 (2026-06-22-0140): first-seen change since Run 29's own audit merge `422e95d`
      (`422e95d..HEAD`) — **SUBSTANTIVE CODE window** (breaks the Runs 11/12/16–29
      ledger-only streak): ~831 insertions / 11 code files. Production: gather-human-backlog.sh
      `emit_gated_hard`→`emit_hard_lanes` (id:78ff explicit `[HARD — pool|meeting|hands]`
      lane tags, untagged=LOUD nonzero reject id:415b); relay-reconcile.sh `--all` cross-repo
      orphan list (unreadable repo SURFACED not swallowed — the id:4e14 anti-pattern avoided);
      orphan-scan.sh `--promotion` + `xledger-ok` (id:d9b0 seam tooling); git-lock-push.sh
      `GIT_TERMINAL_PROMPT=0` + `ssh-add -l` precheck + BatchMode push; new
      tools/check-no-silent-swallow.sh swallow-ban guard (id:4347, advisory→`--enforce`).
      **CLEAN — no code/security defects** across all 3 passes: lane awk regex verified
      against the live 4 open HARD items (all classify right; `[—-]` backwards-range is a
      benign gawk literal set); rc-plumbing survives `set -e`; no injection (relay.toml
      trusted, fixed grep patterns, quoted `git -C`); git-lock-push HARDENS auth. Design
      coherent: id:78ff contract consistent across hard-lanes.md/collector/human.md/test;
      `route:human`→meeting bucket (not hands) **explicitly accepted** (auto-gate emits a
      coarse human-route; fine pool/meeting/hands is a human hand-tag job); swallow-ban
      ships ADVISORY (231 un-annotated swallows in 51 scripts = exactly why not yet
      enforcing). gaming-scan clean. **One coherence drift fixed inline (Run 4/8/17/21–29
      class)** — TODO id:401c MIRROR line still read "Latest ✓ Run 29"; refreshed to Run 30
      (d5e0 itself NOT stale this run). Cross-ledger coherent (0 open ROUTINE / 3 executable
      HARD — dba3 decision-gated / 401c / 3346; de4e DEFERRED non-executable; all three open
      in both ROADMAP+TODO; d5e0 agrees). Both tracked flakes (id:16e9, id:05e8) did NOT
      recur (id:6b91's CLAIM_TTL fix hardens the id:16e9 class). Suite 80/0 on a clean run.
      See `docs/meeting-notes/2026-06-22-0140-strong-model-audit.md`.
    - Run 31 (2026-06-22-0145): first-seen change since Run 30's own audit merge `00cfff7`
      (`00cfff7..HEAD`) — **LEDGER-ONLY window** (Runs 11/12/16–29 class). Sole first-seen
      change = the Run 30 strong-execute checkpoint paragraph in RELAY_LOG.md (+4 lines);
      `git diff --name-only 00cfff7..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No code to
      review, no security surface, no new design decision/gate. gaming-scan clean (no
      DELETED_TEST/ADDED_SKIP/REMOVED_ASSERT). The RELAY_LOG paragraph is internally
      consistent (Run 30 verdict + suite 80/0). **No coherence drift this run** — unlike
      the Run 4/8/17/21–30 class, the TODO id:401c MIRROR line and d5e0 summary were BOTH
      already current on arrival (Run 30 refreshed the mirror to Run 30; d5e0 not stale).
      Cross-ledger coherent (0 open ROUTINE / 3 executable HARD — dba3 decision-gated /
      401c / 3346; de4e DEFERRED non-executable; all three open in both ROADMAP+TODO; d5e0
      agrees). Both tracked flakes (id:16e9, id:05e8) did NOT recur. Suite 80/0 on a clean
      run. See `docs/meeting-notes/2026-06-22-0145-strong-model-audit.md`.
    - Run 32 (2026-06-22-0215): first-seen change since Run 31's own audit merge `d55fd25`
      (`d55fd25..HEAD`, HEAD = checkpoint `relay-ckpt-20260622-0208` / `e37df3a`) —
      **LEDGER-ONLY window** (Runs 11/12/16–29/31 class). Sole first-seen change = the Run 31
      strong-execute checkpoint paragraph in RELAY_LOG.md (+4 lines); `git diff --name-only
      d55fd25..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No code to review, no security surface,
      no new design decision/gate. gaming-scan clean (no DELETED_TEST/ADDED_SKIP/REMOVED_ASSERT).
      The RELAY_LOG paragraph is internally consistent (Run 31 verdict + suite 80/0). **No
      coherence drift this run** — the TODO id:401c MIRROR line and d5e0 summary were BOTH
      already current on arrival (Run 31). Cross-ledger coherent (0 open ROUTINE / 3 executable
      HARD — dba3 decision-gated / 401c / 3346; de4e DEFERRED non-executable; all three open in
      both ROADMAP+TODO; d5e0 agrees). Both tracked flakes (id:16e9, id:05e8) did NOT recur.
      Suite 80/0 on a clean run. See `docs/meeting-notes/2026-06-22-0215-strong-model-audit.md`.
    - Run 33 (2026-06-22-0317): first-seen change since Run 32's own audit merge `b315aed`
      (`b315aed..HEAD`, HEAD = checkpoint `relay-ckpt-20260622-0217` / `59b0b99`) —
      **LEDGER-ONLY window** (Runs 11/12/16–29/31/32 class). Sole first-seen change = the Run 32
      strong-execute checkpoint paragraph in RELAY_LOG.md (+4 lines); `git diff --name-only
      b315aed..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No code to review, no security surface,
      no new design decision/gate. gaming-scan clean (no DELETED_TEST/ADDED_SKIP/REMOVED_ASSERT).
      The RELAY_LOG paragraph is internally consistent (Run 32 verdict + suite 80/0). **No
      coherence drift this run** — the TODO id:401c MIRROR line and d5e0 summary were BOTH
      already current on arrival (Run 32). Cross-ledger coherent (0 open ROUTINE / 3 executable
      HARD — dba3 decision-gated / 401c / 3346; de4e DEFERRED non-executable; all three open in
      both ROADMAP+TODO; d5e0 agrees). Both tracked flakes (id:16e9, id:05e8) did NOT recur.
      Suite 80/0 on a clean run. See `docs/meeting-notes/2026-06-22-0317-strong-model-audit.md`.
    - Run 34 (2026-06-22-0712): first-seen change since Run 33's own audit merge `62b58fa`
      (`62b58fa..HEAD`, HEAD = checkpoint `relay-ckpt-20260622-0712` / `c95852b`) —
      **LEDGER-ONLY window**: `git diff --name-only 62b58fa..HEAD -- '*.sh' '*.py' '*.js'`
      is EMPTY (the window = two TODO+ROADMAP design-analysis commits, `ca1e5f1` id:7809 +
      `31d854b` id:98f0, plus the Run 33 RELAY_LOG checkpoint paragraph). No code to review,
      no security surface. gaming-scan clean (no DELETED_TEST/ADDED_SKIP/REMOVED_ASSERT).
      **Design-coherence pass (substantive this run, unlike the pure-vacuity LEDGER runs):**
      the two NEW `[HARD — meeting]` items are internally consistent and well-formed —
      id:7809 (auto-reconcile-on-restart: a `.relayactive`/heartbeat marker + a TIERED
      safe-vs-judgment orphan classifier — auto-integrate clean/green/ledger-only, SURFACE
      BLOCKED/partial/red; the zkm-stt fixture case is cited as live evidence the judgment
      tier is justified; relates 689c/3313/4e14/0902/98f0/194e — no contradiction) and
      id:98f0 (outage-resilient LOCAL loop: the user-corrected three-way bind — cloud
      `/schedule` survives an outage but can't reach local `~/src`/worktrees/fievel; the only
      local-reaching fit, an OS systemd timer running `claude -p "/relay --afk"`, hits the
      headless permission wall the user won't bypass with `--dangerously-skip-permissions`;
      options a–f well-formed, ties to id:2d01 dedicated-OS-user path — coherent). Both
      correctly routed `[HARD — meeting]` per id:78ff lanes and mirrored single-id-two-views
      into ROADMAP. **2 coherence drifts fixed inline** (the recurring Run 4/8/17 class): the
      TODO d5e0 summary still read "3 open ROADMAP items, all HARD" but the window added two
      open HARD (7809/98f0) → corrected to 5; the id:401c MIRROR line still read "Latest ✓
      Run 33" → refreshed to Run 34. Cross-ledger coherent after fix (0 open ROUTINE / 5
      executable HARD — 401c [pool] / 3346 / dba3 [decision-gate] / 7809 / 98f0; de4e DEFERRED
      non-executable; all five open in both ROADMAP+TODO; d5e0 agrees). Both tracked flakes
      (id:16e9, id:05e8) did NOT recur. Suite 80/0 on a clean run. See
      `docs/meeting-notes/2026-06-22-0712-strong-model-audit.md`.
    - Run 35 (2026-06-22-0722): first-seen change since Run 34's own merge `40bc011`
      (`40bc011..HEAD`, HEAD = checkpoint `relay-ckpt-20260622-0722` / `9702417`) —
      **LEDGER-ONLY window** (Runs 11/12/16/17 class). Sole first-seen change = the Run 34
      strong-execute checkpoint paragraph in RELAY_LOG.md (+4 lines); `git diff --name-only
      40bc011..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No code to review, no security
      surface, no new design decision/gate. gaming-scan clean (no DELETED_TEST/ADDED_SKIP/
      REMOVED_ASSERT). The Run 34 RELAY_LOG paragraph is internally consistent (verdict +
      window + suite count + mirror-drift note match its own meeting note + run log).
      Cross-ledger coherent (0 open ROUTINE / 5 executable HARD — 401c [pool] / 3346
      [meeting] / dba3 [decision-gate] / 7809 [meeting] / 98f0 [meeting]; de4e DEFERRED
      non-executable; all five open in both ROADMAP+TODO; d5e0 agrees, no count drift this
      run). **1 coherence drift fixed inline** (Run 4/8/17 mirror class) — the TODO id:401c
      MIRROR line still read "Latest ✓ Run 34"; refreshed to Run 35. Both tracked flakes
      (id:16e9, id:05e8) did NOT recur. Suite 80/0 on a clean run. See
      `docs/meeting-notes/2026-06-22-0722-strong-model-audit.md`.
    - Run 36 (2026-06-22-0737): first-seen change since Run 35's own merge `69c0bc5`
      (`69c0bc5..HEAD`, HEAD = checkpoint `relay-ckpt-20260622-0737` / `c0dece8`) —
      **LEDGER-ONLY window**: `git diff --name-only 69c0bc5..HEAD -- '*.sh' '*.py' '*.js'`
      is EMPTY (window = the new id:f576 TUI ghost-fragment TODO meta-issue `c54c96e`, the
      `-0730` review(relay) LEDGER-ONLY commit+merge `852c58a`/`4f2200d`, plus the
      `-0730`/`-0737` RELAY_LOG checkpoint paragraphs). No code to review, no security
      surface. gaming-scan clean (no DELETED_TEST/ADDED_SKIP/REMOVED_ASSERT; no test files
      changed). **Design-coherence pass (substantive):** the new id:f576 entry
      (Claude Code TUI ghost workflow-progress/statusline fragments after exiting
      `/workflows`) is internally consistent and well-formed — correctly classified
      cosmetic (Ctrl+L/SIGWINCH clears it), plausible render-race root cause, routed as an
      external/harness meta-issue with NO executable lane tag → correctly TODO-only (not
      promoted to ROADMAP, not in the d5e0 count); `#1 upgrade past v2.1.181` is sound (box
      runs 2.1.177); `disableWorkflows: true` correctly flagged UNSUITABLE here (relay pool
      depends on the Workflow tool) — no contradiction. RELAY_LOG checkpoint paragraphs
      internally consistent. **1 coherence drift fixed inline** (recurring Run 4/8/17/35
      mirror class) — the TODO id:401c MIRROR line still read "Latest ✓ Run 35"; refreshed
      to Run 36. Cross-ledger coherent (0 open ROUTINE / 5 executable HARD — 401c [pool] /
      3346 [meeting] / dba3 [decision-gate] / 7809 [meeting] / 98f0 [meeting]; de4e DEFERRED
      non-executable; all five open in both ROADMAP+TODO; d5e0 agrees, no count drift this
      run). Both tracked flakes (id:16e9, id:05e8) did NOT recur. Suite 80/0 on a clean run.
      See `docs/meeting-notes/2026-06-22-0737-strong-model-audit.md`.
    - Run 37 (2026-06-22-0942): first-seen change since Run 36's own audit merge `b93f024`
      (`b93f024..HEAD`, HEAD = checkpoint `relay-ckpt-20260622-0942` / `183a272`) —
      **SUBSTANTIVE CODE window** (breaks the Run 31/32/33/35/36 ledger-only streak): 403
      insertions / 6 files. First-seen code = the new `relay/scripts/roadmap-archive.sh`
      (id:6b67 [ROUTINE], Relay ROADMAP archiver, 167 L, shipped by a Sonnet executor in
      `f6f594b`) + `tests/test_roadmap_archive.sh` (201 L, 9 hermetic cases, `# roadmap:6b67`)
      + Makefile registration (relay_FILES/EXEC/ALLOW). **CLEAN — no code/security defects**
      across all 3 passes: trap-ordering sound (last EXIT trap cleans both temp+lock, no leak);
      conservative prior-commit/≥30d gate correct — a working-tree-only tick is NEVER archived
      (verified T3 positive / T4 negative); multi-line block capture + `<!-- id:XXXX -->` token
      preservation + no-section-pruning (deliberate divergence from archive-done.sh, ROADMAP
      headers are structural) all verified; quoted `<<'PYEOF'` heredoc with argv-passed inputs
      = no injection, no path traversal beyond the repo, stdlib-only Python, no secrets/network,
      lock covered by the `*.lock` gitignore. gaming-scan clean (test file wholly NEW — additions
      only, no deleted asserts / added skips / removed checks). Design coherent: id:93cc→id:6b67
      single-id-two-views chain sound (93cc = TODO "Prompt is too long" meta-issue, 6b67 =
      fix-direction (b) archiver promoted to ROADMAP; no duplicate-id mint; test maps its item;
      ticked `[x]` ⇒ suite green = DoD). **1 LOW accepted** — `trap 'rm "$LOCK_FILE"'` removes a
      flock'd lock file (unlink-race vs the canonical append.sh/git-lock-push.sh persistent-lock
      pattern); theoretical only — script is `-n` non-blocking (concurrent run cleanly skips),
      has NO automated caller today, rare+idempotent+single-writer; documented future-fix trigger
      (drop the rm if an automated caller is added). **Pre-existing accepted (out of window)** —
      `orphan-scan --cross-ledger` flags id:78ff/id:d9b0 as TODO:[ ]/ROADMAP:[x]; both predate
      this window and are the intended single-id-two-views shape (ROADMAP execution unit closed,
      broader TODO design-ledger umbrella stays open) — not drift from this window. **1 coherence
      drift fixed inline (recurring Run 4/8/17/35/36 mirror class)** — the TODO id:401c MIRROR
      line still read "Latest ✓ Run 36"; refreshed to Run 37 (d5e0 count line NOT stale this run
      — already 5 open HARD / 0 ROUTINE after id:6b67 closed). Cross-ledger coherent (0 open
      ROUTINE / 5 executable HARD — 401c [pool] / 3346 [meeting] / dba3 [decision-gate] / 7809
      [meeting] / 98f0 [meeting]; de4e DEFERRED non-executable; all five open in both
      ROADMAP+TODO; d5e0 agrees, no count drift this run). Both tracked flakes (id:16e9, id:05e8)
      did NOT recur. Suite 81/0 on a clean run. See
      `docs/meeting-notes/2026-06-22-0942-strong-model-audit.md`.
    - Run 38 (2026-06-22-0953): first-seen change since Run 37's own audit merge `8258aa3`
      (`8258aa3..HEAD`, HEAD = checkpoint `relay-ckpt-20260622-0953` / `9ec0b6b`) —
      **clean: LEDGER-ONLY window** (Run 11/12/16/17/31/32/33/35/36 class). Sole first-seen
      change = the Run 37 strong-execute checkpoint paragraph in RELAY_LOG.md (+4 lines);
      `git diff --stat` = `RELAY_LOG.md | 4 ++++` and `git diff --name-only 8258aa3..HEAD --
      '*.sh' '*.py' '*.js'` is EMPTY. No code to review (Pass 1 CLEAN by vacuity), no security
      surface (Pass 2 CLEAN by vacuity; `gaming-scan.sh "$repo" 8258aa3` exit 0, no output),
      no new design decision/gate (Pass 3 — the Run 37 checkpoint paragraph is internally
      consistent with the Run 37 run-log entry + meeting note: same window `b93f024..HEAD`,
      same id:6b67 subject, same suite 81/0; no contradiction). **Pre-existing accepted (out
      of window)** — `orphan-scan --cross-ledger` flags id:78ff/id:d9b0 as TODO:[ ]/ROADMAP:[x];
      both predate this window and are the intended single-id-two-views shape (already accepted
      Run 37). **1 coherence drift fixed inline (recurring Run 4/8/17/35/36/37 mirror class)** —
      the TODO id:401c MIRROR line still read "Latest ✓ Run 37"; refreshed to Run 38 (d5e0 count
      line NOT stale this run — already 5 open HARD / 0 ROUTINE, no items opened/closed). Cross-ledger
      coherent (0 open ROUTINE / 5 executable HARD — 401c [pool] / 3346 [meeting] / dba3
      [decision-gate] / 7809 [meeting] / 98f0 [meeting]; de4e DEFERRED non-executable; all five
      open in both ROADMAP+TODO; d5e0 agrees, no count drift this run). Both tracked flakes
      (id:16e9, id:05e8) did NOT recur. Suite 81/0 on a clean run. See
      `docs/meeting-notes/2026-06-22-0953-strong-model-audit.md`.
    - Run 39 (2026-06-22-1004): first-seen change since Run 38's own audit merge `0174a69`
      (`0174a69..HEAD`, HEAD = checkpoint `relay-ckpt-20260622-1004` / `3cb4d7a`) —
      **clean: LEDGER-ONLY window** (Run 11/12/16/17/31/32/33/35/36/38 class). Sole first-seen
      change = the Run 38 strong-execute checkpoint paragraph in RELAY_LOG.md (+4 lines);
      `git diff --stat` = `RELAY_LOG.md | 4 ++++` and `git diff --name-only 0174a69..HEAD --
      '*.sh' '*.py' '*.js'` is EMPTY. No code to review (Pass 1 CLEAN by vacuity), no security
      surface (Pass 2 CLEAN by vacuity; `gaming-scan.sh . 0174a69` exit 0, no output), no new
      design decision/gate (Pass 3 — the Run 38 checkpoint paragraph is internally consistent
      with the Run 38 run-log entry + meeting note: same window `8258aa3..HEAD`, same LEDGER-ONLY
      verdict, same suite 81/0; no contradiction). **Pre-existing accepted (out of window)** —
      `orphan-scan --cross-ledger` flags id:78ff/id:d9b0 as TODO:[ ]/ROADMAP:[x]; both predate
      this window and are the intended single-id-two-views shape (already accepted Run 37/38).
      **1 coherence drift fixed inline (recurring Run 4/8/17/35/36/37/38 mirror class)** — the
      TODO id:401c MIRROR line still read "Latest ✓ Run 38"; refreshed to Run 39 (d5e0 count
      line NOT stale this run — already 5 open HARD / 0 ROUTINE, no items opened/closed).
      Cross-ledger coherent (0 open ROUTINE / 5 executable HARD — 401c [pool] / 3346 [meeting]
      / dba3 [decision-gate] / 7809 [meeting] / 98f0 [meeting]; de4e DEFERRED non-executable;
      all five open in both ROADMAP+TODO; d5e0 agrees, no count drift this run). Both tracked
      flakes (id:16e9, id:05e8) did NOT recur. Suite 81/0 on a clean run. See
      `docs/meeting-notes/2026-06-22-1004-strong-model-audit.md`.
    - Run 40 (2026-06-22-1601): first **CODE** window since Run 39's LEDGER-ONLY runs —
      `3600642..HEAD` (HEAD = `relay-ckpt-20260622-1715` / `10d837e`), ~251 lines / 12 files.
      First-seen code: the id:93cc ROADMAP discovery-trimmer in `gather-repo-state.sh`, the
      id:7d1e per-verdict progress buckets in `relay-loop.js`, and the id:bde8 loop-hint
      resilience-wording correction (`loop-hint.sh` + SKILL.md), plus the id:98f0/7809
      outage-resilience meeting note. **1 forward-robustness defect fixed inline** — the id:93cc
      trimmer's `python3 … 2>/dev/null || true` failed CLOSED to an EMPTY roadmap on a trimmer
      crash → would silently misclassify the repo as `handoff` (relay-loop.js ~L630 "roadmap
      missing") and re-do C1/C2; changed to fail-OPEN `|| cat "$path/ROADMAP.md"` + a non-vacuous
      regression guard in `test_gather_repo_state.sh` (proven RED on the reverted `|| true` form).
      Pass-1 otherwise clean (trimmer block-parsing correct; per-verdict buckets pure display
      grouping, zero behavioural change, consistent with the pre-existing Integrate bucket).
      Pass-2 security clean (`gaming-scan.sh . 3600642` exit 0; no injection — trimmer reads a
      quoted env path, JS changes are literals). Pass-3 design-coherence: loop-hint correction
      matches memory `babysitter-durable-cron-no-op`; verified the meeting note's claimed
      `[HARD — meeting]→[HARD — hands]` retag of 7809/98f0 landed in ROADMAP and that new items
      e149/0994 are wired. **2 coherence drifts fixed inline (recurring d5e0/mirror class)** —
      (a) the d5e0 count line read "5 open ROADMAP items" with 7809/98f0 mislabelled
      `[HARD — meeting]`; corrected to 7 open HARD with e149/0994 added + the lane fix; (b) the
      TODO id:401c MIRROR line read "Latest ✓ Run 39"; refreshed to Run 40. Cross-ledger coherent
      (0 open ROUTINE / 7 open HARD — 401c [pool] / 3346 [meeting] / dba3 [decision-gate] /
      e149/7809/98f0/0994 [hands]; de4e DEFERRED non-executable; all open in both ROADMAP+TODO).
      Both tracked flakes (id:16e9, id:05e8) did NOT recur. Suite 82/0 test-files on a clean run
      (the new regression guard is an assertion inside test_gather_repo_state.sh, 17→18 cases).
      See `docs/meeting-notes/2026-06-22-1601-strong-model-audit.md`.
    - Run 41 (2026-06-22-1757): first-seen change since Run 40's own audit merge `f3c26f8`
      (`f3c26f8..HEAD`, HEAD = `relay-ckpt-20260622-1757` / `4574c3b`) — **LEDGER-ONLY window**
      (Runs 11/12/16/17/18/19/20/21/22/40 class). `git diff --name-only f3c26f8..HEAD -- '*.sh'
      '*.py' '*.js'` is EMPTY — the only code in the raw `10d837e..HEAD` range
      (`gather-repo-state.sh` + `test_gather_repo_state.sh`, `c941c4e`) is Run 40's OWN
      already-audited id:93cc fail-open fix, out of this window. First-seen changes: Run 40's
      strong-execute+review checkpoint paragraphs in RELAY_LOG.md; the Agent-SDK / `claude -p`
      subscription-billing DEFERRAL note (`e06088f` — new TODO `[MEETING]` id:00a5 multi-perspective
      applications eval + a dba3 "Billing path REAFFIRMED" addendum + a 98f0 billing parenthetical);
      and the review tick of TODO id:bde8 `[ ]`→`[x]` (`561c3fa`, cross-ledger D2 fix). No code to
      review, no security surface (`gaming-scan.sh . f3c26f8` exit 0). Pass-3 design-coherence:
      id:00a5 is internally sound (single TODO-only token, meeting-lane → correctly NOT promoted to
      ROADMAP; cross-refs id:2d01/98f0/dba3/hermes-deferral-contract all resolve), the billing notes
      across dba3/98f0/00a5/memory `anthropic-agent-sdk-billing-deferred` are mutually consistent (no
      contradiction with id:2d01's path-A rationale), and bde8 is now canonically `[x]` in both
      ledgers. **One coherence drift fixed inline (recurring mirror class, Run 4/8/17/21/40)** — the
      TODO id:401c MIRROR line read "Latest ✓ Run 40"; refreshed to Run 41. The d5e0 count line needed
      NO change (already 7 open HARD / 0 ROUTINE; no items opened/closed this window). Cross-ledger
      coherent (0 open ROUTINE / 7 open executable-or-gated HARD — 401c [pool] / 3346 [meeting] / dba3
      [decision-gate] / e149/7809/98f0/0994 [hands]; de4e DEFERRED non-executable; all open in both
      ROADMAP+TODO). Both tracked flakes (id:16e9, id:05e8) did NOT recur. Suite 82/0 on a clean run.
      See `docs/meeting-notes/2026-06-22-1757-strong-model-audit.md`.
    - Run 42 (2026-06-22-1818): first-seen change since Run 41's own audit merge `b65ba59`
      (`b65ba59..HEAD`, HEAD = `relay-ckpt-20260622-1818` / `00f54cf`) — **LEDGER-ONLY window**
      (Runs 11/12/16/17/18/19/20/21/22/40/41 class). `git diff --name-only b65ba59..HEAD -- '*.sh'
      '*.py' '*.js'` is EMPTY. Sole first-seen change = the 4-line Run 41 strong-execute checkpoint
      paragraph in RELAY_LOG.md (`00f54cf`). No code to review, no security surface
      (`gaming-scan.sh . b65ba59` exit 0). Pass-3 design-coherence: the checkpoint paragraph
      accurately mirrors Run 41 (LEDGER-ONLY, CLEAN by vacuity, suite 82/0, 1 mirror-line drift);
      no item opened/closed this window. **One coherence drift fixed inline (recurring mirror
      class, Run 4/8/17/40/41)** — the TODO id:401c MIRROR line read "Latest ✓ Run 41"; refreshed
      to Run 42. The d5e0 count line needed NO change (already 7 open HARD / 0 ROUTINE).
      Cross-ledger coherent (0 open ROUTINE / 7 open executable-or-gated HARD — 401c [pool] /
      3346 [meeting] / dba3 [decision-gate] / e149/7809/98f0/0994 [hands]; de4e DEFERRED
      non-executable; all open in both ROADMAP+TODO). Both tracked flakes (id:16e9, id:05e8) did
      NOT recur. Suite 82/0 on a clean run. See `docs/meeting-notes/2026-06-22-1818-strong-model-audit.md`.
    - Run 43 (2026-06-22-1827): first-seen change since Run 42's own audit commit `a56bed7`
      (`a56bed7..HEAD`, HEAD = `relay-ckpt-20260622-1827` / `9db884a`) — **LEDGER-ONLY window**
      (Runs 11/12/16/17/18/19/20/21/22/40/41/42 class). `git diff --name-only a56bed7..HEAD -- '*.sh'
      '*.py' '*.js'` is EMPTY. Sole first-seen change = the 4-line Run 42 strong-execute checkpoint
      paragraph in RELAY_LOG.md (`9db884a`). No code to review, no security surface
      (`gaming-scan.sh . a56bed7` exit 0). Pass-3 design-coherence: the checkpoint paragraph
      accurately mirrors Run 42 (LEDGER-ONLY, CLEAN by vacuity, suite 82/0); no item opened/closed
      this window. **One coherence drift fixed inline (recurring mirror class, Run 4/8/17/40/41/42)**
      — the TODO id:401c MIRROR line read "Latest ✓ Run 42"; refreshed to Run 43. The d5e0 count
      line needed NO change (already 7 open HARD / 0 ROUTINE).
      Cross-ledger coherent (0 open ROUTINE / 7 open executable-or-gated HARD — 401c [pool] /
      3346 [meeting] / dba3 [decision-gate] / e149/7809/98f0/0994 [hands]; de4e DEFERRED
      non-executable; all open in both ROADMAP+TODO). Both tracked flakes (id:16e9, id:05e8) did
      NOT recur. Suite 82/0 on a clean run. See `docs/meeting-notes/2026-06-22-1827-strong-model-audit.md`.
    - Run 44 (2026-06-23-0701): first-seen code since Run 43's own audit commit `c66c6f4`
      (`c66c6f4..HEAD`, HEAD = `relay-ckpt-20260622-2215` / `e5962f3`) — **REAL CODE window**
      (not LEDGER-ONLY): id:bae5 uv.lock-cascade exemptions (`gather-repo-state.sh`
      `lock_only_unaudited`/`dirty_lock_only` + relay-loop.js review/dirty exemptions),
      id:e107 EXECUTOR-ACTIONABLE @manual/human-only guard (relay-loop.js), id:2c42 deferred
      ledger write-back (meeting/SKILL.md + todo-update/SKILL.md + .gitignore + red→green spec).
      **CLEAN — no inline code/security fix.** Pass-1: bae5's lock booleans diff the SAME
      `latest..HEAD` range as `commits_since` (can't disagree with the review verdict), use a
      fixed-string whole-line `grep -vx 'uv.lock'` (root-only, conservative), all new pipelines
      `set -e`-safe (`|| true` + `[[ ]]`); `$NF` porcelain extraction correct for modify/rename;
      e107 mirrors the EXECUTABLE-HARD gate pattern (id:2d20) — no-op-execute thrash rationale
      sound. Pass-2: gather additions pure-read (no eval/injection/secrets); bae5 dirty-lock
      auto-commit is a bounded named git op on a trusted relay.toml path; id:2c42 replay applies
      only under a FRESH claim via allowlisted flock'd helpers. Pass-3: bae5/e107 slot cleanly
      into the documented precedence (no never-firing gate, no contradiction); id:2c42 matches
      its acceptance verbatim (generic breadcrumb wired only at step 2a, replay in both /meeting
      + /todo-update, gitignore entry); af04 note records the worktree-per-/meeting rejection.
      `gaming-scan.sh . c66c6f4` exit 0. **One coherence drift fixed inline (recurring mirror
      class, Run 4/8/17/40/41/42/43)** — the TODO id:401c MIRROR line read "Latest ✓ Run 43";
      refreshed to Run 44. The d5e0 count line needed NO change (already 7 open HARD / 0 ROUTINE;
      the id:2c42 ROUTINE item closed this window). Cross-ledger coherent (0 open ROUTINE / 7 open
      executable-or-gated HARD — 401c [pool] / 3346 [meeting] / dba3 [decision-gate] /
      e149/7809/98f0/0994 [hands]; de4e DEFERRED non-executable; all open in both ROADMAP+TODO).
      Both tracked flakes (id:16e9, id:05e8) did NOT recur. Suite 83/0 on a clean run. See
      `docs/meeting-notes/2026-06-23-0701-strong-model-audit.md`.
    - Run 45 (2026-06-23-0939): first-seen code since Run 44's own audit commit `0e60f1f`
      (`0e60f1f..HEAD`, HEAD = `relay-ckpt-20260623-0923` / `6dbecf9`) — **REAL CODE window**:
      id:000d deterministic `is_finished` guard (gather-repo-state.sh + relay-loop.js),
      id:1d64 margin-aware quota-stop staleness, id:3c0f `[HARD — pool]` token sync,
      id:69ef install-manifest completeness guard; id:09a3 (`roadmap-lint.sh`) shipped only
      its RED spec `tests/test_roadmap_lint.sh` (script not yet written) — correctly
      EXPECTED-RED, item still open. **1 HIGH defect FIXED INLINE (id:000d):** the JS-side
      `is_finished` demote guard was DEAD code — `DISCOVER_SCHEMA.units[]` did not declare
      `is_finished` and the shard-prompt per-repo-fields list never instructed copying it, so
      the deterministic value computed by gather-repo-state.sh never reached the unit object
      (the JS reads `u.is_finished`, which was always `undefined`). The only live path was the
      non-deterministic LLM shard-prompt instruction — exactly the path id:000d's backstop
      existed to correct; the pre-existing structural test passed because it grepped the guard
      TEXT, not its behaviour. Fixed: declared the schema property, added an explicit "COPY
      is_finished verbatim" prompt line, and added two non-vacuous assertions to
      `test_relay_loop_structure.sh` (schema declares it + prompt instructs the copy) that fail
      on the pre-fix form. Pass-1 otherwise CLEAN: id:1d64 moved `decay_threshold`/`bucket_threshold`
      earlier so they're defined before the new stale-margin block calls them (correct ordering),
      margin math + missing-bucket→exit2 sound; id:3c0f/69ef pure literal/positive-grammar checks.
      Pass-2: no new injection/traversal/secrets (`awk -v` + `${!envname}` read fixed-domain
      provider/bucket inputs; is_finished block pure-read). Pass-3: the guard now closes its own
      loop (deterministic value → unit → JS backstop), demote-only invariant intact, no
      contradiction with the bae5 lock-only-dirty exemption. `gaming-scan.sh . d068334` exit 0.
      **Mirror drift fixed inline (Run 4/8/17/… class)** — TODO id:401c MIRROR line read "Latest
      ✓ Run 44"; refreshed to Run 45. Cross-ledger coherent (0 open ROUTINE after 000d/1d64/3c0f/69ef
      closed this window; open executable-or-gated HARD: 09a3 [pool] / 3346 [meeting] / dba3
      [decision-gate] / e149/7809/98f0/0994 [hands]; de4e DEFERRED non-executable; the d5e0 prose
      enumeration is slated for dissolution under id:1de1/659c and still predates id:09a3 — left
      as-is, not re-enumerated, since 09a3's re-dispatch is suppressed and the count authority is
      moving to the id:2840 index). Both tracked flakes (id:16e9, id:05e8) did NOT recur. Suite
      87/0 + 1 EXPECTED-RED (id:09a3) on a clean run. See
      `docs/meeting-notes/2026-06-23-0939-strong-model-audit.md`.
    - Run 46 (2026-06-23-0945): `d342839..HEAD` (window start = Run 45's audit-note
      commit) — **LEDGER-ONLY, CLEAN by vacuity**. Only commits: `b2b6ee9` (the `--no-ff`
      merge LANDING Run 45's already-audited work — not re-audited) + `1d4b9cb` (checkpoint,
      RELAY_LOG +4). `git diff d342839..HEAD` excluding RELAY_LOG/relay.toml is EMPTY → no
      first-seen code (passes 1+2 N/A). **One coherence finding, fixed inline:**
      `orphan-scan --cross-ledger` flagged id:3c0f/69ef (TODO:[ ] vs ROADMAP:[x]) — a
      scope-split FALSE-POSITIVE (id:d9b0 §3 class): both builds genuinely closed in
      ROADMAP/Run 45; their tokens appear in TODO only inside the still-open umbrella
      line-34 ("lane-token drift + grammar lint", pending id:09a3). Added the
      `<!-- xledger-ok: ... -->` annotation id:d9b0 built for exactly this → cross-ledger
      now exits clean. id:09a3 NOT annotated (still open in ROADMAP too, parked orphan, no
      divergence). gaming-scan `"$PWD" d342839` exit 0; suite 87/0 + 1 EXPECTED-RED (id:09a3).
      Mirror: TODO id:401c line refreshed Run 45→Run 46. See
      `docs/meeting-notes/2026-06-23-0945-strong-model-audit.md`.
    - Run 48 (2026-06-23-1730): first-seen code since Run 46's own audit commit `993d905`
      (merge `80a8441..HEAD`) — **REAL CODE** (Run 47 review shipped id:ad74 + id:09a3 in
      this window, never strong-audited). **1 HIGH defect fixed inline**: the id:ad74
      JS-side INTENSIVE promote backstop in relay-loop.js was a NO-OP — the exact symmetric
      twin of the id:401c Run 45 dead-guard bug, in the very feature meant to be the PROMOTE
      counterpart of that DEMOTE guard. Branch 1 (skipped→unit) was provably-dead code
      (`top_intensive && !u` unreachable; skipped rollup items carry no `top_intensive`);
      branch 2 patched an idle unit's `.intensive` but never flipped `verdict` off `'idle'`,
      so `actionable = units.filter(u => u.verdict !== 'idle')` dropped it BEFORE the
      INTENSIVE partition — silent drop, not even surfaced as deferred. Rewrote to operate
      on emitted units only and FLIP idle→execute (survives the filter → intensive partition
      → `ALLOW_INTENSIVE ? intensiveUnits : intensiveDeferred`); dropped the dead branch.
      Added non-vacuous static guards (2c)/(2d) to `test_relay_loop_intensive_emit.sh`
      (verified: both FAIL against pre-fix JS, pass against fix). roadmap-lint.sh (id:09a3)
      + gather `top_intensive` field clean; lint correctly wired into review §5 + human. 1
      coherence ACCEPTED (c3a6 cache: `top_intensive` is a pure fn of the already-hashed
      ROADMAP blob → no sig change). Cross-ledger drift fixed inline (id:ad74 TODO:[ ] vs
      ROADMAP:[x] — build now genuinely complete post-fix → ticked the TODO twin). gaming-scan
      `"$PWD" 80a8441` exit 0; suite 89/0/0. Mirror: TODO id:401c refreshed Run 46→Run 48
      (Run 47 was the review that shipped this window, not an audit run). See
      `docs/meeting-notes/2026-06-23-1730-strong-model-audit.md`.
    - Run 49 (2026-06-23-1749): first-seen change since Run 48's own audit merge `7dfe7e0`
      (`7dfe7e0..HEAD`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46 class). Sole
      first-seen change = the Run 48 strong-execute checkpoint paragraph in RELAY_LOG.md
      (+4 lines); `git diff --name-only 7dfe7e0..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No
      code to review, no security surface, no new design decision/gate. The RELAY_LOG
      paragraph is internally consistent (Run 48 verdict + suite 89/0/0 + the id:ad74 fix).
      Cross-ledger coherent (0 open ROUTINE / 7 open executable-or-gated HARD — 401c [pool] /
      3346 [meeting] / dba3 [decision-gate] / e149 / 7809 / 98f0 / 0994 [hands]; de4e DEFERRED
      non-executable; all open in both ROADMAP+TODO; d5e0 agrees). roadmap-lint.sh exit 0;
      gaming-scan `"$PWD" 7dfe7e0` exit 0; suite 89/0/0. Tracked flakes 16e9/05e8 did NOT
      recur. Mirror: TODO id:401c line refreshed Run 48→Run 49. See
      `docs/meeting-notes/2026-06-23-1749-strong-model-audit.md`.
    - Run 50 (2026-06-23-1724): first-seen change since Run 49's own audit merge `12b151e`
      (`12b151e..HEAD`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46/49 class). Sole
      first-seen change = the Run 49 strong-execute checkpoint paragraph in RELAY_LOG.md
      (+4 lines); `git diff --name-only 12b151e..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No
      code to review, no security surface, no new design decision/gate. The RELAY_LOG
      paragraph is internally consistent (Run 49 verdict + roadmap-lint 0/gaming-scan 0/suite
      89/0/0). Cross-ledger coherent (0 open ROUTINE / 7 open executable-or-gated HARD — 401c
      [pool] / 3346 [meeting] / dba3 [decision-gate] / e149 / 7809 / 98f0 / 0994 [hands]; de4e
      DEFERRED non-executable; all open in both ROADMAP+TODO; d5e0 agrees). orphan-scan
      --cross-ledger exit 0; roadmap-lint.sh exit 0; gaming-scan `"$PWD" 12b151e` exit 0;
      suite 89/0/0. Tracked flakes 16e9/05e8 did NOT recur. Mirror: TODO id:401c line
      refreshed Run 49→Run 50. See `docs/meeting-notes/2026-06-23-1724-strong-model-audit.md`.
    - Run 51 (2026-06-23-1724b): first-seen change since Run 50's own audit merge `b46be9a`
      (`b46be9a..HEAD`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46/49/50 class). Sole
      first-seen change = the Run 50 strong-execute checkpoint paragraph in RELAY_LOG.md
      (+4 lines); `git diff --name-only b46be9a..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY (verified
      the earlier `efbb7bd` id:d530 TODO note is an ancestor of `b46be9a` — covered by Run 50,
      not first-seen). No code to review, no security surface, no new design decision/gate. The
      RELAY_LOG paragraph is internally consistent (Run 50 verdict + roadmap-lint 0/gaming-scan
      0/suite 89/0/0). Cross-ledger coherent (0 open ROUTINE / 7 open executable-or-gated HARD —
      401c [pool] / 3346 [meeting] / dba3 [decision-gate] / e149 / 7809 / 98f0 / 0994 [hands]; de4e
      DEFERRED non-executable; all open in both ROADMAP+TODO; d5e0 agrees). orphan-scan
      --cross-ledger exit 0; roadmap-lint.sh exit 0; gaming-scan `"$PWD" b46be9a` exit 0;
      suite 89/0/0. Tracked flakes 16e9/05e8 did NOT recur. Mirror: TODO id:401c line
      refreshed Run 50→Run 51. See `docs/meeting-notes/2026-06-23-1724b-strong-model-audit.md`.
    - Run 52 (2026-06-23-1724c): first-seen change since Run 51's own audit merge `9dfce93`
      (`9dfce93..HEAD`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46/49/50/51 class). Sole
      first-seen change = the Run 51 strong-execute checkpoint paragraph in RELAY_LOG.md
      (+4 lines); `git diff --name-only 9dfce93..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No
      code to review, no security surface, no new design decision/gate. The RELAY_LOG
      paragraph is internally consistent (Run 51 verdict + orphan-scan/roadmap-lint/gaming-scan
      0/suite 89/0/0). Cross-ledger coherent (0 open ROUTINE / 7 open executable-or-gated HARD —
      401c [pool] / 3346 [meeting] / dba3 [decision-gate] / e149 / 7809 / 98f0 / 0994 [hands]; de4e
      DEFERRED non-executable; all open in both ROADMAP+TODO; d5e0 agrees). orphan-scan
      --cross-ledger exit 0; roadmap-lint.sh exit 0; gaming-scan `"$PWD" 9dfce93` exit 0;
      suite 89/0/0. Tracked flakes 16e9/05e8 did NOT recur. Mirror: TODO id:401c line
      refreshed Run 51→Run 52. See `docs/meeting-notes/2026-06-23-1724c-strong-model-audit.md`.
    - Run 53 (2026-06-23-1724d): first-seen change since Run 52's own audit merge `8052b4f`
      (`8052b4f..HEAD`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46/49/50/51/52 class).
      Window = the Run 52 strong-execute checkpoint paragraph in RELAY_LOG.md (+4) AND one new
      TODO discussion item, id:9000 (`[HARD — meeting]` inter-session coordination channel, +1);
      `git diff --name-only 8052b4f..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No code to review,
      no security surface. Coherence pass on the sole new design artifact (TODO id:9000):
      `[HARD — meeting]` lane correct for a discussion placeholder; every cross-reference
      resolves to a real, consistent item (id:0902/ebfb lease / id:c144 ledger-lease-exempt /
      id:2c42 deferred write-back / id:c012 `/relay stop` / id:98f0/e149 watchdog heartbeat);
      observe-first gate (≥2–3 recurrences, FIRST logged instance) intact, no contradiction
      with the af04 worktree-per-meeting rejection — sound entry, no defect. Cross-ledger
      coherent (0 open ROUTINE / 7 open executable-or-gated HARD — 401c [pool] / 3346 [meeting]
      / dba3 [decision-gate] / e149 / 7809 / 98f0 / 0994 [hands]; de4e DEFERRED non-executable;
      all open in both ROADMAP+TODO; d5e0 agrees). orphan-scan --cross-ledger exit 0;
      roadmap-lint.sh exit 0; gaming-scan `"$PWD" 8052b4f` exit 0; suite 89/0/0. Tracked flakes
      16e9/05e8 did NOT recur. Mirror: TODO id:401c line refreshed Run 52→Run 53. See
      `docs/meeting-notes/2026-06-23-1724d-strong-model-audit.md`.
    - Run 54 (2026-06-23-1909): first-seen change since Run 53's own audit merge `e905c84`
      (`e905c84..HEAD`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46/49/50/51/52/53 class).
      Window = two RELAY_LOG checkpoint paragraphs (Run 53 strong-execute 18:38 + reviewer
      doc-only 18:51, +8) AND one in-place TODO edit to id:9000 (the UPDATE 2026-06-23
      incident-resolved urgency-reframe, ±1); `git diff --name-only e905c84..HEAD -- '*.sh'
      '*.py' '*.js'` is EMPTY. No code to review, no security surface. Coherence pass on the
      sole new design artifact (id:9000 reframe): correctly narrows scope from "prevent
      corruption" (now redundant) to "avoid wasted stale-base work + surface intent" because
      the cited backstop **id:aa93** (dirty-main-checkout guard, ROADMAP `[x]` shipped
      2026-06-18 — clean-tree-gate.sh in integrate step 1) RESOLVES and supports the claim;
      observe-first gate STRENGTHENED ("the backstop held"), every original cross-ref
      preserved + resolves, lane tag unchanged — sound entry, no defect. Cross-ledger
      coherent (0 open ROUTINE / 7 open executable-or-gated HARD — 401c [pool] / 3346 [meeting]
      / dba3 [decision-gate] / e149 / 7809 / 98f0 / 0994 [hands]; de4e DEFERRED non-executable;
      all open in both ROADMAP+TODO; d5e0 agrees). orphan-scan --cross-ledger exit 0;
      roadmap-lint.sh exit 0; gaming-scan `"$PWD" e905c84` exit 0; suite 89/0/0. Tracked flakes
      16e9/05e8 did NOT recur. Mirror: TODO id:401c line refreshed Run 53→Run 54. See
      `docs/meeting-notes/2026-06-23-1909-strong-model-audit.md`.
    - Run 55 (2026-06-23-1724e): window = since Run 54's audit merge `2cd8d6e`
      (`2cd8d6e..HEAD`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46/49/50/51/52/53/54
      class). `git diff --name-only 2cd8d6e..HEAD` = only RELAY_LOG.md + TODO.md;
      `*.sh`/`*.py`/`*.js` diff EMPTY. Window = three RELAY_LOG checkpoint paragraphs
      (8e041af reviewer 18:51, 92addcb strong-execute 19:13 = Run 54's own ckpt, 4ee6ffd
      reviewer 19:40) AND one `todo(meeting)` commit (8679992) minting two new
      design-deferred TODO items. No code → no Pass-1/Pass-2 surface (clean by vacuity).
      Pass-3 coherence on the sole new design artifact: id:74c7 (`/meeting --cross` inline
      path skips canonical persona-load setup) + id:d23f (same inline path skips the
      EnterPlanMode→ExitPlanMode approval gate) — both minted, sharply scoped to an
      explicit a-vs-b decision (re-dispatch-always vs carry-scaffolding), correctly
      cross-referenced (id:1d01 distinguished, id:d44d, id:a6cb, each other), cite the
      source zkm meeting note, and correctly TODO-parked (design judgment needed, not
      ROADMAP-promotable). id:d23f correctly carves out the by-design Class-3
      decisions→ledger deferral as NOT-the-bug. No contradiction, no dead gate, no defect.
      Cross-ledger coherent (0 open ROUTINE / 7 open executable-or-gated HARD — 401c [pool]
      / 3346 [meeting] / dba3 [decision-gate] / e149 / 7809 / 98f0 / 0994 [hands]; de4e
      DEFERRED non-executable; 401c/3346/dba3 open in both ROADMAP+TODO; d5e0 agrees).
      orphan-scan --cross-ledger exit 0; roadmap-lint.sh exit 0; gaming-scan `"$PWD" 2cd8d6e`
      exit 0; suite 89/0/0. Tracked flakes 16e9/05e8 did NOT recur. Mirror: TODO id:401c
      line refreshed Run 54→Run 55. See `docs/meeting-notes/2026-06-23-1724e-strong-model-audit.md`.
    - Run 56 (2026-06-23-2024): window = since Run 55's audit merge `578c854`
      (`578c854..HEAD`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46/49/50/51/52/53/54/55
      class). `git diff --name-only 578c854..HEAD` = only RELAY_LOG.md;
      `*.sh`/`*.py`/`*.js` diff EMPTY. Sole commit `ca4a743` (checkpoint 20260623-2001
      strong-execute) adds one RELAY_LOG paragraph = Run 55's own checkpoint record. No
      code → no Pass-1/Pass-2 surface (clean by vacuity); no new TODO/ROADMAP design
      item, gate, or contract change → no Pass-3 artifact. Cross-ledger coherent (0 open
      ROUTINE / 7 open executable-or-gated HARD — 401c [pool] / 3346 [meeting] / dba3
      [decision-gate] / e149 / 7809 / 98f0 / 0994 [hands]; de4e DEFERRED non-executable;
      401c/3346/dba3 open in both ROADMAP+TODO; d5e0 agrees). orphan-scan --cross-ledger
      exit 0; roadmap-lint.sh exit 0; gaming-scan `"$PWD" 578c854` exit 0; suite 89/0/0.
      Tracked flakes 16e9/05e8 did NOT recur. Mirror: TODO id:401c line refreshed
      Run 55→Run 56. See `docs/meeting-notes/2026-06-23-2024-strong-model-audit.md`.
    - Run 57 (2026-06-23-2031): window = since Run 56's audit merge `9782379`
      (`9782379..HEAD`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46/49/50/51/52/53/54/55/56
      class). `git diff --name-only 9782379..HEAD` = only RELAY_LOG.md;
      `*.sh`/`*.py`/`*.js` diff EMPTY. Sole commit `2b60f5f` (checkpoint 20260623-2011
      strong-execute) adds one RELAY_LOG paragraph = Run 56's own checkpoint record. No
      code → no Pass-1/Pass-2 surface (clean by vacuity); no new TODO/ROADMAP design
      item, gate, or contract change → no Pass-3 artifact. Cross-ledger coherent (0 open
      ROUTINE / 7 open executable-or-gated HARD — 401c [pool] / 3346 [meeting] / dba3
      [decision-gate] / e149 / 7809 / 98f0 / 0994 [hands]; de4e DEFERRED non-executable;
      401c/3346/dba3 open in both ROADMAP+TODO; d5e0 agrees). orphan-scan --cross-ledger
      exit 0; roadmap-lint.sh exit 0; gaming-scan `"$PWD" 9782379` exit 0; suite 89/0/0.
      Tracked flakes 16e9/05e8 did NOT recur. Mirror: TODO id:401c line refreshed
      Run 56→Run 57. See `docs/meeting-notes/2026-06-23-2031-strong-model-audit.md`.
    - Run 58 (2026-06-23-2037): window = since Run 57's audit merge `9b2abd7`
      (`9b2abd7..HEAD`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46/49/50/51/52/53/54/55/56/57
      class). `git diff --name-only 9b2abd7..HEAD` = only RELAY_LOG.md;
      `*.sh`/`*.py`/`*.js` diff EMPTY. Sole commit `3813fef` (checkpoint 20260623-2021
      strong-execute) adds one RELAY_LOG paragraph = Run 57's own checkpoint record. No
      code → no Pass-1/Pass-2 surface (clean by vacuity); no new TODO/ROADMAP design
      item, gate, or contract change → no Pass-3 artifact. Cross-ledger coherent (0 open
      ROUTINE / 7 open executable-or-gated HARD — 401c [pool] / 3346 [meeting] / dba3
      [decision-gate] / e149 / 7809 / 98f0 / 0994 [hands]; de4e DEFERRED non-executable;
      401c/3346/dba3 open in both ROADMAP+TODO; d5e0 agrees). orphan-scan --cross-ledger
      exit 0; roadmap-lint.sh exit 0; gaming-scan `"$PWD" 9b2abd7` exit 0; suite 89/0/0.
      Tracked flakes 16e9/05e8 did NOT recur. Mirror: TODO id:401c line refreshed
      Run 57→Run 58. See `docs/meeting-notes/2026-06-23-2037-strong-model-audit.md`.
    - Run 59 (2026-06-23-2040): window = since Run 58's audit merge `c8d4469`
      (`c8d4469..HEAD`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46/49/50/51/52/53/54/55/56/57/58
      class). `git diff --name-only c8d4469..HEAD` = only RELAY_LOG.md;
      `*.sh`/`*.py`/`*.js` diff EMPTY. Sole commit `8d8838d` (checkpoint 20260623-2029
      strong-execute) adds one RELAY_LOG paragraph = Run 58's own checkpoint record. No
      code → no Pass-1/Pass-2 surface (clean by vacuity); no new TODO/ROADMAP design
      item, gate, or contract change → no Pass-3 artifact. Cross-ledger coherent (0 open
      ROUTINE / 7 open executable-or-gated HARD — 401c [pool] / 3346 [meeting] / dba3
      [decision-gate] / e149 / 7809 / 98f0 / 0994 [hands]; de4e DEFERRED non-executable;
      401c/3346/dba3 open in both ROADMAP+TODO; d5e0 agrees). orphan-scan --cross-ledger
      exit 0; roadmap-lint.sh exit 0; gaming-scan `"$PWD" c8d4469` exit 0; suite 89/0/0.
      Tracked flakes 16e9/05e8 did NOT recur. Mirror: TODO id:401c line refreshed
      Run 58→Run 59. See `docs/meeting-notes/2026-06-23-2040-strong-model-audit.md`.
    - Run 60 (2026-06-23-2044): window = since Run 59's audit merge `73e4903`
      (`73e4903..daf5694`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46/49/50/51/52/53/54/55/56/57/58/59
      class). `git diff --name-only 73e4903..daf5694` = only RELAY_LOG.md;
      `*.sh`/`*.py`/`*.js` diff EMPTY. Sole commit `daf5694` (checkpoint 20260623-2038
      strong-execute) adds one RELAY_LOG paragraph = Run 59's own checkpoint record. No
      code → no Pass-1/Pass-2 surface (clean by vacuity); no new TODO/ROADMAP design
      item, gate, or contract change → no Pass-3 artifact. Cross-ledger coherent (0 open
      ROUTINE / 7 open executable-or-gated HARD — 401c [pool] / 3346 [meeting] / dba3
      [decision-gate] / e149 / 7809 / 98f0 / 0994 [hands]; de4e DEFERRED non-executable;
      401c/3346/dba3 open in both ROADMAP+TODO; d5e0 agrees). orphan-scan --cross-ledger
      exit 0; roadmap-lint.sh exit 0; gaming-scan `"$PWD" 73e4903` exit 0; suite 89/0/0.
      Tracked flakes 16e9/05e8 did NOT recur. Mirror: TODO id:401c line refreshed
      Run 59→Run 60. See `docs/meeting-notes/2026-06-23-2044-strong-model-audit.md`.
    - Run 61 (2026-06-23-2054): window = since Run 60's audit merge `9da3a6f`
      (`9da3a6f..HEAD`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46/49/50/51/52/53/54/55/56/57/58/59/60
      class). `git diff --name-only 9da3a6f..HEAD` = only RELAY_LOG.md;
      `*.sh`/`*.py`/`*.js` diff EMPTY. Sole commit `a4d670b` (checkpoint 20260623-2047
      strong-execute) adds one RELAY_LOG paragraph = Run 60's own checkpoint record. No
      code → no Pass-1/Pass-2 surface (clean by vacuity); no new TODO/ROADMAP design
      item, gate, or contract change → no Pass-3 artifact. Cross-ledger coherent (0 open
      ROUTINE / 7 open executable-or-gated HARD — 401c [pool] / 3346 [meeting] / dba3
      [decision-gate] / e149 / 7809 / 98f0 / 0994 [hands]; de4e DEFERRED non-executable;
      401c/3346/dba3 open in both ROADMAP+TODO; d5e0 agrees). orphan-scan --cross-ledger
      exit 0; roadmap-lint.sh exit 0; gaming-scan `"$PWD" 9da3a6f` exit 0; suite 89/0/0.
      Tracked flakes 16e9/05e8 did NOT recur. Mirror: TODO id:401c line refreshed
      Run 60→Run 61. See `docs/meeting-notes/2026-06-23-2054-strong-model-audit.md`.
    - Run 62 (2026-06-23-2102): window = since Run 61's audit merge `91d639a`
      (`91d639a..HEAD`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46/49/50/51/52/53/54/55/56/57/58/59/60/61
      class). `git diff --name-only 91d639a..HEAD` = only RELAY_LOG.md;
      `*.sh`/`*.py`/`*.js` diff EMPTY. Sole commit `564f217` (checkpoint 20260623-2056
      strong-execute) adds one RELAY_LOG paragraph = Run 61's own checkpoint record. No
      code → no Pass-1/Pass-2 surface (clean by vacuity); no new TODO/ROADMAP design
      item, gate, or contract change → no Pass-3 artifact. Cross-ledger coherent (0 open
      ROUTINE / 7 open executable-or-gated HARD — 401c [pool] / 3346 [meeting] / dba3
      [decision-gate] / e149 / 7809 / 98f0 / 0994 [hands]; de4e DEFERRED non-executable;
      401c/3346/dba3 open in both ROADMAP+TODO; d5e0 agrees). orphan-scan --cross-ledger
      exit 0; roadmap-lint.sh exit 0; gaming-scan `"$PWD" 91d639a` exit 0; suite 89/0/0.
      Tracked flakes 16e9/05e8 did NOT recur. Mirror: TODO id:401c line refreshed
      Run 61→Run 62. See `docs/meeting-notes/2026-06-23-2102-strong-model-audit.md`.
    - Run 63 (2026-06-23-2110): window = since Run 62's audit merge `a360ac6`
      (`a360ac6..HEAD`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46/49/50/51/52/53/54/55/56/57/58/59/60/61/62
      class). `git diff --name-only a360ac6..HEAD` = only RELAY_LOG.md;
      `*.sh`/`*.py`/`*.js` diff EMPTY. Sole commit `e7d7e4f` (checkpoint 20260623-2104
      strong-execute) adds one RELAY_LOG paragraph = Run 62's own checkpoint record. No
      code → no Pass-1/Pass-2 surface (clean by vacuity); no new TODO/ROADMAP design
      item, gate, or contract change → no Pass-3 artifact. Cross-ledger coherent (0 open
      ROUTINE / 7 open executable-or-gated HARD — 401c [pool] / 3346 [meeting] / dba3
      [decision-gate] / e149 / 7809 / 98f0 / 0994 [hands]; de4e DEFERRED non-executable;
      401c/3346/dba3 open in both ROADMAP+TODO; d5e0 agrees). orphan-scan --cross-ledger
      exit 0; roadmap-lint.sh exit 0; gaming-scan `"$PWD" a360ac6` exit 0; suite 89/0/0.
      Tracked flakes 16e9/05e8 did NOT recur. Mirror: TODO id:401c line refreshed
      Run 62→Run 63. See `docs/meeting-notes/2026-06-23-2110-strong-model-audit.md`.
    - Run 64 (2026-06-23-1724f): `c8127e0..HEAD` (HEAD `69dd4d8`) — **LEDGER-ONLY clean
      by vacuity**. `git diff --name-only c8127e0..HEAD` = only `RELAY_LOG.md`;
      `*.sh`/`*.py`/`*.js` diff EMPTY. Sole commit `69dd4d8` (checkpoint 20260623-2113
      strong-execute) adds one RELAY_LOG paragraph = Run 63's own checkpoint record. No
      code → no Pass-1/Pass-2 surface (clean by vacuity); no new TODO/ROADMAP design
      item, gate, or contract change → no Pass-3 artifact. Cross-ledger coherent (0 open
      ROUTINE / 7 open executable-or-gated HARD — 401c [pool] / 3346 [meeting] / dba3
      [decision-gate] / e149 / 7809 / 98f0 / 0994 [hands]; de4e DEFERRED non-executable;
      401c/3346/dba3 open in both ROADMAP+TODO; d5e0 agrees). orphan-scan --cross-ledger
      exit 0; roadmap-lint.sh exit 0; gaming-scan `"$PWD" c8127e0` exit 0; suite 89/0/0.
      Tracked flakes 16e9/05e8 did NOT recur. Mirror: TODO id:401c line refreshed
      Run 63→Run 64. See `docs/meeting-notes/2026-06-23-1724f-strong-model-audit.md`.
    - Run 65 (2026-06-23-1724g): window = since Run 64's audit merge `69dd4d8`
      (`69dd4d8..HEAD`, HEAD `17c062f`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46/49–64
      class). `git diff --name-only 69dd4d8..HEAD` = RELAY_LOG.md + ROADMAP.md + TODO.md + the
      Run 64 meeting note (all Run 64's own audit + checkpoint ledger writes);
      `*.sh`/`*.py`/`*.js` diff EMPTY. Commits = `34c8a1c` (Run 64 audit), `417321f` (its
      merge), `17c062f` (checkpoint 20260623-2123 = Run 64's own record). No code → no
      Pass-1/Pass-2 surface (clean by vacuity); no new TODO/ROADMAP design item, gate, or
      contract change → no Pass-3 artifact (Run 64's own ledger records are internally
      consistent: its verdict + cited gates match this run's re-verification; TODO mirror
      Run 63→64 correct). Cross-ledger coherent (0 open ROUTINE / 7 open executable-or-gated
      HARD — 401c [pool] / 3346 [meeting] / dba3 [decision-gate] / e149 / 7809 / 98f0 / 0994
      [hands]; de4e DEFERRED non-executable; 401c/3346/dba3 open in both ROADMAP+TODO; d5e0
      agrees). orphan-scan --cross-ledger exit 0; roadmap-lint.sh exit 0; gaming-scan
      `"$PWD" 69dd4d8` exit 0; suite 89/0/0. Tracked flakes 16e9/05e8 did NOT recur. Mirror:
      TODO id:401c line refreshed Run 64→Run 65. See
      `docs/meeting-notes/2026-06-23-1724g-strong-model-audit.md`.
    - Run 66 (2026-06-23-1724h): window = since Run 65's audit commit `9330f72`
      (`9330f72..HEAD`, HEAD `62fc2c7`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46/49–65
      class). `git diff --name-only 9330f72..HEAD` = RELAY_LOG.md only (Run 65's own checkpoint
      paragraph); `*.sh`/`*.py`/`*.js` diff EMPTY. Commits = `5b1e0a4` (Run 65 merge), `62fc2c7`
      (checkpoint 20260623-2132 = Run 65's own record). No code → no Pass-1/Pass-2 surface (clean
      by vacuity); no new TODO/ROADMAP design item, gate, or contract change → no Pass-3 artifact
      (Run 65's own RELAY_LOG paragraph is internally consistent: its verdict + cited gates match
      this run's re-verification). Cross-ledger coherent (0 open ROUTINE / 7 open executable-or-gated
      HARD — 401c [pool] / 3346 [meeting] / dba3 [decision-gate] / e149 / 7809 / 98f0 / 0994
      [hands]; de4e DEFERRED non-executable; 401c/3346/dba3 open in both ROADMAP+TODO; d5e0
      agrees). orphan-scan --cross-ledger exit 0; roadmap-lint.sh exit 0; gaming-scan
      `"$PWD" 9330f72` exit 0; suite 89/0/0. Tracked flakes 16e9/05e8 did NOT recur. Mirror:
      TODO id:401c line refreshed Run 65→Run 66. See
      `docs/meeting-notes/2026-06-23-1724h-strong-model-audit.md`.
    - Run 67 (2026-06-23-2145): window = since Run 66's audit commit `a689119`
      (`a689119..HEAD`, HEAD `5e1a216`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46/49–66
      class). `git diff --name-only a689119..HEAD` = RELAY_LOG.md only (Run 66's own checkpoint
      paragraph, +4 lines); `*.sh`/`*.py`/`*.js` diff EMPTY. Commits = `b8cda3c` (Run 66 merge),
      `5e1a216` (checkpoint 20260623-2140 = Run 66's own record). No code → no Pass-1/Pass-2 surface
      (clean by vacuity); no new TODO/ROADMAP design item, gate, or contract change → no Pass-3
      artifact (Run 66's own RELAY_LOG paragraph is internally consistent: its verdict + cited checks
      match this run's re-verification). Cross-ledger coherent (0 open ROUTINE / 7 open
      executable-or-gated HARD — 401c [pool] / 3346 [meeting] / dba3 [decision-gate] / e149 / 7809 /
      98f0 / 0994 [hands]; de4e DEFERRED non-executable; 401c/3346/dba3 open in both ROADMAP+TODO;
      d5e0 agrees). orphan-scan --cross-ledger exit 0; roadmap-lint.sh exit 0; gaming-scan
      `"$PWD" a689119` exit 0; suite 89/0/0. Tracked flakes 16e9/05e8 did NOT recur. Mirror:
      TODO id:401c line refreshed Run 66→Run 67. See
      `docs/meeting-notes/2026-06-23-2145-strong-model-audit.md`.
    - Run 69 (2026-06-30-1855): window = `8d8d40b..HEAD` (HEAD `7527cb1`), since Run 68 —
      133 commits / ~6007 insertions across 88 files; substantive engine surface ~21
      scripts+code files + tests (`substantive_unaudited=true`). Four days of mechanical-classifier
      (id:4d8e) + outage-resilience build: NEW classify-verdict.sh (85df), classify-repo.sh (3f0f),
      backtest-verdict.py (5f93), decision-queue.sh (de31), drain.mjs (d58f), heartbeat.sh (e149),
      host-gate.sh (43b9), memory-append.sh (6f61), pathspec-drop-guard.py (b67e), relay-watchdog
      (98f0); MODIFIED relay-loop.js (drain/heartbeat/phase-buckets/worked_ids/quota-extrapolation),
      gather-repo-state.sh + classify-repo.sh execve-overflow temp-file fix (07be/3f0f), claim.sh
      heartbeat-gated liveness (33d3), scan-routed --apply (678e), ckpt-tag graceful degrade (a7a3).
      **Pass-1 code review CLEAN** + **Pass-2 security CLEAN** (no correctness/injection defects —
      verified classify-verdict pure-stdin parity-guards, execve temp-file fixes, heartbeat
      ts+TTL, claim fail-safe heartbeat gate, decision-queue set-e-safe resolve, drain.mjs
      byte-identical inline copy, scan-routed idempotent flock'd write, per-round heartbeat keyed on
      stable state.runId). **Pass-3: 2 ledger drifts FIXED INLINE** — (1) id:1bbd `[x]` ROADMAP /
      `[ ]` TODO (lane-anchor fix shipped+merged → ROADMAP authoritative; ticked the TODO twin);
      (2) d5e0 count prose listed the shipped e149/7809/98f0/0994 [HARD — hands] batch as open —
      re-derived to 3 open executable-or-gated (401c [pool] / 3346 [meeting] / dba3 [decision-gate];
      de4e [meeting] DEFERRED). orphan-scan --cross-ledger now 0; roadmap-lint 0; gaming-scan
      `"$PWD" 8d8d40b` 0; todo-conformance 0; suite 135/0/0. 3 accepted-not-defect items (scan-routed
      inbox-done swallow + new-id fallback, pathspec-guard conservative-block). See
      `docs/meeting-notes/2026-06-30-1855-strong-model-audit.md`.
    - Run 68 (2026-06-26-0926): window = `5e1a216..HEAD` (HEAD `8d8d40b`), since Run 67 —
      **first NON-ledger window since Run 48** (`substantive_unaudited=true`): ~4091/-50 across
      35 files (14 scripts + 21 tests), three days of relay-engine work (id:5c00 quota pre-gate,
      c012 graceful-stop, d530 --priority/--exclude, 9973 HARD-pool demote-guard, 365b
      recurring-audit gate + circuit breaker, a707 human-gated INTENSIVE carve-out, 1b11 PID
      claim, 9221 orphan first-wins, c095 heading-as-item, a643 resource claim, 2147 atomic
      ledger commit, 71f2 workflow-template lint, 3441 todo-conformance, 678e scan-routed,
      2dea unpromoted-scan, relay-doctor). **Pass-1 code review CLEAN** (no correctness defects —
      verified commit-ledger scoped-add+escape-reject, todo-conformance stable-lineno --fix +
      duplicate-mint guard, gather substantive_unaudited fail-open + deterministic work_sig,
      relay-loop demote/breaker/pre-gate all demote-only+injected-exempt, the
      lint-workflow-templates single-pass lexer). **Pass-2 security CLEAN** (sed/jq/path/PID
      surfaces: 4-hex id validation before sed, realpath `../*|/*` reject, `jq -n --arg`,
      numeric-only `kill -0` with documented conservative PID-reuse caveat). **Pass-3: 1
      cross-ledger drift FIXED INLINE** — id:5c00 was `[x]` in ROADMAP but `[ ]` in TODO (work
      genuinely done+merged → ROADMAP authoritative); ticked the TODO twin, orphan-scan
      --cross-ledger now exit 0. todo-conversion-policies.md v1 + the 9973/365b/a707/000d guard
      lattice internally coherent. **Accepted (not a defect):** gaming-scan
      `ADDED_SKIP:test_relay_doctor_wiring.sh:60` = benign false-positive (the regex
      `report.only` substring tripped the heuristic on a real report-only assertion).
      roadmap-lint exit 0; todo-conformance exit 0; gaming-scan `"$PWD" 5e1a216` exit 0;
      suite 106/1/0 — the 1 failure is the KNOWN flaky `test_resource_claim_pid.sh` (id:ab5c),
      passed 3/3 in isolation → effectively 107 green. Mirror: TODO id:401c line refreshed
      Run 67→Run 68. See `docs/meeting-notes/2026-06-26-0926-strong-model-audit.md`.

- [x] Autonomous relay front-door: `/fables-turn` no-keyword default mode [HARD — strong model] (done 2026-06-12, reviewer) <!-- id:230f -->
  - **Why HARD**: redesigns the fables-turn SKILL.md trigger surface and dispatch logic; requires
    judgment on the unattended-safe confirmation contract and how the skill hands off to the Workflow engine;
    wrong front-door behaviour silently skips repos or blocks the unattended run.
  - **Acceptance**: invoking `/fables-turn` with no keyword (no `handoff`/`review` argument) starts the
    autonomous pool loop. Non-interactive by default: operates only on relay.toml `classification=own`
    confirmed repos; surfaces (never asks about) new/dirty/needs_review repos in `RELAY_STATUS.md`.
    `--interactive` flag re-enables `AskUserQuestion` confirmations. Front door invokes the
    `relay-loop.js` Workflow script (id:83c9) and exits after the Workflow completes, printing the
    RELAY_STATUS.md path and HANDBACK count. Existing `handoff` and `review` keyword modes are
    unchanged and fully compatible. SKILL.md updated to document the new default mode and the knobs
    (`STRONG_TIER`, `--interactive`, quota-threshold env var).
  - **Tests**: `tests/test_fables_front_door.sh` (`# roadmap:230f`) — verify (1) no-keyword invocation
    without relay.toml confirmed repos surfaces a message + exits cleanly; (2) `--interactive` flag is
    passed through to Workflow args; (3) existing keyword modes remain functional (dry-run check).
  - **Done-check**: `tests/run-tests.sh tests/test_fables_front_door.sh` then full `make test` after ticking
  - **Context**: meeting note `docs/meeting-notes/2026-06-12-2045-fables-relay-autonomous-pool.md` D1/D2.
    fables-turn/SKILL.md and relay-loop.js (id:83c9) must coexist. Workflows are opt-in by design (user
    invoking the command counts as explicit opt-in per harness rules — no extra gate needed).

- [x] Workflow script `relay-loop.js` — priority-mixed 5-wide autonomous pool [HARD — strong model] (done 2026-06-12, reviewer) <!-- id:83c9 -->
  - **Why HARD**: complex Workflow JS orchestrating pool concurrency, the serialized integrator, quota
    guards, and graceful drain — all interacting. Wrong sequencing causes concurrent pushes (the
    double-decrement bug from prior executor runs); wrong quota gate causes runaway or premature stop;
    wrong graceful-drain loses in-flight worktrees.
  - **Acceptance**: `fables-turn/scripts/relay-loop.js` is a valid Workflow script with `export const meta`.
    Scheduler: per-repo classifier maps confirmed repos to {execute(Sonnet)/review(strong)/handoff(strong)/idle};
    pool fills up to 5 execute slots first; backfills idle slots with review (unreviewed-executor-work priority
    > fresh handoff). SERIALIZED integrator: after each agent completes, ONE coordinator agent runs
    `--no-ff` merge → `ckpt-tag.sh` → `git-lock-push.sh --ff-only` — never two repos integrating concurrently
    (one-push-per-repo-per-turn invariant). Quota-stop: calls the id:9934 quota helper; on threshold crossed,
    stops dispatching new units and lets in-flight agents + ALL integration debt finish before `return`.
    `STRONG_TIER` env var (default `fable`, `opus` pilotable) sets `model:` on review/handoff agents.
    `log()` emits phase transitions; `RELAY_STATUS.md` rewritten on each integration.
    **Income preference (user directive 2026-06-12):** within a verdict class, repos flagged
    `income = true` in relay.toml are dispatched first; the class ordering itself is unchanged.
  - **Tests**: `tests/test_relay_loop_structure.sh` (`# roadmap:83c9`) — static checks: (1) `meta` block
    present with required fields; (2) no `AskUserQuestion` call in the script; (3) integration block
    serialized (no bare `parallel()` over the integration step); (4) `STRONG_TIER` variable referenced.
    Integration-behaviour tests deferred to the A6 pilot (live integration is too expensive for unit tests).
  - **Done-check**: `tests/run-tests.sh tests/test_relay_loop_structure.sh` then full `make test` after ticking
  - **Context**: meeting note D2/D3/D5. Gil's constraint: Workflow JS can't run git; the integrator MUST
    be an agent that calls the bash scripts. Petra's fallback (not default): if the in-script integrator
    proves unwieldy, the integrator agent returns branch names and the front-door turn integrates — but
    don't build the fallback pre-emptively. Reuses `scripts/ckpt-tag.sh`, `scripts/discover-repos.sh`,
    and `git-diary-workflow/git-lock-push.sh --ff-only`. See also id:9934 (quota helper) and id:aeaf (STRONG_TIER).

- [x] Tier-aware quota-stop helper for relay-loop.js [ROUTINE] <!-- id:9934 -->
  - **Acceptance**: `fables-turn/scripts/quota-stop.sh [--tier sonnet|strong]` (or a JS helper inline in
    relay-loop.js) reads `/tmp/claude-usage-cache.json` and exits 0 (below threshold) or 1 (at/above).
    Sonnet tier: stop if `seven_day_sonnet`, `five_hour`, OR `seven_day` utilization ≥ threshold
    (env `RELAY_QUOTA_THRESHOLD`, default 0.90 = 90%). Strong tier: stop if `five_hour` OR `seven_day`
    ≥ threshold. **Scale (review fix 2026-06-12):** the live cache stores `.utilization` as a
    0–100 percent (e.g. `37.0`), while `RELAY_QUOTA_THRESHOLD` is a 0–1 fraction — the script
    converts internally (`val >= threshold*100`). Tests must use percent-scale fixtures. Stale cache (mtime > 10 min) or missing file → print a warning to stderr and exit 2
    (caller treats as "stop, uncertain"); missing-key in JSON → same. Threshold 0.90 is the default;
    override via env for piloting. Seatbelt: if agent-count arg `N` ≥ 200 or wall-clock arg `S` seconds ≥ 7200,
    also exit 1 regardless of cache.
  - **Tests**: `tests/test_quota_stop.sh` (`# roadmap:9934`) — synthetic cache JSONs at 0.85/0.90/0.95
    utilization for each relevant bucket; stale/missing file; seatbelt cap triggers.
  - **Done-check**: `tests/run-tests.sh tests/test_quota_stop.sh` then full `make test` after ticking
  - **Context**: meeting note D5. `/tmp/claude-usage-cache.json` format is maintained by
    `statusline/statusline-command.sh` (keys: `five_hour`, `seven_day`, `seven_day_sonnet`, each with
    a `percent_used` or similar field — verify the exact key names from the statusline script before coding).
    NEVER call `/api/oauth/usage` directly (429s after ~5 requests total).

- [x] `STRONG_TIER` config knob in relay-loop.js and front-door SKILL.md [ROUTINE] <!-- id:aeaf -->
  - **Acceptance**: relay-loop.js reads `STRONG_TIER` env var (values: `fable` | `opus`, default `fable`);
    passes it as `model:` override to all review and handoff agent() calls. Front-door SKILL.md documents
    the knob: `STRONG_TIER=opus /fables-turn` or `--strong-tier opus` flag. Sonnet execute agents never
    receive the STRONG_TIER override. If `STRONG_TIER` is unset or empty, defaults to `fable`.
  - **Tests**: `tests/test_strong_tier_knob.sh` (`# roadmap:aeaf`) — verify the JS script references
    `STRONG_TIER` and the SKILL.md documents it (grep-based static check).
  - **Done-check**: `tests/run-tests.sh tests/test_strong_tier_knob.sh` then full `make test` after ticking
  - **Context**: meeting note D4. Opus model ID: `claude-opus-4-8`. fable-class model match: `claude-fable-5`.
    Workflow agent() `model:` override is a first-class field — no wrapper needed.

- [x] `RELAY_STATUS.md` cross-repo rollup writer [ROUTINE] <!-- id:80e2 -->
  - **Acceptance**: relay-loop.js writes/rewrites `~/.config/relay/RELAY_STATUS.md` (or a path
    configurable via `RELAY_STATUS_PATH` env var) on every integration and every phase transition.
    Template sections: `## In-flight` (repo, mode, agent-id), `## Completed this run` (repo, mode,
    ckpt-tag, push status), `## Queued` (repo, classifier verdict), `## Blocked / HANDBACKs` (repo,
    reason, worktree path), `## Quota remaining` (all three buckets with % remaining and reset time if
    available), `## REVIEW_ME open items` (per-repo count + path). Header: `# RELAY_STATUS — last updated
    <ISO timestamp>  run: <runId>`. File is overwritten each time (not appended). Also printed to `log()`
    as a condensed one-liner on each rewrite (so /workflows live view shows progress without the full file).
  - **Tests**: `tests/test_relay_status.sh` (`# roadmap:80e2`) — verify template sections present and
    non-empty for a synthetic completed-run payload; verify `log()` line appears in the condensed form.
  - **Done-check**: `tests/run-tests.sh tests/test_relay_status.sh` then full `make test` after ticking
  - **Context**: meeting note "Surfacing (settled, no vote)". Per-repo REVIEW_ME.md stays the judgment-call
    channel (written by handoff/review children as before). RELAY_STATUS.md is read-only for humans —
    never edited by executor sessions.

- [x] Pilot autonomous pool on 1–2 income repos [HARD — strong model] (done 2026-06-12, run relay-20260612-2304: 6 integrated, 3 HANDBACKs recovered, quota drain verified; retrospective in RELAY_LOG.md 23:50 entry; Opus-handoff pilot NOT run — no handoff units classified; follow-ups id:bae5/59ea/1dff) <!-- id:1ad7 -->
  - **Why HARD**: first-contact with the real relay loop; templates and the executor contract will need
    revision after seeing actual unattended behaviour; judgment required on HANDBACK handling, REVIEW_ME
    quality, and whether priority-mixed scheduling converges as designed. Also the natural window to pilot
    `STRONG_TIER=opus` on handoff/review and compare output quality.
  - **Acceptance**: at least one complete unattended run on zkWhale or trAIdBTC (income repos) without
    manual intervention. `RELAY_STATUS.md` is produced **with all six template sections populated
    correctly — this is the behavioral check of the id:80e2 writer (its unit test is static-grep
    only; rescoped here by 2026-06-12 review)**. Any HANDBACKs are documented with root-cause.
    A short retrospective paragraph is appended to RELAY_LOG.md in this (dotclaude-skills) repo noting
    what needed revision and whether the Opus-handoff pilot was run.
  - **Tests**: none (pilot output is the deliverable; follow-on fixes get their own tests/items)
  - **Done-check**: `RELAY_STATUS.md` exists post-run; retrospective paragraph committed to RELAY_LOG.md here.
  - **Context**: meeting note A6 / D3 / D6. Gate: id:230f (front door) + id:83c9 (relay-loop.js) + id:9934
    (quota helper) must all be implemented first. Do not run fleet-wide until at least one income-repo
    pilot validates the design. This item is the verification gate before `--all` runs.

- [x] `--fable-down` / `-d` flag for executor-only relay runs (Fable inaccessible) [HARD — strong model] (done 2026-06-13, reviewer) <!-- id:3737 -->
  - **Why HARD**: touches the dispatch contract in relay-loop.js (pool partitioning, zero-execute edge,
    deferred-unit surfacing) plus the SKILL.md front-door (Opus self-guard, Workflow args pass-through,
    invocation block, knobs table). Wrong placement would silently skip the Opus guard or fail to
    surface deferred units, masking the outage.
  - **Acceptance**: `--fable-down`/`-d` flag parsed by the front door and passed as `args.fableDown`
    into `relay-loop.js`. When set: (1) review and handoff units are partitioned out of the dispatch
    queue and surface in RELAY_STATUS Queued with reason `deferred: --fable-down, strong model skipped`;
    (2) execute (Sonnet) units proceed normally; (3) zero-execute edge exits cleanly with a log line;
    (4) integrator, quota gate, and drain logic are untouched. Opus self-guard in SKILL.md Default-mode
    step 0: if the session model is `claude-opus-*` and `-d` is not set, print a warning + `sleep 10`
    before launching the Workflow; suppressed when `-d` is set. Auto-probe deferred (forward-compatible:
    a future probe sets `args.fableDown = true` identically).
  - **Tests**: `tests/test_fable_down_flag.sh` (`# roadmap:3737`) — 11 static-grep checks
  - **Done-check**: `tests/run-tests.sh tests/test_fable_down_flag.sh` then full `make test` ✓
  - **Context**: meeting note `docs/meeting-notes/2026-06-13-0825-fable-down-detection.md`;
    https://www.anthropic.com/news/fable-mythos-access (access pull announced).

- [x] Separate Fable-availability from fallback policy (two-switch: `-d` × `STRONG_TIER`) [ROUTINE] <!-- id:5902 -->
  - **Acceptance**: `--fable-down`/`-d` asserts ONE axis only — "the Fable strong tier is
    unavailable this run" — and composes with `STRONG_TIER` (which chooses WHICH strong
    model review/handoff agents use). The FABLE_DOWN defer/demote block in `relay-loop.js`
    is gated on `FABLE_DOWN && STRONG_MODEL === 'claude-fable-5'`: (1) `-d` alone (STRONG_TIER
    `fable`) → defer strong work, executor-only (prior id:3737 behaviour, preserved exactly);
    (2) `-d` + `STRONG_TIER=opus` (STRONG_MODEL `claude-opus-4-8`) → SUBSTITUTE Opus, skip the
    defer block, dispatch review/handoff normally on Opus (already marked `fable-standin` by
    `standInSuffix`). Startup `log()` and explanatory comment describe both axes. SKILL.md
    knobs row documents defer-vs-substitute; a `/fables-turn -d --strong-tier opus` usage
    example is added near the STRONG_TIER examples.
  - **Tests**: `tests/test_fable_down_strong_tier.sh` (`# roadmap:5902`) — static-grep that the
    defer block is gated on `STRONG_MODEL === 'claude-fable-5'`, that no ungated `if (FABLE_DOWN) {`
    remains, and that SKILL.md documents the substitute combo + usage example.
  - **Done-check**: `tests/run-tests.sh tests/test_fable_down_strong_tier.sh` then full `make test` ✓
  - **Context**: follow-up to id:3737. The `-d` flag conflated "Fable unavailable" with "defer
    all strong work"; STRONG_TIER already chose the strong model, so the two compose. Opus
    model ID `claude-opus-4-8`; Fable-class match `claude-fable-5`.

- [x] [ROUTINE] `gaming-scan.sh` — mechanical gaming detector extracted from `review.md` §2 (done 2026-06-15) <!-- id:fa05 -->
  - **Source**: id:2909 meeting 2026-06-15 (`docs/meeting-notes/2026-06-15-1610-adversarial-review-anti-gaming.md`), Piece 1 / D2-D3.
  - **Spec**: `relay/scripts/gaming-scan.sh`, `set -euo pipefail`, args `<repo-root> <since-tag>`. Emits one parseable flag line per mechanical detection:
    - deleted test file: `git diff "$since"..HEAD --diff-filter=D --name-only -- '<test-dirs>'`
    - added `skip`/`xfail`/`.only`/`@pytest.mark.skip` in test files
    - removed `assert`/expectation lines without an equivalent addition in test files
  - **Acceptance**: `tests/test_gaming_scan.sh` (roadmap:fa05) — crafted minimal git repos/diffs: (a) deleted test file → flag emitted; (b) added `@pytest.mark.skip` → flag; (c) removed `assert` line → flag; (d) clean diff (e.g. implementation file only changed) → SILENT. At least one negative control (a legitimate green diff that must NOT flag, modelled on the id:3b02 resurrection case from RELAY_LOG: only input line changed, assertions intact). `make test` green.

- [x] [ROUTINE] `review.md` §2 delegate rewrite — single source of truth (done 2026-06-15) <!-- id:dfaf -->
  - **Source**: id:2909 meeting 2026-06-15 (`docs/meeting-notes/2026-06-15-1610-adversarial-review-anti-gaming.md`), Piece 2 / D3. **Depends on id:fa05 shipping first** (script must exist before prose delegates to it).
  - **Spec**: rewrite `relay/references/review.md` §2 so it: (a) invokes `gaming-scan.sh <repo-root> $LAST` as the mechanical pass and surfaces its output; (b) retains prose ONLY for the judgment-residue checks (resurrection-check + fixture-special-casing); (c) removes the inlined `--diff-filter=D` / `skip`/`xfail` grep one-liners from prose (they now live in the script). Single source of truth: script owns mechanical, prose owns judgment.
  - **Acceptance**: static-grep test (`tests/test_gaming_scan.sh` or a sibling) asserts `review.md` references `gaming-scan.sh` and does NOT contain the old literal one-liners (`--diff-filter=D`, `xfail`, `skip` inline in §2). `make test` green.

- [x] [ROUTINE] Supervisor flag-rate logger in `relay-loop.js` `integrate()` (done 2026-06-15) <!-- id:3826 -->
  - **Source**: id:2909 meeting 2026-06-15 (`docs/meeting-notes/2026-06-15-1610-adversarial-review-anti-gaming.md`), Piece 4 / D1-D3.
  - **Spec**: in `relay-loop.js` `integrate()`, after the `gaming_flags` / `verified_green` / `reopened` fields are available in the review `report`, append a line to `~/.claude/logs/relay-gaming-flags.log` with JSON fields: `{repo, runId, ts, closed_ids, gaming_flags, reopened, verified_green}`. Create the log file if absent. Also add a comment block at the append site: `// DEFERRED-FLEET SEAM: to escalate, spawn parallel() refuters over gaming_flags[] or verified_green[] here; see id:2909 meeting 2026-06-15 D1 for the evidence gate.`
  - **Acceptance**: `tests/test_gaming_logger.sh` (roadmap:3826) — construct a synthetic `report` object with non-empty `gaming_flags` and call the relevant integrate path (or extract the logger into a standalone function that can be called from a test harness); assert the log file receives a line containing the expected repo name, runId, and flag id. `make test` green.

- [x] [HARD — strong model] Tier B model canary harness for gaming-detection judgment checks (done 2026-06-16) <!-- id:414a -->
  - **Done 2026-06-16** (relay HARD child): `tests/gaming-canary/` ships three crafted
    fixtures — `resurrection-rewrite/` (executor rewrote the test ASSERTION to match buggy
    `str(a)+str(b)` output; expects FLAG), `fixture-special-casing/` (impl branches on the
    exact test-input literals 6/28/12 instead of computing the divisor sum; expects FLAG),
    and the `negative-control-input-only/` (real id:3b02 shape — only the test INPUT changed,
    assertion structure + a genuine impl fix intact; expects EMPTY). Each fixture's diff is
    ≤20 lines. `tests/gaming-canary/run.sh` feeds each fixture + a compact review.md §2b
    judgment prompt to one review-style agent (`claude -p --output-format json` by default,
    `CANARY_AGENT` override for token-free plumbing tests; unwraps the claude JSON envelope;
    SKIPs—never false-passes—when no agent is present) and asserts the `gaming_flags`
    contract. `make gaming-canary` invokes it; it is excluded from `run-tests.sh` (globs
    `tests/test_*.sh`) so `make test` stays zero-token. The harness PLUMBING is
    regression-guarded token-free by `tests/test_gaming_canary.sh` (Tier A, in the default
    sweep) using stub agents — pins the FLAG/EMPTY/envelope/no-agent/determinism contract.
  - **Source**: id:2909 meeting 2026-06-15 (`docs/meeting-notes/2026-06-15-1610-adversarial-review-anti-gaming.md`), Piece 3 / D2. **NOT in `run-tests.sh` default sweep** — zero-token; invoked manually via `make gaming-canary`.
  - **Why HARD**: fixtures are prepared mini git repos containing *intentionally crafted gamed diffs* for the judgment checks (resurrection-check, fixture-special-casing) that gaming-scan.sh deliberately does NOT cover mechanically. The harness spawns one review-style agent per fixture and asserts the `gaming_flags` contract — the design of convincing-but-detectable fixtures requires strong-model craft.
  - **Spec**: `tests/gaming-canary/` directory: (a) at least one resurrection-rewrite fixture (an executor rewrote a test's `assert` to match whatever the code returns); (b) at least one fixture-special-casing fixture (code branches on exact test-input literals); (c) at least one **negative control** (a legitimate green resurrection where only the test INPUT changed and assertions stayed intact — must NOT flag). `tests/gaming-canary/run.sh` feeds each fixture diff to a compact review-procedure prompt and checks `gaming_flags`/absence. `Makefile` target `gaming-canary` invokes `run.sh`.
  - **Acceptance**: `make gaming-canary` executes: positive fixtures yield non-empty `gaming_flags`; negative control yields empty `gaming_flags`. The harness itself must not be flaky on identical inputs. Keep each fixture minimal (≤20 lines of diff) so the judgment is unambiguous.
  - **Gate CLEARED 2026-06-15** (audit run 4): id:fa05 (gaming-scan.sh) and id:dfaf (review.md §2 delegate) both shipped — `review.md` now references `gaming-scan.sh` (3×) and the script exists, so the review procedure this harness invokes already delegates mechanical checks. The item is dispatchable; it is HARD because crafting convincing-but-detectable fixtures needs strong-model judgment, not because of an unmet dependency.

- [ ] Sub-agent meeting simulation for main-ctx isolation [HARD — meeting] <!-- id:3346 -->
  - **Why HARD**: architectural — moves the whole meeting transcript generation out
    of the main context into a sub-agent; touches broker contract, persona loading,
    decision routing, and note-writing; wrong cut loses the user's live view.
  - **Acceptance**: see TODO id:3346. **GATED — do not start**: gate is "opencode
    port validated (proves broker contract is stable) + ≥1 meeting with ctx > 200k".
    Listed here for visibility only; remains parked in TODO.md until the gate fires.

- [x] Rename relay state dirs `~/.{config,cache}/fables-turn` → relay naming [HARD — strong model] (done 2026-06-17; code-rename only — the data migration was left half-done, see id:bbd2 for the proper completion) <!-- id:10c0 -->
- [x] Complete the id:10c0 state-dir migration properly + fix the split-brain regression [HARD — strong model] (done 2026-06-17, TDD) <!-- id:bbd2 -->
  - **What broke**: code defaulted to `~/.config/relay` but `relay.toml` was still at `~/.config/fables-turn` and both dirs were real (no symlink) → `gather-human-backlog.sh` silently returned an empty `/relay human` backlog. `migrate-state-dirs.sh` existed but was buggy (skip-on-collision → never symlinked) and never installed/run.
  - **Fix**: rewrote `migrate-state-dirs.sh` to reconcile collisions (merge `*.jsonl` union, union dirs, newest-mtime snapshot, drop `*.lock`), env-overridable for hermetic tests, exit 3 on idle-guard refusal. Spec'd by `tests/test_migrate_state_dirs.sh` (9 cases). Ran for real: old dirs → symlinks→`relay`, events merged 347+12→358 (no loss), gather returns 48 on default path. `make install-relay` linked it. Suite 66/66.
  - **Why HARD**: not the mechanical sed (33 `fables-turn` refs across 13 executable
    files + ~25 docs) but the LIVE-migration / back-compat design call. These are live
    dirs an in-flight pool reads/writes (relay.toml registry, RELAY_STATUS.md,
    relay-events.jsonl, quota-samples.jsonl, fable-probe.json, worktrees/) — needs a
    one-time `mv` + back-compat (symlink-old→new or fallback-read) so a running pool /
    cross-session lease isn't broken mid-migration.
  - **Back-compat design call — RESOLVED 2026-06-17 (Opus apex, via `/relay human`):**
    **symlink-old→new + run-when-idle, symlink kept permanently as the safety net.**
    Migration script `relay/scripts/migrate-state-dirs.sh` does, in order: (1) PRECONDITION
    — refuse unless no relay pool is active (no fresh `RELAY_STATUS.md` touch within
    `RELAY_ACTIVE_SECS`, and `claim.sh` registry shows no live holder); (2) `mkdir -p
    ~/.config/relay ~/.cache/relay`; (3) `mv` the contents over; (4) replace each old dir
    with a symlink `~/.config/fables-turn → ~/.config/relay`, `~/.cache/fables-turn →
    ~/.cache/relay`. The symlink is the load-bearing back-compat net: any straggler
    process, cross-session lease, un-updated ref, or older checkout still resolves the old
    path correctly, so there is NO window where old-path access fails (the only
    non-atomic gap is between mv and symlink — sub-second, and the idle precondition
    covers it). Rejected alternatives: dual-read fallback in code (churns every accessor,
    no upside over a symlink) and hard cutover with no net (re-introduces the
    in-flight-breakage risk the symlink eliminates). Keep the symlink indefinitely — it is
    cheap and is the only thing protecting a pool that started before the migration.
  - **Acceptance** (now UNGATED — bounded hard-execute): (1) `migrate-state-dirs.sh` exists
    with the idle-precondition guard and is idempotent (re-run is a no-op once symlinks
    exist); (2) the 33 `fables-turn` refs across the 13 executable files are updated to the
    new canonical `relay` path in the same change (the symlink covers anything missed, but
    new code reads the new name); (3) git tags `fable-ckpt-*` are NOT touched (constraint
    a — scope is the cache/config DIRECTORIES only; the dual-prefix reader already handles
    tag history); (4) `make test` green; (5) a test asserts the migration's idle-guard
    refuses while a pool looks active. Run only when no pool is active (the script's own
    precondition enforces this). HARD retained for the live-migration care, but the design
    call is made — dispatchable as an Opus hard-execute unit.
  - **Done 2026-06-17** (Opus hard-execute): `relay/scripts/migrate-state-dirs.sh` ships —
    idle-precondition guard (refuses while RELAY_STATUS.md is fresh within
    `RELAY_ACTIVE_SECS` OR `claim.sh peek` shows a live holder), then `mkdir -p
    ~/.config/relay ~/.cache/relay` → `mv` contents (skip-existing for resumability) →
    replace each old dir with a permanent `old→new` symlink (the back-compat net).
    Idempotent: once old is a symlink, a re-run is a no-op. The env-var defaults in the 11
    accessor scripts + `relay-loop.js`'s `RELAY_STATUS_PATH`/`RELAY_EVENTS_PATH` constants,
    `worktreePathFor`, and its prompt-text `~/.cache/relay/worktrees` /
    `~/.config/relay/relay.toml` references now read the canonical `relay` path; the
    fables-turn symlink covers any straggler. Git tags untouched (constraint a). Test:
    `tests/test_relay_migrate_state_dirs.sh` (roadmap:10c0) — guard-refuses (forced +
    fresh-status), migrate-moves-and-symlinks, idempotent re-run, and a no-legacy-default
    grep over the 11 scripts. `test_relay_status.sh` / `test_relay_discovery_guards.sh`
    path assertions updated to the new name. `make test` green.

## Capability-keyed lane taxonomy — slice A (meeting 2026-07-02-1924)

Slice A of the capability-keyed lane taxonomy + mechanical-run daemon
(`docs/meeting-notes/2026-07-02-1924-relay-mechanical-lane-capability-taxonomy.md`).
**Additive only** — introduces the `[MECHANICAL]` capability tier, its recipe/permit/probe
substrate, and the check-and-defer resource arbitration, WITHOUT renaming any existing lane
(the `[HARD — *]`→new-vocab rename is slice B, GATED below). Single-id-two-views (D2): every
id reuses its open TODO.md twin under the `[UMBRELLA]`.

- [x] A1 — `[MECHANICAL]` capability tag + `mechanical` verdict [ROUTINE] <!-- id:7616 -->
  - **Why** (meeting 2026-07-02-1924 decision 1; TODO id:7616): the taxonomy needs a
    fourth capability tier for pure-compute work no LLM or human runs — local-LLM
    benchmarks, pytorch, pilots — dispatched to a host daemon (A3, gated) while an LLM
    session reviews the artifact. This item adds ONLY the tag + verdict plumbing so the
    tier is recognized additively; it does NOT build the daemon consumer.
  - **Acceptance**:
    1. `relay/scripts/roadmap-lint.sh` ACCEPTS `[MECHANICAL]` as a recognized class tag —
       standalone (`- [ ] title [MECHANICAL] <!-- id -->`) and composed with the orthogonal
       resource modifier (`[MECHANICAL] [INTENSIVE — local-llm]`). A `[MECHANICAL]`+`[INTENSIVE]`
       item is grammar-clean; a `[MECHANICAL]`+`[HARD — pool]` item is a tag/prose lane
       conflict (case c) exactly as two hard lanes would be (MECHANICAL is a capability lane,
       INTENSIVE is not).
    2. `relay/scripts/gather-human-backlog.sh` keeps a `[MECHANICAL]` item OUT of every human
       lane bucket — a repo whose only open item is `[MECHANICAL]` (no `[HARD]`) emits NO
       hard_pool/hard_meeting/hard_hands/manual/review_me line and does NOT trip the untagged
       LOUD-reject (exit 0, empty).
    3. `relay/scripts/classify-verdict.sh` emits a NEW `mechanical` verdict for a
       MECHANICAL-only repo: given gather JSON with `open_mechanical >= 1` and nothing
       higher-priority (no actionable routine / unaudited / hard-pool / promote / surface),
       `verdict == "mechanical"`. It is POOL-INERT — never `execute`/`hard`; the `intensive`
       field stays `""` on it (the id:5ac6 invariant `intensive!="" ⇒ verdict∈{execute,hard}`
       holds unchanged). A higher-priority class (open `[ROUTINE]`, etc.) still outranks it.
    4. Document the `[MECHANICAL]` capability + `mechanical` verdict in
       `relay/references/hard-lanes.md` (as an additive capability tier alongside the resource
       axis, noting the slice-B rename is where it folds into the two-axis vocabulary).
  - **Tests**: `tests/test_mechanical_tag.sh` (`# roadmap:7616`) — hermetic fixtures: (a)
    roadmap-lint accepts `[MECHANICAL]` standalone + `[MECHANICAL] [INTENSIVE — local-llm]`,
    rejects `[MECHANICAL] [HARD — pool]` conflict; (b) gather-human-backlog emits nothing for
    a MECHANICAL-only repo; (c) classify-verdict emits `verdict==mechanical` (intensive="") for
    `open_mechanical>=1` and `execute` still wins when a routine item co-exists; (d) hard-lanes.md
    names `[MECHANICAL]`. RED until landed.
  - **Context**: `roadmap-lint.sh` class_re + case-c lane count; `gather-human-backlog.sh`
    emit_hard_lanes (only touches `[HARD` lines); `classify-verdict.sh` priority cascade + the
    `open_mechanical` field it must read; the minimal `open_mechanical` wiring in gather is
    part of this item. Do NOT build A3's daemon. Cross-ref B1/B2 (rename, gated).

- [x] A2 — recipe manifest schema + drop-dir contract + `recipe-validate.sh` [ROUTINE] <!-- id:64d3 -->
  - **Why** (meeting 2026-07-02-1924 decision 3; TODO id:64d3): the mechanical-run daemon
    (A3, gated) consumes relay-authored recipes from a drop-dir. This item pins the recipe
    JSON schema, the `{pending,running,done}/` lifecycle-dir contract, and a LOUD validator
    so a malformed recipe never reaches the daemon. WHITELISTED — recipes are relay-authored
    only, NEVER auto-scanned from ROADMAP (the registry is the gate, not a tag; devil's-
    advocate Riku's constraint).
  - **Acceptance**:
    1. A reference doc (`relay/references/recipe-manifest.md`) specifies: the drop-dir
       `~/.config/relay/recipes/{pending,running,done}/` lifecycle (relay authors into
       `pending/`; daemon moves `pending → running → done`); and the recipe JSON schema
       `{id, repo, cmd, host, est_wall, resource, acceptance_artifact}` with each field's type
       (`id`/`repo`/`cmd`/`host`/`resource`/`acceptance_artifact` strings, `est_wall` a
       positive integer seconds). States explicitly: whitelisted / relay-authored / never
       auto-scanned from ROADMAP.
    2. `relay/scripts/recipe-validate.sh <recipe.json>` validates one recipe against the
       schema: exit 0 + silent on a well-formed recipe; exit NONZERO with a LOUD `ERROR:`
       stderr line naming the FIRST offending field on ANY missing key, wrong type, or
       empty/ non-positive `est_wall`. No silent coercion.
    3. Config-dir path is env-overridable (`RELAY_RECIPE_DIR`, default
       `~/.config/relay/recipes`) for hermetic testing.
    4. `recipe-validate.sh` registered in the Makefile `relay_FILES`/`relay_EXEC`/`relay_ALLOW`
       (3×) and the doc in `relay_FILES` (id:69ef install-completeness).
  - **Tests**: `tests/test_recipe_manifest.sh` (`# roadmap:64d3`) — hermetic tmpdir: a
    complete valid recipe passes (exit 0); each of the 7 fields removed in turn → nonzero +
    `ERROR:` naming that field; a non-integer / zero / negative `est_wall` → nonzero; the doc
    exists and names the drop-dir + all 7 fields + "whitelisted"/"never auto-scanned"; Makefile
    registers the script 3× and the doc. RED until landed.
  - **Context**: mirror `acquire-resource.sh`/`resource-claims.md` for the script+doc+Makefile
    idiom (`tests/test_resource_claim.sh` steps 6–7). Schema fields come from the meeting note
    decision 3. Do NOT build the daemon (A3) or wire `inject.sh`.

- [x] A4 — `permitted-intensity.json` + `relay-intensity.sh` graded-window CLI [ROUTINE] <!-- id:e407 -->
  - **Why** (meeting 2026-07-02-1924 decision 4; TODO id:e407): the binary `ALLOW_INTENSIVE`
    gate is all-or-nothing. Replace it (conceptually) with a GRADED, time-boxed permit — "tea"
    (15m/light) vs "lunch" (2h/heavy) — so a human can authorize a bounded intensive window
    that auto-expires. The relay-loop.js engine wiring is RISKY (crash-prone template-literal
    lint, the a0b6 hazard class) and is a FOLLOW-UP note below, NOT required for this item's
    green — the executor-buildable slice is the config file + CLI + predicate with a hermetic
    test.
  - **Acceptance**:
    1. `~/.config/relay/permitted-intensity.json = {max_wall_seconds, resource_ceiling,
       expires_at}` is the on-disk permit; path env-overridable via `RELAY_INTENSITY_FILE`.
    2. `relay/scripts/relay-intensity.sh` CLI writes/reads it:
       - `--for 15m --light` (tea) and `--for 2h --heavy` (lunch) write a permit with the
         parsed wall-seconds + tier + an `expires_at` = now + the `--for` duration;
       - `--afk` writes the CONSERVATIVE default (a minimal short window that does NOT permit a
         heavy resource — bare `--afk` is NOT full intensive, preserving the old binary
         semantics);
       - `--clear` removes the permit; `--status` prints the current permit (or "none").
    3. `relay-intensity.sh permits <est_wall> <resource>` is the predicate: exit 0 IFF
       `est_wall <= max_wall_seconds` AND the resource fits the ceiling AND `now < expires_at`;
       exit nonzero otherwise (no permit / expired / over-window / over-ceiling). Absent or
       expired permit → nonzero (conservative — deny by default).
    4. Back-compat: a `--intensive` flag writes a permissive window (superseding binary
       `ALLOW_INTENSIVE`); bare `--afk` stays conservative (§2). Document the supersession.
    5. FOLLOW-UP (NOT required for green, note only): `relay-loop.js` reading the permit in
       place of the binary `ALLOW_INTENSIVE` gate is a separate engine edit (`node --check` +
       `lint-workflow-templates.mjs` + structure tests) — do it early-session if attempted,
       else leave as a tracked follow-up.
  - **Tests**: `tests/test_permitted_intensity.sh` (`# roadmap:e407`) — hermetic
    `RELAY_INTENSITY_FILE` override: no permit → `permits 60 cpu` nonzero; `--for 2h --heavy`
    → `permits 3600 local-llm` exit 0; over-window (`permits 9000 local-llm`) nonzero; a
    `--light`/`--for 15m` window does NOT permit a heavy resource (`permits 60 local-llm`
    nonzero) but permits a light one within window; an expired `expires_at` (write then
    hand-edit / `--for 0`) → nonzero; `--clear` → nonzero; `--status` prints the window; bare
    `--afk` refuses a heavy job. RED until landed.
  - **Context**: the resource→tier mapping (which resource names count "heavy") is the
    executor's judgment — the test pins only the monotonic property (a heavy resource passes
    a `--heavy` window and fails a `--light` one); REVIEW_ME records the mapping call. Parse
    `--for` as `<N>m`/`<N>h`/`<N>s`. Do NOT touch relay-loop.js for green (§5).

- [x] A5 — `resource-probe.sh` check-and-defer arbitration [ROUTINE] <!-- id:68dc -->
  - **Why** (meeting 2026-07-02-1924 decision 4; TODO id:68dc): auto-launch of an intensive
    mechanical run needs a LIVE-availability probe on top of the permit window (A4) — measured
    VRAM/RAM/load AND no competing `resource:<res>` claim. **Check-and-defer, NEVER preempt**
    (Riku: suspending an in-flight embed-rebuild can corrupt the index; active-suspend is a
    gated cross-repo enhancement, routed:f506, out of scope here).
  - **Acceptance**:
    1. `relay/scripts/resource-probe.sh <resource>` probes availability of a named resource:
       `gpu` via nvidia-smi when present, else a GRACEFUL "unavailable" with a stated reason
       (never a crash / non-zero from a missing binary being fatal); `ram` via `/proc/meminfo`;
       `cpu` via loadavg (`/proc/loadavg`); `local-llm` = claim-only (no hardware metric —
       availability is purely "no competing claim").
    2. It ALSO reads `claim.sh peek` (sharing `CLAIM_BASE`) and reports NOT available when a
       LIVE `resource:<res>` claim is held — check-and-defer, never preempt.
    3. Thresholds are env-overridable (e.g. `RESOURCE_PROBE_RAM_MIN_MB`,
       `RESOURCE_PROBE_LOAD_MAX`); the nvidia-smi binary is env-overridable
       (`RESOURCE_PROBE_NVIDIA_SMI`, default `nvidia-smi`) so the probe is testable without a
       real GPU.
    4. Emits ONE JSON object `{resource, available, reason, ...metrics}` on stdout and an exit
       code: 0 when available, nonzero when not.
  - **Tests**: `tests/test_resource_probe.sh` (`# roadmap:68dc`) — hermetic `CLAIM_BASE`
    (mktemp): `cpu` with a generous `RESOURCE_PROBE_LOAD_MAX` and no claim → `available:true`,
    exit 0; then `claim.sh acquire resource:cpu` → probe reports `available:false` + nonzero
    (check-and-defer); `gpu` with `RESOURCE_PROBE_NVIDIA_SMI` pointed at a nonexistent binary →
    graceful `available:false` with a reason, no crash; `ram` output is valid JSON with an
    `available` boolean; a low RAM threshold override flips availability deterministically. RED
    until landed.
  - **Context**: compose `claim.sh peek` (reads `CLAIM_BASE`, safekey `resource_<res>`, JSON
    `.key=="resource:<res>"`) — do NOT add a second lock/registry. Never preempt/kill a holder.
    Register in Makefile 3×. Pairs with A4 (permit window) as the two launch conditions.

## Capability-keyed lane taxonomy — wave 2a (MECHANICAL end-to-end)

Wave 2a makes the `[MECHANICAL]` tag END-TO-END: slice A shipped the CONSUMER half only
(the classifier RECOGNIZES `[MECHANICAL]`→the pool-inert `mechanical` verdict), but no
relay layer PRODUCES the tag and nothing RUNS it. Source of truth: the
`## Amendment 2026-07-02 (post-build — the `[MECHANICAL]` producer gap)` section of
`docs/meeting-notes/2026-07-02-1924-relay-mechanical-lane-capability-taxonomy.md`. These
three items (single-id-two-views D2 — each reuses its open TODO.md twin) are UN-GATED —
their deps (A1 id:7616, A2 id:64d3, A4 id:e407, A5 id:68dc) are all landed `[x]`. Uses the
CURRENT lane vocabulary (`[ROUTINE]`/`[HARD — pool]`) — the two-axis rename is wave 2b
(B1/B2, GATED below), NOT here.

- [x] M1 — handoff.md C2 PRODUCES the MECHANICAL tag + authors the recipe [ROUTINE] <!-- id:9c88 -->
  - **Why** (meeting amendment 2026-07-02, M1; TODO id:9c88): the missing PRODUCER link. A1
    taught the classifier to recognize `[MECHANICAL]`→`mechanical`, but `handoff.md` C2 still
    only ever tags `[ROUTINE]`/`[HARD — *]` — so the tag is routed but never produced and
    nothing feeds the daemon (A3). Teach C2 to recognize compute-only / no-LLM /
    benchmark-or-pilot work (leAIrn2learn, pytorch, model-probe-style batteries) and (i) TAG
    it `[MECHANICAL]` (composing `[INTENSIVE — <res>]` when heavy) and (ii) AUTHOR the A2
    recipe (the `relay/references/recipe-manifest.md` schema, id:64d3 —
    `{id,repo,cmd,host,est_wall,resource,acceptance_artifact}`) into
    `~/.config/relay/recipes/pending/`. This is a CONTRACT-PROSE change to `handoff.md`; no
    script logic changes.
  - **Acceptance**:
    1. `handoff.md`'s C2 checkpoint documents recognizing compute-only / no-LLM /
       benchmark-or-pilot work as `[MECHANICAL]` (alongside the existing `[ROUTINE]` /
       `[HARD — *]` tagging), naming the concept.
    2. C2 documents AUTHORING an A2 recipe into `~/.config/relay/recipes/pending/` for such an
       item, referencing the `recipe-manifest.md` schema (id:64d3) — the producer link to the
       A3 daemon.
  - **Tests**: `tests/test_handoff_produces_mechanical.sh` (`# roadmap:9c88`) — a STRUCTURAL
    grep-style test (like `tests/test_hard_lane_buckets.sh`) asserting `handoff.md` C2 carries
    the `[MECHANICAL]`-tagging instruction AND the recipe-authoring instruction (the pending/
    drop-dir + recipe-manifest reference). RED until the prose lands.
  - **Context**: prose only, in `relay/references/handoff.md` §C2 (roadmap checkpoint, the
    tagging paragraph ~L60–73). Pairs with A3 (the daemon that consumes the authored recipe).
    Do NOT touch any script.

- [x] M2 — re-lane DOCTRINE routes compute-only work to MECHANICAL (fix the wrong-to-hands producer sites) [HARD — pool] <!-- id:2313 -->
  - **Why** (meeting amendment 2026-07-02, M2; TODO id:2313): three CONTRACT doc sites still
    route scriptable / no-human / no-LLM "run X" work to `[HARD — hands]` (the human), even
    though `[MECHANICAL]` now exists and a daemon (A3) can run it. `gather-human-backlog.sh`
    already excludes `[MECHANICAL]` from human buckets in CODE (slice-A A1); M2 is the
    DOC/doctrine layer that TEACHES the strong turn to produce `[MECHANICAL]` instead of
    mis-laning to hands. ORTHOGONAL to B2 (the vocabulary rename) — a routing change that must
    survive B2.
  - **Acceptance** (all three doc sites carry the new routing):
    1. `hard-lanes.md` 5-criterion re-lane policy (~L88–101) gains a "needs an LLM?" branch:
       compute-only + passes a–e ⇒ `[MECHANICAL]` (daemon); LLM + passes a–e ⇒
       `[ROUTINE]`/`[HARD — pool]`; fails a–e (needs a human) ⇒ `[HARD — hands]`.
    2. `handoff.md` author-then-run split (~L93–106) routes the daemon-runnable "run X" residue
       to `[MECHANICAL]`, keeping only genuinely-human runs (device/sudo/physical/credential)
       as `[HARD — hands]`.
    3. `human.md` (the "you run these" checklist, ~L158–168/194/287) EXCLUDES `[MECHANICAL]`
       from the human "you run these" list — it is daemon-run, not human-run.
  - **Tests**: `tests/test_mechanical_relane_doctrine.sh` (`# roadmap:2313`) — a STRUCTURAL
    grep test asserting all THREE doc sites (`hard-lanes.md`, `handoff.md`, `human.md`) name
    `[MECHANICAL]` in their re-lane / author-then-run / you-run-these routing. RED until the
    prose lands.
  - **Context**: prose only, across `relay/references/{hard-lanes.md,handoff.md,human.md}`.
    Do NOT rename any existing lane (that is B2). The CODE-layer exclusion already exists
    (`gather-human-backlog.sh` only inspects `[HARD` lines) — this is the doctrine that keeps
    producers from emitting `[HARD — hands]` for daemon-runnable work in the first place.

- [x] A3 — mechanical-run daemon [HARD — pool] <!-- id:b3d0 -->
  - **Why** (meeting 2026-07-02-1924 decision 3; TODO id:b3d0): the host `--user` `.path`-unit
    that runs pending recipes → artifact → `inject.sh` review, OUTSIDE the Workflow (pure
    mechanical → no permission wall; sidesteps the babysitter/outage problem). Model-probe
    topology (`tools/quota-sample.*` + `tools/relay-watchdog.*` are the existing instances of
    the systemd-`--user` → mechanical-script → git-JSONL/notify pattern). UN-GATED: deps
    64d3 + e407 + 68dc all landed.
  - **Acceptance**:
    1. `relay/scripts/mechanical-daemon.sh` performs ONE processing tick (a subcommand, e.g.
       `run`/`tick`) over the recipe drop-dir: for each recipe in `pending/`, VALIDATE it
       (`recipe-validate.sh`); check the launch gate — `relay-intensity.sh permits <est_wall>
       <resource>` AND `resource-probe.sh <resource>` both succeed; if permitted, move
       `pending → running`, run `cmd` (which writes the `acceptance_artifact`), move
       `running → done`, and drop a review-request via `inject.sh add`. If NOT permitted
       (resource claimed OR est_wall over the window OR resource unavailable) the recipe is
       DEFERRED — left in `pending/`, NOT run, no artifact, no inject (check-and-defer, never
       preempt).
    2. Dirs are env-overridable for hermeticity: `RELAY_RECIPE_DIR` (default
       `~/.config/relay/recipes`, holds `pending/running/done`), `RELAY_INTENSITY_FILE`,
       `CLAIM_BASE`, `INJECT_BASE` — all threaded to the sibling scripts.
    3. A systemd `--user` `.path` unit watches `~/.config/relay/recipes/pending/` and triggers
       a oneshot service that runs the tick (`tools/` topology, alongside quota-sample /
       relay-watchdog units). `make install-mechanical-daemon` installs+enables them.
    4. `mechanical-daemon.sh` registered in the Makefile `relay_FILES`/`relay_EXEC`/`relay_ALLOW`
       (id:69ef install-completeness).
  - **Tests**: `tests/test_mechanical_daemon.sh` (`# roadmap:b3d0`) — REAL hermetic tests
    (mktemp `RELAY_RECIPE_DIR`/`CLAIM_BASE`/`INJECT_BASE`/`RELAY_INTENSITY_FILE`): (1) a valid
    recipe whose gate PERMITS runs — recipe moves `pending→running→done`, its
    `acceptance_artifact` is written, and an inject unit appears; (2) a recipe whose resource
    is CLAIMED is DEFERRED — stays in `pending/`, no artifact, no inject; (3) a recipe whose
    `est_wall` EXCEEDS the permit window is DEFERRED likewise. RED until the daemon lands.
  - **Context**: reads all three slice-A helpers at launch (`recipe-validate.sh`,
    `relay-intensity.sh permits`, `resource-probe.sh`); shares the ONE `claim.sh` registry via
    `CLAIM_BASE` (no second lock). Check-and-defer ONLY — never suspend/kill a claim holder
    (active-suspend is routed:f506, out of scope).

## Capability-keyed lane taxonomy — wave 2b (lane-vocabulary RENAME)

Wave 2b executes the `[HARD — <suffix>]` → two-axis-vocabulary RENAME ratified in the meeting
(`docs/meeting-notes/2026-07-02-1924-relay-mechanical-lane-capability-taxonomy.md`, decisions
1+2). **This is the meeting's flagged BLAST-RADIUS step** — the lane vocabulary was hardened
four days ago across ~30 lane-asserting tests + the crash-prone `relay-loop.js` engine, so the
rename is deliberately staged **additive-then-flip** with a deterministic converter and a
DUAL-VOCABULARY lint window (both old and new accepted ERROR-free for one window). NEVER a
flag-day (Riku). Dep A1 (id:7616, `[MECHANICAL]` tag) is landed `[x]`, so B1 is now UN-GATED
and dispatchable; B2 stays gated on B1 (below). Single-id-two-views (D2): both ids reuse their
open TODO.md twin.

**Target taxonomy (decision 1).** Two orthogonal axes — **capability**: `[ROUTINE]` (executor
LLM) · `[HARD]` (strong LLM) · `[INPUT — {meeting,decision,access}]` (human ± LLM; sub-type =
effort) · `[MECHANICAL]` (compute only) — × **resource** (orthogonal): `[INTENSIVE — <res>]`.
The MAPPING: the THREE UNAMBIGUOUS 1:1 renames the converter AUTO-APPLIES — `[HARD — pool]`→`[HARD]`,
`[HARD — meeting]`→`[INPUT — meeting]`, `[HARD — decision gate]`→`[INPUT — decision]`. `[HARD — hands]`
is DELIBERATELY NOT auto-converted: "hardware/sudo/secret/on-device/rehearsal" fragments across FOUR
destinations — `[MECHANICAL]` (a daemon can run it) · `[INPUT — access]` (human provides a
credential/key/physical access) · `[INPUT — decision]` (human must ratify, e.g. it-infra fd30
post-gate decisions) · `[INPUT — meeting]` (human+LLM design judgment, e.g. a rehearsal whose
outcome needs interpretation) — so the converter FLAGS every `[HARD — hands]` item for per-item
human judgment (those four candidates) and converts it to NONE of them (no default). Aligns with M3
(id:3ef7) + the conformance-sweep detector-surfaces/human-decides rule. `[ROUTINE]` / `[MECHANICAL]`
/ `[INTENSIVE — <res>]` are UNCHANGED. **SCOPE (owner-locked):** this wave
migrates THIS repo's contract + lane-readers + tests + THIS repo's own ROADMAP/TODO item tags
only. Cross-repo item re-tagging in OTHER repos is a SEPARATE gated migration — the dual-vocab
window is exactly what lets those migrate later.

- [x] B1 — target taxonomy → `hard-lanes.md` north star + `lane-convert.sh` converter + dual-vocab lint window [HARD — pool] <!-- id:4f02 -->
  - **Why** (meeting 2026-07-02-1924 decision 2; TODO id:4f02): the SAFETY-NET-FIRST half of
    the rename. Before any reader flips (B2), ship (i) the north-star vocabulary in
    `hard-lanes.md` as a BOTH-VOCAB table, (ii) a `roadmap-lint.sh` that DUAL-ACCEPTS old and
    new vocab (neither an ERROR during the window), and (iii) a DETERMINISTIC converter that
    performs the unambiguous renames and FLAGS (never auto-converts) the one ambiguous case
    (`[HARD — hands]`→`[MECHANICAL]` candidate). This item OPENS the dual-vocab window; the
    eventual old-vocab→ERROR FLIP that CLOSES it is deliberately NOT here (it is the tail of
    B2, after every reader + this repo's ledgers are migrated).
  - **Acceptance**:
    1. **North-star write** — `relay/references/hard-lanes.md` documents the ratified two-axis
       taxonomy as the north star, with a BOTH-VOCAB mapping table (old `[HARD — *]` spelling →
       new capability tag). The three unambiguous rows are 1:1 (`[HARD — pool]`→`[HARD]`,
       `[HARD — meeting]`→`[INPUT — meeting]`, `[HARD — decision gate]`→`[INPUT — decision]`); the
       `[HARD — hands]` row shows its FOUR candidate destinations `{[MECHANICAL] | [INPUT — access]
       | [INPUT — decision] | [INPUT — meeting]}` (per-item human judgment, NOT a single target).
       State explicitly that the dual-vocab window is OPEN (both spellings accepted ERROR-free) and
       that the old→ERROR flip lands at the end of B2. Keep the existing `[MECHANICAL]` +
       `[INTENSIVE]` sections coherent with the new axes.
    2. **`roadmap-lint.sh` DUAL-ACCEPTS** — extend the recognized `class_re` so BOTH the old
       lanes (`[HARD — pool|meeting|hands|decision gate]`) AND the new vocab (bare `[HARD]`,
       `[INPUT — meeting]`, `[INPUT — decision]`, `[INPUT — access]`; `[MECHANICAL]` already
       accepted) are ERROR-free class tags. Neither vocabulary is a violation during the window.
       The lane set is READ from `hard-lanes.md` (single source) — extend the extraction to pick
       up the new `[HARD]`/`[INPUT — …]` forms, do NOT hardcode a second copy. GOTCHA: bare
       `[HARD]` is NOT a substring of `[HARD — pool]` (the em-dash + space intervene), so a
       naive `[HARD]` match will not false-fire on old-vocab items — but the case-c two-lane
       conflict counter must not double-count an item that (correctly) carries exactly one new
       OR one old lane. An item carrying an old lane AND its new rename simultaneously (e.g.
       `[HARD — pool]` + `[HARD]`) SHOULD still be a case-c conflict (never both).
    3. **`relay/scripts/lane-convert.sh <ledger-file>`** — a deterministic TEXT transform (not a
       lane-parser) over a ROADMAP/TODO file. AUTO-APPLY the THREE UNAMBIGUOUS 1:1 renames on the
       exact bracket strings ONLY: `[HARD — pool]`→`[HARD]`, `[HARD — meeting]`→`[INPUT — meeting]`,
       `[HARD — decision gate]`→`[INPUT — decision]`. **`[HARD — hands]` is NEVER auto-converted**
       (it fragments four ways — see the section intro): LEAVE the line UNCHANGED and SURFACE it on
       STDERR as a needs-judgment flag naming its FOUR candidate destinations (`[MECHANICAL]`,
       `[INPUT — access]`, `[INPUT — decision]`, `[INPUT — meeting]`) + the item's file:line + id,
       deferring the decision to M3 (id:3ef7) / human. The converter emits NO default for hands.
       `[ROUTINE]` / `[MECHANICAL]` / `[INTENSIVE — <res>]` and the `🚧 route:*` auto-gate aliases
       pass through UNCHANGED. IDEMPOTENT — re-running on already-converted output is a no-op (a
       still-present `[HARD — hands]` re-flags but is not rewritten, so the text is stable). Default
       is stdout (or `--in-place`); the test fixture is the contract.
    4. **Makefile registration** — `lane-convert.sh` in `relay_FILES`/`relay_EXEC`/`relay_ALLOW`
       (3×, id:69ef install-completeness).
    5. Do NOT flip any reader (that is B2) and do NOT run the converter on this repo's ledgers
       yet (also B2). B1 is the additive safety net ONLY.
  - **Tests**: `tests/test_lane_convert.sh` (`# roadmap:4f02`) — hermetic tmp fixtures:
    (a) `roadmap-lint.sh` exits 0 on a ROADMAP whose items use the NEW vocab (bare `[HARD]`,
    `[INPUT — meeting|decision|access]`) AND on one using the OLD vocab (dual-accept); an item
    with two lanes (old + its new rename on one line) still exits nonzero (case-c conflict);
    (b) `lane-convert.sh` on a fixture AUTO-APPLIES the three unambiguous renames exactly
    (`[HARD — pool]`→`[HARD]`, `[HARD — meeting]`→`[INPUT — meeting]`,
    `[HARD — decision gate]`→`[INPUT — decision]`); (c) EVERY `[HARD — hands]` item (plain AND
    `[INTENSIVE]`-composed) is LEFT UNCHANGED in stdout and SURFACED on STDERR naming all four
    candidate destinations — never auto-`[INPUT — kind]` and never auto-`[MECHANICAL]`; (d)
    `[ROUTINE]` / `[MECHANICAL]` / `[INTENSIVE — res]` lines are untouched, and a second pass is a
    no-op (idempotent). RED until B1 lands.
  - **Context**: `roadmap-lint.sh` class_re + hard-lanes-extraction (L54–86) + case-c counter
    (L165–176); the new-vocab north-star lives in `hard-lanes.md`. The converter is a NEW
    sibling script — mirror the `host-gate.sh`/`recipe-validate.sh` script+Makefile idiom. The
    `[HARD — hands]` fan-out is inherently a per-item JUDGMENT (four destinations) — the converter
    only SURFACES it (detector-surfaces/human-decides, M3 id:3ef7); the fixtures pin the
    never-auto-default + four-candidate-flag invariant.

### GATED — B2 migration (DEP: 4f02, NOT dispatchable until B1 lands)

Parked under a GATED heading (roadmap-lint-exempt, non-dispatchable) until B1 (id:4f02) ships
the converter + dual-vocab window. This is a LARGE migration — its acceptance DECOMPOSES into
three separable sub-checks (B2a readers+references / B2b relay-loop.js / B2c this-repo
ledgers+tests) that MAY be dispatched as separate executors (see the handoff report's split
recommendation). Do NOT dispatch until 4f02 is ticked.

- [x] B2 — lane-READERS + references + engine (relay-loop.js) dual-accept the new vocabulary [HARD] <!-- id:8111 -->
  - **RE-SCOPED + verified 2026-07-02 (relay review, wave-2b).** The shipped B2a (parsers+refs)
    + B2b (relay-loop.js engine) dual-accept slice is genuinely DONE and verified both directions
    (old-vocab still buckets/dispatches everywhere; new vocab buckets/classifies correctly; no
    test gamed; suite green). The remaining B2c work — CONVERT this repo's own ledgers, MIGRATE
    the ~30 lane-asserting tests, and CLOSE the dual-vocab window (old-vocab → lint ERROR) — was
    split out to id:7df1 (GATED), because the window cannot close while M3 (id:3ef7) and the
    cross-repo `[HARD — hands]`/scan.py (id:b466) surfaces are still on old vocab. This item is
    the reader+reference+engine dual-accept migration ONLY.
  - **Why** (meeting 2026-07-02-1924 decision 2; TODO id:8111): with B1's converter + dual-vocab
    window in place, flip every lane-READER and reference to EMIT/EXPECT the new vocabulary
    (still ACCEPTING old via B1's window). `[HARD — hands]` items are only FLAGGED, never
    auto-converted (the FOUR-candidate fan-out is per-item judgment, deferred to M3/7df1).
  - **Acceptance (shipped — B2a + B2b):**
    - **B2a — readers + references.** Flip the tag-PARSERS and prose to the new vocab (dual-accept):
      1. `gather-human-backlog.sh::emit_hard_lanes` buckets new vocab: bare `[HARD]`→`hard_pool`,
         `[INPUT — meeting]`/`[INPUT — decision]`→`hard_meeting`, `[INPUT — access]`→`hard_hands`;
         old spellings still accepted during the window. (Today an `[INPUT — …]` line is silently
         skipped — it does not even match `/\[HARD/`.)
      2. `classify-repo.sh` `LANE_TAGS`/`HUMAN_GATES` + primary-lane parse + `gather-repo-state.sh`
         `open_hard_pool` anchor recognize the new vocab (bare `[HARD]` counts as pool; `[INPUT — …]`
         are human-gates, excluded from actionable/pool counts).
      3. References `human.md`, `review.md`, `conventions.md`, `handoff.md` re-worded to the new
         vocabulary (old spellings noted as recognized aliases during the window).
    - **B2b — `relay-loop.js` (the crash-prone engine).** Update the verdict-schema enum comments
      and any HARD-string regexes (`unitIsSubstantive` reason regex `/\[HARD —|no open \[HARD — pool\]/`,
      the row-detail strings) to also match the new vocab. The numeric `open_hard_pool` demote-guard
      is tag-agnostic (unaffected). **ENGINE-EDIT CAUTION:** `node --check` + `lint-workflow-templates.mjs`
      + `test_relay_loop_structure.sh` must pass (the a0b6 template-literal-lint hazard crashed the
      pool 3×) — do this early-session, NOT tail-of-session.
    - **B2c — this-repo ledgers + tests + window close.** ➡️ SPLIT OUT to id:7df1 (GATED) — NOT
      part of this item's done-state. See the finalizer item below.
  - **Done-check (met 2026-07-02)**: `node --check relay/scripts/relay-loop.js` +
    `lint-workflow-templates.mjs` clean; `test_relay_loop_structure.sh` green;
    `tests/test_lane_vocab_migration.sh` green; full suite `tests/run-tests.sh` 0 failed;
    dual-accept proven both directions for `gather-human-backlog.sh` / `classify-repo.sh` /
    `gather-repo-state.sh` / `relay-loop.js`.
  - **Tests**: `tests/test_lane_vocab_migration.sh` (`# roadmap:8111`) — the verifiable slice:
    `gather-human-backlog.sh` buckets a repo whose ROADMAP uses the NEW vocab (bare `[HARD]`→a
    `hard_pool` line; `[INPUT — meeting]`→a `hard_meeting` line; `[INPUT — access]`→a `hard_hands`
    line). GREEN as of B2a. The relay-loop.js regex + classify-repo parse flips are verified by
    review spot-checks + the ~30 old-vocab tests still passing (dual-accept).

- [ ] B2c-finalizer — CLOSE the dual-vocab window: convert this-repo ledgers + migrate ~30 lane tests + flip old-vocab→lint ERROR [INPUT — decision] 🚧 GATED (DEP: 3ef7 + cross-repo re-tag) <!-- id:7df1 -->
  - **Why**: B2 (id:8111) landed reader+reference+engine DUAL-ACCEPT — old and new vocab both
    ERROR-free. The window must stay OPEN until every OTHER surface is on the new vocab, then close
    in one deliberate flip. This is the tail the meeting deliberately deferred.
  - **Acceptance**:
    1. `lane-convert.sh --in-place` on THIS repo's `ROADMAP.md` + `TODO.md` (own tags only; the
       converter auto-renames pool/meeting/decision-gate and FLAGS each `[HARD — hands]` — resolve
       those per-item into one of the four candidates by M3/human judgment, never a blanket default).
    2. Migrate the ~30 lane-asserting `tests/test_*.sh` + `test_hard_lane_buckets.sh` marker-set
       cross-check to the new vocab.
    3. FINAL step — CLOSE the window: `roadmap-lint.sh` + `gather-human-backlog.sh` make an OLD-vocab
       lane a hard ERROR (drop the dual-accept branches; delete the "window OPEN" prose in
       hard-lanes.md/human.md/review.md/handoff.md/conventions.md).
  - **Done-check**: `make test` fully green with every lane-asserting test on the new vocab AND an
    old-vocab `[HARD — pool]` fixture now LINT-REJECTED (a new red-then-green window-closed test).
  - **Blocked on**: 3ef7 (M3 per-item `[HARD — hands]` re-lane must resolve this repo's hands items
    first) AND the cross-repo re-tag (other own repos + `project_manager`'s `scan.py`, id:b466, must
    speak new vocab — the window can't close while any consumer is old-vocab-only). Closing early
    would break every repo still on `[HARD — *]`.

## [MECHANICAL] lane-anchor hotfix (relay handoff 2026-07-03)

- [x] classify-repo.sh open_mechanical must be LANE-ANCHORED, not a bare substring [ROUTINE] <!-- id:0d58 -->
  - **Why** (TODO id:0d58): `classify-repo.sh` has two disagreeing tag readers on an open
    `- [ ]` ROADMAP line. The primary-lane derivation (~line 102, id:4da4) is positionally
    ANCHORED — the FIRST recognized `LANE_TAGS` token wins; backtick/prose mentions further
    right are ignored. But the `open_mechanical` counter (~line 93, `if "[MECHANICAL]" in ln`)
    is a BARE SUBSTRING test outside that anchoring — `[MECHANICAL]` is not in `LANE_TAGS`. So an
    open item whose REAL lane is `[HARD — pool]`/`[ROUTINE]` but that merely mentions a
    backtick'd `` `[MECHANICAL]` `` on the same line falsely increments `open_mechanical`, which
    drives the priority-6 `mechanical` verdict (classify-verdict.sh:146, `open_mechanical >= 1`)
    and can mis-fire it on a repo that has no genuine mechanical work.
  - **How**: make the `open_mechanical` count LANE-ANCHORED the same way the primary-lane parse
    is — only a line whose PRIMARY lane is `[MECHANICAL]` counts (e.g. add `[MECHANICAL]` to
    `LANE_TAGS` and gate the increment on `primary == "[MECHANICAL]"`). Do NOT touch
    classify-verdict.sh's priority cascade; the false positive is purely the count.
  - **Acceptance**: `tests/test_mechanical_lane_anchor.sh` (`# roadmap:0d58`, RED until fixed)
    goes GREEN: (1) a `[ROUTINE] @manual` / `[HARD — pool]` open item mentioning a backtick'd
    `` `[MECHANICAL]` `` does NOT count in `open_mechanical` (via `--emit unit`) and does NOT
    yield the `mechanical` verdict; (2) a GENUINE `[MECHANICAL]`-primary item STILL counts and
    STILL classifies `mechanical` (no over-correction to zero). `make test` fully green.

## [MECHANICAL] recipe explicit-success-marker doctrine (relay handoff 2026-07-03)

- [x] `[MECHANICAL]` recipes must write an EXPLICIT success/failure marker into the acceptance_artifact [ROUTINE] <!-- id:fd37 -->
  - **Why** (TODO id:fd37, pilot finding — mechanical-daemon's first real firing on zkWhale
    id:0a7b, 2026-07-03): a recipe whose `cmd` is e.g. `pnpm -s typecheck` writes an EMPTY
    `acceptance_artifact` on success (tsc is silent-on-clean). An empty artifact is an
    ambiguous acceptance signal — indistinguishable from "never ran / redirect failed". The
    daemon's own success/fail branch is ALREADY correct (exit-code driven: it writes a
    `.error` sibling only when the cmd exits non-zero), so this is purely about the ARTIFACT
    a reviewer inspects.
  - **How**: `[MECHANICAL]` recipe `cmd`s must append an explicit terminal success/failure
    marker to the acceptance_artifact AND preserve the real exit code so the daemon's branch
    still fires. Canonical safe pattern (document verbatim as the reference):
    `cd <repo> && { <realcmd> > "$ART" 2>&1; rc=$?; echo "MARKER exit=$rc finished=$(date -Is)" >> "$ART"; exit $rc; }`.
    Two enforcement surfaces: (1) DOC — `references/recipe-manifest.md` documents the
    explicit-marker + exit-preservation requirement in its schema/acceptance section, and the
    M1 producer site (`handoff.md` C2 / `executor-contract.md`) instructs the recipe author to
    include the marker. (2) OPTIONAL CODE — `recipe-validate.sh` emits a NON-FATAL advisory
    (stderr WARNING, still exit 0) when a `cmd` redirects into the acceptance_artifact but
    carries no explicit marker / exit-preservation. Keep validate's existing 7-field schema
    hard-fail UNCHANGED — the marker check is advisory only (validate can't fully parse
    arbitrary shell, so keep it a heuristic that won't over-flag a correct recipe).
  - **Acceptance**: `tests/test_recipe_success_marker.sh` (`# roadmap:fd37`, RED until fixed)
    goes GREEN: (a) `recipe-manifest.md` documents the explicit-marker + exit-preservation
    doctrine; (b) `recipe-validate.sh` WARNs on stderr (exit still 0) for a redirect-without-
    marker cmd; (c) NO warning for a cmd carrying the canonical `exit=$rc` marker (no false
    positive). `make test` fully green.

## Relay orphan-worktree reconcile (meeting 2026-06-16-0938, id:a4e9)

Decomposition of the orphan-reconcile design. **Sequence: D1 → D2/D3** (D2's reconcile
mode and D3's binding both operate on the `relay/orphan/*` namespace D1 creates). D4
(id:a692, note-only forward-flag) and D6 (id:122f, fsck ADVISORY follow-on, gated "ships
after D1–D3") stay in TODO.md — not executor work yet.

- [x] [ROUTINE] D1 — park unmerged orphans on discovery (done 2026-06-16) <!-- id:689c -->
  - **Source**: `docs/meeting-notes/2026-06-16-0938-relay-orphan-reconcile.md` D1; TODO id:689c.
  - **Context**: today the commits-ahead branch of discovery (`relay/scripts/relay-loop.js`
    ~:569, the id:3ac8 path tested by `test_relay_stale_worktree_reap.sh`) only SURFACES a
    commit-bearing stale worktree as "needs manual integration" and leaves the directory in
    place, so the `ls worktrees/` scan re-surfaces it every round forever.
  - **Spec**: change that path to PARK the orphan instead of re-surfacing: `git worktree remove
    --force <dir>` (stops the re-surface) then `git branch -m relay/<runId>-<v>
    relay/orphan/<runId>-<v>` (the stranded commit stays reachable on the canonical
    `relay/orphan/*` ref — NOT deleted, NOT auto-integrated). Emit ONE summary line, not a
    per-round handback. No `--no-ff` merge in this path (parking is not integration).
  - **Acceptance**: `tests/test_relay_orphan_park.sh` (roadmap:689c, RED until implemented) —
    asserts the discovery prompt carries the `id:689c` marker, parks into `relay/orphan/*` via
    `git branch -m`, removes the worktree dir, and describes parking (not the old surface-only
    handback). Behaviourally: a seeded stale worktree + 1 commit → dir gone, `relay/orphan/<…>`
    ref present carrying the commit, one summary line, idempotent across two discoveries.
  - **Done-check**: tick this box, then `tests/run-tests.sh tests/test_relay_orphan_park.sh`,
    then full `make test` green.

- [x] [ROUTINE] D2 — scripted `/relay reconcile` mode (human-invoked) (done 2026-06-16) <!-- id:3313 -->
  - **Source**: meeting 2026-06-16-0938 D2; TODO id:3313. **Sequence: after D1 (id:689c).**
  - **Spec**: a human-invoked reconcile path (script `relay/scripts/relay-reconcile.sh` or a
    documented mode in the relay skill) that enumerates `relay/orphan/*` across managed repos and,
    per branch, offers {integrate | discard | leave}. Integrate MUST reuse the existing
    verify-clean-main → `git merge --no-ff` → `ckpt-tag.sh` → `git-lock-push.sh --ff-only` path
    (no CAS plumbing — `--no-ff` preserves 3-way conflict surfacing; reusing ckpt-tag + --ff-only
    stops a human skipping the checkpoint tag or racing the live pool's push). Discard is
    `git branch -D`. NEVER auto-triggered by the pool.
  - **Acceptance**: `tests/test_relay_reconcile_mode.sh` (roadmap:3313, RED until implemented) —
    the reconcile entrypoint carries `id:3313`, enumerates `relay/orphan/*`, integrates via
    `merge --no-ff` + `ckpt-tag` + `--ff-only`, and offers a discard path. Behaviourally:
    integrate → `relay-ckpt-*` tag + pushed `--no-ff` merge; discard → ref gone; conflicting
    orphan → left + surfaced, never half-merged.
  - **Done-check**: tick this box, then `tests/run-tests.sh tests/test_relay_reconcile_mode.sh`,
    then full `make test` green.

- [x] [ROUTINE] D3 — suppress-redispatch of items with parked partial work (done 2026-06-16) <!-- id:1f53 -->
  - **Source**: meeting 2026-06-16-0938 D3; TODO id:1f53. **Sequence: after D1 (id:689c).**
  - **Spec**: at discovery, bind each `relay/orphan/*` branch back to its ROADMAP item via
    `git show --stat` on the parked commit; if that item is still OPEN, suppress a fresh dispatch
    (don't repeat the expensive session in vain) and surface ONE line carrying a best-effort
    `relay-burn.sh --run <runId>` cost hint. A CLOSED-item orphan does NOT suppress. Ambiguous
    binding → default to suppress. No new manifest — the `relay/orphan/*` refs ARE the registry.
  - **Acceptance**: `tests/test_relay_orphan_suppress_redispatch.sh` (roadmap:1f53, RED until
    implemented) — discovery carries `id:1f53`, binds via `git show --stat`, suppresses
    re-dispatch of still-open items, and surfaces a `relay-burn` cost hint. Behaviourally:
    open-item orphan NOT dispatched + IS surfaced; closed-item orphan does not suppress.
  - **Done-check**: tick this box, then
    `tests/run-tests.sh tests/test_relay_orphan_suppress_redispatch.sh`, then full `make test` green.

## Model probe (id:dba3 deliverable)

Sub-items of the `[HARD — strong model]` umbrella id:dba3. Design fully settled in
`docs/meeting-notes/2026-06-17-0836-opus-degradation-investigation.md` (D2/D5/D6) and
`docs/meeting-notes/2026-06-17-0905-model-probe-tos-and-band.md` (D1/D2). Promoted to
ROADMAP 2026-06-17 so executors can work them; id:dba3 and id:23e9 (seed) stay `[HARD]`.

- [x] Build `tools/model-probe.sh` + `tools/model-probe.battery.jsonl` + log schema [ROUTINE] (done 2026-06-17) <!-- id:c345 -->
  - **Acceptance**: `tools/model-probe.sh grade`, `battery-version`, and the JSONL log all
    work offline (no model call). `model-probe.sh grade <regex> <output>` exits 0 on match,
    1 on mismatch. `model-probe.sh battery-version` prints the battery's `version` field.
    In mock mode (`PROBE_MOCK_RESPONSE` set), a run over a tiny battery writes a complete,
    valid-JSON log line with all D2+D1 fields. Real mode (`claude -p` as probe OS user with
    empty `~/.claude`) is wired but gated on the probe OS user (id:d0c0) — seeding is id:23e9.
  - **Tests**: `tests/test_model_probe.sh` (`# roadmap:040a` — 040a tests the 040a contract,
    which covers c345's offline surface) (currently RED until 040a is ticked).
  - **Done-check**: `tests/run-tests.sh tests/test_model_probe.sh` then full `make test` after
    ticking both id:c345 and id:040a.
  - **Context**: D2 log schema fields: `{ts, battery_version, model, item_id, pass, latency_s,
    out_tokens, tok_per_s, model_id_str, fingerprint, cli_version, quota_tier, os_user,
    config_hash}`. Invocation: shape A = `claude -p` as dedicated probe OS user (id:d0c0);
    shape B = `claude --bare -p` + `ANTHROPIC_API_KEY` (latent fallback). Scope guards: no
    LLM-judge, no dashboard, no scheduler; no seeding (id:23e9); no `useradd` (id:d0c0).

- [x] Write `tests/test_model_probe.sh` — hermetic offline contract tests [ROUTINE] (done 2026-06-17) <!-- id:040a -->
  - **Acceptance**: hermetic, `mktemp -d`, no network, no `~/.claude` touch. Covers:
    (1) `grade` subcommand pass/fail; (2) log format — all D2+D1 fields present in mock-mode
    run; (3) battery-version propagated from fixture battery into log line; (4) empty-config
    assertion — `PROBE_HOME` pointing to a dir with a `CLAUDE.md` causes non-zero exit.
  - **Tests**: `tests/test_model_probe.sh` (`# roadmap:040a`) (currently RED).
  - **Done-check**: `tests/run-tests.sh tests/test_model_probe.sh` then full `make test` after
    ticking both id:040a and id:c345.
  - **Context**: resolves id:6ffe (the placeholder for adding `# roadmap:` linkage once the
    ROADMAP item is open). Both c345 and 040a must be ticked together — the test covers both.

<!-- Direction: autonomous relay orchestration vision -->
