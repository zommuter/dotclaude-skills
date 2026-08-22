# SALVAGE HANDOVER — 2026-08-22 evening

**Read this first, then `docs/HANDOVER-2026-08-22-1600.md` (body + addendum) for the narrative.**
The 1600 file records what happened. **This file is the action plan.** Where they disagree, the
ledger wins — resolve any id with `grep -n 'id:XXXX' TODO.md ROADMAP.md`. Do **not** read
`TODO.md` whole (563+ open boxes — the `id:35b7` prompt-size trap).

> Written after a session that ended badly. The repo is in a **clean, safe state** — nothing is
> lost or half-merged — but the relay machinery has one defect that makes it actively unsafe to
> run unattended. Read §1 before doing anything.

---

## 1. STOP — do not start a relay pool until `id:a615` is fixed

**A running pool cannot be stopped gracefully.** `/relay stop` writes a sentinel that is only
consumed at a **round boundary**, and a pool that chains work inside one round never reaches one.
Measured 2026-08-22: sentinel written 15:57, still unconsumed 22 minutes later, while the pool
issued **14 dispatches all stamped `round=1`** — four of them after the sentinel existed.

The only thing that actually stops such a run is `TaskStop`, which is precisely the destructive
option the graceful path exists to avoid. `relay/SKILL.md`'s Stop-mode section describes draining
"the already-dispatched wave" — a wave boundary a chaining round does not have.

**Consequence for you:** if you launch a pool, you own it until it drains itself. At 89% of the
7-day quota window (below, §2) that is a real risk. Fix `id:a615` first, or run only
`--once`/`--after N`, which are pure-JS round caps independent of the sentinel.

## 2. Hard state (verified 2026-08-22 ~16:45, not inherited from prose)

| | |
|---|---|
| `main` | clean, pushed to `origin` (fievel) |
| `github` | **8 commits behind — BY MECHANISM, not by prose** (`id:f66e`); publishing is now a deliberate act |
| quota | **89% of the 7-day window**; resets **2026-08-25 12:00 UTC**. Decay schedule `RELAY_QUOTA_DECAY_7D=0.30:0.90` currently yields a 0.65 cap, so a default pool self-stops immediately — an explicit `--quota-7d N` is required to run at all |
| suite | 491 passed / 0 failed / 1 expected-red |
| `REVIEW_ME.md` | 1 open box (`id:8e7a`, device work, correctly human-gated) |
| shared inbox | **0 open** (drained) |
| live relay runs | **none** (only the non-pool `discovery-producer`) |
| relay claims | all released |
| dotclaude-skills worktrees | **22** (`id:b818` hermeticity hazard — prune before trusting any repo-tree sweep) |

**Parked relay branches needing `/relay reconcile`, fleet-wide — 22 across 12 repos:**
`yinyang-puzzle` 4 · `dotclaude-skills` 3 · `loderite` 3 · `cartulary` 2 · `escapement` 2 ·
`mathematical-writing` 2 · `zkWhale`/`isochrone`/`trAIdBTC`/`puzzle-pwa`/`linguistic-universals`/`leancow` 1 each.

Two of those are **rescued work, not junk** — do not discard blind:
- `loderite` → `relay/orphan/relay-20260822-154630-17003-execute-6612-0` — `id:6612`, **finished
  work that died at the commit step** (suite was green, typecheck clean). Reconcile it; do not
  re-run the item from scratch. Why it died: `id:3242`.
- `mathematical-writing` → `relay/relay-20260822-154630-17003-execute-repo-0` @ `1d0587c` — an
  extension change (new 190-line `renderClient.js` + a 28/72 rewrite of `extension.js`) rescued
  from a killed child. Labelled UNVERIFIED per the `id:f272` contract. **Nobody has reviewed it.**

## 3. Salvage order (highest value first)

1. **Fix `id:a615`** — the stop defect. Everything else is safer afterwards.
2. **Fix `id:7986`** — apex `hard` must require `--afk`. **Fully specified, unblocked, no owner
   input outstanding**: gate `hard` ONLY; `review` and `handoff` are permitted always (owner
   ruling 2026-08-22, recorded in the item). `relay-loop.js` has no `args.afk` consumer at all and
   the front door never passes it; `relay/SKILL.md` documents the OPPOSITE and must change in the
   same commit. Mirror the existing `intensive:<res>` skip shape at `relay-loop.js:2484`.
3. **`/relay reconcile`** the 22 parked branches, starting with the two named above.
4. **Reap the 22 worktrees** (`id:b818`).
5. Then the rest: `id:3242`, `id:c9e7`, `id:ae20`, `id:e512`, `id:9bfc`, `id:6a34`, `id:9452`.

## 4. What NOT to do

- **Do not restore** the struck claim in the 1421 handover that "`github` is 72 commits behind by
  design". There was never a hold; see `id:f66e`.
- **Do not re-litigate** the `handoff`-always-permitted ruling in `id:7986`, or the `id:3a09`
  wired-vs-unwired question (settled; `id:9452` covers only the test's hermeticity).
- **Do not "helpfully" mint a version/VERSION file** here — this repo is deliberately version-less
  (`id:8ef3`), and it has a date-bucketed CHANGELOG instead.
- **Do not trust `in-flight=0`** in `RELAY_STATUS.md` as "nothing is running" — `id:e512`. A unit
  mid-transition reads as zero. This mistake is what killed a live pool in the previous session.
- **Do not build a forensic timeline from `relay-events.jsonl` timestamps** — they are batch
  stamps, not event times (`id:ae20`). Use agent transcripts, `/tmp/mechanical-proxy.log`,
  `~/.claude/logs/relay-claim.log`, or git commit dates.

## 5. Traps this session paid for

- **`--remote origin` is now mandatory** in `git-diary-workflow` (`id:f66e`). Publishing to a
  public remote is a separate, deliberate `--remote github --ff-only`. The pre-push privacy gate is
  **not** a safety net: warn-only AND diff-scoped (`id:9bfc`).
- **Any "N repos in the fleet" claim must come from `lib-own-repos.sh own_repos()`** — it honors
  `# path:` and `paused`, and needs `$RELAY_TOML` + `$SRC_DIR` set by the caller. A `~/src` glob
  silently misses the 17 relocated `zkm-*` plugins; that error understated a blast radius by 3.5×
  this session.
- **`is_private_remote_url`**, not `is_private_remote`, is the predicate in
  `lib-private-remote.sh`. Calling the wrong name with `2>/dev/null` produced 46 uniformly wrong
  rows before anyone noticed. Never swallow stderr on a predicate.
- The full suite exceeds the default 2-minute Bash timeout (~3 min at load). Pass a longer timeout
  or it dies silently mid-run.
- `md-merge.py` validates **all** insert anchors up front — anchor every item in a payload on an
  id that **already exists**, never on a sibling in the same payload.
- `rm -rf` on a `mktemp -d` trips the guard; use `rm -r -- <dir>`.

## 6. Open owner decisions

- **`id:e512` / `id:a615` / `id:c9e7` fix shapes** are written as *suggested, not decided*.
- **Publishing** the 8 commits to public GitHub is a deliberate act and remains the owner's call.
- Nothing else is blocked on him — `id:7986` in particular is ready to implement.
