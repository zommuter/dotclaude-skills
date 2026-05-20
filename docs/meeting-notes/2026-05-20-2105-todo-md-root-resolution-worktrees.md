# 2026-05-20 — TODO.md root resolution: prevent autonomous upward traversal

**Started:** 2026-05-20 21:05
**Session:** 84a25382-a0f2-4d46-82ec-87a72e467b59
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime — standing)
**Topic:** When `/meeting`, `/meeting-live`, or `/todo-update` is invoked from a linked git worktree placed as a subdir of a parent repo, the model autonomously reads the parent's TODO.md instead of the worktree-local one.

## Agenda

1. Reproduce: what exactly does each skill do today in `~/src/meeting-rpg/wt/renderer-tauri/`?
2. What is the actual failure mode the user observed?
3. Why does the model walk up, and how do we stop it?
4. Minimum correct fix.

## Discussion

### Agenda 1 — Configuration audit

Live probe (`git rev-parse --show-toplevel` from `wt/renderer-tauri`) confirmed: for a proper linked worktree (`wt/renderer-tauri/.git` is a file → `meeting-rpg/.git/worktrees/...`), `--show-toplevel` correctly returns the **worktree path** — not the parent. So the skill's root-detection is not the bug.

Code-path review (Explore agent): `meeting/SKILL.md` and `meeting-live/SKILL.md` use `<root>` from `--show-toplevel`; `todo-update/SKILL.md` uses bare CWD-relative `TODO.md`. Neither has a "do not walk up" guard. `orphan-scan.sh` and `archive-done.sh` also use `--show-toplevel` but not for reads that would reach outside the CWD scope.

Four plausible failure scenarios identified: A (proper worktree, `--show-toplevel` correct), B (plain subdir, `--show-toplevel` returns parent), C (deep subdir of worktree), D (model autonomous upward traversal).

### Agenda 2 — User disambiguation

User identified **Scenario D**: model walks up autonomously, even when the worktree-local TODO.md is populated, but possibly has an all-done `## Current`. Fallback decision: **hard-fail + ask user** — no autonomous walking, no silent auto-create on the read path.

### Agenda 3 — Root cause of autonomous traversal

`meeting-rpg/wt/renderer-tauri/TODO.md:3` contains: `> Subset of \`../../TODO.md\` for this worktree only.`

This in-file prose reference is what invites the model upward — it's not a hallucination, the file's own text tells the model the parent has "more." The model is being "helpful" by following it, especially when `## Current` is empty/all-done.

Mitigation layers considered:
1. **Prose hardening in SKILL.md** — explicit "do NOT traverse upward; local is authoritative; empty Current is valid terminal state." ← chosen (all three skills).
2. Script-level guard in helpers — doesn't catch model→Read direct calls; N=2 not met. Out of scope.
3. Convention rule banning upward refs in worktree TODO.md — doesn't fix bug, out of scope.

## Decisions

- **D1**: All three skills (`meeting/SKILL.md`, `meeting-live/SKILL.md`, `todo-update/SKILL.md`) gain an explicit "Scope discipline" paragraph at the point where TODO.md is referenced. Three load-bearing clauses: (a) local TODO.md is sole authority; (b) never read/write any other TODO.md, even textually referenced ones; (c) empty/all-done Current is a valid terminal state — stop, don't look elsewhere. *Out of scope:* script guards, convention rules.
- **D2**: `meeting-live/SKILL.md` stays a real file (not symlinked to canonical). Edit in parallel. WIP-sibling status preserved.
- **D3**: Missing-file behaviour for `/meeting`: report missing and ask user — do not auto-create. (`/todo-update` retains its existing Step 1 create path but gains the "do not seed from parent" clause.) *Out of scope:* changing /todo-update's create behaviour.
- **D4**: No edit to `git-diary-workflow` — delegates to /todo-update, which D1 covers.

## Action items

- [ ] AI-1: ✅ Added scope-discipline paragraph to `meeting/SKILL.md` at no-arg Step 1 and Step 5b. — see this note
- [ ] AI-2: ✅ Same in `meeting-live/SKILL.md`. — see this note
- [ ] AI-3: ✅ Adapted paragraph (CWD framing) in `todo-update/SKILL.md` at Step 1. — see this note
- [ ] AI-4: After ≥1 live `/meeting` run from a `meeting-rpg` worktree, log whether autonomous upward traversal recurs. If yes, escalate to D5 follow-up (mechanical guard). — see ~/src/dotclaude-skills/TODO.md
