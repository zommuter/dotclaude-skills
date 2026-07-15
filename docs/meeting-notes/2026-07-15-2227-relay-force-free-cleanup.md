# Make relay worktree/branch cleanup force-free (+ `rm -f` fossils, `git stash drop`)

**Started:** 2026-07-15 22:27
**Session:** cb877143-e282-440b-bc91-cd5ac20d389d
**Chair:** Zommuter
**Attendees:** Zommuter (chair), 🔩 Gil (git plumbing / reflog semantics), 🎛️ Orla (worktree isolation / orchestration), 😈 Riku (devil's advocate), ✂️ Petra (scope)
**Mode:** design meeting → same-session implementation (apex/Opus)

## Context

The user installed a strict destructive-op guardrail (`docs/destructive-op-guardrail.md`, 2026-07-15) that soft-denies / prompts on `rm -f`, `git … --force`, `git reset --hard`, `git restore`, `git checkout -- <path>`, `git clean -f`, `git branch -D`. The relay pool's serialized integrator + reconcile still ran `git worktree remove --force` and `git branch -D`; under the guardrail those are denied → worktrees never removed → orphaned worktrees + branches accumulate every run (TODO id:373e). Two adjacent fossils surfaced during discussion: cargo-cult `rm -f` on single files (no `rm -i` alias exists — likely a former-alias fossil), and `git stash drop`/`clear` missing from the guardrail's destructive-non-force family despite `clean-tree-gate.sh` naming "git stash+drop" as an id:aa93 destruction mechanism.

## Empirical findings (verified, throwaway repos)

- `git worktree remove` (no `--force`) **removes gitignored untracked files cleanly** — they do NOT block. So gitignore hygiene fully dissolves the `__pycache__`/`.pyc`/build-residue case.
- It **refuses** on a non-ignored untracked file (real new source) or a tracked-modified file (e.g. a regenerated `uv.lock`). Both are the correct "surface + leave / commit-it" cases.

## Decisions (D1–D7, ratified by chair)

- **D1** — Force-free retire: attempt plain `git worktree remove` (no `--force`). Dirty/unremovable → **surface it and leave it on disk** for a supervised reconcile / human; automation NEVER sweeps, stashes, cleans, or forces un-inspected work (the chair explicitly rejected an interim `git stash -u` sweep — "don't accumulate stash instead"). Only auto-cleanup: `git worktree prune` for an already-deleted worktree dir.
- **D2** — `git branch -D` → `git branch -d`; on refusal (unmerged) → orphan-park (`branch -m … relay/orphan/<bn>`, keep the ref, id:a4e9), never force-delete. Branch step runs only after a successful worktree removal.
- **D3** — One tested single-target helper `relay/scripts/worktree-retire.sh` (honours id:6e02 scope — no globbing/discovery), called from reconcile's reap+park loops; the `relay-loop.js` integrator prompt (step 5) rewritten to call it, removing the "--force is required and safe" instruction to the agent (the prompt was itself a force site).
- **D4** — Irreducible residual surfaced + left, never auto-forced; a human-only confirm-gated force escape hatch is DEFERRED (build only if a real case needs it; `force-push.sh` is the model).
- **D5** — Executor contract gains a **clean-worktree exit gate** (rule 5b, contract bumped v7→v8): the worktree must be clean at exit, reached by *committing* real work (incl. regenerated lockfiles) or *gitignoring* throwaway — NEVER by reverting/`checkout --`/`stash drop`/`reset --hard`/`clean` (that is gaming, caught by `/relay review`'s re-derive + test re-run; named explicitly in `review.md` §2b check 5). A dirty exit = incomplete → handback. This makes D1's "surface + leave" a genuine-breakage exception, not a per-run event.
- **D6** — De-cargo-cult single-file `rm -f` (fossil of a former `rm -i` alias; none exists now). Fixed the guardrail-tripping `rm -f "$manifest"` in `git-diary-workflow/SKILL.md` (a *direct* Bash call Claude makes each diary run), swept ~all single-file `rm -f` sites in the skill/tool tree (idiom: known-exists → `rm --`; optional → `[ -e f ] && rm -- f`; genuine ENOENT-glob case → `# force-ok:` annotation), and added a regression guard `tools/check-no-bare-rm-f.sh` + `tests/test_no_bare_rm_f.sh` (flags `rm` with `f`-not-`r`; `# force-ok:` escape; recursive `rm -rf` mktemp-dir traps exempt), mirroring the swallow lint.
- **D7** — Forbid `git stash drop` / `git stash clear` (discard saved work, only unreferenced-reflog recovery). Added to the guardrail's destructive-non-force family + named in the D5 anti-gaming check. `stash push`/`save`/`pop`/`apply` untouched. Grep-confirmed no automation runs `git stash`. Settings-pattern install rides id:98fc.

## Action items

- Force-free worktree/branch cleanup shipped (D1–D5) — `worktree-retire.sh`, reconcile + integrator wired, executor contract v8 clean-worktree exit gate, review anti-gaming check. <!-- id:373e -->
- `rm -f` de-cargo-cult sweep + `check-no-bare-rm-f.sh` regression lint (D6) — within id:373e's "audit all scripts for `-f`" scope.
- Guardrail doc extended with `git stash drop`/`clear` (D7); wiring those `permissions.ask`/`soft_deny` patterns into `make install` remains → routed to id:98fc.
- **PROPOSED (universal, approval-gated):** a global `~/.claude/CLAUDE.md` one-liner preferring `rm -- <file>` over `rm -f` and treating `git stash drop`/`clear` as destructive.

## Related

`docs/destructive-op-guardrail.md`, id:98fc (guardrail install target), id:a4e9 (orphan-park), id:6e02 (single-target cleanup scope), id:aa93 (clean-tree-gate / foreign-dirty destruction), `force-push.sh` (confirm-gate model).
