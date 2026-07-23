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
/relay health  [repo | --all]        # relay-machinery health report (id:3eb5): runs relay-doctor.sh
/relay inject  <repo> [--item ID] [--verdict execute|review|hard|handoff] [--prompt TEXT]  # enqueue a high-priority unit into the running pool (id:354f); no <repo> ⇒ list pending
/relay executor                      # load the lean executor contract (cheap Sonnet sessions)
/relay stop [--after N | --now]      # graceful drain-then-end of a RUNNING pool (id:c012)
/relay --once                        # launch: dispatch one round, then stop (id:c012)
```

## `executor` arg (lean executor contract)

`/relay executor` is invoked at the start of a cheap Sonnet executor session. It loads
**only** `references/executor-contract.md` (the 5-rule contract + ROADMAP/RELAY_LOG
format) — it does NOT load the rest of this orchestrator SKILL.md. Read that reference
and follow its rules exactly; ignore everything below (orchestrator-only).

Default `--all` means "confirmed OWN repos, by neediness, in waves of ≤5, until quota
says stop" — resumable across turns via the state file, never all 36 at once.

**Host-aware verification (id:43b9, multi-host config monorepos).** A ROADMAP item may
carry an optional `[host:<name>]` tag (`[host:zomni]`/`[host:fievel]`/`[host:any]`; untagged
⇒ `host:any`). *Editing* a config file is host-agnostic — any host writes it. But the
definition-of-done (`make install`/tests) is HOST-BOUND: you cannot validate fievel's apt
path or zomni's udev rule on the wrong machine. So both the executor done-check (contract
rule 2) and the reviewer re-derivation (review §2c) consult `scripts/host-gate.sh '<item
line>'` before verifying — exit 0 ⇒ proceed, exit 3 ⇒ **DEFER** the item with a `needs
host:<X>` note rather than run install/tests on the wrong host (the conservative default).
ssh-to-host verification is a documented FUTURE option, not built. Ordinary single-host
repos carry no tag, so the gate is a no-op for them.

## `health` arg (relay-machinery health report) <!-- id:3eb5 -->

`/relay health [<repo-dir> | --all]` runs `relay/scripts/relay-doctor.sh` and prints
the report-only relay-health summary to the screen.

- **No arg**: health-checks the cwd repo.
- **`<repo-dir>`**: health-checks that specific repo path.
- **`--all`**: health-checks every `classification = "own"` repo from `relay.toml`.

The report collates: cross-ledger TODO↔ROADMAP checkbox drift (`orphan-scan.sh
--cross-ledger`), ROADMAP grammar/lane violations (`roadmap-lint.sh`), reference-doc
install completeness (id:69ef), and parked orphan branches (`relay-reconcile.sh
--all`). It always exits 0 (report-only by default — pass `--strict` to relay-doctor
directly for a nonzero-on-issues gate; see id:a883). Use this for ad-hoc diagnostics;
the same checks also run as a `/relay review` sub-step.

```bash
/relay health           # cwd repo
/relay health --all     # all own repos
~/.claude/skills/relay/scripts/relay-doctor.sh [<repo>|--all] [--strict]  # direct
```

## `inject` arg (enqueue a high-priority unit into the running pool) <!-- id:354f -->

`/relay inject <repo> [--item ID] [--verdict execute|review|hard|handoff] [--prompt TEXT]`
is the ergonomic front door over `relay/scripts/inject.sh add` (id:baf1) — it lets a user
(or another session) enqueue a high-priority unit into the running autonomous pool without
calling the script by hand. The pool's discovery prelude calls `inject.sh take` each round
and dispatches an injected unit AHEAD of its normal verdict-class schedule
(execute→review→hard→handoff).

Front-door procedure:
1. **Resolve `<repo>` against `relay.toml`** — THE canonical own set (honoring `# path:`
   overrides / `RELAY_TOML`; never a `~/src` glob). A name **not confirmed `own`** there is a
   **LOUD reject** (surface it, no enqueue) — never guess, never mint anything, never onboard.
2. **Default `--verdict execute`** when omitted; validate it is one of
   `execute|review|hard|handoff` (else LOUD reject — `inject.sh add` also enforces this). `--item`
   (a specific ROADMAP id to work) and `--prompt` (freeform instruction for the child) are
   optional pass-throughs.
3. **Enqueue** by calling the script verbatim — **mint nothing here** (the token is the
   script's): `~/.claude/skills/relay/scripts/inject.sh add <repo> [--item ID] [--verdict V] [--prompt TEXT]`.
4. **Echo the printed token** and confirm it will be `take`n on the next discovery round:
   "injected `<token>` (repo=`<repo>`, verdict=`<verdict>`) — the running pool consumes it next
   discovery round, ahead of its verdict class; if no pool is live it waits in the inbox until
   one starts." Injection does NOT itself launch a pool.

**List pending (non-consuming):** `/relay inject` with no `<repo>` (or `/relay inject --list`)
runs `~/.claude/skills/relay/scripts/inject.sh peek` and prints each pending injection (one
compact JSON per line) — NON-consuming, safe to run anytime. The default-mode front door also
surfaces any pending (not-yet-taken) injections in its launch notice / `RELAY_STATUS.md`, so an
enqueue made while no pool is live is visible rather than silently waiting.

Out of scope: writing `relay.toml` (inject never onboards/confirms a repo); consuming the inbox
(`take` is the pool's job in the discovery prelude, never the front door's); priority
REORDERING of a naturally-discovered unit (that is `--priority`, id:d530 — a different mechanism
that creates no unit and can never double-dispatch).

## Default mode: autonomous pool

Invoking `/relay` with no keyword starts the autonomous priority-mixed pool
(meeting note `docs/meeting-notes/2026-06-12-2045-fables-relay-autonomous-pool.md`,
D1/D2):

0pre. **Arg-guard (id:7681) — before any other setup, including 0a.** Run
    `~/.claude/skills/relay/scripts/validate-flags.sh relay -- <the raw invocation
    args>`. Known flags/modes pass through silently. An unknown leading-dash token prints
    a LOUD warning to stderr listing the known flags and is dropped (not folded into a
    repo-list/subject argument) — display that warning, then proceed using the CLEANED
    stdout as the effective args. A near-miss of a mode-changing flag (edit-distance <=2
    of `--afk`/`-d`) instead ESCALATES (non-zero exit): surface it and confirm intent
    (interactive) or treat the run as blocked and surface it in `RELAY_STATUS.md`
    (unattended) rather than silently guessing. Skip this step only when re-entering from
    a Workflow round (the front door already validated args once at launch).

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
   - Manage the cache `~/.config/relay/fable-probe.json`
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
   mid-run. No `AskUserQuestion` is issued anywhere in the default mode. **Pending
   injections** (from `/relay inject`, id:354f) are likewise surfaced — the front door runs
   `inject.sh peek` (non-consuming) at launch and lists any not-yet-taken units in the launch
   notice / `RELAY_STATUS.md`, so an enqueue made while no pool was live is visible rather than
   silently waiting for the next `inject.sh take`.
2. **No confirmed repos → notice, no launch.** If relay.toml has zero confirmed
   `own` repos, the front door prints a short notice (pointing at
   `/relay handoff` to confirm a first wave) and exits cleanly without
   invoking the Workflow.
2b. **Autonomous-pool singleton guard (id:11c6 — bare no-arg `/relay` only).** Immediately
   before launching the Workflow, and ONLY for a bare no-arg autonomous run, acquire a
   process-wide singleton claim via the EXISTING `claim.sh` (compose — no new lockfile
   machinery):
   - `~/.claude/skills/relay/scripts/claim.sh acquire pool:autonomous --run relay-pool-$CLAUDE_SESSION_ID --mode autonomous`.
   - **Refused** (a 2nd autonomous pool is already live — `claim.sh peek` names the holder
     run) → do NOT launch a duplicate: print "autonomous pool already running (held by
     `<holder>`); not launching a duplicate — run a directed/parallel session instead
     (`/relay <repos>`, `--priority`, `--exclude`, or `--afk`), or `/relay stop` the live
     one" and exit cleanly (no Workflow launch).
   - **Acquired** → proceed to launch (step 3); release run-scoped when the Workflow returns
     (step 4): `claim.sh release pool:autonomous --run relay-pool-$CLAUDE_SESSION_ID`. The
     claim's mtime-TTL auto-expires a crashed pool's claim, so the guard never wedges a
     future run (fail-open).
   - **EXEMPT — never guarded** (legitimate multi-clauding must be unaffected — 54 overlap
     events, 16% of messages): any **directed** keyword mode (`handoff`/`review`/`human`/
     `next`/`executor`/`stop`), any **scoped** run (`--priority`/`--exclude` or an explicit
     repo-list), and **`--afk`** runs. These do NOT acquire `pool:autonomous` and run freely
     in parallel. The guard refuses ONLY a second bare-`/relay` autonomous pool. Out of
     scope (id:11c6): blocking any directed/parallel run; any new lockfile.
3. **Workflow launch.** The front door invokes the `relay/scripts/relay-loop.js`
   Workflow script (id:83c9), passing `args.STRONG_TIER`, `args.interactive`,
   `args.fableDown` (true when `--fable-down`/`-d` is set), `args.POOL_WIDTH`
   (when overridden via `POOL_WIDTH` env var / `--pool-width` flag),
   `args.allowIntensive` (true ONLY when `--intensive` / `--allow-intensive` is set — id:8d52,
   semantics revised id:052c; a bare `--afk` NO LONGER sets it — `--afk` stays non-intensive,
   and `--intensive` implies `--afk`),
   `args.priorityRepos` / `args.excludeRepos` (per-run repo lists from `--priority` /
   `--exclude` — id:d530; the front door maps the natural-language forms the user types
   ("priority on X", "exclude Y") onto these arrays),
   `args.onlyRepo` (id:7633 — a first-class SINGLE-REPO scope from a bare repo positional /
   `.` / `--only <repo>`; the front door resolves a `.` to the cwd repo's basename
   `basename "$(git rev-parse --show-toplevel)"` BEFORE launch, and passes the resolved NAME —
   see **Single-repo scope** below),
   `args.RUN_ID` (id:c5ba follow-up — the front door MINTS the run id itself, in shell, BEFORE
   launch: `relay-$(date +%Y%m%d-%H%M%S)-$RANDOM`, and passes it here. relay-loop.js seeds
   `state.runId` from it so a valid `RELAY_RUN_ID` exists at the PRE-DISCOVERY round-1 quota gate
   — the discovery prelude that used to mint it runs AFTER that gate, so without a front-door mint
   `state.runId` was `''` at the first quota check, which disabled the extrapolation fallback +
   burn-sampler (both gated on `RELAY_RUN_ID`) and blind-stopped any background run the moment its
   `/tmp` cache went stale. Workflow scripts cannot call `date`/`$RANDOM` (both unavailable in the
   sandbox), which is why the mint MUST happen in the front door, not the script. The prelude's
   `state.runId || prelude.runId` keeps the front-door value; the uniqueness guarantee is
   unchanged (date+`$RANDOM` is as unique as the prelude's own mint), and
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
4. **Exit summary.** After the Workflow completes, the front door releases the
   autonomous-pool singleton claim run-scoped (id:11c6 — only if it was a bare no-arg run
   that acquired it in step 2b): `claim.sh release pool:autonomous --run
   relay-pool-$CLAUDE_SESSION_ID` (run-scoped → a no-op if not held). Then it runs
   `relay/scripts/backtest-verdict.py --append-log` (post-drain, id:1324 — appends one
   summary JSON line to `~/.config/relay/shadow-log.jsonl` so the id:9d2b accumulation
   gate accrues mechanically; report-only, exit 0). Then it prints the
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
*before* the Workflow launches. The Workflow script itself never calls
`AskUserQuestion` and no longer consumes `args.interactive` — the mechanical
discovery flip (id:a0b6) removed its only consumer.

The existing `handoff` and `review` keyword modes are unchanged and fully
compatible — the default mode is sugar over the same classifier, references, and
integration invariants.

## Orchestrator invariants (never skip)

1. **Discover + reconcile.** Run `scripts/discover-repos.sh [repos…]`. Reconcile its TSV
   against `~/.config/relay/relay.toml`. Present only NEW or changed repos for
   confirm/prune; persist confirmations. `needs_review` repos (mixed-remote forks, dirty
   clones) are never auto-included — they require an explicit user call.
   **Reconcile the shared inbox on every `--all` run (id:1d3f, meeting 2026-06-30).** When
   the scope is cross-repo (`--all` / no explicit repo-list — `human`/`review`/`handoff`
   AND the bare autonomous pool), run the inbox dead-letter auto-filer ONCE, BEFORE triage:
   `scripts/scan-routed.sh --apply --exclude truncocraft` plus one `--exclude <repo>` per
   repo in this run's `--exclude` set (always include `truncocraft`, the hard-exclude;
   `scan-routed.sh` already skips `paused` repos). It is idempotent (greps `routed:XXXX`
   first), class-A only (conforming token + repo resolves on disk → INBOUND stub written +
   committed + `inbox-done`); class-B prose stays surfaced-only (the id:678e slice-2 gate).
   Surface what was auto-filed in `RELAY_STATUS.md` / the turn summary. A directed
   single-repo / non-`--all` run does NOT run this `--all` auto-filer sub-step — but it
   MUST still check the per-repo filtered inbox surface instead (id:ce50):
   `scripts/inbox-scan-repo.sh <repo>`, once per repo in scope. That is a report-only
   VISIBILITY check (never writes), distinct from the `--all` auto-filer above; it
   surfaces any `[<repo>]`-targeted inbox item so a directed run no longer misses it
   the way `/relay human .` did on chidiai 2026-07-20 (routed:4975).
2. **Cheap pre-scan, then ONE question batch.** Spawn ≤5 lightweight read-only Explore
   agents (README + tree + `git log` skim, no worktrees) to collect per-repo clarifying
   questions and a dirty assessment. Ask the user EVERYTHING in one `AskUserQuestion`
   batch — new-repo confirmations, dirty-repo `wip: pre-relay snapshot` offers, and
   spec ambiguities. Never ask mid-flight after spawning.
3. **Allocate id tokens.** For each repo, pre-allocate roadmap tokens:
   `~/.claude/skills/meeting/append.sh new-ids <N> <repo-root>`.
4. **Spawn waves of ≤5 children** via plain Agent-tool fan-out (one repo per child),
   each in its own worktree under `~/.cache/relay/worktrees/<repo>/<runId>-<verdict>`
   (outside the repo tree, so it never pollutes status) — the child CREATES it with an
   explicit `git -C <repo> worktree add ~/.cache/relay/worktrees/<repo>/<runId>-<verdict>`
   that names the TARGET `<repo>`. **Do NOT use the Agent tool's `isolation: worktree`
   parameter for a relay child (id:c6c8): it is CWD-repo-relative — it worktrees the
   session's *current* repo, not `<repo>`, so a cross-repo child silently gets an isolated
   worktree of the WRONG repo and ends up editing the target's MAIN checkout unisolated
   (observed 2026-06-30: a jobAI executor dispatched with `isolation: worktree` from a
   dotclaude-skills cwd committed straight to jobAI's real `main`). Use the explicit relay
   worktree above; or — for a review/ledger-only pass — work the target's main checkout
   directly under the held lease (the id:15d5 review pattern, since ledger writes land in
   the main checkout anyway).** Pass the child the relevant reference doc
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
   sequential: verify `contract_met` and checkpoint ordering → **isolation gate (id:f682)**
   `~/.claude/skills/relay/scripts/verify-isolation.sh <worktree> [--base <ref>]` (mirrors
   `clean-tree-gate.sh`; exit 2 = the child's worktree is empty or dirty — a likely
   main-checkout write, NOT a normal merge conflict — ABORT the merge and defer; see
   `references/conventions.md`'s recovery-doctrine paragraph for the salvage-under-lease
   path before discarding) → `--no-ff` merge the
   worktree branch into the integration branch → `scripts/ckpt-tag.sh <repo-path> -m
   "<summary>" -l "reviewer (<model>)"` → ONE push via
   `~/.claude/skills/git-diary-workflow/git-lock-push.sh --ff-only` → `git worktree prune` →
   update relay.toml. `ckpt-tag.sh` itself now syncs `last_ckpt` (and, for a strong-model
   label, `last_strong_ckpt`/`strong_model`) via the flock'd `relay-state-write.sh` (id:0a3b
   — before this, supervised-session checkpoints left the watermark stale and the pool
   re-dispatched duplicate strong reviews, 2026-07-01); you still set the fields it does NOT
   own — `status`, `last_review`/`handoff_date`, `fable_rechecked` — via
   `~/.claude/skills/relay/scripts/relay-state-write.sh toml-set <repo> <key> <value>`
   (NEVER hand-edit relay.toml). A child that fails
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
  RELAY_LOG + `relay-ckpt-*` tag) → `git-lock-push.sh --ff-only` → force-free `git branch -d`
  the consumed (now-merged) ref (id:373e; a refusal is surfaced + left, never force-deleted).
  A merge **conflict** is `git merge --abort`ed and the branch is **left + surfaced**, never
  half-merged.
- **discard** — `RELAY_DISCARD_CONFIRM=1 relay-reconcile.sh --discard <branch>` → `git branch
  -D` (drop the work). The destructive force-delete is **gated behind the explicit
  `RELAY_DISCARD_CONFIRM=1`** (force-push.sh model, id:373e); without it, discard refuses so
  automation/accident can't destroy parked work.
- **leave** — do nothing; the `relay/orphan/*` ref stays for a later pass.

`<branch>` may be given with or without the `relay/orphan/` prefix. `id:3313`, `id:4e14`.

## Next mode

`/relay next` is a quick auto-router: it inspects the CURRENT repo's state and acts,
collapsing the "human-or-not" decision to its fastest form. It operates on the **cwd
repo by default** (`git rev-parse --show-toplevel`, consistent with the `review`-default
flip above) and does NOT define new work — it reuses the existing executor/review/human
modes. Decide ONE route and take it:

1. **Open executor-ACTIONABLE `[ROUTINE]` items in `ROADMAP.md`** → run as **`/relay
   executor`** (load the lean executor contract, work the routine items). Autonomous — do
   NOT ask. "Executor-actionable" is the `actionable_routine_open` predicate from
   `classify-repo.sh` (the single source — do not re-derive it): primary-lane `[ROUTINE]`,
   NOT `@manual`/human-gated, NOT `🚧`/`BLOCKED on`-gated. An `@manual`-only or blocked
   `[ROUTINE]` set does NOT take this route (id:9014).
2. **Else, unaudited commits since the last relay checkpoint tag** (`git tag -l
   'fable-ckpt-*' 'relay-ckpt-*' | sort | tail -1`, then commits after it) → run
   **`/relay review`** on this cwd repo (the per-repo default). Autonomous — do NOT ask.
2a. **Else, an EFFECTIVELY-DRAINED ROADMAP that still has open TODO backlog** — when
   `ROADMAP.md` has **no executor-actionable open `- [ ]` item** — zero open boxes OR only
   `@manual`/human-lane/`🚧`-blocked boxes remain (**effectively drained**, id:9014; the
   `roadmap_actionable_open == 0` predicate from `classify-repo.sh`) — do NOT conclude
   "drained / needs human": run
   `relay/scripts/unpromoted-scan.sh` (id:2dea) and check the open `TODO.md` backlog.
   Promoting TODO→ROADMAP is exactly handoff C2's job (the 2026-06-25 truncocraft miss: a
   fully-`[x]` ROADMAP hid five open TODO items, so the repo read as drained for days). If
   the scan reports any item → route to **`/relay handoff`** on this repo (promote the
   backlog), NOT "human/idle". The scan is **lane-tag-agnostic** and labels each item:
   `promote` (executable lane already tagged → directly promotable), `surface` (untagged /
   `[HARD — meeting]` → handoff C2 lane-triages it, **never auto-promote with a guessed
   lane**), `untracked` (an open checkbox with no `<!-- id -->` — the favicon-class gap;
   mint an id via `append.sh new-id` first). NOTE: when ROADMAP still has executor-actionable
   open items the un-promoted list is normal design-ledger backlog, not a routing signal —
   this route fires only on a genuinely (effectively-)drained ROADMAP.
3. **Else, a judgment box truly needing a human** — open `REVIEW_ME.md` `- [ ]` boxes,
   open `@manual` scenarios, or genuinely-chewy design — → route to **`human`** (the
   cross-repo human-backlog triage) or **`/meeting`**. This is the ONLY route that
   involves the human.

Optimize for the fastest human-or-not call: do the autonomous executor/review work
**without asking**; only stop for the human when a judgment box genuinely requires it.
**When unsure, prefer acting over asking** — a borderline-routine item runs as executor
work, and the next `review` re-checks it (anti-gaming). If multiple routes apply, take
the earliest in the list (execute → review → handoff-promote → human), mirroring the
default pool's verdict-class order.

## Single-repo scope

`/relay <repo>` (named) and `/relay --only <repo>` run the **autonomous pool scoped to ONE
repo** (id:7633). It is the SAME engine as the default pool — same verdict classes, same
dispatch/integrate/review chain — merely narrowed at discovery: the front door passes
`args.onlyRepo`, and `relay-loop.js` resolves it against the canonical `relay.toml` own
set (honoring `# path:`), then feeds **only that repo** into the exclude filter + sig-cache +
discover fan-out. The own-repo universe enumeration + the 40× `discover-repo.sh` classification
are bypassed; only the one repo is classified (the per-repo path is reused, never forked). A name
not confirmed `own` in `relay.toml` is a **LOUD reject** (surfaced in `RELAY_STATUS.md`, nothing
dispatched) — never a `~/src`-glob guess. This is the first-class replacement for the old
`--exclude`-every-other-repo workaround, which silently missed `# path:`-relocated repos.

**Bare `/relay .` (the cwd repo, no other args) is the one exception — see Drain mode below.**
The 2026-07-19 Amendment reverses id:7633 acceptance #4 ("`/relay .` = the autonomous
single-repo Workflow pool") for the bare-dot form only: `/relay .` now means the
**off-Workflow drain**, not this Workflow pool. `/relay <repo>` and `/relay --only <repo>`
(named-repo forms) are unaffected and still resolve to the single-repo POOL described above.

`--exclude` still filters the SAME canonical own set BEFORE any classification, and an unknown
`--exclude`/`--priority` name still LOUD-rejects against the FULL own set, even under a
single-repo scope (so `/relay zkm --exclude bogus` still surfaces `bogus`).

**Scope vs. `next` (design decision, id:7633 acceptance #4): a bare `/relay .` does NOT route to
`/relay next` semantics.** They are deliberately distinct verbs:
- `/relay .` runs the **autonomous single-repo POOL** — unattended, no `AskUserQuestion`, it
  dispatches the repo's naturally-discovered verdict-class work (execute/review/hard) exactly as
  the fleet pool would, just for one repo. It never involves the human.
- `/relay next` is the **interactive auto-router** that collapses the cwd repo to its ONE fastest
  route and *can* stop for the human (`human`/`/meeting`), using `AskUserQuestion` — which a
  Workflow cannot call. Conflating the two would either strip `next`'s human-routing (surprising
  for a user who typed `next`) or inject `AskUserQuestion` into the unattended Workflow path
  (impossible). Keeping them separate preserves least-surprise: `.` = "run the pool, but only
  here"; `next` = "inspect here and pick the single fastest route, human included." The user
  chooses the verb; the engine never silently swaps one for the other.

## Drain mode

**Bare `/relay .` = the off-Workflow drain (2026-07-19 Amendment, supersedes id:7633
acceptance #4 — "a bare `/relay .` = the autonomous single-repo Workflow pool").**
`classify-repo.sh` proved the per-repo classification is free and deterministic
(`ambiguous:false`, zero agents), so spinning the full Workflow harness — a once-only
prelude agent plus a discovery-runner agent **per round** — for ONE repo was the waste, not
the classification logic. The owner ratified reversing the front door instead of keeping
both meanings: `/relay .` now drives the lean **off-Workflow drain**, run by the apex
session or the host `drain-driver.mjs` script (id:cd7a, a child of id:93fe, NOT a Workflow
script) — it calls `classify-repo.sh` directly, dispatches ONE agent per unit in a worktree,
integrates, re-classifies, and loops round by round — **no Workflow prelude/discovery
agents** — until the backlog is **drained or fully human-blocked**: the `isDryRound`→
`drained` (K=2 consecutive no-substantive-progress rounds, keyed on the inlined `drain.mjs`
substantive/dry/blocked classification, id:d58f/4ca8) and `isBlockedRound`→
`blocked-pending-human` termination ARE the drain contract (meeting
`docs/meeting-notes/2026-07-19-2035-relay-drain-parallel-contract.md`, D2/D6).

`/relay . --drain` (id:93fe Phase 1) names the exact same off-Workflow drain explicitly.
**`--drain` stays a discoverability alias, not a new engine** — since a bare `/relay .`
already drains, `--drain` is not strictly needed; it just names the intent for a user who
reaches for the flag, or lets you request the drain on a named/`--only` repo
(`/relay zkm --drain`) without relying on cwd. Prefer `/relay .` if you already know it
drains; `--drain` is sugar for the same off-Workflow `drain-driver.mjs`.

**Build status:** this section documents the ratified front-door *meaning* the id:cd7a
driver core and its heartbeat/quota/event wiring (id:f9d2/838d/dd1e) implement — NOT their
build state (which rots if restated here). Track merge/wiring state in ROADMAP.md, not here.

The remaining Phase-1 contract item — the **review-agent anti-spam brief** (D3: a reviewer may
open a REVIEW_ME box only for genuine human-judgment, never to re-question already-decided
design) — is owned by **id:c17c** (which names "the id:93fe review-agent brief") and is queued,
NOT part of this alias. **`--parallel N` (Phase 2, id:ebbe)** is not yet built — see the flags
table.

## Stop mode

`/relay stop` is the **voluntary, operator-initiated** graceful wind-down of a *running*
autonomous pool (id:c012) — distinct from the *involuntary* quota-stop and from a hard
`TaskStop`. It exists because the self-feeding loop otherwise ends only on quota cap, two
dry discoveries (backlog drained), or the `MAX_ROUNDS` seatbelt; before this there was no
way to say "finish what you're doing and stop" without `TaskStop` killing in-flight
children mid-task and parking their worktrees as `relay/orphan/*`.

**How it works.** The pool's `discover-prelude` (which runs shell at the top of every
round) checks a **STOP sentinel file** — `~/.config/relay/STOP` by default (override via
`RELAY_STOP_PATH` / `args.STOP_PATH`). The sentinel's CONTENT is an integer "rounds
remaining before stop":

- **`/relay stop`** — write an EMPTY file (e.g. `: > ~/.config/relay/STOP`). At the next
  round boundary the prelude sees it, **consumes** it (`rm`), and the loop drains the
  already-dispatched wave + integration debt, **drops queued-but-not-dispatched units, does
  NOT re-discover/dispatch a new wave**, and returns cleanly with `stopReason: "user-stop"`.
  Nothing is abandoned — the prior round's integration was already drained before the stop
  is observed.
- **`/relay stop --after N`** — write `N` to the file (`printf '%s' N > ~/.config/relay/STOP`).
  The prelude decrements `N→N-1` each round and fires the stop when it reaches 0, i.e. the
  pool drains `N` more rounds then winds down.
- **`/relay stop --now`** — the impatient path: this is just the hard `TaskStop` of the
  running Workflow (orchestrator calls `TaskStop`), accepting that in-flight children are
  killed and their worktrees park as `relay/orphan/*` (recover via `/relay reconcile`). Use
  only when you won't wait for the current wave to finish.

The sentinel is **self-consuming and fail-safe**: only a literal `stopRequested===true` from
the prelude triggers the stop, so a flaky read can never wedge the pool, and a fired sentinel
is removed so it can't silently stop the *next* pool. To cancel a pending `/relay stop`
before it fires, just `rm ~/.config/relay/STOP`. The check/countdown/consume step is one
atomic call to `relay/scripts/stop-sentinel.sh` (id:482d); every consume appends an
ISO-timestamped line to `~/.claude/logs/relay-stop-sentinel.log` (override via
`RELAY_STOP_SENTINEL_LOG`), so a delayed-consumption report has a real timeline.

**Launch-time variants** (no running pool — set a cap when you start one):

- **`/relay --once`** — dispatch exactly ONE round, then stop (`args.once`, `stopReason:
  "user-stop"`). Useful for a single supervised wave.
- **`/relay --after N`** — dispatch `N` rounds, then stop (`args.stopAfter = N`; `--once` is
  sugar for `--after 1`). A pure-JS round cap in the outer loop, independent of the sentinel.

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
  `~/.config/relay/quota-samples.jsonl`; `report [--since|--run|--json]` segments at
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
  append-only `~/.config/relay/relay-events.jsonl` records one line per
  dispatch/integrate/handback (flushed off-critical-path via `relay-state-write.sh
  event-append`) — `tail -f` it for a live event feed (the snapshot file is rewritten each
  round, so use `tail -F` there). The Claude Code statusline shows a live `🔁<round> ✓<done>
  ⚙<in-flight> Δ$<burn>/h` segment whenever `RELAY_STATUS.md` was touched in the last
  `RELAY_ACTIVE_SECS` (default 600).
- `tools/relay-gap-sample.sh` + `.service`/`.timer` (id:bf7a) — between-runs churn evidence
  logger: samples each repo's discover-sig + live classify verdict on a systemd user timer
  cadence, appending change/tick lines to `RELAY_GAP_SAMPLES` (JSONL, default under
  `~/.config/relay/`) so churn between relay-loop dispatches is captured for forensics.
  `make install-gap-sample` / `status-gap-sample` / `uninstall-gap-sample` manage the timer
  (same systemd-user pattern as `install-quota-timer`).

## State: `~/.config/relay/relay.toml`

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
| `RELAY_QUOTA_THRESHOLD_<BUCKET>` | 0–1 fraction | (general threshold) | Per-bucket override of `RELAY_QUOTA_THRESHOLD` for one cache bucket only, e.g. `RELAY_QUOTA_THRESHOLD_FIVE_HOUR=0.80` or `RELAY_QUOTA_THRESHOLD_SEVEN_DAY=0.50`. Caps a long-window bucket tighter than the 5h bucket ("use most of the 5h window but never exceed 50% of 7d"); buckets without an override keep the general threshold, so behaviour is unchanged unless set. **Nested form** (id:b841): the front door may pass `args.quotaThresholds = { SEVEN_DAY: 0.70 }` as a map; `relay-loop.js` folds each entry into the corresponding flat key (flat key wins if both present). **Note (2026-06-30):** the per-model weekly sub-limits (`seven_day_sonnet` et al.) are `null` in `/api/oauth/usage` since 2026-06-30 — they now appear in `.limits[]` as `weekly_scoped` entries (currently `is_active:false`), so a `RELAY_QUOTA_THRESHOLD_SEVEN_DAY_SONNET` override no longer binds; the consolidated `SEVEN_DAY` bucket governs the weekly cap. See memory `usage-api-per-model-weekly-null-2026-06-30`. |
| `--quota-7d <pct>` / `--quota-5h <pct>` | percent or 0–1 | (none) | id:20bd — front-door ergonomic flags for the per-bucket quota cap (the natural-language form "permit up to N% 7d usage" maps here too). `--quota-7d 45` (or `0.45`) → `args.quotaThresholds = { SEVEN_DAY: 0.45 }` (the consolidated weekly bucket; the per-model `seven_day_sonnet` sub-bucket is `null` since 2026-06-30, so there is no longer a separate Sonnet 7-day cap to set — see the note above and `usage-api-per-model-weekly-null-2026-06-30`); `--quota-5h 80` → `{ FIVE_HOUR: 0.80 }`. The front door accepts either a bare percent (`45`) or a fraction (`0.45`) and normalizes to the 0–1 fraction `relay-loop.js` expects. These ride the existing id:b841 nested-map plumbing — **an explicit per-bucket threshold WINS over the `RELAY_QUOTA_DECAY_7D` time-decay** (quota-stop.sh `bucket_threshold`), so `--quota-7d 45` is a hard 45% cap even when a rising decay schedule is set. |
| `POOL_WIDTH` | integer | `5` | Number of distinct repos dispatched in parallel (one unit per repo). Passed as `args.POOL_WIDTH`. NOTE: the Workflow harness independently caps concurrent agents at `min(16, cpu_cores-2)`, so values above that ceiling just queue — no benefit. |
| `--priority` `<repo\|repo,repo>` | repo list | (none) | **Per-run ORDERING bump only (id:d530), scoped to THIS run — NEVER writes relay.toml.** Ranks a priority repo's NATURALLY-discovered unit ahead of non-priority units **within the same verdict class** (above `income`, but below injected-unit precedence and the D3 verdict-class order — never a verdict override). Unlike `inject.sh`-as-priority, it does NOT create or inject a unit — it only reorders the repo's own discovered unit, so it can never double-dispatch a repo. An unknown/unconfirmed repo name is a **LOUD reject** (surfaced in `RELAY_STATUS.md`, never silently dropped). The front door maps the natural-language form ("priority on X") onto `args.priorityRepos`. |
| `--exclude` `<repo\|repo,repo>` | repo list | (none) | **Per-run exclusion, scoped to THIS run — NEVER writes relay.toml** (avoids the destructive `classification = own→excluded` registry mutation that survives a session-kill = silent permanent exclusion). Excluded repos are DROPPED from the own-repo list **before sharding** (no shard ever sees them, no unit is emitted); each is surfaced in `RELAY_STATUS.md` Skipped as `excluded for this run (--exclude)`. An unknown/unconfirmed repo name is a **LOUD reject** (surfaced, never silently dropped). The front door maps the natural-language form ("exclude Y") onto `args.excludeRepos`. |
| `<repo>` / `.` / `--only <repo>` | repo name | (none) | **First-class SINGLE-REPO scope (id:7633).** `/relay zkm` or `--only zkm` classifies **ONLY** that repo — the own-repo universe enumeration + 40× discover fan-out is bypassed, but the SAME per-repo path (`discover-repo.sh` reconcile→classify→route) is reused for the one repo (never forked). The repo resolves against `relay.toml` (THE canonical own set, honoring `# path:`-relocated repos — never a `~/src` glob); a name not confirmed `own` there is a **LOUD reject** (surfaced, no dispatch), not a guess. This replaces the old `--exclude`-everything-else workaround (which silently missed `# path:` repos). **Bare `/relay .` is the one exception** (2026-07-19 Amendment, supersedes id:7633 acceptance #4): it resolves to the cwd repo's basename but now means the **off-Workflow drain**, not this Workflow pool — see **Drain mode** below. See **Single-repo scope** below for the pool forms. |
| `RELAY_QUOTA_DECAY_7D` | `START:END` fractions | (unset) | Time-decaying cap for the 7-day + 7-day-Sonnet buckets: the threshold linearly interpolates from `START` at the rolling 7-day window's open to `END` at its reset (e.g. `0.30:0.90` → ~0.82 at 6/7 elapsed). **Direction matters — weekly quota is use-it-or-lose-it (unused 7-day allowance is forfeit at reset), so the cap should RISE toward reset (`START < END`): conserve early (don't blow the week on day 1), then spend down the about-to-reset budget.** A `START > END` (spend-early / back-off-late) schedule is almost always wrong — it false-stops a healthy low-utilization run right before reset (observed 2026-06-22: `0.40:0.18` stopped at 24% 7d-util with ~22 h to reset, leaving 76% to be forfeit). Recomputed each gate check from `seven_day.resets_at`. 5h bucket unaffected (it is the real short-term burst guard). Forwarded into the quota-gate via args. |
| `MAX_ROUNDS` | integer | `30` | Self-feeding-loop seatbelt: max re-discover→dispatch→drain rounds in one `relay-loop.js` invocation before it returns regardless. The loop normally ends earlier on the quota cap or two consecutive empty discoveries (backlog drained). Passed as `args.MAX_ROUNDS`. |
| `RELAY_STOP_PATH` / `--stop-path` | path | `~/.config/relay/STOP` | id:c012 — the graceful-stop **STOP sentinel** the `discover-prelude` checks each round. Content = integer "rounds remaining before stop" (empty/≤0 = stop at next round boundary; the prelude consumes+removes it on firing → `stopReason: "user-stop"`). Written by `/relay stop` (empty) / `/relay stop --after N` (N). Passed as `args.STOP_PATH`. See **Stop mode**. |
| `--once` | flag | off | id:c012 — launch-time round cap: dispatch exactly ONE round, then stop with `stopReason: "user-stop"`. Sugar for `--after 1`. Passed as `args.once = true`. |
| `--after N` | integer | (none) | id:c012 — launch-time round cap: dispatch `N` rounds, then stop with `stopReason: "user-stop"`. Pure-JS outer-loop cap, independent of the STOP sentinel. Passed as `args.stopAfter = N`. |
| `--drain` | flag | off | id:93fe Phase 1 — **single-repo off-Workflow drain, a discoverability ALIAS.** Resolves to the cwd repo (or the named/`--only` repo) and runs the lean **off-Workflow** drain via `drain-driver.mjs` (id:cd7a) — no Workflow prelude/discovery agents. **Not strictly needed: bare `/relay .` already drains** (2026-07-19 Amendment, supersedes id:7633 acceptance #4) — the driver's `isDryRound`→`drained` (K=2 no-substantive-progress rounds via the inlined `drain.mjs`, id:d58f/4ca8) and `isBlockedRound`→`blocked-pending-human` termination is the whole drain contract (meeting `2026-07-19-2035-relay-drain-parallel-contract.md`, D2/D6). `--drain` is the explicit verb for users who reach for it, or for requesting the drain on a named/`--only` repo — no separate engine. |
| `--parallel N` | integer | (none) | id:ebbe — **Phase 2 of `--drain`, NOT YET BUILT.** Would fan out N executors within a drain round (one-writer-to-main: executors→worktrees, single driver merges `--no-ff` serially; mechanical fail-closed disjoint-path greenlight — meeting D4/D5). Gated-on id:0534 (landed). Until built, the front door LOUD-surfaces "`--parallel` (id:ebbe) is not yet implemented — running single-executor drain" and proceeds as `--drain` (N=1). Route id:ebbe to `/relay handoff` to author the RED spec. |
| `DISCOVER_SHARDS` | integer | `6` | Number of parallel discovery-shard classifiers fanned out per round (id:9ed4). A once-only prelude does the global work (runId, the consuming `inject.sh take`, `claim.sh peek`, the own-repo list + non-own skipped rollup); the own repos are round-robin chunked across this many shard agents that classify in parallel, then merged into the same discovery object. Capped at the repo count; the Workflow harness's `min(16, cpu_cores-2)` agent ceiling still applies, so shards above it just queue. Passed as `args.DISCOVER_SHARDS`. |
| `RELAY_STATUS_PATH` | path | `~/.config/relay/RELAY_STATUS.md` | Where the cross-repo rollup is written (override for testing). |
| `RELAY_EVENTS_PATH` | path | `~/.config/relay/relay-events.jsonl` | Append-only event-log JSONL (id:c8b6): one line per dispatch/integrate/handback, flushed off-critical-path. Passed as `args.RELAY_EVENTS_PATH`. |
| `RELAY_QUOTA_SAMPLES` | path | `~/.config/relay/quota-samples.jsonl` | Where `relay-burn.sh` appends/reads burnup samples (id:219b). Override for testing. |
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
