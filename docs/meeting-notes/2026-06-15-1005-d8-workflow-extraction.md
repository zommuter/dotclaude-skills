# 2026-06-15 — D8: Workflow-extraction common-ground analysis (/meeting ↔ /fables-*)

**Started:** 2026-06-15 10:05
**Session:** 88a72bda-10b7-43d8-b74e-e6fb8ed55742
**Mode:** Analysis / design deliverable (no code touched) — the deferred D8 from
`2026-06-15-0715-meeting-fables-interaction.md`, gated on D1–D7 landing.
**Relates:** `id:6ba4` (this item), `id:7b23` (the unified-skill question).

## Why this analysis exists

D1–D7 wired `/meeting` and the `/fables-*` relay together: a shared id-token ledger
(single-id-two-views, D1/D2), a cross-ledger guard (`orphan-scan.sh --cross-ledger`),
relay-detection-gated `/meeting` behaviour (D4/D5), reverse-handoff qualification (D6),
and "C1 ≈ executor" discipline in relay-managed repos (D7). With those built there is now
*real* common ground to factor — D8 asks whether the three bodies of bookkeeping should be
**extracted** into a shared Workflow and/or a shared helper library, weighed against the
`relay-loop.js` Workflow that already exists.

The three bodies analyzed:

1. **`/meeting` end-of-meeting bookkeeping** — `meeting/SKILL.md` §End-of-meeting steps:
   orphan-scan (forward/reverse/cross-ledger), action-item mirroring to TODO.md with
   minted `id:XXXX`, `md-merge.py update-ids` close, cross-repo inbox routing via
   `append.sh -t inbox`, D5 REVIEW_ME/ROADMAP write-back, persona-state shard+collapse,
   discoveries/personas registry appends, and (at session end) git-diary-workflow +
   todo-update.
2. **Executor work-discipline** — `fables-executor/SKILL.md` (the 5 rules): scope to one
   `[ROUTINE]` item, full-suite-green definition-of-done, no test-gaming, RELAY_LOG append
   committed-in-session, commit hygiene (worktree, never push, never edit item defs).
3. **Review write-back** — `fables-turn/references/review.md`: re-derive ROADMAP, close
   genuinely-green items + tick the twinned TODO line (D2), reverse-handoff qualification
   (§5b), cross-repo inbox routing, REVIEW_ME `@manual` checklist emission, `routine_open`
   report. Integration (merge → `ckpt-tag.sh` → `git-lock-push.sh --ff-only`) is the
   **orchestrator's** job, not the child's.

## Shared primitives (the map)

Walking the three bodies against the actual scripts, the *mechanically shared* primitives
are a short list — and all already exist as standalone, flock'd, single-responsibility
helpers that both surfaces call by path:

| Primitive | Script (canonical) | /meeting | executor | review |
|---|---|---|---|---|
| id-token mint | `meeting/append.sh new-id[s]` | ✓ (mirror step 2b) | — (uses pre-allocated) | ✓ (new work only) |
| id-token scan/correlate | `meeting/orphan-scan.sh` (`--reverse`, `--cross-ledger`) | ✓ (setup) | — | indirectly (guard) |
| flock'd checkbox/line write | `meeting/md-merge.py update-ids` | ✓ (close + D5 write-back) | — (ticks via plain edit) | ✓ (twin-tick TODO) |
| flock'd section write | `meeting/md-merge.py update-sections` | ✓ (user-profile) | — | — |
| append-only union log | `RELAY_LOG.md` (`merge=union`) + `ckpt-tag.sh` | — | ✓ (rule 4, hand-append) | ✓ (via ckpt-tag, orchestrator) |
| registry append | `meeting/append.sh -t {discoveries,personas,inbox}` | ✓ | — | ✓ (inbox only) |
| cross-repo routing | `append.sh -t inbox` | ✓ | — | ✓ |
| worktree-per-session | git worktree + `relay/<id>` branch | — (main tree) | ✓ | ✓ |
| flock'd serialized merge | `git-lock-push.sh` / relay serialized integrator | ✓ (at session end) | — (never pushes) | — (orchestrator) |
| checkpoint tag | `ckpt-tag.sh` (`fable-ckpt-*`) | — | — | orchestrator only |

The crucial observation: **the primitives are already extracted.** `append.sh`,
`md-merge.py`, `orphan-scan.sh`, `ckpt-tag.sh`, `git-lock-push.sh` are each a single-file,
flock-guarded, short-stdout helper that any caller invokes by absolute path. There is no
copy-pasted bookkeeping *logic* duplicated between the SKILL.md files — what is duplicated
is the **prose instruction telling an agent which helper to call, in which order, with which
invariant**. That distinction drives the whole recommendation.

## Genuinely common vs superficially-similar-but-different

### Genuinely common (one substance, three callers)

- **The single-id-two-views invariant (D1/D2).** "An `id:XXXX` in both TODO and ROADMAP
  must have agreeing checkbox state; reuse the token, never mint a duplicate." This *exact*
  sentence is now restated in four places: `handoff.md` C2, `review.md` §5, the
  `relay-loop.js` review-unit prompt, and `meeting/SKILL.md` step 2e. The guard
  (`orphan-scan.sh --cross-ledger`) is one script; the *contract text* is fan-copied. This
  is the one piece of genuinely-common substance that is **duplicated as prose** and is a
  real extraction candidate (see Recommendation, `id:962a`).
- **The flock'd ledger-write pattern.** "To close/toggle an id-bearing line, go through
  `md-merge.py update-ids`, never a raw Edit (concurrent-session clobber)." Stated in
  `meeting/SKILL.md` 2b/2e and `todo-update/SKILL.md` step 3. Same helper, same rationale.
- **Cross-repo routing.** Both `/meeting` (step 2b sub-step) and `review.md` §5 route a
  follow-up that belongs to a different repo to `append.sh -t inbox`, never to the other
  repo's TODO.md. Identical rule, identical helper.
- **Append-only self-report.** Executor RELAY_LOG (rule 4) and `/meeting` diary entry are
  the same *shape* — a committed-in-session append to a `merge=union` append-only log that
  the next session/turn reads as the "what happened" record.

### Superficially similar but genuinely different (do NOT merge)

- **Interactivity.** `/meeting` is fundamentally an `AskUserQuestion`-driven interactive
  session — git-hygiene prompt (step 2b), decision points, profile/memory classification
  (steps 3–4), persona registry (step 5). The relay Workflow is **unattended by hard
  invariant** (`relay-loop.js` is grepped by a test to ensure it never calls a question
  tool; `INTERACTIVE` only routes choices into RELAY_STATUS.md, never a prompt). A Workflow
  **cannot prompt**. This is the single biggest "looks shared, is not" trap.
- **Worktree vs main-tree.** Executor/review children work in an isolated
  `~/.cache/fables-turn/worktrees/...` worktree, never push, and hand the branch to a
  serialized integrator. `/meeting` edits the *main* working tree and runs git-diary-workflow
  itself at session end (per D7's explicit carve-out: "a direct `/meeting` session still
  pushes + runs git-diary-workflow"). Same git verbs, opposite ownership model.
- **Test-integrity audit.** Review's trust-but-verify (`review.md` §2: deleted/weakened/
  resurrection/fixture/green-guard/unverified checks) is *strong-model judgment work* with
  no `/meeting` analogue. The D5 carve-out is explicit: `/meeting` does **bookkeeping only**,
  never re-derives the roadmap or runs the integrity audit. Not common; deliberately
  partitioned.
- **Checkpoint tagging + serialized integration.** `ckpt-tag.sh` + the relay's promise-chain
  integrator are an *orchestrator* concern for unattended multi-repo waves. `/meeting` has a
  single tree, a single session, and `git-lock-push.sh` already serializes its push. No
  shared need.
- **Persona-state + memory classification.** Entirely `/meeting`-specific
  (`persona-state.py` shard/collapse, discoveries/profile). No relay analogue and no reason
  to invent one.

## Should /meeting's bookkeeping become a Workflow? — decisive answer: NO

A Workflow (the `relay-loop.js` shape) buys three things: deterministic JS control flow,
schema-validated agent returns, and an unattended self-feeding loop. `/meeting`'s
end-of-meeting bookkeeping needs **none** of those and is **disqualified** by one hard
constraint:

1. **Workflows cannot prompt; `/meeting` is constitutively interactive.** Steps 2b, 3, 4,
   5 are all `AskUserQuestion` decision points by design. The relay went out of its way to
   *forbid* prompting (the front-door test greps `relay-loop.js` for any question tool). You
   cannot host an interactive flow in an engine whose defining invariant is "never prompt."
   Routing those decisions into a status file is exactly the wrong move for a human-in-the-
   loop meeting.
2. **No determinism win.** The bookkeeping is already deterministic *at the helper layer* —
   `md-merge.py` does the atomic flock'd write, `append.sh` mints collision-free tokens,
   `orphan-scan.sh` correlates. The SKILL.md prose is the orchestration, and a Workflow would
   just re-encode that prose as JS — adding a build artifact, a schema layer, and a second
   place to keep the contract in sync, for zero new safety the helpers don't already give.
3. **Worktree-awareness is a non-goal for /meeting.** D7 deliberately kept `/meeting` on the
   main tree with its own git-diary-workflow. Wrapping it in a worktree-aware Workflow would
   *contradict* a decision made three hours earlier in the same design line.

So: **do not extract `/meeting` bookkeeping into a Workflow.** The Workflow engine is the
right tool for the unattended, multi-repo, parallel, schema-validated relay pool — and a
poor tool for a single-tree interactive session. They are different shapes and should stay
different shapes.

## What TO extract — and what to leave duplicated

**Extract (small, prose-level, no engine):**

- **The shared-invariant contract text into one canonical doc that all four callers cite by
  reference** instead of restating. `conventions.md` already plays exactly this role for the
  executor contract (the "thin versioned pointer" pattern — handoff/review embed a pointer,
  the substance lives once in `fables-executor/SKILL.md`). Apply the *same* pattern to the
  single-id-two-views + flock'd-ledger-write + cross-repo-routing invariants: write them once
  (a "ledger discipline" reference section), and have `handoff.md` C2, `review.md` §5,
  `relay-loop.js`'s review prompt, `meeting/SKILL.md` 2b/2e, and `todo-update/SKILL.md`
  step 3 each carry a one-line pointer. This kills the fan-copy drift risk (the same class of
  drift the contract-pointer `vN` marker already guards against) without any new engine.
  → `id:962a`.

**Leave duplicated (intentional, cheap, divergent):**

- **The git verbs.** worktree-create / commit / push-via-lock are a handful of lines each and
  are *deliberately different* between worktree-child and main-tree-meeting. A shared
  "git helper library" would have to branch on ownership model immediately — more complexity
  than the duplication it removes. Leave them inline.
- **Test-integrity, checkpoint-tag, persona-state, memory classification.** Single-owner by
  design; no second caller; nothing to share.

**Optional, low-priority convenience helper (NOT a library):**

- A single thin wrapper `ledger-close.sh <file> <id> <line>` that is just
  `md-merge.py update-ids` with the JSON heredoc pre-built, so callers stop hand-writing the
  heredoc in three SKILL.md files. This is a *typing-convenience* extraction, not an
  architectural one — it removes the most error-prone copy-paste (the heredoc) while leaving
  the flock'd substance exactly where it is. Worth doing only if the contract-text extraction
  (`id:962a`) shows the heredoc is the residual drift source. → `id:3103` (gated; build only
  if 962a's audit finds heredoc drift).

## Connection to id:7b23 (unified /meeting + /fables-* skill)

This analysis argues **against** unifying the surfaces, and refines *why*:

- The two surfaces share **primitives** (already extracted as standalone helpers) but have
  **opposite execution models**: interactive-single-tree-self-pushing (`/meeting`) vs
  unattended-worktree-orchestrated-never-push (relay). A unified skill would have to carry a
  mode switch that gates literally every step on "am I prompting or not / am I in a worktree
  or not" — which is just the two skills with a shared preamble, at the cost of one giant
  conditional document.
- The *correct* unification is the one this note recommends: unify the **contract text**, not
  the **skills**. That is the `conventions.md` pointer pattern already in production. It gives
  the "single source of truth" benefit people reach for when they say "unify" without forcing
  two divergent execution models into one entry point.
- `id:7b23` should be resolved as: **keep the split skills; consolidate the shared ledger
  invariants into one cited reference (`id:962a`).** The `/batch`-vs-relay half of `id:7b23`
  is orthogonal to this and stays open under its own trigger.

## Recommendation (3–5 sentences)

Do **not** extract `/meeting`'s bookkeeping into a Workflow: Workflows cannot prompt, and
`/meeting` is constitutively interactive (`AskUserQuestion` at every decision point), so the
`relay-loop.js` engine is the right tool only for the unattended multi-repo relay pool and the
wrong tool here. The bookkeeping *primitives* are already correctly extracted as standalone
flock'd helpers (`append.sh`, `md-merge.py`, `orphan-scan.sh`, `ckpt-tag.sh`,
`git-lock-push.sh`) — there is no duplicated *logic* to factor, only duplicated *contract
prose*. The one genuine extraction is to move the single-id-two-views / flock'd-ledger-write /
cross-repo-routing invariants into a single cited reference (mirroring the existing
`conventions.md` thin-pointer pattern for the executor contract), so the four current copies
become one source plus pointers (`id:962a`). Leave the git verbs, the test-integrity audit,
checkpoint tagging, and persona/memory steps duplicated or single-owner — they are
deliberately divergent or have no second caller. This also resolves `id:7b23`: keep the split
skills, unify the *contract text* rather than the *surfaces*.

## Proposed build items (ledger-neutral, acceptance-shaped)

- [ ] **Ledger-discipline shared reference + pointers** — write the single-id-two-views (D1/D2),
  flock'd-ledger-write (`md-merge.py update-ids`), and cross-repo-routing (`append.sh -t inbox`)
  invariants ONCE in a canonical reference section (extend `fables-turn/references/conventions.md`
  or a sibling `ledger-discipline.md`), and replace the restated copies in `handoff.md` C2,
  `review.md` §5, the `relay-loop.js` review-unit prompt, `meeting/SKILL.md` steps 2b/2e, and
  `todo-update/SKILL.md` step 3 with a one-line pointer to it (same thin-pointer pattern as the
  executor-contract pointer in `conventions.md`). Acceptance: the three invariants appear in full
  prose in exactly one file; the five call sites each cite it by path; `grep` for the
  single-id-two-views sentence returns one substantive hit + pointer lines; no behaviour change in
  any skill (pure doc-dedup). Relates `id:7b23`. <!-- id:962a -->

- [ ] **(Gated) `ledger-close.sh` heredoc-convenience wrapper** — only if `id:962a`'s
  consolidation audit shows the `md-merge.py update-ids` JSON heredoc is the residual copy-paste
  drift source: add a thin `meeting/ledger-close.sh <file> <id> "<replacement-line>"` wrapper that
  builds the JSON and calls `md-merge.py update-ids` under its existing flock, and point the
  SKILL.md close-steps at it. Acceptance: callers no longer hand-write the heredoc; flock'd
  substance unchanged (delegates to `md-merge.py`); allowlist entries generated; tests cover a
  concurrent two-id close. Build-gated on `id:962a` finding heredoc drift — skip if consolidation
  alone removes it. <!-- id:3103 -->
