# Session handover -- 2026-09-08/09 (Opus 5, 1M)

Point-in-time snapshot for the next session. Durable detail lives in the ledger items and
notes cited below -- read those; do not trust this doc if it disagrees with them.

*Second half written unattended at 03:47 on 09-09 by a scheduled backstop, after the
overnight pool stopped without sending a completion notification.*

> **CORRECTED 2026-09-09 by the following session (interactive).** The backstop's account of
> the pool's death is wrong in four places; the diagnosis is now `id:76e4` /
> `docs/ledger-notes/76e4.md`. Corrections are marked inline below. In short: the run did not
> crash, it **blocked on a permission prompt nobody could answer**, and the `id:98f0` watchdog
> **did** fire. Where this doc and `76e4.md` disagree, `76e4.md` wins.

## Can the pool be run again? YES -- verified at 03:47 on 09-09, not assumed

| Precondition | State |
|---|---|
| Working tree | clean, pushed (`98fc043a`) |
| Parked orphans, all own repos | **0** -- nothing at risk |
| Retirable worktree residue | **4** (merged, no unmerged work) -- see below |
| Live pools | none (only the non-pool `discovery-producer` heartbeat) |
| `make test` | **610 passed, 0 failed, 5 expected-red** (measured 09-08 pre-pool; NOT re-run after the pool's own commits -- re-run before trusting it) |

**Retirable residue, deliberately LEFT for you** (`relay-reconcile.sh --all` says no work is
at risk; the unattended-conservative rule is surface-don't-act, so nothing was disposed of):

```
worktree-retire.sh dotclaude-skills ~/.cache/relay/worktrees/dotclaude-skills/relay-20260908-231617-32609-execute-64f9-0 relay/relay-20260908-231617-32609-execute-64f9-0 --expect-merged
  (same for -execute-64f9-1 and -execute-repo-0)
worktree-retire.sh wisenheimer ~/.cache/relay/worktrees/wisenheimer/relay-20260908-231617-32609-hard-repo-0 relay/relay-20260908-231617-32609-hard-repo-0 --expect-merged
```

> **CORRECTION 3 -- do NOT retire `-execute-repo-0` blind.** The "4 (merged, no unmerged
> work)" row above is true of the branches and false of the working tree. That worktree
> still holds **uncommitted work**: `M tools/shrink-acceptance.py`, 181 insertions, from the
> child that was in-flight when the run stopped. `worktree-retire.sh` is force-free so it
> should refuse rather than destroy, but the row as written invites a blind sweep. Note the
> shape: the child hung *while trying to `git checkout --` exactly that file*, so the work
> survives only because the prompt blocked it.

**The `id:b54b` hermeticity caveat is RESOLVED, not merely dormant.** The prior handover said
the guard false-fires while relay worktrees are live. The 609-green run on 09-08 was taken
under **29 live worktrees**, which is exactly that condition -- so the fix (commit `40af4ebb`,
"exclude harness agent worktrees from the hermeticity snapshot", already merged to main) works.
Its `b54b-fix` worktree is leftover residue and can be removed.

## ~~The overnight pool DIED without reporting~~ -- DIAGNOSED 2026-09-09, it HUNG on a prompt

**The account in this section was wrong; the corrected diagnosis is `id:76e4` /
`docs/ledger-notes/76e4.md`.** What actually happened: the run **blocked on a permission
prompt nobody could answer**. Its last in-flight child, `agent-ae932ecfc6732dad3`, ends its
transcript at **01:36:48** on a `tool_use` block with **no `tool_result`** -- a compound
`cd … && git checkout -- tools/shrink-acceptance.py && git status --porcelain`.
`~/.claude/settings.json` carries `Bash(git checkout -- *)` under `permissions.ask`, and the
`cd … &&` chain matches no allowlist pattern besides. On an unattended run there was nobody
to answer, so the child blocked, the loop blocked on the child, and it sat there until the
clean shutdown at 03:53:38. Ruled out by evidence, not assumption: every proxied response in
the window is 200; there is no crash or kill in the journal; the only OOM (01:03:45,
`relay-mech.slice`) is the mechanical-sandbox **test fixture**; and
`hooks/destructive-git-guard.py` is not involved (single-file checkout is explicitly allowed).

The superseded text, and what each clause got wrong:

| Said | Actually |
|---|---|
| "**gone from the heartbeat registry**" | Still **present** at `~/.config/relay/heartbeats/relay-20260908-231617-32609.json`. Stale, not gone -- which is exactly what `heartbeat.sh` defines as dead. |
| "nothing local noticed for 2h20m" | The `id:98f0` watchdog **fired correctly**: `NOTIFIED 1 new dead run(s)` at **02:13:19**, one full TTL after the 01:13:02 beat, plus a row in `relay-outage-deaths.jsonl`. Whether a desktop notification wakes a sleeping human is a separate question from whether the mechanism worked. |
| died at ~01:13 (last heartbeat) | Worked until **01:36:48**. The heartbeat stopped earlier only because it beats once per round and that round never completed. |
| watchdog silent after 03:43 | That is the **clean shutdown at 03:53:38** (boot again 07:55), not a second fault. |

Final state stands as recorded: **12 dispatched, 8 completed, 8 blocked, 1 in-flight,
agent-failures=0.** Eight checkpoints landed (project_manager, zkWhale, six on
dotclaude-skills). No orphans. **The `agent-failures=0` is the finding, not a reassurance:**
a child wedged on a prompt is counted as in-flight forever, nothing times out, and no
handback is produced -- so the floor on noticing a hung unattended pool is one heartbeat TTL,
and the verdict it then emits ("dead") is the wrong diagnosis. That is `id:76e4`.

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

## ~~FIRST JOB: re-run the three probes~~ -- DONE 2026-09-08, and the answer INVERTED

Run in this session with corrected instruments. Full record: `docs/ledger-notes/c3c1.md`
(§ *RE-MEASUREMENT 2026-09-08, corrected instruments*). Matched `model: sonnet`,
token-identical prompts, zero tool uses:

| Probe | tools | first-request |
|---|---|---|
| default `general-purpose` | default full set | **74,529** |
| `preamble-probe-wide` | literal 21-name roster | **74,162** |
| `preamble-probe-exec` | `Bash, Read, Edit, Write` | **43,499** |
| `preamble-probe-narrow` | `Bash` | **41,654** |

**The win is the TOOL LIST, not the system prompt, by ~89:1** -- the opposite of the
retracted 4:1 finding. System-prompt body swap = **367 tokens (0.5%)**; tool definitions
beyond Bash = **32,508 (43.6%)**; floor = **41,654 (55.9%)**, unreachable by any definition.

Two consequences that change the plan: **`relay-implementer` captures 31,030 (41.6%)**,
because Read+Edit+Write cost only 1,845 combined -- the retracted split said an executor
could capture almost none of the win. And **step (2), "decide which subset of the global
`CLAUDE.md` to keep", is very nearly moot**: the 367 delta proves a custom definition does
not drop `CLAUDE.md`, the memory index, or the harness scaffolding at all, so the owner
judgement call this item warned would silently degrade agent quality is not on the path.

The labelling in the superseded version of this section was also wrong: `wide - exec` is the
tool cost an executor **can** avoid (30,663), and `exec - narrow` (1,845) is what it cannot.

**Instrument note that now cuts the other way.** `default - wide` = 367 is a self-validation:
a definition carrying the literal default roster reproduces the default child within 0.5%,
which is evidence the 21 names are right. The old probe failed exactly this check -- `Glob`,
`Grep` and `TodoWrite` are NOT real tool names here, so it declared 11 of which 8 resolved.

## MEASURED 03:47 on 09-09: half the unit children never read their contract

The owner asked whether the executor contract should be BAKED into the agent definition's
system prompt (generated, kept in sync) instead of each child `Read`ing it at runtime. The
deciding question was whether children actually read it. Measured on run
`relay-20260908-231617-32609`'s 12 real unit children (denominator taken from
`*.meta.json` `agentType`/`model`, NOT from prompt-text grepping -- a looser filter first gave
a garbage n=76 by sweeping in discovery shards and the 225 mechanical `bash` hops):

| Tier | children | read a governing ref doc | read NONE | **edited anyway, unbound** |
|---|---|---|---|---|
| `relay-implementer` / sonnet (execute) | 6 | 4 (all at tool call #2) | 2 | **1** |
| `workflow-subagent` / opus (review, hard) | 6 | 2 | 4 | **3** |
| **total** | **12** | **6** | **6** | **4** |

**Half the unit children read no contract at all, and four of twelve edited a repo without
ever loading the rules that govern them.** Zero read it *late* (after a first edit) -- the
failure mode is not reading it at all. Children that did read it did so immediately, at tool
call #2, so the instruction works when it is followed; it is simply skippable.

**Opus children were counted fairly.** Review/hard children legitimately follow
`references/review.md` rather than the executor contract, so "read a governing ref doc" counts
either. Even so, 4 of 6 Opus children read **nothing**: `a0d18f73` (13 tools, no edit),
`a5c56711` (edit@42), `acb7b65b` (edit@21), `afdc0e13` (edit@23). The one clean Opus child
read all three docs. Note the direction, which is the opposite of the usual prior: the trimmed
Sonnet definition had the BETTER read rate (4/6) than Opus (2/6).

**This settles the reliability half of the bake question, and it is the whole case.** Baking
is token-neutral (the same ~31KB arrives via the system prompt instead of a `Read`), so it buys
no window headroom -- its only prize is that a system prompt cannot be skipped, and the skip
rate is now measured at 50% rather than assumed. It would also dissolve the `id:9eb7` SKILL
COUNTERMAND paragraph outright.

**NOT DECIDED -- this is the owner's call, and the argument against is real.** Agent
definitions are read once at session start, so a baked contract cannot be updated for a running
pool, or by `make install-agents`, until a restart -- today a contract edit reaches the very
next child. And the `id:35b7`/`id:4f9b` prompt-size gate sizes the *brief*: move 8-12k into the
system prompt and the gate stops counting bytes that still consume the window (the `id:f3d2`
class). **Recommended shape if adopted:** split rather than bake wholesale -- the binding rules
(contract lines 7-280, ~21KB) generated into the body where they cannot be skipped, the
reference tail (ROADMAP format, RELAY_LOG conventions, maintenance -- ~10KB) left as a live
`Read`. Add a `--check` digest gate, the pattern `tools/memory-index.py --check` already uses.
Filed as an information-flow instance for inflownistration (`routed:5997`).

**Caveats: n=12, one run, and `verdict=` was not recoverable from the prompt text**, so the
review-vs-hard split within the Opus six is not established. The headline (6/12 read nothing,
4/12 edited unbound) does not depend on it.

## `EXECUTE_AGENT_TYPE` WORKED in a live pool -- `id:c3c1` step 4 is validated end-to-end

Six execute children ran with `agentType: relay-implementer` / `model: sonnet`, confirmed in
their `*.meta.json`. No `Agent type '<name>' not found` failures, `agent-failures=0`. The
fail-loud path was therefore **not** exercised (open thread 3 stands -- it is still unproven
against a live rejection), but the happy path is now proven in production rather than by
inspection.

## What LANDED this session

- **`id:4263` FIXED and ticked** (`abc681c3`). `relay-reconcile.sh`'s `integrate_branch()` no
  longer pushes `--all`: it sources `lib-private-remote.sh` (the same single predicate
  `integrate.sh` uses), classifies each remote by push URL, and pushes only provably-private
  ones via repeated `--remote`. Public/unproven remotes are withheld and surfaced loudly, URL
  deliberately unprinted. **Fail-closed** -- an absent predicate lib withholds everything.
  Test `tests/test_reconcile_private_remote_push_4263.sh`, five cases, negative case
  machine-verified (`green-now OK` / `red-there OK` against a mutation restoring `--all`).
  The urgency the item as filed did NOT record: it is reachable **unattended** via
  `relay-loop.js:4860` -> `--auto-restart` -> its own `--all --auto` -> the same shared
  `integrate_branch`. Scope limit: no ratification-queue entry is minted (`id:6a5d`).
- **The corrected preamble split** -- see the probe section above. The win is the TOOL LIST,
  not the system prompt, by ~89:1, inverting the retracted finding in direction as well as
  magnitude. Written into `docs/ledger-notes/c3c1.md` and `77d9.md` (`08f35661`).
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

1. ~~**WHY DID THE POOL DIE?**~~ **ANSWERED 2026-09-09 -- it did not die, it hung on a
   permission prompt.** Filed as **`id:76e4`** (`docs/ledger-notes/76e4.md`); see the
   corrected section above. What remains open is not the diagnosis but the **disposition**,
   and that is the owner's: auto-deny any `permissions.ask` match under `--afk`, pre-approve
   a narrow set for pool children, or fail-fast handback. Note that option 2 is the dangerous
   one -- `git checkout -- <file>` is precisely the class of the 2026-08-22 unconditional-deny
   ruling, and this would relax it in the least supervised context there is. The **detection**
   half needs no decision: a child with no tool result for N minutes should be surfaced as
   wedged rather than counted as in-flight, and the watchdog needs a verdict between "alive"
   and "dead".
2. **Decide the bake-vs-split question** (measurement above, `routed:5997`). Owner's call.
3. ~~**`ae932ecfc6732dad` edited without reading the contract**~~ -- **partly answered**: it is
   the same child that hung, and its transcript is the primary evidence for `id:76e4`. Its last
   act was an attempt to `git checkout --` its own modified file. Whether it violated a rule it
   never loaded is still worth a read, but the transcript is no longer unexamined.
4. **The fail-loud regex is STILL unproven against a live rejection.** Six children ran under
   `relay-implementer` and all resolved, so the rejection path never fired.
5. **`executor-contract.md:229-243` tells children to prefer `Grep`/`Glob`/LSP** -- tools
   that do not exist in this harness. Pre-existing; same fictional-name class that
   invalidated the probe measurement. Cheap to fix and it misdirects every child that
   *does* read the contract.
6. **`relay-loop.js:3192` tells every child the contract is "~5.5k"; it is 31,074 B**
   (~8-12k tok). Understated 1.4-2x, in a live dispatch prompt. Left unfixed deliberately --
   a pool was running on that file, which is the in-flight-automation case.
7. **`id:6a5d`** -- a withheld reconcile integrate mints no `id:4d44` ratification-queue
   entry, so the local unpushed merge lives only in an stderr line.
8. **Four retirable worktrees + the `b54b-fix` worktree** left for you (commands above).
9. **Possible `id:5355` regression, NOT traced -- verify before acting.** `archive-done.sh`
   archived `id:4263` the day after it closed, though its own trailing date (`on 2026-09-08`)
   was well inside the 30-day cutoff and `id:5355` says an item's own date outranks the
   prior-commit rule. Harmless here (no `routed:` breadcrumb, genuinely closed), so it was
   left alone rather than "fixed" unattended at 04:00. Plausible cause, unverified: the
   date sits before the trailing `<!-- id:4263 -->` comment rather than at end-of-line.

~~`EXECUTE_AGENT_TYPE` needs front-door threading~~ -- **was already done** (`relay/SKILL.md:313`,
documented `:922`); the thread was stale when written, and the knob worked in production tonight.
~~`id:4263` is unfixed~~ -- **FIXED**, see below.

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
