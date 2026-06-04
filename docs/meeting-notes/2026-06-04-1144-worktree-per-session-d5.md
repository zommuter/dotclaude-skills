# 2026-06-04 — Worktree-per-session for same-repo Class 1 code edits (D5)

**Started:** 2026-06-04 11:44
**Session:** 5222a783-f439-415d-892d-82a18aed1ead
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime, standing), 🎛️ Orla (multi-agent orchestration), 🔩 Gil (git plumbing/object-model, new)
**Topic:** Scope, `--no-ff` constraint, and lifecycle management for worktree-per-session isolation of concurrent same-repo Class 1 code edits — D5 from 2026-06-03 parallel-session-state-coordination.

## Surfaced discoveries
- [2026-06-04 dotclaude-skills] A background git-diary daemon (session B) committed+pushed session A's half-finished ~/.claude edits mid-task; git-lock-push flock serializes push but does NOT prevent the daemon snapshotting another session's uncommitted tree.
- [2026-06-03 dotclaude-skills] Multi-writer coordination is shape-dependent; custom merge drivers run on merge but NOT fast-forward.
- [2026-05-20 dotclaude-skills] Worktree-local TODO.md prose pointers invited autonomous upward traversal.
- [2026-05-28 dotclaude-skills] MEETING_ROOT_OVERRIDE env-redirect is the existing cross-root dispatch pattern.

## Agenda
1. Does D5 need any new build, or is it a convention on top of harness-native `EnterWorktree` + `Workflow isolation:'worktree'`?
2. Scope: which concurrency scenarios warrant a worktree?
3. `--no-ff` merge-back contract + `worktree.baseRef` setting.
4. Lifecycle: cleanup, naming, failure handling.

## Discussion

### Item 1 — Build vs. convention

🏗️ Archie: Worktree substrate already ships in the harness. Main session: `EnterWorktree`/`ExitWorktree` (creates under `.claude/worktrees/`, base ref via `worktree.baseRef`; ExitWorktree refuses to remove a dirty worktree without `discard_changes:true`). Sub-agents: `Workflow isolation:'worktree'`, auto-cleaned if unchanged. D5 is a convention, not a new script.

✂️ Petra: N=2 on any new code finds zero unserved consumers — both targets (D6 dispatch, top-level parallel sessions) already have a harness tool. Output is wording, not files.

🎛️ Orla: Three scenarios, asymmetric: (a) sub-agent dispatch → Workflow isolation (D6.2 already decided); (b) top-level parallel human sessions → EnterWorktree; (c) the git-diary daemon race → only conditionally fixed by worktrees.

😈 Riku: (c) survives D5 unless per-session worktrees become the default launch posture — that's the "fix you must remember" failure mode.

⚙️ Sage: Default-worktree-everything taxes the common single-session case (branch + diverge + merge-back) for a rare (n=1) race — the "observe before preventing" trap.

**Tobias:** Include the daemon-race fix in D5. `/meeting` should be clever enough to use worktrees for Class 1 agents. Any change to a repo other than the session's own project should always use a worktree.

### Item 2 — Cross-repo always-worktree rule + root-cause sharpening

🎛️ Orla: The daemon-race datapoint WAS a cross-repo case (zkm-session editing shared `~/.claude`). Worktree isolation of that edit would have hidden it from session B's committer.

⚙️ Sage: But mechanism ≠ `EnterWorktree` (that relocates whole session cwd, current-repo only). Cross-repo worktree = manual `git -C <repo> worktree add` → edit via path → `--no-ff` merge back → remove. Script-shaped.

✂️ Petra: Most cross-repo edits are one-line `~/.claude` tweaks. Worktree ceremony per one-liner is the prevention-without-evidence trap pointed at cross-repo.

😈 Riku: Cost yes, but the precondition is "another session's committer live on the same repo" — not edit size.

**Tobias (refines):** Easiest fix for one-liners — an "atomic commit only this patch" approach. Alternative: forbid direct `~/.claude` edits, require tools/skills that commit atomically.

🏗️ Archie (post-verification): git-diary-workflow ALREADY bans `git add -A`. The actual leak: Step 1b/1c derive their file list from `git -C ~/.claude status --porcelain`, which on a shared tree reflects ALL sessions' dirty files. B stages A's half-finished work "by name." Defect = staging from shared-tree status, not blunt add-all. `git commit -- <paths>` is plain porcelain; the lever is the *source of the path list*, not the commit verb.

⚙️ Sage: Deterministic source already exists — Stop hooks receive `transcript_path` with every Edit/Write record. A committer can derive "files THIS session touched" from the transcript. B's transcript never contains A's files → B cannot grab them.

🔩 Gil (new — git plumbing/object-model): Two independent problems: **integrity** (shared `.git/index` add→commit RMW is not atomic-as-a-unit) vs **attribution** (B must not commit A's files; serialization alone doesn't fix it since B staging from `git status` sees A's files). Lock-free plumbing recipe: `hash-object -w` → private `GIT_INDEX_FILE` → `read-tree HEAD` + `update-index --cacheinfo` → `write-tree` → `commit-tree -p HEAD` → `update-ref <new> <old>` (CAS, retry on failure). Solves both: B's tree = HEAD + only B's blobs (attribution); CAS guards the ref (integrity). Caveat: touches neither working tree nor shared index → stale-index footgun for porcelain users.

**Tobias (decisive correctness objection):** `commit-tree` does last-writer-wins per path with **no conflict detection by design** — a same-path concurrent edit is silently lost, not flagged. A worktree's `--no-ff` merge runs git's 3-way merge and surfaces the conflict. Silent loss is strictly worse than a surfaced conflict.

🔩 Gil: Conceded — plumbing recipe optimizes the wrong axis (lock-free speed at cost of conflict detection). Withdrawn.

😈 Riku: Residual: worktree isolates editing but merging back into the shared canonical checkout is still a write to that checkout's index+tree+ref. Race moved from edit-time to merge-time (smaller, conflict-detecting, not gone).

**Tobias:** Use a fixed per-repo flock other sessions wait on — that IS the coordination.

🔩 Gil: Two cheap levers. Integrity → fixed per-repo flock held only for fast commit+push (not during editing → waits are seconds). Attribution → stage from this session's own edit manifest, NEVER from `git status` (load-bearing even inside the lock).

🏗️ Archie: Minimal extension of `git-lock-push.sh` (already holds `.git-lock-push.lock` / `/tmp/claude-git-dotclaude.lock`): extend from wrapping pull+push to wrapping manifest-scoped stage+commit+pull+push. No worktree for ad-hoc one-liners.

🎛️ Orla: Same flock serves both topologies — ad-hoc serializes whole commit on it; dispatch uses worktrees for the parallel build phase, then main merges each branch `--no-ff` under the same flock. One per-repo commit/merge/push gate.

### Items 3 & 4 — /meeting dispatch, lifecycle, failure handling

🏗️ Archie: One Class 1 item → build in-session (flock+manifest). ≥3 disjoint-footprint items → D6 dispatcher (worktree-per-item, Sonnet builds+verifies, main merges `--no-ff` sequentially under flock). D5 ratification = D6 build-gate #1 satisfied.

⚙️ Sage: baseRef=`fresh` (origin/main) default for dispatch — clean base, no inherited uncommitted orchestrator state. `head` only when item depends on un-pushed local work. Cleanup via `ExitWorktree remove` (refuses if dirty) / Workflow auto-clean / `git worktree prune`. Naming `.claude/worktrees/<todo-item-id>`.

😈 Riku: Failure non-negotiable — `contract_met=false` or verify-fail → do NOT merge; leave branch unmerged, surface to user. A dropped failure looks identical to a completed item (the ledger-gap failure mode).

**Tobias:** Keep D6's 3-part build gate. baseRef = `fresh`.

## Decisions

- **D5.1 — Mechanism by topology, not one-size.** Worktree-per-item for deliberate parallelism (Class 1 dispatch, long-running multi-file cross-repo); fixed-flock + manifest-scoped commit for ad-hoc cross-repo one-liners. *Out of scope:* unconditional always-worktree on every cross-repo edit; plumbing/CAS atomic-commit (rejected — silent same-path loss).
- **D5.2 — Plumbing CAS rejected.** `commit-tree`+`update-ref` does last-writer-wins per path with no conflict detection → silent data loss on same-path concurrency. Worktree `--no-ff` merge preserves git 3-way conflict surfacing. *Out of scope:* any lock-free commit path that bypasses merge conflict detection.
- **D5.3 — Ad-hoc cross-repo = flock + manifest.** Extend `git-lock-push.sh` to wrap manifest-scoped stage+commit+pull+push under the existing per-repo flock. Integrity ← flock; attribution ← stage from this session's edit manifest, never `git status`. *Out of scope:* worktree for ad-hoc one-liners.
- **D5.4 — git-diary Step 1b/1c manifest fix.** Replace `git -C <repo> status --porcelain`-derived staging with this-session edit-manifest staging (ideally transcript-derived via Stop hook for determinism). This is the structural fix for the 2026-06-04 cross-session attribution race. *Out of scope:* changing project-repo Step 1 (already model-staged by name).
- **D5.5 — Dispatch merge-back = single-owner sequential `--no-ff` under flock.** Orchestrating session owns all merges; workers return branches; main merges each `--no-ff` in sequence under per-repo flock, pushes once. baseRef=`fresh`. Failure → do not merge, surface unmerged branch. Naming `.claude/worktrees/<todo-item-id>`; cleanup via ExitWorktree remove / Workflow auto-clean / prune. *Out of scope:* independent-session concurrent merge model (D5.6).
- **D5.6 — Independent-session flock'd merge-to-canonical = deferred.** Forward-flagged, NOT built — minimum evidence = a second cross-session race recurring after D5.3/D5.4 land. *Out of scope:* building model (b) now.
- **D5.7 — /meeting dispatch keeps D6's 3-part gate.** Single Class 1 item builds in-session; the worktree dispatcher stays gated on D6's three conditions. **D5 ratification satisfies D6 build-gate #1.** *Out of scope:* enabling the dispatcher now; single-item-worktree.

## Action items
- [ ] **Extend `git-lock-push.sh` to wrap manifest-scoped stage+commit** — `git-diary-workflow/git-lock-push.sh`. Move local stage+commit inside existing per-repo flock so the index RMW is atomic-as-a-unit. Contract: two concurrent sessions committing disjoint files to the same repo both land; neither commits the other's files; same-repo commits serialize. <!-- id:3e35 -->
- [ ] **git-diary Step 1b/1c: stage from session manifest, not `git status`** — `git-diary-workflow/SKILL.md` (+ optional Stop-hook to derive manifest from `transcript_path`). Contract: a session with another session's uncommitted files present in the shared tree commits ONLY its own touched files. <!-- id:d00e -->
- [ ] **Record worktree-dispatch spec + tick D6 build-gate #1** — update D6 TODO line / note: D5 ratified 2026-06-04; mechanism = worktree-per-item, baseRef=`fresh`, `--no-ff`, single-owner sequential merge under flock, naming `.claude/worktrees/<item-id>`, fail→don't-merge. Contract: D6 dispatcher build references this spec; gate #1 marked satisfied. <!-- id:14d7 -->
- [ ] **Forward-flag: independent-session flock'd merge-to-canonical** — deferred; build only if a second cross-session race recurs after the flock+manifest fixes land. Contract: a recorded recurrence opens the build. <!-- id:3558 -->
