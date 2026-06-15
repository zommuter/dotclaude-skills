---
name: fables-turn
description: Relay workflow that spends a strong reviewer-model turn (Fable/Opus) preparing repos for cheaper executor sessions (Sonnet), then verifying their work. Two modes — handoff (write docs, roadmap, failing-test specs, BDD) and review (verify executor work isn't gamed, re-derive roadmap). Trigger on "fables-turn", "relay handoff", "relay review", "hand off repos to executors", "review executor work". Keywords: relay, handoff, review, executor, checkpoint, ROADMAP, RELAY_LOG.
---

# fables-turn

A relay between a strong reviewer model and cheaper executor sessions, run ON THE
STRONG MODEL'S TURN. The strong turn produces what needs judgment — architecture,
roadmaps, failing tests as the spec, anti-gaming review — and leaves `[ROUTINE]` work
for Sonnet executor sessions driven by a generated `CLAUDE.md` contract.

Invocation:

```
/fables-turn                              # default: autonomous pool (no keyword)
/fables-turn -d                           # executor-only: strong model unavailable (--fable-down)
/fables-turn --fable-down                 # long form of -d
/fables-turn handoff [repo-list | --all]
/fables-turn review  [repo-list | --all]
```

Default `--all` means "confirmed OWN repos, by neediness, in waves of ≤5, until quota
says stop" — resumable across turns via the state file, never all 36 at once.

## Default mode: autonomous pool

Invoking `/fables-turn` with no keyword starts the autonomous priority-mixed pool
(meeting note `docs/meeting-notes/2026-06-12-2045-fables-relay-autonomous-pool.md`,
D1/D2):

0. **Fable-availability probe + apex-tier selection (Opus is APEX; Fable is a bonus).**
   Opus is the apex decision tier. Fable is treated as an OPTIONAL bonus second-opinion
   *if it returns* — never a required gate (user directive 2026-06-15: "treat Opus as the
   apex tier, Fable as a bonus re-review"). Do NOT warn when running on Opus — it is the
   intended tier; there is no self-guard and no `sleep`. Select the strong tier:
   - Read `~/.config/fables-turn/fable-probe.json` (`{available: bool, checked: ISO-ts}`).
     If absent or `checked` is older than **2 h**, PROBE once: spawn ONE tiny agent pinned
     to `model: claude-fable-5` with a trivial prompt. It returns → `available=true`; a
     "Fable unavailable" / model error → `available=false`. Write the cache either way.
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
   `/fables-turn handoff` to confirm a first wave) and exits cleanly without
   invoking the Workflow.
3. **Workflow launch.** The front door invokes the `fables-turn/scripts/relay-loop.js`
   Workflow script (id:83c9), passing `args.STRONG_TIER`, `args.interactive`,
   `args.fableDown` (true when `--fable-down`/`-d` is set), `args.POOL_WIDTH`
   (when overridden via `POOL_WIDTH` env var / `--pool-width` flag), and
   `args.RELAY_STATUS_PATH` (when overridden). The Workflow owns the pool, the serialized integrator, the
   quota guards, **and the self-feeding loop** — it re-discovers after each dispatch wave
   so executes→reviews→executes cycle inside a SINGLE invocation (`runRound()` in a `while`),
   ending only on the quota cap, two consecutive empty discoveries (backlog drained), or
   the `MAX_ROUNDS` seatbelt. The front door launches it ONCE; it is not relaunched
   per-wave. Scheduling order: verdict class
   first (execute → review → handoff, the D3 anti-gaming invariant), then repos
   flagged `income = true` in relay.toml win slot contention within a class
   (user directive 2026-06-12), then a *slight* `fable-standin` tiebreaker
   (user directive 2026-06-13): repos whose latest `fable-ckpt-*` was produced by
   Opus are marked `fable-standin`. Under the Opus-apex model these are **complete**
   work (Opus decided), so the marker only flags an *available optional Fable recheck*:
   on a Fable session with spare capacity they may be re-reviewed as a free second
   opinion (`@fable-optional-recheck`, id:9821), sorted **last** (real work first); on
   Opus/executor/handoff work they carry no special weight. It never excludes, never
   gates, and never marks work "pending" — an absent Fable simply means the optional
   recheck never runs.
4. **Exit summary.** After the Workflow completes, the front door prints the
   `RELAY_STATUS.md` path and the HANDBACK count, then ends the turn (plus the
   global git-diary-workflow/todo-update obligation).

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
5. **Integrate per completed child as one uninterrupted block**, repos strictly
   sequential: verify `contract_met` and checkpoint ordering → `--no-ff` merge the
   worktree branch into the integration branch → `scripts/ckpt-tag.sh <repo-path> -m
   "<summary>" -l "reviewer (<model>)"` → ONE push via
   `~/.claude/skills/git-diary-workflow/git-lock-push.sh --ff-only` → `git worktree prune` →
   update relay.toml (`status`, `last_ckpt`/`last_review`). A child that fails
   `contract_met` is NOT merged; its worktree is held and listed as a HANDBACK.
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

## Shared resources

- `docs/fables-relay.md` (repo root) — user-facing guide: what a relay turn does
  end-to-end, what the artifacts mean, what the human does between turns.
- `references/conventions.md` — environment facts + the verbatim executor-contract
  block embedded into every generated CLAUDE.md.
- `references/templates.md` — ROADMAP.md / RELAY_LOG.md / REVIEW_ME.md templates.
- `scripts/discover-repos.sh` — read-only ownership classifier (TSV).
- `scripts/ckpt-tag.sh` — atomic RELAY_LOG.md append + annotated `fable-ckpt-*` tag.

## State: `~/.config/fables-turn/relay.toml`

```toml
[repos.<name>]
classification = "own"          # own | clone | excluded (user-confirmed, sticky)
confirmed      = "YYYY-MM-DD"
status         = "pending"      # pending | handed-off | active | paused | blocked-dirty
handoff_date   = ""
last_ckpt      = ""
last_review    = ""
```

Tag/dirty facts are re-derivable from git; this file is the confirmation registry and
wave scheduler. The orchestrator is its only writer (after user confirmation).

## Configuration knobs

| Env var / flag | Values | Default | Effect |
|---|---|---|---|
| `STRONG_TIER` | `fable` \| `opus` | `opus` | Apex model for review/handoff/HARD-execute agents. **Default `opus`** — Opus is the apex tier; Fable is an optional bonus (user directive 2026-06-15). Execute (Sonnet) agents are never affected. Set/keep `fable` only when the step-0 probe **or** you explicitly confirm Fable is available. |
| `--strong-tier fable` / "Fable is available" | flag/override | off | The ONLY way to use Fable: asserts Fable is up, overriding even a failing step-0 probe. Use when you know Fable works despite a probe error. Without it the default stays `opus`. |
| `--fable-down` / `-d` | flag | off (probe decides) | Forces Fable-down *without* probing. On the now-default `STRONG_TIER=opus` it is a **no-op** (Opus is already apex). Only meaningful with an explicit `STRONG_TIER=fable`, where it triggers the legacy defer/demote (executor-only) path. Passed as `args.fableDown = true`. |
| `--interactive` | flag | off | Re-enables the one-batch `AskUserQuestion` confirmations before launch; passed to the Workflow as `args.interactive`. Default mode is unattended. |
| `RELAY_QUOTA_THRESHOLD` | 0–1 fraction | `0.90` | Quota stop threshold used by `scripts/quota-stop.sh` (cache `.utilization` is 0–100 percent; converted internally). |
| `RELAY_QUOTA_THRESHOLD_<BUCKET>` | 0–1 fraction | (general threshold) | Per-bucket override of `RELAY_QUOTA_THRESHOLD` for one cache bucket only, e.g. `RELAY_QUOTA_THRESHOLD_SEVEN_DAY=0.50` or `RELAY_QUOTA_THRESHOLD_SEVEN_DAY_SONNET=0.50`. Caps a long-window bucket tighter than the 5h bucket ("use most of the 5h window but never exceed 50% of 7d/Sonnet"); buckets without an override keep the general threshold, so behaviour is unchanged unless set. |
| `POOL_WIDTH` | integer | `5` | Number of distinct repos dispatched in parallel (one unit per repo). Passed as `args.POOL_WIDTH`. NOTE: the Workflow harness independently caps concurrent agents at `min(16, cpu_cores-2)`, so values above that ceiling just queue — no benefit. |
| `RELAY_QUOTA_DECAY_7D` | `START:END` fractions | (unset) | Time-decaying cap for the 7-day + 7-day-Sonnet buckets: the threshold linearly interpolates from `START` at the rolling 7-day window's open to `END` at its reset (e.g. `0.70:0.10` → ~0.53 at 2/7 elapsed), so a self-looping run front-loads work early in the window and backs off late. Recomputed each gate check from `seven_day.resets_at`. 5h bucket unaffected. Forwarded into the quota-gate via args. |
| `MAX_ROUNDS` | integer | `30` | Self-feeding-loop seatbelt: max re-discover→dispatch→drain rounds in one `relay-loop.js` invocation before it returns regardless. The loop normally ends earlier on the quota cap or two consecutive empty discoveries (backlog drained). Passed as `args.MAX_ROUNDS`. |
| `RELAY_STATUS_PATH` | path | `~/.config/fables-turn/RELAY_STATUS.md` | Where the cross-repo rollup is written (override for testing). |

Usage:
```bash
STRONG_TIER=opus /fables-turn          # pilot Opus for review+handoff agents
/fables-turn --strong-tier opus        # flag form (front door passes it to relay-loop.js via args.STRONG_TIER)
/fables-turn -d --strong-tier opus     # Fable down → substitute Opus for review+handoff
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
