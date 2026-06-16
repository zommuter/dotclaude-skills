# Strong-model audit — run 8 (2026-06-16-0650)

Recurring audit item id:401c. Window: `relay-ckpt-20260615-2150..HEAD`
(the audited surface since run 7's end-checkpoint).

## Window

First-seen **code** since run 7:

- `relay/scripts/profile-run.sh` (409 lines, new — id:a59e) — Workflow run profiler:
  per-agent records from journal/transcript files, concurrency-over-time, round-boundary
  block-vs-queued classification, per-phase/per-model aggregates.
- `relay/scripts/profile-runs-batch.sh` (206 lines, new — id:08a3) — batch driver folding
  many runs into cross-run stats + the "single-Haiku-blocked discovery" claim test.
- `tests/test_profile_run.sh`, `tests/test_profile_runs_batch.sh` (hermetic, fixture-fed).
- `Makefile` — both scripts joined `relay_FILES`/`_EXEC`/`_ALLOW` (install-manifest correct).
- Non-code: `docs/relay-profiling-2026-06-15.md`, TODO/TODO.archive/RELAY_LOG churn.

## Pass 1 — code review

**Clean on correctness.** Both scripts are `set -euo pipefail`, stdlib-only (bash +
python3), pure-read (no network, no mutation, no model invocation). Arg parsing handles
both `--flag value` and `--flag=value`; unresolvable arg / no-runs paths exit non-zero
with a stderr message. The python embedded heredocs guard JSON decode (`try/except
json.JSONDecodeError`), tolerate missing timestamps/usage keys (`int(... or 0)`),
and handle the `span <= 0` degenerate run. Tests are non-vacuous (real fixture journals,
assert the claim-metric and the resolve-by-substring/wf-id paths).

One **dead-code** residue noted, **not fixed** (cosmetic, zero behavioural effect): in
`profile-run.sh` the `at_cap_intervals`/`prev_t`/`prev_c` block (≈L277-281) including
`for t, c in [(e[0], None) for e in []]: pass` iterates an empty list and is superseded
by the real `time_at_cap` event-sweep immediately below it. Left as-is — accepted risk:
purely a clarity wart, removing it touches working code for no functional gain; flagged
here so it isn't mistaken for load-bearing logic next pass.

## Pass 2 — security audit

**Clean.** No injection surface: the only place user input meets a shell tool is
`grep -ql -- "$ARG"` and `grep -ql '"verdict"'` — the former uses `--` to stop option
parsing, and ARG is never `eval`'d or word-split into a command. `find ... -name
journal.jsonl` is literal. No secrets are read or emitted (pure timing/token metadata).
File reads are all under the resolved `$WFDIR` / search roots; no path-traversal lever
(ARG either names an existing dir-with-journal, a `wf_*` id matched under roots, or is a
grep substring — none constructs a write path). `mktemp -d` + `trap rm -rf` in the batch
driver is correctly scoped. No `sudo`, no package install.

## Pass 3 — design coherence

**One drift fixed inline.** Both scripts' header comments documented the default search
root as `~/.claude/projects/*/subagents/workflows` (one wildcard), but the actual glob
(and the real on-disk layout, verified: `projects/<slug>/<uuid>/subagents/workflows`) is
`projects/*/*/subagents/workflows` (two wildcards). The code is correct (the be6b98b
commit "fix profile-run search-root glob" already corrected the glob); the comments were
left stale and would mislead a maintainer reading the usage block. Updated both comment
lines to the two-wildcard form to match the code.

**Cross-ledger state coherent.** ROADMAP: 0 open `[ROUTINE]`, 3 open `[HARD]`
(id:401c recurring, id:414a gate-cleared, id:3346 still gated). The TODO.md relay mirror
line (id:d5e0) agrees exactly (3 HARD, 0 ROUTINE). The classifier's `hard` verdict for
this turn is consistent with that state.

## Verdict

**Clean** — no code or security defects. One coherence drift (stale search-root glob
comment ×2) fixed inline. One cosmetic dead-code residue flagged and explicitly accepted.
Full suite green (52/0) before and after the comment fix.
</content>
</invoke>
