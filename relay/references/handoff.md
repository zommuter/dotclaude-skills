# Handoff mode — per-repo child procedure

A handoff child runs inside its own worktree for ONE repo and prepares that repo
for executor sessions: docs, an executor-facing roadmap, failing tests as the spec,
and BDD scenarios. Work proceeds as ordered commit checkpoints so an abrupt quota
cutoff loses the least (docs and red tests are worth more half-done than nice-to-haves).

Read `references/conventions.md` first — its environment facts are inputs to C1.
The executor contract now lives at `relay/references/executor-contract.md` (loaded by
`/relay executor`); C1 writes the thin versioned pointer (see §Executor-contract
pointer in conventions.md), not the full block.

## Inputs the orchestrator provides

- Repo name, worktree path, and base ref (fresh from origin's default branch).
- A batch of pre-allocated `id:XXXX` tokens (from `append.sh new-ids N <repo-root>`).
- Whether C5 (HARD execution) is budgeted this turn.

## Checkpoints

Commit after each checkpoint with the stated message prefix so the orchestrator can
verify ordering from the returned commit list. Never push.

**C1 — docs.** Read the repo fully; note quirks and implicit conventions. Write or
refresh `CLAUDE.md` (commands, conventions, deploy, gotchas — nothing implicit; write
the thin relay pointer as `## Relay contract <!-- relay-executor contract vN -->` —
vN = the canonical version in `relay/references/executor-contract.md` — with
the two-line body from conventions.md §Executor-contract pointer). Write
`ARCHITECTURE.md` (decisions WITH rationale and rejected alternatives). Refresh
`README.md` if present and stale (feature/usage tables, install instructions) —
user-facing docs are part of the docs checkpoint, not an afterthought (review
step 4 audits them as drift surface from then on). Commit
`relay(handoff): C1 docs`.

**C2 — roadmap.** C2's FIRST check is the open `TODO.md` backlog, **not** the
ROADMAP open-count: **"ROADMAP closed" ≠ "nothing to hand off"** (id:2dea, the
2026-06-25 truncocraft miss — a fully-`[x]` ROADMAP hid five open TODO items and the
repo read as "drained" for days). First, make the backlog WELL-FORMED so none of it hides: run
`relay/scripts/todo-conformance.sh --fix <repo>/TODO.md` (id:3441) — it mints+appends an id
onto every well-formed open item missing one (`missing-id`) and SURFACES (never rewrites)
any `orphan` line; resolve those by hand before promoting. **A handed-off `TODO.md` is
ITEMS-ONLY — no prose** (user directive 2026-06-25): it carries headers (`## Current` /
`## Done`), well-formed `- [ ]/[x] … <!-- id -->` items, and `## [LANE] Title <!-- id -->`
heading-as-items with their `- [ ] Open`/`- [x] Done` status sub-lines — nothing else.
Relocate every `orphan` prose line to its proper home: design rationale/intros →
`docs/` or `ARCHITECTURE.md`; relay handoff/review log paragraphs → `RELAY_LOG.md`;
a real task hiding in prose → a proper `- [ ]` item (reuse/mint its id); genuine cruft →
delete. `<!-- lint-ok: <reason> -->` is reserved for a deliberate non-item marker (e.g. a
cross-repo `<!-- ref:XXXX -->` pointer), NOT a license to keep prose in TODO.md. **Resolve
each finding by the owner-approved policies in `references/todo-conversion-policies.md`**
(P1 non-canonical ids / P2 stale-dup / P3 relocate-by-type / P4 status-as-task; flag genuine
task/identity ambiguity to REVIEW_ME, never guess). NEVER block on this — auto-fix what is
safe, relocate/surface the rest. Then run
`relay/scripts/unpromoted-scan.sh <repo>` to list
every open TODO id with no ROADMAP twin **regardless of lane tag** (the gap that bit
truncocraft: its items were untagged, so the lane-gated `orphan-scan.sh --promotion`
missed them). `promote`-disposition items get sized into ROADMAP here; `surface` ones
get lane-triaged below — never auto-promote an untagged item with a guessed lane.

Write `ROADMAP.md` from the template: items sized for one Sonnet
session, each self-contained with acceptance criteria and an explicit done-check
command. Tag each `[ROUTINE]` (executor) or `[HARD — strong model]`. Assign one
`id:XXXX` per item — **single-id-two-views (D2): if a roadmap item promotes work the
repo's `TODO.md` already tracks under an `<!-- id:XXXX -->`, REUSE that token; mint a
fresh pre-allocated token ONLY for newly-discovered work.** TODO/meeting is the design
ledger ("why"); ROADMAP is the execution queue ("now") — the same token spanning both
is the intended shape, and lets `orphan-scan.sh --cross-ledger` keep their checkbox
states consistent. Minting a duplicate id for already-tracked work is the anti-pattern
the guard exists to catch. **Unqualified TODO items** (added by `/meeting` or manual
edits with no `[ROUTINE]`/`[HARD]` tag and no acceptance/tests) are prime promotion
candidates — size and tag execution-ready ones into ROADMAP here (reuse their id), and
leave genuinely design-judgment ones as TODO/`/meeting` candidates (same triage as
review §5b). Add/refresh the single TODO.md summary line. Commit
`relay(handoff): C2 roadmap`.

**Author-then-run split for scriptable `[HARD — hands]` items (id:e175, meeting 2026-06-30).**
A hands item is often *(an authorable artifact) + (a thin on-device run)* — e.g. write a
systemd `.service`/`.path`/`.timer` (in-repo, authorable) then `systemctl --user` enable
+ observe it fire (on-device). When the authoring half is genuinely buildable in a
worktree, **split it into two existing-lane items, do NOT leave the whole thing `hands`:**
a `[HARD — pool]` "author script/config X" item the `--afk` pool builds unattended (the
`hard` verdict, id:da26), plus a `[HARD — hands]` "run X on device" item gated `(DEP:
<author-id>)`. Reuse the parent's id for one half and mint one fresh id for the other; keep
them DEP-linked so the dependency is explicit. **The split is authoring JUDGMENT, not a
mechanical transform** — only split when the author half is really worktree-buildable
(counter-example: an item whose only steps are an *outside-the-repo* config edit + an
`ssh <host> chmod` is wholly hands — both halves are unreachable from a worktree). Relay
NEVER auto-executes the device/sudo run; `/relay human` only PRINTS the command (see
human.md §4). A detector that merely FLAGS splittable candidates is deferred (observe-first).

**C3 — spec-as-tests.** For every `[ROUTINE]` item, write the FAILING tests now and
verify each is actually red (run them). Map each test to its item with a
`# roadmap:XXXX` comment. The suite is the spec — an executor is done when it goes
green plus a refactor pass, nothing else. Commit `relay(handoff): C3 red tests`.

Two real-world C3 cases the strict "red = spec" rule doesn't cover (meeting
`docs/meeting-notes/2026-06-13-1751-handoff-review-me-wave.md`, D1/D2):

- **Already-built behavior → labeled regression-guard (not a red spec).** When the
  feature already exists and a faithful test passes on arrival, do NOT delete working
  code to manufacture a red. Ship it as a GREEN regression-guard — mark it as such in
  the test header (e.g. `# regression-guard (passes today): roadmap:XXXX`) and file a
  REVIEW_ME entry asking **"is this behavior correct, or are we freezing a bug?"** A
  green guard is allowed; an *unflagged* green guard that silently pins a bug is not.
- **Relay host can't run the test → mark `unverified`, never count it as a spec or a
  pass.** If the relay host lacks the toolchain or fixture (no Android SDK, no game-ROM,
  etc.), you cannot verify redness — assertion "by construction" (uncompilable) is a
  promissory note, not a verified spec. Tag the test `# unverified — run in <env>`
  (e.g. Docker on fievel, Termux on pixel, with `<fixture>`), record it in RELAY_LOG.md
  + REVIEW_ME, and set the item's done-check to REQUIRE running it in that env. A
  **skipped or uncompiled test is NOT a pass.** If the executor also lacks the env, the
  item is a HANDBACK (hardware/fixture-gated), not a completion.

**C4 — BDD + review queue.** For user-facing surfaces, write Given/When/Then scenarios
for the key journeys:
- Web → executable headless Playwright features.
- TUI / Android / other non-automatable surfaces → the same Gherkin tagged `@manual`
  as a human checklist.
- **Skip C4 entirely if the repo has no user-facing surface** (library, script, infra).

Every red test that encodes a JUDGMENT CALL (ambiguous spec, a chosen interpretation
among defensible ones) goes into `REVIEW_ME.md` for the human's 15-min/repo budget.
Commit `relay(handoff): C4 bdd`.

**C5 — HARD item (only if budgeted).** Execute the top `[HARD]` item full
red-green-refactor. If cut off **mid-item with real work already committed**, write a
`HANDBACK:` paragraph to RELAY_LOG.md describing the exact state and the worktree branch
so any session can resume it. Commit `relay(handoff): C5 <id>` (or a partial commit + handback).

**SIZE-OUT vs CUTOFF (id:8b1f).** The RELAY_LOG `HANDBACK:` commit above is ONLY for a
genuine mid-item CUTOFF where you ALREADY committed real work and need resume provenance.
If instead you SIZE OUT the item BEFORE starting (too large / gated / multi-session /
can't make it green) and make no real code change, leave the worktree COMPLETELY CLEAN:
make NO commit, do NOT touch RELAY_LOG.md / ROADMAP.md / REVIEW_ME.md — put the rationale
ONLY in the returned `handback` field. The integrator never merges a handback, so a commit
made on a pre-start refusal strands forever as an orphan worktree (id:a4e9); a clean
worktree is auto-reaped (id:3ac8).

## Return contract

Return a structured report — do NOT push, do NOT run git-diary-workflow or todo-update
(those are the orchestrator's job, batched across children):

```json
{
  "repo": "<name>",
  "branch": "<worktree branch>",
  "stages_completed": ["C1", "C2", "C3", "C4"],
  "commits": ["<sha> relay(handoff): C1 docs", "..."],
  "roadmap_items": {"routine": <n>, "hard": <n>},
  "review_me": <count of REVIEW_ME.md entries>,
  "diary_fragment": "<one-paragraph summary for the batched diary entry>",
  "handback": "<text if C5 was interrupted, else empty>",
  "contract_met": true
}
```

**On a handback (`contract_met: false`), ALSO classify it (id:3801)** so the integrator records
it durably in ROADMAP.md (`handback-followup.py`) and the pool stops re-dispatching the same
un-doable item. Add:

```json
{
  "handback_item": "<4-hex id the handback concerns, e.g. the [HARD] item you sized out>",
  "route": "decision-gate | hard-split | human | none",
  "gate_reason": "<ONE short line for the inline ROADMAP gate note>",
  "proposed_split": [
    {"title": "<seam>", "tier": "HARD|ROUTINE", "dep": "<id it depends on, omit if independent>",
     "id": "<reuse an existing token if the seam already has one, else OMIT to mint>"}
  ]
}
```

- `decision-gate` — needs a `/meeting` design decision first → parent re-tagged `[HARD — decision gate]`.
- `hard-split` — too large but decomposable → parent gated + `proposed_split` seams minted as pickable units.
- `human` — needs a manual human action / `/relay human`.
- `none` (or omit) — transient/other failure, no durable action.

`contract_met` is false if checkpoints are out of order (e.g. C3 without C1/C2) or a
required artifact is missing; the orchestrator holds such a worktree for inspection
rather than merging it.

## Resuming an interrupted handoff

Because each checkpoint is its own commit, a handoff killed mid-run (API stream-idle
timeout, terminal error after the harness's retries, OOM) leaves its completed
checkpoints safe on the worktree branch — only the in-progress stage is lost. Resume,
don't restart: a fresh handoff would redo the expensive early work (C1 docs / C2 roadmap).

- **Autonomous pool**: `runUnit` in `relay-loop.js` catches a child throw/null and, for a
  handoff, spawns ONE auto-resume child (`resumePrompt`) that reads the worktree's
  committed checkpoints and continues from the next stage. If that also fails, the unit
  is recorded as a **recoverable handback** in `RELAY_STATUS.md` with the real worktree
  path (never orphaned with `-`).
- **Manual / next turn**: point an Opus handoff child at the existing worktree
  (`~/.cache/fables-turn/worktrees/<repo>/<runId>-handoff`), tell it C1..Cn are committed,
  and have it continue from C(n+1) using ONLY the id tokens already in the committed
  `ROADMAP.md`. Then integrate normally (merge → ckpt-tag → push → prune).

A resume child must NOT re-mint tokens or rewrite already-committed checkpoints — it only
adds the missing stages.
