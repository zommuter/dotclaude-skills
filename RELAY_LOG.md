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
