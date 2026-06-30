# PREP — "Revamp the relay-loop as mechanically as possible" (meeting for NEXT session)

> **This is a meeting-PREP / handover doc, not a meeting record.** It hands the next
> session everything needed to convene the `/meeting` on **dotclaude-skills id:4d8e**
> (+ siblings b444 / 80b8 / 0ee6) without re-deriving the context. Written 2026-06-30
> 15:14 after a long `/relay --afk` session that surfaced 8 discovery-contract failures.

## Why this meeting

The relay-loop's **discovery contract fails too often.** Discovery is currently an LLM
`discover-shard` + scattered greps that infer a verdict by trusting tag/gate/lane/guard
states that **don't match the ledger**. One `/relay --afk` session (2026-06-30) surfaced
**8 distinct false verdicts**, every one the same shape: *the loop trusted a state instead
of the deterministic scan.* The user's verdict: **"95% of this loop should really be kicked
off mechanically."**

This is now backed by a **global CLAUDE.md rule** established the same session:

> **Mechanize-first; reserve the LLM for loud failures.** If a process can be *mostly*
> mechanized, mechanize it (or explicitly suggest/file it) — reserve the LLM for cases the
> mechanical layer genuinely cannot resolve, and make those **fail LOUDLY** (never a silent
> fallback). Gate the build on the determinism+cost rule (id:415b). Fold each LLM
> loud-failure resolution back into the mechanical layer over time (shrink the LLM surface).

The meeting applies that rule to relay discovery specifically.

## The RED-test corpus (the 8 cases — these become failing fixtures)

Each is "the classifier/guard trusted a state that didn't match reality." All observed
2026-06-30; ids are live in `dotclaude-skills/TODO.md` (cases a–h under id:4d8e).

| # | id | failure | the mechanical truth it should have used |
|---|----|---------|------------------------------------------|
| a | fb7f | counted `[HARD — pool]` inside back-tick'd re-lane PROSE → phantom `hard` verdict (it-infra) | match the item's own lane bracket, not a substring grep |
| b | 9014 | a ROADMAP whose only open item is `@manual` read as "needs human/idle", hiding 35 TODO items (truncocraft) | "drained" = no executor-ACTIONABLE open item → run unpromoted-scan |
| c | 244b | bracket tag `[HARD — decision gate]` contradicts its own prose "re-laned to pool" → gated, never ran, empty run misread as "done" (ai-codebench) | tag is authority; a tag/prose disagreement must fail loud |
| d | c5e9/fd30 | `[INTENSIVE — local-llm]` free-typed onto a disk `rm` / a `/meeting` decision item (it-infra) | intensive must be derivable, not free-typed; lint it |
| e | ded2 | 10 plugins each emitted a separate `review` for one identical mechanical fan-out commit | cohort-detect near-identical diffs → one verification |
| f | 3ac8 | auto-reap didn't fire on a clean handback worktree | mechanical clean-worktree reap check |
| g | (in 4d8e) | explicit `/relay handoff truncocraft` ran unpromoted-scan ("17 surface") then **silently promoted nothing** | a loud detection wasted because the RESOLUTION wasn't forced — "N surface" must escalate to a forced lane-triage |
| h | (in 4d8e) | "finished repo" guard (id:000d) declared zelegator done on a 0-open ROADMAP **without running unpromoted-scan**, hiding 7 open TODO items | "finished" = 0-open ROADMAP AND scan reports no promote/surface |

**The through-line:** g and h are the sharpest — a deterministic detector (`unpromoted-scan`)
that *works and reports loudly* but whose result is then **swallowed** by a guard/no-op. That
is the exact anti-pattern the new CLAUDE.md rule names.

## The direction (user-decided — don't re-litigate, decide the HOW)

1. A **deterministic verdict classifier** emits the verdict (execute/review/hard/handoff/human/idle)
   from the PARSED ledgers — **no LLM in the common path**.
2. Every discrepancy **fails LOUDLY** (never a silent mis-verdict or guessed lane).
3. LLM "resolution thinking" is a **last-resort fallback** only for cases the mechanical layer
   flags as genuinely ambiguous.
4. **~95% of loop kick-off is mechanical.**
5. Fold in the **inotify wake (id:0ee6)** so the classifier runs on real ledger/ref change, not
   a polling round.

## Substrate to REUSE (do not reinvent — feedback-use-existing-tools)

- `discover-sig.sh` (id:c3a6) — content-hash of discovery inputs; the inotify watch-set derives
  from the SAME superset (so watcher and sig can't disagree).
- `unpromoted-scan.sh` (id:2dea) — promote/surface/untracked (note: its promote/surface label
  semantics themselves want a tested contract — see case h secondary finding).
- `gather-human-backlog.sh` + `hard-lanes.md` (id:78ff) — lane vocabulary, LOUD-reject untagged.
- `roadmap-lint.sh` (id:09a3) — positive-grammar validator.
- Determinism-gate M/G/K tagging (id:415b) — discovery is exactly the LLM step that audit deferred;
  **this meeting is that audit's discovery child.**

## What the MEETING must decide

1. **The deterministic classifier's I/O contract** — one tested script: `repo → verdict JSON`.
   What fields? (verdict, reason, evidence-pointers, ambiguity-flag).
2. **Carve-out vs replace** — how it relates to / replaces the LLM `discover-shard`.
3. **The ≤5% LLM boundary** — exactly which sub-decisions are irreducibly LLM vs mechanical.
   (Candidate irreducibles: "is this untagged design item ROUTINE-ready or a [HARD — meeting]
   epic?" — the lane-triage in case g.)
4. **The RED-test harness shape** — fixture ROADMAP/TODO files → expected verdicts, wired into
   `make test` (the EXPECTED-RED convention already exists).
5. **inotify composition** (id:0ee6) with the sig-cache + the two-dry-discovery exit.
6. **Migration/cutover order.**
7. **(Sibling) Broker-backed parallel human-decision channel (id:b444)** — should the loud-failure
   RESOLUTIONS flow to an async broker queue (reusing meeting-rpg `broker.py`) so the Workflow
   pool — which CANNOT call `AskUserQuestion` — can dispatch human decisions without blocking?
   Heavy overlap with hermes record-and-defer + the ping-threshold surfacing; decide ONE home.
8. **(Sibling) Continuous dispatch (id:80b8)** — pipeline-not-barrier refill; interacts with the
   classifier (the refill picker consumes classifier verdicts).

## Children to mint in the meeting

The classifier contract + harness; then one RED fixture per case (a)–(h); then the cutover; then
the b444/80b8/0ee6 integration items. Folds in / supersedes the **discovery half of id:415b** for
relay.

## How to run it next session

`/meeting` on **id:4d8e** ("revamp relay-loop as mechanically as possible"), this doc as the brief.
Suggested personas: an architect (the contract), a devil's advocate (where does mechanical break /
what's truly irreducibly LLM), a productivity lens (cutover cost vs payoff), and a
formal/determinism lens (the M/G/K gate). Pull the 8 cases up as the concrete fixtures.

## Live pointers

- Umbrella + 8 cases: `dotclaude-skills/TODO.md` id:4d8e. Siblings: id:b444, id:80b8, id:0ee6.
- The rule: `~/.claude/CLAUDE.md` "Mechanize-first; reserve the LLM for loud failures."
- This session's diary: `~/src/claude-diary/DIARY.md` (2026-06-30 `/relay --afk`).
