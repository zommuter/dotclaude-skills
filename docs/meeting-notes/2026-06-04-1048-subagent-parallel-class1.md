# 2026-06-04 — Sonnet/Haiku sub-agent spawning for parallel Class 1 tasks (D6)

**Started:** 2026-06-04 10:48
**Session:** 04d7742e-6550-4208-adf5-8c1f606983ea
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime, standing), 🎛️ Orla (multi-agent orchestration, new)
**Topic:** Whether and how to spawn sub-agents to build multiple impl-ready (Class 1) TODO items in parallel — D6 from the 2026-06-03 parallel-session-state-coordination meeting.

## Surfaced discoveries
- [2026-05-14 project_manager] `claude --model opusplan` accepted alias — relevant to per-agent model-tier selection.
- [2026-06-03 dotclaude-skills] Multi-writer coordination is shape-dependent; merge drivers skip fast-forward — relevant to worktree merge-back.
- [2026-05-20 dotclaude-skills] Worktree-local TODO.md prose pointers invite autonomous upward traversal.
- [2026-05-08 .claude] Stop hooks receive `transcript_path` — relevant to sub-agent output verification.

## Agenda
1. Warrant & sequencing
2. Orchestration substrate & isolation
3. Model-tier policy & verification
4. Mandatory-trigger handling (git-diary + todo-update in sub-agents)

## Discussion

### Item 1 — Warrant & sequencing

✂️ Petra: The real Class 1 queue today is thin — the three unbuilt coordination items (γ, δ, merge=union) are the closest batch. The rest of TODO is trigger-/date-gated. D6 sits on top of D5 (worktrees) + the δ merge helper, both unbuilt. Building D6 first inverts the dependency stack.

😈 Riku: Sharper — spawning sub-agents today triggers the exact race the last meeting diagnosed but never fixed. Each child, on current skill wording, runs git-diary + todo-update → N concurrent whole-file TODO.md rewrites (unprotected δ clobber), N commits, N pushes. The detector only logs after the fact. Minimum evidence to move me: a dispatch contract that provably stops the race, plus a ratified worktree decision.

🏗️ Archie: D6 is the consumer of D5's worktree substrate, but we can design the shape now and gate the build — our standard move (cf. gh-issue-audit, meeting-cross).

🎛️ Orla: Fan-out only pays when (a) ≥3 independent units, (b) each large enough to amortize dispatch+merge, (c) verification doesn't eat the savings. Today (a) is borderline, (b) questionable — many Class 1 items are small script edits where one Sonnet in sequence beats spawning + worktree-ing + merging agents.

### Item 2 — Orchestration substrate & isolation

🏗️ Archie: Two substrates — (A) native Agent fan-out, each child gets one item + decision note in its own worktree; (B) the Workflow tool, a deterministic `parallel()` script with a built-in verify stage. For "build N impl-ready items," Workflow + worktree-per-item + verify is the cleaner fit; verification topology comes for free.

⚙️ Sage: Sub-agents do not inherit our skills automatically — desirable, because a child explicitly instructed to build in its worktree and return a diff sidesteps the mandatory-trigger landmine.

🎛️ Orla: Worktree-per-agent is field-standard isolation. D5 already recorded the `--no-ff` hard constraint (ff skips merge drivers). Main session merges sequentially.

😈 Riku: Worktrees aren't free (~200–500ms + disk per item, cross-repo lifecycle). And if two agents touch the same file, only safe answer is items partitioned to **disjoint file sets**, or serialized. Partition-by-footprint is a hard constraint on what's parallelizable.

✂️ Petra: So the parallelism unit isn't "Class 1 item" — it's "Class 1 item with a disjoint file footprint." Narrows demand further.

### Item 3 — Model-tier policy & verification

🎛️ Orla: Haiku is cheap/fast for mechanical edits; Sonnet for logic-heavy. `opusplan` is the existing per-phase tiering precedent.

🏗️ Archie: "Impl-ready" means design done → mostly mechanical → Haiku-default defensible.

😈 Riku: Haiku unsupervised is the risk — "impl-ready" ≠ "trivial." Non-negotiable: a verify gate before merge. Every Class 1 item already carries a `Contract:` line — a Sonnet verify-agent checks each diff against it.

✂️ Petra: Scope guard — do not build a tier-selection heuristic. Fixed roles: builder builds, Sonnet verifies, human approves. No auto-classifier until demand proves it.

**Tobias:** "We should pilot Haiku on some test tasks first, let's stick to Sonnet first."

### Item 4 — Mandatory-trigger handling

😈 Riku: The live landmine. Both skills say "mandatory after every prompt." N agents → N pushes, N TODO.md rewrites (unprotected δ clobber), N diary entries.

⚙️ Sage: Instruct children: "build in your worktree, do NOT run git-diary/todo-update, do NOT push." Main session then does one commit (sequential `--no-ff` merges), one diary entry, one TODO fold-in.

🏗️ Archie: Worktree isolation + single-writer fold-in sidestep most of the coordination program for this use case. The δ helper is still wanted for the human-concurrent case, not needed here.

**Tobias:** "No what's the point of non-committing children when we use worktrees specifically for that?"

⚙️ Sage (correction): Fair — committing in a worktree IS fully isolated (that's the payoff). The contention is (1) pushing to shared origin and (2) shared-ledger skills: git-diary appends DIARY.md in a separate repo; todo-update rewrites the shared TODO.md. Not the local code commit.

🏗️ Archie: Revised boundary — children DO commit their code in worktree branches. Main session merges `--no-ff`, then writes the shared ledger once: one batch diary entry + one TODO fold-in + single push. "Children own code commits, main owns shared ledger + push."

😈 Riku: The only shared writers left after this (DIARY append, origin push) are already flock-guarded. Clean.

**Tobias:** "Fine with 1, though what about the children feeding back their diary contribution to the main session instead of that having to re-think?"

⚙️ Sage: Make it part of the child return contract. Each child returns `{branch, diary_fragment, todo_item_id, done_summary, contract_met}`. Main session concatenates the fragments into the batch diary entry and applies the TODO deltas verbatim — no re-derivation from diffs.

🎛️ Orla: This maps naturally to a Workflow structured-output schema. The verify stage receives the diff + `contract_met` from the builder and confirms it before the main loop folds and pushes.

## Decisions

- **D6.1 — Design-and-gate, don't build now.** Record the orchestration design; gate the build. *Out of scope:* building the dispatcher this session.
- **D6.2 — Substrate: Workflow tool, worktree-per-item, verify stage.** `parallel()` build → Sonnet verify stage; one git worktree per item; merge `--no-ff` (ff skips merge drivers). **Parallelism unit = Class 1 items with disjoint file footprints** (overlapping-footprint items serialize). *Out of scope:* native Agent fan-out.
- **D6.3 — Tier: Sonnet builds + Sonnet verifies (Tobias revision).** Sonnet builds each item → Sonnet verify-agent checks diff against item `Contract:` line → human approves merge. **Haiku-as-builder NOT adopted** — gated behind a dedicated quality pilot (Haiku vs Sonnet on real impl-ready items). *Out of scope:* auto-tier classifier; Haiku in the live pipeline pre-pilot. Note: Sonnet builds raises per-item cost, which sharpens the demand gate from D6.1 further.
- **D6.4 — Boundary: children own code commits + return ledger fragments; main owns shared ledger + push.** Children commit code in worktree branches and return `{branch, diary_fragment, todo_item_id, done_summary, contract_met}`; they do NOT run git-diary/todo-update and do NOT push. Main session merges `--no-ff`, concatenates returned fragments → one batch diary entry, applies returned TODO deltas, single push. *Out of scope:* per-child diary/TODO writes; per-child origin push.
- **D6.5 — Prerequisite re-sequencing.** D6 hard-depends on **D5 ratified** + the **suppress-and-fold dispatch contract** (D6.4). The δ merge helper (id:42f4) is a **soft** prerequisite — still wanted for the human-concurrent-meetings case, not a blocker for sub-agents under one main session.

## Build gate (all three required before building the dispatcher)
1. ✓ D5 worktree-per-session design meeting ratified (2026-06-04).
2. A logged instance of ≥3 independent impl-ready items with disjoint file footprints queued at once.
3. ✓ Haiku-vs-Sonnet builder pilot run and decided (2026-06-04). Decision: **Sonnet-default confirmed.** See `2026-06-04-1300-haiku-sonnet-builder-pilot.md`.

## Action items
- [x] **Haiku-vs-Sonnet builder pilot** — complete 2026-06-04. Sonnet-default confirmed; Haiku fails LOGIC-HEAVY items. See `2026-06-04-1300-haiku-sonnet-builder-pilot.md`. <!-- id:c0d2 -->
