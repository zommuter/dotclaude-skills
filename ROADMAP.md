# Roadmap <!-- fables-turn roadmap v1 -->

Executor-facing task spec. Each item is sized for ONE Sonnet session. Items are
the single source of truth — TODO.md carries only a summary line. Executors tick
checkboxes; only the reviewer adds, removes, or re-scopes items.

Read `CLAUDE.md` (§Testing, §Gotchas, §Relay contract) before starting any item.
Done-check for every item: tick the item's checkbox below, then `make test` must
be fully green (see CLAUDE.md §Testing for the expected-red semantics).

## Items

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
- [ ] [HARD — hands] Heartbeat liveness on the relay claim/lease — FOUNDATION for id:7809 + id:98f0; build FIRST. Extend the existing id:0902 claim/lease to write `runId` + `heartbeat_ts` + a TTL, with a single staleness-check helper (`heartbeat older than TTL ⇒ prior run died`) consumed by BOTH the auto-reconcile (id:7809) and the watchdog (id:98f0) — one source of truth, no separate `.relayactive` file. Acceptance: a test asserts a stale heartbeat reads "dead", a fresh one "alive". Files: `relay/scripts/claim.sh` (+ `heartbeat.sh` or equivalent) + a test. Design: **TODO id:e149** + `docs/meeting-notes/2026-06-22-1546-relay-outage-resilience.md`. <!-- id:e149 -->
- [ ] [HARD — hands] Auto-reconcile-on-restart for the relay loop — DESIGN RESOLVED 2026-06-22 (`docs/meeting-notes/2026-06-22-1546-relay-outage-resilience.md`): `/relay reconcile --auto` (one code path with the human reconcile) loop-invoked at startup on a STALE heartbeat (id:e149 foundation, extends id:0902 — no new `.relayactive` file); SAFE auto-integrate = clean tree + mechanical `gaming-scan.sh` + full-suite-green + ledger-only/trivial diff; everything else (BLOCKED/partial/red/conflicting/needs-strong-judgment) → parked + surfaced via REVIEW_ME / `/relay human`; conservative classifier defaults to JUDGMENT, never a weaker bar than a human `/relay review`. Design + rationale: **TODO id:7809** (single-id-two-views). Build AFTER id:e149. <!-- id:7809 -->
- [ ] [HARD — hands] Outage-resilient LOCAL relay loop — DESIGN RESOLVED 2026-06-22 (`docs/meeting-notes/2026-06-22-1546-relay-outage-resilience.md`): observe-first. Build a watchdog systemd `--user` timer (modelled on `quota-sample.timer`) that detects a dead loop via the SHARED heartbeat (id:e149) and NOTIFIES for one-tap restart (PushNotification→`notify-send` fallback) — NOT a headless `claude -p`, so it sidesteps the permission wall entirely; its outage-death log is the EVIDENCE GATE to re-open the deferred heavy build (curated allowlist / dedicated-OS-user scoped allowlist = id:2d01). Deferred-out-of-scope until evidence warrants: any `--dangerously-skip-permissions` use, the allowlist treadmill, the OS-user repo-access bridge. Cheap fixes split out: nudge id:bde8, upstream report id:0994. Design + rationale: **TODO id:98f0**. Build AFTER id:e149. <!-- id:98f0 -->
- [x] [ROUTINE] Fix the misleading `loop-hint.sh`/step-0a "unattended resilience" nudge — correct it to state `/loop`/cron dies WITH the session (resilient only to relay's own early-exit — quota/seatbelt — within a live session, NOT to a session/process kill). Pairs with id:888a/id:8602. Files: `relay/scripts/loop-hint.sh` + SKILL.md step 0a. Design: **TODO id:bde8** + `docs/meeting-notes/2026-06-22-1546-relay-outage-resilience.md`. <!-- id:bde8 -->
- [ ] [HARD — hands] File `CronCreate durable:true` no-op upstream — report that `{durable:true, recurring:true}` returns `[session-only]` locally (durable flag appears to be a no-op for local in-session crons). Human action (file the report). Design: **TODO id:0994** + `docs/meeting-notes/2026-06-22-1546-relay-outage-resilience.md`. <!-- id:0994 -->

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
  - **Also:** the relay SKILL.md reconcile section should document that `reconcile --all` is the cross-repo list (one canonical command), so no future turn hand-rolls a sweep. Note the relay.toml path discrepancy to verify while here: `gather-human-backlog.sh` defaults `RELAY_TOML` to `~/.config/relay/relay.toml` but the live file is `~/.config/fables-turn/relay.toml` — resolve to whatever the rest of the relay scripts actually use (don't break the existing default; just make `--all` read the same file the pool reads).
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
    resource semaphore `~/.cache/fables-turn/resources/<resource>.lock` — at most one local-llm task
    at a time; conservative default = it RUNS ALONE (pool pauses new dispatch / forces POOL_WIDTH=1
    while held) — this is the actual OOM fix. (3) Opt-in to run them: `/relay --allow-intensive`
    (flag) and an **AFK mode** `/relay --afk [duration]` ("I'm away, do something useful" — drains
    light work, then chews intensive items one-at-a-time within a time/quota budget, reports back).
    (4) Tagging: strong children tag per criteria in `conventions.md` (cite OOM + TTFT), PLUS a coarse
    per-repo default `[repos.ai-codebench] intensive = true` / `[repos.zkm] intensive = true` as a
    safety net; item-level tags override.
  - **RATIFIED 2026-06-15** (meeting 2026-06-15-1216): `[INTENSIVE — <resource>]` is a **claim on a
    resource key** (`~/.config/fables-turn/claims/resource:local-llm.json`), exclusive; while held
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
    inbox `~/.config/fables-turn/inject.d/`, consumed → `inject.done/`). relay-loop.js discovery
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
    polls at each round's discovery — per-shard files `~/.config/fables-turn/inject.d/<token>.json`,
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

- [ ] Strong-model audit: code review, security, and design coherence [HARD — pool] <!-- id:401c -->
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
  - **Acceptance**: relay-loop.js writes/rewrites `~/.config/fables-turn/RELAY_STATUS.md` (or a path
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
