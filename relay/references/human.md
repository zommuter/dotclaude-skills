# Human mode — cross-repo HUMAN-BACKLOG triage procedure

The relay has three actors: **execute** (Sonnet executor sessions), **review/hard**
(the strong apex model, Opus), and **human** (you). `/relay human` is the
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
all confirmed own repos; `/relay human <repo-list>` narrows to the named repos;
`/relay human --all` is the explicit full sweep.

## 2. Collect the backlog

Run the read-only collector (optionally inside a single Explore sub-agent):

```bash
scripts/gather-human-backlog.sh                 # all own repos
scripts/gather-human-backlog.sh repoA repoB     # named repos
```

**Grammar-lint each own repo's ROADMAP alongside the gather (id:09a3).** Run
`scripts/roadmap-lint.sh <repo-root>` across the same own repos — a POSITIVE-grammar
validator that LOUD-rejects ANY open `- [ ]` item not matching the proper syntax (a
recognized `[ROUTINE]`/`[HARD — pool|meeting|hands|decision gate]` lane from
`hard-lanes.md` PLUS a 4-hex `id:` token; gated/deferred/icebox/archive sections are
exempt). This widens the net beyond the gather's untagged-`[HARD]` check: it also catches
an open item with NO class tag at all (invisible to BOTH the loop AND triage) and
malformed/unknown lanes. A nonzero lint exit means a ROADMAP item needs a lane/id assigned
at the source — surface it on the "you fix these at source" list (do NOT auto-rewrite).

**TODO grammar-lint each own repo too (id:3441).** Run `scripts/todo-conformance.sh --fix
<repo>/TODO.md` across the same repos — the TODO-side sibling of roadmap-lint. It AUTO-FIXES
the safe class (an open checkbox item missing an id → mints+appends one) and SURFACES every
`orphan` line on the "you fix these at source" list; resolve them by the owner-approved
policies in `references/todo-conversion-policies.md` (P1–P4) — surface, never auto-convert
prose to a task on a guess. **NEVER blocks.**

**Surface the shared inbox's non-conforming entries + dead-letters (id:678e slice 1).** Run
`scripts/scan-routed.sh` (`RELAY_INBOX` default `~/.claude/todo-inbox.md`, override per the
config-path convention — the public script never embeds inbox *contents*). It reports each
`DEAD-LETTER` (a conforming `routed:` item whose `[target]` repo never ingested it),
`UNRESOLVED` target, and `NON-CONFORMING` prose block (the latter via `todo-conformance.sh
--inbox`), each with a ready-to-run file command — so the inbox can't silently strand
cross-project work. Respect `--exclude`/`relay.toml paused` for the target set. **Report-only
— it NEVER writes.** The gated AUTO-FILE half (auto-filing class-A routed items into their
target repos) is slice 2 of id:678e; until it lands, run the surfaced command by hand.

It emits a TSV `repo  path  kind  box_summary` covering:

- every OPEN `- [ ]` box in each repo's `REVIEW_ME.md` (`kind = review_me`), AND
- open `@manual` boxes — REVIEW_ME `@manual` lines AND `ROADMAP.md` items tagged
  `@manual`/BDD that need a human to RUN them (`kind = manual`), AND
- every open `- [ ]` `[HARD]` `ROADMAP.md` item, bucketed by its EXPLICIT lane tag
  (id:78ff) into one of three kinds — **`hard_pool` / `hard_meeting` / `hard_hands`** —
  re-derived from ROADMAP, not a possibly-stale live `RELAY_STATUS.md`. The lane is
  READ from the bracket tag, never inferred (decision 2026-06-21 "obviously explicit");
  the shared lane vocabulary is **`relay/references/hard-lanes.md`**, parsed identically
  by `project_manager`'s `scan.py` (id:b466 — keep the two in sync). The buckets:
  - **`hard_pool`** (`[HARD — pool]`) — bounded, unattended-safe apex work the
    `/relay --afk` pool already runs via its `hard` verdict (id:da26). **NOT a human
    action** — surface it as FYI, do not route it to a meeting.
  - **`hard_meeting`** (`[HARD — meeting]`, plus the auto-gate aliases
    `[HARD — decision gate]` and `🚧 route:meeting|human|decision-gate`, id:3801) —
    needs a `/meeting` design decision before anyone can build it. This is the tier-(c)
    "needs a /meeting" backlog.
  - **`hard_hands`** (`[HARD — hands]`) — hardware/sudo/secret/on-device/rehearsal: the
    human runs it. Belongs on the "you run these" checklist (§4), NOT a meeting.

  This REPLACES the old single `gated_hard` lump (id:f6c9), which routed EVERY open
  `[HARD]` item to "needs a /meeting" — so ~40 pool-executable HARD items read as 40
  meetings. The pool-executable majority now bucket as `hard_pool` and only genuine
  decision/hands work reaches human triage. The collector spawns no model: each
  recognized row's `box_summary` carries the item text plus ` — <bucket>: <why>`.
- **`untagged` is a HARD ERROR, not a kind.** An open `[HARD]` item with no recognized
  lane tag makes the collector print an `ERROR:` line to stderr (repo + item) and **exit
  nonzero** (id:415b grammar-tightening-with-loud-rejection). If `/relay human` sees a
  nonzero gather exit, the FIRST fix is to add the missing lane tag to the offending
  ROADMAP item(s) at the source — never silently default a disposition.

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

**The three HARD-lane kinds map to distinct dispositions (id:78ff) — do NOT lump
them.** The collector has already READ each item's explicit lane, so route by `kind`:

- **`hard_meeting` boxes ARE tier-(c) by construction.** Each is a `[HARD]` item that
  needs a `/meeting` to resolve or re-scope. Present them as a distinct tier-(c)
  **"needs a /meeting" checklist**, separate from the REVIEW_ME verdict tiers (a)/(b):
  one line per item — `repo · item id · one-line why` (the ` — meeting: <why>` already
  in `box_summary`) — routed to `/meeting --cross` with the box left OPEN. NEVER
  auto-tick one (a human meeting must resolve the gate).
- **`hard_hands` boxes go on the "you run these" checklist (§4), NOT a meeting.** They
  need a human to physically run something (hardware/sudo/secret/on-device); a meeting
  cannot discharge them. Leave OPEN; surface in the §4 manual checklist.
- **`hard_pool` boxes are NOT a human action.** They are pool-executable apex work the
  `/relay --afk` pool already runs via its `hard` verdict (id:da26). Do NOT route them
  to a meeting and do NOT put them on the "you run these" list — surface them only as a
  short FYI ("N pool-executable HARD items waiting on the next `/relay --afk` run") so
  the human can kick a pool if none is live. This is the whole point of id:78ff: the
  pool-executable majority no longer masquerades as a meeting backlog.

Without explicit lanes, every one of these was a single `gated_hard` row routed to
"needs a /meeting" (id:f6c9), drowning the real meeting backlog (~40 HARD ≈ 40
meetings). All three kinds are still re-derived from ROADMAP (freshness-safe), so the
human sees the pool's HARD backlog in the SAME place they triage REVIEW_ME.

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

**Commit each repo's ledger edit ATOMICALLY, never leave it dirty-uncommitted (id:2147).**
`md-merge.py` writes the ledger but does NOT commit — and an interrupted `/relay human` run
(mid-run API error, session kill) that wrote a lane back-fill / gate annotation / tick but
never reached a commit leaves dirty residue in the main checkout, which trips the dirty-guard
(id:aa93) so every later pool run DEFERS that repo forever. Immediately after each repo's
`md-merge.py` ledger writes, commit them with the scoped, flock'd helper (stages ONLY the
named files — never `git add -A` — and never stashes/resets a foreign-dirty tree):
```bash
~/.claude/skills/relay/scripts/commit-ledger.sh <repo> \
  -m "relay human: ledger flow-back (id:3801, id:2147)" ROADMAP.md TODO.md REVIEW_ME.md
```
It is a clean no-op for any named file that didn't change, so listing all three is safe.
Commit-only (no push, per the contract above); committing locally is what clears the
dirty-guard for the next pool run.

**Peek-and-warn, not lease-gated (id:c144 — supersedes the id:0902 DEFER for ledger writes).**
A `/relay human` write-back is a **ledger-only** edit (line-scoped ticks + flow-back), so per
meeting D2 (`docs/meeting-notes/2026-06-17-0953-k3s-parallelity-coordination-design.md`) it is
**not** gated by the relay `hard` lease — that lease guards CODE/WORKTREE integration only. The
write is already safe under a live pool via three layers: the per-file flock (`md-merge.py`), the
atomic scoped commit (`commit-ledger.sh`, id:2147/id:148b), and the `orphan-scan.sh
--cross-ledger` backstop. So a repo's write-back does **not** `claim.sh acquire` and does **not**
DEFER on a held lease. Instead **peek and warn, then proceed**:
`~/.claude/skills/relay/scripts/claim.sh peek | grep <repo>` — if a live relay run holds the
repo, WARN in the turn summary ("relay pool live on <repo> — proceeding with the flock-protected,
atomically-committed ledger write; the hard lease guards code integration only, not ledger
writes, id:c144; cross-check `orphan-scan.sh --cross-ledger <repo>` after the pool drains"), then
do the write-back. (Peek is advisory awareness only; the bilateral advisory-claim the pool
*honors* is the separate observe-first id:9000 follow-up.) The CODE children in
`/relay handoff|review` STILL acquire the lease before fan-out (SKILL.md invariant 4) — only
ledger-only write-backs are exempt. Fallback: if `commit-ledger.sh` cannot acquire its flock
within the timeout (rare contention, not a pool deferral), surface the repo and re-run once idle
— your auto-answers are re-checkable CLAIMs, so nothing is lost.

**Push unblocked work to the running pool, low-latency (id:fb75).** When a resolved box
**unblocks** a gated/blocked ROADMAP item (e.g. ticking a decision-gate box opens a
`[HARD]`/`[ROUTINE]` item that was waiting on it), don't make the pool wait until its next
discovery re-derives the dependency. After the clean lease-held write-back, hand the
now-unblocked item straight to the pool:
`~/.claude/skills/relay/scripts/inject.sh add <repo> --item <id> --verdict execute`
(reuse the **same id** the unblocked item already carries — single-id-two-views, never mint
a fresh token for already-tracked work). Do this **only when the resolution actually
unblocks pool work** — a plain bookkeeping tick that frees nothing needs no injection (a
blind inject on every toggle just churns discovery). A live pool then pulls the injected
unit ahead of its normal verdict-class schedule (id:baf1), and with id:6e9d a freed lane
picks it up mid-round without waiting for the round boundary. The `/meeting` REVIEW_ME
write-back (id:15d5) does the same on resolution that unblocks work.

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
- tier-(c) boxes routed to `/meeting --cross` — including the **`hard_meeting` "needs a
  /meeting" checklist** (repo · item id · why), surfaced here so the pool's decision
  backlog stops silently stalling (id:78ff),
- the **"you run these"** checklist (open `@manual` boxes AND `hard_hands` items),
- a short **`hard_pool` FYI** line (count of pool-executable HARD items waiting on the
  next `/relay --afk` run — NOT a human action, just so the human can kick a pool),
- any dirty repos skipped,
- if the gather exited NONZERO: the **untagged-`[HARD]` ERROR** — list the offending
  repo/item and the missing lane tag to add (id:415b: fix at the source).

Lead the summary with what the human can now observe (closed REVIEW_ME boxes, the
manual checklist to run), not counts.
