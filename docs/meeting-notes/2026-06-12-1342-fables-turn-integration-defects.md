# 2026-06-12 — fables-turn integration defects (id:821c)

**Started:** 2026-06-12 13:42
**Session:** f4915923-d644-460f-afa6-6e659deead1a
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), 🔩 Gil (git plumbing, new)
**Topic:** Fix three integration defects found in the 2026-06-12 fables-turn dotclaude-skills pilot.

🔩 **Gil** — git object-model / plumbing lens: rebase/merge topology, ref/tag reachability, CAS, concurrent-commit integrity. Designed the D5 worktree-merge model; natural owner for the rebase-orphans-tag question.

## Surfaced discoveries
- [2026-05-10 .claude] `git-lock-push.sh` accepts an optional `REPO_PATH` positional arg — relevant: the script is the repo-wide push serializer; any change to it affects every project's post-prompt push.

## Agenda
1. Defect (a) — `pull --rebase --autostash` orphans the `fable-ckpt-*` tag and flattens the `--no-ff` merge. Fix in repo-wide `git-lock-push.sh` or special-case the relay path?
2. Defect (b) — `git push <remote> <tag>` blocked by the auto-mode permission classifier. `--follow-tags` vs new allowlist entry?
3. Defect (c) — `ckpt-tag.sh` takes a path; SKILL.md invariant 5 writes `<repo>`. Doc fix vs accept-both.

## Discussion

**Item 1:** 🔩 Gil distinguished two distinct failures — topology loss (`--rebase` drops merge commits without `--rebase-merges`) and tag orphaning (rebase rewrites SHAs regardless of merge-preservation, so the annotated tag points at a stale SHA). The only way the tag survives is if no rewrite occurs: a fast-forward. 😈 Riku flagged blast radius: `git-lock-push.sh` is the repo-wide serializer; flipping the global default to `--ff-only` regresses parallel-session reconciliation on `main` for all projects. ✂️ Petra resolved: opt-in flag, not a default change — one new getopts branch, zero fleet blast radius. On real divergence: loud failure (committed locally, same non-fatal contract as flock-timeout). 🔩 Gil confirmed that ff-only plus reorder (push-then-tag) were the two shapes; ff-only is simpler and already surfaces divergence loudly, making reorder's extra robustness moot.

**Item 2:** 🔩 Gil: `--follow-tags` pushes annotated, reachable tags only. After Decision 1's ff-only push the checkpoint tag sits on a commit on the branch (reachable ✓), so it rides along with the existing push — no separate command, no new allowlist entry. ✂️ Petra: second consumer confirmed — bump-and-tag `vX.Y.Z` version tags currently need a manual push; `--follow-tags` closes that gap fleet-wide, satisfying N=2 for touching the global script. 😈 Riku: blast-radius check — `--follow-tags` is conservative (annotated + reachable only); no repo in the fleet deliberately keeps annotated tags local. Approved.

**Item 3:** All personas agreed: `ckpt-tag.sh` is already correctly path-only (`git -C "$repo"`; usage string says `<repo-path>`). The only inconsistency is SKILL.md. Accept-both (name→path via relay.toml inside the script) is speculative flexibility for one caller that already passes a path — strictly more surface to break. Doc fix only.

## Decisions

- **(a)** Add opt-in `--ff-only` mode to `git-diary-workflow/git-lock-push.sh` (new getopts flag). When set, run `git pull --ff-only $target` instead of `git pull --rebase --autostash $target` — no SHA rewrite, merge topology preserved, annotated tag stays reachable. On divergence: loud failure, work committed locally (same non-fatal contract as flock-timeout). Relay path passes this flag; global default unchanged. **Out of scope:** no fleet-wide default change.
- **(b)** Add `--follow-tags` to the `git push` invocation(s) in `git-diary-workflow/git-lock-push.sh`. Annotated, reachable tags ride along with the branch push. Composes with (a): ff-only keeps the tag reachable. Bonus: auto-pushes `vX.Y.Z` version tags fleet-wide. **Out of scope:** no new allowlist entry; lightweight/unreachable tags never pushed.
- **(c)** Doc-only: change `ckpt-tag.sh <repo>` to `ckpt-tag.sh <repo-path>` in `fables-turn/SKILL.md` invariant 5 and any matching echo in `references/`. No code change to `ckpt-tag.sh`. **Out of scope:** accept-both in ckpt-tag.sh.

## Action items

- [ ] Add `--ff-only` getopts flag to `git-diary-workflow/git-lock-push.sh`. <!-- id:95b0 -->
- [ ] Add `--follow-tags` to push line(s) in `git-diary-workflow/git-lock-push.sh`. <!-- id:a827 -->
- [ ] Update `fables-turn/SKILL.md` invariant 5 (ff-only flag + `<repo-path>`) and `fables-turn/references/conventions.md` if it echoes the push/tag sequence. <!-- id:05cb -->
- [ ] Add scratch-repo test `tests/test_git_lock_push_ff_only.sh`: (1) ff-only + unchanged remote → tag survives on-branch; (2) ff-only + diverged remote → loud failure; (3) `--follow-tags` → annotated tag reaches remote. <!-- id:ed1a -->
