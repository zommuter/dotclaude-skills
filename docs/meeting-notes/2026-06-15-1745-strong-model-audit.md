# 2026-06-15 1745 — strong-model audit: code review, security, design coherence

**Started:** 2026-06-15 17:45
**Session:** relay HARD-execute child (worktree relay/relay-20260615-161339-1270-hard), Opus-apex
**Mode:** Class 2 audit record (ROADMAP id:401c, third run — three-pass solo audit, no meeting held)
**Topic:** Adversarial review of the work landed since the previous strong-model audit
(`2026-06-15-1520-strong-model-audit.md`, which itself diffed against `fable-ckpt-20260612-1827`).
Correctness, security, design coherence.

## Context

ROADMAP id:401c specifies a recurring strong-model audit after each significant executor /
design batch, each run diffing against the most recent checkpoint. The previous (15:20) run
covered the relay-script surface and stated "next run diffs against this checkpoint." Its work
landed around `relay-ckpt-20260615-1559`.

This third run's window is **`relay-ckpt-20260615-1559`..HEAD** — a bounded, in-budget batch
(~1060 insertions / 23 files) comprising the five ROUTINE items closed at the 1731 checkpoint
plus the anti-gaming design:

- `gaming-scan.sh` (id:fa05) — new mechanical gaming-detector script + hermetic tests
- `relay-state-write.sh toml-set` hardening (id:c8db) — the F1/F2 fix the 15:20 audit filed
- quota-stop reason surfacing (id:8c35)
- `review.md §2` gaming-scan delegation (id:dfaf)
- supervisor gaming-flag rate logger in `relay-loop.js integrate()` (id:3826)
- parallel-shard discovery + RELAY_STATUS off-critical-path in `relay-loop.js` (id:9ed4, id:cb50)
- the deprecated-alias-stub untrack (commit 608800b)
- the anti-gaming design note (id:2909)

**Surface audited (read in full):** `relay/scripts/gaming-scan.sh`, the full
`relay-ckpt-20260615-1559..HEAD` diff of `relay/scripts/relay-loop.js`,
`relay/scripts/relay-state-write.sh`, `relay/references/review.md`,
`tests/test_gaming_scan.sh`, `tests/test_gaming_logger.sh`, `tests/test_relay_executor.sh`,
`tests/test_relay_loop_structure.sh`, and commit 608800b.

Every finding below is fixed inline, tracked with a token, or explicitly accepted with
rationale. No finding is silently dropped.

## Pass 1 — Code review (correctness)

- **C1 (FIXED inline — broken test, false "green" claim).** Commit `608800b` ("untrack the
  deprecated fables-turn / fables-executor alias stubs") `git rm --cached`'d
  `fables-executor/SKILL.md` (+ `.gitignore`, Makefile SKILLS removal) and updated
  `test_makefile_skills.sh` to match — but **overlooked `test_relay_executor.sh` §8**, which
  still asserted `[[ -f "$SRC_DIR/fables-executor/SKILL.md" ]]` (the stub *must exist*). After
  the untrack, that test FAILS on any fresh clone / CI checkout (the untracked dir isn't there).
  The commit message's "Suite 45 green" claim was wrong — the dir lingered locally as an
  untracked redirect, masking the failure on the author's machine. On this audit's clean
  worktree the suite was **47 passed / 1 failed (`test_relay_executor.sh`)** on arrival.
  **Fix:** rewrote §8 to assert the stub is *untracked* (via `git ls-files --error-unmatch`,
  the tracked-set, not the filesystem — a local fat-finger redirect dir may still exist), with
  a tarball fallback to on-disk absence. Suite is now **48 passed / 0 failed**. This mirrors
  exactly the update the same commit made to `test_makefile_skills.sh`; it was simply missed
  for the second test that referenced the stub.

- **C2 (FIXED inline — dead telemetry feed; logger/dispatch-contract contradiction).** The
  id:3826 gaming-flag rate logger (`logGamingFlags`, `relay-loop.js` ~L897) reads
  `report.gaming_flags`, `report.verified_green`, and `report.reopened` from each REVIEW
  unit's return. The review CONTRACT doc (`review.md §6`, L165-167) defines all three in its
  return schema, and the logger code + `test_gaming_logger.sh` agree with each other. **But the
  actual dispatch prompt** issued to the review child (`unitPrompt`, `relay-loop.js` L738 —
  the single `Return: contract_met, …` line shared across verdicts) **never asked the child
  to return those three fields.** A child returns only the StructuredOutput its prompt
  requests, so `report.gaming_flags` et al. were always `undefined → []`. **Net effect: every
  review logged `{closed_ids:[], gaming_flags:[], reopened:[], verified_green:[]}` — the
  base-rate signal the id:2909 meeting mandated ("so 'if flags start firing' can be measured")
  was a completely inert channel.** The static `test_gaming_logger.sh` passed because it only
  checks the logger's *code structure*, never an end-to-end review with populated fields.
  **Fix:** appended a review-only clause to `unitPrompt`'s return contract requesting
  `verified_green` / `gaming_flags` / `reopened` (gated `unit.verdict === 'review'`, pointing at
  review.md §6). Added a regression guard `(19)` in `test_relay_loop_structure.sh` that ties
  the consumer (`report.<field>`) to the dispatch contract (the `Return:` line must name all
  three) so the contradiction cannot silently reappear. Suite green.

- **C3 (verified — toml-set hardening is correct, closes 15:20 F1/F2).** The id:c8db change to
  `relay-state-write.sh toml-set` correctly addresses both findings the prior audit filed:
  **F1** — `value` now flows via `ENVIRON["TOML_VAL"]` instead of `awk -v val=`, so awk's
  C-style backslash-escape processing can no longer mangle a value containing `\t`/`\\`;
  **F2** — the key is matched by a literal fixed-width prefix compare
  (`substr($0,1,klen)==key` then a `^[ \t]*=` tail check) instead of being spliced into a
  regex, so a key with regex metacharacters can never match the wrong line. `hdr`/`key` remain
  `-v` (safe identifiers, no backslash risk). The `test_relay_state_write.sh` additions cover
  the backslash and metacharacter cases. Correct and complete.

- **C4 (ACCEPTED — minor, gaming-scan `ADDED_SKIP` line numbers are advisory).** `gaming-scan.sh`
  Check 2 tracks an approximate line number for each `ADDED_SKIP` flag by parsing `@@ … +c,d @@`
  hunk headers and incrementing on context/added lines. The arithmetic is best-effort and may
  be off-by-one in edge cases (e.g. it increments `lineno` on the first added line before
  emitting, and treats `^[^-]` context lines uniformly). This is purely *informational* — the
  detection (that a skip was added at all) is what reopens the item, and `test_gaming_scan.sh`
  asserts the flag fires by `<path>` prefix, not by exact line. Accepted as cosmetic; no action.

- **C5 (verified — parallel-shard discovery preserves the single-agent shape).** The id:9ed4
  split (PRELUDE does the once-only consuming work — `inject.sh take`, `claim.sh peek`, runId,
  own-repo list; N parallel SHARD classifiers do the per-repo verdicts) correctly funnels the
  CONSUMING / single-shot operations into the prelude (`inject.sh take` must run exactly once —
  it consumes; the prompt says so explicitly) and passes the live-claim set to shards as DATA
  so no shard re-runs `claim.sh peek`. The merge re-assembles `{runId, ts, units, surfaced,
  skipped}` byte-identically (PRELUDE/SHARD schemas reuse `DISCOVER_SCHEMA`'s item shapes);
  `shardOk` guards an all-shards-failed round into the same "discovery failed" return as before.
  Round-robin chunking (`idx % SHARDS`) balances repos regardless of order. No double-consume,
  no double-classify path.

## Pass 2 — Security audit

- **S1 (verified — gaming-scan.sh is hermetic, no injection surface).** All git operations
  `cd "$REPO_ROOT"` and are scoped to it; the since-ref is validated with `git rev-parse
  --verify "$SINCE^{}"` before use; the diff pathspecs are a fixed array, not interpolated user
  data. The grep patterns are single-quoted literals. Filenames from `git diff --name-only` are
  read via `while IFS= read -r path` (NUL-safe enough for the `\n`-delimited git output, and
  paths are repo-internal). No `eval`, no command construction from diff content. The script
  reads diffs and emits flag strings — it never writes or executes anything. Clean.

- **S2 (ACCEPTED — gaming-flags log write: relay-internal data, safe single-quote escaping).**
  `logGamingFlags` builds a JSON line and embeds it into a Haiku agent prompt as a
  single-quoted shell literal: `printf '%s\n' '${json.replace(/'/g, "'\\''")}' >> "${logPath}"`.
  The `replace(/'/g, "'\\''")` is the canonical safe single-quote-escape for a `'…'` shell
  literal, so even a value containing a quote cannot break out. Moreover the JSON's contents
  (`gaming_flags`, `verified_green`, `reopened`, repo, runId) are relay-INTERNAL structured
  data returned by a relay review child — not arbitrary external/network input. `logPath` is a
  fixed `$HOME`-derived constant. The write is fire-and-forget with `.catch` (a log failure is
  non-fatal, never stalls integration). Accepted; no change. (Sidenote: now that C2 is fixed,
  this channel will actually carry data — the escaping was correct all along, it just had
  nothing to escape.)

- **S3 (verified — no new secret/credential surface in the window).** None of the new code
  touches credentials, tokens, or network endpoints beyond the already-audited `quota-stop.sh`
  (unchanged this window). The new agents (`discover-prelude`, `discover-shard`, `gaming-log`)
  run shell commands that are all repo-internal git / file operations or the fixed `claim.sh` /
  `inject.sh` helpers. No new attack surface introduced.

## Pass 3 — Design coherence

- **D1 (verified — review.md §2 delegation is internally consistent).** The id:dfaf split of
  `review.md §2` into §2a (mechanical `gaming-scan.sh` pass) + §2b (judgment residue:
  resurrection-check, fixture special-casing, green regression-guards, unverified-not-a-pass)
  is coherent: the three mechanical checks gaming-scan.sh emits (`DELETED_TEST`/`ADDED_SKIP`/
  `REMOVED_ASSERT`) exactly match the three it documents, and §2b explicitly keeps the
  bash-impossible judgment checks in prose ("This is model-judgment; no mechanical bash check
  can reliably detect it"). The §2 instruction to surface every flag "in `gaming_flags` in the
  return report" now actually reaches the logger thanks to the C2 fix — before C2 it was a
  contract that the dispatch prompt silently dropped.

- **D2 (verified — RELAY_STATUS off-critical-path is race-safe).** id:cb50's `scheduleStatusWrite`
  correctly snapshots state at schedule time (`snapshotState` deep-copies all arrays + the
  module-level `stopReason`) so a write queued on the serialized `statusTail` cannot read
  state mutated by a later round; writes are serialized on a single promise tail
  (`statusTail = statusTail.then(...)`) so concurrent schedules never clobber; each `.catch`
  makes a failed write non-fatal; and BOTH return paths (`round===1` discovery-fail early
  return AND the normal end) `await statusTail` so the final status is durable before the run
  returns. The `test_relay_status_offcrit.sh` additions pin this. No lost-final-write path.

- **D3 (verified — stop-reason taxonomy is exhaustive and machine-readable).** id:8c35's
  `stopReason` is set on every quota stop and distinguishes the cases the operator needs:
  `quota-stale-cache` (agent death OR exit 2 — can't verify, conservative stop),
  `quota-exhausted:<bucket>` (exit 1, with the first ≤10%-remaining bucket named), default
  `:unknown`. It flows into both the RELAY_STATUS "Stop reason" section (via `buildStopReasonLine`)
  and the run's return object. Consistent with the conservative-on-uncertainty quota stance the
  earlier audits verified. No gate that mislabels a stop.

- **D4 (verified — alias-stub retirement is coherent across surfaces).** Commit 608800b's
  untrack is internally consistent *except* for the one test it missed (C1, now fixed): the
  stubs are removed from `.gitignore`-tracking, the Makefile SKILLS list, the CLAUDE.md Layout/
  commands tables, and `test_makefile_skills.sh` — all aligned on "fables-* alias stubs are
  retired; the `~/.claude/skills` symlinks resolve and a local untracked redirect dir may
  remain." The migration note ("No remaining cron/scheduled jobs or invocations reference the
  old names") is the kind of claim a future review should spot-check, but is plausible and not
  contradicted by anything in-tree. With C1 fixed the retirement is fully coherent.

## Outcome

**Two real defects found and FIXED inline, both introduced in this window:**

1. **C1** — `608800b` broke `test_relay_executor.sh` (asserted a stub the same commit removed)
   and shipped a false "Suite 45 green" claim. The clean worktree was **1 test red** on
   arrival. Fixed: §8 now asserts the stub is untracked. Suite **48/0**.
2. **C2** — the id:3826 gaming-flag rate logger was a **dead telemetry feed**: the review
   dispatch prompt never requested the `gaming_flags`/`verified_green`/`reopened` fields the
   logger reads, so it logged empty arrays for every review and the id:2909 base-rate signal
   produced nothing. Fixed: the review-unit return contract now requests them; a new regression
   guard `(19)` ties the dispatch contract to the consumer so it can't drift again.

The id:c8db toml-set hardening correctly closes the prior audit's F1/F2. The parallel-shard
discovery (id:9ed4), off-critical-path status write (id:cb50), stop-reason taxonomy (id:8c35),
review.md delegation (id:dfaf), and gaming-scan.sh (id:fa05) are all correct and internally
coherent. No security finding required action (S1-S3 clean/accepted). One cosmetic accept (C4 —
advisory line numbers in gaming-scan). id:401c remains an open recurring item (next run diffs
against this checkpoint).

### Sizing note

The window was small enough (~1060 insertions, one cohesive batch) to audit line-by-line in one
bounded turn — both code defects were caught, both fixes are trivial and verified green, and the
full suite passes. This is the in-budget shape the C5 "only if small enough to finish safely"
discipline calls for; no half-audit, no deferred surface.
