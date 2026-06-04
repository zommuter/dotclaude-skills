# 2026-06-03 — Parallel-session state coordination

**Started:** 2026-06-03 16:13
**Session:** 34d02816-ef54-449f-b166-5b1832bc9fa7
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime, standing), 🗄️ Cassi (derived-data / sharded-file, new)
**Topic:** Whether per-session ephemeral worktrees are the right fix for parallel-session write friction, and what is.

## Surfaced discoveries
- [2026-05-14 zkm] An atomic tmp+rename write makes a single write process-safe but does NOT make a read-modify-write atomic across processes — exactly the persona-state.yml failure mode.
- [2026-05-20 dotclaude-skills] Worktree-local TODO.md prose pointers invited autonomous upward traversal; worktree subdirs already created a friction class once.
- [2026-05-28 dotclaude-skills] MEETING_ROOT_OVERRIDE env-redirect is the existing cross-root dispatch (no cd) — the closest thing to worktree-aware routing today.

## Agenda
1. What is the actual failure mode and its frequency?
2. Does worktree-per-session solve the sharpest races?
3. What is the right fix set, shape-matched per file class?
4. Is "meeting-rpg edits the /meeting skill itself" a concurrency problem or a separate responsibility question?

## Discussion

### Item 1 — failure mode taxonomy

Three hazard classes found in the codebase:

1. **γ — lost-increment accumulators.** `persona-state.yml`/`.json`: `persona-state.py update` does atomic-write (tmp+rename) but non-atomic cross-process read-modify-write (read baseline → mutate in memory → replace). Two sessions both read the same baseline YAML, each appends and bumps affinity sums; second `replace()` clobbers the first's increments. **Gitignored** — git's merge layer never sees it.
2. **δ — direct-Edit RMW.** `user-profile.md`, `TODO.md`, `MEMORY.md`: written via raw Edit at end-of-meeting. Two sessions finishing concurrently can clobber. `user-profile.md` is untracked-and-not-ignored (invisible to git too).
3. **β — append-only.** `discoveries.md`, `personas.md`, logs: written via `append.sh`'s `>>`. Single-`printf` appends are near-atomic under PIPE_BUF; multi-line entries could interleave. Low risk today.

Only serialization primitive today: `git-lock-push.sh` (flock, push-only — guards transport, not working-tree file edits).

### Item 2 — worktrees revised

Initial assessment (Sage): "worktrees don't solve user-profile.md" — conditional on untracked state; **withdrawn**. Tracked + worktree *does* convert silent clobber → visible merge for δ docs, which is strictly better.

Three remaining complications:
- Git cannot semantically merge stored running-sums — but user correctly noted a 3-way additive merge driver (`ours + theirs − base = old + δA + δB`) is mathematically trivial for scalars.
- One `/meeting` end-of-meeting writes across 3–4 repos → "worktree per session" is really "per session per repo" + cross-repo lifecycle coordination.
- Shared private files are **untracked-on-purpose** (P2 publishability split keeps personal data out of the public dotclaude-skills repo) → "just track it" forces a private-home decision.

Custom merge drivers run on merge but **NOT on fast-forward** — so "atomic ff-merge" (the user's original formulation) would skip any merge driver. ff-merge and merge-driver are mutually exclusive.

### Item 3 — sharding and the file-shape taxonomy

Cassi introduced: shard-per-writer is a **G-Counter on disk** — each session writes only its own `<session-id>` file, so the lost-update race is structurally impossible. No lock, no daemon, no merge driver.

User constraint: on-read folding is **absolute no-go** if it costs AI tokens. Solution: fold is **script-side** (deterministic Python, never touches the AI context). Session writes a small delta shard; a `flock`'d collapse command folds all shards into the unified file and GCs them at meeting end. Unified file at rest — no reader burden.

Taxonomy across all shared files:

| Shape | Files | Contention | Fix |
|---|---|---|---|
| α unique-file | meeting notes, memory/<topic>.md | none by construction | — |
| β append-log | DIARY.md, discoveries.md, personas.md, MEMORY.md | low / append | `flock`'d append + `merge=union` |
| γ accumulator | persona-state.yml/.json | **sharp / silent** | shard-per-session + script-fold-collapse |
| δ section-doc | TODO.md, user-profile.md | medium / clobber | `flock`'d deterministic merge |
| git commits | all repos | handled | git-lock-push.sh |

External research validated (sources: git docs, git-merge-changelog/gnulib, SQLite WAL docs, CodeCRDT arXiv:2510.18893, multi-agent AI worktree patterns):
- `merge=union` ships built-in in git; canonical precedent is git-merge-changelog for changelog files.
- shard-per-writer = G-Counter on disk; fold must be script-side for zero AI token cost.
- δ section-docs are non-commutative — CRDT-text is heavy overkill; `flock`'d deterministic merge is textbook-legit (same pattern as git-lock-push.sh).
- SQLite/WAL is the "correct" transactional answer but kills plaintext + git-diffability — rejected for this system.
- **Bonus finding:** the current AI-rewrites-whole-TODO.md loop is itself both the lost-update vector AND pays tokens ∝ filesize/prompt.

### Item 4 — worktrees, scoped; agent-spawning

Worktree-per-session **is** the right tool, scoped: concurrent tracked code edits in the *same source repo* (the field-endorsed worktree-per-agent pattern). Not state-coordination. Hard constraint: `--no-ff` merges only (ff skips merge drivers).

"meeting-rpg edits the /meeting skill itself" is a separate cross-repo ownership/responsibility question, not a concurrency fix target in this meeting.

User added: discuss spawning Sonnet/Haiku sub-agents for parallel Class 1 impl-ready items (separate meeting).

### Item 5 — /meeting self-bug

Interactive protocol failed twice: transcript-print and `AskUserQuestion` call were emitted in separate turns, leaving the user with a UI that showed options before the discussion was visible. Fix: SKILL.md "Interactive mode" step 5 must state both ship in the same turn.

## Decisions

- **D1 — Shape-matched program, not one mechanism.** Coordinate shared state per file-shape (β/γ/δ); do NOT adopt a universal worktree-per-session layer for state. *Out of scope:* SQLite/daemon substrate (rejected — plaintext + git-diffability is a core value).
- **D2 — β append-logs: `flock`'d append + `merge=union`.** Wrap `append.sh` write in `flock`. Add `.gitattributes` `merge=union` for tracked append-logs (`personas.md`@dotclaude-skills; `DIARY.md`@claude-diary; MEMORY.md indices). *Out of scope:* dedup/ordering guarantees (union is order-free by design).
- **D3 — γ accumulators: shard + script-fold-collapse.** `persona-state.py` gains `shard` (append this session's delta to gitignored `persona-events/<session-id>` — zero contention) and `collapse` (under `flock`, fold all shards → unified yml/json, GC shards). SKILL.md step 2d wired to `shard` during meeting, `collapse` at end. Fold is script-side — zero AI tokens; canonical file stays untracked-private (no home decision). *Out of scope:* tracking the state files; on-read folding.
- **D4 — δ section-docs: `flock`'d deterministic merge.** `TODO.md` (keyed by `<!-- id:XXXX -->`) and `user-profile.md` (keyed by `## section`) get a `flock`'d merge helper: re-reads under lock, applies this session's structured delta rather than blind whole-file rewrite. Stays markdown-in-git. Begins the delta-over-rewrite migration. *Out of scope (this build):* fully converting todo-update to delta-only.
- **D5 — Worktrees retained, scoped.** Worktree-per-session applies only to concurrent tracked code edits in the same source repo. Separate follow-up design meeting. Hard constraint: `--no-ff`.
- **D6 — Agent-spawning (TODO).** Discuss Sonnet/Haiku sub-agents for parallel Class 1 tasks. Separate meeting.
- **D7 — Fix /meeting self-bug.** Interactive protocol: transcript-print + `AskUserQuestion` must ship in the **same turn** (SKILL.md "Interactive mode" step 5).

## Action items
- [ ] β: wrap `append.sh` write in `flock` — `meeting/append.sh`. Contract: two concurrent calls to same target never interleave lines. <!-- id:9cfb -->
- [ ] β: add `.gitattributes` `merge=union` for tracked append-logs (`personas.md`@dotclaude-skills; `DIARY.md`@claude-diary; MEMORY.md indices). Contract: concurrent-branch appends union-merge with no conflict markers. <!-- id:fbcd -->
- [ ] γ: add `shard` + `collapse` subcommands to `meeting/persona-state.py`; update SKILL.md step 2d to `shard` during meeting, `collapse` (flock'd) at end. Contract: N concurrent meetings each record delta; final sums = Σ all deltas; no shard files remain after collapse. <!-- id:5f60 -->
- [ ] δ: new `flock`'d deterministic merge helper for `TODO.md` (by `<!-- id:XXXX -->`) + `user-profile.md` (by `## section`). Wire into `todo-update` + `/meeting` end-of-meeting writes. Contract: two sessions editing different items/sections both survive; same-item serializes, last-under-lock wins without clobbering other items. <!-- id:42f4 -->
- [ ] self-bug: edit SKILL.md "Interactive mode" step 5 to require transcript-print + AskUserQuestion in the same turn — `meeting/SKILL.md`. <!-- id:ec72 -->
- [ ] TODO (discuss): worktree-per-session for concurrent same-repo Class 1 code edits (D5) — separate design meeting. <!-- id:d18d -->
- [ ] TODO (discuss): spawn Sonnet/Haiku agents for parallel Class 1 tasks (D6) — separate design meeting. <!-- id:cbb5 -->
