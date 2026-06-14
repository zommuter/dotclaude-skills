# The fables relay — user guide

What the `fables-turn` / `fables-executor` skill pair actually does, what the
artifacts in your repos mean, and what *you* are expected to do between turns.
(The skills' own SKILL.md / references/ files are internal procedure docs for
the models; this page is for the human.)

## The idea in one paragraph

A strong reviewer model (Fable, or Opus via `STRONG_TIER=opus`) spends its
expensive turns on what needs judgment: writing roadmaps, specifying work as
*failing tests*, and auditing finished work for gaming. Cheap Sonnet executor
sessions then grind through the well-specified `[ROUTINE]` items. The relay is
the protocol between them: checkpoints, an append-only log, and a
trust-but-verify review that diffs everything an executor touched since the
last checkpoint and re-runs the *original* test versions against the new code.

## Three ways to run it

| Command | What it does | When you run it |
|---|---|---|
| `/fables-turn` | **Autonomous pool** (unattended). Classifies every confirmed repo into execute / review / handoff, dispatches up to 5 units in parallel (Sonnet executors first, strong-tier review/handoff backfill, income-flagged repos win ties), integrates and pushes serially, stops on quota. | The default. Kick it off when you want the fleet to make progress without you. |
| `/fables-turn handoff [repos]` | Prepares repos for executors: writes/refreshes docs (C1), roadmap with sized `[ROUTINE]`/`[HARD]` items (C2), red tests as the spec (C3), BDD scenarios (C4), optionally executes the top `[HARD]` item (C5). | Once per repo to onboard it; again when a repo's roadmap is exhausted. |
| `/fables-turn review [repos]` | Audits everything since the last checkpoint: test-integrity (deleted/weakened/rewritten tests, fixture special-casing), spec drift, then re-derives the roadmap and optionally executes a `[HARD]` item. | After executor sessions worked a repo, or any time you want an anti-gaming sweep. The autonomous pool schedules these automatically. |

A plain Sonnet session working inside a managed repo is an **executor**: the
repo's `CLAUDE.md` carries a `## Relay contract` pointer telling it to load
`/fables-executor` and follow the five contract rules (ROUTINE items only,
red-test definition of done, never touch test expectations, self-report to
RELAY_LOG.md, hygiene).

## The artifacts and what they mean

- **`ROADMAP.md`** (per repo) — the executor task queue. Each item has
  Acceptance / Tests / Done-check / Context fields and an opaque `<!-- id:XXXX -->`
  token. Unticked items with red tests are *open specs* — the failing test IS
  the spec ("expected-red" in the suite). Only the reviewer adds, removes, or
  re-scopes items; executors only tick checkboxes.
- **`RELAY_LOG.md`** (per repo, append-only, `merge=union`) — the relay's
  flight recorder: checkpoint paragraphs from `ckpt-tag.sh`, executor
  self-reports, `BLOCKED:` lines. Read it to see what happened while you were
  away.
- **`REVIEW_ME.md`** (per repo) — judgment calls queued **for you**: checkboxes
  the models did not want to decide unilaterally, plus `@manual` BDD checklists
  only a human can run. This is your main between-turns duty.
- **`fable-ckpt-YYYYMMDD-HHMM` tags** — annotated checkpoint tags marking each
  integrated relay turn. The diff window between the last tag and HEAD is what
  the next review audits. Don't delete them.
- **`~/.config/fables-turn/relay.toml`** — the confirmation registry and
  scheduler state: which repos are confirmed `own`, their status, last
  checkpoint/review dates, and the `income = true` flags that get scheduling
  priority. Only the orchestrator writes it (after your confirmation).
- **`~/.config/fables-turn/RELAY_STATUS.md`** — live cross-repo rollup during
  autonomous runs: in-flight units, completed integrations with their tags,
  queued/blocked repos, quota remaining, open REVIEW_ME counts. Overwritten on
  every integration; read-only for humans.
- **Worktrees under `~/.cache/fables-turn/worktrees/<repo>/`** — children work
  in isolation and never push. A worktree that is still there after a turn is a
  **HANDBACK**: work that failed its contract and was deliberately *not* merged.
  It survives on disk with its branch; the turn summary / RELAY_STATUS tells
  you why. Either fix and merge it manually, or delete it.

## What you do between turns

1. **Work through `REVIEW_ME.md`** in repos you care about — tick, correct, or
   reject the judgment boxes; run any `@manual` checklists.
2. **Ratify gated decisions** — `[HARD]` items and TODO gates the reviewer
   queued for an explicit user call.
3. **Resolve HANDBACKs and blocked-dirty repos** — commit or stash stray
   changes in repos the relay refused to touch; inspect held worktrees.
4. **Adjust the registry when asked** — new repos are only ever included after
   you confirm them (in `--interactive` mode or a manual handoff turn).

## Knobs

| Knob | Default | Meaning |
|---|---|---|
| `STRONG_TIER` (env or `--strong-tier`) | `fable` | Model for review/handoff agents (`opus` pilotable). Executors are always Sonnet. |
| `--interactive` | off | Re-enables the one-batch confirmation questions before an autonomous run. |
| `--fable-down` / `-d` | off | Asserts the Fable strong tier is unavailable this run (one axis); composes with `STRONG_TIER`. With `STRONG_TIER=fable` (default, no substitute): defer strong work, run executors only — a `review` repo that also has open `[ROUTINE]` work is demoted to execute so the pool stays busy; handoff units and review-only repos are deferred and surface in RELAY_STATUS Queued. With `STRONG_TIER=opus` (`-d --strong-tier opus`): substitute Opus for the unavailable Fable — review/handoff dispatch normally on Opus (marked `fable-standin`), nothing is deferred/demoted. |
| `RELAY_QUOTA_THRESHOLD` | `0.90` | Utilization fraction at which dispatch stops (in-flight work still drains and integrates). |
| `RELAY_STATUS_PATH` | `~/.config/fables-turn/RELAY_STATUS.md` | Rollup location override (mostly for testing). |
| `income = true` (relay.toml) | — | Marks a repo income-relevant; such repos win dispatch-slot contention within their class. |

## Safety properties worth knowing

- One push per repo per turn, always through the flock'd
  `git-lock-push.sh --ff-only`; integrations are strictly serialized — two
  children can never push the same remote concurrently.
- Work that fails its contract is never merged (HANDBACK, see above).
- The quota gate checks before *every* dispatch (tier-aware: executors stop
  when any of the three buckets is exhausted; strong agents on the 5h/7d
  buckets) and a stale or missing usage cache means "stop, uncertain" — the
  relay fails toward doing less, not more.
- Push-to-main is deliberate (meeting D6): gamed work surviving until the next
  review was judged cheaper than a staging-branch process; the scheduler
  guarantees unreviewed executor work is the top-priority strong unit.

See `fables-turn/SKILL.md` for orchestrator internals,
`fables-executor/SKILL.md` for the executor contract, and
`docs/meeting-notes/2026-06-12-2045-fables-relay-autonomous-pool.md` for the
design decisions behind the autonomous pool.
