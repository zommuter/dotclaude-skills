# Relay log <!-- merge=union; append-only — never edit or reorder past entries -->

## 2026-06-12 13:28 — reviewer (claude-fable-5)

Handoff pilot C1-C5: fresh CLAUDE.md (relay contract v1) + ARCHITECTURE.md; ROADMAP.md with 5 ROUTINE (3b02, 44ba, 1ec1, 32d6, 2520) + 2 HARD (de9c done, 3346 gated); zero-dep test harness with 5 verified-red specs; 3 @manual BDD features; HARD de9c executed: append.sh scan-ids + ROADMAP token ledger, orphan-scan union-read, classify RELAY class. 8 REVIEW_ME entries.

## 2026-06-12 16:18 — reviewer (Fable 5)

review 2026-06-12: id:7691 verified genuinely green (no gaming flags); test-integrity audit clean over 10 commits; suite 3 pass / 5 expected-red; ARCHITECTURE §10 + CLAUDE.md Layout/Testing synced; relay mirror count 6→7

## 2026-06-12 — executor (Sonnet)

Worked id:44ba — added `> **Fable note:**` blockquote after the γ-branch reference table in `meeting/broker-mode.md` naming the inline-prose replacement for `AskUserQuestion` on Fable-class harnesses with a pointer to `format.md §Interactive mode §Harness-class gate`. Test `test_fable_caveat.sh` green; full suite 4 pass / 0 fail / 4 expected-red.
Friction: none.

## 2026-06-12 — executor (Sonnet)

Worked id:2520 — added `humanize_tokens` helper to `statusline/statusline-command.sh` and changed `CONTEXT_DISPLAY` from bare `<pct>%` to `<pct>%(<tokens>)` where tokens are humanized: <1k plain, 1k–10k one decimal (e.g. `9.5k`), ≥10k integer (e.g. `115k`). Test `test_statusline_tokens.sh` green; full suite 5 pass / 0 fail / 3 expected-red.
Friction: none.

## 2026-06-12 — executor (Sonnet)

Worked id:32d6 — created `tools/ctx-budget.sh`: scans `*/SKILL.md` files, emits TSV `<relpath>\t<est_tokens>\t<gate>\t<OK|WARN>` (est=bytes/4, default gate 2000, CTX_BUDGET_GATE override), `--summary` mode shows only WARN lines plus total count, always exits 0. Test `test_ctx_budget.sh` green; full suite 6 pass / 0 fail / 2 expected-red.
Friction: none.

## 2026-06-12 — executor (Sonnet)

Worked id:1ec1 — added `fables-turn` and `projects` to the Makefile SKILLS list; defined per-skill `_FILES/_EXEC/_ALLOW/_LOCAL` variables; extended `SKILL_RULES install-*` to `mkdir -p` each file's dirname so nested `references/` and `scripts/` subdirs are created; added `trap '' PIPE || true` to `status-*` recipe to survive `grep -q` early pipe exit. `fables-turn_ALLOW` covers both scripts. Test `test_makefile_skills.sh` green; full suite 7 pass / 0 fail / 1 expected-red.
Friction: none.

## 2026-06-12 — executor (Sonnet)

Worked id:3b02 — added `say` subcommand to `meeting/broker-curl.sh`: reads stdin line-by-line with `while IFS= read -r line || [[ -n "$line" ]]` (handles no-trailing-newline), skips empty lines, builds JSON per line with `jq -n --arg` (apostrophes/quotes/backslashes safe), first line gets `"kind":"opener"` when `--opener` passed as $4, curl redirects stdout to /dev/null with `--fail` so errors reach stderr. Updated `meeting/broker-mode.md` §Discussion example to use one `say` call per agenda item via `printf '%s\n' ... | broker-curl.sh say --opener`. Fixed a quoting bug in `tests/test_broker_say.sh`: the test used `'\''` inside a `$'...'` ANSI-C string which ended the ANSI-C context early, turning all subsequent `\n` into literal two-char sequences (only 1 real newline in the 4-line input). Changed to `\'` (valid inside `$'...'`); no assertions altered. Full suite 8 pass / 0 fail.
Friction: none.

## 2026-06-12 — executor (Sonnet) — no-op session

No ROUTINE items remain open in ROADMAP.md. All six ROUTINE items are ticked.
Remaining open items (id:401c, id:3346) are both [HARD — strong model].
No work performed; no tests run.

## 2026-06-12 18:11 — reviewer (Fable 5)

review 2026-06-12 (window fable-ckpt-20260612-1618..HEAD): all five executor items (id:44ba, 2520, 32d6, 1ec1, 3b02) verified genuinely green — no deleted/weakened/skipped tests, no hardcoded actuals, no fixture special-casing. The id:3b02 test edit was resurrection-checked byte-by-byte: the ORIGINAL fixture's `'\''` inside `$'…'` made the test unsatisfiable (1 real newline instead of 3, double backslash vs single-backslash assertion); the executor's `\'` fix changed only the input line, assertions intact — equivalent-or-stricter, no gaming. Suite 8 pass / 0 fail / 0 expected-red. Spec-drift: ARCHITECTURE §3/§5/§9 + CLAUDE.md install list synced; relay-contract pointer v1 == skill v1, no refresh. HARD id:401c executed (first strong-model audit, window since fable-ckpt-20260612-1328): 16 findings — fixed inline: git-lock-push.sh slash-branch upstream parse bug (silent pull skip; defect test added) and broker-curl.sh non-numeric-port URL-host-injection guard; tracked: id:697e (contract self-report format vs de-facto heading style); rest accepted with rationale in `docs/meeting-notes/2026-06-12-1811-strong-model-audit.md`. TODO relay mirror resynced 3→1 (two executors had double-claimed the same 4→3 decrement). id:6a3c assessed for ROADMAP promotion — stays parked in TODO.md (cross-repo scope, single-repo ROADMAP contract). No items reopened; no promotions/demotions (all friction lines "none"). Suite fully green at final commit.

## 2026-06-12 18:27 — reviewer (Fable)

review turn: verified 5 ROUTINE items (44ba/2520/32d6/1ec1/3b02) genuine-green, no gaming flags; strong-model audit id:401c done (16 findings: 4 fixed incl. git-lock-push slash-branch pull bug + broker-curl port-injection guard, 1 tracked id:697e, rest accepted); ARCHITECTURE/CLAUDE.md drift synced; only gated id:3346 remains open

## 2026-06-12 — executor (Sonnet)

[2026-06-12 executor sonnet] No ROUTINE items available — all prior items ticked. Only open item is id:3346 [HARD — strong model], which is out of scope for executor tier. No work done this session; queue is empty for executor. Reviewer should add new ROUTINE items or tackle id:3346 in a strong-model session.
Friction: none (no items to work).

## 2026-06-12 — executor (Sonnet)

[2026-06-12 executor sonnet] Worked id:9934 — implemented `fables-turn/scripts/quota-stop.sh` and `tests/test_quota_stop.sh`. Script reads `/tmp/claude-usage-cache.json`, checks tier-specific buckets against `RELAY_QUOTA_THRESHOLD` (default 0.90), exits 0/1/2 for below/above/uncertain. Seatbelt triggers on agents≥200 or wall≥7200s regardless of cache. 17 tests cover all specified cases; full suite green (10 files, 0 failures).
Friction: id:aeaf and id:80e2 both require relay-loop.js which is a HARD (id:83c9) item not yet built — only id:9934 was actionable this session.

## 2026-06-12 — executor (Sonnet)

[2026-06-12 executor sonnet] Worked id:aeaf — created `fables-turn/scripts/relay-loop.js` stub with STRONG_TIER knob wired in; updated `fables-turn/SKILL.md` with Configuration knobs table documenting STRONG_TIER=fable|opus, usage examples, and model-ID mapping; created `tests/test_strong_tier_knob.sh` (9 grep-based static checks). Full suite green (11 files, 0 failures). ROADMAP checkbox ticked.
Friction: relay-loop.js is a stub — the full pool implementation is HARD item id:83c9; this ROUTINE item adds only the STRONG_TIER wiring that id:83c9 and id:80e2 depend on.

## 2026-06-12 — executor (Sonnet)

[2026-06-12 executor sonnet] Worked id:80e2 — added `buildRelayStatus(state)` and `writeRelayStatus(state, path)` to `fables-turn/scripts/relay-loop.js`. All 6 template sections (In-flight, Completed this run, Queued, Blocked/HANDBACKs, Quota remaining, REVIEW_ME open items) plus ISO-timestamp header. RELAY_STATUS_PATH env var support. Agent-based file write (Workflow JS has no fs access); `log()` condensed one-liner on each rewrite. Created `tests/test_relay_status.sh` (14 static grep checks). Full suite green (12 files, 0 failures).
Friction: none — RELAY_STATUS.md writer is a Workflow JS helper; live integration-behaviour tests deferred to id:83c9 pilot per the ROADMAP spec.

## 2026-06-12 21:53 — reviewer (Fable)

review turn (window fable-ckpt-20260612-1827..a047097): 3 executor items audited. id:aeaf and id:80e2 genuine-green (specs themselves mandated static checks; implementations match acceptance). id:9934 flagged and FIXED: quota-stop.sh compared the live cache's 0–100-percent `.utilization` against the 0–1 fraction threshold — in production every run ≥0.9% usage exited 1, permanently closing the quota gate; tests passed only on fraction-scale synthetic fixtures. Fix: val >= threshold*100, percent fixtures, live-shaped 37/24/8 regression case (item stays closed). Soft note: id:80e2's unit test is static-grep only vs the spec's synthetic-payload check — behavioral verification rescoped into id:1ad7 pilot acceptance (node not a repo dependency). HARD execution: id:230f front door shipped red-test-first (tests/test_fables_front_door.sh, SKILL.md autonomous default mode + knobs table, relay-loop.js args.interactive pass-through). ARCHITECTURE.md §10 synced with the autonomous-pool components; contract pointer v1=v1 OK; TODO relay line refreshed (3 open: 83c9, 1ad7, 3346-gated). Suite 13/13 green.
Friction: none.

## 2026-06-12 21:57 — reviewer (claude-fable-5)

review ckpt-1827 window: 9934/aeaf/80e2 verified, quota-stop percent-scale fix, id:230f autonomous front door, ARCHITECTURE+SKILL drift sync

## 2026-06-12 22:32 — reviewer (claude-fable-5)

id:83c9 relay-loop.js autonomous pool implemented (income-preferring scheduler per user directive); id:a354 user-facing relay guide docs/fables-relay.md; id:456a flake instrumentation

## 2026-06-12 22:38 — reviewer (claude-fable-5)

Executor contract v2: RELAY_LOG self-reports are committed-or-not-written (no-op sessions leave the tree untouched); pointer trail (own CLAUDE.md, handoff.md C1) follows. make test 14 passed.

## 2026-06-12 23:50 — reviewer (claude-fable-5)

id:1ad7 pilot retrospective (run relay-20260612-2304, wf_2c2050dd-08d): first full autonomous pool run over 21 confirmed repos — 40 agents, ~990k subagent tokens, 23 min. WORKED: discovery classified all 21 correctly (incl. ai-codebench path override and zelegator declared-acceptable dirt); income-first execute scheduling dispatched zkWhale first; serialized integrator landed 6 execute units (ai-codebench, zkm-whatsapp, isochrone, zkm-social, zkm-claude-ai, zkm-ner) with zero push races despite a concurrent MANUAL relay session integrating zkWhale review work in parallel; quota gate fired at five_hour=90% and the graceful drain behaved exactly as designed; resume-after-pause (user dismissed /workflows dialog) reused cached agent results; all 3 HANDBACKs were recoverable with zero lost work (orchestrator integrated them post-run: zkm-calendar ckpt-2342, zkm-eml ckpt-2343, zkWhale ckpt-2345 after a trivial import-conflict resolution, typecheck + 346 tests green). NEEDS REVISION: (1) review starvation — 13 execute units ate the whole budget, all 7 review units quota-deferred, anti-gaming window stays open (id:1dff); (2) integrator dirty-check is judgment, not mechanics — one Sonnet integrator treated '?? untracked' as clean (proceeded into a conflict on zkWhale) while two others aborted on ' M uv.lock'; also RELAY_STATUS Queued section double-lists deferred repos (id:59ea); (3) uv.lock drift from a parent-repo version bump blocked 2 integrations + 1 dispatch — benign, mechanically resolvable (id:bae5); (4) live cross-session collision on zkWhale confirms id:ebfb (worktree-as-lock option (c) would have prevented the dispatch). Caveats vs acceptance: run was unattended except the dialog pause/resume and a mid-run orchestrator sentinel on zkWhale (which the integrator ignored — untracked files are NOT a fence; folded into id:d0bc). STRONG_TIER=opus handoff pilot NOT run (no handoff units classified this round). RELAY_STATUS.md: all six sections populated correctly — id:80e2 behavioral check passes modulo the id:59ea queued duplication.

## 2026-06-13 10:58 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review 20260613-1048: 19 commits audited clean, 16 tests green, id:3737/1ad7 verified, doc-drift fix for --fable-down knob

## 2026-06-13 15:35 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review 20260613-1519: 7 commits audited clean, 16 tests green, resurrection-check passed, doc-drift fix for RELAY_QUOTA_THRESHOLD_<BUCKET>

## 2026-06-13 16:18 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review 20260613-1604: 1 commit (7c55793 POOL_WIDTH) audited clean, 16 tests green, default/override verified, doc-drift fix for POOL_WIDTH knob + front-door forwarding

## 2026-06-13 17:17 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review 20260613-1712: 1 commit (37e7926 id:738c API-error failsafe) audited clean, 16 tests green, resurrection/no-op check passed, contract pointer v2 in sync, no drift

## 2026-06-13 17:50 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review 20260613-1745: 1 docs-only commit (9e0bd90 forbid sudo pamac) audited clean, 16/16 tests green, no gaming, contract pointer v2 current, no roadmap delta

## 2026-06-13 18:19 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review 20260613-1812: 3 docs/relay-contract commits audited clean, 16 tests green, id:3114 verified-closed, no source/test changes (nothing to game), contract pointer v2 in sync

## 2026-06-13 18:44 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review 20260613-1837: 1 commit (id:b8ae review→execute chaining) audited clean, 16/16 tests green, contract pointer v2 current, routine_open=0

## 2026-06-13 18:50 — reviewer (claude-opus-4-8, relay-loop)

review 20260613-1850: window fable-ckpt-20260613-1844..HEAD = 1 commit (0262d3a) — a docs-only TODO.md addition by user recording relay defect id:b4f7 (TERMINAL/archived repos re-handed-off forever; voicebot 5×; stopgap = relay.toml classification=excluded). No code/test/spec changes. Test-integrity audit: zero test files touched/deleted, no resurrection/weakening surface. Full suite 16 pass / 0 fail / 0 expected-red. Contract pointer v2 == fables-executor SKILL v2 (no drift). No ARCHITECTURE/README drift. Roadmap re-derived: all [ROUTINE] ticked, 0 open [ROUTINE]; sole open item id:3346 [HARD]. routine_open=0.

## 2026-06-13 18:56 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review 20260613-1850: 1 commit audited clean (id:b4f7 docs-only TODO note), 16 tests green, no drift, 0 open ROUTINE

## 2026-06-13 19:57 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review 20260613-1957: window fable-ckpt-20260613-1856..HEAD = 3 commits (7eaaad6 quota-stop self-refresh of stale cache, 267c0af RELAY_QUOTA_DECAY_7D time-decaying 7d/Sonnet cap, 5e3ab93 id:60e1 self-feeding relay loop runRound+outer while). Test-integrity audit: no test files deleted; one modified assertion (test_quota_stop "stale cache → exit 2" now USAGE_CREDS=/dev/null) is STRENGTHENED+hermetic, documenting the intentional self-refresh behavior, not weakened; all other test changes additive (new bucket-decay cases + static grep guards). Resurrection check: the original stale-cache test now exits 0 against new impl ONLY because the self-refresh genuinely hit /api/oauth/usage and found healthy quota — the behavior change IS the shipped feature (7eaaad6), not a spec-weaken. Decay math independently verified (5d-left→cap≈0.53). relay-loop.js node --check OK; runRound/MAX_ROUNDS/roundCapHit/cross-round accumulators all present and consistent with tests 15-17. Full suite 16 pass / 0 fail / 0 expected-red. Contract pointer v2 == fables-executor SKILL v2 (no drift). SKILL.md documents both new knobs + self-feeding loop; README/ARCHITECTURE intent unchanged (no drift fix needed). Roadmap re-derived: all [ROUTINE] ticked, 0 open [ROUTINE]; sole open item id:3346 [HARD — strong model]. routine_open=0. REVIEW_ME 0 open boxes.

## 2026-06-13 20:04 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review 20260613-1957: 3 relay commits (quota self-refresh, RELAY_QUOTA_DECAY_7D cap, self-feeding loop id:60e1) audited clean, 16/16 tests green, no gaming, contract v2 in sync, routine_open=0

## 2026-06-13 23:04 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review 20260613-2304: window fable-ckpt-20260613-2004..HEAD = 3 commits (26287cc id:60e1 done, fb1dbad @manual BDD automation triage, f0652d8 T4 manual-BDD checklist + REVIEW_ME triage). Pure docs+TODO diff — no code/script/skill-spec/test files touched (git diff --name-only: TODO.md + 3 new docs/*.md). Test-integrity audit: zero test files deleted/weakened/added; no resurrection or fixture-special-casing surface. id:60e1 closure is legitimate — marks shipped+verified self-feeding relay loop done, citing a concrete run (wf_29c465c4-bad, 7 rounds, drained termination, 8 integrations, 0 handbacks), not a test-gated item. Full suite 16 pass / 0 fail / 0 expected-red. BDD: dotclaude-skills' 14 @manual scenarios (5 meeting + 4 relay-executor + 4 install per feature files; install legs already covered by test_makefile_skills.sh DEST_DIR) are T4-by-convention and surfaced to the human via docs/manual-bdd-checklist-2026-06-13.md — not test debt. The two new triage docs (bdd-automation 129→T1/T2/T3/T4; review-me 88→R1/R2/R3/stale) are cross-repo planning records correctly placed under docs/; the T1[ROUTINE]/T2[HARD] roadmap items they file land in OTHER repos' roadmaps (dotclaude-skills itself has 0 T1/T2). Contract pointer v2 == fables-executor SKILL v2 (no drift). No README/ARCHITECTURE drift (docs-only window, no new command/knob/artifact). Roadmap re-derived: all [ROUTINE] ticked, 0 open [ROUTINE]. routine_open=0. No gaming flags, nothing reopened, no REVIEW_ME boxes written.

## 2026-06-13 23:35 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review 20260613-2304: 3 docs/TODO commits (id:60e1 done, BDD-automation + REVIEW_ME triage) audited clean, 16/16 tests green, no gaming, contract v2 in sync, routine_open=0

## 2026-06-14 09:56 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review 20260614-0942: id:5902 two-switch verified genuinely green (gate STRONG_MODEL==='claude-fable-5', new static test, no gaming), 17/17 tests green, fixed fables-relay.md -d knob drift, contract v2 in sync, routine_open=0

## 2026-06-15 09:48 — strong-execute (claude-opus-4-8, fable-standin, manual HARD)

da26 HARD-execute verdict (Opus-apex, gated, Sonnet-never) + tested probe-fable.sh; 23/23 green

## 2026-06-15 10:09 — strong-execute (claude-opus-4-8, fable-standin, D8 design)

D8 workflow-extraction analysis (id:6ba4): no Workflow for /meeting; dedupe contract prose → id:962a/3103

## 2026-06-15 10:13 — strong-execute (claude-opus-4-8, fable-standin, manual HARD)

/fables-turn human mode (id:72cc/2892): cross-repo human-backlog triage + gather-human-backlog.sh + references/human.md; 24/24 green

## 2026-06-15 10:45 — strong-execute (claude-opus-4-8, fable-standin, manual HARD)

rename fables-* → relay + merge executor as /relay executor (id:1cb4); contract v3, aliases, idempotent install fix; 24/24 green

## 2026-06-15 10:56 — strong-execute (claude-opus-4-8, fable-standin, manual HARD)

relay-ckpt-* tag prefix + dual-prefix matching + model-tracked Fable-bonus queue (id:96a8/e030); 25/25 green

## 2026-06-15 11:04 — review (claude-opus-4-8, fable-standin, relay-loop)

Verified 5481502 install-manifest+quota-stop fix (genuine: quota-stop.sh exits 2 on bare positionals; all 6 relay/scripts now in Makefile manifest); 25/25 green, no deleted/weakened tests in window. Noted id:5f09 (new) is an open [ROUTINE] shipped WITHOUT its red spec test — left open, routine_open=1 for execute chaining. Refreshed stale TODO relay-mirror (id:d5e0): 1→3 open ROADMAP items. Pointer v3=canonical, no spec drift.

## 2026-06-15 11:19 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: verified 5481502 install-manifest+quota-stop fix (genuine); 25/25 green; re-derived ROADMAP, refreshed stale TODO mirror 1→3

## 2026-06-15 11:59 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review 20260615-1152: verified id:bc9d (per-repo integrator) + 82a2dda (quota throttle) genuine; suite 26 green; 1 open [ROUTINE] (5f09)

## 2026-06-15 14:59 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: audited 16 commits / 9 closed items (dispatch-safety cluster + 0902 interactive-claim) — all genuinely green, no gaming flags, suite 40-green, 2 open [HARD] items remain

## 2026-06-15 15:59 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: verified fb75/6e9d/3ac8 (relay-loop inject+stale-reap ships) genuine — 43 tests green, no gaming, ledger consistent, contract v4 current

## 2026-06-15 16:23 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: verified id:8c35 doc-only ledger commit genuine (no code/test churn, contract v4 current, ledger consistent); mini-handoff'd its missing red spec test — 43 green + 1 expected-red

## 2026-06-15 17:12 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

Reviewed cb50/53f7/9ed4/2909 — all verified-green (no gaming); doc'd DISCOVER_SHARDS knob, refreshed open-item count 4→8, 45 tests green

## 2026-06-15 — executor (sonnet)

Worked all 5 open [ROUTINE] items in one session:
- id:8c35 — surfaced REAL quota-stop reason: quotaGate now distinguishes exit 2 (stale-cache) vs exit 1 (real exhaustion) and surfaces stopReason in log(), run result, and RELAY_STATUS.md "## Stop reason" section.
- id:c8db — hardened relay-state-write.sh toml-set: value via ENVIRON (no awk -v escape mangling), key by literal substr-prefix compare (no regex metachar risk). New edge-case tests added.
- id:fa05 — created relay/scripts/gaming-scan.sh (mechanical gaming detector): DELETED_TEST / ADDED_SKIP / REMOVED_ASSERT flags from git diff; Makefile registered; hermetic tests with negative control (id:3b02 model case).
- id:dfaf — rewrote review.md §2 to delegate mechanical checks to gaming-scan.sh; §2a runs script, §2b retains only resurrection-check + fixture-special-casing judgment prose; --diff-filter=D removed from inline prose.
- id:3826 — added logGamingFlags() to relay-loop.js integrate(): fire-and-forget Haiku agent appends JSON line to ~/.claude/logs/relay-gaming-flags.log per review integration; DEFERRED-FLEET SEAM comment at call site (id:2909 D1).
Friction: none — all items self-contained and well-scoped. Full suite: 48 passed, 0 failed.

## 2026-06-15 17:31 — executor (sonnet, relay-loop)

executor: close all 5 open [ROUTINE] items — quota-stop reason (8c35), toml-set hardening (c8db), gaming-scan.sh (fa05), review.md §2 delegate (dfaf), gaming-flag rate logger (3826)

## 2026-06-15 17:48 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

HARD id:401c strong-model audit run 3 (window 1559..HEAD): 2 defects fixed inline — test_relay_executor.sh broken by stub-untrack (suite 1-red→48/0), gaming-flag logger dead feed (review prompt never requested its fields); regression guard added

## 2026-06-15 18:01 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

HARD id:401c strong-model audit run 4 (window 1748..HEAD): clean, 1 coherence drift fixed inline (id:414a stale GATED marker); suite 49 green

## 2026-06-15 19:20 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review 191123: 3 commits clean (no gaming); 2 relay-loop.js fixes verified green by additive tests; D2 cross-ledger reconciled (tick fa05/dfaf/3826 in TODO, refresh d5e0 8→3 open all HARD); routine_open=0

## 2026-06-15 19:31 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review relay-20260615-193130-2122 (window relay-ckpt-20260615-1920..a8fe504, 1 commit): defect-fix verified genuine — logGamingFlags() (id:3826) process.env.HOME sandbox violation removed (literal ~ path, agent-expanded like writeRelayStatus id:c34a). Resurrection check PASSED: original Date-only guard test runs green against the new implementation, so the impl genuinely dropped the forbidden API. The test edit only STRENGTHENED the spec (Date-only → Date/process/require/fs/Math.random backstop pattern). gaming-scan.sh flagged REMOVED_ASSERT (removed=2,added=1) on the test — resolved as a false-positive artifact (id:3b02-style negative control): the single-line grep was split into PATTERN= + hits= and two message strings reworded; matching logic broadened, no assertion weakened. Suite 50/50 green. No TODO/ROADMAP additions in window → no reverse-handoff. Contract pointer v4 current. routine_open=0.

## 2026-06-15 19:37 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: verified id:3826 process.env.HOME sandbox fix genuine (resurrection check green, spec only strengthened); suite 50/50, routine_open=0

## 2026-06-15 19:49 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

HARD id:401c strong-model audit run 5 (window 1748..HEAD): clean — two pool-crash fixes verified correct, cross-ledger coherent; suite 50/0

## 2026-06-15 21:29 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

Review of 7456e1f (gather-human-backlog paused filter): gaming-scan clean, suite 50/50 green, filter verified, pointer v4 current, routine_open=0

## 2026-06-15 21:37 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

HARD id:401c strong-model audit run 6 (window relay-ckpt-20260615-1937..HEAD): clean — only first-seen code is the 2-line gather-human-backlog.sh `paused` filter (7456e1f); no code/security/coherence defects. Forward-robustness gap fixed inline: the new sweep-skip filter shipped untested → added a non-vacuous regression guard (repoD paused fixture) to test_relay_human.sh. Suite 50/0. Item stays open (recurring by design).

## 2026-06-15 21:47 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

HARD id:401c strong-model audit run 7 (window relay-ckpt-20260615-2129..HEAD): clean — only first-seen code is the `warn_nested_worktrees` stale-checkout guard in gather-human-backlog.sh (83d8614); no code/security/coherence defects (`set -e`-safe grep guards, `-F` trailing-slash prefix match, stdout/stderr split all verified correct). Forward-robustness gap fixed inline (same class as run 6): the new warning shipped untested → added a non-vacuous regression guard (test_relay_human.sh section 4: real-git nested-worktree fixture + clean-repo negative control + stdout-clean assertion). Suite 50/0. Item stays open (recurring by design). Note: this branch also carries the un-integrated run-6 commit b6b086d (ahead of main).

## 2026-06-15 21:50 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

HARD id:401c strong-model audit run 7 (window 2129..HEAD): clean — nested-worktree guard 83d8614 audited, no defects; untested-warning gap fixed inline (test_relay_human.sh §4). Suite 50/0.

## 2026-06-15 — executor (claude-opus-4-8)

Worked id:a59e — built relay/scripts/profile-run.sh, the workflow profiler for the /relay loop. Parses a run's on-disk journal.jsonl + per-agent agent-*.jsonl transcripts into per-agent records {label, phase, model, start/end, duration_ms, tokens_in/out} and emits: (a) a concurrency-over-time curve vs the harness cap min(16,cores-2) with %-time-at-cap; (b) round-boundary analysis that distinguishes a logical block from being merely queued-behind-cap (the recurring "was a Haiku waited for before the next discovery round" question — now answerable with data: at each discovery prelude's start it reports live-occupant count vs cap and labels the boundary clean-start / overlapped-not-capped / queued-behind-cap); (c) per-phase and per-model aggregates (count, total/avg duration, tokens). Resolves its arg as a wf-dir, a wf_* id, or a runId substring (RELAY_WF_SEARCH_ROOT-overridable). Stdlib-only, pure read. Verified against a real 83-agent run (peak 6 = cap, 39.9% at cap). Added hermetic tests/test_profile_run.sh + registered the script in the Makefile relay_FILES/_EXEC/_ALLOW manifest. Suite 51/0.
Friction: phase/label are NOT in the journal (only started/result + agentId), so they're a best-effort heuristic on each agent's first prompt — documented as such in the script. Item lives in TODO.md (not a ROADMAP [ROUTINE] item with red-test spec); built on explicit `/relay executor a59e` invocation, so the test omits a `# roadmap:` header.

## 2026-06-15 — executor (claude-opus-4-8)

Worked id:08a3 — built relay/scripts/profile-runs-batch.sh (batch driver over profile-run.sh) + tests/test_profile_runs_batch.sh, and ran it over all 31 retained relay runs (1935 agents) to settle the recurring "discovery waits on a single Haiku" suspicion. Findings note: docs/relay-profiling-2026-06-15.md. RESULT: the claim does NOT reproduce — 0/41 round boundaries were cap-blocked, max inter-round gap 4.1s (median 0.1s); the 15 boundaries with a single live Haiku at prelude start all had free concurrency slots (overlapped-not-capped, not blocking). 80-20: pool is under-saturated (mean 14.7% time-at-cap, mean peak concurrency 4.8 vs ~6 cap) → the efficiency lever is more parallel work (id:ca87 intra-repo parallelism), NOT a bigger cap; Haiku status+quota agents are 1020/1935 (the /workflows visual noise) — optional cheap wins are 1 status-write/round + longer quota cache. Also fixed a real bug in profile-run.sh's default search-root glob (was projects/*/subagents/workflows, one level short of the projects/*/*/subagents/workflows session-dir layout) — runId/wf-id resolution would have failed in real use; tests used RELAY_WF_SEARCH_ROOT so hadn't caught it. Suite 52/0. Separately (per user) raised cleanupPeriodDays to 999999 in ~/.claude/settings.json to stop transcript pruning going forward.
Friction: id:08a3 lives in TODO.md (not a ROADMAP [ROUTINE] item); built on explicit user request, so test omits a # roadmap: header.

## 2026-06-16 — review (claude-opus-4-8, relay-loop)

Reviewed window relay-ckpt-20260615-2150..be6b98b (8 commits: 2 profiler scripts + tests, 6 TODO sweeps). TRUST-BUT-VERIFY: clean. Mechanical gaming-scan.sh over the window emits ZERO flags (no DELETED_TEST / ADDED_SKIP / REMOVED_ASSERT); no test files modified so no resurrection check needed; the only test changes are two NEW hermetic suites (test_profile_run.sh, test_profile_runs_batch.sh) that build synthetic wf_* fixtures and assert on real --json structure (the overlapped-not-capped vs queued-behind-cap distinction is genuinely exercised under both cap 4 and cap 1). Full suite 52/0 green in the worktree. The profile-run.sh search-root glob fix (projects/*/subagents → projects/*/*/subagents) is a real bug fix the new batch test's fixture layout confirms. Both scripts correctly registered in Makefile relay_FILES/_EXEC/_ALLOW. Findings doc docs/relay-profiling-2026-06-15.md is substantive (31 runs/1935 agents, Haiku-wait claim does not reproduce). Contract pointer v4 == canonical v4 (no drift); profiler scripts are internal diagnostics (not user-facing commands) so no README/docs/relay.md gap. verified_green: id:a59e, id:08a3.

Reverse-handoff (§5b) — 3 new open TODO items added this window, all DESIGN-JUDGMENT (NOT mini-handoff-promoted to ROADMAP): id:ca87 (intra-repo parallelism) — explicitly self-flagged "Likely wants a /meeting", non-obvious tradeoffs (worktree-per-unit vs serialized stages, claim re-granularity, merge ordering) → meeting candidate. id:3b1e (patient stop for the pool) — touches the live Workflow engine relay-loop.js with open sentinel-mechanism choices (file vs relay.toml flag); editing relay-loop.js is the exact class the pool crashed on 3x → [HARD], not a clean [ROUTINE] red-green. id:e37b (guard relay-loop.js vs sandbox bugs) — offers two alternative designs (runtime smoke check OR protected-file) → design-judgment, [HARD]. None promoted to ROADMAP; all kept as TODO/meeting candidates. routine_open = 0 (all 3 ROADMAP open items are [HARD — strong model]: id:401c, id:414a, id:3346).
