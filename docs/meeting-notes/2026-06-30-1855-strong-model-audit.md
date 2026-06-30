# Strong-model audit — Run 69 (2026-06-30-1855)

**Item:** ROADMAP id:401c (recurring `[HARD — pool]` strong-model audit).
**Window:** `8d8d40b..HEAD` (HEAD `7527cb1`) — everything since Run 68 (2026-06-26-0926).
133 commits / ~6007 insertions / 364 deletions across 88 files, but the SUBSTANTIVE
engine surface is ~21 production scripts/code files + their tests (~4623 insertions in the
non-ledger subset). `substantive_unaudited=true`. The rest is the pool's own checkpoint /
ledger / inbox-ingest churn. Four days of relay mechanical-classifier (id:4d8e) +
outage-resilience build.

Scope audited (the new/changed engine surface):
- **New scripts:** `classify-verdict.sh` (id:85df deterministic verdict classifier),
  `classify-repo.sh` (id:3f0f assembly wrapper), `backtest-verdict.py` (id:5f93 pre-flip gate),
  `decision-queue.sh` (id:de31 durable human-decision queue), `drain.mjs` (id:d58f
  fleet-quiescence), `heartbeat.sh` (id:e149 run-liveness marker), `host-gate.sh` (id:43b9
  host-awareness), `memory-append.sh` (id:6f61 flock'd index append), `hooks/pathspec-drop-guard.py`
  (id:b67e), `tools/relay-watchdog.{sh,service,timer}` (id:98f0 outage watchdog).
- **Modified:** `relay-loop.js` (id:d58f drain integration, id:e149 per-round heartbeat,
  id:7c10 phase buckets, id:de69 worked_ids, id:0175/82e3 quota-extrapolation, id:08c0 size-out
  prompt), `gather-repo-state.sh` (id:07be execve-overflow temp-file rewrite), `claim.sh`
  (id:33d3 heartbeat-gated worktree liveness), `scan-routed.sh` (id:678e --apply slice 2),
  `relay-reconcile.sh`, `roadmap-lint.sh`, `quota-stop.sh`, `gather-human-backlog.sh`
  (id:1bbd lane-anchor), `meeting/md-merge.py`, `meeting/orphan-scan.sh` (id:d097 plugin-aware),
  `ckpt-tag.sh` (id:a7a3 graceful .gitattributes degrade).

## Pass 1 — code review: CLEAN (no correctness defects)

Read the new/changed surface line-by-line. The work is uniformly defensive, well-commented,
and test-backed (suite 135/0 green on arrival, 0 expected-red). Load-bearing invariants
spot-confirmed:

- **`classify-verdict.sh`** — pure stdin→stdout, no git/FS/dispatch. Reads JSON via a shell
  var (`INPUT=$(cat)`), not argv — execve-safe. Parity guards (id:e424) outrank the D3 cascade:
  `diverged` (ahead>0 AND behind>0) then `dirty_block` (dirty AND NOT lock-only) → `blocked`
  rank 0; then execute/review/hard/handoff/idle. `upstream_ahead_behind` split is exception-guarded
  (ValueError/IndexError → 0,0). Correct.
- **`classify-repo.sh` + `gather-repo-state.sh` execve-overflow fixes (id:3f0f / id:07be)** — both
  now pass the large gather JSON + unpromoted-scan TSV (dotclaude-skills' ~130KB) via TEMP FILES,
  never env/argv (the >128KB MAX_ARG_STRLEN execve break). `gather`'s `emit()` expands `$_blobdir`
  at trap-definition time (`trap "rm -rf '$_blobdir'" EXIT`) so cleanup fires after the function's
  local scope is gone — correct, and `emit` is the single terminal call so the one-shot EXIT trap
  is safe. Verified by `test_classify_repo_large.sh` / `test_gather_repo_state_large.sh`.
- **`heartbeat.sh`** — pure ts+TTL staleness; deliberately ignores worktrees/pids (the design
  point: a dead loop that left a working worktree must still read dead). `hb_ts` falls back to file
  mtime when the field is garbled; `beat` preserves `started_at` across refreshes under flock+tmp+mv.
  TTL default 3600s (the 2026-06-29 too-tight-1800s false-positive fix). Correct.
- **`claim.sh` is_live (id:33d3)** — the id:7570 worktree-extends-lease clause is now gated on
  `heartbeat_alive_for_run`, which FAIL-SAFES to not-alive on any error (script missing / bad
  output / absent marker) → falls back to mtime-TTL (the safe D2 direction). A committed-but-dead
  run no longer holds its claim forever. Correct.
- **`decision-queue.sh`** — add/list/resolve build JSON via python3 (never string-concat), flock'd
  append, atomic tmp+rename on resolve. On a not-found resolve, python exits non-zero → `set -e`
  aborts BEFORE the `mv`, so a missing tmp file is never moved over the queue. Correct.
- **`drain.mjs` / relay-loop.js inline copy** — `unitIsSubstantive` treats a confirming-only
  review (no reopen/gaming/routine_open) as NON-progress so the dry-counter drains a quiescent
  fleet; null report → conservative non-substantive; unknown verdict → conservative substantive.
  Byte-identical inline copy in relay-loop.js confirmed (the sandbox can't import). Correct.
- **`scan-routed.sh --apply` (id:678e)** — idempotent (grep target TODO for `routed:XXXX` before
  writing), flock'd md-merge write, scoped commit-ledger (never `git add -A`), claim-peek skip on a
  live pool worktree, loud-fail relay.toml parse gate (id:2945). Correct.
- **`relay-loop.js` per-round heartbeat (id:e149)** — beats `state.runId` (FIXED at round 1), NOT
  the prelude's per-round-regenerated runId; beating the latter would spawn a fresh orphan marker
  each round and never refresh the prior, falsely reading "dead" to the watchdog. Subtle and
  correct (called out explicitly in the inline comment).

## Pass 2 — security audit: CLEAN (no injection / path / secrets defects)

- **JSON construction** — every script that emits JSON with arbitrary user/text content builds it
  via `python3 json.dumps` or `jq -n --arg` (decision-queue, scan-routed, heartbeat, gather),
  never string interpolation. No quote/apostrophe-break surface.
- **Path / pathspec** — `pathspec-drop-guard.py` is conservative-by-default: unparseable shell →
  no block; no path args → no block; nothing staged → no block; only an explicit path arg with NO
  staged counterpart blocks. `git diff --cached --name-only` shells with a fixed argv (no input
  interpolation). `host-gate.sh` extracts the `[host:<name>]` tag with a bounded char class
  `[A-Za-z0-9_.-]+`. `memory-append.sh` resolves to an absolute path before locking.
- **Subprocess** — `backtest-verdict.py` / `classify` invoke `classify-repo.sh` with an argv list
  (no shell=True), 90s timeout, capture; report-only (exit 0). No injection seam.
- **No secrets, no sudo, no network** in any new script. `relay-watchdog.sh` (read per the manifest)
  notifies only; no `claude -p`, per the id:98f0 design.

**Accepted (not defects), with rationale:**
- `scan-routed.sh:272` `"$APPEND_SH" inbox-done "$tok" 2>/dev/null || true` swallows an
  inbox-done error. ACCEPTED: the idempotent grep guard (line 208) makes a re-run a write-no-op
  even if the cross-off failed, and the default inbox path legitimately differs from a test
  override — the comment states the reason. Low risk (worst case: an inbox line stays un-crossed
  and is re-detected next sweep, never re-written).
- `scan-routed.sh:245-246` new-id fallback to `secrets.token_hex(2)` when `append.sh new-id`
  fails. ACCEPTED: last-resort only; matches the 4-hex format; the per-target idempotency guard
  bounds the blast radius. The CLAUDE.md "never invent tokens" rule targets hand-authoring, not a
  generator fallback.
- `pathspec-drop-guard.py` could false-positive-block `git commit ./foo.py` when `foo.py` is
  staged (textual `./`-prefix mismatch). ACCEPTED: it is an OPT-IN guard hook whose chosen design
  is conservative-block-on-ambiguity; the false-positive is a one-keystroke fix and never silent.

## Pass 3 — design coherence: 2 cross-ledger/count drifts FIXED INLINE

1. **id:1bbd cross-ledger drift FIXED INLINE** — `[x]` in ROADMAP (the
   `gather-human-backlog.sh emit_hard_lanes()` lane-anchor fix shipped + merged, suite 135 green)
   but `[ ]` in TODO (the INBOUND routed:6645 twin). Work genuinely done+merged → ROADMAP
   authoritative; ticked the TODO twin. `orphan-scan.sh --cross-ledger` now exit 0 (was reporting
   the one disagreement). Same class as Run 68's id:5c00 fix.
2. **d5e0 count-prose drift FIXED INLINE** — the hand-maintained "Relay: 7 open ROADMAP items"
   line still listed the four `[HARD — hands]` outage-resilience items e149/7809/98f0/0994 as
   open, but all four shipped `[x]` 2026-06-29/30 (heartbeat.sh, auto-reconcile, the
   relay-watchdog timer, and the GH #72238 CronCreate upstream report). Re-derived the actual
   ROADMAP truth: 4 open `- [ ]` HARD items — 401c [pool] (executable recurring audit), 3346
   [meeting] gated, dba3 [decision-gate] gated, de4e [meeting] DEFERRED non-executable. Updated the
   count to "3 open executable-or-gated" + the de4e deferred line, noting the hands batch closure.
   (This line is itself slated for removal once the id:2840 derived index lands — id:1de1/id:659c.)

The mechanical-classifier lattice (id:4d8e: classify-verdict ↔ classify-repo ↔ backtest-verdict ↔
the forward-shadow id:9d2b) is internally coherent: classify-verdict's priority cascade matches the
loop's verdict semantics; backtest-verdict is the human-read pre-flip gate (report-only, 0 crashes =
hard gate) and explicitly documents the live-state-vs-historical fidelity caveat (DP7). No gate that
can never fire; no contract rule that contradicts another.

## Verification (all clean)

- `roadmap-lint.sh .` → exit 0.
- `orphan-scan.sh --cross-ledger .` → exit 0 (after the id:1bbd fix).
- `gaming-scan.sh "$PWD" 8d8d40b` → exit 0, no flags.
- `todo-conformance.sh TODO.md` → exit 0.
- `tests/run-tests.sh` → 135 passed, 0 failed, 0 expected-red.

## Outcome

No code or security defects in four days of engine work — the relay self-build remains high
quality and heavily tested. Two ledger-hygiene drifts (one cross-ledger checkbox, one stale
count prose) fixed inline. No new TODO/ROADMAP items filed; nothing dropped silently.
