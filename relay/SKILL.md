---
name: relay
description: Relay workflow that spends a strong reviewer-model turn (Opus apex; Fable optional bonus) preparing repos for cheaper executor sessions (Sonnet), then verifying their work. Two modes — handoff (write docs, roadmap, failing-test specs, BDD) and review (verify executor work isn't gamed, re-derive roadmap); plus `executor` to load the lean executor contract and `next` to auto-route the current repo. Trigger on "relay", "relay handoff", "relay review", "relay next", "relay executor", "hand off repos to executors", "review executor work". Keywords: relay, handoff, review, next, executor, checkpoint, ROADMAP, RELAY_LOG.
---

# relay

A relay between a strong reviewer model and cheaper executor sessions, run ON THE
STRONG MODEL'S TURN. The strong turn produces what needs judgment — architecture,
roadmaps, failing tests as the spec, anti-gaming review — and leaves `[ROUTINE]` work
for Sonnet executor sessions driven by a generated `CLAUDE.md` contract.

Invocation:

```
/relay                              # default: autonomous pool (no keyword)
/relay -d                           # executor-only: strong model unavailable (--fable-down)
/relay --fable-down                 # long form of -d
/relay handoff [repo-list | --all]
/relay review  [repo-list | --all]   # default: cwd repo only; --all (or a repo-list) = cross-repo sweep
/relay next                          # auto-router: inspect the cwd repo's state and act (executor/review/human)
/relay human   [repo-list | --all]   # interactive: cross-repo human-backlog triage
/relay executor                      # load the lean executor contract (cheap Sonnet sessions)
```

## `executor` arg (lean executor contract)

`/relay executor` is invoked at the start of a cheap Sonnet executor session. It loads
**only** `references/executor-contract.md` (the 5-rule contract + ROADMAP/RELAY_LOG
format) — it does NOT load the rest of this orchestrator SKILL.md. Read that reference
and follow its rules exactly; ignore everything below (orchestrator-only).

Default `--all` means "confirmed OWN repos, by neediness, in waves of ≤5, until quota
says stop" — resumable across turns via the state file, never all 36 at once.

## Default mode: autonomous pool

Invoking `/relay` with no keyword starts the autonomous priority-mixed pool
(meeting note `docs/meeting-notes/2026-06-12-2045-fables-relay-autonomous-pool.md`,
D1/D2):

0a. **Early-exit retry nudge — FIRST, before any work (user directive 2026-06-18; corrected id:bde8).**
    The very first action of a default/`--afk` run is to surface the `/loop` nudge, NOT
    bury it in the exit summary: a user who typed `/relay --afk` is signalling they are
    walking away, so the hint is only useful *up front* (after a long run + diary it is
    too late to act on). Run `~/.claude/skills/relay/scripts/loop-hint.sh` as the FIRST
    line of output and, if it prints anything, relay that output verbatim before starting
    the probe. It still self-suppresses when it detects we are already inside a `/loop`
    (so loop ticks don't re-nag) and never fails the turn (exits 0; prints nothing → print
    nothing). The exit summary no longer repeats it (see step 4).
    **Scope correction (id:bde8, 2026-06-22):** `/loop` runs within the same Claude session
    — it is resilient only to relay's own early-exit (quota/seatbelt) within a live session;
    it dies with the session if the session is killed or the process crashes. Do NOT imply
    `/loop` gives session-kill or outage protection — that is a separate watchdog concern
    (id:98f0). The nudge (loop-hint.sh) reflects this corrected scope.

0. **Fable-availability probe + apex-tier selection (Opus is APEX; Fable is a bonus).**
   Opus is the apex decision tier. Fable is treated as an OPTIONAL bonus second-opinion
   *if it returns* — never a required gate (user directive 2026-06-15: "treat Opus as the
   apex tier, Fable as a bonus re-review"). Do NOT warn when running on Opus — it is the
   intended tier; there is no self-guard and no `sleep`. Select the strong tier:
   - Manage the cache `~/.config/fables-turn/fable-probe.json`
     (`{available: bool, checked: ISO-ts}`) through `scripts/probe-fable.sh` — the tested
     helper that owns the read + 2 h staleness check (the helper NEVER spawns the model;
     the actual agent-probe stays here in the front door). Run
     `scripts/probe-fable.sh check`: `fresh-available` / `fresh-unavailable` (exit 0) →
     use the cached decision, skip the probe; `stale` / `absent` (exit 1) → PROBE once:
     spawn ONE tiny agent pinned to `model: claude-fable-5` with a trivial prompt (it
     returns → available; a "Fable unavailable" / model error → unavailable), then record
     it with `scripts/probe-fable.sh set <true|false>` (the helper stamps the ISO timestamp).
   - **Default assumption: Fable is unavailable** → `STRONG_TIER=opus`, proceed with Opus
     as apex. **Nothing depends on Fable.** The only ways to use Fable: the probe says
     available, OR the user explicitly passes `--strong-tier fable` / says "Fable is
     available" (an override that wins even over a failing probe).
   - `-d`/`--fable-down` forces Fable-down *without probing* (this is just the default
     posture made explicit; on the now-default `STRONG_TIER=opus` it is a no-op).
   - When Fable IS available it is used ONLY as an optional bonus recheck of
     `fable-standin` checkpoints (see scheduling). Opus decisions remain **final** — they
     are never "pending Fable", so the roadmap never looks half-complete while Fable is out.
1. **Non-interactive by default.** The front door operates ONLY on relay.toml
   `classification = "own"` confirmed repos. New, dirty, or `needs_review` repos are
   *surfaced* in `RELAY_STATUS.md` (Queued/Blocked sections) — never asked about
   mid-run. No `AskUserQuestion` is issued anywhere in the default mode.
2. **No confirmed repos → notice, no launch.** If relay.toml has zero confirmed
   `own` repos, the front door prints a short notice (pointing at
   `/relay handoff` to confirm a first wave) and exits cleanly without
   invoking the Workflow.
3. **Workflow launch.** The front door invokes the `relay/scripts/relay-loop.js`
   Workflow script (id:83c9), passing `args.STRONG_TIER`, `args.interactive`,
   `args.fableDown` (true when `--fable-down`/`-d` is set), `args.POOL_WIDTH`
   (when overridden via `POOL_WIDTH` env var / `--pool-width` flag),
   `args.allowIntensive` (true ONLY when `--intensive` / `--allow-intensive` is set — id:8d52,
   semantics revised id:052c; a bare `--afk` NO LONGER sets it — `--afk` stays non-intensive,
   and `--intensive` implies `--afk`),
   `args.priorityRepos` / `args.excludeRepos` (per-run repo lists from `--priority` /
   `--exclude` — id:d530; the front door maps the natural-language forms the user types
   ("priority on X", "exclude Y") onto these arrays), and
   `args.RELAY_STATUS_PATH` (when overridden). The Workflow owns the pool, the serialized integrator, the
   quota guards, **and the self-feeding loop** — it re-discovers after each dispatch wave
   so executes→reviews→executes cycle inside a SINGLE invocation (`runRound()` in a `while`),
   ending only on the quota cap, two consecutive empty discoveries (backlog drained), or
   the `MAX_ROUNDS` seatbelt. The front door launches it ONCE; it is not relaunched
   per-wave. Scheduling order: verdict class
   first (execute → review → **hard** → handoff, the D3 anti-gaming invariant — note
   `hard` ranks after review so unaudited work is always reviewed before fresh strong
   work, id:da26), then repos
   flagged `income = true` in relay.toml win slot contention within a class
   (user directive 2026-06-12), then a *slight* `fable-standin` tiebreaker
   (user directive 2026-06-13): repos whose latest checkpoint (`relay-ckpt-*` or the
   historical `fable-ckpt-*`) was produced by Opus are marked `fable-standin`. Under the
   Opus-apex model these are **complete** work (Opus decided), so the marker only flags an
   *available optional Fable recheck*: on a Fable session with spare capacity they may be
   re-reviewed as a free second opinion (`@fable-optional-recheck`, id:9821), sorted
   **last** (real work first); on Opus/executor/handoff work they carry no special weight.
   The pending recheck is ALSO tracked durably in relay.toml
   (`last_strong_ckpt`/`fable_rechecked`, id:e030) so it survives a later executor
   checkpoint masking the latest-tag signal — see State below. It never excludes, never
   gates, and never marks work "pending" — an absent Fable simply means the optional
   recheck never runs.
   **HARD-execute verdict (`hard`, id:da26).** When a repo has no unaudited commits and
   no open `[ROUTINE]` work but ≥1 open `[HARD — strong model]` item, the classifier
   emits a `hard` unit. It dispatches an Opus-apex child that works ONE bounded `[HARD]`
   item in its worktree under full verify-before-merge discipline — modelled on the
   handoff C5 "only if small enough to finish safely" rule (the child sizes the item,
   implements only if it finishes green, ticks the box only if genuinely green, else
   hands back). This is the steady-state path now that `[ROUTINE]` is drained and every
   repo carries a ROADMAP (so `handoff`/opportunistic C5 never fire) — without it the
   ~46 open `[HARD]` items would stall while Fable is out. **Gate: `hard` is dispatched
   ONLY when `STRONG_TIER=opus` (`STRONG_MODEL=claude-opus-4-8`, the apex tier) — never
   on the Sonnet execute tier, and not when the strong tier is Fable or under the
   `-d` defer path** (there it stays for Fable handoff-C5 / review-step-6 as today, and
   surfaces in `RELAY_STATUS.md` Queued with a clear reason). It carries `fable-standin`
   (apex Opus work invites an optional Fable recheck) and uses a `strong-execute (...)`
   checkpoint label.
4. **Exit summary.** After the Workflow completes, the front door prints the
   `RELAY_STATUS.md` path and the HANDBACK count, then ends the turn (plus the
   global git-diary-workflow/todo-update obligation).
   **Early-exit retry nudge moved to step 0a** (user directive 2026-06-18; corrected
   id:bde8): a single `/relay` run is resumable but NOT self-restarting — a quota/seatbelt
   early-exit ends the run; `/loop` retries within the live session. Surfaced FIRST (step
   0a), where the user can still act on it, NOT here after a long run + diary. Do NOT also
   print it in the exit summary (it was already shown). Do NOT bake a self-chained wakeup
   into the front door — that is the fragile kind a well-timed outage breaks (user
   decision 2026-06-16). Note: `/loop` dies WITH the session on a session kill (id:bde8
   scope correction) — for watchdog/outage-death handling see id:98f0.

`--interactive` re-enables the orchestrator's one-batch `AskUserQuestion`
confirmations (invariant 2 below: new-repo confirms, dirty-repo snapshot offers)
*before* the Workflow launches, and is passed through as `args.interactive` so the
Workflow may surface choices instead of silently skipping; the Workflow script
itself still never calls `AskUserQuestion`.

The existing `handoff` and `review` keyword modes are unchanged and fully
compatible — the default mode is sugar over the same classifier, references, and
integration invariants.

## Orchestrator invariants (never skip)

1. **Discover + reconcile.** Run `scripts/discover-repos.sh [repos…]`. Reconcile its TSV
   against `~/.config/fables-turn/relay.toml`. Present only NEW or changed repos for
   confirm/prune; persist confirmations. `needs_review` repos (mixed-remote forks, dirty
   clones) are never auto-included — they require an explicit user call.
2. **Cheap pre-scan, then ONE question batch.** Spawn ≤5 lightweight read-only Explore
   agents (README + tree + `git log` skim, no worktrees) to collect per-repo clarifying
   questions and a dirty assessment. Ask the user EVERYTHING in one `AskUserQuestion`
   batch — new-repo confirmations, dirty-repo `wip: pre-relay snapshot` offers, and
   spec ambiguities. Never ask mid-flight after spawning.
3. **Allocate id tokens.** For each repo, pre-allocate roadmap tokens:
   `~/.claude/skills/meeting/append.sh new-ids <N> <repo-root>`.
4. **Spawn waves of ≤5 children** via plain Agent-tool fan-out (one repo per child),
   each in its own worktree under `~/.cache/fables-turn/worktrees/<repo>/` (outside the
   repo tree, so it never pollutes status). Pass the child the relevant reference doc
   (`references/handoff.md` or `references/review.md`), `references/conventions.md`, its
   tokens, and whether C5/step-6 HARD work is budgeted this turn. Children commit in
   their worktree and return the structured report — they NEVER push and NEVER run
   git-diary-workflow or todo-update.
   **Cross-session lease (id:0902).** BEFORE spawning each repo's child, acquire the repo
   lease: `~/.claude/skills/relay/scripts/claim.sh acquire <repo> --run relay-<mode>-$CLAUDE_SESSION_ID
   --mode <handoff|review>`. If it is REFUSED (a live autonomous pool, `/relay executor`,
   `/meeting`, or another interactive relay session already holds that repo), SKIP the repo
   this turn and surface it ("claimed by another relay run") — never spawn a colliding child.
   Only fan out children for repos whose lease you acquired.
5. **Integrate per completed child as one uninterrupted block**, repos strictly
   sequential: verify `contract_met` and checkpoint ordering → `--no-ff` merge the
   worktree branch into the integration branch → `scripts/ckpt-tag.sh <repo-path> -m
   "<summary>" -l "reviewer (<model>)"` → ONE push via
   `~/.claude/skills/git-diary-workflow/git-lock-push.sh --ff-only` → `git worktree prune` →
   update relay.toml (`status`, `last_ckpt`/`last_review`). A child that fails
   `contract_met` is NOT merged; its worktree is held and listed as a HANDBACK.
   **Release the lease (id:0902)** run-scoped when done with the repo — whether merged OR
   handed back: `~/.claude/skills/relay/scripts/claim.sh release <repo> --run relay-<mode>-$CLAUDE_SESSION_ID`
   (run-scoped → a no-op if you don't hold it; a stale lease also auto-expires via the claim TTL).
6. **Quota between waves.** Check the statusline pricing indicator (💸 = expensive
   weekday window ~05:00–11:00 PT, 🪙 = reduced) if present; otherwise judge by remaining
   quota. Default HARD execution (handoff C5 / review step 6) OFF in the expensive
   window — but it is the user's call per invocation. On low quota, finish merge debt
   for completed children BEFORE starting a new wave (an unmerged worktree is the worst
   thing to abandon; it survives on disk as a HANDBACK).
7. **End of turn.** Run git-diary-workflow + todo-update once (global obligation). Print
   a turn summary: per-repo checkpoint tags, REVIEW_ME.md counts, blocked-dirty repos,
   and any HANDBACKs with their worktree branches.

## Mode procedures

- **Handoff** — see `references/handoff.md` (per-repo child: checkpoints C1 docs → C2
  roadmap → C3 red tests → C4 BDD → C5 optional HARD).
- **Review** — see `references/review.md` (per-repo child: diff since last ckpt →
  test-integrity audit → BDD → spec-drift → re-derive roadmap → optional HARD).
  **Default scope is the cwd repo only** (`git rev-parse --show-toplevel`),
  mirroring `/relay executor`'s least-surprise default; pass `--all` (or an explicit
  repo-list) to opt into the cross-repo sweep over every confirmed `own` repo. (This
  flips the historical default — bare `/relay review` no longer means `--all`.)
- **Human** — see `references/human.md` (cross-repo human-backlog triage; the human
  is the relay's 3rd actor). See `## Human mode` below.

## Human mode

`/relay human [repo-list | --all]` is the cross-repo HUMAN-BACKLOG triage — the
human as the relay's **third actor** (execute = Sonnet, review/hard = Opus apex,
**human = you**). It is an **interactive strong-turn PROCEDURE**, NOT an autonomous Workflow:
it uses `AskUserQuestion` (which Workflows cannot call), so the apex model
drives it directly — mirroring how `handoff`/`review` are reference-doc procedures the
strong turn runs (it may delegate the read-only gather and per-repo apply to sub-agents).
It **generalizes the planned `review_me` mode**: instead of one repo's queue, it sweeps
every `classification = "own"` repo's human-backlog in one turn.

What it does (full procedure in `references/human.md`):

1. **Scope** — relay.toml `own` repos only (honor `# path:`); skip clone/excluded/needs_review.
2. **Collect** — `scripts/gather-human-backlog.sh` emits a TSV of every open `REVIEW_ME.md`
   `- [ ]` box, open `@manual` BDD scenarios (REVIEW_ME `@manual` + ROADMAP `@manual`), and
   every open `[HARD]` ROADMAP item bucketed by its EXPLICIT lane tag (id:78ff) into
   `hard_pool` / `hard_meeting` / `hard_hands` (vocabulary: `references/hard-lanes.md`). An
   open `[HARD]` with no recognized lane is a LOUD reject (stderr ERROR + nonzero exit) —
   add the lane tag at the source.
3. **Classify each box into 3 tiers** by answerability/runnability:
   - **(a) AUTO-ANSWERABLE** — unambiguous from code/tests/spec; the apex model verifies,
     ticks with a re-checkable rationale, and flows back to ROADMAP/TODO under the **same
     id** (single-id-two-views, flock'd `meeting/md-merge.py`).
   - **(b) BATCH-DECIDABLE** — quick human yes/no, presented in small multiple-choice
     `AskUserQuestion` batches (≤3–4 per call, ONE `questions` array) with REAL per-item
     context (read the box + cited code so options aren't one-liners).
   - **(c) CHEWY** — genuine design judgment, routed OUT to `/meeting --cross` (box left open).
4. **`@manual`/scenario-run boxes are NEVER auto-ticked** — a human must RUN them; surface
   them as a "you run these" checklist.

Discipline: clean-tree only; commit per-repo **in the main checkout** (the per-repo
`/meeting` REVIEW_ME write-back path, id:15d5), not a worktree merge. An auto-answer is a
CLAIM the next `review` re-checks (anti-gaming, conservative — **when unsure, downgrade
a→b**). **Opus is apex**: auto-answers are final, never "pending Fable".

## Reconcile mode

`/relay reconcile [repo]` is the **human-invoked** disposal of parked orphan branches —
the consume side of D1's orphan-park (id:689c). When a dead/orphaned relay run leaves
unmerged commits, D1 renames its branch into `relay/orphan/*` (commit reachable on the ref,
worktree dir removed) and surfaces it. Reconcile lets a human dispose those parked branches.
**NEVER auto-triggered by the pool** — it is a deliberate, per-branch decision.

**Cross-repo sweep (canonical — use this first):** `relay-reconcile.sh --all` enumerates
all relay.toml `classification = "own"` repos (honoring `# path:` overrides, `RELAY_TOML`,
`SRC_DIR`) and lists every `relay/orphan/*` branch across all of them. An unreadable or
missing repo path is SURFACED on stderr — never silently swallowed as "no orphans". Do NOT
hand-roll a per-repo `git for-each-ref … 2>/dev/null` sweep; that is the exact false-clean
bug (id:4e14). `--all` is list-only; combining it with `--integrate`/`--discard` is rejected.

Run `scripts/relay-reconcile.sh [repo]` (defaults to the cwd repo). With no flag it
**lists** every `relay/orphan/*` branch with its parked commit; then per branch choose:

- **integrate** — `relay-reconcile.sh --integrate <branch>`. Reuses the **same**
  serialized-integrator recipe the live pool uses, so a human can't skip the checkpoint
  tag or race the pool's push: verify clean main + `sync-origin.sh` → `git merge --no-ff`
  (preserves 3-way conflict surfacing; **no CAS plumbing**) → `ckpt-tag.sh` (atomic
  RELAY_LOG + `relay-ckpt-*` tag) → `git-lock-push.sh --ff-only` → `git branch -D` the
  consumed ref. A merge **conflict** is `git merge --abort`ed and the branch is **left +
  surfaced**, never half-merged.
- **discard** — `relay-reconcile.sh --discard <branch>` → `git branch -D` (drop the work).
- **leave** — do nothing; the `relay/orphan/*` ref stays for a later pass.

`<branch>` may be given with or without the `relay/orphan/` prefix. `id:3313`, `id:4e14`.

## Next mode

`/relay next` is a quick auto-router: it inspects the CURRENT repo's state and acts,
collapsing the "human-or-not" decision to its fastest form. It operates on the **cwd
repo by default** (`git rev-parse --show-toplevel`, consistent with the `review`-default
flip above) and does NOT define new work — it reuses the existing executor/review/human
modes. Decide ONE route and take it:

1. **Open `[ROUTINE]` items in `ROADMAP.md`** → run as **`/relay executor`** (load the lean
   executor contract, work the routine items). Autonomous — do NOT ask.
2. **Else, unaudited commits since the last relay checkpoint tag** (`git tag -l
   'fable-ckpt-*' 'relay-ckpt-*' | sort | tail -1`, then commits after it) → run
   **`/relay review`** on this cwd repo (the per-repo default). Autonomous — do NOT ask.
3. **Else, a judgment box truly needing a human** — open `REVIEW_ME.md` `- [ ]` boxes,
   open `@manual` scenarios, or genuinely-chewy design — → route to **`human`** (the
   cross-repo human-backlog triage) or **`/meeting`**. This is the ONLY route that
   involves the human.

Optimize for the fastest human-or-not call: do the autonomous executor/review work
**without asking**; only stop for the human when a judgment box genuinely requires it.
**When unsure, prefer acting over asking** — a borderline-routine item runs as executor
work, and the next `review` re-checks it (anti-gaming). If multiple routes apply, take
the earliest in the list (execute → review → human), mirroring the default pool's
verdict-class order.

## Shared resources

- `docs/relay.md` (repo root) — user-facing guide: what a relay turn does
  end-to-end, what the artifacts mean, what the human does between turns.
- `references/conventions.md` — environment facts + the verbatim executor-contract
  block embedded into every generated CLAUDE.md.
- `references/templates.md` — ROADMAP.md / RELAY_LOG.md / REVIEW_ME.md templates.
- `scripts/discover-repos.sh` — read-only ownership classifier (TSV).
- `scripts/ckpt-tag.sh` — atomic RELAY_LOG.md append + annotated `relay-ckpt-*` tag
  (older `fable-ckpt-*` tags are historical and never rewritten; readers match both prefixes).
- `scripts/gather-human-backlog.sh` — read-only cross-repo collector for `human` mode
  (open REVIEW_ME boxes + `@manual` scenarios as TSV; flags `@manual`).
- `scripts/relay-burn.sh` — quota burnup time-series (id:219b). `sample` appends one
  point (utilization buckets + `extra_usage.used_credits` USD) to
  `~/.config/fables-turn/quota-samples.jsonl`; `report [--since|--run|--json]` segments at
  resets and prints `$/h`, `$/day` and per-bucket `%/h` projected to reset — the data for
  evaluating Max x20/x5/Pro tiers. Sampling is wired into `quota-stop.sh` (gated on
  `RELAY_RUN_ID`, best-effort/non-fatal), so every quota gate during a run leaves a sample.
- `scripts/relay-econ.py` — relay-loop ECONOMICS (id:08a3) on `profile-run.sh --json`'s
  per-agent `records`. Three lenses over all retained runs (or `--limit N`): **cost** (USD,
  cache-accurate — `tokens_in` @full, `cache_read` @0.1×, `cache_create` @1.25×, `out` @rate,
  per the agent's actual model), **time standalone** (Σ durations), and **time
  parallelity-weighted** (per-category UNION of `[start,end]` = wall-clock the category was
  active; `Σdur/wall` = mean concurrency it ran at). Categorized (work/status/scaffold/poll),
  by model, daily + hourly-of-day; `--json` for the raw object. Finding (36 runs): ~71% of
  *cost* is Opus work, but status+scaffold are a bigger share of *wall-clock* than of cost
  (low concurrency → on the critical path).
- **Observability artifacts** (id:c8b6): `RELAY_STATUS.md` now carries a `## Run progress`
  counter block and a `## Burnup this run` section (filled from `relay-burn.sh report`); the
  append-only `~/.config/fables-turn/relay-events.jsonl` records one line per
  dispatch/integrate/handback (flushed off-critical-path via `relay-state-write.sh
  event-append`) — `tail -f` it for a live event feed (the snapshot file is rewritten each
  round, so use `tail -F` there). The Claude Code statusline shows a live `🔁<round> ✓<done>
  ⚙<in-flight> Δ$<burn>/h` segment whenever `RELAY_STATUS.md` was touched in the last
  `RELAY_ACTIVE_SECS` (default 600).

## State: `~/.config/fables-turn/relay.toml`

```toml
[repos.<name>]
classification = "own"          # own | clone | excluded (user-confirmed, sticky)
confirmed      = "YYYY-MM-DD"
status         = "pending"      # pending | handed-off | active | paused | blocked-dirty
handoff_date   = ""
last_ckpt      = ""             # newest checkpoint tag (relay-ckpt-* or legacy fable-ckpt-*)
last_review    = ""
# Durable, model-tracked Fable-bonus-recheck queue (id:e030). Written by the integrator
# on a STRONG (review/handoff/hard) checkpoint; an executor (sonnet) checkpoint NEVER
# clears these, so a pending optional Fable recheck survives a later executor checkpoint
# masking last_ckpt. A non-empty last_strong_ckpt with fable_rechecked = false is an
# OPTIONAL recheck candidate (non-gating @fable-optional-recheck — never blocks work).
last_strong_ckpt = ""           # tag of the last strong-model checkpoint
strong_model     = ""           # e.g. "claude-opus-4-8" — the producing strong model
fable_rechecked  = false        # false until a real Fable session rechecks, then its ISO date
```

Tag/dirty facts are re-derivable from git; this file is the confirmation registry, wave
scheduler, and durable Fable-bonus-recheck queue. The orchestrator is its only writer
(after user confirmation). The latest-checkpoint lookup matches BOTH `relay-ckpt-*` and
the historical `fable-ckpt-*` prefix:
`git tag -l 'fable-ckpt-*' 'relay-ckpt-*' | sort | tail -1`.

## Configuration knobs

| Env var / flag | Values | Default | Effect |
|---|---|---|---|
| `STRONG_TIER` | `fable` \| `opus` | `opus` | Apex model for review/handoff/HARD-execute agents. **Default `opus`** — Opus is the apex tier; Fable is an optional bonus (user directive 2026-06-15). Execute (Sonnet) agents are never affected. Set/keep `fable` only when the step-0 probe **or** you explicitly confirm Fable is available. |
| `--strong-tier fable` / "Fable is available" | flag/override | off | The ONLY way to use Fable: asserts Fable is up, overriding even a failing step-0 probe. Use when you know Fable works despite a probe error. Without it the default stays `opus`. |
| `--fable-down` / `-d` | flag | off (probe decides) | Forces Fable-down *without* probing. On the now-default `STRONG_TIER=opus` it is a **no-op** (Opus is already apex). Only meaningful with an explicit `STRONG_TIER=fable`, where it triggers the legacy defer/demote (executor-only) path. Passed as `args.fableDown = true`. |
| `--interactive` | flag | off | Re-enables the one-batch `AskUserQuestion` confirmations before launch; passed to the Workflow as `args.interactive`. Default mode is unattended. |
| `--afk` | flag | off | "I'm away, do something useful" — an unattended run (surfaces the `/loop` resilience nudge, step 0a). **Stays NON-intensive (id:052c):** it does NOT opt into `[INTENSIVE — <resource>]` work — auto-running OOM-risky local-LLM/big-index units *because* the user stepped away is backwards (the [[oom-local-model-session-kills]] hazard). A bare `--afk` runs the normal parallel pool only; intensive units stay surfaced-as-skipped. Does NOT set `args.allowIntensive`. |
| `--intensive` / `--allow-intensive` | flag | off | Explicit opt-in to `[INTENSIVE — <resource>]` work (id:8d52; `--intensive` is the canonical name as of id:052c, `--allow-intensive` a synonym). By default such resource-heavy units (local-LLM benchmarks, big index rebuilds — the OOM risk) are NEVER auto-dispatched: they're surfaced as skipped in `RELAY_STATUS.md`. With this flag they run **serially-alone** after each round's normal parallel wave, each holding an exclusive `resource:<name>` claim (cross-run). **`--intensive` IMPLIES `--afk`** (id:052c — intensive work is inherently a long, away-run): a user need not pass both. Sets `args.allowIntensive = true`. |
| `RELAY_QUOTA_THRESHOLD` | 0–1 fraction | `0.90` | Quota stop threshold used by `scripts/quota-stop.sh` (cache `.utilization` is 0–100 percent; converted internally). |
| `RELAY_QUOTA_THRESHOLD_<BUCKET>` | 0–1 fraction | (general threshold) | Per-bucket override of `RELAY_QUOTA_THRESHOLD` for one cache bucket only, e.g. `RELAY_QUOTA_THRESHOLD_SEVEN_DAY=0.50` or `RELAY_QUOTA_THRESHOLD_SEVEN_DAY_SONNET=0.50`. Caps a long-window bucket tighter than the 5h bucket ("use most of the 5h window but never exceed 50% of 7d/Sonnet"); buckets without an override keep the general threshold, so behaviour is unchanged unless set. **Nested form** (id:b841): the front door may pass `args.quotaThresholds = { SEVEN_DAY: 0.70, SEVEN_DAY_SONNET: 0.70 }` as a map; `relay-loop.js` folds each entry into the corresponding flat key (flat key wins if both present). |
| `POOL_WIDTH` | integer | `5` | Number of distinct repos dispatched in parallel (one unit per repo). Passed as `args.POOL_WIDTH`. NOTE: the Workflow harness independently caps concurrent agents at `min(16, cpu_cores-2)`, so values above that ceiling just queue — no benefit. |
| `--priority` `<repo\|repo,repo>` | repo list | (none) | **Per-run ORDERING bump only (id:d530), scoped to THIS run — NEVER writes relay.toml.** Ranks a priority repo's NATURALLY-discovered unit ahead of non-priority units **within the same verdict class** (above `income`, but below injected-unit precedence and the D3 verdict-class order — never a verdict override). Unlike `inject.sh`-as-priority, it does NOT create or inject a unit — it only reorders the repo's own discovered unit, so it can never double-dispatch a repo. An unknown/unconfirmed repo name is a **LOUD reject** (surfaced in `RELAY_STATUS.md`, never silently dropped). The front door maps the natural-language form ("priority on X") onto `args.priorityRepos`. |
| `--exclude` `<repo\|repo,repo>` | repo list | (none) | **Per-run exclusion, scoped to THIS run — NEVER writes relay.toml** (avoids the destructive `classification = own→excluded` registry mutation that survives a session-kill = silent permanent exclusion). Excluded repos are DROPPED from the own-repo list **before sharding** (no shard ever sees them, no unit is emitted); each is surfaced in `RELAY_STATUS.md` Skipped as `excluded for this run (--exclude)`. An unknown/unconfirmed repo name is a **LOUD reject** (surfaced, never silently dropped). The front door maps the natural-language form ("exclude Y") onto `args.excludeRepos`. |
| `RELAY_QUOTA_DECAY_7D` | `START:END` fractions | (unset) | Time-decaying cap for the 7-day + 7-day-Sonnet buckets: the threshold linearly interpolates from `START` at the rolling 7-day window's open to `END` at its reset (e.g. `0.30:0.90` → ~0.82 at 6/7 elapsed). **Direction matters — weekly quota is use-it-or-lose-it (unused 7-day allowance is forfeit at reset), so the cap should RISE toward reset (`START < END`): conserve early (don't blow the week on day 1), then spend down the about-to-reset budget.** A `START > END` (spend-early / back-off-late) schedule is almost always wrong — it false-stops a healthy low-utilization run right before reset (observed 2026-06-22: `0.40:0.18` stopped at 24% 7d-util with ~22 h to reset, leaving 76% to be forfeit). Recomputed each gate check from `seven_day.resets_at`. 5h bucket unaffected (it is the real short-term burst guard). Forwarded into the quota-gate via args. |
| `MAX_ROUNDS` | integer | `30` | Self-feeding-loop seatbelt: max re-discover→dispatch→drain rounds in one `relay-loop.js` invocation before it returns regardless. The loop normally ends earlier on the quota cap or two consecutive empty discoveries (backlog drained). Passed as `args.MAX_ROUNDS`. |
| `DISCOVER_SHARDS` | integer | `6` | Number of parallel discovery-shard classifiers fanned out per round (id:9ed4). A once-only prelude does the global work (runId, the consuming `inject.sh take`, `claim.sh peek`, the own-repo list + non-own skipped rollup); the own repos are round-robin chunked across this many shard agents that classify in parallel, then merged into the same discovery object. Capped at the repo count; the Workflow harness's `min(16, cpu_cores-2)` agent ceiling still applies, so shards above it just queue. Passed as `args.DISCOVER_SHARDS`. |
| `RELAY_STATUS_PATH` | path | `~/.config/fables-turn/RELAY_STATUS.md` | Where the cross-repo rollup is written (override for testing). |
| `RELAY_EVENTS_PATH` | path | `~/.config/fables-turn/relay-events.jsonl` | Append-only event-log JSONL (id:c8b6): one line per dispatch/integrate/handback, flushed off-critical-path. Passed as `args.RELAY_EVENTS_PATH`. |
| `RELAY_QUOTA_SAMPLES` | path | `~/.config/fables-turn/quota-samples.jsonl` | Where `relay-burn.sh` appends/reads burnup samples (id:219b). Override for testing. |
| `RELAY_ACTIVE_SECS` | integer | `600` | Statusline relay segment (id:15bd) shows only when `RELAY_STATUS.md` was touched within this many seconds; otherwise hidden. |

Usage:
```bash
STRONG_TIER=opus /relay          # pilot Opus for review+handoff agents
/relay --strong-tier opus        # flag form (front door passes it to relay-loop.js via args.STRONG_TIER)
/relay -d --strong-tier opus     # Fable down → substitute Opus for review+handoff
```

Model IDs: `fable` → `claude-fable-5`, `opus` → `claude-opus-4-8`.

## Guardrails

- Verification-before-merge; one push per repo per turn; never two children pushing to
  the same remote (D5/D6 discipline).
- Parallelism only across repos, or within a repo on disjoint paths.
- Pilot a handful of income-relevant repos before any `--all` run — templates and the
  executor contract will need revision after first contact with real executor sessions.
- **Shared ledgers with `/meeting` (single-id-two-views, D2).** `TODO.md`, `ROADMAP.md`,
  and `REVIEW_ME.md` are written by BOTH the relay (in worktrees, `--no-ff` merged) and
  `/meeting` / manual edits (in the main checkout). None are `merge=union` — checkbox
  toggles `[ ]`↔`[x]` cannot union — so a concurrent meeting + pool can conflict at
  integration. Keep ledger writes line-scoped (flock'd `meeting/md-merge.py`); git
  surfaces the conflict (not silent); `orphan-scan.sh --cross-ledger` catches residual
  checkbox drift. Promotion REUSES the existing TODO id (handoff C2 / review step 5) —
  never mint a duplicate for already-tracked work. `RELAY_LOG.md` stays `merge=union`
  (append-only).
