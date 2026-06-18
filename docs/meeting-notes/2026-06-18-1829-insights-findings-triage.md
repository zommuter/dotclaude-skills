# 2026-06-18 — Distilling the 2026-06-18 /insights findings

**Started:** 2026-06-18 18:29
**Session:** 298ffff4-40a7-4d68-a4ca-5fd27e49238e
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity)
**Topic:** Triage the 5 friction clusters + horizon ideas from the 2026-06-18 `/insights` report (770 sessions, 173 analyzed, 2026-05-05→2026-06-18) into per-finding verdicts: adopt / global CLAUDE.md rule / new TODO id / drop.

## Surfaced context (orphan-scan advisories, tangential to topic)
- Cross-ledger drift: id:2425, id:10c0, id:aa93, id:b841 — TODO `[ ]` but ROADMAP `[x]`. Not this meeting's job; flag for next `/todo-update` or `/relay review`.
- Reverse-orphan candidates are all in-session-completed relay notes; no action.

## Grounding checks (done before agenda — report itself flags "acting before context loaded")
- **(a) pre-flight orchestration:** CONFIRMED unimplemented. `claim.sh` guards *per-repo* work (relay-loop.js:621-625) but there is NO pool-level singleton guard — relay-loop.js:542 explicitly assumes concurrent pools can coexist. No shared dep cache: children do bare `git worktree add` (relay-loop.js:878), no `--store-dir`/XDG wiring. Tracked only as raw material + wishlist id:e79b (which only proposes per-worktree `pnpm install`, not a shared store).
- **(b) verify-before-assert:** No explicit accuracy rule in global `~/.claude/CLAUDE.md` (confirmed absent).
- **(c) sibling-project resolution:** No resolution convention exists. NB: report conflated `zomni` (a machine, CLAUDE.md Machines section) with a project dir. `relay-repo-path-resolution` memory covers zkm-* plugin paths only.
- **(d) output-to-file:** No such rule anywhere.
- **sudo finding (report extra):** ALREADY covered by global CLAUDE.md "Sudo and authentication" + never-sudo-pamac. → no action.
- **pre-commit hook:** No PreToolUse / pre-commit hook exists; hooks/ has only Stop/Notification/SessionStart.

## Agenda
1. Which findings warrant a durable **global CLAUDE.md rule** vs. a lighter form vs. drop? Cluster: (b) verify-before-assert, (d) output-to-file, (c) sibling-resolution.
2. (a) Pre-flight orchestration: duplicate-pool guard + shared dep cache — build / fold / logger-first / drop.
3. Report's remaining suggestions: pre-commit staging hook; Task-Agents-for-classification nudge.
4. (e) Horizon ideas (self-healing fleet, TDD feature factory, nightly sweeper).

## Discussion

### Item 1 — CLAUDE.md rule candidates (the always-loaded-ctx cluster)

🏗️ **Archie:** Three findings all resolve to "add a line to global CLAUDE.md". (b) had the most incidents — "fails to render", "already merged", cherry-pick-instead-of-merge — the report's #1 correctness friction (8× "Wrong Approach"). (d) is flagged as "your single most common hard failure mode" (output-token-limit). (c) is lowest-incidence.

✂️ **Petra:** Stop. Every line in `~/.claude/CLAUDE.md` loads into *every* prompt of *every* project — the "Per-prompt ctx multipliers" heuristic demands a ctx-budget review before adding always-loaded text. Three rules off one report is the multiplier trap. Which actually earn permanent residence?

😈 **Riku:** A CLAUDE.md rule is a behavioural nudge backed by 173 analyzed sessions, not speculation — the bar is "worth the per-prompt tokens". Per finding: **(b)** highest value, gap is specifically *factual claims about file/git state asserted without running the check*; a tight one-liner is high-leverage; adopt. **(d)** real and unrecoverable, but trigger is narrow (500-tok cap, unusual config) — permanent global rule for a config-specific failure is mistargeted. **(c)** lowest incidence, and the report's example was wrong (zomni is a machine) — one line, but is it global or local?

✂️ **Petra:** My cut: (b) clearly earns *global* status. (c) pairs naturally with the "Machines" section as a one-liner — cheap, accept. (d) I'd resist as global — config-specific; its home is the relay/long-output context, not the universal preamble.

🏗️ **Archie:** One nuance on (b): CLAUDE.md is *curated — owner ratifies exact wording* (the whole shape of id:6ac6). So the verdict is "adopt, owner ratifies text", not "I write final prose unilaterally." And (b)+id:6ac6 are siblings under "Reporting work" — they can land as one curated edit.

### Item 2 — Pre-flight orchestration: duplicate-pool guard + shared dep cache

🏗️ **Archie:** Two distinct sub-problems. **(a1)** relay-loop.js:542 generates a per-run `runId` and *assumes* concurrent pools can coexist; `claim.sh` guards per-repo so two pools won't double-work the same repo, but nothing stops a second front-door from competing for the remainder. Guard = a `pool:` claim at the front door before the Workflow launch. **(a2)** children do bare `git worktree add` (relay-loop.js:878) with no dep provisioning; the ~256MB VS Code re-download is ad-hoc. id:e79b proposes relay-worktree.sh but only per-worktree `pnpm install`, not a shared store.

😈 **Riku:** (a1) real but n=1, and per-repo claim already prevents the corrupting failure. Minimum guard: a front-door `pool:` claim via *existing* `claim.sh` (id:ebfb) — compose, don't build new machinery. But caution: a hard pool-singleton lock collides with legitimate multi-clauding (54 overlap events, 16% of messages). The guard must refuse only a duplicate *autonomous no-arg pool*, never a directed `/relay <args>` front session. A `pool:autonomous` key respecting claim.sh liveness does that.

✂️ **Petra:** (a2) is already half-tracked by id:e79b — fold the shared-cache requirement in rather than mint a parallel item (N=2 rule). For a1, logger-first? No — mechanism is cheap (reuse claim.sh), harm concrete, guard non-destructive (refuse + name holder). Observe-first is for expensive or risky prevention; this is neither.

### Item 3 — Pre-commit hook, Task-Agents nudge

😈 **Riku:** A `git status` PreToolUse hook doesn't *prevent* anything — it prints into the tool stream; I'd still have to act on it. The failure (pathspec typo) is n=1, and the diary workflow commits after *every* prompt — constant per-commit noise for a one-time error. The report's report itself suggested a smarter guard; that could be a new TODO.

✂️ **Petra:** Task-Agents nudge is "you already do this" — the user dispatches parallel agents heavily. No gap. Drop.

### Item 4 — Horizon ideas

😈 **Riku:** Aspirational re-descriptions of work already being built incrementally — self-healing fleet = a1+a2+atomic ledgers; nightly sweeper = `/relay --all` + autonomous pool + cron; TDD factory = relay contract scaled. None is a discrete decision.

✂️ **Petra:** Don't mint vague umbrella TODOs. One non-actionable ROADMAP direction line so the vision isn't re-litigated; the concrete ids carry the increments.

## Decisions

- **(b) verify-before-assert → ADOPT** a curated global `~/.claude/CLAUDE.md` rule (conclusions about code/git/file state only after running the proving command), landed under "Reporting work" in the **same curated edit as id:6ac6**. Owner ratifies exact wording. Out of scope: harness-level "care" prose. <!-- id:f082 -->
- **(c) sibling-resolution → ADOPT** a one-liner near the "Machines" section ("Projects live under ~/src/; resolve bare names there before asking"). Owner ratifies. Out of scope: a richer programmatic resolver. <!-- id:35fe -->
- **(d) output-to-file → NEW TODO** for an output-style doc / relay-context note, NOT a global always-loaded rule (trigger is the narrow 500-tok capped config). Re-open-to-global trigger: recurrence outside capped sessions. <!-- id:ef77 -->
- **(a1) duplicate-pool guard → NEW TODO**, claim.sh-based: front-door `pool:autonomous` claim before the no-arg Workflow launch; refuse only a 2nd autonomous pool (peek names holder); directed/scoped/`--afk` runs EXEMPT. Out of scope: blocking any directed/parallel run; new lockfile machinery. <!-- id:11c6 -->
- **(a2) shared dep cache → FOLD INTO id:e79b** — upgrade its relay-worktree.sh spec from per-worktree `pnpm install` to a shared store-dir / XDG cache. No new id (N=2 rule).
- **pre-commit staging → NEW TODO** for a *blocking* guard (dropped-file/pathspec). Report's bare `git status` hook rejected (per-commit cost, no prevention). <!-- id:b67e -->
- **Task-Agents nudge → DROP** (no gap; user already dispatches parallel agents).
- **Horizon ideas (e) → one ROADMAP direction line**, no umbrella TODOs.
- **sudo finding (report extra) → already covered** by global CLAUDE.md; no action.
- **id:f1a7 → CLOSED** (this meeting is its resolution).

## Action items
- [ ] Curated `~/.claude/CLAUDE.md` edit: add verify-before-assert rule under "Reporting work", bundled with id:6ac6 no-clickbait rule; owner ratifies wording before landing. <!-- id:f082 -->
- [ ] Curated `~/.claude/CLAUDE.md` edit: one-liner near "Machines" section — bare project names resolve against ~/src/ before asking; owner ratifies. <!-- id:35fe -->
- [ ] NEW TODO: output-to-file discipline as an output-style doc / relay-long-output note; re-open-to-global if it recurs outside capped configs. <!-- id:ef77 -->
- [ ] NEW TODO: relay front-door `pool:autonomous` claim via claim.sh; refuse only a 2nd no-arg autonomous pool; directed/scoped/--afk exempt; touches relay/SKILL.md + claim.sh; relates id:1968. <!-- id:11c6 -->
- [ ] NEW TODO: pre-commit guard that actually blocks a dropped-file/pathspec commit (not a bare status print). <!-- id:b67e -->
- [ ] Update id:e79b: fold shared store-dir / XDG dep-cache requirement into the relay-worktree.sh spec.
- [ ] Add one non-actionable "direction" line to ROADMAP.md for the horizon vision, referencing concrete ids.
