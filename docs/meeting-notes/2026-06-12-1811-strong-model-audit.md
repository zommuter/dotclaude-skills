# 2026-06-12 — strong-model audit: code review, security, design coherence

**Started:** 2026-06-12 18:11
**Session:** fables-turn review child (worktree relay/review-20260612-1811)
**Mode:** Class 2 audit record (ROADMAP id:401c, first run — no meeting held; three-pass solo audit)
**Topic:** Adversarial review of all work since `fable-ckpt-20260612-1328` (handoff pilot + five Sonnet executor items + integration-defect fixes): correctness, security, and design coherence.

## Context

ROADMAP id:401c specifies a recurring strong-model audit after each significant
executor batch. First run window: `fable-ckpt-20260612-1328`..HEAD — 23 files,
~676 insertions. Major artifacts in scope: `git-lock-push.sh` `--ff-only`/
`--follow-tags` mode, `fables-executor/SKILL.md` + pointer, `broker-curl.sh say`,
`statusline` token display, Makefile nested-skill installer, `tools/ctx-budget.sh`,
two new test files, `broker-mode.md` Discussion rewrite. Every finding below is
fixed inline, tracked with a token, or explicitly accepted with rationale.

## Pass 1 — Code review

- **F1 (FIXED)** `git-lock-push.sh` parsed the upstream ref with `tr '/' ' '`,
  so any branch whose name contains a slash (`origin/relay/review-x` →
  `origin relay review-x`) broke the remote/branch split; the `ls-remote` gate
  then failed and the pull step was **silently skipped** (push then fails
  non-fast-forward when the remote is ahead). The new `--ff-only` relay path
  made slash-named branches a realistic case. Fixed: split at the FIRST slash
  only; hermetic defect test `tests/test_git_lock_push_slash_branch.sh` added
  (verified red against the old parse, green now). Commit `97152df`.
- **F2 (verified, no action)** `tests/test_broker_say.sh` original fixture was
  self-contradictory: `'\''` inside `$'…'` ended the ANSI-C context early, so
  the input had 1 real newline (not 3) and a double backslash where the
  assertion expected one — **no implementation could have passed the original
  test**. The executor's one-line fixture fix (`\'`) is verified
  equivalent-or-stricter by byte-dump comparison and resurrection run;
  assertions untouched. (Test-integrity audit detail; also in review report.)
- **F3 (ACCEPTED)** `git-lock-push.sh` manifest mode `git commit` fails loudly
  (set -e) when the manifest stages no changes. Loud failure is preferable to a
  silent no-op; the caller controls the manifest.
- **F4 (ACCEPTED)** `make uninstall-fables-turn` removes symlinks but leaves
  empty `references/`/`scripts/` dirs under DEST_DIR. Cosmetic; harmless.
- **F5 (ACCEPTED)** `humanize_tokens` renders ≥1M as e.g. `1500k` (no `M`
  tier). Out of spec scope and rare at current context sizes; revisit if seen.
- **F6 (ACCEPTED)** `tools/ctx-budget.sh` uses `find "$ROOT" -name SKILL.md`
  (any depth) where the spec said `*/SKILL.md`. Broader is safe for an
  advisory exit-0 logger; no stray SKILL.md exists outside skill dirs.
- **F7 (ACCEPTED)** `ckpt-tag.sh` flocks `$(git rev-parse --absolute-git-dir)/relay-ckpt.lock`,
  which is worktree-specific — two worktrees of the same repo would not share
  the lock. The orchestrator invokes ckpt-tag once per repo per turn from the
  main checkout, and the `-2/-3` tag-collision suffix loop mitigates the
  residual race. Re-examine only if multiple same-repo ckpt callers appear.

## Pass 2 — Security

- **F8 (FIXED)** `broker-curl.sh` interpolated `$PORT` unvalidated into
  `http://127.0.0.1:${PORT}`. PORT can originate from
  `/tmp/meeting-rpg/broker.json` (world-writable directory): a poisoned value
  like `:@evil.com` relocates the URL **host**, exfiltrating meeting text
  (POST bodies include persona/discussion content). Fixed: hard-fail unless
  `^[0-9]{1,5}$`. Commit `a10102d`.
- **F9 (ACCEPTED)** `$SESSION` appears unencoded in query strings
  (`?session=${SESSION}`). Session ids are self-generated tokens, never
  user-supplied; all JSON bodies already go through `jq --arg`. Revisit if
  session ids ever become external input.
- **F10 (no finding)** `broker.py` and `tests/fixtures/mock-broker.py` both
  bind `127.0.0.1` only. Loopback still admits other *local* users on a
  multi-user host; accepted on single-user machines (zomni/cartmanjaro).
- **F11 (no finding)** `discover-repos.sh` is read-only, parses only
  user-owned files (`state.json`, `relay.toml`); `ctx-budget.sh` and the
  Makefile additions consume no untrusted input. `mock-broker.py` pyright nit
  already tracked as TODO id:e956.

## Pass 3 — Design coherence

- **F12 (FIXED)** TODO.md relay mirror said `3 open ROADMAP items` while only
  2 were open: two executor sessions both logged a `4→3` decrement (id:1ec1
  and id:3b02 raced on the count). Resynced this turn (now 1 after ticking
  id:401c). The mirror is manually decremented and mechanically re-derived at
  each review — acceptable drift mode, self-healing per turn.
- **F13 (TRACKED — id:697e)** `fables-executor/SKILL.md` specifies self-report
  format `[YYYY-MM-DD executor <tier>] Worked id:… `, but every actual
  RELAY_LOG entry (and `ckpt-tag.sh` itself) uses `## YYYY-MM-DD — <label>`
  headings. Content fields are identical, merge=union unaffected, so no
  behavioural fix now; align the contract example at the next natural vN bump
  (clarification only — per the skill's own Maintenance rule, no bump for it).
- **F14 (ACCEPTED)** `broker-mode.md` §Discussion now composes the full block
  before one `say` POST batch, replacing compose→POST→compose streaming. The
  renderer still paints per line (one `/event` per line), but lines arrive in
  a burst and the `kind=opener` t0 now marks batch start, not authoring start —
  TTFL measurements before/after id:3b02 are not directly comparable. This
  trade was sanctioned by the id:3b02 acceptance criteria (ctx win ~25–35
  tool-call records → ≤10); noted here so cost-calibration consumers know.
- **F15 (FIXED)** ARCHITECTURE.md §3/§5 still described de9c and 3b02 as
  pending; §9 lacked ctx-budget.sh. Synced, plus CLAUDE.md install list and
  tools/ row. Commit `b5ce74f`.
- **F16 (assessed — stays parked)** TODO id:6a3c ([HARD] cross-project
  dependency audit for review mode) was considered for ROADMAP promotion and
  rejected: ROADMAP items execute inside a single-repo worktree, while 6a3c
  inherently reads *other* repos (meeting-rpg vs meeting/, shared broker API)
  and modifies the fables-turn review procedure itself. It is reviewer-mode
  tooling, correctly parked in TODO.md until ≥2 active relay repos exist.
- **Gate sanity check**: no never-fires gates found. id:15e9 gate already
  marked met; id:5ab4 needs ≥2 full relay turns (this turn is the second —
  fires next); id:7b23, id:4f5f, id:cbb5 gates all reachable.

## Decisions

- **D1 — Fix-inline threshold**: F1 and F8 were fixed in this worktree with
  tests/guards (separate commits); everything else is tracked (F13 → id:697e)
  or accepted above with rationale. No finding dropped.
- **D2 — id:6a3c stays in TODO.md** (F16): cross-repo scope disqualifies it
  from the single-repo ROADMAP contract.
- **D3 — Audit cadence confirmed**: subsequent id:401c runs diff against the
  most recent `fable-ckpt-*` tag, same window as review step 2. Checkbox is
  ticked per-run; the reviewer re-opens it when a new executor batch lands.

## Action items

- [x] Fix slash-branch upstream parse in git-lock-push.sh + defect test. <!-- id:401c -->
- [x] Add numeric-port guard to broker-curl.sh.
- [ ] Align fables-executor SKILL.md self-report example with the de-facto `## date — label` RELAY_LOG heading format at the next natural contract vN bump (no bump for this alone). <!-- id:697e -->
