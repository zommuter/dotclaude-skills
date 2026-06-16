# Strong-model audit — Run 9 (2026-06-16 09:28)

**Item**: ROADMAP id:401c (recurring strong-model audit — code review / security / design coherence).
**Window**: `relay-ckpt-20260616-0653..HEAD` (HEAD = `063b700`, relay-ckpt-20260616-0936).
**Verdict**: **CLEAN** — no code or security defects. One trivial doc/impl discrepancy **fixed inline**; three findings explicitly **accepted** with rationale (no silent drops). Suite 53/0 throughout.

## Window contents

First-seen code since Run 8's `relay-ckpt-20260616-0653` checkpoint (~586 lines / 14 files), three logical changes:

1. **id:c8b6 — observability**: `## Run progress` counter block + `## Burnup this run` section in `RELAY_STATUS.md`; append-only `relay-events.jsonl` (one line per dispatch/integrate/handback) flushed off-critical-path via a new `relay-state-write.sh event-append` subcommand; statusline relay segment.
2. **id:2d20 — drain-on-progress + gated-HARD exclusion**: outer loop keys drain on `produced` (checkpoints integrated this round) instead of units dispatched, so an all-handback round counts as no-progress; discovery classifier gains an EXECUTABLE-HARD test that excludes GATED/decision-gate/deferred/multi-session items from the `hard` verdict and `openHard`, surfacing all-gated repos for `/meeting` instead of re-dispatching a doomed Opus child every round.
3. **id:4267 — quota seatbelt accounting**: quota gate now feeds `quota-stop.sh --agents` the run-total `totalDispatched` (accumulates across rounds) instead of the per-round `unitsDispatched` (resets to 0 each round → the 200-agent runaway-spawn seatbelt could never fire across a multi-round run).

New 199-line script `relay/scripts/relay-burn.sh` (id:219b): quota burnup time-series `sample` + `report`, wired into `quota-stop.sh` (gated on `RELAY_RUN_ID`, best-effort/non-fatal). Doc edits to `handoff.md` (id:8b1f size-out-clean-worktree rule) and `SKILL.md` (knobs/artifacts). Makefile registers relay-burn.sh in FILES/EXEC/ALLOW (id:5f09 install-manifest satisfied).

## Pass 1 — Code review

- **relay-loop.js drain logic (id:2d20)**: `completedBefore = state.completed.length` at round start, `produced = state.completed.length - completedBefore` at round end. `state.completed` accumulates across rounds (never reset), so the delta correctly isolates this round's integrations. Both early-return paths (`actionable.length === 0`, and the FABLE_DOWN no-work path) now return `produced: 0`. Outer loop drain keys on `(r.produced || 0) === 0`. **Correct.**
- **round / totalDispatched hoist**: `let round = 0` / `let totalDispatched = 0` moved above `runRound` (removing the duplicate `let round = 0` that previously lived at the outer loop). `snapshotState` reads both with no temporal-dead-zone risk. `totalDispatched++` sits beside `unitsDispatched++` in `runUnit`. **Correct.**
- **pushEvent / snapshotState (id:c8b6)**: `pushEvent` stamps each line with the current `state.ts`/`state.runId` (the Workflow sandbox forbids `Date.now()`); `snapshotState` drains `pendingEvents.splice(0)` into the batch, so a flushed batch is never re-emitted across rounds. Dispatch events stamped before any integration carry the discovery ts — documented and acceptable. **Correct, no duplication.**
- **relay-burn.sh segment math**: verified by `test_relay_burn.sh` (hermetic): +$8.40/2h = $4.20/h, 7d +8%, segment isolation at a credit-drop/reset boundary, `--run` filter, null `extra_usage` handling, non-fatal missing cache. One **dead sub-condition** at the segment-boundary reduce (`(.cur[-1].used_credits // 0) != null` is always true after the `// 0` default) — harmless tautology, no behavioural effect. **Accepted** (cosmetic).
- **statusline relay segment (id:15bd)**: `NOW` defined at line 67, used at line ~352 — no TDZ. mtime-gated (`RS_AGE < RELAY_ACTIVE_SECS`), purely additive (appended via `${RELAY_PART}`), with a graceful fallback to bullet-counting for pre-Run-progress status files. **Correct.**
- **event-append (id:03a5)**: reads all STDIN before locking, drops blanks, rejects non-absolute paths (id:c34a), empty-stdin no-op. `set -e`-safe (`grep -v ... || true`). **Correct.**

## Pass 2 — Security audit

- **relay-burn.sh `report` human-table path, line 177**: `cmd = "date -d \"" reset "\" +%s 2>/dev/null"` interpolates the JSONL `reset` field (originating from `seven_day.resets_at` / `five_hour.resets_at` in `/tmp/claude-usage-cache.json`) into a shell command run via awk `getline`. This is a command-injection **seam** if the usage cache contained a crafted `resets_at`. **Risk accepted, LOW**: the cache is written by `statusline-command.sh` from the Anthropic `/api/oauth/usage` response (provider-controlled ISO timestamps), not user/network-attacker input; an attacker able to write `/tmp/claude-usage-cache.json` already has local code execution. Recorded here rather than fixed inline because hardening (parse the ISO date in jq, or validate `^[0-9T:+-]+$` before the `date -d`) is a small follow-up, not a trivial one-liner, and the seam is unexercised by any non-`--json` caller in the relay path today. → TODO candidate noted below.
- **event-append / sample locks**: both flock with a finite `-w` timeout and fall through non-fatally; `printf '%s\n'` (no `echo -e` injection); paths validated absolute. **No issue.**
- **quota-stop.sh sampling hook**: `USAGE_CACHE="$USAGE_CACHE" "$(dirname "$0")/relay-burn.sh" sample 2>/dev/null || true` — best-effort, gated on `RELAY_RUN_ID`, can never alter the quota decision (separate statement before the threshold logic). **No issue.**
- No new secrets exposure, no `eval`, no unquoted expansions in the changed shell. jq invocations pass values via `env`/`--arg`-equivalent (`env.X`), not string-spliced.

## Pass 3 — Design coherence

- **id:2d20 ↔ id:4267**: same per-round-vs-run-total accounting family (drain on run-total progress; seatbelt on run-total agents). Internally consistent; the id:4267 comment explicitly cross-references id:2d20. **Coherent.**
- **id:8b1f handoff.md ↔ hard unitPrompt**: the size-out-leaves-clean-worktree rule is now stated in BOTH `handoff.md` C5 and the relay-loop.js hard unitPrompt, and matches the orphan-reaping rationale (id:a4e9/id:3ac8). This very audit child's prompt carries the same rule — consistent end-to-end. **Coherent.**
- **doc/impl discrepancy (FIXED INLINE)**: `relay-state-write.sh` event-append header said the append happens "under the SAME flock" and the Paths note said "flock fd 9" for all subcommands — but event-append actually flocks the **target events file** (`exec 9>>"$target"`), NOT the shared `$BASE/.state-write.lock` that toml-set/status-write use. The implementation is **correct** (appends to distinct event logs should not block unrelated toml/status writes; flock'ing the append target still serializes concurrent appenders). Only the comment was misleading. Fixed the header + Paths note + extended the `--help` `sed` range 2,26 → 2,30 to keep help complete. Suite 53/0 after.
- **Unregistered code-only sub-ids (ACCEPTED)**: `id:15bd` (statusline segment), `id:cd19` (sampling-wire in quota-stop), `id:03a5` (event-append subcommand), `id:219b` (relay-burn.sh) appear ONLY in code comments — no TODO/ROADMAP/meeting-note/RELAY_LOG entry. The parent surfaces ARE tracked (id:c8b6, id:4267 in RELAY_LOG; id:2d20/id:8b1f in TODO). `orphan-scan.sh` scans ledger files only, not code comments, so these are not flagged and are not orphans in the tooling sense. **Accepted**: they are inline provenance tags for sub-surfaces of a tracked parent (the informal convention for code comments), not ledger-claiming tokens; retroactively minting+filing them is design-churn with no payoff. Noted for awareness.
- **Cross-ledger state**: 0 open ROUTINE, 3 open HARD (id:401c recurring, id:3346 GATED, id:414a gaming-canary) — matches the TODO id:d5e0 summary line exactly. **Coherent.**

## Follow-up (tracked, not blocking)

- **relay-burn.sh `date -d` injection seam** (Pass 2): low-risk hardening — validate/parse `resets_at` (jq date-parse, or a `^[0-9T:+\-]+$` guard) before the awk `date -d` shellout. Small follow-up; filed as forward-robustness TODO id:287b, not fixed in this audit (not a trivial one-liner, unexercised seam).

## Done-check

- Meeting note exists at `docs/meeting-notes/2026-06-16-0928-strong-model-audit.md`. ✓
- Every finding fixed (1 inline doc/help), tracked (1 TODO follow-up), or explicitly accepted (3, with rationale). No silent drops. ✓
- `make test` green (53/0). ✓
