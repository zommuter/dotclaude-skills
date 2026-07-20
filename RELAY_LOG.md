# Relay log <!-- merge=union; append-only — never edit or reorder past entries -->

## 2026-07-07 — executor (Sonnet) id:b3ee

Worked id:b3ee — extended the EXISTING `meeting/orphan-scan.sh` (no NIH) with a new
`--shipped`/`-s` mode implementing the two D1/D2 report-only reconciliation classes from
`docs/meeting-notes/2026-07-07-1138-stale-ledger-root-cause.md`: **TICK-READY** (an open
`- [ ]` TODO.md item with NO gating lexeme AND a linked `tests/test_*.sh` — inline path in
the line, or a test carrying `# roadmap:<id>` for the item's token — that actually runs
GREEN) and **GATE-STALE** (an open item WITH a gating lexeme whose TODO.md line is >=14
days old by `git blame` author-time, threshold overridable via
`ORPHAN_SCAN_SHIPPED_AGE_DAYS`). Both classes are advisory text only — the mode NEVER
touches a checkbox; verified this by asserting TODO.md's raw checkbox text is byte-identical
before/after the scan in the new test. Wired into two consumers per D3: `/relay review`
step 5 (`relay/references/review.md`, new bullet right after the roadmap-lint grammar
bullet) instructs the reviewer to run `orphan-scan.sh --shipped` and manually verify each
TICK-READY hit before ticking, surfacing GATE-STALE hits to REVIEW_ME; `todo-update/SKILL.md`
gained a new Step 5 doing the equivalent for a normal session, same "advisory only, verify
before acting" framing. New hermetic test `tests/test_orphan_scan_shipped.sh` builds a real
git repo in `mktemp -d` with `GIT_AUTHOR_DATE`/`GIT_COMMITTER_DATE`-controlled commits so
git-blame ages are deterministic, and covers exactly the 5 cases from the design note:
(1) green-test + no-gate → TICK-READY, (2) gate-lexeme + 20-days-old line → GATE-STALE,
(3) gate-lexeme + 5-days-old line → neither (observe-window correctly suppressed), (4)
genuinely-open item with no linked test → neither, (5) an already-`[x]` item → never
appears. No ROADMAP.md twin exists for id:b3ee, so the test file omits the `# roadmap:XXXX`
header per the stated testing convention (comment explains why). Full suite: 189 passed, 0
failed, 0 expected-red. Ticked id:b3ee `[x]` in TODO.md via `md-merge.py update-ids`
(flock'd, per convention for `<!-- id:XXXX -->` lines).
Friction: none — the design note's D1/D2/D3 decisions were unambiguous and orphan-scan.sh's
existing mode-dispatch pattern (cross-ledger/promotion elif chain) was a clean template to
extend.

## 2026-07-07 — executor (Sonnet) id:6f61

Worked id:6f61 — closure-only verification, no new code. Confirmed all three shipped pieces are actually in place: (1) `meeting/memory-append.sh` exists as the flock'd helper; (2) `tests/test_memory_append.sh` (header "Tracks TODO id:6f61") exercises 20 concurrent appends against a shared `MEMORY.md` and asserts each of the 20 pointer lines lands exactly once (no lost update, no duplication); (3) the "REMAINING" global-adoption gap noted in the TODO item is closed — `~/.claude/CLAUDE.md`'s "Memory writes" section (line 117) instructs going through `~/.claude/skills/meeting/memory-append.sh "<MEMORY.md path>" "<pointer line>"` rather than a plain Write/Edit for the shared index append. No ROADMAP.md mirror of id:6f61 existed, so nothing to tick there. Ticked `- [x]` on the TODO.md id:6f61 line with a CLOSED-2026-07-07 note, preserving the full prior text. Full suite: 186 passed, 0 failed, 0 expected-red.
Friction: none — pure verification, test file and helper were untouched.

## 2026-07-03 — executor (Sonnet) id:854c

Worked id:854c — the three JS-side dispatch backstops in `relay/scripts/relay-loop.js` (id:000d finished-repo demote, id:9973 HARD-pool demote, id:ad74 INTENSIVE promote) now persist each fire durably, not just `log()` to sandbox stdout. Added a shared `emitBackstopFire(backstopId, repo, verdict)` helper right after `pushEvent`'s definition (near line 57), which calls `pushEvent('backstop', { backstop: backstopId, repo, verdict })` — reusing the existing durable pipeline (pendingEvents → snapshotState → RELAY-EVENTS heredoc → relay-status-publish.sh → relay-state-write.sh event-append → relay-events.jsonl) exactly as the reviewer specified; no new sink invented, no fs/net/shell/Date.now()/process.env introduced. Wired one call per affected unit inside each of the three backstop blocks' existing demote/promote loops (id:000d passes the pre-demote verdict, id:9973 passes 'hard', id:ad74 passes the post-promote verdict 'execute') — demote/promote logic itself untouched, this is instrumentation only. Added the `id:854c` marker comment on the shared helper.
Target test `tests/test_backstop_fire_log.sh` (roadmap:854c) passes both parts: (A) source-shape — all three backstop ids emit through `pushEvent('backstop', …)` carrying repo+verdict, `node --check` and `lint-workflow-templates.mjs` stay clean; (B) outcome — a synthetic backstop event round-trips through the real publish→event-append pipeline into `relay-events.jsonl` with kind/backstop/repo/verdict. Full suite: 178 passed, 0 failed, 2 expected-red (unrelated pre-existing open items id:14d0 and id:5884).
Friction: none — followed the reviewer's chosen sink and call-site guidance exactly; smallest-diff edit to the crash-prone engine file, mirroring existing `pushEvent` call syntax verbatim.

## 2026-07-03 — executor (Sonnet) id:e833

Worked id:e833 — closed id:3134's instrument gap, two parts per the reviewer's guidance. (1) `backtest-verdict.py`'s `--append-log` shadow-log entry now carries `red_rows`: a list of `{repo, dispatch_verdict, classifier_verdict, sig}`, one per RED bucket, appended at the point the RED bucketer fires (`len(red_rows) == entry["red"]` by construction) — a disputed RED is now attributable without reconstructing from `relay-events.jsonl`. (2) Sig-fidelity fix via approach 2a (per reviewer instruction, not 2b): `discover-sig.sh` now computes a `substantive_unaudited` signal — mirroring `gather-repo-state.sh`'s id:365b logic (audit ref = `last_strong_ckpt` from the toml block, else the latest ckpt tag, advanced to a newer `reviewer*`/`strong-execute*`-labeled tag when one exists; unaudited iff any non-checkpoint commit since that ref touches more than just `uv.lock`) — and hashes it as a new `== substantive_unaudited ==` blob section. This closes the gap where a force-retagged ckpt (same tag name/message, different target commit — e.g. the audit anchor advancing across an execute→review boundary) left the sig byte-identical despite a real state change. Added the section strictly additively (superset rule preserved; no existing section removed/reordered; fail-open empty/sentinel-sig contract untouched).
Target test `tests/test_backtest_red_row_persist.sh` (roadmap:e833) passes. Full suite: 177 passed, 0 failed, 2 expected-red (unrelated pre-existing open items id:14d0 and id:5884) — no sig-stability test broke; `test_discover_sig.sh` and all `test_backtest_*.sh` stay green because the new signal is additive (existing fixtures never force-retag a ckpt tag onto a different target, so their sigs are unaffected).
Friction: none.

## 2026-06-30 — executor (Sonnet) id:9062

Worked id:9062 — roadmap-lint case (d) realigned to the operative-vs-advisory INTENSIVE doctrine (meeting 2026-06-30-2238). Removed the pool-only restriction from `relay/scripts/roadmap-lint.sh` (old: reject INTENSIVE unless `[HARD — pool]`; new: accept INTENSIVE on any recognised lane, reject only on lane-less items via the existing missing-class-tag grammar). Updated the `class_re` comment to reference id:9062. Restated the operative-vs-advisory doctrine in `relay/references/hard-lanes.md` under a new "Operative vs advisory" subsection. Reconciled `tests/test_roadmap_lint_tagprose.sh` case (d): repointed from `[HARD — meeting] [INTENSIVE]` (now accepted as advisory) to a genuinely lane-less `[INTENSIVE]` item — exercises the same reject path via the grammar's missing-class-tag check rather than an INTENSIVE-specific check. All 142 tests pass, 2 expected-red (id:5eb3/id:5ac6, unrelated open items). `roadmap-lint.sh ROADMAP.md` exits 0. Reconcile choice: repointed-to-laneless.

## 2026-06-30 — executor (Sonnet)

Worked id:07be — fixed the `execve` overflow in `gather-repo-state.sh`'s `emit()` function. The old code set ~20 env vars (including the full ROADMAP content) on the `python3` command line; a ROADMAP larger than `MAX_ARG_STRLEN` (128KB) caused "Argument list too long". Fix mirrors the classify-repo.sh (id:3f0f) pattern: write all field values via `printf '%s'` to per-key files under `mktemp -d`, pass only the tmpdir path as `EMIT_DIR` to python, and have python read values with `open()`. The trap uses `trap "rm -rf '$_blobdir'" EXIT` (definition-time expansion) so `set -u` does not fire when it runs after the function returns. Output verified byte-identical against the old version on `~/src/zelegator`. Full suite 131 pass / 0 fail / 0 expected-red.
Friction: one iteration to fix `set -u` interaction with `local` + deferred trap expansion.

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

## 2026-06-16 06:43 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review 2150..be6b98b clean: profiler batch + Haiku-claim findings verified (id:a59e, id:08a3), gaming-scan zero flags, suite 52/0, routine_open=0

## 2026-06-16 06:53 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

HARD id:401c strong-model audit run 8 (window 2150..HEAD): profiler batch clean, search-root glob comment drift fixed inline, suite 52/0

## 2026-06-16 09:36 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: verified 12 relay-meta commits (id:2d20 drain+gated-HARD, id:8b1f clean-sizeout, id:4267 run-total seatbelt, id:c8b6/219b observability) genuinely green; suite 53/0, gaming-scan clean, negative-control confirmed; 0 open ROUTINE

## 2026-06-16 09:59 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

HARD id:401c strong-model audit run 9 (window 0653..HEAD): observability/drain/quota-seatbelt/relay-burn clean, event-append flock comment fixed inline, injection-seam TODO id:287b, suite 53/0

## 2026-06-16 10:22 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review dotclaude-skills @relay-ckpt-20260616-0959: 2 ledger-only commits, gaming-scan clean, no green-by-weakening; reverse-handoff promoted orphan-reconcile D1/D2/D3 (689c/3313/1f53) to ROADMAP [ROUTINE] + 3 red specs; suite 53/0/3xred

## 2026-06-16 — executor (claude-opus-4-8)

Worked id:689c — a parallel session had committed the orphan-park impl (relay-loop.js
discovery PARKs commit-bearing stale worktrees into relay/orphan/* + removes the dir,
commit 796e275) and the red spec test_relay_orphan_park.sh now passes, but the ROADMAP
box was left unticked. Verified the done-check (targeted test PASS, full make test 55/0,
2 expected-red = 3313/1f53) and ticked the box, closing D1 and unblocking D2/D3.
Friction: none — straight verify-and-tick of already-landed work (relates to id:a6cb,
the /meeting-leaves-impl-uncommitted/unticked pattern).

## 2026-06-16 11:57 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review 2026-06-16: 14 commits since relay-ckpt-20260616-1022 verified genuinely green (689c/3313/1f53 orphan-reconcile + archive-done multiline + relay-econ), no gaming flags; cross-ledger synced (ticked TODO 3313/1f53); routine_open=0

## 2026-06-16 12:13 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: audited doc-only commit 67fc66a (TODO id:872e bisect-skip meeting-candidate); gaming-scan clean, suite 58/0, no ROADMAP delta, routine_open=0

## 2026-06-16 12:38 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

relay/human id:f6c9 — /relay human now surfaces pool's gated-HARD 'needs a /meeting' backlog (gather-human-backlog kind=gated_hard re-derived from ROADMAP); 58/0 green

## 2026-06-16 12:50 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

HARD id:401c strong-model audit run 10 (window 95d3d07..HEAD): orphan-reconcile/relay-econ/archive-multiline/gated-HARD-sweep clean; fixed relay-reconcile.sh missing-arg shift-2 set-e bug inline (+regression guard), doc nit; suite 58/0

## 2026-06-16 13:02 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

HARD id:401c strong-model audit run 11 (window 5ab8c12..HEAD): ledger-only window (TODO id:0547 + RELAY_LOG ckpt), clean — no code/security/coherence defects; verified id:0547 race diagnosis against relay-loop.js; suite 58/0

## 2026-06-16 13:12 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

HARD id:401c strong-model audit run 12 (window d3ca7a9..HEAD): ledger-only, clean — no code/security/coherence defects; cross-ledger coherent (0 ROUTINE / 3 HARD); suite 58/0

## 2026-06-16 13:52 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

id:7570 — fix cross-session lease leak (per-unit finally release) + long-child liveness (worktree-anchored staleness + heartbeat); suite 59/0

## 2026-06-16 15:14 — reviewer (claude-opus-4-8)

review 2026-06-16: 3 commits since relay-ckpt-20260616-1352 (Della + Orla persona appends, archive-done maintenance) — no code/test/spec changes; gaming-scan clean; suite 59/0/0; routine_open=0; relay-executor contract pointer v4 == canonical (no drift)

## 2026-06-16 16:20 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: audit since relay-ckpt-20260616-1514 (2 doc-only persona registrations Dex+Milo — clean, no gaming, 0 open ROUTINE)

## 2026-06-16 17:46 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

hard: 414a Tier B model gaming-canary harness (tests/gaming-canary/ + make gaming-canary), green

## 2026-06-16 19:06 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review since relay-ckpt-20260616-1746: id:10c0 (doc-only) clean, promoted to ROADMAP as gated HARD; 60 tests green, 0 open ROUTINE

## 2026-06-16 20:34 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: audit a8c361e (id:f6c9) — fixed stale RED negative-control test + human.md doc drift from the full-HARD-backlog behavior change; suite 60-green

## 2026-06-16 19:57 — reviewer (claude-opus-4-8)

review since relay-ckpt-20260616-2034 (2 commits: 3048a09 /loop nudge; 8dcc5f8 Sven persona). gaming-scan clean (no DELETED_TEST/ADDED_SKIP/REMOVED_ASSERT). loop-hint.sh behaviour verified by hand (first-run prints, within-GAP suppresses, >GAP re-prints, custom GAP honoured; always exit 0). Sven persona addition is well-formed per personas.md format. **Regression caught & fixed:** 3048a09 added relay/scripts/loop-hint.sh + SKILL wiring but omitted it from the Makefile install manifest — test_relay_install_manifest.sh (green at the baseline checkpoint) went red; registered scripts/loop-hint.sh in relay_FILES/_EXEC/_ALLOW (commit 3c0438a). Full suite now 60 passed, 0 failed, 0 expected-red. No ROADMAP/TODO ledger changes this window; 0 open [ROUTINE] after re-derivation; no reverse-handoff items to qualify. Contract pointer at v4 (current). 0 REVIEW_ME.

## 2026-06-16 22:04 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review since relay-ckpt-20260616-2034: gaming-scan clean, loop-hint.sh verified; fixed install-manifest regression (loop-hint.sh unregistered) — suite 60/0

## 2026-06-16 22:41 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review since relay-ckpt-20260616-2204: Quinn persona append (doc-only) clean; gaming-scan clean, suite 60/0, 0 open ROUTINE

## 2026-06-17 — executor (sonnet)

Worked id:9cb1 — attribution analysis for discover-shard econ bucket. Code trace: relay-loop.js:537/627 pass `phase:'Discover'`; profile-run.sh:140 heuristic maps to `"discover"`; relay-econ.py:36 `PHASE_CAT` maps `"discover"` → **`"scaffold"`** bucket (not `"status"`). Updated ROADMAP.md and TODO.md id:9cb1 lines with the resolved attribution and the exact post-run verification command. No post-fix pool-run data exists yet; id:9cb1 left open. No code changes to relay-econ.py (additive --phase view assessed as unnecessary given documented command suffices). suite 62/0. Friction: none — pure code-read + ledger update, correctly scoped.

## 2026-06-17 — executor (sonnet)

Worked id:c345 + id:040a — build the standing model-probe deliverable (sub-items of [HARD] id:dba3). Promoted both to ROADMAP.md as [ROUTINE] items (single-id-two-views; design fully settled by two meetings today). Wrote `tests/test_model_probe.sh` RED first (4 offline contracts: grade pass/fail, log-field validation in mock mode, battery-version propagation, dirty-probe-home refusal), then implemented `tools/model-probe.sh` (grade/battery-version offline subcommands; run mode with PROBE_MOCK_RESPONSE/PROBE_LOG_PATH/PROBE_HOME overrides; config-clean assertion; 15-item `tools/model-probe.battery.jsonl`; shape A probe-user invocation + latent shape B). Both boxes ticked; id:6ffe closed. Suite 64/0. Seeding (id:23e9) left open — gated on probe OS user (id:d0c0). Friction: none — spec was complete from the meetings.

## 2026-06-17 10:43 — reviewer (claude-opus-4-8)

Review of 18-commit window since relay-ckpt-20260616-2241 (today's /meeting design-ledger + relay feature commits). gaming-scan clean (0 flags); make test 64/0/0 (new test files green); contract pointer v4 current. Closed id:0b11 (annotated distributed-orchestrator SEED note with 2026-06-17 D1 ruling — ref-CAS rejected). D2 lease cluster (c144/148b/debf/179e) qualified as load-bearing-coupled → dedicated bundled handoff, not independent ROUTINE. Spec-drift fix: model-probe.sh+battery, settings-env.py added to CLAUDE.md tools/ row. routine_open=0.

## 2026-06-17 10:56 — reviewer (claude-opus-4-8)

Review of 2-commit window since relay-ckpt-20260617-1043 (a4cc91b archive chore + 1679960 /relay human triage write-back). Ledger/doc-only — no code or test changes; gaming-scan clean; make test 64/0/0. Confirmed last turn's id:10c0 ungating is sound (symlink-old→new + run-when-idle design coherent, acceptance concrete). routine_open=0. Repo now carries 2 open [HARD] hard-execute units ready for the default pool: id:401c (toml-set hardening) + id:10c0 (state-dir rename).

## 2026-06-17 11:08 — strong-execute (claude-opus-4-8)

strong-execute id:401c Run 13 strong-model audit (Opus apex, via /relay . --afk). Window = new code since last audit 2026-06-16-1247 (discover-sig.sh, relay-loop.js cache diff, model-probe.sh, settings-env.py, battery). 3 passes, CLEAN — 0 inline fixes, make test 64/0/0. 2 LOW findings tracked (id:4348 discover-sig upstream-no-fetch under-invalidation; id:b9b5 model-probe echo→printf), 3 accepted. Corrected last turn's id:401c mislabel (it's the recurring audit; toml-set was id:c8db done). id:401c recurring → stays open.

## 2026-06-17 11:56 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

Review clean: 2 append-only persona additions (Fenn, Lana) verified; suite 64/0 green, no gaming, 0 open ROUTINE

## 2026-06-17 13:26 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

id:10c0 done: rename relay state dirs fables-turn→relay (migrate-state-dirs.sh + 14 file path updates); make test green (65)

## 2026-06-17 15:45 — reviewer (claude-opus-4-8)

id:401c Run 14: adversarial audit of id:bbd2 migration — 4 defects fixed inline (HIGH jsonl trailing-newline fusion + 3 MED), test 9→12, suite 66/66; id:16e9 flaky test tracked

## 2026-06-18 10:48 — reviewer (claude-opus-4-8, relay-loop)

review since relay-ckpt-20260617-1545 (24 commits; ~4 feature, rest TODO/meeting ledger). Trust-but-verify clean: gaming-scan.sh empty (no deleted tests / added skips / removed asserts); full suite 71 pass / 0 fail / 0 expected-red. Verified genuinely green — id:11ad (gather-repo-state.sh one-call shard data layer: superset-sig invariant holds vs discover-sig.sh, no new unhashed signal; canary-validated; the two MODIFIED tests test_relay_discovery_guards/test_relay_tag_scheme are legitimate behavior-RELOCATION — fetch/ahead-behind + both-prefix tag asserts moved to gather-repo-state.sh, decision logic stays asserted on relay-loop.js, coverage preserved not weakened); id:0d31 (L1 relay-status-publish.sh thin-glue, hermetic test exercises sentinel-split + event-append + target-refusal + node --check); id:c855 (L2 push-seed discoverCache, drained-only gate openRoutine==0 && openHard==0, fail-open preserved, delete-on-not-drained under-invalidation guard); id:3ea3 (shard-canary with positive + negative-control stubs — proves the harness discriminates, not a rubber stamp). No gaming flags, no reopens. Contract pointer v4 == canonical v4 (no refresh). New Makefile-registered scripts (gather-repo-state.sh, relay-status-publish.sh) not user-facing → no README drift. Re-derived ROADMAP: 0 open [ROUTINE], 4 open [HARD] all GATED (id:dba3 sub-items+ToS+meeting; id:de4e DECISION GATE; id:401c recurring audit; id:3346 design-sim) → none EXECUTABLE-HARD. §5b reverse-handoff: 16 new TODO items this window are all design-ledger by design (id:0a1e/3947/888a/8602/d44d/8691/1968/e79b/2904/c0bc/6563 carry open design-qs → /meeting candidates; id:8a1a future-dated 2026-06-19; id:2895/e905 explicitly DEFERRED/gated; id:6ac6 owner-ratification of global CLAUDE.md, out-of-repo) — NONE qualify for mini-handoff into ROADMAP (would force design-judgment into the executor queue, §5b forbids). Pre-existing doc drift noted (non-blocking): relay docs (SKILL.md/conventions.md/human.md/evals.json) still cite ~/.config/fables-turn/relay.toml while all scripts use the live ~/.config/relay/relay.toml — scripts are correct, docs lag the rename; not introduced this window.

## 2026-06-18 11:01 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review since relay-ckpt-20260617-1545: id:11ad/0d31/c855/3ea3 verified genuinely green (gaming-scan clean, suite 71/0/0), ROADMAP re-derived (0 routine, 4 gated hard), no reopens

## 2026-06-18 14:12 — reviewer (claude-opus-4-8, relay-loop)

review since relay-ckpt-20260618-1101 (6 commits): docs/todo-only window — no code or test
changes. gaming-scan.sh clean; full suite 71 pass / 0 fail / 0 expected-red. §5b reverse-handoff:
6 new TODO items added by /meeting --cross + manual edits (f1a7 [MEETING] retrospective; 354f
/relay inject front-door; 6366 dirty-check artifact guard; 1ffc income non-binary schema; 7ace
gate-resolution detection; fc04 triage tail) — all carry genuine design ambiguity (explicit
"decide the schema / fix directions / needs a meeting"), so left as design-judgment/deferred TODO
items, NO mini-handoff promotion (none are execution-ready ROUTINE). Closed id:9c92 inline: relabeled
ROADMAP id:de4e heading "DECISION GATE → DEFERRED (decided 2026-06-17)" (the meeting was already held;
old heading contradicted the resolved block) and ticked the TODO line. ROADMAP open = 4 [HARD] (dba3,
de4e now DEFERRED-labeled, 401c, 3346), ZERO open [ROUTINE]. Contract pointer v4 == canonical v4 (no
drift). Orphan note honored: id:401c re-dispatch suppressed pending orphan reconciliation (id:1f53;
relay/orphan/relay-20260616-112222-* refs from dead run).

## 2026-06-18 14:21 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review 20260618-1412: docs-only window (6 commits), suite 71/0, closed id:9c92 de4e relabel, 0 open ROUTINE

## 2026-06-18 15:54 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review 20260618-1554: single commit 2cca947 (ledger-only; ROADMAP+TODO additions for quota bugs A/B). gaming-scan clean (no DELETED_TEST/ADDED_SKIP/REMOVED_ASSERT); suite 71/0 baseline. Both new items are reverse-handoff §5b reverse-qualifications: filed [ROUTINE] with RED-test acceptance but the spec tests were missing — completed the mini-handoff by writing tests/test_relay_quota_args.sh (# roadmap:b841) and tests/test_relay_stop_reason.sh (# roadmap:2425), both static-structural per test_relay_loop_structure.sh, both verified RED against current code and reported EXPECTED-RED by the suite (b841/2425 checkboxes unticked). Reused existing TODO ids (single-id-two-views D2; no mint). Verified both bug diagnoses against actual code: b841 envPairs forwards only flat keys (~L901–904, nested args.quotaThresholds never read); 2425 exit-1 culprit finder hardcodes pctRemaining<=10 (~L935) → below-90% decayed/overridden crossing falls through to :unknown. Contract pointer v4 == canonical v4 (no drift). No code/ARCHITECTURE/README touched in-window. routine_open=2.

## 2026-06-18 16:10 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review 20260618-1554: ledger-only window; mini-handoff RED specs for quota bugs id:b841,2425; gaming-scan clean; suite 71/0/2-red; routine_open=2

## 2026-06-18 16:25 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review 20260618-1616: id:612f shard no-hunting guard verified clean (gaming-scan clean, suite 71/0/2-red, JS valid); ledgers consistent; routine_open=2

## 2026-06-18 16:30 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review 20260618-1616: id:612f shard no-hunting guard verified clean (gaming-scan clean, suite 71/0/2-red, JS valid); ledgers consistent; routine_open=2
## 2026-06-18 — executor (claude-sonnet-4-6)

Worked id:b841 + id:2425 — two quota-gate bug fixes, both ROUTINE.

id:b841: relay-loop.js ignored a nested `args.quotaThresholds` map (envPairs only reads flat `RELAY_QUOTA_THRESHOLD_*` keys). Added a fold loop in the args-normalization block: each nested entry is promoted to the flat key unless the flat key is already set (flat wins). Documented the nested arg shape in SKILL.md config-knobs table. Test `test_relay_quota_args.sh` (roadmap:b841) now passes.

id:2425: the exit-1 stopReason culprit finder used `pctRemaining<=10` (the 90%-cap assumption), so a decayed/overridden threshold crossing below 90% fell through to `quota-exhausted:unknown`. Extended QUOTA_SCHEMA with a `crossedBucket` field; updated the quota-gate agent prompt to capture and return the bucket name from quota-stop.sh stderr. On exit-1 relay-loop now uses `v.crossedBucket` as primary attribution; the `<=10` finder demoted to a documented last-resort fallback. Test `test_relay_stop_reason.sh` (roadmap:2425) now passes.

Full suite: 73/0/0ER (was 71/0/2-EXPECTED-RED on arrival). Friction: none.

## 2026-06-18 16:35 — executor (sonnet, relay-loop)

executor: fix quota-gate bugs id:b841 (nested quotaThresholds silently dropped) + id:2425 (stopReason quota-exhausted:unknown on decayed-threshold crossings); suite 73/0/0ER

## 2026-06-18 16:56 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

deterministic clean-tree gate stops integrator data loss (id:aa93)

## 2026-06-18 17:20 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

id:aa93 already implemented+merged in prior turn; verified genuinely green (test_integrator_foreign_dirty.sh + full suite 74/0/0ER) — no new work, worktree clean

## 2026-06-18 19:00 — reviewer (claude-opus-4-8)

Review relay-ckpt-20260618-1720..HEAD (4 commits, docs-only: insights-triage meeting + TODO archive/cross-ledger sync). gaming-scan clean; tests 74/0/0; contract pointer v4 matches canonical; orphan-scan --cross-ledger clean (confirms the aa93/b841/2425/10c0 sync commits resolved drift). Step 5b: 6 new insights-meeting TODO items (f082/35fe/ef77/11c6/b67e/e79b) all correctly design-ledger — owner-gated curated rules or [HARD]/design-judgment, none execution-ready for a [ROUTINE] mini-handoff. routine_open=0, 4 open [HARD]. No reopens, no spec drift.

## 2026-06-19 16:21 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: docs-only window (2 persona appends Della+Reni) verified clean — 74/74 tests green, no gaming flags, no roadmap delta

## 2026-06-19 16:13 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review relay-ckpt-20260619-1621..HEAD (3 commits: quota-sampler tool 27f06ab + 2 TODO records). Test-integrity audit clean: gaming-scan.sh no output (no deleted tests / added skips / removed asserts); full suite 75/0/0; new tests/test_quota_sample.sh genuine (hermetic fixture, real assertions on sampler row capture + reporter jump-detection/reset-segmentation) and passes isolated. No formerly-red tests in window (new feature, not a red-spec close). Contract pointer v4 == canonical v4 (no drift). Step 5b reverse-handoff: id:d267 (quota sampler — already SHIPPED+tested+installed; "let it run, re-evaluate after ≥1 spike/week" → deferred/gated, skip) and id:3b18 (git-lock-push manifest silent-noop snag — multiple fix candidates a/b/c/d + open root-cause, relates id:aa93/3558 → design-judgment, leave as TODO /meeting candidate). Neither is a [ROUTINE] mini-handoff. Spec-drift fix: added quota-sample.* to CLAUDE.md tools/ row. No roadmap delta; routine_open=0, 4 open [HARD].

## 2026-06-19 17:15 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: quota-sampler window (id:d267) verified genuinely green — gaming-scan clean, 75/75, CLAUDE.md tools/ synced; routine_open=0

## 2026-06-19 16:13 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review relay-ckpt-20260619-1715..HEAD (1 commit: 3af0630 quota-sample QUOTA_COMMIT_INTERVAL default 3600->0, id:d267). Test-integrity audit clean: gaming-scan.sh no output; full suite 75/0/0; test_quota_sample.sh passes isolated and does not pin the old default (hermetic via QUOTA_NO_COMMIT). The 3-line change (one env default + its doc) is a faithful bugfix to the shipped sampler — the hourly gate was hiding commits behind sub-60-min timer firings. Spec-drift fix inline: the same commit left the WHY-block header (line 23) still saying "default hourly", contradicting the corrected env-doc; aligned it (commit de75d72). Step 5b: no new TODO/ROADMAP items in the window — nothing to qualify; id:d267 stays open by its own "re-evaluate after >=1 spike/week" gate. Contract pointer v4 == canonical v4. No reopens, no roadmap delta; routine_open=0, 4 open [HARD].

## 2026-06-19 18:07 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: quota-sample QUOTA_COMMIT_INTERVAL default flip (id:d267) verified genuinely green — gaming-scan clean, 75/75, stale header comment fixed inline; routine_open=0

## 2026-06-19 19:15 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review relay-ckpt-20260619-1807..HEAD (2 commits: 42ac0a3 strengthen TODO id:3801 with leAIrn2learn d61a 4th-handback evidence; 20ece4f preserve run-13 strong-model audit note from parked orphan, reconcile id:401c). Both pure docs/ledger — no code or test surface. Test-integrity audit clean: gaming-scan.sh no output (no DELETED_TEST/ADDED_SKIP/REMOVED_ASSERT); full suite 75/0/0. id:3801 re-write REUSES its own token (single-id-two-views honored — no duplicate minted); the salvaged meeting note is a net-add docs file. Step 5b: the only new open `- [ ]` line is the re-written id:3801 (existing design/[MEETING] candidate), so nothing unqualified to reverse-handoff. Contract pointer v4 == canonical v4 (no drift). No reopens, no gaming flags, no roadmap delta; routine_open=0, 4 open [HARD] (dba3/de4e/401c/3346).

## 2026-06-19 19:24 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review 20260619-1807..HEAD: 2 docs/ledger commits (id:3801 evidence, id:401c audit-note salvage) verified clean; gaming-scan no output, suite 75/0/0; routine_open=0

## 2026-06-19 19:53 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

Reviewed id:3801 (durable handback follow-up) — genuinely green: hermetic test w/ idempotency, suite 76/0, no gaming, routine_open=0

## 2026-06-19 20:08 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

relay(401c Run 15): strong-model audit 61020a0..HEAD — clean (L1/L2 skeleton + data-loss batch), 1 LOW flake tracked id:05e8, suite 76/0

## 2026-06-19 20:17 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

relay(401c Run 16): strong-model audit 36fb824..HEAD — clean (ledger-only window), suite 76/0

## 2026-06-19 20:26 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

relay(401c Run 17): strong-model audit 250613f..HEAD — clean ledger-only window, 1 coherence drift fixed inline (d5e0 stale open-HARD set), suite 76/0

## 2026-06-19 20:41 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

relay(401c Run 18): strong-model audit c4c0fdc..HEAD — clean ledger-only window, suite 76/0

## 2026-06-19 20:49 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

relay(401c Run 19): strong-model audit c4c0fdc..HEAD — clean ledger-only window, no inline fix, suite 76/0

## 2026-06-19 20:58 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

relay(401c Run 20): strong-model audit f24b99e..HEAD — clean ledger-only window, no inline fix, suite 76/0

## 2026-06-19 22:30 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

relay(review): relay-ckpt-20260619-2058..HEAD — 2 commits, both TODO.md-only (id:daf0 screenshots/README refresh, id:81cb statusline per-session ctx/cost/quota state file). gaming-scan clean (no code/test churn); suite 76/0. Contract pointer v4 == canonical v4, no drift. §5b reverse-handoff: both new open TODO items are design-judgment work (each carries open "Design qs (a)-(d)" — medium/path/schema decisions, no single observable done-state) → left as TODO /meeting candidates, NOT promoted to ROADMAP, ids preserved. ROADMAP open = 4 [HARD] (dba3/de4e/401c/3346), routine_open=0.

## 2026-06-19 22:35 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: ledger-only window (id:daf0/id:81cb TODO adds), gaming-scan clean, suite 76/0, contract v4 current, 0 routine open

## 2026-06-19 22:45 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

relay(401c Run 21): strong-model audit 39592e8..HEAD — clean ledger-only window, mirror-line drift fix, suite 76/0

## 2026-06-21 16:26 — reviewer (claude-opus-4-8, relay-loop)

review relay-ckpt-20260619-2245..HEAD: ledger-only window (2 commits, TODO.md only). gaming-scan clean (no DELETED_TEST/ADDED_SKIP/REMOVED_ASSERT); no formerly-red tests went green this window (nothing to resurrection-check). Suite 76/0 on clean run; test_relay_claim_liveness.sh (roadmap:7570, closed) flakes intermittently under the parallel suite run — passes 76/0 on re-run and in isolation — pre-existing test-isolation issue, NOT introduced by this window; logged a REVIEW_ME box. §5b: only genuinely-new item this window is id:ebd0 ([HIGH PRIORITY — SECURITY] global pre-push privacy gate); id:11c6 only appeared in the diff because the new `## privacy & security` section was inserted above it (pre-existing 2026-06-18 meeting item). Privacy sanitization (e886e6f) correctly moved leak specifics out of the public TODO into private memory — matches the no-leak-specifics-in-public-files directive. id:ebd0 qualified as a [HARD] design-judgment item (allowlist semantics + public/private-remote detection + override behavior are non-obvious design decisions) — kept in TODO as a /meeting candidate per §5b, NOT forced into ROADMAP, id reused (no duplicate minted). Contract pointer v4 == canonical v4 (no refresh). routine_open=0 (all 4 open ROADMAP items are [HARD — strong model]: dba3, de4e, 401c, 3346).

## 2026-06-21 16:39 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review relay-ckpt-20260619-2245..HEAD: clean ledger-only window (TODO privacy sanitization), gaming-scan clean, suite 76/0, qualified new id:ebd0 as HARD /meeting candidate, flagged flaky claim-liveness test

## 2026-06-21 16:59 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

relay(401c Run 22): strong-model audit b0b4076..HEAD — clean ledger-only window, mirror-line drift fix, suite 76/0

## 2026-06-21 17:16 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

relay(401c Run 23): strong-model audit c40b20e..HEAD — clean ledger-only window, mirror-line drift fix, suite 76/0

## 2026-06-21 17:45 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

relay(401c Run 24): strong-model audit b2db0bc..HEAD — clean ledger-only window, mirror-line drift fix, suite 76/0

## 2026-06-21 18:42 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review 20260621-1835: ledger-only window (1 commit, ROADMAP gate residue id:dba3); gaming-scan clean, suite 76/0, contract v4 current, cross-ledger coherent (0 ROUTINE / 3 HARD open)

## 2026-06-21 18:51 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

relay(401c Run 25): strong-model audit 99a1f2e..HEAD — clean ledger-only window, dba3 gate coherent, mirror-line drift fix, suite 76/0

## 2026-06-21 19:03 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

relay(401c Run 26): strong-model audit cb83ad1..HEAD — clean ledger-only window, mirror-line drift fix, suite 76/0

## 2026-06-21 19:12 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

relay(401c Run 27): strong-model audit 32f430d..HEAD — clean ledger-only window, mirror-line drift fix, suite 76/0

## 2026-06-21 19:22 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

relay(401c Run 28): strong-model audit 8b82136..HEAD — clean ledger-only window, mirror-line drift fix, suite 76/0

## 2026-06-21 19:32 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

relay(401c Run 29): strong-model audit 8016dfa..HEAD — clean ledger-only window, mirror-line drift fix, suite 76/0

## 2026-06-21 — executor (sonnet)

Worked id:4e14 — added `--all` to relay-reconcile.sh: enumerates relay.toml `own` repos via a copied `own_repos()` parser (same logic as gather-human-backlog.sh), lists each repo's `relay/orphan/*` branches with repo name on each line, surfaces unreadable/missing paths on stderr (never swallows), rejects `--all --integrate`/`--all --discard` with exit 2. SKILL.md reconcile section updated with canonical cross-repo sweep command and anti-hand-roll guard. Suite: 77/0/0.
Friction: none — test was a clean spec, `own_repos()` copy was straightforward.

## 2026-06-21 23:04 — reviewer (claude-opus-4-8)

Opus review (/relay review --all): 13-commit window. gaming-scan clean; suite 78p/0f/0xred. Genuine code verified: check-no-silent-swallow.sh (id:4347 mechanization guard) with an 86-line test asserting violation-count/annotation-clears/empty-reason-still-fails/enforce-baseline; relay-reconcile.sh --all (id:4e14) with a test asserting --all flag + no-silent-swallow on an unreadable repo. /meeting design-ledger (415b decomposition, Priya persona, 78ff explicit HARD-lane, d9b0/2840) + git-lock-push/quota-sample askpass+CF-browser hardening audited clean (docs/scripts, no test drift). Cross-ledger consistent.

## 2026-06-21 23:22 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

reviewer (claude-opus-4-8): verified 1 doc-only commit (d9b0 3rd-seam-gap), suite 78 green, no gaming, 2 open ROUTINE

## 2026-06-21 — executor (claude-sonnet-4-6)

Worked id:6b91 — hardened test_relay_claim_liveness.sh: identified the shared surface as CLAIM_TTL=1 causing a timing-sensitive window on a loaded machine between the heartbeat refresh and the subsequent acquire check (>1s elapsed → claim appeared stale again, steal succeeded). Fixed by changing CLAIM_TTL from 1 to 3600; all stale-state is forced via `touch -d '1 hour ago'` so natural aging never triggers. Documented the fix and the absence of a fixed /tmp lock. Verified 0 liveness-test flakes across 20 parallel full-suite runs.
Worked id:d9b0 — mechanized the TODO↔ROADMAP seam: (1) added `--promotion` (`-p`) mode to orphan-scan.sh that flags open TODO items with [ROUTINE]/[HARD — pool] lane tags absent from ROADMAP (pool-invisible un-promoted items); (2) extended `--cross-ledger` to honor `<!-- xledger-ok: <reason> -->` annotations on scope-split lines (intentional divergences no longer alarm-fatigue); (3) wrote tests/test_ledger_seam.sh (# roadmap:d9b0) covering all three acceptance criteria including derived-count assertion (fixture has no hand-maintained count line).
Friction: none — both items were well-specified with clear acceptance criteria; the cross-ledger xledger-ok needed care with bash associative arrays to track annotation per-id.

## 2026-06-21 23:49 — executor (sonnet, relay-loop)

Closed 2 open [ROUTINE] items: id:6b91 (hardened test_relay_claim_liveness.sh — CLAIM_TTL=1 timing race fixed with TTL=3600; verified 0 flakes across 20 parallel runs) and id:d9b0 (orphan-scan.sh --promotion + xledger-ok cross-ledger suppression + test_ledger_seam.sh; suite 78→79p/0f/0xred)

## 2026-06-22 01:12 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

relay(hard): id:78ff explicit [HARD] lane tags (pool/meeting/hands) + bucketed human-backlog collector with loud untagged-reject; suite 80/0

## 2026-06-22 01:43 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

relay(401c Run 30): strong-model audit 422e95d..HEAD — CLEAN substantive code window (id:78ff lanes / 4347 swallow-ban / d9b0 seam / git-lock-push auth), 1 mirror-drift fix, suite 80/0

## 2026-06-22 02:08 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

relay(401c Run 31): strong-model audit 00cfff7..HEAD — LEDGER-ONLY, CLEAN by vacuity, no drift, suite 80/0

## 2026-06-22 02:17 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

relay(401c Run 32): strong-model audit d55fd25..HEAD — LEDGER-ONLY, CLEAN by vacuity, no drift, suite 80/0

## 2026-06-22 06:54 — reconcile (human)

reconcile integrate: relay(401c Run 33): strong-model audit b315aed..HEAD — LEDGER-ONLY, CLEAN by vacuity, no drift, suite 80/0

## 2026-06-22 07:12 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

strong-model review relay-ckpt-20260622-0654..HEAD — LEDGER-ONLY, CLEAN by vacuity (no code/test changes), single-id-two-views verified (id:7809/98f0 reused), suite 80/0, no drift

## 2026-06-22 07:22 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

relay(401c Run 34): strong-model audit 62b58fa..HEAD — LEDGER-ONLY, CLEAN by vacuity, design-coherence on new HARD 7809/98f0, 2 mirror-drifts fixed, suite 80/0

## 2026-06-22 07:30 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

relay(401c Run 35): strong-model audit 40bc011..HEAD — LEDGER-ONLY, CLEAN by vacuity, no drift, 1 mirror-line refresh, suite 80/0

## 2026-06-22 07:05 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

Review relay-ckpt-20260622-0730..HEAD (1 commit c54c96e). LEDGER-ONLY, CLEAN by vacuity: single one-line TODO addition (id:f576 — Claude Code TUI ghost workflow-progress/statusline fragments after exiting /workflows; external/harness meta-issue, not repo code). gaming-scan clean (no DELETED_TEST/ADDED_SKIP/REMOVED_ASSERT — no test files touched). Step 5b: id:f576 is design-judgment/deferred (external upstream bug; #1 action = upgrade Claude Code 2.1.177→latest + retest, a human action) → correctly stays a TODO ledger item, NOT promoted to ROADMAP; token unique (not a duplicate). Contract pointer v4 == canonical v4, no drift. No open [ROUTINE] items; open [HARD] all gated (7809/98f0 meeting, dba3 human, de4e/401c/3346 deferred/pool/meeting). Suite 80/0/0.

## 2026-06-22 07:37 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

relay review relay-ckpt-20260622-0730..HEAD — LEDGER-ONLY, CLEAN by vacuity, id:f576 meta-issue ledger-only, no drift, suite 80/0

## 2026-06-22 07:49 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

relay(401c Run 36): strong-model audit 69c0bc5..HEAD — LEDGER-ONLY, CLEAN by vacuity, design-coherence on new id:f576 TUI meta-issue, 1 mirror-line refresh, suite 80/0

## 2026-06-22 09:28 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

Review relay-ckpt-20260622-0749..HEAD (2 commits: 1b0ce42 id:93cc, 8762cdb id:6b67). LEDGER-ONLY, CLEAN by vacuity — only TODO.md + ROADMAP.md ledger edits, zero code/test changes. gaming-scan clean (no DELETED_TEST/ADDED_SKIP/REMOVED_ASSERT — no test files touched). Step 5b reverse-handoff: id:93cc is the design-ledger root item (executor "Prompt is too long" overflows on large ROADMAPs — fix-directions a/c stay TODO design-judgment, not yet executor-ready); fix-direction (b) was promoted by the strong turn itself as id:6b67 [ROUTINE] "Relay ROADMAP archiver" — already fully qualified (acceptance + done-check + spec test tests/test_roadmap_archive.sh described), single-id-two-views cross-ref present in TODO. Both tokens minted by append.sh (not invented), no duplicate-id. roadmap-archive.sh + its test correctly absent (open [ ] item = work-to-do). Contract pointer v4 == canonical v4, no drift. routine_open=1 (id:6b67). Suite 80/0/0.

## 2026-06-22 09:37 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

relay review relay-ckpt-20260622-0749..HEAD — LEDGER-ONLY, CLEAN by vacuity, id:6b67 [ROUTINE] qualified, no drift, suite 80/0, routine_open=1
## 2026-06-22 — executor (claude-sonnet-4-6)

Worked id:6b67 — shipped `relay/scripts/roadmap-archive.sh`: moves done `[x]` top-level items (plus all indented continuation lines as one block) from ROADMAP.md into ROADMAP.archive.md, with the conservative prior-commit/≥30-day-aged gate, flock guard, idempotency, and no section pruning. Added `tests/test_roadmap_archive.sh` (9 cases covering multi-line capture, open-item + header preservation, prior-commit gate positive/negative, aged-date gate positive/negative, idempotency, token preservation, empty-header retention). Registered in Makefile relay_FILES/_EXEC/_ALLOW. Full suite: 81 passed, 0 failed.
Friction: none.

## 2026-06-22 09:42 — executor (sonnet, relay-loop)

id:6b67 [ROUTINE] — shipped relay/scripts/roadmap-archive.sh + tests/test_roadmap_archive.sh (9 cases), Makefile registration; suite 81/0

## 2026-06-22 09:53 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

relay(401c Run 37): strong-model audit b93f024..HEAD — SUBSTANTIVE CODE (roadmap-archive.sh id:6b67), CLEAN all 3 passes, 1 LOW accepted, 1 mirror refresh, suite 81/0

## 2026-06-22 10:04 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

relay(401c Run 38): strong-model audit 8258aa3..HEAD — LEDGER-ONLY, CLEAN by vacuity, no drift, mirror→Run38, suite 81/0

## 2026-06-22 10:14 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

relay(401c Run 39): strong-model audit 0174a69..HEAD — LEDGER-ONLY, CLEAN by vacuity, no drift, mirror->Run39, suite 81/0

## 2026-06-22 16:30 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

relay review relay-ckpt-20260622-1014..HEAD — strong-model/meeting window CLEAN (gaming-scan clean, gather-trim id:93cc genuine red→green, no drift); §5b mini-handoff red spec for id:bde8; suite 81/0/1-expected-red

## 2026-06-22 17:10 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review relay-ckpt-20260622-1630..6851d4e CLEAN: suite 81/0, gaming-scan clean, xledger exit 0, recorded id:7d1e closed; routine_open=1
## 2026-06-22 — executor (claude-sonnet-4-6)

Worked id:bde8 — corrected the misleading loop-hint.sh "unattended resilience" nudge and SKILL.md step 0a. The pre-fix TIP promised "/loop gives outage/session-kill resilience" and "a tick missed during an outage is recovered by the next one" — both false when the session itself is killed. Fixed loop-hint.sh to state: /loop is useful for relay's own early-exit (quota/seatbelt) within a live session; if the session is killed, /loop dies with it. Updated SKILL.md step 0a + step 4 references with the corrected scope and pointer to id:98f0 for watchdog concerns. ROADMAP:bde8 ticked; test_loop_hint_resilience_wording.sh green; full suite 82/0/0.
Friction: none — test was already written and precisely specified the two correctness properties needed; straightforward wording fix.

## 2026-06-22 17:15 — executor (sonnet, relay-loop)

fix(relay): correct loop-hint scope — /loop dies with the session (id:bde8); full suite 82/0/0

## 2026-06-22 17:31 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

relay(401c Run 40): strong-model audit 3600642..HEAD — CODE window, fixed id:93cc trimmer fail-closed→fail-open + regression guard + 2 ledger coherence drifts; suite 82/0

## 2026-06-22 17:57 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review e06088f (ledger-only Agent-SDK billing-deferral note): CLEAN by vacuity, gaming-scan 0, suite 82/0, id:00a5 new token valid, fixed cross-ledger bde8 TODO[ ]/ROADMAP[x] divergence, routine_open=0

## 2026-06-22 18:18 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

relay(401c Run 41): strong-model audit f3c26f8..HEAD — LEDGER-ONLY, CLEAN by vacuity, gaming-scan 0, suite 82/0, 1 mirror-line drift fixed, cross-ledger coherent

## 2026-06-22 16:01 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

relay(401c Run 42): strong-model audit b65ba59..HEAD — LEDGER-ONLY (sole first-seen = Run 41 checkpoint paragraph), CLEAN by vacuity, gaming-scan 0, suite 82/0, 1 mirror-line drift fixed (Run 41→42), no count drift, cross-ledger coherent

## 2026-06-22 18:27 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

relay(401c Run 42): strong-model audit b65ba59..HEAD — LEDGER-ONLY, CLEAN by vacuity, no drift, mirror->Run42, suite 82/0

## 2026-06-22 18:35 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

relay(401c Run 43): strong-model audit a56bed7..HEAD — LEDGER-ONLY, CLEAN by vacuity, gaming-scan 0, suite 82/0, mirror->Run43, cross-ledger coherent

## 2026-06-22 20:27 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review 6273a33: id:e107 @manual/human-only [ROUTINE] execute-verdict guard verified genuinely green — gaming-scan clean, suite 82/0, no drift, 0 open ROUTINE

## 2026-06-22 21:37 — strong-execute (claude-opus-4-8, id:bae5)

uv.lock-only relay exemption (id:bae5) + intensity-profiling TODO (id:c7b6). Authored+verified this Opus turn: gather emits lock_only_unaudited/dirty_lock_only, discovery exempts them; test suite 82/0 green.

## 2026-06-22 20:20 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review relay-ckpt-20260622-2137..HEAD (2 commits): CLEAN by vacuity — diff window is entirely chore-level: TODO archival of 3 already-`[x]` items (d9b0, bde8, bae5) into TODO.archive.md, and concurrent autonomous-pool persona appends (Theo, Vox) into the merge=union meeting/personas.md. No code, no test files touched. gaming-scan.sh clean (0 DELETED_TEST/ADDED_SKIP/REMOVED_ASSERT); full suite 82/0/0. Cross-ledger orphan-scan clean — archived d9b0/bde8 ROADMAP twins already `[x]`, no checkbox divergence to tick. Relay contract pointer in CLAUDE.md is v4 = canonical (no drift). Reverse-handoff (§5b) vacuous: no new open `- [ ]` items added this window. Personas each appear once, format-correct. routine_open=0.

## 2026-06-22 21:45 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review (claude-opus-4-8, fable-standin, relay-loop): relay-ckpt-20260622-2137..HEAD CLEAN by vacuity — chore-only window (TODO archival + persona appends), gaming-scan 0, suite 82/0, cross-ledger consistent, contract pointer v4

## 2026-06-22 20:20 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review relay-ckpt-20260622-2145..HEAD (1 commit, 797d221): meeting(af04) commit — meeting note `2026-06-22-2139-meeting-worktree-writeback.md` + 2 new TODO items (id:2c42, id:6f61). NO code/test files touched; gaming-scan.sh clean (0 DELETED_TEST/ADDED_SKIP/REMOVED_ASSERT); full suite 82/0. ids genuine (each appears once in TODO, none in ROADMAP/archive — no duplicates), cross-ledger orphan-scan clean. Contract pointer CLAUDE.md v4 = canonical (no drift). Reverse-handoff (§5b): **id:2c42** is execution-ready (concrete `meeting/SKILL.md` step-2a breadcrumb+replay change with an observable done-state + test contract) → mini-handoff: promoted to ROADMAP as `[ROUTINE]` reusing its id, wrote red spec `tests/test_meeting_deferred_writeback.sh` (`# roadmap:2c42`, EXPECTED-RED). **id:6f61** is explicitly deferred/folded into the lock-hygiene umbrella id:d2cd (meeting D3b "Out of scope: building it this session") → SKIPPED per §5b (deferred/gated). routine_open=1.

## 2026-06-22 22:07 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review relay-ckpt-20260622-2145..HEAD (meeting af04, ledger-only): gaming-scan 0, suite 82/0, mini-handoff id:2c42→ROADMAP [ROUTINE]+red spec, id:6f61 skipped (folded into d2cd), routine_open=1

## 2026-06-22 — executor (claude-sonnet-4-6)

Worked id:2c42 — implemented `/meeting` deferred ledger write-back (breadcrumb + replay-on-next-invocation + log). Extended `meeting/SKILL.md` step 2a: on a final deferral, persists a generic `{target_file, helper, payload}` JSON to `<root>/.meeting-deferred-writeback.json` + appends to `~/.claude/logs/meeting-deferred-writeback.log`. Added a step 2a-replay setup-phase check in `/meeting` that applies pending payloads under a fresh claim, clears the drop file, or re-defers if pool still holds the claim. Added a matching Step 0 replay check in `todo-update/SKILL.md`. Gitignored the drop file. Also ticked TODO/ROADMAP id:2c42 (single-id-two-views) and added af04 cross-link on id:3558 (worktree-per-meeting rejected, id:3558 orthogonal). All 83 tests pass.
Friction: none — worktree was behind main (reviewer mini-handoff added the red spec); merged before starting.

## 2026-06-22 22:15 — executor (sonnet, relay-loop)

executor: implement id:2c42 — /meeting deferred ledger write-back (breadcrumb + replay + log); 83/0 tests

## 2026-06-23 07:33 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

relay(401c Run 44): strong-model audit c66c6f4..HEAD — REAL CODE window (bae5/e107/2c42), CLEAN, gaming-scan 0, suite 83/0, mirror->Run44

## 2026-06-23 — executor (sonnet)

Worked id:1d64 — margin-aware quota-stop staleness. Replaced the unconditional `exit 2` in the stale-path post-refresh-failure branch with a per-bucket margin check: if every tier-relevant bucket's last-known util < (bucket_threshold×100 − MARGIN), proceed on the stale-but-safe cache (fall through to check_key); otherwise keep exit 2. MARGIN=RELAY_QUOTA_STALE_MARGIN, default 30. Moved decay_threshold/bucket_threshold definitions before the stale block (required so they're callable from the margin check — no behaviour change to those functions). Updated test_quota_stop.sh's stale+no-creds case (util=50% is now stale-but-safe under margin=30, so expected exit changed 2→0). Suite: 84 passed, 0 failed, 3 expected-red.
Friction: none.

## 2026-06-23 08:25 — executor (sonnet, id:1d64) integrated by opus

id:1d64 margin-aware quota-stop staleness — proceed on stale-but-safe cache (executor sonnet, integrated)

## 2026-06-23 — executor (sonnet)

Worked id:69ef — added `references/hard-lanes.md` to the `relay_FILES` manifest in the Makefile so `make install-relay` symlinks it. Test `tests/test_relay_refs_install_complete.sh` turned GREEN; full suite 85 passed / 0 failed / 2 expected-red.
Friction: none.

## 2026-06-23 08:42 — executor (sonnet, relay-loop)

feat(relay): id:69ef — add references/hard-lanes.md to relay_FILES install manifest; 85/0 tests

## 2026-06-23 08:45 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: gaming-scan clean, 84/0 tests; reconciled id:1d64 TODO twin (D2 cross-ledger close); 3 new meeting items well-qualified

## 2026-06-23 08:48 — executor (sonnet, relay-loop)

feat(relay-loop): sync hard-lane token to canonical [HARD — pool] (id:3c0f) — 5 sites updated in relay-loop.js; tests/test_relay_loop_hard_token.sh GREEN; full suite 86 passed / 0 failed

## 2026-06-23 — executor (sonnet, relay-loop)

Worked id:000d — deterministic is_finished guard. Added `is_finished` bool to gather-repo-state.sh (arg 16 through the emit() positional→env→JSON path): true when roadmap present/non-empty + 0 open "- [ ]" items + commits_since_ckpt empty + clean tree (dirty_lock_only exempt, id:bae5). Added JS-side demote guard in relay-loop.js: after all shard results are merged, units with is_finished=true and verdict in {execute,hard,handoff} are demoted to surfaced with the canonical "finished repo … anti-false-handoff guard id:000d" reason; review unaffected; injected units exempt. Shard prompt updated with IS-FINISHED DEMOTE GUARD instruction. Structural assertions added to test_relay_loop_structure.sh. test_gather_is_finished.sh: 5/5 green. Full suite: 87 passed, 0 failed, 1 expected-red (id:09a3, unrelated, still open).
Friction: none.

## 2026-06-23 09:12 — executor (sonnet, relay-loop)

feat(relay): id:000d — deterministic is_finished guard (anti-false-handoff); 87/0 tests

## 2026-06-23 09:23 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: audited 1 commit (id:0907 TODO design-ledger add); suite 87/0 + 1 expected-red; no gaming, no drift; routine_open=0

## 2026-06-23 09:44 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

relay(401c Run 45): strong-model audit 0e60f1f..HEAD REAL CODE (000d/1d64/3c0f/69ef) — 1 HIGH inline fix (dead is_finished guard), 87/0 +1 expected-red

## 2026-06-23 10:19 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

id:401c Run 46 strong-model audit (LEDGER-ONLY/clean-by-vacuity); 1 inline coherence fix (xledger-ok on id:3c0f/69ef scope-split); suite 87/0 +1 expected-red

## 2026-06-23 12:00 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

Run 47 review: audit relay-ckpt-20260623-1019..HEAD clean LEDGER-ONLY (gaming-scan vacuous, 87/0 +2 expected-red); reverse-handoff promoted id:ad74 INTENSIVE-emit fix to ROADMAP [ROUTINE] + red spec

## 2026-06-23 — executor (claude-sonnet-4-6)

Worked id:ad74 — implemented the INTENSIVE-emit fix (two-part symmetric PROMOTE counterpart to id:000d DEMOTE guard). (1) `gather-repo-state.sh`: added `top_intensive` field (grep for the resource of the top open `[INTENSIVE — <res>]` item, "" when none), passed through the 17th positional `emit()` arg and emitted in the JSON output. (2) `relay-loop.js` DISCOVER_SCHEMA: added `top_intensive: { type: 'string' }` unit property. (3) shard prompt: added INTENSIVE-EMIT-GUARD rule (id:ad74 marker) — instructs the shard that an open [INTENSIVE] item is always work/never idle. (4) per-repo fields section: added `top_intensive` copy instruction. (5) JS-side INTENSIVE promote backstop block (after id:000d demote guard): promotes any repo that is idle/skipped with top_intensive set to a `units` entry with `intensive` set, self-correcting a shard that ignores the instruction.
Friction: none — well-specified item with clear symmetric pattern from id:000d. Suite 88/0 +1 expected-red.

## 2026-06-23 12:20 — executor (sonnet, relay-loop)

feat(relay): id:ad74 INTENSIVE-emit fix — shard + JS backstop so open [INTENSIVE] items never classify idle

## 2026-06-23 15:37 — reconcile (human)

reconcile integrate: relay(hard): implement id:09a3 — roadmap-lint.sh grammar validator

## 2026-06-23 17:41 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

401c Run 48 strong-model audit (80a8441..HEAD REAL CODE): 1 HIGH inline fix — id:ad74 JS INTENSIVE promote backstop was a no-op (idle units never reached dispatch); flipped idle→execute + non-vacuous guards; suite 89/0/0

## 2026-06-23 17:51 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

401c Run 49 strong-model audit (7dfe7e0..HEAD): LEDGER-ONLY clean by vacuity — no code/security/coherence findings; roadmap-lint 0, gaming-scan 0, suite 89/0/0

## 2026-06-23 18:01 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

401c Run 50 strong-model audit (12b151e..HEAD): LEDGER-ONLY clean by vacuity — no code/security/coherence findings; orphan-scan/roadmap-lint/gaming-scan 0, suite 89/0/0

## 2026-06-23 18:13 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

401c Run 51 strong-model audit (b46be9a..HEAD): LEDGER-ONLY clean by vacuity — no code/security/coherence findings; orphan-scan/roadmap-lint/gaming-scan 0, suite 89/0/0

## 2026-06-23 18:23 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

401c Run 52 strong-model audit (9dfce93..HEAD): LEDGER-ONLY clean by vacuity — no code/security/coherence findings; orphan-scan/roadmap-lint/gaming-scan 0, suite 89/0/0

## 2026-06-23 18:38 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

401c Run 53 strong-model audit (8052b4f..HEAD): LEDGER-ONLY clean — no code/security findings; coherence pass on new TODO id:9000 sound; orphan-scan/roadmap-lint/gaming-scan 0, suite 89/0/0

## 2026-06-23 18:51 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review 2026-06-23: doc-only diff (id:9000 urgency-reframe note); gaming-scan clean, suite 89/0, roadmap lint-clean, cross-ledger consistent, 0 open ROUTINE

## 2026-06-23 19:13 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

401c Run 54 strong-model audit (e905c84..HEAD): LEDGER-ONLY clean — no code/security findings; id:9000 urgency-reframe coherence-sound; orphan-scan/roadmap-lint/gaming-scan 0, suite 89/0/0

## 2026-06-23 19:40 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: audited 1 doc-only commit (8679992, new TODO id:74c7/d23f) — clean, suite 89/0, lint+cross-ledger clean, contract v4 current; no ROUTINE work

## 2026-06-23 20:01 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

401c Run 55 strong-model audit (2cd8d6e..HEAD): LEDGER-ONLY clean — no code/security findings; new design items id:74c7/d23f coherence-sound; orphan-scan/roadmap-lint/gaming-scan 0, suite 89/0/0

## 2026-06-23 20:11 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

401c Run 56 strong-model audit (578c854..HEAD): LEDGER-ONLY clean by vacuity — no code/security/coherence findings; orphan-scan/roadmap-lint/gaming-scan 0, suite 89/0/0

## 2026-06-23 20:21 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

401c Run 57 strong-model audit (9782379..HEAD): LEDGER-ONLY clean by vacuity — no code/security/coherence findings; orphan-scan/roadmap-lint/gaming-scan 0, suite 89/0/0

## 2026-06-23 20:29 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

401c Run 58 strong-model audit (9b2abd7..HEAD): LEDGER-ONLY clean by vacuity — no code/security/coherence findings; orphan-scan/roadmap-lint/gaming-scan 0, suite 89/0/0

## 2026-06-23 20:38 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

401c Run 59 strong-model audit (c8d4469..HEAD): LEDGER-ONLY clean by vacuity — no code/security/coherence findings; orphan-scan/roadmap-lint/gaming-scan 0, suite 89/0/0

## 2026-06-23 20:47 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

401c Run 60 strong-model audit (73e4903..daf5694): LEDGER-ONLY clean by vacuity — no code/security/coherence findings; orphan-scan/roadmap-lint/gaming-scan 0, suite 89/0/0

## 2026-06-23 20:56 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

401c Run 61 strong-model audit (9da3a6f..HEAD): LEDGER-ONLY clean by vacuity — no code/security/coherence findings; orphan-scan/roadmap-lint/gaming-scan 0, suite 89/0/0

## 2026-06-23 21:04 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

401c Run 62 strong-model audit (91d639a..HEAD): LEDGER-ONLY clean by vacuity — no code/security/coherence findings; orphan-scan/roadmap-lint/gaming-scan 0, suite 89/0/0

## 2026-06-23 21:13 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

401c Run 63 strong-model audit (a360ac6..HEAD): LEDGER-ONLY clean by vacuity — no code/security/coherence findings; orphan-scan/roadmap-lint/gaming-scan 0, suite 89/0/0

## 2026-06-23 21:23 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

401c Run 64 strong-model audit (c8127e0..HEAD): LEDGER-ONLY clean by vacuity — no code/security/coherence findings; orphan-scan/roadmap-lint/gaming-scan 0, suite 89/0/0

## 2026-06-23 21:32 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

401c Run 65 strong-model audit (69dd4d8..HEAD): LEDGER-ONLY clean by vacuity — no code/security/coherence findings; orphan-scan/roadmap-lint/gaming-scan 0, suite 89/0/0

## 2026-06-23 21:40 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

401c Run 66 strong-model audit (9330f72..HEAD): LEDGER-ONLY clean by vacuity — no code/security/coherence findings; orphan-scan/roadmap-lint/gaming-scan 0, suite 89/0/0

## 2026-06-23 21:47 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

401c Run 67 strong-model audit (a689119..HEAD): LEDGER-ONLY clean by vacuity — no code/security/coherence findings; orphan-scan/roadmap-lint/gaming-scan 0, suite 89/0/0

## 2026-06-24 11:52 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: verified 4 relay self-items genuinely green (d530/052c/a707/365b), gaming-scan clean, suite 93/0/0, no drift; 0 open ROUTINE

## 2026-06-24 12:44 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: verified id:c012 (/relay graceful stop) genuinely green — real red→green spec, clean gaming-scan, suite 94/0, ledgers consistent; 0 open ROUTINE

## 2026-06-24 — executor (id:9973, deterministic HARD-pool demote-guard)

execute: shipped the deterministic demote-guard for a `hard` verdict on a repo with NO open `[HARD — pool]` item (the 2026-06-24 false-dispatch of `[HARD — decision gate]`-only repos that burned Opus on pre-start size-outs). gather-repo-state.sh now emits a new number field `open_hard_pool` (count of open `- [ ]` items tagged exactly `[HARD — pool]`, excluding a vacuous `<!-- relay:recurring-audit -->` item via the existing id:365b `substantive_unaudited` logic) through the same positional→env→JSON emit path as is_finished/top_intensive. relay-loop.js gained a JS-side demote block right after the id:000d finished-demote: a non-injected `hard` unit with `open_hard_pool == 0` is removed from `units` and pushed to `surfaced` with the id:2d20-style gated reason — DEMOTE-ONLY, injected-exempt, review/execute/handoff untouched, plus the DISCOVER_SCHEMA field + shard copy-verbatim instruction so the value actually reaches the unit (mirrors the id:401c is_finished fix). Pure logic, no Date/process/require/fs/Math.random — `node --check` and `tests/test_relay_no_date_api.sh` stay green. New hermetic static-structural spec `tests/test_relay_demote_guard_hard_pool.sh` (`# roadmap:9973`) covers both layers (decision-gate+hands→0, one pool→1, done [x]→0, vacuous recurring-audit→0; JS demote-guard wiring). Promoted id:9973 to ROADMAP `[ROUTINE]` reusing the same id, ticked `[x]`. Full suite: 95 passed / 0 failed / 0 expected-red.

## 2026-06-24 17:25 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: verified c012/9973/9bec closures genuine, suite 96/0/0, gaming/lint/cross-ledger clean; 3 open [ROUTINE]

## 2026-06-24 — executor (claude-sonnet-4-6)

Worked id:9221, id:3eb5, id:a883 — all 3 open [ROUTINE] items:
  id:9221: Fixed orphan-scan.sh --cross-ledger false-positive (archived/recycled id
    overwriting active TODO.md state). Applied first-wins semantics when building
    todo_state and roadmap_state maps — active file (TODO.md, processed first via
    grep -h) wins over archive. New hermetic test covers both the reused-archive scenario
    (a) and the prose-on-sibling-lines scenario (b), plus verifies genuine drift still caught.
  id:3eb5: relay-doctor front-door wiring — added `/relay health` to SKILL.md invocation
    block + a `## health arg` section documenting relay-doctor.sh; added step 4b to
    relay/references/review.md routing findings to REVIEW_ME (report-only, never a block).
  id:a883: relay-doctor --strict + quota-config sanity — added --strict flag (exits
    nonzero when issues_total>0); new quota_config_check() validates RELAY_QUOTA_DECAY_7D
    direction (START<END) and RELAY_QUOTA_THRESHOLD bounds; removed quota-config from the
    "not-yet-wired" list (now wired). Full suite: 99 passed / 0 failed / 0 expected-red.
Friction: none — all 3 items were cleanly bounded and testable within one session.

## 2026-06-24 17:42 — executor (sonnet, relay-loop)

executor: worked all 3 open [ROUTINE] items (id:9221, id:3eb5, id:a883); 99 tests pass

## 2026-06-24 17:46 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

id:71f2: lexer-aware workflow template-literal lint (lint-workflow-templates.mjs) + test, full suite green

## 2026-06-24 18:35 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: verified id:71f2 twin-tick genuine; closed 3 cross-ledger drifts (3eb5/a883/9221) by ticking TODO twins; suite 100/0, lint clean

## 2026-06-24 20:58 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: verified id:2147 [HARD — pool] gate-detection-atomic-commit spec + TODO twin genuine (ledger-only, reused token); gaming-scan/roadmap-lint/relay-doctor clean; suite 100/0

## 2026-06-24 21:20 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: id:a643 [HARD — pool] standalone-GPU resource-claim ledger addition verified clean (no code/test changes); suite 100 green, no flags

## 2026-06-24 21:52 — reviewer (claude-opus-4-8)

Recover stranded id:2147 implementation (commit-ledger.sh + review/human §5 wiring + test) that the pool's hard child built but the dirty-guard deferred at integration (my concurrent id:a643 edit made main dirty). Verified 101/101 green. Superseded gate-detection decomposition (fce2/6910/1339) stashed, not landed.

## 2026-06-25 11:23 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: empty diff window since relay-ckpt-20260624-2152 (only the checkpoint RELAY_LOG paragraph); 101/101 green, roadmap-lint+relay-doctor clean, no flags, 0 open ROUTINE

## 2026-06-25 11:35 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

id:a643 — standalone intensive jobs acquire a relay resource:<name> claim (acquire-resource.sh + resource-claims.md vocab + collision test); suite green 102

## 2026-06-25 14:36 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: id:1b11 PID-anchored claim liveness verified genuinely green (103-test suite, gaming-scan/roadmap-lint/relay-doctor clean); no drift, no reopens, routine_open=0

## 2026-06-25 15:24 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: id:20bd doc-only commit verified (--quota-7d/--quota-5h knobs accurately ride b841 plumbing); suite 103/0, roadmap-lint + relay-doctor clean, 0 open ROUTINE

## 2026-06-26 10:13 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: 13 commits since 1524 verified clean (id:2dea/3441/c095 green, gaming-scan clean, suite 107 green); ledgers conformant, id:5c00 open

## 2026-06-26 — executor (sonnet)

Worked id:5c00 — added a quota PRE-GATE at the top of `runRound()` in `relay-loop.js`, before the discover-prelude and DISCOVER_SHARDS fan-out. The gate calls the existing `quotaGate('sonnet')` and returns `{ actionable: 0, produced: 0 }` early if quota is at threshold, preventing N shard agents from spending tokens on a round that will immediately stop. Extended `tests/test_relay_loop_structure.sh` with ordering assertions (python3 confirms `id:5c00` marker precedes `'discover-prelude'` inside `runRound()`). Suite 107/0 green.
Friction: none — straightforward; the pre-existing `quotaGate()` function reused directly.

## 2026-06-26 10:32 — executor (sonnet, relay-loop)

feat(relay): id:5c00 quota PRE-GATE before discovery fan-out — quotaGate('sonnet') at top of runRound() prevents N shard agents wasting tokens on a quota-stop round; test_relay_loop_structure.sh extended with ordering assertions; suite 107/0 green

## 2026-06-26 10:48 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

id:401c strong-model audit Run 68 — first non-ledger window since Run 48 (3-day engine batch, ~4091 lines/35 files) clean code+security; fixed id:5c00 TODO/ROADMAP cross-ledger drift inline

## 2026-06-26 11:58 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: diff window = 2 user TODO-bookkeeping commits (archive id:5c00, add investigation id:ad9d); no code/tests, gaming-scan + roadmap-lint + relay-doctor clean, 0 open ROUTINE

## 2026-06-29 10:44 — reviewer (claude-opus-4-8)

review: clean (id:43b9 host-gate verified; suite 108/0 green; pruned 9 resolved REVIEW_ME; surfaced 2 inbox dead-letters)

## 2026-06-29 11:49 — reviewer (claude-opus-4-8)

handoff C3: red spec id:678e slice-2 scan-routed --apply (5 cases, EXPECTED-RED)

## 2026-06-29 — executor (sonnet)

Worked id:678e — implemented `scan-routed.sh --apply` (slice-2): added `--apply` and `--dry-run` flags; a `resolve_target()` helper that resolves `[target]` by relay.toml first (incl. `# path:` polyrepo override) then by `$SRC_DIR/<name>` existence on disk (so an own repo without a relay.toml block still resolves); idempotency guard (grep target TODO for `routed:XXXX` before writing); `claim.sh peek` skip for live pool worktrees; flock'd write via `md-merge.py`; commit via `commit-ledger.sh`; best-effort `append.sh inbox-done`; `--dry-run` prints the inspectable plan without writing. All 5 red-spec cases (polyrepo→central TODO, non-relay-own→its TODO, nonexistent→UNRESOLVED, idempotent re-run=no-op, dry-run=no write+diff) now green. Full suite 109/0. Friction: none — spec was precise and self-contained; the existing slice-1 code was a clean base for the extension.

## 2026-06-29 12:00 — executor (claude-sonnet-4-6)

executor: id:678e slice-2 scan-routed.sh --apply implemented (5 cases green, suite 109/0); ticked pending review

## 2026-06-29 12:04 — reviewer (claude-opus-4-8)

review: id:678e slice-2 VERIFIED honest (gaming-clean, red spec byte-identical, suite 109/0); item closed, routine_open=0

## 2026-06-29 13:09 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: verified outage-resilience cluster green (e149/7809/98f0/0994); suite 112/0, gaming-scan clean, 0 open ROUTINE

## 2026-06-29 13:40 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: docs-only deletion verified clean (gaming-scan clean, 112 tests green, lint+doctor clean); 0 open ROUTINE

## 2026-06-29 13:56 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: verify id:e149 heartbeat fix (stable state.runId beat); 112 tests green, gaming-scan clean, no ledger drift

## 2026-06-29 14:09 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: qualified id:d58f [HARD — meeting] (reverse-handoff §5b); audit clean, no tests changed, routine_open=0

## 2026-06-30 11:27 — reviewer (claude-opus-4-8)

review: relay-ckpt-20260629-1409..HEAD (39 commits incl. d097 zkm-B-topology, orphan-scan plugin-aware, 82e3 quota-extrapolation merge). make test 125/0 green; gaming-scan clean; 82e3+orphan-scan tests verified legitimate; 6 closures green (33d3/08c0/672b/d58f/7c10/de69); roadmap-lint/cross-ledger clean; contract pointer v6. routine_open=0.

## 2026-06-30 12:13 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review 20260630: c6c8/a7a3 doc-only (no gaming); reverse-handoff id:a7a3 → ROADMAP [ROUTINE] + red spec; suite 125/0, lint+doctor clean, contract v6 current [id:a7a3,c6c8]

## 2026-06-30 — executor (claude-sonnet-4-6)

Worked id:a7a3 — fixed `ckpt-tag.sh` to degrade gracefully when `.gitattributes` is unaddable (e.g. repo `.gitignore` `.*` catch-all swallows it). Now stages `.gitattributes` tolerantly (warns to stderr on failure, does not abort), then always stages `RELAY_LOG.md` and commits. All 4 test assertions in `test_ckpt_gitattributes_degrade.sh` green; full suite 126/0 green.
Friction: none.

## 2026-06-30 12:25 — executor (sonnet, relay-loop)

fix(ckpt-tag): degrade gracefully when .gitattributes is unaddable (id:a7a3) — tolerant git add + warn, always commits RELAY_LOG.md + tag; suite 126/0 green [id:a7a3]

## 2026-06-30 12:49 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: 3 TODO-only ledger commits since ckpt-1225 (ids ebd0/a17a/2a3d/80b8/0ee6) — gaming-scan + roadmap-lint + relay-doctor all clean; new items correctly [HARD — meeting] in TODO, no ROADMAP promotion; routine_open=0 [id:ebd0,a17a,2a3d,80b8,0ee6]

## 2026-06-30 16:13 — reviewer (claude-opus-4-8)

handoff: promote id:4d8e foundation — classify-verdict.sh (85df) + roadmap-lint case c/d (297b) as [ROUTINE] with RED specs

## 2026-06-30 16:18 — executor (claude-sonnet-4-6)

execute: id:85df classify-verdict.sh — implemented relay/scripts/classify-verdict.sh as a pure-function bash+python3 script (no heredoc stdin conflict: captures stdin via `cat` then pipes to `python3 -c`); D3 priority cascade: execute→review→hard→handoff→idle; handoff fires on any unpromoted.promote>0 OR surface>0, beating idle/human even when is_finished=true or roadmap_actionable_open=0 (the case b/h fix). Also registered the script in Makefile relay_FILES/relay_EXEC/relay_ALLOW to satisfy the install-manifest test. Full suite: 127 passed, 0 failed, 1 expected-red (test_roadmap_lint_tagprose.sh/297b, pre-existing).
## 2026-06-30 — executor (claude-sonnet-4-6)

execute: id:297b — extended `relay/scripts/roadmap-lint.sh` with case-c (tag/prose lane disagreement: detect >1 recognised lane bracket on a single item line, emit stderr ERROR matching `tag.*prose|prose.*lane|disagree`) and case-d (free-typed [INTENSIVE]: INTENSIVE only valid with [HARD — pool], any other lane emits stderr ERROR matching `intensive`). Both checks run inside the existing scan loop after `has_class=1` is confirmed; case-c counts recognised lane brackets with `grep -qF` per lane string from `hard_lanes`; case-d greps for `\[INTENSIVE — [^]]+\]` then checks for `[HARD — pool]` absence. No false positives on conforming fixtures; `test_roadmap_lint_tagprose.sh` GREEN, `test_roadmap_lint.sh` GREEN, full suite 127 passed 0 failed 1 expected-red (id:85df, pre-existing). ROADMAP id:297b ticked.

## 2026-06-30 16:26 — reviewer (claude-opus-4-8)

execute: id:85df classify-verdict.sh + id:297b roadmap-lint case c/d — both green (Sonnet executors, reviewed)

## 2026-06-30 16:40 — executor (claude-sonnet-4-6)

execute: id:3f0f classify-repo.sh — implemented `relay/scripts/classify-repo.sh`, the DP1 assembly wrapper that productizes the 2026-06-30 dogfood prototype. The script accepts `--repo <name> --path <abs>`, runs `gather-repo-state.sh` for base JSON, derives `hasRoutine`/`roadmap_open`/`roadmap_actionable_open` from `<path>/ROADMAP.md` (excluding human-gated lines), runs `unpromoted-scan.sh <path>` and folds promote/surface counts into `unpromoted`, then pipes the assembled JSON to `classify-verdict.sh`. Side-effect-free (verified by test fixture git-status check). Registered in Makefile `relay_FILES`/`relay_EXEC`/`relay_ALLOW`. `tests/test_classify_repo.sh` GREEN; full suite 129 passed 0 failed 0 expected-red. ROADMAP id:3f0f ticked.

## 2026-06-30 16:51 — reviewer (claude-opus-4-8)

execute+review: id:3f0f classify-repo.sh wrapper (green) + execve-overflow fix on large repos

## 2026-06-30 17:08 — reviewer (claude-opus-4-8)

execute: id:07be gather-repo-state execve overflow fix + id:5f93 backtest-verdict.py pre-flip gate

## 2026-06-30 17:12 — executor (claude-sonnet-4-6)

execute: id:de31 decision-queue.sh — durable file-backed human-decision-request queue. Implemented add/list/resolve subcommands with flock'd JSON append/rewrite; python3-safe JSON building; RELAY_DECISION_QUEUE env-overridable; registered in Makefile relay_FILES/EXEC/ALLOW. All 133 tests green.

## 2026-06-30 17:21 — reviewer (claude-opus-4-8)

execute: id:de31 decision-queue.sh — durable human-decision queue (DP4)

## 2026-06-30 17:25 — reviewer (claude-opus-4-8)

execute: id:e424 classify-verdict verdict-parity (blocked for dirty/diverged) — flip step a

## 2026-06-30 18:32 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: ledger reframes verified green (gaming-scan clean); promoted id:1bbd RED spec, fixed id:07be cross-ledger drift; suite 134 green +1 expected-red [id:1bbd,07be]
## 2026-06-30 — executor (Sonnet)

Worked id:1bbd — fixed `emit_hard_lanes()` in `gather-human-backlog.sh` to strip backtick-quoted strings from the line before lane detection. The bug: pool branch was checked first on the whole line, so a `[HARD — hands]` item whose prose quoted `` `[HARD — pool]` `` mis-bucketed as `hard_pool`. Fix adds a single `gsub(/`[^`]*`/, "", clean)` step that strips backtick spans from a scratch copy; lane detection runs on `clean` while the original `line` is preserved for the summary output. `tests/test_gather_lane_anchor.sh` (roadmap:1bbd) green; `test_hard_lane_buckets.sh` unregressed; suite 135 green.
Friction: none (one-liner fix; apostrophe-in-single-quoted-awk caught immediately on first test run).

## 2026-06-30 18:37 — executor (sonnet, relay-loop)

fix(relay): id:1bbd anchor emit_hard_lanes() to item OWN bracket tag — strip backtick prose before lane detection; suite 135 green [id:1bbd]

## 2026-06-30 19:00 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

id:401c strong-model audit Run 69 — code/security passes CLEAN, 2 ledger drifts fixed inline, suite 135/0 [id:401c,1bbd,d5e0]

## 2026-06-30 23:24 — reviewer (claude-opus-4-8)

id:9062 roadmap-lint INTENSIVE-lane realign (operative-only-on-dispatchable-lanes; supersedes 297b case-d)
## 2026-06-30 — executor (claude-sonnet-4-6, relay-loop)

id:5eb3 + id:5ac6 SHIPPED — implement the two classifier-flip prerequisites from meeting 2026-06-30-2238. (1) id:5eb3 case-b split: `classify-verdict.sh` now emits `human` (rank 5) instead of `handoff` for `promote==0 ∧ surface>0`; new `relay/scripts/file-surface-decisions.sh` does mechanical decision-queue filing when the loop sees `human`; `handoff.md` updated to remove the case-g filing obligation; `relay-loop.js` wired with human-verdict partition (extracts human units, calls file-surface-decisions.sh via haiku agents). (2) id:5ac6 INTENSIVE flag: `classify-verdict.sh` copies `top_intensive` verbatim to `intensive` field (string, always present) when verdict ∈ {execute,hard}, "" otherwise — enforcing the invariant `intensive!="" ⇒ verdict∈{execute,hard}`; fail-closed pre-dispatch assertion added to `runUnit` in `relay-loop.js` (skips+surfaces loudly if intensive unit reaches dispatch without ALLOW_INTENSIVE). Authorized reconciles: `test_classify_verdict.sh` case-b, `test_classify_repo.sh` handoff→human, `test_relay_loop_structure.sh` DISCOVER_SCHEMA enum + PRIORITY. Suite 144 passed / 0 failed / 1 expected-red (id:9062 open). [id:5eb3,id:5ac6]

## 2026-06-30 23:41 — reviewer (claude-opus-4-8)

id:5eb3 case-b→human + mechanical surface-filer; id:5ac6 INTENSIVE flag+invariant+fail-closed dispatch guard (SAFETY)

## 2026-07-01 14:48 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: verified id:0175 (routed:82e3) quota-gate fixes genuine — credential egress removed, --once stopReason guarded, seven_day_sonnet optional; 146 tests green, gaming-scan clean [id:0175]

## 2026-07-01 16:35 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: verified backtest expected-policy-delta bucket (candidate-worse 0/762, 0 crashes) + id:9d2b triage note genuinely green; 1 ADDED_SKIP flag adjudicated legitimate; suite 147 green [id:0e57,9d2b]

## 2026-07-01 19:27 — reviewer (claude-opus-4-8, handoff)

handoff: staged id:5987 [ROUTINE] reconcile-repo.sh with a behavioral RED spec (test_reconcile_repo.sh, 5 real-fixture scenarios) — the side-effecting git island of the a0b6 classifier-flip step (b). Executor picks up 5987 next; a0b6 engine swap stays supervised (gated on 5987 green).

## 2026-07-01 19:33 — reviewer (claude-opus-4-8, integrate)

executor(id:5987) + reviewer integrate: reconcile-repo.sh built green (test_reconcile_repo.sh 7/7, suite 148/0), the side-effecting git island of the a0b6 flip step (b). Reviewer verified genuine implementation + independently re-ran the suite. Noted nested-uv.lock fidelity gap → folded into a0b6 acceptance. Remaining for the flip: the full-unit assembler + relay-loop.js runner swap (a0b6, supervised).

## 2026-07-01 19:42 — reviewer (claude-opus-4-8, integrate)

executor(id:3d61) + reviewer integrate: classify-repo.sh --emit unit full-unit assembler green (5/5, suite 149/0). Second a0b6 flip-step-(b) component. Remaining: discover-repo.sh (64b4, per-repo composition) then the relay-loop.js runner swap (a0b6, supervised).

## 2026-07-01 19:48 — reviewer (claude-opus-4-8, integrate)

executor(id:64b4) + reviewer integrate: discover-repo.sh per-repo composition green (5/5, suite 150/0). The full mechanical discovery path is now tested (reconcile 5987 + assembler 3d61 + composition 64b4). Only the confined relay-loop.js runner swap (a0b6) + nested-lock fix remain — supervised.

## 2026-07-01 20:19 — reviewer (claude-opus-4-8, integrate)

FLIP COMPLETE (id:a0b6 / id:4d8e): the LLM discovery shard is replaced by the mechanical runner (reconcile-repo.sh + classify-repo.sh --emit unit + discover-repo.sh, all deterministic + tested). Suite 151/0, node-check + template-lint clean. Live smoke: discover-repo.sh on 6 real own repos (dotclaude-skills/zkWhale/zelegator/helferli/meeting-rpg/zkm) → 0 crashes, valid full units, coherent verdicts (review/handoff/human), via both canonical and the runner's ~/.claude path (symlinks installed via make install-relay). LLM confined to the dormant AMBIGUOUS surface. Backstops kept (A2); deletion gated id:b50e.

## 2026-07-01 21:10 — reviewer (claude-opus-4-8, integrate)

fix(id:4da4): classify execute-precision — actionable-routine gate + primary-lane anchoring + blocked-dep exclusion. Resolves all 3 /relay --once mis-fires (yinyang-puzzle @manual→human, leAIrn2learn prose-[ROUTINE]-on-[HARD-pool]→hard, zkm-threema BLOCKED-on-dep→human). classify-verdict gates execute on actionable_routine_open (back-compat -1 fallback); primary-lane = first lane-tag beats fragile backtick-strip. Suite 151/0. State-machine investigation stays open (id:4da4).

## 2026-07-01 23:17 — reviewer (claude-fable-5)

Fable catch-up review 2110..9f32043: 4 substantive commits clean (ed2e/2ec4/4da4-pt2), anomalies root-caused → 8e3e/0a3b/6e02

## 2026-07-01 23:19 — reviewer (claude-fable-5)

meeting-skill deep audit: 8 findings (3 MED b767/123d/e32a), concurrency+allowlist CLEAN; 0a3b one-time correction ticked

## 2026-07-01 23:39 — reviewer (claude-fable-5)

relay bugfix batch: 8e3e ckpt-at-reviewed-tip + 6e02 cleanup scoping + 0a3b toml sync + stale-watermark anchor; suite 158/0/0; POOL-SAFE restored

## 2026-07-01 23:50 — reviewer (claude-fable-5, relay-loop)

review: clean 2-commit ledger-only window (id:482d observe-downgrade + 3 archive moves); suite 158/0/0, gaming-scan + relay-doctor + lint all clean; 0 open ROUTINE [id:482d]

## 2026-07-02 01:19 — reviewer (claude-fable-5, relay-loop)

handoff C2-C5: promoted 8 TODO items to ROADMAP (4 ROUTINE dff8/482d/fb7f/a42e + 3 HARD-pool 7633/25aa/f032 + gated 659c), executed 9014 (route-2a effectively-drained predicate) at C5, wrote 4 red specs + 4 REVIEW_ME boxes, ingested 3 inbound dead-letters, lane-tagged 5 scan-mislabeled items, closed 22ef (overtaken), repaired fused 77f3/01fa line + misfiled ##Done EOF-appends; suite 159/0/4-expected-red [id:dff8,482d,fb7f,9014,7633,659c,a42e,25aa,f032,22ef]

## 2026-07-02 01:38 — reviewer (claude-fable-5, relay-loop)

Fable recheck of ckpt-20260702-0119: handoff window audited clean (9014 genuine, 4 red specs valid, gaming-scan clean, ledgers/lint consistent); dispatch itself exposed id:6856 — relay-loop.js queues a bogus Fable-rechecks-Fable unit after a Fable HANDOFF (isFableRecheck verdict-conjunct) with a hardcoded "Opus stood in" reason — filed [ROUTINE]+red spec; suite 159/0/5-expected-red [id:9014,6856]
## 2026-07-02 — executor (sonnet)

Worked id:a42e — gated `classify-repo.sh`'s `standin` derivation on the id:e030 `fable_rechecked` watermark (`standin = ("fable-standin" in ckpt_msg) and not fable_rechecked`), so a genuine Fable-recheck annotation that merely mentions the standin review it audited no longer re-elevates an already-rechecked repo idle→review on every pool round; updated the stale literal-string drift-guard in `test_fable_standin_marker.sh` to match. Ticked ROADMAP+TODO twins. Full suite 160/0/3-expected-red.
Friction: none.

## 2026-07-02 01:44 — executor (sonnet, relay-loop)

id:a42e — gated classify-repo.sh's standin flag on the id:e030 fable_rechecked watermark, stopping the perpetual idle-to-review re-dispatch on every Fable pool round [id:a42e]

## 2026-07-02 — executor (sonnet)

Worked id:dff8 — `git-lock-push.sh` id:aa93 dirty-guard now classifies the pull-path porcelain: untracked-only churn (every line `?? `) proceeds with the autostash-rebase (untouched by `--autostash`, which only stashes tracked changes), while any tracked modified/staged/renamed entry still refuses (the id:aa93 data-loss guard is unchanged for tracked dirt). Reworded the refusal to state facts ("working tree has uncommitted tracked changes; not autostash-rebasing (id:aa93)") instead of the unverified "(a concurrent edit?)" causal guess. Used the RED spec `tests/test_git_lock_push_dirty_guard.sh` already written by the handoff — no test changes needed, only the script fix. Ticked ROADMAP+TODO twins. Full suite 161/0/3-expected-red.
Friction: none.

## 2026-07-02 02:08 — executor (sonnet, relay-loop)

executor: closed [ROUTINE] id:dff8 — git-lock-push.sh dirty-guard now tolerates untracked-only churn and drops the "concurrent edit" causal guess; suite 161/0/3-expected-red [id:dff8]

## 2026-07-02 — executor (sonnet)

Worked id:482d — collapsed the discover-prelude's STOP-sentinel check/countdown/consume (previously prose instruction 8, timing-variance-prone) into one atomic `relay/scripts/stop-sentinel.sh check --path <file>` call; prelude step 8 now delegates verbatim. On consume it appends an ISO-8601-timestamped line to a log (`RELAY_STOP_SENTINEL_LOG`, default `~/.claude/logs/relay-stop-sentinel.log`) for the OBSERVE-instrumentation half. Registered in Makefile relay_FILES/EXEC/ALLOW. `node --check` + `lint-workflow-templates.mjs` + `test_relay_loop_structure.sh` all green on the prompt-string edit. Ticked ROADMAP+TODO twins. Full suite 162/0/2-expected-red.
Friction: none — the RED test spec (`tests/test_stop_sentinel_consume.sh`) was already written by the handoff, matched the implementation with no changes needed.

## 2026-07-02 02:30 — executor (sonnet, relay-loop)

executor: closed [ROUTINE] id:482d — STOP-sentinel check/countdown/consume collapsed into one atomic stop-sentinel.sh call + timestamped consume log; suite 162/0/2-expected-red [id:482d]

## 2026-07-02 — executor (sonnet)

Worked id:fb7f — lane-anchored the two remaining substring-matching parsers per the it-infra phantom-`hard` evidence. `gather-repo-state.sh`'s `open_hard_pool` was flagging any open item whose PROSE quoted `[HARD — pool]`; it now derives a `roadmap_primary_lane` helper (leftmost lane-tag by byte position after stripping backtick-quoted spans, mirroring classify-repo.sh's id:4da4 first-tag parse plus gather-human-backlog.sh's id:1bbd backtick-strip) and only counts an item when that primary lane is exactly `[HARD — pool]`, also excluding 🚧/`BLOCKED on` items (mirrors classify-repo.sh:98). `unpromoted-scan.sh`'s `primary_lane` had the same class of bug for TODO.md's bold-titled items: a leftmost-tag-anywhere scan let a prose `[ROUTINE]` mention (backtick'd or bare) outrank the item's real (non-executable) lane tag when one existed early, or masquerade as a lane when the item was genuinely untagged (33c2/a505/7b23/b8ae, live evidence from the 2026-07-02 handoff). Fixed by requiring the tag sit immediately after the bold title's closing `**` for bold-titled items; a bold item with no title-adjacent tag now returns no lane (disposition `surface`) regardless of prose mentions elsewhere. `tests/test_gather_pool_count_anchor.sh` 6/6 green (was 1/6). Full suite 163/163 green (was 162/1, one pre-existing structure-test drift-guard fixed along the way — a comment rewrite had dropped the literal "tagged EXACTLY" phrase `test_relay_loop_structure.sh` greps for; restored it, no behavior change).
Friction: none — the RED test spec (`tests/test_gather_pool_count_anchor.sh`) was already written by the handoff and its fixtures were the exact contract; classify-repo.sh's pure "leftmost tag anywhere" (cited in the acceptance as the mirror target) alone does not satisfy fixture A1 (a genuine trailing tag preceded by a backtick'd prose mention of a DIFFERENT tag) — backtick-stripping first was necessary, same technique gather-human-backlog.sh already uses for its own lane parse (id:1bbd).

## 2026-07-02 03:13 — executor (sonnet, relay-loop)

Closed [ROUTINE] id:fb7f: lane-anchored gather-repo-state.sh open_hard_pool and unpromoted-scan.sh primary_lane to exclude prose-only lane-tag mentions; suite 163/163 green. [id:fb7f]

## 2026-07-02 — executor (sonnet)

Worked id:6856 — dropped the `verdict === 'review'` conjunct from `isFableRecheck` in `relay-loop.js` so a strong checkpoint produced by REAL Fable (handoff/review/hard) always consumes the durable id:e030 recheck watermark instead of only doing so for review units; replaced the hardcoded "Opus stood in for Fable" elevation-reason literal with neutral wording. `tests/test_fable_recheck_write_side.sh` 4/4 green (was RED); `node --check` + `lint-workflow-templates.mjs` + `test_fable_standin_marker.sh` + `test_relay_loop_structure.sh` all green; full suite 164 passed, 0 failed.
Friction: none.

## 2026-07-02 03:27 — executor (sonnet, relay-loop)

id:6856 fixed — relay-loop.js isFableRecheck no longer restricted to review verdicts; elevation reason no longer hardcodes "Opus stood in for Fable"; full suite 164/0/0 green. [id:6856]

## 2026-07-02 04:43 — reviewer (claude-fable-5, relay-loop)

review 0138..0327: 5 executor units (a42e/dff8/482d/fb7f/6856) verified genuine — red specs green unmodified, gaming-scan clean, suite 164/0/0; ticked fb7f+6856 TODO twins (cross-ledger drift) + SKILL.md stop-sentinel doc gap; 0 open ROUTINE [id:a42e,dff8,482d,fb7f,6856]

## 2026-07-02 08:22 — reviewer (claude-fable-5, relay-loop)

review 0443..HEAD: window = 2 inbox ingests only (no executor work; gaming-scan clean, suite 164/0/0); both stubs misfiled under ## Done → relocated + new [ROUTINE] id:14d0 (scan-routed EOF-append fix, red spec); reverse-handoff promoted id:5884 [ROUTINE] (model-aware strongRecheckPending read gate, routed:1c2b, red spec); routed:20b2/id:962d folded into id:25aa as 2nd -c-anchor occurrence; REVIEW_ME pruned 8e3e/0a3b + surfaced routed:d51c dead-letter; 11 open / 2 ROUTINE [id:5884,14d0,25aa,962d]

## 2026-07-02 08:23 — executor (sonnet, relay-loop)

No-op: ROADMAP.md has 0 open [ROUTINE] items (the dispatch reason was stale — the prior review merge commit 2e58337 already ticked fb7f+6856 and states "0 open ROUTINE"); worktree left clean, no commit made.

## 2026-07-02 20:33 — executor (sonnet)

Worked id:68dc (A5) — built `relay/scripts/resource-probe.sh`: check-and-defer live-availability probe for the mechanical-run daemon's auto-launch gate (gpu via env-overridable nvidia-smi with graceful missing-binary degrade; ram via /proc/meminfo MemAvailable; cpu via /proc/loadavg vs nproc; local-llm claim-only), every resource first consulting `claim.sh peek` for a live `resource:<res>` claim (check-and-defer, never preempt) before any hardware read. Registered the script 3x in the relay Makefile block, documented the two-gate (permit-window + live-availability) launch condition in `relay/references/hard-lanes.md`, and ticked ROADMAP `<!-- id:68dc -->` via `md-merge.py update-ids`. `tests/test_resource_probe.sh` green; full suite 165 passed / 0 failed / 5 expected-red (all pre-existing open items, unaffected). Friction: none.
## 2026-07-02 — executor (sonnet)

Worked id:e407 — built the graded permitted-intensity slice (A4): `relay/scripts/relay-intensity.sh` CLI (`--for <dur> --light|--heavy`, `--afk` conservative default, `--intensive`/`--allow-intensive` back-compat permissive window, `--clear`, `--status`, `permits <est_wall> <resource>` predicate) writing/reading `$RELAY_INTENSITY_FILE` (default `~/.config/relay/permitted-intensity.json`) `{max_wall_seconds,resource_ceiling,expires_at}`; resource->tier mapping (light/heavy, ordered) is a hardcoded `HEAVY_RESOURCES` list (gpu/local-llm/local-model/llama), executor judgment per the item's Context note. Registered the script in the Makefile's relay_FILES/relay_EXEC/relay_ALLOW (mirrors acquire-resource.sh). `tests/test_permitted_intensity.sh` 7/7 green (was RED); full suite 165 passed, 0 failed, 5 expected-red. Deliberately did NOT wire `relay-loop.js`'s `ALLOW_INTENSIVE` gate to the new predicate — the item explicitly flags that engine edit as RISKY (a0b6 template-literal-lint hazard class) and defers it; left a clearly-marked `TODO (id:e407 follow-up)` comment at the `ALLOW_INTENSIVE` definition (~line 75) pointing at `relay-intensity.sh permits` and the meeting note, verified with `node --check`.
Friction: none.
## 2026-07-02 — executor (sonnet)

Worked id:64d3 — built A2 of the mechanical-run daemon prep (meeting 2026-07-02-1924
decision 3): `relay/scripts/recipe-validate.sh` validates one recipe JSON against the
7-field schema `{id,repo,cmd,host,est_wall,resource,acceptance_artifact}` (python3
stdlib `json` for parsing, never string munging) — silent exit 0 on a well-formed
recipe, LOUD `ERROR: <field> ...` on stderr + nonzero exit on the first missing/wrong-
typed field or a non-positive/non-integer `est_wall`; and
`relay/references/recipe-manifest.md` documents the `{pending,running,done}/` drop-dir
lifecycle, the schema, and — the load-bearing part — that recipes are WHITELISTED /
relay-authored only and the daemon (A3, gated, not built here) must NEVER auto-scan
ROADMAP.md to invent them. Registered the script 3x (relay_FILES/EXEC/ALLOW) and the
doc 1x (relay_FILES) in the Makefile per id:69ef install-completeness. Ticked ROADMAP
id:64d3 via `md-merge.py update-ids`. `tests/test_recipe_manifest.sh` 5/5 green (was
RED); full suite 165 passed, 0 failed, 5 expected-red (other open items).
Friction: none — the RED spec's field-injection helper (Python json load/pop/dump)
made the exact rejection contract unambiguous, including the bool-is-not-int and
float-est_wall edge cases.
## 2026-07-02 — executor (sonnet)

Worked id:7616 (A1) — added the `[MECHANICAL]` capability tag + pool-inert `mechanical`
verdict per the 2026-07-02-1924 meeting's slice-A plumbing-only scope. `roadmap-lint.sh`
now recognizes `[MECHANICAL]` as a class tag (standalone or composed with
`[INTENSIVE — <resource>]`) and treats it as a capability lane in the tag/prose
lane-count check, so `[MECHANICAL]` + `[HARD — pool]` on one item correctly trips the
two-lane conflict. `gather-human-backlog.sh` needed NO change — it only ever inspects
lines containing `[HARD`, so a MECHANICAL-only repo was already silently excluded from
every human-triage bucket; the RED test for (b) passed unmodified against the untouched
script. `classify-verdict.sh` gained a new `open_mechanical` input field and a `mechanical`
verdict branch (priority_rank 6, inserted between `human` and `idle`, which shifted from
rank 6 to rank 7 — no consumer pins the numeric rank, checked via grep first) that fires
only when nothing higher-priority is present; `intensive` stays `""` on it, preserving the
id:5ac6 invariant. Wired minimal producer plumbing in `classify-repo.sh`'s ROADMAP parse
(counts `[MECHANICAL]` lines into `open_mechanical`, folded into both the classifier input
and the `--emit unit` passthrough) — no daemon consumer built (A3 stays gated).
Documented the tier in `hard-lanes.md` (properties table: daemon-run, pool-inert,
human-inert, INTENSIVE composes, two-lane conflict with `[HARD — *]`, verdict `mechanical`).
`tests/test_mechanical_tag.sh` 6/6 green; ticked ROADMAP id:7616 via `md-merge.py
update-ids`; full suite 165 passed, 0 failed, 5 expected-red (unrelated open items).
Friction: none — (b)'s RED assertion turned out to already hold against the unmodified
script, confirmed by re-running the test before touching gather-human-backlog.sh at all.

## 2026-07-02 — reviewer (Opus apex) — slice-A capability-taxonomy review

Reviewed window 5d8cf34..d2146c2 (8 commits: 4 executor builds + 4 integrate merges) for the four slice-A items from meeting 2026-07-02-1924. VERDICT: all four GENUINE (PASS). Anti-gaming: the four RED test files (test_mechanical_tag/recipe_manifest/permitted_intensity/resource_probe.sh) are BYTE-IDENTICAL between the ced7343 C3 commit and HEAD (git diff = 0 lines) — no assertion was weakened; the impl scripts (relay-intensity/resource-probe/recipe-validate.sh) were ALL absent at ced7343, so red⇒green came purely from new implementation. `gaming-scan.sh` over the window: ZERO flags (no DELETED_TEST/ADDED_SKIP/REMOVED_ASSERT).

Per-conjunct verification: (A1 id:7616) classify-verdict emits `mechanical` at priority_rank 6, pool-inert, `intensive=""` preserved (id:5ac6 invariant `intensive!="" ⇒ verdict∈{execute,hard}` holds — mechanical is neither); roadmap-lint accepts `[MECHANICAL]` standalone+`[INTENSIVE]`-composed and rejects a `[MECHANICAL]+[HARD — pool]` two-lane conflict; gather keeps a MECHANICAL-only repo out of every human lane; hard-lanes.md documents the tier. Idle correctly renumbered rank 6→7; grep confirms no external consumer pins numeric rank 6/7 (relay-loop.js keys on verdict STRINGS only). (A2 id:64d3) recipe-validate fails LOUD (nonzero + `ERROR: <field>` naming the FIRST offender) on every missing/wrong-typed field and non-positive/float/bool est_wall — no silent coercion; doc names drop-dir + 7 fields + whitelist/never-auto-scanned; Makefile 3x+doc registered. (A4 id:e407) `permits` predicate enforces window (est_wall≤max_wall) AND ceiling (light<heavy ordered) AND strict expiry (now<expires_at); deny-by-default (no permit / expired / 0-duration); `--afk` writes a conservative short+light window (not full intensive). (A5 id:68dc) resource-probe consults `claim.sh peek` FIRST — before any hardware read — so a held `resource:<res>` claim ⇒ available:false, exit 1, never preempts (check-and-defer); gpu/ram/cpu/local-llm sources all emit valid JSON with a boolean `available`; confirmed on the real zomni host (nvidia-smi ABSENT ⇒ graceful available:false+reason, no crash; ram 10163MB free; LOAD_MAX default=nproc=8).

A4's deferred relay-loop.js `ALLOW_INTENSIVE`→`permits` wiring is RECORDED durably (not a silent gap): a clearly-marked `TODO (id:e407 follow-up)` comment at the ALLOW_INTENSIVE definition (~line 75) pointing at `relay-intensity.sh permits` + the meeting note (RISKY a0b6 template-literal-lint hazard class, deferred deliberately), plus the note in TODO.md id:e407 and the executor's RELAY_LOG entry.

Ledger actions: ticked TODO.md ids 7616/64d3/e407/68dc `[x]` (single-id-two-views D2 sync — were `[ ]` in TODO while `[x]` in ROADMAP) via md-merge.py update-ids, reusing the same ids. Resolved+closed the slice-A REVIEW_ME box (three executor judgment calls — resource→tier mapping, mechanical rank, probe thresholds — all confirmed sane; #3 verified on the real host). Suite: 168 passed / 0 failed / 2 expected-red (unrelated open items 14d0 + one other). `roadmap-lint.sh ROADMAP.md` exit 0. verified_green: 7616, 64d3, e407, 68dc. gaming_flags: none. reopened: none.

## 2026-07-02 — handoff (wave 2a — `[MECHANICAL]` end-to-end)

Prepared wave-2a of the capability-keyed-taxonomy build: make the `[MECHANICAL]` tag
END-TO-END (produced + run), building on slice-A which shipped only the CONSUMER half
(the classifier recognizes `[MECHANICAL]`→`mechanical` but no layer PRODUCES it and
nothing RUNS it). Source of truth: the `## Amendment 2026-07-02 (post-build — the
`[MECHANICAL]` producer gap)` section of
`docs/meeting-notes/2026-07-02-1924-relay-mechanical-lane-capability-taxonomy.md`.
Promoted three items to ROADMAP (single-id-two-views, reusing the TODO ids): M1
(id:9c88, `[ROUTINE]`) teach `handoff.md` C2 to PRODUCE the tag + author the recipe;
M2 (id:2313, `[HARD — pool]`) fix the three producer sites (`hard-lanes.md` re-lane,
`handoff.md` author-then-run split, `human.md` "you run these") that still route
daemon-runnable no-LLM work to `[HARD — hands]`; A3 (id:b3d0, `[HARD — pool]`)
un-gated (deps 64d3/e407/68dc met) — the mechanical-run daemon. Slice-B rename
(B1 id:4f02 / B2 id:8111) and M3 (id:3ef7 existing-item re-lane audit) stay GATED.
Uses the CURRENT lane vocabulary (`[ROUTINE]`/`[HARD — pool]`); the rename is wave 2b.

## 2026-07-02 — executor (Sonnet)

Worked id:9c88 (M1) + id:2313 (M2) — both CONTRACT-PROSE-only, no script changes, one
executor session since they share the same three docs. M1: taught `handoff.md`'s C2
checkpoint to PRODUCE `[MECHANICAL]` for compute-only/no-LLM/benchmark-or-pilot work
(instead of always `[ROUTINE]`/`[HARD — *]`) and to author the A2 recipe (id:64d3
schema) into `~/.config/relay/recipes/pending/` — the missing producer link to the A3
daemon. M2: added the "needs an LLM?" branch to all three sites that were still routing
daemon-runnable "run X" work to `[HARD — hands]` — `hard-lanes.md`'s 5-criterion re-lane
(compute-only+passes-a–e ⇒ `[MECHANICAL]`; LLM-needed+passes-a–e ⇒
`[ROUTINE]`/`[HARD — pool]`; fails-a–e ⇒ unchanged `hands`/`meeting`), `handoff.md`'s
author-then-run split (the run residue is `[MECHANICAL]` unless it genuinely needs a
human — device/sudo/physical/credential), and `human.md`'s `hard_hands` triage bullet
(explicitly excludes `[MECHANICAL]` from the "you run these" checklist, noting
`gather-human-backlog.sh` already keeps it out in code per slice-A A1). Did a
consistency re-read across all three docs after editing: the compute-only/LLM-needed/
fails-criteria trichotomy is stated identically (cross-referencing id:9c88/id:2313) in
each, no contradictions. Both structural tests
(`test_handoff_produces_mechanical.sh`, `test_mechanical_relane_doctrine.sh`) went
green; ticked both ROADMAP checkboxes via `md-merge.py update-ids`. Full suite:
170 passed, 0 failed, 3 expected-red (unrelated open items 5884/b3d0/14d0 — b3d0 is A3,
correctly still open, unaffected by this doc-only change).
Friction: none — the two specs and the meeting-note amendment fully constrained the
prose; no ambiguity encountered.
Worked id:b3d0 (A3, mechanical-run daemon) — built `relay/scripts/mechanical-daemon.sh`,
the one-tick processor over the `~/.config/relay/recipes/{pending,running,done}/` drop-dir
gated on it in wave-2a. For each recipe in `pending/`: validates via `recipe-validate.sh`
(a malformed recipe is moved to a new `rejected/` dir with a loud sibling `.error` file and a
log line — never a silent drop, id:4347); checks the launch gate
(`relay-intensity.sh permits <est_wall> <resource>` AND `resource-probe.sh <resource>`, both
must pass); on permit moves `pending→running`, runs `cmd`, moves `running→done`, and drops a
review-request via `inject.sh add --verdict review`. Denial on EITHER gate check leaves the
recipe untouched in `pending/` for the next tick — check-and-defer, never preempt, matching
`resource-probe.sh`'s own doctrine; a failed `cmd` still lands in `done/` (with a `.error`
file) rather than a permanent `running/` ghost, but does not inject a review. Added the
`tools/mechanical-daemon.{path,service}` systemd `--user` unit pair (model-probe/quota-sample
topology: a `.path` unit watching `pending/` triggers a oneshot tick, no polling) and
`make install-mechanical-daemon`/`status-`/`uninstall-` targets creating the drop-dir on
install. Registered `scripts/mechanical-daemon.sh` in the Makefile `relay_FILES`/`_EXEC`/
`_ALLOW` (id:69ef install-completeness — `test_relay_install_manifest.sh` confirms all 51
`relay/scripts/*` present). Ticked ROADMAP id:b3d0 `[x]` via md-merge.py update-ids. Suite:
169 passed / 0 failed / 4 expected-red (unrelated open items 5884/9c88/2313/14d0).
Friction: none — the three slice-A helpers (recipe-validate.sh, relay-intensity.sh,
resource-probe.sh) and inject.sh/claim.sh composed cleanly with no interface surprises.

## 2026-07-02 — review: wave-2a `[MECHANICAL]` end-to-end (M1/M2/A3) — Opus reviewer

Adversarial review of the three items that make `[MECHANICAL]` end-to-end (diff window
d94248f..HEAD). **Verdict: PASS — all three GENUINE.** The three spec tests
(test_handoff_produces_mechanical / test_mechanical_relane_doctrine / test_mechanical_daemon)
are **byte-identical to their RED versions at f0ddadd** (`git diff f0ddadd..HEAD -- tests/`
empty) — the executor changed the implementation, never loosened a spec.

- **M1 (id:9c88) GENUINE** — handoff.md C2 gained a real producer paragraph: recognize
  compute-only / no-LLM / benchmark-or-pilot work → tag `[MECHANICAL]` (composing
  `[INTENSIVE — <res>]`) AND author the A2 recipe (`recipe-manifest.md` schema, id:64d3) into
  `~/.config/relay/recipes/pending/`, with the producer-link rationale ("tagging alone routes
  to the pool-inert verdict but nothing runs it"). Structural test is C2-anchored (§3 asserts
  the token lives at/after the `**C2 — roadmap.**` marker) — not keyword-bait; the doctrine is
  actually, coherently stated.
- **M2 (id:2313) GENUINE** — the "needs an LLM?" branch landed coherently at all THREE sites,
  same rule everywhere: passes-a–e + compute-only/no-LLM ⇒ `[MECHANICAL]` (daemon); passes-a–e
  + needs-LLM ⇒ `[ROUTINE]`/`[HARD — pool]`; fails-a–e (human hands/eyes/credential) ⇒ stays
  `[HARD — hands]`. hard-lanes.md new branch + worked verdicts UNCHANGED (c5e9 fails-(b), 9321
  live-GPU+sudo fails-(c) both still **stay hands**), handoff.md author-then-run split routes
  the daemon-runnable run-residue to `[MECHANICAL]`, human.md §4 EXCLUDES `[MECHANICAL]` from
  "you run these". No contradiction across the three docs; genuinely-human hands work preserved.
- **A3 (id:b3d0) GENUINE (with one host-gate REVIEW_ME).** Per-conjunct done-claim (id:369c)
  verified clause-by-clause against mechanical-daemon.sh: (a) validates via recipe-validate.sh
  before anything; (b) check-and-defer — a denied intensity-permit OR unavailable
  resource-probe leaves the recipe untouched in pending/ (`continue`, no move, no artifact, no
  inject, no preempt/kill); (c) invalid recipe is NOT silently dropped (→ rejected/ + sibling
  `.error` + loud log + stderr, id:4347); (d) on permit pending→running→done + `cmd` writes the
  artifact + inject.sh review-request; (e) whitelist invariant — loops ONLY over pending/*.json,
  never scans ROADMAP/TODO. A cmd-failure lands in done/ + `.error` with no inject (no
  running/ ghost) — documented + reasonable. **Finding:** the daemon never host-gates — reads
  `est_wall`/`resource`/`cmd`/`artifact` but not `.host`, despite recipe-validate requiring a
  non-empty host and recipe-manifest binding it to `[host:<name>]`. Not a live bug (per-host
  drop-dir) but a latent auto-execute safety gap → REVIEW_ME box filed; does NOT reopen b3d0.

Cross-ledger (D2): 9c88/2313/b3d0 were `[x]` in ROADMAP but `[ ]` in TODO — ticked all three
in TODO.md via md-merge.py update-ids (checkbox-only flip, full line preserved). Full suite:
**171 passed / 0 failed / 2 expected-red** (unrelated open 14d0 + one other). `roadmap-lint.sh
ROADMAP.md` exit 0 (clean). Makefile install-/status-/uninstall-mechanical-daemon +
`.path`/`.service` units reviewed — `.path` uses `PathModified` (re-arms per write, correct vs
`DirectoryNotEmpty`), oneshot service `Nice=10`. Do NOT push — integrator merges.

## 2026-07-02 — executor (Sonnet)

Worked id:9cfa — mechanical-daemon.sh now enforces the recipe `host` binding before running (the wave-2a review finding). Added a host gate as step 2 of the tick loop, BEFORE the intensity/resource launch gate: reads the recipe's `.host` field and calls `host-gate.sh "[host:$host]"` (REUSED as-is, synthesizing the `[host:<name>]` tag text it already parses, rather than a raw `uname -n` compare — host-gate.sh's own `RELAY_HOSTNAME` override also gave the new test a clean way to inject a hermetic 'current host' without depending on the real machine's hostname). On mismatch (exit 3) the recipe is left untouched in pending/ (check-and-defer, same discipline as the intensity/resource gates) with a `DEFERRED ... reason=host-mismatch` log line; on match it proceeds to the existing gates unchanged. TDD: extended `tests/test_mechanical_daemon.sh` with case (4) foreign-host recipe (confirmed RED — stayed pending, no host check existed) and case (5) matching-host recipe (guards against the fix over-blocking); both green after the change, and the three pre-existing cases (permitted / resource-claimed / est_wall-too-big) still pass unmodified. Ticked TODO id:9cfa (checkbox-only, full line preserved via md-merge.py). Full suite: 171 passed / 0 failed / 2 expected-red (unrelated). Friction: none.

## 2026-07-02 — handoff (Opus) — wave 2b prep (lane-vocabulary RENAME)

Prepared wave 2b of the capability-keyed lane taxonomy (meeting 2026-07-02-1924, decisions
1+2): the `[HARD — <suffix>]`→two-axis-vocabulary rename. Un-gated B1 (id:4f02, safety-net
converter + dual-vocab lint) and B2 (id:8111, the migration) — dep A1 (id:7616) is landed
`[x]`. B1 promoted to an ACTIVE `## … wave 2b` section (dispatchable now); B2 kept under a
`### GATED — B2 (DEP: 4f02)` sub-heading (roadmap-lint-exempt, non-dispatchable until B1
lands). RED specs: `tests/test_lane_convert.sh` (B1 — dual-vocab lint dual-accepts old+new;
`lane-convert.sh` exact mappings incl. hands→`[INPUT — access]` DEFAULT + MECHANICAL-candidate
FLAG-not-convert) and `tests/test_lane_vocab_migration.sh` (B2 — readers bucket the new vocab).
Both verified RED. Scope LOCKED to THIS repo's contract + lane-readers + tests + this repo's
own ROADMAP/TODO tags; cross-repo item re-tagging is the SEPARATE gated migration the
dual-vocab window enables. Do NOT push — integrator merges.

## 2026-07-02 — executor (Sonnet)

Worked id:4f02 (B1 — SAFETY-NET-FIRST half of the wave-2b lane-vocabulary rename). Three
deliverables landed: (1) `relay/references/hard-lanes.md` gained a "North star —
capability-keyed vocabulary" section: the ratified two-axis table, the three unambiguous
1:1 rename rows, the `[HARD — hands]` four-candidate fan-out table (per the "no auto-default"
amendment), and an explicit "dual-vocab migration window OPEN" statement — the old lane table
stays untouched above it. (2) `relay/scripts/roadmap-lint.sh`'s `class_re` now dual-accepts
BOTH vocabularies: added an `input_lanes` extraction (mirrors the existing `hard_lanes`
extraction, `grep -oE '\[INPUT — [a-z]+\]'` over hard-lanes.md — no second hardcoded copy) plus
a literal bare `[HARD]` alternative; the case-c two-lane conflict counter was extended with the
same two additions so an item carrying both an old lane and its new rename (e.g.
`[HARD — pool]` + `[HARD]`) is still correctly flagged as a conflict. Confirmed bare `[HARD]`
cannot false-match inside `[HARD — pool]` (the em-dash+space always intervenes). (3) new
`relay/scripts/lane-convert.sh <ledger-file>` (`--in-place` optional, for B2c): a pure text
transform doing only the three unambiguous renames; every `[HARD — hands]` line is left
byte-for-byte unchanged and flagged on stderr naming all four candidate destinations
(`[MECHANICAL]`/`[INPUT — access]`/`[INPUT — decision]`/`[INPUT — meeting]`) plus file:line+id —
it never auto-substitutes any lane onto a hands line. Registered in all three Makefile relay
lists (`relay_FILES`/`relay_EXEC`/`relay_ALLOW`, id:69ef pattern). `tests/test_lane_convert.sh`
now passes all four cases (a/b/c/d). Ticked ROADMAP id:4f02 via `md-merge.py update-ids`. Full
suite: 172 passed / 0 failed / 3 expected-red (id:8111 B2 — correctly still gated on this item;
id:14d0, id:5884 — unrelated open items). Friction: none — the ROADMAP item's Context section
pointed at the exact `class_re`/case-c line ranges to extend, and the hard-lanes.md doc-driven
extraction pattern generalized cleanly to the new `[INPUT — …]` vocabulary. Do NOT push —
integrator merges.

## 2026-07-02 — executor (Sonnet) id:8111 B2b

Worked id:8111 B2b — dual-vocab lane recognition in `relay/scripts/relay-loop.js` (the
crash-prone engine half of the vocabulary migration). Widened `classifyDrainBacklog`'s
gated-bucket regex from `/HARD backlog|\[HARD —|no open \[HARD — pool\]|.../i` to also
match `\[HARD\]` (bare new-vocab tag) and `\[INPUT —` (the three `[INPUT — meeting|
decision|access]` human-gate tags), so a surfaced/blocked reason mentioning the new
vocabulary still buckets correctly instead of falling into `other`. Updated the
DISCOVER_SCHEMA `openHard`/`open_hard_pool` field comments and the demote-guard's
block comment (id:9973) to name both the legacy `[HARD — pool]` spelling and the new
bare `[HARD]`/`[INPUT — …]` equivalents (comments only — confirmed and left the
`open_hard_pool` numeric demote-guard logic itself untouched, per the item's explicit
"tag-agnostic, do not touch" note). Updated the `Hard` stage's display `detail` string
(meta.phases) to mention both spellings. Left the `open_hard_pool`-computing regex
inside gather-repo-state.sh (B2a scope) and the LLM-shard prompt text alone —
out of B2b's file scope. Engine-edit safety: `node --check relay/scripts/relay-loop.js`
clean, `lint-workflow-templates.mjs` clean (1 workflow script), `test_relay_loop_structure.sh`
all green, full suite 172 passed / 0 failed / 3 expected-red (unrelated open items:
id:8111 itself via test_lane_vocab_migration.sh which targets B2a's gather-human-backlog.sh
not this file, plus id:14d0/id:5884). Friction: none — the ROADMAP item's B2b bullet named
the exact function (`unitIsSubstantive`/`classifyDrainBacklog`) and regex to widen, and
`test_lane_vocab_migration.sh` explicitly documents B2b as "verify-on-implementation" via
the ~30 lane tests once they're migrated in B2c, not directly re-encoded here — so this
slice's own done-check is the four engine-safety commands plus the unchanged full suite
staying green. Do NOT push — integrator merges.
## 2026-07-02 — executor (Sonnet) id:8111 B2a

Worked id:8111 B2a — flipped the lane-PARSERS + reference prose to EMIT/EXPECT the new
capability-keyed vocabulary while keeping the dual-vocab window OPEN (old venue-keyed
spellings still accepted). (1) `gather-human-backlog.sh::emit_hard_lanes`: the line-selection
guard now also matches `[INPUT — <lane>]` (previously only `/\[HARD/`, so an `[INPUT — …]`
item was silently skipped, never even reaching the untagged check); the bucket `if/else` chain
now recognizes bare `[HARD]` → `hard_pool`, `[INPUT — meeting]`/`[INPUT — decision]` →
`hard_meeting`, `[INPUT — access]` → `hard_hands`, checked AFTER the old dash-lane branches so
an old-vocab tag (`[HARD — pool]` etc.) is never mis-caught by the new bare-`[HARD]` branch.
Updated the file-header and function-header comment blocks + the untagged ERROR message to
describe both vocabularies. (2) `classify-repo.sh`: extended `HUMAN_GATES` with the three
`[INPUT — …]` spellings and `LANE_TAGS` with bare `[HARD]` (an exact-substring match — never
false-matches inside `[HARD — pool]`/`[HARD — hands]`, which always carry `[HARD —`, never the
literal `[HARD]`); `is_pool` now checks `primary in ("[HARD — pool]", "[HARD]")`. (3)
`gather-repo-state.sh::roadmap_primary_lane`: extended the tag list the same way, then
normalizes any matched new-vocab tag to its old-vocab equivalent before returning, so the
downstream `open_hard_pool` anchor (and any future caller) keeps comparing against one
canonical string. (4) Reference prose (`human.md`, `review.md`, `conventions.md`,
`handoff.md`): re-worded the normative lane-vocabulary passages to present the new vocab as
canonical with the old spelling noted as "still accepted during the dual-vocab migration
window" — meaning unchanged, no lane's disposition changed. `tests/test_lane_vocab_migration.sh`
(the RED spec) now passes both assertions (no LOUD-reject on a new-vocab ROADMAP; correct
hard_pool/hard_meeting/hard_hands bucketing). Manually verified `gather-repo-state.sh` +
`classify-repo.sh --emit unit` against an ad-hoc new-vocab fixture repo: `open_hard_pool=1` for
a bare-`[HARD]` item, `actionable_routine_open=0` (correctly excludes the `[INPUT — meeting]`
human-gate item). Full suite: 173 passed / 0 failed / 2 expected-red (id:14d0, id:5884 —
unrelated open items; all ~30 old-vocab lane tests still pass unchanged, confirming dual-accept
is intact). Did NOT touch `relay-loop.js` (B2b), convert any ROADMAP/TODO item tags, migrate
the ~30 lane-asserting tests, or close the dual-vocab window (B2c) — out of scope. Did NOT tick
id:8111 (multi-part item, orchestrator ticks after all three sub-parts land). Friction: none —
the sub-check text in ROADMAP.md named the exact functions/anchors to touch. Do NOT push —
integrator merges.

## 2026-07-02 — REVIEW of wave-2b (B2a parsers+refs, B2b relay-loop.js) + id:8111 re-scope

Adversarial relay review (Opus apex) of the `8ad343b..HEAD` migration window. **Verdict:
both units GENUINE.** Dual-accept was verified BOTH directions (the load-bearing claim):
- **B2a — GENUINE.** Directly proved new-vocab handling in all three parsers with ad-hoc
  fixtures (not just the passing old-vocab suite): `gather-repo-state.sh::roadmap_primary_lane`
  normalizes bare `[HARD]`→`[HARD — pool]`, `[INPUT — meeting]`→`[HARD — meeting]`,
  `[INPUT — decision]`→`[HARD — decision gate]`, `[INPUT — access]`→`[HARD — hands]` (8/8
  cases incl. old-vocab pass-through + no-false-match); replicated `classify-repo.sh`'s
  `LANE_TAGS`/`HUMAN_GATES` parse — bare `[HARD]`→pool, `[INPUT — access/meeting/decision]`→
  human-gate, and confirmed bare `[HARD]` does NOT shadow `[HARD — pool]` (exact-substring,
  `[HARD — pool]` contains `[HARD —` never `[HARD]`). `open_hard_pool` counter (line 383) keys
  off the normalized lane, so a bare-`[HARD]`-only repo IS counted (demote-guard safe).
- **B2b — GENUINE.** `node --check` + `lint-workflow-templates.mjs` + `test_relay_loop_structure.sh`
  all green. The ONLY executable change is a pure widening of the diagnostic `classifyDrainBacklog`
  bucket regex (old alternatives preserved verbatim, `\[HARD\]`/`\[INPUT —`/`no open \[HARD\]`
  added) — a display categorization, NOT a dispatch decision. The numeric `open_hard_pool`
  demote-guard (line 944, `(u.open_hard_pool||0)===0`) is tag-agnostic and UNTOUCHED. Everything
  else in the diff is comment/detail-string prose.
- **Tests not gamed.** `git diff 8ad343b..HEAD -- tests/` is EMPTY — no test touched in the
  window; `test_lane_vocab_migration.sh` existed at 8ad343b (added at handoff b6c87ff) and is
  now green by implementation. No assertion weakened.
- **INTERACTIVE var — LEFT IN (not removed).** The harness flagged it dead, but it is
  load-bearing: `tests/test_relay_front_door.sh:60` greps relay-loop.js for
  `!!A\.interactive|args\.interactive` and line 65 (`const INTERACTIVE = !!A.interactive`) is
  the SOLE match. Removing it would break that assertion. The lint flag is a false positive.

**Bookkeeping (the honest re-scope):** id:8111's original text covered readers+refs+engine AND
(ledger conversion + ~30-test migration + window-CLOSE). Only B2a/B2b shipped. RE-SCOPED
id:8111 to "lane-readers + references + engine dual-accept migration" and TICKED it (genuinely
done + verified). SPLIT the unshipped B2c tail into new **id:7df1** ("close the dual-vocab
window — convert this-repo ledgers + migrate ~30 tests + flip old-vocab→lint ERROR"), left
UNTICKED and GATED on M3 (id:3ef7) AND cross-repo re-tag (other own repos + `project_manager`
scan.py id:b466 must speak new vocab first — closing early breaks repos still on `[HARD — *]`).
Sharpened **M3 (id:3ef7)** per the owner's human-lanes-closed amendment: its per-`[HARD — hands]`
judgment now LEADS with "BDD-automate? (why isn't this a test?)" before any `[INPUT]`/
`[MECHANICAL]` placement; human lanes closed to {meeting,decision,access}; `[INPUT — unspecific]`
= undecidable-only catch-all; NO `[INPUT — run]` lane. Cross-ledger D2 consistent (8111 `[x]`
both ledgers, 7df1 `[ ]` both). `roadmap-lint.sh ROADMAP.md` exit 0; full suite 173 passed / 0
failed / 2 expected-red. **Overall: PASS.** Do NOT push — integrator merges.

## relay(execute): id:0d58 — anchor open_mechanical to primary lane (2026-07-03)

Fixed the `[MECHANICAL]` lane-anchoring bug in `relay/scripts/classify-repo.sh` (id:0d58).
`open_mechanical` was a bare-substring test (`if "[MECHANICAL]" in ln`) independent of the
id:4da4 primary-lane derivation, so a backtick'd `` `[MECHANICAL]` `` mention on a
differently-laned open item (e.g. `[ROUTINE] @manual ... `[MECHANICAL]` runner note` or
`[HARD — pool] ... superseded a `[MECHANICAL]` sub-step`) falsely inflated the count and could
mis-fire the priority-6 `mechanical` verdict. Fix: added `[MECHANICAL]` to `LANE_TAGS` so it
flows through the SAME positional `primary = min(_found)[1]` derivation as every other lane,
derived `is_mechanical = (primary == "[MECHANICAL]")`, and deleted the standalone bare-substring
counter — `primary` is now the sole lane reader, so no future tag can bypass anchoring.
`classify-verdict.sh`'s priority cascade was untouched per the reviewer's caveat (the bug was
purely the count). The anchoring alone satisfied all three RED fixtures (false-positive on
`[ROUTINE]`-mention, false-positive on `[HARD — pool]`-mention, and the genuine-`[MECHANICAL]`
no-over-correction guard) — no additional whitespace-boundary regex was needed.
`tests/test_mechanical_lane_anchor.sh` is now GREEN, id:0d58 ticked in ROADMAP.md, and the full
suite is 174 passed / 0 failed / 2 expected-red (unrelated open items). **Overall: PASS.** Do
NOT push — parent session handles it.

## relay(execute): id:fd37 — [MECHANICAL] recipe explicit-success-marker doctrine (2026-07-03)

Implemented the two enforcement surfaces the RED spec (`tests/test_recipe_success_marker.sh`)
pinned. (1) DOC: `relay/references/recipe-manifest.md` gained a new "Explicit success/failure
marker (acceptance_artifact) — id:fd37" section documenting the requirement (a `cmd` that
redirects into `acceptance_artifact` must append an explicit terminal marker AND preserve the
real exit code) plus the canonical verbatim pattern `cd <repo> && { <realcmd> > "$ART" 2>&1;
rc=$?; echo "MARKER exit=$rc finished=$(date -Is)" >> "$ART"; exit $rc; }`. (2) CODE:
`relay/scripts/recipe-validate.sh` grew a conservative advisory check (python3 stdlib, run only
after the existing 7-field schema hard-fail passes) that emits a `WARNING:` on stderr — still
exit 0 — iff `cmd` contains the `acceptance_artifact` value alongside a redirect (`>`) and
carries no `exit=`/`exit $?`-style marker token; a cmd already carrying the canonical `exit=$rc`
pattern draws no warning, so no false positive on a correct recipe. Also updated the producer
site per the item's stated scope: `relay/references/handoff.md`'s C2 `[MECHANICAL]`-tagging
paragraph now tells the recipe author to include the `exit=$rc` marker when the `cmd` redirects
into `acceptance_artifact`, pointing at `recipe-manifest.md` for the pattern and noting
`recipe-validate.sh`'s non-fatal warning. `tests/test_recipe_success_marker.sh` is GREEN (all
three assertions a/b/c), id:fd37 ticked in both ROADMAP.md and its TODO.md twin (`md-merge.py
update-ids`, flock'd), and the full suite is 175 passed / 0 failed / 2 expected-red (unrelated
open items: id:14d0 stub-placement spec). **Overall: PASS.** Do NOT push — parent session
handles it.

## 2026-07-03 — executor (Sonnet) id:ad8a

Worked id:ad8a — added the tag-first-among-trailing lint to `relay/scripts/roadmap-lint.sh`
(the "A" floor of the d259 A→C decision). New `first_lane_tag <line> <strip>` helper mirrors
`classify-repo.sh`'s raw `min()` scan (strip=0) and `gather-repo-state.sh::roadmap_primary_lane`'s
backtick-stripped scan (strip=1, id:1bbd) over the same full lane-tag set ([ROUTINE]/[MECHANICAL]/
[HARD]/hard_lanes/input_lanes). Inside the existing `has_class` block, computes `raw_first` and
`genuine_first` and emits a `WARN` (report-only, exit 0 — no `violations` increment) when they
diverge, naming the ordering ("tag-first-among-trailing … precedes the genuine lane tag …
raw-first=… genuine-first=…") so it stays grep-separable from case-c's "conflict/multiple lane
brackets" wording. `tests/test_roadmap_lint_tag_first.sh` (`# roadmap:ad8a`) is GREEN on all three
fixtures (a: prose-before-genuine flagged; b: plain tag-first not flagged; c: genuine-first with a
later backtick'd mention not flagged).

Case-c backtick-awareness: the handoff/TODO note recommended also stripping backticks before
counting case-c's lane brackets, so the c3f5-compliant shape (genuine tag first, backtick'd
mention later) stops false-positiving as a "conflict". Verified this is NOT safe to add: stripping
backticks collapses `tests/test_roadmap_lint_tagprose.sh`'s own case-c fixture (`[HARD — decision
gate] … actually re-laned to `[HARD — pool]``) to a single bracket too, silencing the genuine
tag/prose ERROR that test requires — both fixtures are structurally identical (genuine tag first,
a *different* tag later in backticks); only the prose semantics differ, which bracket-counting
can't distinguish. Per the reviewer's explicit escape hatch, left case-c's counting untouched
rather than weaken/break `test_roadmap_lint_tagprose.sh`. The c3f5 shape still trips case-c's OLD
"conflict" message as a known, harmless, pre-existing false-positive (different message string,
doesn't collide with the new tag-first diagnostic, outside this test's assertions) — noted in
ROADMAP.md under id:ad8a for a possible future follow-up (likely resolved for good once id:7df1/
d259-C's structural reorder deletes this anchoring reimplementation entirely).

id:ad8a ticked in both ROADMAP.md and its TODO.md twin (`md-merge.py update-ids`, flock'd). Full
suite: 176 passed / 0 failed / 2 expected-red (unrelated open items: id:14d0 stub-placement spec,
id:5884 Fable model gate). **Overall: PASS.** Do NOT push — parent session handles it.

## 2026-07-03 executor: id:9078 — case-c narrowed to BARE lane tags only

RED test `tests/test_roadmap_lint_casec_backtick.sh` (`# roadmap:9078`) confirmed failing before
the change. This closes the false-positive/sign-off note id:ad8a left behind: the owner signed
off on option (a) — narrow case-c's lane count to lanes OUTSIDE backticks, and separately
repoint `test_roadmap_lint_tagprose.sh`'s fixture to a genuine two-bare-tag conflict (done by the
reviewer, not touched here).

Code change in `relay/scripts/roadmap-lint.sh`'s case-c block (~lines 222-244): added
`_bare="$(printf '%s' "$line" | sed -E 's/`[^`]*`//g')"` — the exact backtick-strip idiom already
used by `first_lane_tag`'s `strip=1` branch (id:1bbd/ad8a) — and switched every case-c
`grep -qF '<tag>'` count from the raw `$line` to `$_bare`. The `_lc -gt 1` flag condition and the
id:ad8a tag-first WARN / case-d / grammar clauses were left untouched, only the case-c comment
was updated to describe the bare-only semantics. This is the mechanical dual to id:ad8a's earlier
finding: back then, stripping backticks would have silently broken `test_roadmap_lint_tagprose.sh`
because its fixture wasn't yet a genuine two-bare-tag conflict; now that the reviewer has
repointed that fixture (owner sign-off), the strip is safe.

Verified: `test_roadmap_lint_casec_backtick.sh` GREEN (compliant c3f5 shape — genuine bare tag +
later backtick'd mention — no longer flagged; a genuine two-bare-tag conflict still is).
`test_roadmap_lint_tagprose.sh` still GREEN (its repointed two-bare-tag fixture still flags).
All 5 `test_roadmap_lint*.sh` files GREEN. id:9078 ticked in both ROADMAP.md and its TODO.md twin
(`md-merge.py update-ids`, flock'd). Full suite: 179 passed / 0 failed / 2 expected-red (unrelated
open items: id:14d0 stub-placement spec, id:5884 Fable model gate). **Overall: PASS.** Do NOT
push — parent session handles it.

## 2026-07-06 10:38 — reviewer (opus handoff)

Handoff (id:4b37): authored RED spec tests/test_lane_reorder.sh for the tag-first reorder tool (lane-convert.sh --reorder) + roadmap-lint TAG-NOT-FIRST WARN — d259 endgame (C). Anti-gaming split: spec ONLY, not implemented. 6 adversarial cases (reorder-to-first, multi-tag+INTENSIVE cluster order-preserved, idempotent [ ]/[x]+second-pass, non-lane body bracket preserved, backtick-mention safety + non-checkbox untouched, TAG-NOT-FIRST report-only exit 0). RED now; EXPECTED-RED in suite (179 passed / 0 failed / 3 expected-red). Ready for a Sonnet executor: implement lane-convert.sh --reorder (+ --in-place composition) + the lint WARN to green per executor contract (never weaken/rewrite the test). Ungated; feeds id:7df1 (which then only runs the tool + flips lints to ERROR).

## 2026-07-06 — executor (Sonnet)

Worked id:5884 — `classify-repo.sh`'s `strongRecheckPending` derivation (the `--emit unit` Python
block, ~line 180) was model-blind: it only checked `last_strong_ckpt` set + `fable_rechecked`
false, so a relay.toml entry whose `strong_model` was ALREADY a Fable model (e.g. chidiai's
`claude-fable-5` with a stale `fable_rechecked = false`) elevated a same-tier
Fable-rechecks-Fable review (routed:1c2b). Added a third conjunct: parse `strong_model` from the
toml block (regex mirroring the existing `last_strong_ckpt`/`fable_rechecked` parses), test for a
case-insensitive `"fable"` substring, and AND its negation into `strong_recheck_pending`. When
`strong_model` is absent/empty (legacy entry), the substring test is false, so behavior is
unchanged (conservative default preserved per Acceptance #2). No changes to the `standin`
derivation (id:a42e territory) or any JS-side elevation OR — read-side gate only, as scoped.
`tests/test_classify_repo_fable_model_gate.sh` 3/3 PASS (fable strong_model → pending false;
Opus strong_model → pending true regression guard; absent strong_model → pending true legacy
default). Full suite: 180 passed / 0 failed / 2 expected-red (unrelated open items: id:14d0 stub
placement, id:25aa ckpt-tag anchor). Friction: none — spec was unambiguous and the fix was a
single added conjunct plus its parse. **Overall: PASS.**

## 2026-07-06 10:46 — reviewer (opus)

Review+integrate (id:5884): classify-repo.sh strongRecheckPending is now model-aware — parses relay.toml strong_model, ANDs 'not fable-produced' (case-insensitive) into the pending conjunct so a Fable strong checkpoint never queues a Fable-rechecks-Fable review (routed:1c2b). Conservative default kept (absent strong_model → pending stays true). Executor bc5d8e6; RED test tests/test_classify_repo_fable_model_gate.sh UNCHANGED (verified not gamed); suite 180 passed / 0 failed / 2 expected-red.
Worked id:14d0 — `scan-routed.sh --apply`'s stub write path (`md-merge.py update-ids`) previously
appended every not-found id at EOF, so a `TODO.md` ending in a `## Done` section misfiled brand-new
open `- [ ]` INBOUND stubs under Done (the 2026-07-02 review had to relocate two by hand). Fixed at
the shared write path rather than the caller: `update_ids()` in `meeting/md-merge.py` now anchors
any NOT-FOUND id immediately before the first archive-class heading (`## Done` / `## Archive` /
`## Icebox`, case-insensitive) found in the file; EOF append remains the fallback only when no such
heading exists. Existing-id replacements (the common case — closing an item in place) are completely
untouched, still done in-place at the matched line's original position. Chose the shared md-merge.py
fix over a scan-routed.sh-local anchor because it's the correct default for every update-ids caller
that appends genuinely NEW ids (not just scan-routed) and the flock'd atomic write path stays
exactly as it was — no raw append introduced. Verified `handback-followup.py` (ROADMAP.md,
existing-id-only updates) and `test_md_merge_commit.sh` (existing-id-only fixtures) are unaffected —
neither exercises the not-found/append branch. `tests/test_scan_routed_stub_placement.sh` 3/3 PASS
(stub lands before Done; EOF fallback still works when no Done heading exists). Full suite: 180
passed, 0 failed, 2 expected-red (unrelated open items). id:14d0 ticked in ROADMAP.md.
Friction: none.

## 2026-07-06 10:49 — reviewer (opus)

Review+integrate (id:14d0): meeting/md-merge.py update_ids now anchors brand-new (not-found) ids BEFORE the first archive-class heading (## Done/Archive/Icebox, case-insensitive), EOF append only as fallback — so scan-routed.sh --apply INBOUND stubs never misfile under ## Done. Superset fix at the shared write path; existing-id in-place replacement untouched; other consumers (handback-followup.py, test_md_merge_commit.sh) verified unaffected. Executor 2d3237d; RED test tests/test_scan_routed_stub_placement.sh UNCHANGED (not gamed); suite 181 passed / 0 failed / 1 expected-red.
## 2026-07-06 — executor (sonnet)

Worked id:4b37 — implemented `lane-convert.sh --reorder` (composable with `--in-place`) and
`roadmap-lint.sh`'s TAG-NOT-FIRST WARN to make `tests/test_lane_reorder.sh` green without
touching the RED spec. `--reorder` reuses hard-lanes.md's lane vocabulary (same extraction
idiom as roadmap-lint.sh) to build the recognized tag set, masks backtick-quoted spans with
same-length filler so tag-position search never matches a prose MENTION, finds the leftmost
recognized bare tag via the same `first_lane_tag`-style leftmost-substring scan, then greedily
absorbs an adjacent (whitespace-only-separated) `[INTENSIVE — <res>]` on either side into the
cluster before lifting it after the checkbox and single-space-normalizing the gap. Only
top-level `- [ ]`/`- [x]` lines are touched (matched via a bash regex capturing the checkbox
prefix separately); anything not matching that shape (headings, prose, indented `**Why**`
sub-bullets) passes through byte-for-byte. Idempotency (case c) fell out of the algorithm for
free — no special-casing needed, since an already-first tag's cluster reconstructs to the
identical string. `roadmap-lint.sh` gained a second, independent WARN block right after the
existing id:ad8a split-brain check: it re-checks whether the genuine (backtick-stripped)
primary lane tag is literally the first token after the checkbox (position, not just
leftmost-among-trailing), emitting `TAG-NOT-FIRST` + the item's id on stderr, still exit 0.
Ticked id:4b37 in ROADMAP.md. `bash tests/test_lane_reorder.sh`: all 6 cases PASS. Full suite:
`make test` → 180 passed, 0 failed, 2 expected-red (id:14d0, id:5884 — both pre-existing,
unrelated). Existing `test_lane_convert.sh` and all `test_roadmap_lint*.sh` files re-verified
GREEN (no regressions to the rename-converter or the ad8a split-brain WARN). Friction: none —
the existing arg-parsing in lane-convert.sh needed reshaping from a fixed `if first-arg ==
--in-place` check to a small `while`-based flag loop to accept `--reorder`/`--in-place` in
either order, but that's the only structural change to the pre-existing rename path (its logic
is untouched, just gated behind the new loop). Do NOT push — parent session integrates.

## 2026-07-06 10:52 — reviewer (opus)

Review+integrate (id:4b37): lane-convert.sh gains a --reorder mode (composable with --in-place) that masks backtick spans, finds the leftmost genuine bare lane tag, absorbs an adjacent [INTENSIVE — res] into the cluster, and lifts it to first-position after the checkbox with whitespace normalized (idempotent by reconstruction); existing rename logic untouched, arg parsing reshaped to a flag loop. roadmap-lint.sh gains an independent TAG-NOT-FIRST WARN (report-only, exit 0) firing on tag POSITION — distinct from ad8a's split-brain check; 5 informational warns on the current pre-migration ledger. Executor f851870; RED test tests/test_lane_reorder.sh UNCHANGED (6/6 cases, not gamed); suite 182 passed / 0 failed / 0 expected-red. d259-C endgame tool ready; feeds id:7df1 (run --in-place --reorder + flip lints to ERROR at window-close).

## 2026-07-06 11:00 — reviewer (opus handoff)

Handoff (id:abbd): promoted routed:dc81 inbound stub to ROADMAP [ROUTINE] + authored RED spec tests/test_relay_state_write_toml_quote.sh (relay-state-write toml-set must smart-quote bare string values → valid TOML, idempotent, backward-compatible). Anti-gaming split: spec only, not implemented. RED now; EXPECTED-RED in suite (182 passed / 0 failed / 1 expected-red). Ready for a Sonnet executor.

## 2026-07-06 — executor (sonnet)

Worked id:abbd — implemented smart-quote in `relay/scripts/relay-state-write.sh` `toml-set`: before the value reaches the awk writer, a bash `case`/regex classifies it — already `"..."`-wrapped → verbatim, bare `true`/`false` → verbatim, `^-?[0-9]+(\.[0-9]+)?$` → verbatim (bare number), else wrap in double quotes (bare string, incl. hyphenated words like `handed-off`). Updated the script header comment from "value written VERBATIM — caller supplies quotes" to describe the new smart-quote contract. `status-write`/`event-append` untouched. `tests/test_relay_state_write_toml_quote.sh` now 4/4 PASS (was RED at case a); regression guard `tests/test_relay_state_write.sh` (pre-quoted/bare-bool/bare-int callers) still 11/11 PASS, confirming idempotency. Ticked id:abbd in ROADMAP.md. Full `make test`: 183 passed, 0 failed, 0 expected-red. Friction: none — the fix was a small, self-contained bash case-block inserted between the existing arg-validation and the flock acquisition in `toml-set`, no other subcommand or file touched.

## 2026-07-06 11:06 — reviewer (opus)

Review+integrate (id:abbd): relay-state-write.sh toml-set now smart-quotes the value before the awk write — already-quoted/bare-bool/bare-number left verbatim, any other bare string (incl. hyphenated like handed-off) wrapped in double quotes → always valid TOML, idempotent, backward-compatible. Executor 6024908; RED test tests/test_relay_state_write_toml_quote.sh UNCHANGED (4/4); regression guard test_relay_state_write.sh 11/11 (no double-quoting existing callers); suite 183 passed / 0 failed / 0 expected-red.
## 2026-07-06 — executor (opus HARD-pool)

Worked id:f032 — rewrote `review.md` step 3 from a bare "BDD suites" note into a
run-or-record-skip mandate for EVERY declared test tier (routed:49a0). Step 3 now
requires the reviewer to (a) ENUMERATE the repo's declared tiers from its manifests
(package.json scripts / Makefile targets / CI config), (b) RUN each or RECORD-THE-SKIP
with the reason in both RELAY_LOG.md and the returned summary, and (c) NAME the tiers
actually run in any green claim — banning bare "suites green" from a subset. Aligned
with handoff C3 D2's `unverified` doctrine (§2.4, cited): a tier that did not run is
not a pass. Motivated by isochrone's e2e tier sitting RED for 13 days across 5 reviews
that logged "suites green" while running only unit tiers (playwright silently absent).
Added tests/test_review_tier_enumeration.sh (# roadmap:f032) — a section-scoped WORDING
drift-guard over step 3 asserting the enumerate/record-skip/name-tiers markers + the C3
cross-reference. Friction: none; the mechanical-relane doctrine test was a clean style
template for the section-region guard.

## 2026-07-06 11:09 — reviewer (opus)

Review+integrate (id:f032): review.md step 3 rewritten from bare 'BDD suites' to 'Test tiers — run-or-record-skip for EVERY declared tier' — (a) enumerate declared tiers from package.json/Makefile/CI manifests, (b) run each or RECORD-THE-SKIP with reason in RELAY_LOG + summary (silently-absent tier = unverified, keeps item OPEN), (c) name tiers actually run ('suites green' from a subset BANNED); cites handoff C3 §2.4 unverified doctrine + the isochrone 13-day-RED case. New section-scoped wording guard tests/test_review_tier_enumeration.sh (6 PASS). Opus f032; suite 184 passed / 0 failed / 0 expected-red.
## 2026-07-06 — strong-execute (claude-opus-4-8, HARD-pool)

Worked id:25aa — integrator `-c` anchor for a carries-commits review/recheck branch. The integrate() step 2/3 prompt only carved out the id:8e3e zero-commit case (`-c <reviewedTip>`) and left the carries-commits case to "default (no -c)", but the surrounding id:8e3e reasoning ("anchor on what the child audited, NEVER main HEAD") could be generalized by the sonnet integrator into passing `-c <reviewedTip>` even when the branch carried commits — anchoring the tag BEHIND the `--no-ff` merge and stranding the run's own merged commits outside the audited window (classify-repo then re-dispatches "substantive unaudited commits" forever; observed at zkm-photo routed:37f0 and llm-from-scratch routed:20b2/id:962d). Fix: made step 2 decide `-c` by case explicitly and symmetrically — zero-commit → `-c <reviewedTip>` (unchanged); branch WITH commits → NO `-c` so ckpt-tag's default lands the tag on the post-merge tip that CONTAINS the merge. Added tests/test_integrate_ckpt_merged_tip.sh (`# roadmap:25aa`): a structure check pinning the merged-tip rule wording + a hermetic behavioral fixture (branch with commits → --no-ff merge → default ckpt-tag → tag target contains the merge commit, never the base/branch-tip). Ticked ROADMAP id:25aa and the folded TODO id:962d. Optional ckpt-tag.sh defensive assert SKIPPED — it would need a new CLI param (a second "known integrated tip" arg) for no marginal safety over the computation fix; not gold-plating per the item's explicit guidance. Friction: none — engine edit confined to the integrate() prompt; node --check + template-lint + test_relay_loop_structure.sh all green.

## 2026-07-06 11:14 — reviewer (opus)

Review+integrate (id:25aa, folds TODO 962d): integrate() -c anchor disambiguated — ZERO-COMMIT branch keeps -c reviewedTip (id:8e3e, unchanged); a branch that CARRIED commits (--no-ff merge commit created) now passes NO -c so ckpt-tag defaults to the POST-MERGE tip, keeping the run's own merged commits INSIDE the audited window (fixes the perpetual 'substantive unaudited commits' re-dispatch; carries-commits complement of id:8e3e). Prompt-logic disambiguation in relay-loop.js:1457 (no executable-logic change); new behavioral test tests/test_integrate_ckpt_merged_tip.sh. Opus b191bc0; node --check + template-lint + structure test green; suite 185 passed / 0 failed / 0 expected-red. 962d ticked (llm-from-scratch signature covered).

## 2026-07-06 — strong-execute (claude-opus-4-8, HARD-pool)

Worked id:7633 — first-class single-repo scope for the autonomous pool (`/relay <repo>` / `/relay .` / `--only <repo>`). A single-repo invocation previously still enumerated + fully classified the whole 40+-repo own universe (incl. `# path:` plugins) to dispatch ONE repo, and the `--exclude`-everything-else workaround silently missed `# path:`-relocated repos. Fix (confined to the front-door + engine, per the ENGINE-EDIT CAUTION): the front door maps the bare positional / `.` / `--only` onto `args.onlyRepo` (resolving a bare `.` to the cwd repo basename before launch); relay-loop.js parses it into `ONLY_REPO` and, right after the prelude returns the canonical `relay.toml` own list, resolves it via the new PURE helper `pool-args.mjs::resolveScopeRepo` (byte-identical inline copy in relay-loop.js — the Workflow sandbox cannot import). A confirmed match narrows `scopedOwnRepos` to that one entry BEFORE the exclude-filter + sig-cache + discover fan-out, so only ONE `discover-repo.sh` runs — the per-repo path is REUSED, never forked, and the universe classification is bypassed. An unconfirmed name is a LOUD reject (surfaced, scoped list emptied → no dispatch, no `~/src` guess) — honoring [[feedback-use-existing-tools-not-improvise]] (relay.toml is THE own set). Acceptance #3 VERIFIED and regression-guarded: `--exclude`/`--priority` still validate against the FULL canonical `ownNames` set and drop from the (now possibly scoped) list BEFORE any classification, so an unknown exclude/priority name loud-rejects even under a single-repo scope. **Acceptance #4 DECISION: a bare `/relay .` does NOT route to `/relay next` semantics** — kept deliberately distinct: `.` = the autonomous single-repo POOL (unattended, no `AskUserQuestion`, dispatches the repo's naturally-discovered verdict-class work), whereas `next` = the interactive human-or-not auto-router that can stop for the human via `AskUserQuestion` (which a Workflow cannot call). Conflating them would strip `next`'s human routing or inject a prompt into the unattended Workflow path; the user chooses the verb, the engine never silently swaps. Documented in relay/SKILL.md (launch-args note, config-knob row, new "Single-repo scope" subsection). New test tests/test_relay_single_repo_scope.sh (`# roadmap:7633`): resolveScopeRepo pure cases (confirmed→entry incl. `# path:` path, unconfirmed→LOUD reject no-guess, empty→fail-safe no-op) + structural wiring (inline copy, scope narrows scopedOwnRepos, resolves BEFORE the discover fan-out, unconfirmed empties the list, exclude validates against the full set) + SKILL.md docs — 10/10. Friction: none; the JS-side filter reused discover-repo.sh's per-repo path cleanly with no discovery-prelude refactor (the load-bearing prelude was left untouched; the prelude's cheap relay.toml read is exactly the canonical resolution acceptance #2 requires — the EXPENSIVE per-repo classification fan-out is what's bypassed). node --check + lint-workflow-templates.mjs + test_relay_loop_structure.sh + full `make test` (186 passed / 0 failed / 0 expected-red) all green.

## 2026-07-06 11:27 — reviewer (opus)

Review+integrate (id:7633): first-class single-repo scope. pool-args.mjs gains pure resolveScopeRepo (fail-safe empty→whole-fleet; confirmed name→scoped {repo,path,income}; unconfirmed→LOUD reject, never a ~/src guess); relay-loop.js parses A.onlyRepo→ONLY_REPO + a byte-identical inline copy, narrowing scopedOwnRepos to the single canonical match BEFORE exclude-filter/sig-cache/discover fan-out — the 40-repo universe classification is bypassed, discover-repo.sh's per-repo path reused not forked; --exclude/--priority still validate against the FULL canonical set. Acceptance #4 DECIDED: bare '.' does NOT route to /relay next semantics (kept distinct — /relay .=unattended single-repo pool, /relay next=interactive human-or-not router). SKILL.md documents the arg. Opus bc3368c; node --check + template-lint + structure test green; new test_relay_single_repo_scope.sh 10/10; test_relay_pool_args.sh 18/18 unaffected; suite 186 passed / 0 failed / 0 expected-red.

## 2026-07-06 — Run 70 strong-model audit (id:401c, claude-opus-4-8, HARD-pool)

Recurring strong-model audit (id:401c, RE-OPENED not ticked). **Window:** since Run 69's `8d8d40b` to HEAD `8d0b45a`; the substantive surface is this-session's 2026-07-06 batch — lane-convert `--reorder` + roadmap-lint TAG-NOT-FIRST (id:4b37), classify-repo strong_model fable-gate (id:5884), md-merge archive-heading anchor (id:14d0), relay-state-write toml-set smart-quote (id:abbd), relay-loop integrate `-c` case disambiguation + resolveScopeRepo single-repo scope (id:25aa/7633), review.md step-3 tier enumeration (id:f032).

**Pass-1 code review — 1 HIGH, FIXED INLINE.** `lane-convert.sh`'s `reorder_rest` (right-trim) AND `roadmap-lint.sh`'s TAG-NOT-FIRST (after-checkbox trim) both looped `while [[ "$x" == [[:space:]]* ]]; do x="${x# }"; done` — the guard tests any whitespace but `${x# }` strips only a LITERAL space, so a TAB immediately after the lane tag (lane-convert) or after the checkbox (roadmap-lint) satisfies the guard forever without being consumed → infinite loop. Reproduced both as `timeout` exit 124. Fixed both to `${x#[[:space:]]}` (bracket-expression strip that matches the guard's class); `lane-convert`'s left-trim already used the correct `${left%[[:space:]]}` form (the asymmetry was the tell). Added regression case (g) to `tests/test_lane_reorder.sh` (tab after tag → terminates + still lifts; tab after checkbox → lint terminates). The remaining reorder machinery (backtick masking positions byte-for-byte, leftmost-tag anchoring, INTENSIVE adjacent-before/after cluster lift) is sound.

**Pass-2 security — CLEAN.** toml-set smart-quote wraps a bare string in `"…"`; an embedded-`"`/backslash value would emit invalid TOML, but every caller (ckpt-tag.sh, relay-loop.js prompt) passes only tags / ISO dates / model-ids / bools — no such value is reachable → accepted, not a hole. classify-repo's `strong_model` regex only matches a quoted value; a bare/absent value falls back to the conservative pending=true default (correct). md-merge inserts new stubs before the first archive-class heading via list-splice (no shell surface). resolveScopeRepo's relay-loop.js inline copy is byte-identical to pool-args.mjs's unit-tested pure export (structural test pins them). No injection / path-traversal / secret exposure in the changed scripts.

**Pass-3 design coherence.** d5e0 count prose FIXED INLINE: stale "11 open ROADMAP items after the 2026-07-02 review" → 8 open after the 2026-07-06 batch (ZERO open [ROUTINE] — 5884/14d0/7633/25aa/f032/4b37/abbd all shipped; b50e CLOSED NO-GO 2026-07-04 with forward path id:c79e added; Run 70 note appended to the maintenance-history chain). One finding FILED (id:5dc3, REVIEW_ME box): roadmap-lint's id:c095 heading-as-item detector false-positives on 3 descriptive `## [MECHANICAL]/[ROUTINE]` relay-handoff section headers (ROADMAP ~L2861/2883/2911) whose children are full id'd `[x]` items, not bare status markers — report-only today (both tools exit 0), pre-existing c095 tension surfaced by the in-window headers. orphan-scan --cross-ledger: 0. roadmap-lint: only the 4 expected dual-vocab-window TAG-NOT-FIRST WARNs (report-only) + the 3 c095 false-positives now filed. relay-doctor: report-only — 2 parked orphans (expected) + inbox dead-letter routed:ab31 targeting this repo (SURFACED, not auto-filed: it describes loderite's `npm run version:check`, which this npm-less repo has no manifest for — ambiguous applicability, human routing).

**Suite:** `make test` 186 passed / 0 failed / 0 expected-red (file-count unchanged from baseline — the new regression case (g) lives inside the existing test_lane_reorder.sh, which still passes as one file). Committed in worktree, staged by name. id:401c LEFT OPEN (recurring). Parent integrates — no push / diary / ckpt-tag from this child.

## 2026-07-06 11:44 — reviewer (opus)

Review+integrate Run 70 audit (id:401c, stays open/recurring): HIGH-severity fix — lane-convert.sh reorder_rest + roadmap-lint.sh TAG-NOT-FIRST both infinite-looped on a TAB (guard [[:space:]]* but strip ${x# } only consumes a literal space); fixed both to ${x#[[:space:]]} + regression case (g) in test_lane_reorder.sh (timeout-guarded). Pass-2 security CLEAN; Pass-3 fixed d5e0 count prose inline + filed id:5dc3 (REVIEW_ME: roadmap-lint c095 heading-as-item false-positive on descriptive ## handoff-section headers). Surfaced inbox dead-letter routed:ab31 (ambiguous target — human routing). orphan-scan --cross-ledger 0; suite 186 passed / 0 failed / 0 expected-red. Opus 5ac8c95.

## 2026-07-07 — executor (sonnet)

Worked id:b67e — investigated before building, since the item claimed only the settings.json activation was outstanding for the dropped-file/pathspec-drop guard. Confirmed via diff against HEAD that `hooks/pathspec-drop-guard.py`, its 8-case `tests/test_pathspec_drop_guard.sh`, the `hooks/README.md` PreToolUse doc section, and the `make install-hooks` symlink rule were all already shipped and unchanged (commit 07a061d, 2026-06-29). Checked the live `~/.claude/settings.json` (read-only) and `~/.claude/hooks/pathspec-drop-guard.py`: the symlink exists and the `PreToolUse`→matcher `Bash`→`python3 ~/.claude/hooks/pathspec-drop-guard.py` block is already present and wired — activation had in fact already happened, just never reflected back into TODO.md. No new code was needed; ticked id:b67e `[x]` in TODO.md with a note recording the live-activation verification. `make test`: 186 passed / 0 failed / 0 expected-red (unchanged — no test file added since none of the deliverables needed new code).
Friction: none — this was a stale-TODO-status item, not an unbuilt feature; verified rather than re-implemented to avoid duplicating already-shipped, already-tested work.
Worked id:3558 (Independent-session flock'd merge-to-canonical) — BUILT, not subsumed. Constraint archaeology first: checked `git-lock-push.sh` manifest mode (D5.3/D5.4, id:3e35/id:d00e, already shipped) and `meeting/md-merge.py` — neither closes the gap. Manifest mode's `git add -- <path>` stages whatever content sits on disk for a listed path; it never does a 3-way merge, so two sessions concurrently editing the SAME file in a shared working tree still clobber each other (exactly the TODO item's cited "manifest git add scoops foreign hunks" recurrence). Built `--merge-branch <branch>` mode on `git-diary-workflow/git-lock-push.sh`: an independent session commits in its own git worktree, then this mode `git merge --no-ff`s that branch into the canonical checkout under the same per-repo flock, then continues into the existing pull+push. A genuine conflict aborts the merge and exits non-zero (branch/commit left untouched, nothing pushed) — no silent last-writer-wins, per D5.2's plumbing-CAS rejection. New hermetic test `tests/test_git_lock_push_merge_branch.sh` (9/9): concurrent disjoint-file merges from two worktrees both land + reach the remote (no lost update, lock released after); a genuine same-file conflict on the 2nd merge fails loud, leaves the canonical checkout clean, and preserves the losing branch for manual resolution. Ticked id:3558 `[x]` in TODO.md with the resolution note. Full suite 187 passed / 0 failed / 0 expected-red (up from 186 — the new test file).
Friction: none. One snag during the build — `${commit_msg:-merge: ... (flock'd merge-to-canonical, id:3558)}` broke bash parsing (an unescaped apostrophe inside a `${VAR:-default}` expansion desyncs the parser, same class of gotcha as the broker-curl.sh JSON apostrophe issue in CLAUDE.md) — reworded to "flock-serialized" to drop the apostrophe rather than escaping it. Also note: this session's relay claim (`claim.sh acquire`) returned already-held (mode:"meeting", same session-id prefix, fresh mtime) — treated as self-coordination from the orchestrating session that dispatched this exact task, not a foreign collision, and proceeded per the explicit task assignment.

## 2026-07-07 — executor (sonnet)

Worked id:c79e — Port the 000d/ad74 per-round backstop logic into `classify-verdict.sh` (b50e forward path). Read relay-loop.js's three JS-side runtime guards (000d finished-repo demote, 9973 hard-pool demote, ad74 INTENSIVE promote) and gather-repo-state.sh's derivation of `is_finished`/`top_intensive`/`actionable_routine_open`/`open_hard_pool` to pin down exactly what the two proven-load-bearing fires (b50e's 2026-07-06 NO-GO: 000d ×9 / ad74 ×3 on run relay-20260704-173233-19787) actually guard: a stale/inconsistent `actionable_routine_open`/`open_hard_pool` count disagreeing with the independently-derived `is_finished` flag (zelegator), and an undercounted `top_intensive` that leaves an open `[INTENSIVE]` item unclassified as dispatchable (isochrone). Wrote RED test `tests/test_classify_verdict_backstop.sh` reproducing both fixture shapes plus a dirty-tree regression check, confirmed genuinely RED against the pre-fix script via `git stash`, then made `classify-verdict.sh` fold both natively: (a) `is_finished=true` now forces `actionable_routine`/`open_hard_pool` to 0 before the D3 cascade runs (DEMOTE-only — falls through to promote/surface/idle, never touches those branches); (b) a non-empty `top_intensive` with both counts still at 0 now promotes `actionable_routine` to 1 (PROMOTE-only — lets the existing cascade reach `execute` with the `intensive` field riding it). Per the task's explicit instruction and the b50e NO-GO doctrine, the JS-side id:000d/9973/ad74 runtime guards in relay-loop.js are UNCHANGED — kept as belt-and-suspenders; their deletion stays separately gated (re-opens id:b50e) on a forward window proving 0 fires with this native fold live. Ticked id:c79e `[x]` in both TODO.md and ROADMAP.md (single-id-two-views). Full suite: 188 passed / 0 failed / 0 expected-red (up from 187 — one new test file).
Friction: id:c79e is tagged `[HARD — pool]`, normally reviewer-only per the executor contract's scope rule — proceeded anyway per this session's explicit task assignment (which already carried the RED-spec authoring + implementation instructions a `/relay handoff` would normally produce), same self-coordination read as the prior session's claim note.

## 2026-07-07 — executor (sonnet) id:9d97

Worked id:9d97 — built the mechanical discovery producer per the 2026-07-07 meeting decision
D2 (docs/meeting-notes/2026-07-07-1228-relay-discovery-off-workflow.md): the Workflow's
discover-run shard was a Haiku agent() whose only job is "exec discover-repo.sh + echo the
JSON verbatim" — pure transport, but observed to mangle even that; the doctrine is "no LLM
if mechanical can do as good or better." Built `relay/scripts/discover-repos-mechanical.sh`,
which enumerates confirmed own repos from relay.toml via the SAME `own_repos()` parser
already used by relay-doctor.sh/relay-reconcile.sh/gather-human-backlog.sh (honors `# path:`
overrides + `paused`), execs `discover-repo.sh` (id:64b4) verbatim per repo — zero LLM, no
`claude -p`, no `agent()` anywhere in the script — and assembles a schema-checked aggregate
{schema_version, generated_at, run_id, repos[], units[], surfaced[], skipped[]} written
atomically (tmp+mv) to both a timestamped `queue-<tag>.json` and a stable `latest.json`.

Drop-dir decision: CHECKED whether the 2026-07-02 daemon topology (id:64d3/b3d0,
`~/.config/relay/recipes/{pending,running,done}`) was buildable-into — it IS built
(`mechanical-daemon.sh`, `recipe-validate.sh`), but its schema is a flat
{id,repo,cmd,host,est_wall,resource,acceptance_artifact} object describing ONE EXECUTABLE
command the daemon runs; a discovery snapshot is an ARRAY of per-repo classification
verdicts to be READ, not executed — folding it into the recipe schema would be a category
error, not reuse. Defined a NEW sibling drop-dir `~/.config/relay/discovery-queue/`
(RELAY_DISCOVERY_QUEUE_DIR override for hermetic tests) and documented its schema in a new
`relay/references/discovery-queue-manifest.md` mirroring recipe-manifest.md's structure,
explicitly noting the non-reuse rationale so a future reader doesn't rediscover the same
question. Noting the dependency per the task brief: id:7402 (wiring the executor prelude to
actually consume this queue, and labeling the residual agent() bridge-read as the known-
remaining LLM surface) and id:54fc (extending the run-heartbeat to this timer as a second
liveness domain) are both still open, gated on this item, and were NOT built here.

Shipped the `--user` systemd pair `tools/discover-repos-mechanical.{service,timer}` (mirrors
quota-sample.sh's oneshot+timer pattern, 15-min cadence) and a `make install-discovery-timer`
/`status-`/`uninstall-` target trio mirroring install-quota-timer/install-relay-watchdog.
Per the task's conservative-AFK instruction, did NOT run `make install-discovery-timer`
myself — the unit files + Makefile target are built and manually verified (`make help`
lists the target; Makefile parses), but activation (`systemctl --user enable --now`) is left
as a deliberate step for the user to run when ready.

Test: `tests/test_discover_repos_mechanical.sh` (no `# roadmap:9d97` header — TODO.md has
the id but no matching ROADMAP.md item, so expected-red semantics don't apply; failures
always count). Two properties pinned: (1) schema validity — latest.json parses and matches
the documented top-level shape across a 3-repo fixture set (execute/idle/dirty-blocked);
(2) determinism parity — for each repo that reaches classification (r_exec, r_idle; r_dirty
is routed to "surfaced" by discover-repo.sh's own reconcile step before any unit exists),
the unit embedded in the aggregate is content-identical (json.dumps(sort_keys=True) equality)
to a fresh direct discover-repo.sh call for the same repo/path/runid — this is the strongest
meaningful form of "byte match" for an aggregated multi-repo file (literal byte-identity of
the whole aggregate vs. a single-repo call's raw text isn't a coherent comparison once
multiple repos' JSON is folded into one array). Both assertions pass. Manually smoke-tested
the script end-to-end against a 2-repo fixture before writing the formal test.

Ticked id:9d97 `[x]` in TODO.md with a shipped note recording the drop-dir decision and the
built-not-enabled unit. Full suite: `make test` 190 passed / 0 failed / 0 expected-red (up
from 188 — one new test file; test_resource_claim_pid.sh, flagged flaky in project memory,
passed cleanly this run).
Friction: none — the recipe-manifest-vs-discovery-queue schema mismatch was the one
substantive judgment call (documented above and in discovery-queue-manifest.md's "why this
is a NEW drop-dir" section) rather than a genuine blocker.

## 2026-07-07 — executor (sonnet) id:7402

Worked id:7402 (D3, gated on id:9d97 which had already landed) — wired the relay discovery
runner's agent() recipe (relay-loop.js `runnerPrompt`, ~line 890) to prefer the id:9d97
mechanical work-queue over the live discover-repo.sh exec. The Workflow sandbox has no
fs/net/subprocess (id:2ec4), so "consume the queue" cannot be JS-side fs access — the ONLY
lever is the recipe text the discover-run agent() call executes. Added STEP 0 to the recipe:
run `find ~/.config/relay/discovery-queue/latest.json -newermt "@$(date +%s - 1200)"` (TTL =
1200s = the id:9d97 .timer's 15min cadence + a 5min buffer for one slow/missed tick); if it
prints the path (fresh), `cat` the queue once per chunk and copy each repo's
units/surfaced/skipped verbatim out of it (no re-derivation) instead of running
discover-repo.sh; if empty (missing/stale — the id:9d97 .timer ships DISABLED by default, so
this is the out-of-the-box case), fall back to the pre-existing live discover-repo.sh exec
path byte-for-byte unchanged. Confirmed non-breaking: with the timer off (the shipped
default), the queue file never exists, so every live pool run today takes the same fallback
branch it always has.

Per D3 + no-silent-swallow: the queue-cat step is explicitly labeled "RESIDUAL LLM SURFACE
(id:7402/D3)" inline in the recipe text (so the LLM running it sees the label, not just a
code comment), and a `log()` line fires at dispatch time every round a runner agent is
dispatched, surfacing the same "id:7402 discover-run agent() dispatch ... residual LLM
surface" wording into the round log the operator can tail — it does not read as "fully
mechanized," per the meeting note's D3/Orla concern.

Test: `tests/test_discovery_queue_consume.sh` (no `# roadmap:7402` header — TODO-only item,
no matching ROADMAP.md entry per D3's own gating note; failures always count). Structural
(mirrors test_relay_discover_shard.sh's pattern — live discovery is unrunnable hermetically):
asserts (a) the recipe references the queue dir + latest.json + a freshness/TTL check
(newermt), (b) the live discover-repo.sh fallback path text is still present verbatim, (c) the
residual-read label string + its id:7402/D3 pointer + the round-log line are all present.

Ticked id:7402 `[x]` in TODO.md with a shipped note. Full suite: `make test` 191 passed / 0
failed / 0 expected-red (up from 190 — one new test file).
Friction: none — the design was already fully specified by the meeting note and the
discovery-queue-manifest.md schema doc; the only judgment call was the TTL value (1200s),
chosen conservatively (cadence+buffer) rather than measured, since id:9d97's timer isn't
enabled anywhere yet to observe real producer latency.
## 2026-07-07 — executor (opus)

Worked id:54fc — extended the run-heartbeat (id:e149) to cover the mechanical discovery
producer's `.timer` (id:9d97) as a SECOND, independent liveness domain, per the 2026-07-07
meeting's Item 3 forward-flag (docs/meeting-notes/2026-07-07-1228-relay-discovery-off-workflow.md).
`relay/scripts/discover-repos-mechanical.sh` now calls `heartbeat.sh beat` with a fixed
runId (`discovery-producer`, override via `DISCOVERY_PRODUCER_RUN_ID`) after a successful
write, reusing the exact same marker format/location (`HEARTBEAT_BASE`) as the dispatch
loop's per-round `relay-*` runIds — beat failures are logged but non-fatal, never blocking
the actual discovery write. `tools/relay-watchdog.sh` was restructured to check TWO domains
per tick instead of early-exiting after the dispatch-loop check: the existing dispatch-loop
dead-runs logic is unchanged in behavior, and a new second block checks the producer marker
via `heartbeat.sh status <runId>` with its OWN TTL (`RELAY_WATCHDOG_PRODUCER_TTL`, default
2100s = the timer's 15-min cadence ×2 + a missed-run buffer), its own de-dup state file
(`$RELAY_WATCHDOG_STATE.producer`), and its own evidence-log domain tag
(`domain:"discovery-producer"`), notifying "⚠️ Discovery producer stale/down" — a message
distinct from the dispatch domain's "⚠️ Relay loop died" so an operator can tell "discovery
is down" apart from "the pool is just idle / no work." Only a PRESENT-but-STALE producer
marker triggers a report (mirrors dead-runs' own present-but-stale semantics); a marker that
has never been beaten (producer never run yet) is silently not-reported, same as the
dispatch domain's absent-marker handling. Purely observe/notify — no systemd unit installed
or enabled (conservative AFK default), no repo/timer touched.

New hermetic test `tests/test_discovery_producer_heartbeat.sh` (no `# roadmap:` header —
id:54fc has no matching ROADMAP.md item) pins: (a) a successful producer run creates/beats
its own heartbeat marker; (b) a marker aged past `RELAY_WATCHDOG_PRODUCER_TTL` makes the
watchdog report the producer-down condition distinctly (asserts the message text AND that
it does NOT bleed into the generic "Relay loop died" string, plus the evidence JSON's
`domain` tag) with de-dup on a repeat tick; (c) a fresh marker produces no report. Also
added `HEARTBEAT_BASE`/`HEARTBEAT_LOG` overrides to the existing
`tests/test_discover_repos_mechanical.sh` fixture env — the new heartbeat-beat call would
otherwise have written to the real `~/.config/relay/heartbeats` during that test, breaking
hermeticity (not a test-integrity weakening, purely isolating a new side effect the producer
now has). Full suite: `make test` 191 passed / 0 failed / 0 expected-red (up from 190).
Friction: none — relay-loop.js (the dispatch loop's own heartbeat.sh call sites) was
deliberately left untouched per the task brief, to avoid a merge conflict with a parallel
executor working that file.

## 2026-07-07 — executor (opus)

Fixed a CONFIRMED DATA-LOSS bug in the mechanical discovery producer (audit finding against
id:9d97). `discover-repos-mechanical.sh` is documented as a READ-ONLY verdict snapshot, but it
called `discover-repo.sh` which composes `reconcile-repo.sh` — bounded SIDE-EFFECTING git
(fetch, ff-merge, uv.lock commit, and worktree reap/park = `git worktree remove --force` +
branch rename). The producer's systemd `.service` passes NEITHER `--live-claims` NOR `--runid`,
so `live_claims=""` → every executor worktree looked stale → the 15-min timer would force-remove
a LIVE executor's worktree (destroying uncommitted work) and rename its branch.

Fix (audit option (a), classify-only): added an ADDITIVE `--no-reconcile` flag to
`discover-repo.sh` that SKIPS `reconcile-repo.sh` entirely and runs only the side-effect-free
classify path (`classify-repo.sh --emit unit`); the producer now passes `--no-reconcile`. The
LIVE dispatch loop (`relay-loop.js:914`) NEVER sets the flag, so its reconcile+reap is
byte-for-byte unchanged — it still protects in-flight worktrees via `--live-claims`/`--runid`
and reconciles at actual dispatch. Updated `discovery-queue-manifest.md` + the producer header
so "read-only snapshot" is now TRUE. New RED test `tests/test_discovery_producer_readonly.sh`
builds a fixture repo with a pre-existing unmerged worktree+branch (mimicking a live executor)
and asserts (a) worktree+branch survive, (b) HEAD/reflog/branch-tip unchanged (no
fetch/ff-merge/commit), (c) a schema-valid snapshot is still emitted — it failed against the
old code (worktree force-removed) and passes after the fix. Existing
`test_discover_repos_mechanical.sh` still green (clean fixtures → reconcile was a no-op there
anyway, units identical).
Friction: none.
## 2026-07-07 — executor (sonnet)

Worked 4 independent remediations from strong-model audit run 70 (findings 2/test-bug/3/4),
scoped away from `relay/scripts/discover-repo.sh`, `reconcile-repo.sh`,
`discover-repos-mechanical.sh` per the task brief (a parallel executor owned those).

1. **Cross-domain alarm suppression (audit finding 2)**: `heartbeat.sh reap` archived
   EVERY present-but-stale marker unscoped, including the fixed `discovery-producer`
   runId (id:54fc) — so a dispatch-loop restart's auto-reconcile-on-restart
   (`relay-loop.js:1896`) silently cleared the producer's own down-alarm on every
   restart, even when the producer really was dead. Fixed by adding an optional
   `reap [--prefix GLOB]` scope to `heartbeat.sh` (matches the marker's `runId` field
   against a shell glob; omitted = old unscoped behavior, back-compat preserved) and
   updating `relay-loop.js`'s auto-reconcile-on-restart call to pass
   `--prefix 'relay-*'` (the dispatch loop's own runId namespace,
   `relay-<ts>-<rand>`), so the discovery-producer marker is never swept by a
   dispatch-loop restart. Extended `tests/test_discovery_producer_heartbeat.sh` with a
   new case (d): backdates both a producer marker and a `relay-*` marker past the
   default reap TTL, then asserts a `--prefix 'relay-*'` reap archives the `relay-*`
   marker but leaves the producer marker untouched. Verified genuinely red against the
   unscoped behavior (temporarily stripped the filter, confirmed FAIL) before
   restoring the fix.
2. **`test_classify_verdict_backstop.sh` fixture-key bug**: all 4 fixtures set
   `roadmap_actionable_open` while `classify-verdict.sh:51` reads
   `actionable_routine_open`, so the key was silently ignored (falls back to
   `has_routine`) and the "STALE nonzero actionable_routine_open -> demote via
   is_finished" scenario (id:c79e guard-a) was never actually exercised — the test
   passed by fallback luck, not by testing the real guard. Fixed the fixture keys to
   `actionable_routine_open`. Verified: temporarily disabled the `if is_finished:`
   demote block in `classify-verdict.sh`, confirmed the test now correctly FAILs
   (`FAIL (a): is_finished=true must never yield verdict=execute`), then restored it.
3. **`orphan-scan.sh --shipped` gate-word substring false-positives (audit finding 3)**:
   `completion_re`/`wait_re` matched as unanchored substrings, so "gated" fired inside
   investi-gated/aggre-gated/dele-gated, "observe" inside observe-d, etc.,
   misclassifying ordinary prose as EXTERNAL-WAIT/COMPLETION-pending. Anchored both
   regexes with `\b(...)\b`. Added case 8 to `tests/test_orphan_scan_shipped.sh`: an
   item containing "investigated" (false gate substring) with a green
   roadmap-owned test must classify TICK-READY, not be suppressed. Verified red
   against the unanchored regex (case8 disappeared, only unrelated cases printed),
   then restored the fix.
4. **`orphan-scan.sh --shipped` unbounded TICK-READY test execution (audit finding
   4)**: the discovered test ran via plain `bash "$test_rel"` with no timeout, so a
   hung/non-hermetic test could hang the advisory scan indefinitely. Wrapped in
   `timeout "${ORPHAN_SCAN_TEST_TIMEOUT_S:-60}s" bash "$test_rel"` (overridable via
   env, default 60s; a timeout is treated as non-green, same as a genuine failure —
   never TICK-READY). Added case 9 to `tests/test_orphan_scan_shipped.sh`: a
   `sleep 300` test with `ORPHAN_SCAN_TEST_TIMEOUT_S=2` must not be TICK-READY and the
   whole scan must finish in well under 15s. Verified red (reverted the `timeout`
   wrapper, script hung past an outer 15s bound and was killed, rc=124), then
   restored the fix.

Full suite: `make test` 192 passed / 0 failed / 0 expected-red. Friction: none — all 4
fixes landed cleanly in one session, each independently verified red-then-green before
being restored to the passing state.

## 2026-07-07 — executor (sonnet)

Worked id:e3ad — defense-in-depth CLASS fix for `reconcile-repo.sh`'s worktree
reap/park logic: it now distinguishes THREE cases instead of two. Previously
`--live-claims` defaulted to `""`, so a caller that PASSED `--live-claims ""`
(explicit "nothing is live") and a caller that never passed `--live-claims` at
all were indistinguishable — both hit the fail-OPEN reap path. Added
`live_claims_provided` (set to 1 only inside the `--live-claims)` arg-parse
branch, i.e. only when the flag is actually seen on argv) so the three cases
are: (1) flag present with a value → reap repos not in the CSV (unchanged);
(2) flag present but explicitly empty → reap permitted (unchanged, this is the
legit "nothing live" case, e.g. `test_reconcile_repo.sh` case 4/5); (3) flag
ABSENT entirely → REFUSE every reap/park in that repo, emit a loud
`WARNING:` on stderr plus a `surfaced` JSON entry naming the missing
`--live-claims` context, and leave the worktree/branch untouched. Verified the
LIVE loop is unaffected: `relay-loop.js:914` always renders `--live-claims
"${liveClaimsCsv}"` (a template literal, so the flag is present even when the
CSV is empty) when it calls `discover-repo.sh`, which unconditionally forwards
`--live-claims "$live_claims"` to `reconcile-repo.sh` — so the live dispatch
path only ever hits case (1) or (2), never (3); this is purely an additive
guard against a *future or alternate* caller that forgets the flag (exactly
the class of bug the empty-CSV producer incident, logged above, was an
instance of).

New RED test `tests/test_reconcile_failclosed_reap.sh` (hermetic, no
`# roadmap:` header — defect-fix hardening, not a queued ROADMAP item):
(a) invoking with NO `--live-claims`/`--runid` at all → worktree dir and
`relay/<bn>` branch both survive, no `reap`/`park` action in the JSON, and a
stderr warning naming `--live-claims` is emitted — FAILED against the
pre-fix code (worktree was force-removed) and PASSES after the fix; (b)
invoking with explicit `--live-claims ""` → reap still happens (proves the
guard didn't over-restrict the legitimate empty case); (c) invoking with
`--live-claims "<repo>"` naming the repo → worktree survives, surfaced as
in-flight-elsewhere (existing id:ebfb protection intact). All three pass; full
`make test` is green (194 passed, 0 failed, 0 expected-red).
Friction: none.

## 2026-07-07 — executor (sonnet)

Worked id:1bd1 — added the LOUD, report-only `mechanical-orphan` check to
`relay-doctor.sh` (a 12th check, `relay/scripts/relay-doctor.sh:377-437`, run
inside `check_repo` right after the last_ckpt check). handoff.md:77-92 warns
that tagging a ROADMAP item `[MECHANICAL]` routes it to the pool-inert
`mechanical` verdict, but nothing runs it until an A2 recipe is authored into
`~/.config/relay/recipes/pending/` — and there was no detector for the case
where that authoring never happened (or the recipe was lost). The new check
scans every OPEN `- [ ]` ROADMAP item tagged `[MECHANICAL]`, pulls its
`<!-- id:XXXX -->` token, and cross-references it against the top-level `id`
field of every recipe JSON in `$RELAY_RECIPE_DIR/{pending,running,done}/`
(recipe-manifest.md's `id` field is the schema's only explicit id-linkage —
NOT filename, which is unconstrained; a recipe already consumed into `done/`
still counts as "fed"). An unfed item prints
`⚠️ [MECHANICAL] item id:XXXX has no authored recipe in .../{pending,running,done} — it will never run (author its A2 recipe per handoff.md).`
and increments `repo_issues`, so it participates in the existing report-only
default / `--strict` escalation exactly like every other check — no new flag,
no new exit-code path. `$RELAY_RECIPE_DIR` is honored (same env var
`mechanical-daemon.sh` already reads) so the RED test is fully hermetic
(mktemp -d recipe root, mktemp -d git repo, no `~/.config/relay`, no network).

New RED test `tests/test_mechanical_orphan.sh` (`# roadmap:1bd1` — no such
open ROADMAP item exists so the header is purely documentary; the test
passes outright, so expected-red semantics never engage). Four fixture items:
(a) open `[MECHANICAL]`, no recipe anywhere → reported; (b) open
`[MECHANICAL]` with its recipe sitting in `done/` → not reported; (c) closed
`[x]` `[MECHANICAL]`, no recipe → not reported; (d) open `[ROUTINE]` (not
`[MECHANICAL]`), no recipe → not reported. Plus two cross-cutting assertions:
report-only stays exit-0 despite the (a) finding, and `--strict` turns that
same finding into a nonzero exit. Verified RED against the pre-change script
(no `mechanical-orphan` section at all, so grep for it failed first), then
GREEN after the implementation — all 6 assertions pass. Full `make test` is
green (196 passed, 0 failed, 0 expected-red).
Friction: none — recipe-manifest.md's `id` field was an unambiguous, already-
documented linkage, no guessing required.
## 2026-07-07 — handoff (fable)

Scoped Fable-tier handoff pass (RED specs only, no C1/C4): surveyed the open backlog
via `unpromoted-scan.sh` (60 findings: 2 promote / 48 surface / 9 laned / 1 untracked)
+ the ROADMAP open set (6 items, all HARD/gated/human-lane — 0 open [ROUTINE]).
Handed off the ENTIRE genuinely-executor-ready set, which is exactly 2 items:
- id:758e purity-test-as-contract — RED `tests/test_purity_helper.sh` specs a shared
  `tests/lib/assert-repo-unchanged.sh` (snapshot + byte-identical assert, loud stderr
  drift) generalizing `test_discovery_producer_readonly.sh`, plus a documented
  convention note in executor-contract.md (no-bump call boxed in REVIEW_ME).
- id:bf7a relay-gap-sample hardening — `tests/test_gap_sample_install.sh`: the hermetic
  behavior spec half (stubbed RELAY_SCRIPTS; change/tick/ERROR lines) PASSES today
  (regression guard for the test-lessly shipped logger); the RED half is the missing
  `make install-gap-sample`/`uninstall-gap-sample` targets + SKILL.md doc line.
Deliberately NOT handed off: id:f599 (echo-runner adoption — [HARD — pool]
measure-then-decide, an adopt-or-reject endpoint can't be a red test without
pre-deciding it, and it edits relay-loop.js, the a0b6 template-lint hazard class);
the 48 surface items (lane decisions belong to the human-verdict mechanical filer,
id:5eb3); the 9 laned human/meeting items + the untracked [HARD — meeting] umbrella
heading (meeting lane); all gated items. Honest read: the backlog is design-heavy and
THIN on executor work — 2 real handoffs is the whole crop, not a shortfall.
Stayed out of relay-doctor.sh / tests/test_mechanical_orphan.sh (parallel executor
mid-flight). `make test`: 194 passed, 0 failed, 2 expected-red.
Friction: unpromoted-scan's persisted-output truncation initially hid id:758e from the
promote set — re-ran filtered; scan itself is correct.

## 2026-07-07 — executor (sonnet)

Worked two CONFIRMED Fable-tier review findings (defect fixes, no roadmap id — both
pre-existing scripts). Finding 3: `relay/scripts/classify-verdict.sh`'s id:c79e fold (b)
(top_intensive native promote) could resurrect the exact state fold (a) (is_finished
authority) just demoted — a finished repo with a stale top_intensive + stale nonzero
counts would zero the counts (fold a) then fold (b) would see top_intensive set + zero
counts and promote to verdict=execute. Fixed by guarding fold (b) with `and not
is_finished`; added a COMBINED fixture to test_classify_verdict_backstop.sh that
verified FAIL pre-fix (verdict resurrected to execute) and PASS post-fix (falls through
to handoff). Finding 4: `git-diary-workflow/git-lock-push.sh`'s `--merge-branch` mode
without an explicit `--ff-only` fell through to the rebase-pull path, which flattens the
just-created `--no-ff` merge commit on remote divergence. Fixed by making
`--merge-branch` mode imply `ff_only=1`, and by erroring loudly (instead of silently
degrading to legacy mode) when `--merge-branch` is passed with no following branch-name
value. Extended test_git_lock_push_merge_branch.sh with a remote-ahead scenario
(confirmed the merge commit is now a surviving 2-parent commit, not pushed, no
force-push) and a missing-value scenario (confirmed nonzero exit + error message);
both new cases verified FAIL pre-fix / PASS post-fix. `make test`: 195 passed, 0 failed,
2 expected-red (open, unrelated roadmap items).
## 2026-07-07 — executor (opus)

Fixed two CONFIRMED HIGH findings from the Fable-tier second-opinion review of the
mechanical discovery loop (id:9d97/7402/54fc).

FINDING 1 (fresh-queue path dropped reconcile side-effects): the discover-run recipe's
STEP 0, on a FRESH mechanical queue, only `cat latest.json` + copied the verdict and
NEVER ran reconcile-repo.sh that round — so ff-merge (id:c3f7), uv.lock cascade commit
(id:bae5), worktree reap/park + orphan suppress-redispatch (id:1f53/ebfb) and live-claims
filtering silently stopped happening on the queue path. Chose the clean split (Fable's
recommended shape, not the freshness-gate fallback): CASE A now runs reconcile-repo.sh
LIVE per repo (with --live-claims + --runid) for the side-effecting half and takes ONLY
the deterministic CLASSIFY verdict from the queue, mirroring discover-repo.sh's
surfaced-non-empty→stop routing; CASE B (no fresh queue) is the unchanged full live
discover-repo.sh exec. This also restores live-claims protection the queue never carried.
Corrected the THREE false "still runs full reconcile byte-for-byte" contract texts
(discover-repos-mechanical.sh header + inline dup, discovery-queue-manifest.md, and the
relay-loop.js:1513 integrator "discovery already fast-forwarded" comment) to state the
true reconcile-live/classify-from-queue split. Structural test: test_discovery_queue_consume.sh
(d) asserts reconcile-repo.sh --repo is invoked with --live-claims on the queue path.

FINDING 2 (dead-runs unscoped → spurious producer alarms): heartbeat.sh `dead-runs` swept
HEARTBEAT_BASE with no namespace filter, so the discovery-producer marker (2100s domain-2
TTL) aged past heartbeat's 3600s default and tripped domain-1 — a bogus "Relay loop died:
discovery-producer" and a relay-reconcile --all --auto on EVERY restart. Gave dead-runs the
same optional `--prefix GLOB` filter reap already has and passed `--prefix 'relay-*'` at both
consumers (relay-watchdog.sh domain-1 + relay-loop.js:1893 auto-reconcile-on-restart).
test_discovery_producer_heartbeat.sh (e) asserts an aged producer marker is absent from
`dead-runs --prefix 'relay-*'` while domain-2 (`--prefix 'discovery-*'`) and the unscoped
default still see it.

`make test`: 195 passed, 0 failed, 2 expected-red.
Friction: none.

## 2026-07-08 — executor (sonnet)

Worked id:bf7a and id:758e — both open [ROUTINE] items closed in one session.

id:bf7a: added `install-gap-sample`/`status-gap-sample`/`uninstall-gap-sample` Makefile
targets mirroring `install-quota-timer`'s systemd-user pattern exactly (symlink
`tools/relay-gap-sample.{service,timer}` into `$(SYSTEMD_USER)`, daemon-reload,
enable --now; uninstall disables + removes symlinks), plus a `tools/relay-gap-sample.sh`
doc line in `relay/SKILL.md` §Shared resources. `tests/test_gap_sample_install.sh`
(roadmap:bf7a) was already-passing on its behavior-spec half; the RED install-plumbing
half now passes too.

id:758e: added `tests/lib/assert-repo-unchanged.sh` (`repo_state_snapshot` +
`assert_repo_unchanged`), generalizing the inline pattern
`tests/test_discovery_producer_readonly.sh` proved against a real near-miss into a
shared, sourceable helper. Documented the convention as a new
`### Purity-test-as-contract` note in `relay/references/executor-contract.md`, additive
only — did NOT bump the v6 contract marker per the item's explicit design (recorded here
for the reviewer to overrule if warranted). `tests/test_purity_helper.sh`
(roadmap:758e) green.

`make test`: 201 passed, 0 failed, 0 expected-red.
Friction: none.

## 2026-07-08 16:40 — executor (sonnet, relay-loop)

Closed both open [ROUTINE] items: id:bf7a (relay-gap-sample Makefile install/status/uninstall targets + SKILL.md doc line) and id:758e (shared tests/lib/assert-repo-unchanged.sh purity-test helper + executor-contract.md convention note); full suite 201 passed, 0 failed, 0 expected-red. [id:bf7a,758e]

## 2026-07-08 17:03 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

Verified id:bf7a + id:758e green (gaming-scan clean, suite 201/201); ticked TODO twins, upheld no-bump verdict [id:bf7a,758e]

## 2026-07-08 17:19 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

handoff C2/C3: promoted id:356f (classify-repo gated-section actionable_routine_open fix) to ROADMAP + RED test [id:356f,4299]

## 2026-07-08 — executor (sonnet)

Worked id:356f — added whole-section gating to classify-repo.sh's ROADMAP-derivation loop, mirroring roadmap-lint.sh's is_exempt_heading regex (gated|deferred|done|icebox|archive|parked, case-insensitive). While inside such a section, open [ROUTINE]/[HARD — pool]/[MECHANICAL] lines no longer increment actionable_routine_open / roadmap_actionable_open / open_mechanical (roadmap_open's raw total count is left untouched — the acceptance criteria only named the three actionable counters). tests/test_classify_repo_gated_section.sh (roadmap:356f) now green (8/8); full make test: 202 passed, 0 failed, 0 expected-red.
Friction: none.

## 2026-07-08 17:31 — executor (sonnet, relay-loop)

Fixed classify-repo.sh to whole-section-gate actionable_routine_open/roadmap_actionable_open/open_mechanical, mirroring roadmap-lint.sh's is_exempt_heading (id:356f); full suite 202/0/0. [id:356f]

## 2026-07-08 17:48 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

Verified id:356f genuinely green (gaming-scan clean, RED spec unchanged since handoff & passing, suite 202/0/0); ticked TODO twin; surfaced installed-tree-stale REVIEW_ME box [id:356f]

## 2026-07-08 18:08 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

Handoff C1-C4: promoted 3 TODO items to ROADMAP (7725/aec5 [ROUTINE]+red specs, f599 [HARD]); suite 202 pass / 2 expected-red [id:7725,aec5,f599]

## 2026-07-08 — executor (sonnet)

Worked id:7725 — added a `reap-run <runId>` subcommand to `relay/scripts/heartbeat.sh` that archives one named run's marker to `heartbeats.done` REGARDLESS of TTL staleness (mirrors `stop`, but logs a distinct `reap-run run=<id> reason=observed-dead` line), plus header doc + usage-list entries. `tests/test_heartbeat_reap_run.sh` (roadmap:7725) now green. Wired site (2) — the auto-reconcile-on-restart handler in `relay-loop.js` (~line 1971) — to call `heartbeat.sh reap-run` on each specific runId `dead-runs` reports, BEFORE falling back to the blanket TTL `reap --prefix` sweep, so a promptly-reconciled crash's marker is archived immediately instead of lingering under-TTL until it later trips the watchdog (the exact id:7725 failure mode). `node --check` + `lint-workflow-templates.mjs` clean on the edited template. Site (1) ("the front-door/observer path that catches a relay-loop.js Workflow reject") has no concrete in-repo anchor today — no script/file in this repo implements a Workflow-reject observer distinct from the front-door SKILL.md prose — so it is left unwired; flagging this gap for the reviewer rather than inventing a mechanism. Full `make test`: 203 passed, 0 failed, 1 expected-red (aec5, open).
Friction: none on the shipped part; site (1) wiring deferred as described above (not a size-out — the ticket's core deliverable, the reap-run subcommand + its clearest concrete wiring point, is done and green).

## 2026-07-08 18:26 — executor (sonnet, relay-loop)

Added heartbeat.sh reap-run subcommand + wired it into relay-loop.js auto-reconcile-on-restart (id:7725); full suite 203/0/1-expected-red [id:7725]

## 2026-07-08 — executor (sonnet, relay-loop)

Worked id:aec5 — authored `tests/fixtures/loop-round-exec-harness.mjs`, a full-round executable smoke harness that mirrors `discovery-exec-harness.mjs`'s stub-globals technique but drives one entire self-feeding-loop round (bounded via `args.once = true`) with a stubbed discovery seeding one unit of each pool-dispatchable non-hard verdict (execute/review/handoff). This reaches and evaluates every non-discovery inline prompt-builder template — the per-verdict unit dispatch (`execute:`/`review:`/`handoff:` labels), the quota gate (`quota:`), the serialized integrate (`integrate:`), the mid-round inject-take (`inject-take`), and the auto-reconcile-on-restart check (`auto-reconcile-restart`) — none of which the discovery-only harness exercises. Adjusted `tests/test_relay_loop_all_builders_exec.sh`'s builder-name list to the real `agent()` label prefixes per the item's own reconciliation note (labels are `${verdict}:${repo}` etc., not literal `execute-child`/`review-child`/`handoff-child`; the harness's stub maps them to the test's required builder names). No `hard` unit seeded — the item's acceptance list names only the 7 builders above, not a hard-child. Full `make test`: 204 passed, 0 failed, 0 expected-red.
Friction: none.

## 2026-07-08 18:40 — executor (sonnet, relay-loop)

Added tests/fixtures/loop-round-exec-harness.mjs — a full-round exec-smoke harness generalizing the discovery-only guard to every relay-loop.js prompt builder (execute/review/handoff dispatch, integrate, quota, inject-take, auto-reconcile); id:aec5 closed, full suite 204/0/0. [id:aec5]

## 2026-07-08 19:25 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: verified id:c5ba quota-stop null-bucket+margin fix + id:7725/aec5 ticks genuine (additive tests, resurrection clean, 204/0/0); no gaming, no new ROUTINE [id:c5ba,7725,aec5]

## 2026-07-08 19:58 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

Review since relay-ckpt-20260708-1925: window was bookkeeping-only; fixed in-window f599 tag/prose lane-conflict + repaired dangling REVIEW_ME box; suite 204/0/0, gaming-scan+orphan-scans clean. [id:f599]

## 2026-07-10 11:11 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

Review since relay-ckpt-20260708-1958: bookkeeping-only window (5 inbox ingests + fix closing id:83b7 +3 dups, filing id:9e06); verified lib-own-repos.sh symlink restores relay-doctor, suite 204/0/0, gaming-scan clean, orphan/cross-ledger clean. [id:83b7,5721,203a,b591,9e06,4958]

## 2026-07-10 11:18 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

Front-door --quota-7d→SEVEN_DAY only; sampler records .limits[] weekly_scoped; filed id:c471 (quota-gate loud-surface) + id:3a46 (preflight-delegation meeting); suite 204/0/0 [id:c471,3a46]

## 2026-07-10 11:46 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

mechanical verdict now representable + surfaced (never dispatchable), mirroring human; roadmap-lint clean; suite 205/0/0 (id:d310/baf1) [id:d310,baf1]

## 2026-07-10 12:18 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

baf1: kill human-backlog meeting overcount at source (human_decision bucket + real-route trailer + roadmap-lint doctrine rules) & record 82c4 shadow flip-gate met; suite 207/0 [id:baf1,1f1c,80e0,8504,dafa,82c4]

## 2026-07-10 12:36 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

close id:5937 deny-tail probe (D4→branch 1, auto-mode approves all 12 op-classes) + land harness (deny-tail-probe.sh + ref doc) + security invariant id:453a (--disallowedTools not a boundary); suite 207/0 [id:5937,453a,e2b1,13ae]

## 2026-07-10 13:16 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

Review since relay-ckpt-20260710-1236: window was a single clean TODO doc commit (id:d484, id:f3a0 filed); gaming-scan clean, suite 207/0/0, orphan/lint/doctor clean; reverse-handoff kept both new items as TODO design-judgment (no ROADMAP promotion). [id:d484,f3a0]

## 2026-07-10 — executor (sonnet)

Worked id:7d97 — added `user:`-prefix + emphasis-preservation invariants to `tools/memory-index.py --check` (diffs each entry's hook against `git show HEAD:<path>`; flags a dropped `user:` prefix or a lost `**bold**`/ALL-CAPS token, fail-open when there's no git history). Two new hermetic git-fixture tests (test12/13) cover both invariants plus the unchanged/brand-new non-flag cases. Suite 211/0/0.
Friction: none.

## 2026-07-10 17:26 — executor (sonnet, relay-loop)

id:7d97: memory-index --check now diffs each hook against git HEAD, flagging a dropped `user:` prefix or a lost **bold**/ALL-CAPS emphasis token; suite 211/0/0. [id:7d97]

## 2026-07-10 18:37 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

Verified id:7d97 genuinely green (not gamed); promoted id:411d [ROUTINE] w/ red spec; closed id:46f6+id:06e3 as shipped; suite 212/0/1-expected-red [id:7d97,411d,46f6,06e3]

## 2026-07-10 — executor (sonnet)

Worked id:411d — anchored `append.sh inbox-done XXXX` on the item's OWN trailing `<!-- routed:XXXX -->` marker (regex, optional whitespace) instead of a bare substring test; a sibling item whose prose merely cites the token no longer gets deleted as collateral. `tests/test_inbox_done_anchor.sh` green; suite 213/0/0.
Friction: none.

## 2026-07-10 18:41 — executor (sonnet, relay-loop)

Anchored append.sh inbox-done on the item's own trailing routed:XXXX marker instead of a substring match (id:411d); suite 213/0/0. [id:411d]

## 2026-07-10 19:18 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

Verified id:411d genuinely green (inbox-done anchors on own routed marker, spec unchanged); ticked TODO twin (cross-ledger drift); flagged id:9fdb umbrella; suite 213/0/0. [id:411d]

## 2026-07-10 19:35 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

handoff C1-C4: promoted id:77ce (reconcile-repo.sh pure planner + --dry-run parity oracle) with RED spec test_reconcile_planner.sh; suite 213/0/1-red [id:77ce]

## 2026-07-10 — executor (Sonnet)

Worked id:77ce — refactored `relay/scripts/reconcile-repo.sh` into a pure PLAN phase
(read-only git observations → actions/surfaced lists, zero mutating git calls) + a thin
APPLY phase (walks the planned action list and performs the mutation per kind: ff-merge,
lock-commit, reap, park). Added `--dry-run`: runs PLAN, emits the same JSON, stops before
APPLY. Also replaced the `live_claims_provided` bool + `live_claims` string pair with one
sentinel-bearing tri-state variable (`__UNSET__`/`""`/`"a,b"`) per the id:e3ad design note
(Option-as-bool-default cost). tests/test_reconcile_planner.sh (6 cases: dry-run-no-mutate
for ff-merge/lock-commit/reap/park, parity oracle, fail-closed-preserved) now green;
tests/test_reconcile_repo.sh (live behavior, id:5987) stays green — no regression. Full
suite 214/0/0-red. Ticked id:77ce in both ROADMAP.md and its TODO.md twin (INBOUND
routed:2f0c). Friction: the TODO.md deliverable list also named "git-free unit tests" for
the decision core; PLAN still reads real git state via read-only calls (not a fully
git-free decision function) — the git-fixture PLAN-only/dry-run tests shipped here are the
unit-test-equivalent; a further decision-core extraction (feeding a synthesized observation
record with no git repo at all) is left as a possible follow-up if relay-core's ebdb-b port
needs it, since it wasn't in the item's Acceptance/Done-check.

## 2026-07-10 19:52 — executor (sonnet, relay-loop)

Split reconcile-repo.sh into pure PLAN + thin APPLY with --dry-run parity oracle (id:77ce); full suite 214/0/0-red [id:77ce]

## 2026-07-10 20:05 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: verified id:77ce genuinely green (reconcile-repo.sh pure PLAN + thin APPLY, --dry-run parity oracle); suite 214/0/0; ledgers consistent, relay-doctor clean [id:77ce]

## 2026-07-11 — executor (sonnet, relay-loop)

Worked id:26c2 — investigated the ROADMAP `[ROUTINE]` item ("add a host-gate to
mechanical-daemon.sh — skip+defer any recipe whose `.host` != `uname -n`") and found the
identical behavior was already implemented and tested under id:9cfa (commit 97c322e,
wave-2a review finding, prior to this ROADMAP item being filed as its formal follow-up):
`mechanical-daemon.sh`'s step-2 host-binding gate reuses `host-gate.sh` (never a raw
`uname -n` compare) and `tests/test_mechanical_daemon.sh` cases (4)/(5) already cover the
exact foreign-host-defer / matching-host-permit acceptance criteria this item specifies.
No code change was needed — the acceptance was already met. Added a `# roadmap:26c2`
cross-reference comment to the test file (alongside its existing `# roadmap:b3d0` tag) so
the discoverability convention holds, then ticked the checkbox in both ROADMAP.md and
TODO.md (id:26c2 spans both ledgers per single-id-two-views). Left id:dfe4 (the other open
ROUTINE item, `roadmap-lint.sh` c095 heading-as-item refinement) untouched this session —
its `tests/test_roadmap_lint_c095.sh` spec does not exist yet in this worktree, so it needs
its own session to author the fixture + implementation rather than being folded into this
one. Full suite: 216 passed / 0 failed / 0 expected-red. Friction: none.

## 2026-07-11 13:34 — executor (sonnet, relay-loop)

Closed id:26c2 (mechanical-daemon host-gate) — behavior was already shipped under id:9cfa; ticked ROADMAP+TODO, cross-referenced test, full suite 216/0/0-red. [id:26c2]

## 2026-07-11 — executor (sonnet, relay-loop)

Worked id:dfe4 — refined `roadmap-lint.sh`'s c095 heading-as-item detector: a
`## …[LANE]…` heading is now treated as a heading-item requiring its OWN id only
when its children (up to the next heading) are ALL bare status markers; if ANY
child carries its own class tag + id, the heading is a descriptive SECTION title
and is no longer flagged MISSING-id (fixes the 3 false positives at ROADMAP
~L2861/2883/2911, children 0d58/fd37/9078). Implemented via a lookahead helper
(`section_has_tagged_child`) after converting the main scan loop from a `read`
pipe to an indexed array (`mapfile`) so it can peek forward. Added
`tests/test_roadmap_lint_c095.sh` (# roadmap:dfe4) with 3 cases: (a) section
header over a tagged+ided child NOT flagged, (b) genuine c095 shape (bare-marker
children) still flagged MISSING-id, (b2) same shape with the heading's own id
present stays clean. Ticked ROADMAP.md. Full suite: 217 passed / 0 failed / 0
expected-red. Friction: none.

## 2026-07-11 14:01 — executor (sonnet, relay-loop)

Refined roadmap-lint.sh c095 heading-as-item detection to only require a heading's own id when its children are bare status markers, fixing 3 false positives (id:dfe4); full suite 217/0/0-red. [id:dfe4]

## 2026-07-11 14:31 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: window was one M3 relane commit (id:77f3/13ae HARD→INPUT, legit); reconciled id:dfe4 cross-ledger drift, surfaced de4e lint warning; 217/0/0 green [id:dfe4,de4e]

## 2026-07-11 15:03 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

handoff C1-C4: promoted 6 [ROUTINE] TODO items to ROADMAP (f8df/34c7/431f/4245/1b1a/2b0b) with red-spec tests; C5 skipped (top HARD too large) [id:f8df,34c7,431f,4245,1b1a,2b0b]

## 2026-07-11 — executor (sonnet, relay-loop)

Worked id:431f — widened `orphan-scan.sh --shipped`'s two col-0 anchors (the typed-edge `local_state` map's checkbox-state test and the closed/open scan grep) to `^\s*- \[ \] `/`^\s*- \[[xX]\] ` so INDENTED `  - [ ] … <!-- id:XXXX -->` sub-items are classified (UMBRELLA-READY etc.), matching pre-existing col-0 behaviour unchanged. `tests/test_orphan_scan_shipped_indent.sh` (# roadmap:431f) was already RED from handoff C2 and is now green. Ticked ROADMAP.md + TODO.md twin. Full suite: 218 passed / 0 failed / 5 expected-red (open roadmap items). Friction: none.

## 2026-07-11 15:20 — executor (sonnet, relay-loop)

Widened orphan-scan.sh --shipped's two col-0 checkbox anchors to classify INDENTED sub-items (id:431f); full suite 218/0/5-red. [id:431f]

## 2026-07-11 — executor (sonnet, relay-loop)

Worked id:2b0b — added the 5th capability lane `[INPUT — author]` (human-expert-authored content) to `relay/references/hard-lanes.md`'s capability table, wired `relay/scripts/gather-human-backlog.sh` to bucket it onto `hard_hands` ("you write this", NOT untagged/meeting), and `roadmap-lint.sh` picked it up automatically since it reads the INPUT-lane marker set dynamically from `hard-lanes.md`. `tests/test_lane_input_author.sh` (# roadmap:2b0b, already RED from handoff) is now green; `tests/test_hard_lane_buckets.sh` unaffected/still green. Ticked ROADMAP.md's this-repo-half checkbox; left TODO.md's twin OPEN because it also covers the cross-repo `project_manager scan.py` half (id:b466, out of this worktree's scope, already flagged in the ROADMAP context note as tracked not duplicated). Full suite: 219 passed / 0 failed / 4 expected-red (open roadmap items). Friction: none.

## 2026-07-11 15:30 — executor (sonnet, relay-loop)

Added the [INPUT — author] capability lane (id:2b0b): hard-lanes.md table entry + gather-human-backlog.sh bucketing; test_lane_input_author.sh RED→green; full suite 219/0/4-red. [id:2b0b]

## 2026-07-11 — executor (sonnet, relay-loop)

Worked id:34c7 — widened `orphan-scan.sh --cross-ledger`'s two column-0-anchored checkbox scans (`grep -hE '^- \[[ xX]\] '` over TODO.md/TODO.archive.md and ROADMAP.md) to `^\s*- \[[ xX]\] ` (indent-agnostic), matching the `--shipped` driver's pre-existing approach (id:431f), so a drift whose TODO twin is an INDENTED sub-item is now caught by its own checkbox state (not its parent umbrella's). `tests/test_orphan_scan_cross_ledger_indent.sh` (# roadmap:34c7, already RED from handoff C2) is now green. Ticked ROADMAP.md + TODO.md twin. Full suite: 220 passed / 0 failed / 3 expected-red (open roadmap items). Friction: none.

## 2026-07-11 15:42 — executor (sonnet, relay-loop)

Unified orphan-scan.sh --cross-ledger on an indent-agnostic checkbox anchor so indented TODO sub-item twins are caught (id:34c7); full suite 220/0/3-red. [id:34c7]

## 2026-07-11 — executor (sonnet, relay-loop)

Worked id:1b1a — `meeting/md-merge.py update-ids` now fails LOUD (non-zero, unmatched token(s) named on stderr, writes NOTHING) when an id is not found in the target file, instead of silently appending a duplicate line; the append behaviour is now opt-in behind `--allow-new`. Updated the two production callers that legitimately mint new ids (`relay/scripts/scan-routed.sh`'s INBOUND-stub writer, and `relay/scripts/handback-followup.py`'s hard-split seam-append path) to pass `--allow-new`; left the decision-gate/human/none routes without the flag since they only edit an EXISTING parent line and should still fail loud on a mistyped parent id. Also fixed the companion bug named in the item's Context: `handback-followup.py:71`'s gate-note insertion used a `$`-anchored regex that silently no-op'd on an id comment followed by another annotation (e.g. `<!-- id:78ff --> <!-- xledger-ok: ... -->`) — it now inserts the note right after the id comment regardless of what follows it. `tests/test_md_merge_update_ids_strict.sh` (# roadmap:1b1a, RED from handoff) is now green. Ticked ROADMAP.md + TODO.md twin. Friction: initially wired `--allow-new` unconditionally into handback-followup.py's merge_cmd, which broke `test_handback_atomic_commit.sh` — that test invokes handback-followup.py's hardcoded `~/.claude/skills/meeting/md-merge.py` (the pre-merge installed copy, not this worktree's edited one), so an unconditional new flag looked "unrecognized" there; fixed by gating `--allow-new` on `route == "hard-split"` (the only route that mints new ids), which is also the more correct semantics. Full suite: 221 passed / 0 failed / 2 expected-red (open roadmap items).

## 2026-07-11 16:01 — executor (sonnet, relay-loop)

md-merge.py update-ids fails LOUD on an unmatched id, gates append behind --allow-new (id:1b1a); full suite 221/0/2-red [id:1b1a]

## 2026-07-11 — executor (sonnet, relay-loop)

Worked id:f8df — `diary-append.sh` no longer loses the `-f` entry temp file on a failed run. Previously the `-f` file was `rm`'d immediately after being read, before any commit/push had happened; a concurrent-commit rebase failure (the observed 2026-07-08 incident) then silently dropped the entry. Now the file is kept until push SUCCEEDS; any failure (pull/rebase, commit, or push) aborts a dangling rebase, quarantines the header+entry to `$DIARY_DIR/.failed/entry-<timestamp>-<pid>`, and prints a loud stderr path — only then is the original `-f` file removed. `.failed/entry-*` quarantine files share the existing `.diary-pending-*` replay loop, so the next successful run appends the entry exactly once. Also pinned the pull/push refspec (`git pull --rebase origin "$branch"` / `git push origin "$branch"` with the branch resolved via `git symbolic-ref`) instead of ambient tracking config, addressing the "Cannot rebase onto multiple branches" failure mode. Added a `DIARY_SKIP_SSH=1` test seam so hermetic tests can skip the real ssh-agent setup. `tests/test_diary_append_entry_survival.sh` (# roadmap:f8df, RED from handoff) is now green. Ticked ROADMAP.md + TODO.md twin. Full suite: 222 passed / 0 failed / 1 expected-red (open roadmap items: id:4245). Friction: none.

## 2026-07-11 — executor (sonnet, relay-loop)

Worked id:4245 — surfaced the two deliberately-unmarked cross-repo gate edges (`7df1`, `50c4`) as UNMARKED-GATE in `orphan-scan.sh --shipped`. The production UNMARKED-GATE backstop (gate-phrase regex incl. `🚧 GATED (DEP: …)`) was already implemented in `meeting/orphan-scan.sh` (landed alongside earlier typed-edge work), and both `id:7df1` and `id:50c4` already classify correctly (`ORPHAN_SCAN_LIMIT=0 orphan-scan.sh --shipped .` shows both as UNMARKED-GATE; the default run only omits them because the advisory output cap (10) is reached by other candidates first — cap behavior, not a classification gap). The one real defect was in the RED test itself: `tests/test_orphan_scan_unmarked_gate.sh`'s negative fixture (id:9999, "a local gated-on: marker MUST NOT be UNMARKED-GATE") embedded the literal substring "UNMARKED-GATE" in its own title prose, so the test's negative assertion (`grep 'id:9999.*UNMARKED-GATE'`) false-matched its own fixture text via `short_text()`'s title echo — not a code bug. Reworded the fixture line's prose (semantics unchanged: still a col-0 item with a proper local `gated-on:` marker) to drop the self-referential substring; the assertion logic is untouched. `tests/test_orphan_scan_unmarked_gate.sh` (# roadmap:4245) is now green. Ticked ROADMAP.md + TODO.md twin. Full suite: 223 passed / 0 failed / 0 expected-red. Friction: the only friction was diagnosing that the test failure was a fixture self-collision rather than a missing feature — worth noting for future readers of this test.

## 2026-07-11 16:20 — executor (sonnet, relay-loop)

Fixed diary-append.sh entry-loss + rebase-refspec bug (id:f8df) and verified/fixed the UNMARKED-GATE test fixture for id:4245; full suite 223/0/0-red, both open [ROUTINE] items closed. [id:f8df,4245]

## 2026-07-11 16:37 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

Review clean: 8 executor items (f8df/34c7/431f/4245/1b1a/2b0b/dfe4/26c2) verified genuine, 223/0/0; fixed id:2b0b TODO-twin drift; 0 open ROUTINE [id:f8df,34c7,431f,4245,1b1a,2b0b,dfe4,26c2]

## 2026-07-11 16:54 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

Root-caused spurious re-dispatched handoff: unpromoted-scan primary_lane() ignores new-vocab tags; filed id:719a [ROUTINE] + RED spec; suite 223/0 +1 expected-red [id:719a]

## 2026-07-11 17:03 — executor (sonnet, relay-loop)

Worked id:719a — `unpromoted-scan.sh` `primary_lane()` now recognizes the new capability-keyed lane vocabulary (`[INPUT — meeting|access|decision]`, bare `[HARD]`, `[MECHANICAL]`) alongside the old venue-keyed spelling, closing the false-positive `promote` mis-classification that caused the 2026-07-11 spurious handoff re-dispatch. Two changes: (1) added the five new-vocab tags to both existing tag lists (the bold-anchor "tag-after-title" branch and the leftmost-scan fallback); (2) added a new tag-before-bold-title anchor (`- [ ] [TAG] **title** …`, the shape new-vocab items actually use) that wins over any prose token regardless of position — this was the root gap, since the old bold-anchor only looked for a tag AFTER the closing `**`. Bare `[HARD]` deliberately stays OUT of the promote set (only `[ROUTINE]`/`[HARD — pool]` promote; `[HARD]` alone is reserved for the strong reviewer per rule 1) — confirmed against the RED test's case (n), which asserts bare `[HARD]` → `laned`, not `promote`; this is more precise than the ROADMAP item's own "How/Design" prose (which listed bare `[HARD]` under "executable lanes → promote") — the test is the binding acceptance criterion and rule 3 forbids weakening it, so implementation followed the test. `tests/test_unpromoted_scan_newvocab.sh` (# roadmap:719a, RED from review) is now green; `tests/test_unpromoted_scan.sh` (cases a–i, existing old-vocab anchoring) stays green — no regression. Ticked ROADMAP.md (no TODO.md twin exists for id:719a — nothing to sync). Full suite: 224 passed / 0 failed / 0 expected-red. Friction: none.

## 2026-07-11 17:04 — executor (sonnet, relay-loop)

Fixed unpromoted-scan.sh primary_lane() to recognize new-vocab lane tags (id:719a); full suite 224/0/0-red, 0 open ROUTINE items remain [id:719a]

## 2026-07-11 17:19 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

Review clean: id:719a (unpromoted-scan primary_lane new-vocab recognition) verified genuine, suite 224/0/0, 0 open ROUTINE items remain [id:719a]

## 2026-07-12 10:15 — reviewer (claude-opus-4-8)

handoff: ingested routed:8a55 (id:3273 git-lock-push stall timeout) + routed:5434 (id:1b18 diary-append replay ordering) — 2 [ROUTINE] items + 2 RED specs; suite 225/0/2-red

## 2026-07-12 11:20 — executor (claude-opus-4-8, delegated background agents)

Worked the 2 open [ROUTINE] items surfaced by today's handoff (routed:8a55/5434), each implemented+verified by a background agent in an isolated worktree, integrated + re-verified here. **id:3273** (`git-lock-push.sh`): both push invocations (existing-branch + `--set-upstream` first-push) now run `GIT_SSH_COMMAND="ssh … -o ServerAliveInterval=15 -o ServerAliveCountMax=3" timeout "${GIT_LOCK_PUSH_TIMEOUT:-120}" git push …`; on rc≠0 (rc=124 = timeout) a LOUD stderr WARNING fires, the flock fd is released (`exec 8>&-`), exit 0 — same non-fatal committed-locally contract as the flock-timeout/ff-only branches. A stalled ESTABLISHED ssh now self-terminates instead of hanging 40+ min on the flock. **id:1b18** (`diary-append.sh`): reordered replay to pull → replay+append → single commit → push (was: replay+append+unlink → pull, which dirtied the tree and deadlocked). Exactly-once preserved (quarantine files rm'd only AFTER commit succeeds; commit-failure does `git checkout HEAD -- DIARY.md` + on_failure, leaving replay files on disk); no-entry-loss preserved (pull/commit failures still quarantine loudly); push-failure path stops re-quarantining a now-committed entry (kills a latent double-append the old order masked) and fails loud; an `ls-remote --exit-code --heads` guard skips the pull only when the remote branch genuinely doesn't exist (first push). Also fixed a same-session regression: the /meeting §Versioning table reproduced the literal `relay-executor contract vN` marker string, which test_relay_executor.sh greps for the CLAUDE.md version — reworded the cell (eb0ea8a). Ticked ROADMAP + TODO twins (single-id-two-views). Contract compliance: no test weakened; both RED specs green + f8df sibling stays green. Full suite: 227 passed / 0 failed / 0 expected-red. Friction: none.

## 2026-07-12 21:20 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: verified id:3273+id:1b18 genuinely green (unchanged specs, red-vs-checkpoint); reverse-handoff promoted id:8800+id:0f7a [ROUTINE] with RED specs [id:3273,1b18,8800,0f7a]

## 2026-07-12 21:20 — executor (sonnet)

Worked id:8800 — `orphan-scan.sh`: added a `<!-- gate-prose-only -->` marker that bypasses ONLY the UNMARKED-GATE backstop (does not set has_typed, leaves typed-predicate/EXTERNAL-WAIT/GATE-STALE paths untouched). `tests/test_orphan_scan_gate_prose_only.sh` (roadmap:8800) goes green; `test_orphan_scan_unmarked_gate.sh` (id:4245) and `test_orphan_scan_shipped.sh` stay green. Full suite: 228 passed / 0 failed / 1 expected-red (id:0f7a, still open — untouched this session, one-item-per-session scope). Friction: none. Stopped here per the executor contract's one-[ROUTINE]-item-per-session rule; id:0f7a (archive-done.sh nested subsection pruning) remains open for the next session.

## 2026-07-12 21:29 — executor (sonnet, relay-loop)

executor: shipped id:8800 (orphan-scan.sh gate-prose-only marker bypasses UNMARKED-GATE backstop for confirmed external-prose gates) [id:8800]

## 2026-07-12 21:30 — executor (sonnet, relay-loop)

Worked id:0f7a — `archive-done.sh`: the empty-section pruner previously split TODO.md into segments on ANY heading level >=2, so a `### subsection` started its own segment and left the enclosing `## section` looking empty (pruned) even when its tasks lived entirely under the subsection. Changed the segment split to break ONLY on level-2 `##` headings; deeper (`###`+) headings now stay in the parent section's body, so a nested-subsection's tasks count toward the parent's has_content check and the parent survives. `tests/test_archive_done_nested_subsection.sh` (roadmap:0f7a) goes green; `test_archive_done_multiline.sh`, `test_roadmap_archive.sh`, `test_archive_closed.sh` stay green. Full suite: 229 passed / 0 failed / 0 expected-red. Friction: none.

## 2026-07-12 21:58 — executor (sonnet, relay-loop)

executor: shipped id:0f7a (archive-done.sh: only ## headings are prune-segment boundaries, ### subsections count as parent body) [id:0f7a]

## 2026-07-12 22:21 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: id:0f7a (archive-done nested-### fix) verified green; fixed 0f7a+8800 cross-ledger TODO drift; suite 229 pass [id:0f7a,8800]

## 2026-07-13 13:27 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: window is human ledger edits (gaming-scan clean); mini-handoff promoted id:1781 + id:7f30 to [ROUTINE] with RED specs; suite 229 pass +2 expected-red; roadmap-lint/cross-ledger/relay-doctor clean [id:1781,7f30,3273,1b18,8800,0f7a]

## 2026-07-13 — executor (sonnet, relay-loop)

Worked id:1781 — `roadmap-lint.sh` case-c "multiple lane brackets" conflict check counted EVERY bare lane bracket anywhere on the line, so a correctly-tagged item whose body cited a prior lane transition in trailing audit-trail prose (e.g. "was [HARD — pool] before, re-laned to [ROUTINE]") false-positived the LOUD-reject. Added a `leading_lane_run()` helper that walks only the CONTIGUOUS run of recognized lane brackets immediately after `- [ ] `/`- [x] `, and pointed the case-c bare-tag scan at that leading run instead of the whole (backtick-stripped) line. Two genuinely contiguous LEADING tags (e.g. `[HARD — pool] [ROUTINE] …`) still ERROR; a clean single-tag item still passes. `tests/test_roadmap_lint_trailing_lane_prose.sh` (roadmap:1781) goes green; `test_roadmap_lint_tagprose.sh`, `test_roadmap_lint.sh`, `test_roadmap_lint_tag_first.sh` stay green. Full suite: 230 passed / 0 failed / 1 expected-red (id:7f30, the remaining open ROUTINE item from this mini-handoff). Friction: none.

## 2026-07-13 14:00 — executor (sonnet, relay-loop)

Fixed roadmap-lint.sh case-c conflict check to count only the leading contiguous lane-bracket run, ignoring lane brackets in trailing audit-trail prose (id:1781); full suite 230 passed / 0 failed / 1 expected-red. [id:1781]

## 2026-07-13 — executor (sonnet, relay-loop)

Worked id:7f30 — added an `<!-- xgate:TOKEN@repo -->` sibling-comment marker to `meeting/orphan-scan.sh`, mirroring the shipped `gate-prose-only` (id:8800) bypass: it records a confirmed CROSS-REPO gate whose blocking token lives in another repo (no local `gated-on:` edge to point at) and bypasses ONLY the UNMARKED-GATE backstop, without setting `has_typed` or touching the typed-predicate/EXTERNAL-WAIT/GATE-STALE paths. Parses `TOKEN@repo` loosely via `grep -qP`; a malformed marker simply doesn't match (no crash). Added the marker to id:50c4's TODO line as the first real consumer (per the item's How/Design), and ticked its TODO checkbox alongside the ROADMAP item (single-id-two-views). `tests/test_orphan_scan_xgate.sh` (roadmap:7f30) goes green; `test_orphan_scan_gate_prose_only.sh` (id:8800) and `test_orphan_scan_unmarked_gate.sh` (id:4245) stay green. Full suite: 231 passed / 0 failed / 0 expected-red. Friction: none.

## 2026-07-13 14:28 — executor (sonnet, relay-loop)

Shipped id:7f30 — orphan-scan.sh xgate:TOKEN@repo marker bypasses UNMARKED-GATE for confirmed cross-repo gates; applied to id:50c4; full suite 231 passed / 0 failed. [id:7f30]

## 2026-07-13 14:50 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: verified id:e3c0 gate annotation (only commit); gaming-scan clean, 231 tests pass, lint/doctor/cross-ledger clean, contract v6 current [id:e3c0]

## 2026-07-14 12:52 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: verified id:8a6b/1432/2ab2 genuinely green (gaming-scan clean, 234/0), lint+cross-ledger clean, 0 open ROUTINE; surfaced routed:6754 inbox dead-letter to REVIEW_ME [id:8a6b,1432,2ab2]

## 2026-07-14 14:07 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: verified id:85df/297b done → ticked (classify-verdict.sh + roadmap-lint case-c); gaming-scan clean, 234/0, lint+cross-ledger clean, 0 open ROUTINE [id:85df,297b]

## 2026-07-14 14:28 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

C2: promoted the @needs-auth co-meet cluster (id:a505, id:1750) from TODO backlog into ROADMAP as [HARD] pool items [id:a505,1750]

## 2026-07-14 14:50 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

a505: @needs-auth convention (4 fields, REVIEW_ME carrier) + executor-contract rule 6 record-and-continue, marker v6→v7 with CLAUDE.md pointer in lockstep; roadmap-lint/gather recognition; make test 235/0 [id:a505]

## 2026-07-14 15:10 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

HARD id:1750 — offline AI-free @needs-auth lister (gather-human-backlog --needs-auth); full suite 236/0 green [id:1750]

## 2026-07-15 — executor (claude-sonnet-5, direct-agent)

Worked id:e4f5 — user-mandated hardening of `git-lock-push.sh` after the loderite incident (2026-07-15: a relay reviewer's deliberate `--no-ff` integration merges got flattened by legacy-mode `git pull --rebase`, because `--ff-only`/`--merge-branch` weren't used). Added an auto-guard in the legacy/manifest rebase branch: before rebasing, fetch the remote tip and `git rev-list --merges --count FETCH_HEAD..HEAD`; if >0, emit a loud NOTE to stderr and force `ff_only=1`, taking the same ff-only reconcile path (non-fatal warn+exit-0 on divergence, same as the existing flock-timeout/id:aa93/ff-only-divergence contract). Purely linear local-ahead is unaffected — the existing rebase path (id:aa93 tracked-dirty refusal, id:dff8 untracked carve-out, mid-rebase-conflict handling) runs unchanged. Updated the header usage docs for `--ff-only` and `git-diary-workflow/SKILL.md` Step 1 to note the auto-detection while still recommending explicit `--ff-only` when the caller already knows. New `tests/test_git_lock_push_merge_autoguard.sh` (3 scenarios: un-moved-remote+merge-ahead → topology survives + NOTE fires; diverged-remote+merge-ahead → non-fatal warn, not pushed, local history intact; linear-local-ahead regression → guard does not fire, legacy rebase still pushes). Full suite: 242 passed / 0 failed / 0 expected-red (including the new test + the pre-existing ff_only/dirty_guard/slash_branch tests). Friction: none — the existing remote-exists/mode-dispatch structure around line 166-225 made the guard a minimal insertion, no restructuring of the surrounding branches needed. [id:e4f5]

## 2026-07-15 12:44 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: verified id:85d3/546b/e4f5 green (REVIEW_ME+roadmap archivers, lockpush merge-topology guard); mini-handoff id:b8c2 (needs-auth lister named-repo crash) + RED spec; 242 tests green [id:85d3,546b,e4f5,b8c2]

## 2026-07-15 — executor (Sonnet)

Worked id:b8c2 — fixed `gather-human-backlog.sh: list_needs_auth_repo` crashing under
`set -u` on every explicit `--needs-auth <repo>` invocation. Root cause: the single-line
`local name="$1" path="$2" file="$path/REVIEW_ME.md"` expands all RHS words before any
assignment takes effect, so `$path` in the `file=` word resolved against the caller's
scope (unset there for the named-arg branch). Split into two `local` statements so
`path` is assigned before `file` references it — matches the roadmap's prescribed fix
exactly; no other lines touched. `tests/test_needs_auth_lister_named_repo.sh`
(roadmap:b8c2) now green; `tests/test_needs_auth_lister.sh` (id:1750, no-arg form)
stays green; full `make test` 243 passed / 0 failed / 0 expected-red.
Friction: none — a one-line split, already-written RED spec covered both the crash fix
and the plugin-path `PATH_OF` lookup (already correct pre-fix, unchanged). [id:b8c2]

## 2026-07-15 12:58 — executor (sonnet, relay-loop)

id:b8c2 — fixed gather-human-backlog.sh unbound-variable crash in list_needs_auth_repo (split local decl); 243 tests green [id:b8c2]

## 2026-07-15 13:25 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: verified id:b8c2 genuinely green (unbound-var fix satisfies unchanged RED spec); 243 tests pass, relay-doctor clean, 0 open ROUTINE [id:b8c2]

## 2026-07-15 13:52 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

handoff: promoted id:f682 (relay pre-integrate isolation gate) to ROADMAP [ROUTINE] with functional RED spec test_verify_isolation.sh [id:f682]

## 2026-07-15 — executor (sonnet, relay-loop)

Worked id:f682 — implemented `relay/scripts/verify-isolation.sh` (part 2, the load-bearing
mechanized integrator gate): observe-only, exit 0 when the worktree has commits beyond
base + a clean tree, exit 2 (never mutates) on an empty worktree, a dirty tree, or a
non-worktree path. Wired it into `relay/SKILL.md` invariant 5 (integrate step, called
before the `--no-ff` merge) and added the "write only inside your worktree" boilerplate
sentence + a recovery-doctrine paragraph (salvage-under-lease, id:15d5 pattern) to
`relay/references/conventions.md` (parts 1 + 3 of the item's design). Registered the new
script in the Makefile's `relay_FILES`/`relay_EXEC`/`relay_ALLOW` manifests — the
pre-existing `test_relay_install_manifest.sh` caught the omission on first `make test`.
`tests/test_verify_isolation.sh` (roadmap:f682) green; full `make test` 244 passed / 0
failed / 0 expected-red.
Friction: none.

## 2026-07-15 14:10 — executor (sonnet, relay-loop)

id:f682 — implemented relay/scripts/verify-isolation.sh (pre-integrate isolation gate) + wired into SKILL.md invariant 5 and conventions.md; 244/0 tests green [id:f682]

## 2026-07-15 14:31 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: verified id:f682 genuinely green (verify-isolation.sh, unmodified RED spec, suite 244/0) + ticked TODO twin (cross-ledger sync) [id:f682]

## 2026-07-16 12:34 — reviewer (claude-opus-4-8)

id:7612 — wire the isolation gate into the integrator (step 1a) + main-HEAD discriminator resolving the id:8e3e ambiguity; f682's acceptance never asserted a call site [id:7612]

## 2026-07-16 13:55 — reviewer (claude-opus-4-8, relay-loop)

review: id:7612 VERIFIED genuinely green — the isolation gate is really wired (verify-isolation.sh
called in relay-loop.js via the absolute path, before `merge --no-ff`, instructing ABORT), confirmed
by mutation-testing 3 broken-gate variants, all still caught. gaming-scan clean; the window was
ledger-only (no code/test files touched), so no resurrection/fixture/refactor residue to audit.
Tiers (id:f032): the repo declares ONE tier — `make test` (no CI, no package.json). Ran green:
248 passed / 0 failed / 2 expected-red. No tier skipped.

id:b780 — FIXED a flake that was red-lighting the whole suite: tests/test_isolation_gate_wired.sh
piped 91697 B of relay-loop.js into `grep -q` under `set -o pipefail`. The pipe buffer is 65536 B,
so printf blocks mid-write while grep -q matches at byte 63529 and exits first; printf dies of
SIGPIPE and pipefail promotes it to a failure EVEN THOUGH grep matched (rc=141, PIPESTATUS=[0]).
Measured 1/25 idle, 22/40 under CPU load. Fix = herestrings + `grep -m1`; 0/60 after, spec intact
per the mutation tests. Diagnosis requires real bash — the agent shell is zsh, where PIPESTATUS is
empty and the race does not reproduce (that mis-shell cost several invalid "cannot reproduce" runs).

§5b reverse-handoff — 4 unqualified TODO items arrived this window. PROMOTED 2 (ids REUSED, D2):
id:1312 (unpromoted-scan bare-substring twin check) → [ROUTINE] + RED tests/test_unpromoted_scan_anchoring.sh;
id:d515 (scan-routed apply header claims DRY-RUN) → [ROUTINE] + RED tests/test_scan_routed_apply_header.sh.
Both specs verified red-for-the-right-reason with passing controls. NOT promoted: id:1f60 and
id:2456 — each turns on owner judgment (what counts as a "delegated verdict"; a bar on skill-authored
invariant prose), so they stay TODO-side /meeting candidates.

Ingested inbox dead-letter routed:f1f5 → id:521f (roadmap-lint's unanchored first-match id_re) —
same defect family as id:1312; flagged for a possible shared anchored-extraction helper (REVIEW_ME).
DECLINED the orphan-scan --shipped TICK-READY hit on id:de31: its linked test declares a narrower
scope than the item (record format only; C7 also needs the forced-resolution write + triage
sub-agent), so a tick would freeze the harder half as done. Verified the 8eaa0c9 routed:6754 tick
claim — genuinely drained from the inbox and present in project_manager/TODO.md.

routine_open: 2 (id:1312, id:d515). Contract pointer v9 == canonical v9, no drift. relay-doctor:
2 findings (the f1f5 dead-letter, now ingested; relay-core shadow 28351 rounds / 0 mismatches). [id:7612 id:b780 id:1312 id:d515 id:521f]

## 2026-07-16 14:25 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: id:7612 verified genuinely green (mutation-tested); fixed a SIGPIPE flake red-lighting the whole suite (id:b780); promoted id:1312/id:d515 [ROUTINE] with RED specs; suite 248/0 + 2 expected-red [id:7612,b780,1312,d515,521f,de31]

## 2026-07-16 — executor (claude-sonnet-5)

Worked id:1312 and id:d515 — both open [ROUTINE] items from the previous review round.
id:1312: anchored `unpromoted-scan.sh`'s twin check to an item's own trailing `- [ ]/- [x]
... <!-- id:XXXX -->` checkbox-line marker instead of a bare `grep -qF "id:$token"` over the
whole ROADMAP.md, which had been false-matching prose that merely mentions a token inside
another item's explanatory text. id:d515: fixed `scan-routed.sh`'s APPLY-mode header, which
used `${DRY_RUN:+...}` (expands on the non-empty default `DRY_RUN=0`) so every real --apply
run mislabelled itself "(DRY-RUN)"; switched to a value-gated `$([[ "$DRY_RUN" -eq 1 ]] && ...)`.
Both RED specs (tests/test_unpromoted_scan_anchoring.sh, tests/test_scan_routed_apply_header.sh)
now pass; full suite green at 250/0/0. Both fixes were one-line changes with a scoped comment
explaining the anchoring; no new duplication introduced.
Friction: none.
refactor: none needed — one-line fixes each, mirroring an anchoring pattern scan-routed.sh
already used elsewhere; no new duplication to extract.

## 2026-07-16 14:30 — executor (sonnet, relay-loop)

Closed both open [ROUTINE] items: id:1312 (anchored unpromoted-scan.sh's twin check to an item's own trailing checkbox marker, no longer false-matching prose mentions) and id:d515 (fixed scan-routed.sh's APPLY-mode header mislabelling every real run as DRY-RUN); full suite green 250/0/0. [id:1312,d515]

## 2026-07-16 14:48 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: id:1312 + id:d515 verified genuinely green (mutation-tested, specs untouched); synced TODO twins (cross-ledger drift, the only relay-doctor findings); promoted id:521f [ROUTINE] with RED spec — roadmap-lint's unanchored id grep both misattributes and false-negatives; suite 250/0 + 1 expected-red [id:1312,d515,521f]

## 2026-07-16 — executor (claude-opus-4-8, interactive apex, owner-directed)

Worked id:f980 + id:a921 — the id:365b circuit breaker counted units that never dispatch,
and both inline suppression call sites cited a phantom runId.

The brief's stated premise for id:f980 ("a unit still 'idle' at the breaker is
non-dispatchable BY CONSTRUCTION") was FALSE and I stopped rather than fix blind: the
id:9821/e030 Fable elevation runs AFTER the breaker and mutates idle→review, so on a
Fable session (STRONG_TIER unset ⇒ SESSION_IS_FABLE, a normal config) an idle unit CAN
dispatch. The narrow "skip idle in the guard" fix would have let elevated units dispatch
un-breakered forever. The owner then ratified shape A (breaker last, after all verdict
mutations, over the idle-filtered set), explicitly widening the change envelope.

Two things the report did not contain, found while implementing:
  1. id:1432's no-work suppression call site had the IDENTICAL phantom-runId defect.
  2. state.runId's general-path assignment sat BELOW the dispatch sort (the L884 one is in
     the user-stop early-return branch), so naively reading state.runId at the breaker would
     have printed an EMPTY run id — worse than the phantom. Fixed by canonicalizing once at
     the prelude, which made two later assignments redundant.

Friction: relay-loop.js cannot be executed in-harness (Workflow module), so the pipeline
ORDER is asserted structurally by line position — stated as an explicit coverage limit on
id:f980 rather than papered over. The Fable-recheck-not-dropped case is pinned by that
ordering assertion, not by an end-to-end run; staging a real Fable session is not possible
here and I did not fake it. Also: my first worktree was reaped mid-session by force-free
cleanup (empty branch, nothing lost); mitigation is an immediate anchoring commit.

## 2026-07-16 15:26 — reviewer (claude-opus-4-8)

strong-execute: id:f980 (circuit breaker counts only what dispatches — shape A, owner-ratified) + id:a921 (canonical state.runId in both cost hints, incl. the id:1432 sibling). Killed 38 phantom blocked entries that buried 2 real handbacks. Two prescribed fixes were REJECTED by the executing agent as wrong (skip-idle would open a Fable spin hole; state.runId at the breaker would print empty) — both premises verified false and corrected. Suite 250/0/1 expected-red.

## 2026-07-17 10:59 — executor (sonnet)

Worked id:521f — `roadmap-lint.sh` id extraction was an unanchored first-match `id_re='id:[0-9a-fA-F]{4}'` grep at 5 call sites (heading-as-item tagged-child check, heading missing-id check, the grammar's clause-2 has_id check, the TAG-NOT-FIRST warn's display id, and the violation-report idtoken). Fixed by anchoring all 5 to the canonical trailing `<!-- id:XXXX -->` HTML-comment marker via a new `own_id_of_line`/`has_own_id_marker` pair; `item_id()` now uses the anchored marker first, falling back to a bare `id:XXXX` grab ONLY for report-display convenience on a line with no marker at all (never to satisfy the has-id grammar clause). `tests/test_roadmap_lint_id_anchoring.sh` green (misattribution, false-negative, and no-false-positive-on-citation controls all pass); the real ROADMAP.md still lints clean (exit 0).
Friction: none — item was well-scoped, no size-out needed.
refactor: extracted the anchored-marker regex + extraction/boolean helpers into a new shared file `relay/scripts/lib-anchored-id.sh` (mirrors the existing `lib-own-repos.sh` pattern — sourced, not executed; registered in the Makefile's `relay_FILES`). Deliberately did NOT force `scan-routed.sh` / `unpromoted-scan.sh` (id:1312/d515, already closed+tested) onto the same helper: they solve a different shape — "does a SPECIFIC KNOWN token appear as some line's own marker" (whole-file/string presence check, one end-of-line-strict, one spanning two files with a `routed:`-or-`id:` prefix) — versus roadmap-lint's "extract the UNKNOWN owning id from THIS line, tolerant of trailing prose after the marker". Rewriting the other two into per-line loops for a stylistic 3-way unification would touch already-shipped, tested code for no behavioural gain; the rationale is recorded in `lib-anchored-id.sh`'s header comment so it isn't re-litigated. Full suite: 251 passed, 0 failed, 0 expected-red.

## 2026-07-17 15:41 — executor (sonnet)

Worked id:de36 — extended `/meeting` step 7b (`meeting/SKILL.md`) so the inbox surface is LINTED, not just grepped. Added a paragraph directly after the existing routed-item-adoption prose, inside the 7b marker span: it runs `relay/scripts/todo-conformance.sh --inbox <resolved inbox path>` (the same detector `scan-routed.sh` already reuses — invoked, not reimplemented) and, if it emits findings, displays them under a distinct `⚠ Inbox — non-conforming entries (todo-conformance.sh --inbox)` heading, separate from the `📥 Inbox — items routed to this repo` block. Kept it surface-only per the test's forbidden-phrase check (no "auto-fix"/"automatically fix"/"block the meeting"/"abort the meeting" wording) and skip-silent on empty output. `tests/test_meeting_inbox_lint_surface.sh` green (8/8 assertions); full suite 254 passed, 0 failed, 1 expected-red (`test_inbox_write_integrity.sh`, my sibling's id:34c2, correctly still open).
Friction: none of substance — first draft phrased the surface-only clause as "no auto-fix, and never block or abort the meeting", which literally contained the test's forbidden substring "abort the meeting" and failed one assertion; reworded to "display and move on ... never halt or gate the rest of the meeting" to convey the same contract without tripping the phrase-ban, then reran green. Did not touch `meeting/append.sh` (sibling's id:34c2 file) or the now-EXPECTED-RED test for it.
refactor: none needed — the change is a same-shape prose extension of an existing step (matching its style: a fenced example block + a short surface-only reminder), not new code; there was no duplication or structural debt in `meeting/SKILL.md` step 7b to clean up, and the detector itself (`todo-conformance.sh`) was untouched (already correct, per the roadmap item's own framing — the defect was invocation, not detection).
## 2026-07-17 15:43 — executor (sonnet)

Worked id:34c2 — `append.sh -t inbox` now (A) validates on write, (B) mints inside via
`--route-to <target-repo> -e "<desc>"`, and (C) always echoes the routed token actually
written, closing the acc7 phantom-append incident (a caller could previously report a
token that was never on disk). (A) reuses `relay/scripts/todo-conformance.sh --inbox`'s
existing `classify_inbox` grammar rather than re-deriving the conforming-form regex — the
entry is written to a throwaway single-line temp file and run through the real classifier;
an `orphan` verdict rejects (exit 1, nothing appended) with the offending line and the
expected form. (B) mints via a new `scan_routed_tokens <target>` helper (also exposed as
the `scan-routed-tokens` verb, mirroring `scan-ids`'s output contract) that unions the
inbox's own `routed:` markers with the target repo's `routed:` citations across the same
file set `scan_ids` already scans (`docs/meeting-notes`, `TODO.md`, `TODO.archive.md`,
`ROADMAP.md`) via the existing `resolve_target()` — the mint loop re-rolls
`secrets.token_hex(2)` until it draws a token outside that set, so the collision-check is
the same function the `scan-routed-tokens` verb exposes, not a second copy. (C) parses the
token back out of the line just appended (`grep -oP 'routed:\K[0-9a-f]{4}'`) rather than
trusting any caller-side variable — stdout is now ground truth for what landed on disk.
`-t discoveries`/`-t personas` are untouched (validation is gated on `target == inbox`
only); `tests/test_inbox_write_integrity.sh` (RED spec, not written by me) is green
unmodified, and the full suite is 254 passed, 0 failed, 1 expected-red (id:de36, my
sibling's item, correctly still open).
Friction: none of substance — the one design call was reuse-vs-reimplement for the
conforming-form check; running the entry through the real `todo-conformance.sh --inbox`
classifier (rather than copying its regex into append.sh) avoids a second definition of
the inbox grammar drifting from the first.
refactor: none needed — this item adds a new, previously-nonexistent write-path guard and
two new verbs to `append.sh`; there was no existing `-t inbox` validation/echo logic to
clean up, and the new code reuses `resolve_inbox()`/`resolve_target()`/`scan_ids`'s file-set
convention rather than introducing a parallel implementation.

id:1102 (2026-07-17, executor session): relay-doctor.sh now detects install DRIFT, the
manifest -> tree direction id:69ef's reference-install check structurally could not catch
(id:69ef only verifies repo -> manifest, i.e. "is every relay/references/*.md DECLARED?" —
lib-anchored-id.sh WAS declared, so id:69ef stayed clean while the live tree had 62 of 64
scripts). The new `install_drift_check()` (section `=== install-drift: manifest -> tree
(id:1102) ===`) walks the SAME `relay_files_manifest()` join id:69ef already used (factored
out of check 4 so both callers share one parser, per CLAUDE.md no-not-invented-here — this
IS the refactor line, see below) and, for every `scripts/*`/`references/*` token, asserts
`$RELAY_INSTALL_ROOT/relay/<token>` exists (default `~/.claude/skills`, overridable so
`tests/test_relay_install_drift_check.sh` never touches the real install tree). Prints
`MISSING: relay/<token> ...` per gap, a clean summary otherwise, and is wired into the
cross-repo/once-only section right after `refs_install_check`. The meeting-cross/id:4f5f
carve-out is satisfied structurally (this check reads only the relay skill's own
relay_FILES manifest, so meeting-cross's deliberately-uninstalled SKILL.md is never in
scope) and is recorded explicitly in a code comment so that reads as a decision, not an
oversight. One knock-on fix: had to add a "no relay install found under
$RELAY_INSTALL_ROOT/relay" SKIP guard, because `tests/test_relay_doctor_strict.sh` runs
relay-doctor against a synthetic `$HOME` with no installed relay skill at all — without the
guard every manifested file read as MISSING and `--strict` started failing that
pre-existing test's "clean fixture" case (a bare-missing-root is a setup state, not drift,
so it SKIPs rather than counting issues). Target spec
`tests/test_relay_install_drift_check.sh` green; full suite green (256 passed, 0 failed, 0
expected-red).
refactor: factored the backslash-continued `relay_FILES := …` awk join (previously
duplicated between check 4/id:69ef and its test) out into a shared `relay_files_manifest()`
function that both `refs_install_check()` and the new `install_drift_check()` now call —
one parser instead of a second/third copy, per the item's explicit reuse mandate.

## 2026-07-17 — review (Opus apex) window relay-ckpt-20260716-1526..HEAD (32 commits)

Ledger-only review pass on the MAIN checkout (id:15d5 pattern; no worktree, no claim.sh —
orchestrator held the cross-session lease). Window was mostly chore(inbox) ingests +
meeting/docs commits plus three relay-machinery integrates: id:34c2 (append.sh -t inbox
write-path integrity), id:de36 (conformance lint at the /meeting inbox surface), id:1102
(relay-doctor install-drift detection), and id:1735 (relay-loop handback-summary
reconciliation).

**Test-integrity (§2):** gaming-scan.sh clean (no DELETED_TEST / ADDED_SKIP /
REMOVED_ASSERT). No gaming flags. Judgment-residue checks clean — the four integrated
items' linked tests all pass against the committed tree
(test_relay_loop_handback_summary, test_inbox_write_integrity,
test_meeting_inbox_lint_surface, test_relay_install_drift_check,
test_relay_loop_drain_vs_blocked).

**Test tiers (§3):** enumerated from the Makefile — `lint` tier + `run-tests.sh` unit tier.
- unit tier: GREEN — 256 passed, 0 failed, 0 expected-red.
- lint tier: **RED** — `check-no-bare-rm-f.sh --enforce` fails on a NEW bare `rm -f -- "$tmp_check"`
  at `meeting/append.sh:384`, introduced by febb0c3 (integrate id:34c2). `make test` aborts at
  the lint tier before the unit suite. This review is code-safety-constrained (must not touch
  `meeting/*.sh`), so RECORDED not fixed: filed ROADMAP `[ROUTINE]` id:a286 + TODO twin + a
  REVIEW_ME box. One-line fix (`rm -- "$tmp_check"`, known-present mktemp file). Root cause is
  an id:34c2 handoff spec/lint gap. NOTE: id:34c2's functional acceptance (validate/mint/echo)
  IS met and its unit test is green — the lint regression is a separate defect, so 34c2 stays
  closed and a286 carries the fix. (id:bbb2, filed this window, already tracks a second id:34c2
  follow-up: the swallowed validator diagnostic in the dependency-absent case.)

**Spec-drift (§4):** no README/ARCHITECTURE/CLAUDE.md drift found for the window's changes
(inbox write-path + install-drift check are internal relay plumbing; CLAUDE.md already
documents the id:1102 install-drift check and the id:e647/b8fa CHANGELOG amendment landed
this window and matches). Relay-contract pointer marker v9 == executor-contract.md — current.

**Relay-doctor (§4b):** 5 findings, all report-only. 4 = cross-ledger drift (id:34c2, id:de36,
id:1735, id:1102 — ROADMAP `[x]`, TODO `[ ]`) — RESOLVED this pass by ticking the TODO twins
after verifying each is genuinely green. Remaining surfaced to REVIEW_ME: 1 parked orphan
branch in loderite (cross-repo, not this repo's disposition) + 1 report-only lodelore inbox
line with a literal `$ID` routed marker (cross-project, not a dead-letter here).

**ROADMAP re-derivation (§5):** roadmap-lint clean. orphan-scan --shipped: id:de31 TICK-READY
but VERIFIED-and-NOT-ticked — its linked test covers a narrower scope than the item's acceptance
(pre-existing REVIEW_ME box already records this); the rest are UNMARKED-GATE/UMBRELLA advisories,
no action. **Re-laned id:4a46 `[ROUTINE]` -> `[INPUT — decision]`** (both ROADMAP + TODO twin): its
body is "Decide whether the event log is meant to be complete… confirm the intended taxonomy
rather than assume it" — a design-judgment decision, not clean executor-actionable routine; the
emit-at-five-sites work is downstream of and gated on that decision. This is a lane correction,
not a scope cut. After the re-lane the only open `[ROUTINE]` is the newly-filed id:a286 lint fix,
so routine_open = 1.

**Reverse-handoff (§5b):** 27 newly-added open `- [ ]` lines this window; the large majority are
`/meeting`-authored design-ledger items (correctly ledger-neutral, `/meeting` owns the "why") or
already-promoted twins (id:1102/1735/34c2/de36/dc5b/4a46/e647/b8fa). No un-promoted
execution-ready item needed a mini-handoff beyond a286.

## 2026-07-17 18:20 — reviewer (claude-opus-4-8)

review + apex fixes: audited 32-commit window since relay-ckpt-20260716-1526 (gaming-scan clean); re-laned 4a46 [ROUTINE]->[INPUT decision]; ticked cross-ledger TODO twins (34c2/de36/1735/1102); fixed live make-test breakage (append.sh bare rm -f -> rm --, a286); shipped id:2630 — classifier no longer spends Opus reviews on non-auditable (ledger/docs/version-bump) diffs. make test 257 green.

## 2026-07-18 09:56 — /meeting Class-1 dispatch (opus, id:b8fa deriver)

Built the b8fa CHANGELOG deriver: relay/scripts/changelog-append.sh derives a CHANGELOG.md entry at integrate from the integrator's own report.summary + worked ids (meeting D2 — no new per-item field). Date-bucketed for version-less repos (this repo, D3), --version release-bucketed for semver repos. Opt-in by construction (no-op unless CHANGELOG.md already exists) — the D4 safety that keeps it off semver repos until e647 bootstraps them. Wired into relay-loop.js integrate step 2b (scoped-add commit of CHANGELOG.md only, id:debf). Bootstrapped this repo's CHANGELOG.md (date-bucketed, from-now, no backfill). tests/test_changelog_derive.sh (8 cases) green; full suite 258/0. b8fa stays OPEN: e647 bump-trigger + semver-fleet rollout remain (D4 ships-together); owner sequencing decision pending.

## 2026-07-18 — /meeting Class-1 dispatch (opus, id:e647 bump trigger)

Built the e647 reviewer-at-integrate SemVer bumper — the sibling of the b8fa deriver, shipping together per meeting 2026-07-17-1541 D4. New `relay/scripts/version-bump.sh <repo> --level minor|patch [--date]`: the level is an INPUT (the reviewer's user-observable judgement, not derivable — D1); detects pyproject.toml then package.json (no manifest → logged no-op exit 0, so version-less repos like this one stay exempt by construction); rewrites only the version line (loose-0.x: patch=z+1, minor=y+1/z=0, major untouched); regenerates the lockfile via an injectable `$VERSION_BUMP_LOCK_CMD` (default `uv lock`/`npm install --package-lock-only`, stubbed hermetically in tests); invokes the repo's OWN `scripts/relock-plugins.sh` for the zkm ~18-plugin uv.lock cascade when present (finding c — never re-implemented); commits manifest+lockfile TOGETHER with scoped `git add -- <path>` (id:debf) leaving the tree CLEAN so clean-tree-gate.sh does not defer; and creates an ANNOTATED tag vX.Y.Z (finding b — lightweight tags are silently skipped by `git describe` without --tags). Wired into relay-loop.js integrate as new step 2a (bump BEFORE the 2b changelog append, threading the resulting `--version` so semver repos release-bucket; refactor-only closes skip both). tests/test_version_bump.sh (9 cases incl. the finding-b lightweight-tag reader assertion) green; registered in Makefile relay_FILES/_EXEC/_ALLOW. Also fixed a latent hermeticity gap in tests/test_relay_doctor_verdict_invariant.sh: it isolated RELAY_INBOX/RELAY_TOML but not RELAY_INSTALL_ROOT, so a manifest-declared-but-not-yet-`make install`ed script tripped its --strict clean assertion via install-drift (id:1102) — now points install-drift at an empty dir (SKIP), the invariant checks unchanged. Full suite 259/0. e647 tag-in-script decision + install-drift note recorded for owner ratification (see report).

## 2026-07-18 10:35 — e647 integration (opus apex review + merge)

Reviewed + integrated the background-built id:e647 (branch worktree-agent-a30372f04107d8384, commit ae39461) into main via --no-ff merge (6c5f84f). Apex review APPROVED version-bump.sh (loose-0.x, anchored version-line rewrite, injectable lockfile regen, scoped clean-tree commit, annotated vX.Y.Z tag per finding b, zkm cascade via the repo's own relock-plugins.sh per finding c) + integrator step 2a (reviewer non-derivable bump judgement per D1, threads bumpVersion into the b8fa changelog --version). Accepted the agent's hermeticity fix to test_relay_doctor_verdict_invariant.sh (isolate RELAY_INSTALL_ROOT — correct scope hygiene, install-completeness has its own test). version-bump.sh symlinked into ~/.claude; agent worktree+branch retired. Full suite 260/0. e647 ticked done; b8fa mechanism complete (only per-semver-repo CHANGELOG bootstrap remains, operational).

## 2026-07-18 20:32 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: 20-commit window since relay-ckpt-20260717-1820 verified green (gaming-scan clean, suite 260/0); ticked shipped id:bbb2; verified e647/b8fa/7d20/fc0f/af5a; routine_open=0 [id:bbb2,e647,b8fa,7d20,fc0f,af5a]

## 2026-07-18 — handoff (relay-20260718-201041-23915-handoff)

C1: docs verified current (CLAUDE.md relay pointer v9 = canonical, README lists all skills) — no changes. C2: promoted 4 open TODO [ROUTINE] items with no ROADMAP twin (unpromoted-scan `promote` disposition), each reusing its TODO `<!-- id -->` token (single-id-two-views): e875 (memory-index.py mis-resolves title:/hook: re-nested under metadata:), b9b5 (model-probe.sh grade `echo`→`printf` flag-robustness), ab5c (flaky test_resource_claim_pid.sh — pid_alive swallows jq read errors), eb46 (relay children need `SUDO_ASKPASS=/bin/false` so a sub-process sudo can't pop a GUI prompt). Open ROADMAP items 8→12. FOUR other `promote`-flagged ids were deliberately NOT promoted: **2e6d** (largely SHIPPED — its executable residual is already tracked as ROADMAP id:7d97, plus an [INPUT — user] settings.json install; promoting it would double-count 7d97); **659c** (already has an OPEN gated ROADMAP twin, route:decision-gate "premise false: edges.json is a co-citation graph"); **d5e0** (a running open-item COUNT summary, not a task — slated for drop per id:1de1); **2d20** (the executable part shipped 2026-06-16; the STILL-OPEN residual — durable auto-closure option (c) — is meeting-gated → id:719e with open design forks, i.e. decision-gate, not clean ROUTINE). C3: RED specs tests/test_model_probe_flag_robust.sh (roadmap:b9b5) + tests/test_memory_index_metadata_nesting.sh (roadmap:e875), both verified EXPECTED-RED; ab5c/eb46 got no fresh red (ab5c = flaky-regression, done-check is 5×-green; eb46 = Workflow-sandbox env, no in-worktree runtime). C4: no BDD (no user-facing surface); flagged eb46's lane judgment call (possible [INPUT — user] re-lane) in REVIEW_ME. C5: skipped — the only non-gated [HARD] is the recurring id:401c strong-model audit (not small-enough-to-finish-safely); left specced. Full suite 260/0, 2 expected-red.

## 2026-07-18 21:04 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

handoff: promoted 4 ROUTINE items (e875/b9b5/ab5c/eb46) into ROADMAP (8→12 open), 2 red specs, suite 260/0 [id:e875,b9b5,ab5c,eb46]

## 2026-07-18 — executor (Sonnet)

Worked id:b9b5 — one-line fix in `tools/model-probe.sh` grade arm: `echo "$output"` →
`printf '%s\n' "$output"` so an output that is exactly `-n`/`-e`/`-E`/`-ne` (or any
literal starting with those tokens) is no longer swallowed by the bash `echo` builtin's
flag interpretation. The existing RED spec `tests/test_model_probe_flag_robust.sh`
(`# roadmap:b9b5`) confirmed RED before the change (all 5 cases failing) and GREEN
after. Ticked the ROADMAP checkbox and ran the full suite: 261 passed, 0 failed, 1
expected-red (an unrelated still-open item). No other files touched.
Friction: none — item was exactly as scoped, a genuine one-line fix with its RED spec
already authored by the reviewer.
refactor: none needed — one-line builtin swap, no new duplication introduced.

## 2026-07-18 21:15 — executor (sonnet, relay-loop)

Closed id:b9b5 — model-probe.sh grade arm swapped echo for printf so a literal -n/-e/-E/-ne output no longer mismatches; RED spec confirmed red then green; full suite 261/0/1-expected-red. [id:b9b5]

## 2026-07-18 — executor (sonnet)

Worked id:e875 — `tools/memory-index.py` (`build_entries`, `hook_from_frontmatter_text`)
now resolves `title:`/`hook:`/`description:` from `metadata.*` when the top-level key
is absent, and emits a LOUD stderr warning naming the file when a hook is resolved only
from `metadata.hook` (never a silent `description:` substitution). Step-1 culprit check:
ruled out `memory-index.py --write` round-tripping as the re-nesting source — it never
modifies memory `*.md` files (only the two index files; confirmed by re-running it over
a top-level-only fixture and diffing byte-identical). The actual writer that re-nests
(Write/Edit path, a frontmatter normalizer, or the backup commit) remains unconfirmed —
out of scope to chase further this session, so the fix is the robust-regardless-of-culprit
Step 2 the item calls for. RED spec `tests/test_memory_index_metadata_nesting.sh`
(`# roadmap:e875`) confirmed failing (4/4 assertions) before the change, green after.
Ticked the ROADMAP checkbox; full suite green: 262 passed, 0 failed, 0 expected-red.
Friction: none.
refactor: none needed — a two-line fallback + one warning print, no new duplication.

## 2026-07-18 21:27 — executor (sonnet, relay-loop)

memory-index.py resolves title:/hook:/description from metadata.* nesting + loud stderr warning (id:e875), full suite 262/0/0 [id:e875]

## 2026-07-18 — executor (sonnet, relay-loop)

Worked id:ab5c — fixed the flaky `test_resource_claim_pid.sh`: `claim.sh::pid_alive` swallowed any transient `jq` read failure (fork/EAGAIN under full-suite process load) as "no live_pid" -> dead, silently stealing a claim whose PID was actually alive. Added a 3x retry (50ms backoff) around the jq read; a genuine absent `.live_pid` still resolves empty on every attempt so the legacy no-`--pid` path is unaffected. Verified with 20 parallel stress runs of the isolated test (all green) plus a full `make test` (262 passed, 0 failed, 0 expected-red). Friction: none — root cause was already diagnosed precisely in the ROADMAP item text, the fix was a direct implementation of it.
refactor: none needed — the fix is a targeted retry loop inside the existing pid_alive() with no new duplication; no unrelated cleanup was in scope for this item.

## 2026-07-18 21:42 — executor (sonnet, relay-loop)

Fixed flaky test_resource_claim_pid.sh (id:ab5c) — claim.sh's pid_alive() now retries the jq read 3x before concluding a PID-anchored claim is dead, eliminating the ~50%-flaky false-dead verdict under full-suite process load; full suite green 262/0/0. [id:ab5c]

## 2026-07-19 12:43 — reviewer (claude-opus-4-8, relay-handoff)

handoff: promote af48 children ac7f (@wire grammar KEYSTONE) / 66d4 (tier-coverage gate) / 78df (consumer-enum aid) — C2 roadmap + C3 apex-authored RED specs (test_wire_grammar_classify.sh, test_review_gate_tier_coverage.sh, test_consumer_enum.sh, all EXPECTED-RED) + C4 REVIEW_ME judgment boxes; suite 262/0/3-xred; gated siblings bea2/2b49/0c86/07dc left unpromoted

## 2026-07-19 14:01 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

hard: closed ac7f (af48 KEYSTONE) — @wire grammar in hard-lanes.md, classify-repo @wire→actionable_routine_open count, new render-verdict.sh drained render-alias; suite 263/0 [id:ac7f]

## 2026-07-19 14:18 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

C5 66d4: shipped review-gate.sh tier-coverage checkpoint gate (mechanizes review.md §3), suite 264/0 green [id:66d4]

## 2026-07-19 14:32 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

C5 78df: shipped consumer-enum.sh spec-completeness listing aid (grep-based artifact-reader enumeration), suite green [id:78df]

## 2026-07-19 14:57 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

C2-C4: promoted id:798d (unpromoted-scan gated-twin fix) with verified RED spec; triaged 6 phantom/mis-classified promote items to REVIEW_ME [id:798d]

## 2026-07-19 — executor (claude-sonnet-5)

Worked id:798d — dropped the `[[:space:]]*$` end-of-line anchor from
`unpromoted-scan.sh`'s twin-check regex (line ~269), so a ROADMAP marker
followed by a trailing gate note (`<!-- id:XXXX --> — 🚧 GATED (auto, id:3801;
...)`, the id:1b1a `gate_line` shape) is still recognized as a real twin
instead of phantom-re-dispatching its TODO source every round. The
`<!-- id:XXXX -->` HTML-comment anchor itself (unchanged) still prevents the
id:1312 bare-prose false-match, so no regression there.
`tests/test_unpromoted_scan_gated_twin.sh` (`# roadmap:798d`) EXPECTED-RED→PASS;
`tests/test_unpromoted_scan_anchoring.sh` (id:1312 regression control) stays
green; full suite 266/0. Ticked both the ROADMAP and TODO twin (id:798d) to
keep the ledgers in agreement.
Friction: none — the RED spec was already authored by the handoff and the
fix was a single-line regex change exactly as specified.
refactor: none needed — one-line regex fix, no new duplication introduced.

## 2026-07-19 15:08 — executor (sonnet, relay-loop)

Fixed unpromoted-scan.sh twin-check end-of-line anchor so auto-GATED ROADMAP items (marker + trailing gate note) are recognized as twins instead of phantom-re-dispatching; id:798d closed, full suite 266/0. [id:798d]

## 2026-07-19 15:29 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

Verified id:798d (unpromoted-scan gated-twin fix) genuinely green — real red→green, RED spec untouched, suite 266/0; reconciled 5 cross-ledger drift twins (e875/b9b5/ab5c/66d4/78df) [id:798d,e875,b9b5,ab5c,66d4,78df]

## 2026-07-19 18:42 — handoff (claude-opus-4-8)

handoff: promoted a17a (state-machine diagram set) to ROADMAP [HARD — pool] + authored the drift-guard RED spec (test_a17a_diagram_state_sync.sh, verified red). Diagram authoring left for pool. Suite 266/0/1-red.

## 2026-07-19 19:13 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

a17a: authored the /relay + /meeting state-machine diagram set (3 Mermaid diagrams) + drift guard-test green; full suite 267/0 [id:a17a]

## 2026-07-19 19:35 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

handoff (claude-opus-4-8): re-laned id:4a46 [INPUT — decision]→[ROUTINE] (owner-resolved handback-log-completeness gate) + RED spec test_handback_invariant_equality.sh; suite 267/0/1-red [id:4a46]

## 2026-07-19 20:51 — reviewer (claude-opus-4-8)

hard-exec id:0534 (mechanical-daemon repo-lease peek-and-defer + RED test) reviewed clean; meeting id:93fe --drain contract phased into 93fe(Phase1)+ebbe(Phase2); os-users 13ae/02c7 provisioned

## 2026-07-19 21:34 — executor (claude-sonnet-5, drain)

drain round 1: execute id:4a46 — handback event log bidirectional invariant (equality over real-worktree subset) + 2 emit sites; reviewed inline (two-pole test, not gamed); suite 270/0/0

## 2026-07-19 21:51 — reviewer (claude-opus-4-8, drain)

drain round 2: independent review of window 2051..HEAD — CLEAN (id:4a46 genuinely green, no gaming, no reopen, no spec-drift; suite 270/0/0)

## 2026-07-19 22:33 — builder (claude-opus-4-8)

build id:176f — mechanical-dispatch gateway + hermetic test (relay-command allowlist, fail-open, 28 assertions incl. chained/substitution refusal); suite 271/0/0; awaiting independent review

## 2026-07-19 22:41 — reviewer (claude-opus-4-8)

independent review: id:176f REOPENED — allowlist bypassable (3 confirmed holes); fix direction recorded; not wired in

## 2026-07-19 23:11 — builder (claude-opus-4-8)

id:176f allowlist hardening — identity-pin (realpath under canonical root), refuse process-substitution + redirection; 18 new refusal assertions (RED-before verified); suite 271/0/0; awaiting re-review

## 2026-07-19 23:19 — reviewer (claude-opus-4-8)

independent re-review: id:176f allowlist fix SOUND (3 bypasses closed, no new holes, tests bite); SHIP; cross-filed

## 2026-07-20 13:17 — reviewer (claude-opus-4-8)

fix gather bugs fa5c + 306d (execute+review SHIP, suite 273/0)

## 2026-07-20 14:04 — reviewer (claude-opus-4-8)

integrate id:be0e (roadmap-lint head-anchor) + id:050b (Makefile-tier fixture)
