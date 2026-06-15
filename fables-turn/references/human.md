# Human mode — cross-repo HUMAN-BACKLOG triage procedure

The relay has three actors: **execute** (Sonnet executor sessions), **review/hard**
(the strong apex model, Opus), and **human** (you). `/fables-turn human` is the
procedure for the third actor: it drains the cross-repo human-backlog — the open
`REVIEW_ME.md` judgment calls and the `@manual` scenarios a human must RUN — by
sorting each item into what the strong model can answer on its own, what is a quick
batched human yes/no, and what is genuine design judgment that belongs in a meeting.

Unlike the autonomous pool (a Workflow that NEVER prompts), human mode is an
**interactive strong-turn PROCEDURE**: the apex model drives it directly because it
uses `AskUserQuestion`, which Workflows cannot call. It mirrors how `handoff.md` and
`review.md` are reference-doc procedures the strong turn runs (optionally delegating
the read-only gather and the per-repo apply to sub-agents). **Opus is apex** — there
is no "pending Fable"; an auto-answer is Opus's final decision, re-checkable by the
next review. This generalizes the planned `review_me` mode: instead of a single repo's
queue, it sweeps every own repo's human-backlog in one turn.

## 1. Scope

Operate ONLY on `~/.config/fables-turn/relay.toml` `classification = "own"` repos
(skip `clone`/`excluded`/`needs_review`). Honor each repo's `path =` override
(the `# path:` convention) — never assume `~/src/<name>`. With no argument, scope is
all confirmed own repos; `/fables-turn human <repo-list>` narrows to the named repos;
`/fables-turn human --all` is the explicit full sweep.

## 2. Collect the backlog

Run the read-only collector (optionally inside a single Explore sub-agent):

```bash
scripts/gather-human-backlog.sh                 # all own repos
scripts/gather-human-backlog.sh repoA repoB     # named repos
```

It emits a TSV `repo  path  kind  box_summary` covering:

- every OPEN `- [ ]` box in each repo's `REVIEW_ME.md` (`kind = review_me`), AND
- open `@manual` boxes — REVIEW_ME `@manual` lines AND `ROADMAP.md` items tagged
  `@manual`/BDD that need a human to RUN them (`kind = manual`).

Closed `- [x]` boxes are never collected. The collector never spawns a model and never
writes — it is purely the read side. For each `kind = review_me` box, before deciding,
read the actual box line in context AND the code/test/spec it points at (a REVIEW_ME
entry names a `test::case` and an interpretation — open both) so your classification and
any AskUserQuestion options carry REAL per-item context, not a one-liner restated.

## 3. Three-tier classification

Sort each collected box into exactly one tier by **answerability / runnability**:

### (a) AUTO-ANSWERABLE — strong model verifies and ticks
The answer is unambiguous from the code, the tests, or the spec — the REVIEW_ME
question has one defensible resolution once you read the surrounding code. The strong
model:
- verifies the interpretation against the implementation/test it cites,
- ticks the box (`[ ]`→`[x]`) with a one-line, **re-checkable rationale** appended
  (what evidence made it unambiguous — the next review re-derives it),
- flows the resolution back to `ROADMAP.md`/`TODO.md` under the **same id**
  (single-id-two-views, D2) via the flock'd `meeting/md-merge.py` — never minting a
  duplicate token, ticking the matching ledger line so checkbox state stays consistent.

> *Example.* REVIEW_ME: `- [ ] parse.py::test_empty (roadmap:9f0a) — should an empty
> input list return [] or raise?` The handoff test already asserts `== []` and the
> ARCHITECTURE.md rationale says "empty is a valid no-op". Unambiguous → verify the
> test passes, tick with rationale "empty-as-no-op confirmed by test_empty + ARCH §2",
> tick roadmap id:9f0a.

An auto-answer is a **CLAIM the next review re-checks** (anti-gaming). It is
conservative: **when unsure whether a box is truly unambiguous, downgrade it from (a)
to (b)** and ask the human. Never weaken a test or rewrite a spec to manufacture an
auto-answer.

### (b) BATCH-DECIDABLE — quick human yes/no
A defensible answer exists but needs the human's call (a preference, a product
decision, "is this frozen behavior a bug?"). Present these in small multiple-choice
`AskUserQuestion` batches:
- **≤3–4 questions per `AskUserQuestion` call** (batch related decisions into ONE call's
  `questions` array — never separate tool calls, which render as confusing separate
  tabs).
- each option is a REAL resolution with per-item context drawn from the code you read in
  §2 — not "Option A / Option B" one-liners. Include the repo name and the cited
  test/spec so the human can decide without opening files.
- on the human's answer: tick the box with the chosen resolution noted, and flow back to
  ROADMAP/TODO under the same id (same md-merge.py path as tier (a)).

### (c) CHEWY — genuine design judgment → route OUT to `/meeting --cross`
The box is a real design decision: two plausible approaches, ambiguous scope, a
trade-off the wrong call on is hard to reverse. Do NOT answer it and do NOT force a
yes/no. Route it to a cross-project meeting:
- surface it as a `/meeting --cross` candidate (the REVIEW_ME box becomes one agenda
  item, grounded in its text + cited code, per the meeting REVIEW_ME-backlog dispatch
  shape, id:15d5),
- leave the box OPEN; note in the turn summary that it was routed to `/meeting --cross`.

## 4. `@manual` / scenario-run boxes — NEVER auto-tick

A `kind = manual` box (a `@manual` BDD scenario, a "run on device/hardware" check)
requires a HUMAN to actually RUN it — the strong model cannot observe the result.
**Never auto-tick an `@manual`/scenario-run box** (it is excluded from tier (a) by
definition). Surface every open `@manual` box as a **"you run these"** checklist in the
turn summary: repo, the scenario, and what running it proves. The human runs it between
turns and ticks it themselves (or files a follow-up if it fails). This is the same
discipline as review.md §3 (emit `@manual` checklists rather than automate them),
applied across all own repos.

## 5. Commit discipline

Clean-tree only: if a target repo's working tree is dirty, skip it and surface it in
the turn summary (never auto-snapshot). Tick + flow-back edits are committed **per-repo
in the main checkout** — the same path as the per-repo `/meeting` REVIEW_ME write-back
(D5, id:15d5), NOT a worktree merge — because these are line-scoped bookkeeping toggles,
not a roadmap re-derivation. Use the flock'd `meeting/md-merge.py` for every ledger edit
so a concurrent pool/meeting surfaces a git conflict rather than silently losing a
toggle. One commit per repo touched; do NOT push, tag, or run git-diary-workflow /
todo-update (the orchestrator/global obligation owns those).

## 6. Anti-gaming and the apex framing

- Every tier-(a) auto-answer is a re-checkable CLAIM, not a closed question — the next
  `review` turn re-derives it from the rationale and reopens it if the rationale doesn't
  hold. Write rationales the next review can actually verify.
- When unsure, **downgrade a→b** (ask the human) rather than auto-ticking. Conservative
  by construction.
- **Opus is apex.** Auto-answers are final the moment Opus makes them — never marked
  "pending Fable", never half-complete while Fable is out. Fable, if available, is only
  an optional bonus recheck (same posture as the autonomous pool's `fable-standin`).

## Return summary

End the turn with, per repo touched:
- tier-(a) boxes auto-answered (id + one-line rationale each),
- tier-(b) human decisions captured (the AskUserQuestion answers applied),
- tier-(c) boxes routed to `/meeting --cross`,
- the **"you run these"** `@manual` checklist (these stay open),
- any dirty repos skipped.

Lead the summary with what the human can now observe (closed REVIEW_ME boxes, the
manual checklist to run), not counts.
