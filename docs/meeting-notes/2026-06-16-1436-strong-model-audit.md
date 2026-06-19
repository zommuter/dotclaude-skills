# Strong-model audit — Run 13 (2026-06-16-1436)

Recurring `[HARD — strong model]` audit item **id:401c**. Apex-Opus strong-execute child
(run relay-20260616-112222-29307). Three passes: code review, security, design coherence.

## Window

- **Base**: `db57c6e` (Run 12's merge — `merge(relay): HARD id:401c strong-model audit run 12`).
- **HEAD**: `2403d83`.
- First-seen since Run 12. `git diff --stat db57c6e..HEAD`:
  - `relay/scripts/claim.sh` (+123/-22) — id:7570 worktree-anchored liveness + `heartbeat` subcommand + `worktree` shard field
  - `relay/scripts/relay-loop.js` (+35) — id:7570 per-unit FINALLY lease release (`releaseLease`) + `--worktree` anchor on acquire
  - `tests/test_relay_claim_liveness.sh` (+97, new) — heartbeat + worktree-anchored staleness, hermetic
  - `tests/test_relay_loop_structure.sh` (+35) — id:7570 static checks
  - `RELAY_LOG.md` / `TODO.md` / `meeting/personas.md` — ledger + persona-doc (append-only)
- Substantive code surface = the **id:7570** cross-session-lease leak + long-child liveness fix.
  Suite green on arrival (59/0).

## Verdict: CLEAN — no code or security defects. Two findings ACCEPTED with rationale.

### Pass 1 — Code review

The id:7570 fix is correct.

- **`claim.sh worktree_working()`**: logic is right. Resolves the recorded `--worktree`,
  tilde-expands a leading `~/`, resolves the shared `main`/`master` ref inside the worktree
  (worktrees share refs, so `rev-parse main` is the canonical main), and returns "working"
  iff `HEAD` is NOT an ancestor of main (commits beyond main). This is the exact converse of
  the id:3ac8 staleness signal (HEAD==main → dead). `set -e`-safe: every git call has
  `|| return 1` / `2>/dev/null`, no unhandled non-zero. Back-compat: a shard with no
  `worktree` field → empty → returns 1 → falls back to mtime-only liveness (test §4 proves
  the no-worktree stale shard is still reaped — no leak).
- **`is_live()`**: clean single predicate (`is_fresh OR worktree_working`) shared by
  acquire/peek/reap — no divergence between the three consumers.
- **`acquire` re-entrant worktree preservation**: a heartbeat-via-acquire that omits
  `--worktree` re-reads the existing shard's worktree before rewriting, so the liveness
  anchor isn't dropped on a re-entrant refresh. Correct.
- **`releaseLease()` + the `rechainedSameRepo` guard (relay-loop.js)**: the review→execute
  re-chain steal-window is correctly handled — the lease is held across the re-acquire gap
  by suppressing the per-unit release when the same repo was just re-enqueued
  (`if (!rechainedSameRepo) await releaseLease(unit)`). The re-chained execute re-acquires
  re-entrantly. Sound.
- **Defense-in-depth**: the integrator step-0 release is retained and is run-scoped +
  idempotent, so a merged unit double-releases harmlessly (the second is a no-op).

### Pass 2 — Security

No new injection / traversal / secrets surface.

- `worktree_working` uses the recorded worktree path only as a `git -C "$wt"` directory
  argument (quoted) — never eval'd, never word-split into a command. The path is
  provider-controlled (written by `acquire`/relay-loop), not arbitrary external input.
- All `jq -r` reads are quoted and defaulted (`// ""`); all git invocations are quoted and
  `2>/dev/null`-guarded.
- `releaseLease`'s `resourceRelease` interpolates `unit.intensive` into an agent-run shell
  command, same trust level as the existing integrator step-0 (author-controlled resource
  string from `[INTENSIVE — <r>]` tags / relay.toml). No escalation.
- `--worktree ${wt}` interpolation in `unitPrompt` carries the same controlled-input profile
  as the pre-existing `acquire ${unit.repo}` interpolation (repo name + generated runId).

### Pass 3 — Design coherence

- **ACCEPTED — `heartbeat` shipped but not auto-wired.** `claim.sh heartbeat` is added and
  tested, but relay-loop.js does NOT call it on a schedule; the auto long-child-liveness path
  is the `--worktree` anchor instead. This is coherent, not a dead-feed: the worktree anchor
  needs no periodic shell (the Workflow sandbox can't run shell mid-agent anyway), so it is
  the correct primary mechanism; `heartbeat` is a forward/manual facility (e.g. a future
  in-agent or external nudge). Tested, documented in the header. No action.
- **ACCEPTED — per-unit release widens a PRE-EXISTING release-before-merge window.** The new
  `releaseLease` frees the lease at child-settle, while integration (the `--no-ff` merge into
  main) is only *enqueued*, running later on the serialized per-repo chain. So the lease is
  free for the integration-queue interval before the child's commits reach main. BUT the
  original design already released at integrator **step 0**, i.e. before the merge (step 2) —
  so a release-precedes-merge window has always existed; id:7570 only widens it by the queue
  wait. The relay safety model does not rely on the lease to prevent divergence here: a steal
  in that gap is caught at push by `git-lock-push.sh --ff-only` (refuses a non-ff push) and by
  the integrator's step-1b `sync-origin.sh` abort-on-diverged. A leaked lease held for the
  full 1800s TTL (the bug being fixed, observed live on mathematical-writing) is strictly
  worse than this narrow widening. Internally consistent; no change.
- **Cross-ledger coherent**: 0 open `[ROUTINE]`, 3 open `[HARD]` in ROADMAP (id:401c, id:414a,
  id:3346); TODO id:7570 is `[x]` matching the shipped fix and its done-note accurately
  describes the (a)+(b) landed / (c) deferred state. d5e0-style summary agrees.

## Tests

- `tests/test_relay_claim_liveness.sh` and the new id:7570 blocks in
  `tests/test_relay_loop_structure.sh` are genuine static-structural / hermetic-behavioural
  assertions matching the implementation (not gamed).
- `gaming-scan.sh . db57c6e` → SILENT (no deleted tests, no skip/xfail, no stripped asserts).
- Full suite green: **59/0** (no test changes this audit run).

## Outcome

No findings fixed inline (window was clean). Two findings explicitly accepted with rationale
above. The id:401c run log gets a Run 13 entry; the item stays open by design.
