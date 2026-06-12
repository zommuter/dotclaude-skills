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
/fables-turn handoff [repo-list | --all]
/fables-turn review  [repo-list | --all]
```

Default `--all` means "confirmed OWN repos, by neediness, in waves of ≤5, until quota
says stop" — resumable across turns via the state file, never all 36 at once.

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

## Guardrails

- Verification-before-merge; one push per repo per turn; never two children pushing to
  the same remote (D5/D6 discipline).
- Parallelism only across repos, or within a repo on disjoint paths.
- Pilot a handful of income-relevant repos before any `--all` run — templates and the
  executor contract will need revision after first contact with real executor sessions.
