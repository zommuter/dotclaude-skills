# Strong-model audit — Run 15 (2026-06-19-2005)

Recurring [HARD — strong model] item id:401c. Adversarial three-pass audit (code review /
security / design coherence) of the relay work since the last audit.

- **Window**: first-seen code since **Run 14**'s own audit commit `61020a0`
  (`61020a0..HEAD`, HEAD `b6f9ae9`). The `relay-ckpt-20260617-1326..HEAD` tag-range
  nominally includes `migrate-state-dirs.sh`, but that file's only change in the range
  IS Run 14's audit commit — already audited, excluded from the first-seen set.
- **First-seen code** (~1.9 kLOC / 9 prod files + test corpus):
  `clean-tree-gate.sh` (new, 93L), `gather-repo-state.sh` (new, 110L),
  `handback-followup.py` (new, 209L), `relay-status-publish.sh` (new, 100L),
  `quota-sample.sh` (new, 180L), `quota-report.py` (new, 125L),
  `relay-loop.js` (+221/−… integration of all the above), `git-lock-push.sh` (+13),
  `profile-run.sh` (+6/−2). Plus the `shard-canary/` model-harness corpus + ~12 test files.
- **Run mode**: Opus apex HARD-execute relay child (id:da26), in worktree
  `relay/relay-20260619-191539-21573-hard`.

## Verdict: CLEAN — no inline code/security fixes needed; 1 LOW flake tracked (id:05e8)

The window is unusually large but is the **L1/L2 token-skeleton + data-loss-fix batch**
(ids aa93 / 11ad / 0d31 / c855 / 3801 / b841 / 2425). It was written to a high bar and
audits clean across all three passes.

### Pass 1 — Code review (correctness, error handling, quoting, races)

- **clean-tree-gate.sh (id:aa93)** — observe-only (`git status --porcelain`), never
  stash/checkout/reset/clean. Porcelain parse `path="${entry:3}"` correct; `--accept`
  exact-path match; `${accepts[@]+"${accepts[@]}"}` is the correct empty-array-safe
  expansion under `set -u`. Fail-safe exit codes (0 = clean, 2 = dirty/error). **Clean.**
- **gather-repo-state.sh (id:11ad)** — collapses ~17 per-repo git calls into ONE JSON
  blob to cut shard TURN COUNT (the measured cost driver, not prompt/ctx size). JSON is
  built in `python3 -c` from **env vars** (not string interpolation) → arbitrary
  multi-line porcelain/roadmap content can never break the JSON or inject. Fail-open
  (`is_git:false`, exit 0). `git fetch origin -q || true` best-effort. **Clean.**
- **handback-followup.py (id:3801)** — `gate_line` swaps the tier tag to
  `[HARD — decision gate]` idempotently (returns None if already gated, respecting a
  human's manual gate); the note is inserted *before* the id comment so the token stays
  end-of-line (find_line/md-merge invariant). Seam dedup is by explicit-id OR
  title-under-parent-marker → no duplicate mint on re-run. All writes go through the
  flock'd `md-merge.py update-ids` + `git-lock-push.sh --ff-only` manifest path; the
  manifest temp file is `unlink`'d in a `finally`. **Clean.**
- **relay-status-publish.sh (id:0d31)** — sentinel split (`===RELAY-EVENTS===`, a
  fixed string with no regex metachars → safe in the `sed` address) is correct; jq
  rendering of claims is guarded; `relay-state-write.sh` re-applies the absolute-path
  (c34a) guard. Collapses a ~40-line haiku prompt to one piped invocation (drift
  surface removed). **Clean.**
- **quota-sample.sh / quota-report.py** — cooperative sampler: reuses the statusline's
  shared `/tmp` cache+lock+backoff (never a second poller); `set -o noclobber` lock
  acquisition; dead-lock reap mirrors the statusline's 30s rule; data appended under a
  dedicated flock; the gated partial-commit path scopes `git add -- "$DATA_REL"` and
  pushes only on an otherwise-clean tree (never rebases over live DIARY.md edits — the
  documented reason it cannot use git-lock-push manifest mode here). report is
  stdlib-only, defensive JSON parse, reset-boundary segmentation keyed on the reset
  DATE to absorb sub-second `resets_at` jitter. **Clean.**
- **relay-loop.js diff** — the four behavioral changes all check out:
  - **quotaThresholds normalization (id:b841)** — nested→flat fold with an
    `A[flatKey] === undefined` guard so an explicit flat override wins. Correct.
  - **discoverCache idle push-seed (id:c855)** — seeds an `idle` entry ONLY when
    `postSig && openRoutine===0 && openHard===0` (provably drained). Read side routes
    `cached.idle` to a `skipped` rollup line (no shard, NOT dispatched); any open work
    or a fail-open empty sig → `delete` the entry → re-classify. Over-counting openHard
    (gated items included) is safe by construction (only 0/0 seeds). **No
    under-invalidation hazard.**
  - **durableHandbackFollowup (id:3801)** — POSIX single-quote escaping
    (`'` → `'\''`) on every interpolated arg; fire-and-forget `.catch` (a follow-up
    failure can never crash the integrator). Correct.
  - **crossedBucket stop-reason (id:2425)** — agent-reported bucket first, old
    `pctRemaining<=10` heuristic demoted to last-resort fallback. Correct.
- **git-lock-push.sh (id:aa93)** — refuses the `pull --rebase --autostash` path on a
  foreign-dirty tree (autostash would RESET a concurrent editor's work outside any lock
  it respects; a stash that fails to re-apply is silent loss). Exit 0 non-fatal,
  work committed-locally. Same data-loss class as clean-tree-gate. **Clean.**
- **profile-run.sh** — removes the bare `"rollup"` PHASE_RULES needle that
  misclassified discover-shard's "SKIPPED ROLLUP" instruction into the `status` bucket
  (hid the bulk of discovery cost — the id:9cb1 measurement bug). Comment added so it is
  not re-introduced. Correct.

### Pass 2 — Security (injection, traversal, secrets, permissions)

- **No command/path/jq injection**: gather-repo-state.sh builds JSON via env vars;
  relay-loop.js escapes every shell arg in the handback follow-up; clean-tree-gate and
  relay-status-publish use fixed-string sentinels/patterns. No `eval`, no unquoted
  expansion into a shell word.
- **quota-sample.sh** holds an OAuth bearer token (`$TOKEN` from
  `~/.claude/.credentials.json`) in a single `curl -sf` to the official
  `api.anthropic.com/api/oauth/usage` endpoint; the token is never logged or written to
  the data file (only utilization percentages are). The credentials path is the
  standard one the statusline already reads. **Accepted** — in-bounds for a local
  sampler; the broker-curl.sh convention is meeting-skill-scoped, not relay.
- No new world-writable files; locks live in `/tmp` (shared by design with the
  statusline) and per-data-dir `.lock` files (gitignored class).

### Pass 3 — Design coherence

- **discover-sig.sh ⟷ gather-repo-state.sh superset invariant holds.** Both emit the
  identical signal set (porcelain, upstream, worktrees, orphans, toml block, roadmap,
  head, tags) with structurally parallel variable lists. This is the CLAUDE.md gotcha
  ("add any new shard signal to discover-sig.sh too"); verified they stay in lockstep,
  so the c3a6 discovery cache and the c855 push-seed cache HIT/MISS coherently — no
  stale-verdict hazard.
- **shard-canary corpus (id:3ea3)** is the correct safety net for the gather-repo-state
  behavior-preservation claim: a golden git-fixture corpus with KNOWN verdicts, run
  on-demand (`make shard-canary`, costs tokens), with zero-token plumbing guarded by
  `test_shard_canary.sh` (green). The refactor changes HOW the shard gets data; the
  canary guards that the verdict JUDGMENT is unchanged. Coherent.
- **No contradictory gates / dead gates** found among the new ids. The
  EXECUTABLE-HARD test (id:2d20) and the push-seed openHard count are mutually
  consistent (push-seed only fires at 0/0, so gated-only repos always re-classify and
  re-apply the gate test).
- **Cross-ledger**: ROADMAP open verdicts unchanged by this audit (id:401c stays open
  by design; the three HARD ids remain `[ ]` in both ROADMAP and TODO).

### Findings ledger

- **LOW / tracked — id:05e8**: `test_git_lock_push_slash_branch.sh` failed on the FIRST
  full-suite run, then PASSED in isolation and on an immediate full-suite re-run
  (76/0). Both it and `test_quota_sample.sh` isolate their state via `mktemp -d` +
  `QUOTA_CACHE` override, so this is NOT new `/tmp` contention from the quota sampler —
  it is a pre-existing real-git fetch/push timing flake (same class as id:16e9 noted in
  Run 14), surfaced (not caused) by the larger parallel suite. Tracked as a
  forward-robustness TODO; the suite is deterministically green on a clean run, so the
  audit's definition-of-done (green suite) is met.
- **No findings silently dropped.** No code/security defect required an inline fix this
  round; the one LOW is tracked above with explicit rationale.

## Done-check

`tests/run-tests.sh` → **76 passed / 0 failed** on a clean run. Audit deliverable (this
note) exists; every finding is fixed, tracked (id:05e8), or explicitly accepted.
