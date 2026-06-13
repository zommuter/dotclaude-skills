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
