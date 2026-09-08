# Session handover -- 2026-09-08 (Opus 5, 1M)

Point-in-time snapshot for the next session. Durable detail lives in the ledger items and
notes cited below -- read those; do not trust this doc if it disagrees with them.

## Can the pool be run again? YES -- verified, not assumed

Checked at handover, all green:

| Precondition | State |
|---|---|
| `make test` | **609 passed, 0 failed, 0 errored, 5 expected-red** |
| Working tree | clean, pushed (`eeead92e`) |
| Parked orphans, all own repos | **0** |
| Stranded branches | **0** |
| Relay worktrees on disk | **0** |
| Live claims | **0** |
| Live pools | none (only the non-pool `discovery-producer` heartbeat) |
| `ratification_pending` | **0** |

Run `/relay --intensive` (or plain `/relay`) as normal. The last run stopped cleanly via a
targeted sentinel; nothing is wedged and no residue is left to trip over.

**One caveat that is NOT a blocker:** the `id:b54b` hermeticity guard false-fires while relay
worktrees are live (`id:c132`/`id:b87b`). There are none right now, so a suite run today is
trustworthy; during a pool run it may fire spuriously. Re-run once before believing it.

## READ THIS FIRST: the custom agent definitions

**A changed or newly installed agent definition is NOT visible to an already-running
session** -- the registry is read once at startup, and dispatching an unregistered type
fails with `Agent type '<name>' not found`. `make install-agents` does not activate
anything; a restart does. This cost this session two measurement rounds.

| Type | Purpose |
|---|---|
| `relay-implementer` | the trimmed executor definition (`id:c3c1` step 3); `Bash, Read, Edit, Write`, sonnet |
| `echo-runner` | mechanical one-command dispatch; live consumer in `mechanical-proxy.py` |
| `preamble-probe-wide` | MEASUREMENT ONLY -- all 21 default tools |
| `preamble-probe-narrow` | MEASUREMENT ONLY -- Bash only |
| `preamble-probe-exec` | MEASUREMENT ONLY -- the realistic executor set |

**`relay-implementer` deliberately has NO `Skill` tool.** An earlier revision added it,
reasoning that an executor needs `/relay executor` to load its contract. That premise is
FALSE: `relay-loop.js:3192` sends every child an explicit SKILL COUNTERMAND (`id:9eb7`)
because the Skill tool ignores the `executor` arg and injects the ~26.4k-token ORCHESTRATOR
SKILL.md, which does not contain the contract. The contract is loaded with **Read**, from
`~/.claude/skills/relay/references/executor-contract.md` (~5.5k). Do not re-add Skill.

## FIRST JOB: re-run the three probes

They were repaired after the last measurement and are invisible until a restart, so the
corrected split has never been taken. Dispatch each with `Reply with exactly the word OK.`
and read the first-request context (method at the foot of this doc).
`default - wide` = system-prompt cost; `wide - exec` = the tool cost an executor cannot
avoid; `exec - narrow` = the rest.

**Do not trust any prompt-vs-tools split quoted anywhere before that run.** `Glob`, `Grep`
and `TodoWrite` are NOT real tool names in this harness, so the original probe declared 11
tools of which only 8 resolved, against a real roster of 21.

## What LANDED this session

- **`id:c3c1` step (1) DISCHARGED** -- the owner's 2026-08-22 "prove the shrink cheaply
  before migrating" ruling, unexercised for three weeks. `echo-runner` at matched haiku:
  **54,844 -> 29,796 = 25,048 saved, 45.7%.** The mechanism works. The prompt-vs-tools SPLIT
  was measured, found invalid, and **retracted** -- see the probe note above.
- **`id:c3c1` steps (3) and (4)** -- `agents/relay-implementer.md` authored on the owner's
  ratified subset, and `EXECUTE_AGENT_TYPE` wired into `relay-loop.js`: off by default,
  execute-lane only, fail-loud on a missing type. Adversarially reviewed; the key name
  `opts.agentType` is CORRECT (the harness echoes it back in a real error), so it is not an
  `id:d35a` no-op.
- **`id:77d9`** -- the preamble is ~82k, not the 58.6k banked by `id:c3c1`/`id:10dc`: ~40%
  growth in 18 days. Sonnet wall ~176.7k; fixed floor ~95k (54%). 5 of 15 execute children
  died `Prompt is too long` in run `relay-20260908-174448-4421`, all Sonnet, 0 of 12 Opus.
- **`id:3cc7`** -- `agent-failures` reported 2 while 7 children failed, disjoint sets. The
  data is collected correctly (the Workflow `<failures>` block is complete); the status
  write drops it, so the fix is plumbing, not instrumentation.
- **`id:e63d`** -- the `id:1432` repeat-handback alert keys on repo+verdict, so it could not
  express that wisenheimer refused the SAME six ids in all three handbacks.
- **`id:4263`** -- `relay-reconcile.sh --integrate` pushes `--all` and auto-publishes to a
  PUBLIC remote, violating `id:f66e`. **Escalated:** one such push also DRAINED the
  `ratification_pending` queue (6 -> 0), because `ratify-queue.sh` self-verifies via
  `git ls-remote`. The queue that exists to hold a public push for an owner decision was
  cleared BY the unreviewed push. Fired three times tonight.
- **`id:0640`, `id:0220`, `id:3294`, `id:4839` (REPO_KEY finding), `id:a0a8`** filed/routed.
- **Reconcile swept clean.** Integrated `8372-0`, `45ff-0` (trustless-ai), `5ad9-0`,
  `aa5e-0`. Discarded `64f9-0`, `c655-0`, `repo-0`, and the 09-05 hanging branch. Every
  disposition was verified in a scratch worktree first, never on the strength of a stamp.
- **Global `CLAUDE.md`**: two owner directives, on `zomni/claude` (NOT `main`) --
  **don't install software** (inverted from which-installer; project-local `uv`/`pnpm`/`lake`
  explicitly allowed), and the **btrfs CoW directive for Lean** (`~/src/leancow`).

## OPEN threads, priority order

1. **Re-run the probes** (above). Everything about sizing the trim waits on it.
2. **`EXECUTE_AGENT_TYPE` is off by default and needs front-door threading.** The Workflow
   sandbox has no `process.env`, so the env var only works if `/relay` reads it and passes
   `args.EXECUTE_AGENT_TYPE`. Same shape as `POOL_WIDTH`; a forgotten thread means the knob
   is silently off.
3. **The fail-loud regex is unproven against a live rejection.** It matches all three real
   error spellings found on disk, but a harness reword disarms it silently.
4. **`executor-contract.md:229-243` tells children to prefer `Grep`/`Glob`/LSP** -- tools
   that do not exist in this harness. Pre-existing; same fictional-name class that
   invalidated the probe measurement.
5. **`id:4263` is unfixed** and fires on every reconcile integrate.

## Corrections made this session -- do not rebuild on the superseded versions

- `id:0640`'s events-feed half is **RETRACTED**: `relay-events.jsonl` is complete-but-
  delayed (the `id:c8b6` off-critical-path flush), not lossy. The `RELAY_STATUS.md` half
  stands and is wider than filed (12 of 59 unaccounted at round 6).
- `id:c3c1`'s "gated on the `id:4313` do-not-modify directive" is **wrong twice over**: it is
  not a standing gate (the item is closed), and it does not "say nothing about relay-loop.js"
  (it says exactly that, verbatim). It is a **spent** time-bound directive -- "loderite is
  running fine on it", 2026-07-30. Converting it into a permanent gate suppressed step (4)
  for weeks.
- `fa13`'s `[INTENSIVE - local-llm]` tag was **earned**, not inherited. `id:45ff` is the one
  that was MIS-tagged (missing `[INTENSIVE]`); fixed in trustless-ai.

## Measurement method, so it is not re-derived

First-request context = `input_tokens + cache_creation_input_tokens + cache_read_input_tokens`
on the first assistant message with a usage block (the `id:10dc` method). **Grepping
transcripts for `Prompt is too long` returns ~10x false positives** -- `RELAY_STATUS`
payloads and ledger prose quote the phrase, and `id:7829`'s own title contains it. Filter to
`isApiErrorMessage:true` / `model:"<synthetic>"` or the count is meaningless.
