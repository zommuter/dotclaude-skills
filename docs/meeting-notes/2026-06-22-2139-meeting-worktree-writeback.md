# 2026-06-22 — Should `/meeting` run in a git worktree for relay-managed repos?

**Started:** 2026-06-22 21:39
**Session:** 9030db88-5654-4f3a-bd2f-88bf5db5df01
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime)
**Topic:** Adopt inbox item `routed:af04` (from truncocraft) — should `/meeting` write+commit its end-of-meeting output via an isolated worktree + serialized integration, instead of writing directly into the main checkout where a live relay pool can collide?

## Surfaced prior art
- **id:3558** (BUILD OPENED) — "Independent-session flock'd merge-to-canonical": the umbrella *worktree-per-session* structural fix. af04 is essentially "extend id:3558 to `/meeting`."
- **id:ca87** — ratified: *worktree work → serialized merge, no flock; same-directory work → flock*; explicitly classified `/meeting` as a **same-directory→flock** actor (flock'd `md-merge.py`), NOT a worktree actor.
- **id:c144** ([[relay-local-parallelism-d2]]) — deliberately **exempts `/meeting` + `/relay human` ledger writes from the hard lease**; scoop window closed via atomic `md-merge.py` commit (id:148b) + ban `git add -A` in integrator (id:debf). "Hard lease = code-only."
- **[[parallel-session-state-coordination]]** — worktrees scoped to **same-repo *code* edits only**; ledger/doc edits deliberately kept out of worktrees.
- **Step 2a** (current `meeting/SKILL.md`) — relay-pool claim hold: meeting NOTE + read/think never blocked; only the shared-ledger write-back is gated; on refusal it **DEFERS** with a durable pointer to the note.
- **Incident (truncocraft, 2026-06-22)** — a `/meeting` wrote/committed into the same main checkout a live relay pool used as its integration checkout; ledger write-back had to be fully deferred. N=1.

## Agenda
1. Is the truncocraft incident a *defect*, or is it claim.sh step 2a *working as designed*?
2. If worth acting: **worktree-per-meeting-writeback** vs **subsume into id:3558** vs **cheaper deferral-UX fix**.
3. (Conditional) integration path — superseded by D2 (worktree rejected); became the write-surface inventory.

## Discussion

### Item 1 — Defect, or working as designed?
- 🏗️ Archie: step 2a deferred exactly as specified; no corruption, decisions durable in the note.
- 😈 Riku: actual harm in the incident = nothing lost; "deferral is bad" is an unestablished premise. But the *real* gap: deferral is manual and never auto-completes → the ledger silently lags the note until the next meeting's `--cross-ledger` scan catches the drift.
- ⚙️ Sage: a meeting is an interactive FOREGROUND session in the user's terminal cwd; its only repo writes are the end-of-meeting note + ledger edits + commit (the plan file already lives outside the repo). "Run in a worktree" reduces to "do the ~6 end-of-meeting writes in a worktree."
- ✂️ Petra: scope collapses to ~6 writes in the last 30s; evidence is N=1; observe-before-preventing applies.

### Item 2 — What (if anything) to build
- 🏗️ Archie: worktree-per-meeting INHERITS id:ca87's non-unionable-checkbox merge problem (worktree off a stale baseRef while the pool advances main) + adds setup cost for ~6 tiny writes. Reject.
- ⚙️ Sage: literal af04 contradicts id:ca87 (`/meeting`=same-dir→flock) + worktrees-are-code-only; the existing layering (file-flock + repo-level claim.sh step 2a) is already correct. Constraint archaeology: the old decision still binds.
- 😈 Riku: "subsume into id:3558" is a TRAP — id:3558 covers concurrent CODE writers, not the foreground meeting's main-checkout ledger tick; the D1 gap would stay open forever. id:3558 and the gap are ORTHOGONAL.
- ⚙️ Sage: near-free fix = on deferral, drop a `md-merge.py`/`append.sh`-ready payload to a gitignored path + log; replay on next `/meeting`/`/todo-update` setup under a fresh claim. Self-heals AND gathers frequency evidence (observe-first logger).

**User amendment:** collisions are not limited to `<root>` ledgers — they also arise from `~/.claude` shared-file writes (user-profile, memory, discoveries/personas) and cross-repo / inter-project influence. The write-back contract must account for ALL of a meeting's persistent write surfaces. → Item 3.

### Item 3 — Write-surface inventory

| Surface | Path | Guard today | "Pool holds whole repo" risk? |
|---|---|---|---|
| Meeting note | `<root>/docs/meeting-notes/…` | unique new filename | none |
| `<root>` ledgers (TODO/ROADMAP/REVIEW_ME) | `<root>/*.md` | `md-merge.py` flock **+ step 2a claim** | **YES** — the af04 case |
| user-profile.md | `~/.claude/skills/meeting/` | `md-merge.py` flock | none (local-only, uncommitted; `~/.claude` not pool-managed) |
| discoveries / personas | `~/.claude/skills/meeting/` | `append.sh` flock (union) | none |
| shared inbox (cross-repo routing) | `~/.claude/todo-inbox.md` | `append.sh` flock (union) | none |
| memory files + `MEMORY.md` | `~/.claude/projects/<slug>/memory/` | **plain `Write` — NO flock** | none, but **unguarded vs concurrent writer** |
| `~/.claude/CLAUDE.md` (universal) | — | manual propose+approve | n/a (human-gated) |

- The "pool holds the whole tree" mode only exists for relay-managed PROJECT repos. `~/.claude` is a git repo but NOT pool-managed (no ROADMAP.md/relay.toml), so its shared files only ever face concurrent-writer contention — flock blocks-and-completes, never defers. Cross-repo influence routes through the flock'd inbox, never a direct other-repo write.
- Genuine new finding: **memory writes use plain `Write` (no flock)** → two concurrent sessions can clobber `MEMORY.md`'s pointer list (unlike discoveries/personas, memory does NOT go through `append.sh`).

## Decisions
- **D1:** Step 2a is **working as designed** — the truncocraft deferral was the safety mechanism firing, not a defect; no data was lost. The only real shortcoming is that a deferred write-back is not auto-reconciled. *Out of scope:* treating deferral itself as a bug.
- **D2:** **Reject** the literal af04 worktree-per-meeting option — it inherits id:ca87's non-unionable-checkbox merge problem, adds worktree cost for ~6 tiny writes, and contradicts id:ca87 (`/meeting`=same-dir→flock) + worktrees-are-code-only. Build instead a **breadcrumb + replay-on-next-invocation + log**: on a deferred write-back, persist a replayable payload (gitignored) and log the event; the next `/meeting` or `/todo-update` setup replays pending payloads under a fresh claim. af04 → cross-link motivation on id:3558 (no new structural build). *Out of scope:* any long-lived queue/daemon (escalate only if the log shows recurrence).
- **D3a:** Breadcrumb payload format is **generic** (`{target_file, helper, payload}`) so it extends if a new defer site appears, but it is **wired in only at the step-2a `<root>` ledger write-back** — the sole site that defers today. *Out of scope:* pre-spreading the breadcrumb across `~/.claude` / every helper call.
- **D3b:** Memory writes (`~/.claude/projects/<slug>/memory/*.md` + `MEMORY.md`) are the one unguarded surface → flock them via a helper, **folded into the lock-hygiene umbrella id:d2cd**. *Out of scope:* building it this session.

## Action items
- [ ] **Breadcrumb + replay-on-next-invocation + log for deferred `<root>` ledger write-back** — extend `meeting/SKILL.md` step 2a: on a refused claim (deferral), write a generic `{target_file, helper, payload}` JSON to a gitignored drop path (`<root>/.meeting-deferred-writeback.json`) AND append an event to `~/.claude/logs/meeting-deferred-writeback.log`; add a setup-phase replay check (in `/meeting` setup and `/todo-update`) that applies any pending payload via the named helper under a fresh `claim.sh acquire`, then clears the drop file. Test contract: a deferred write-back leaves a replayable payload; the next invocation applies it under a fresh claim and removes the drop file; nothing is applied while the pool still holds the claim. Add `.meeting-deferred-writeback.json` to `.gitignore`. Also add the af04 motivation as a cross-link note on id:3558 and record the worktree option as rejected-by-this-meeting. (session: smooth-sprouting-grove, `docs/meeting-notes/2026-06-22-2139-meeting-worktree-writeback.md`) <!-- id:2c42 -->
- [ ] **Flock the meeting memory writes (fold into id:d2cd)** — route `~/.claude/projects/<slug>/memory/*.md` writes and the `MEMORY.md` pointer append through a flock'd helper (append.sh-style or md-merge) so concurrent sessions can't clobber `MEMORY.md`. Cross-link the lock-hygiene umbrella id:d2cd. Test contract: two concurrent `MEMORY.md` pointer appends both land (no lost update). (session: smooth-sprouting-grove, `docs/meeting-notes/2026-06-22-2139-meeting-worktree-writeback.md`) <!-- id:6f61 -->
