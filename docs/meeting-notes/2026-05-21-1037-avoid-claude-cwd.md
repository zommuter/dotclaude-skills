# 2026-05-21 — Avoid `~/.claude/` as cwd (or accept the cwd-triggered prompt)?

**Started:** 2026-05-21 10:37
**Session:** 403af3b4-1e67-473b-a7e1-83e1b1f33e98
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime — project-standing)
**Topic:** Decide whether to avoid `~/.claude/` as cwd, accept the cwd-triggered "edit own settings" prompt, or codify a hybrid convention — closing the TODO deferred since 2026-05-10.

## Agenda
1. Post-migration reality: what genuine `~/.claude/`-cwd cases remain?
2. H3a vs H3b: does the cwd guard FORCE a prompt on every write, or only DECORATE prompts firing from allowlist misses?
3. Decide: (b) avoid cwd / (c) accept UX / (d) codify hybrid convention.

## Grounding facts
- `~/.claude/` is its own git repo (remote `fievel:src/claude.git`).
- `CLAUDE.md` and `settings.json` are real files, canonical home `~/.claude/`.
- `hooks/` files are symlinks into `~/src/dotclaude-skills/hooks/`.
- 4 meta-meeting notes live in `~/.claude/docs/meeting-notes/`.
- 2026-05-10-2200 confirmed H3: the harness detects cwd=`~/.claude/` and adds "option 2 (allow editing own settings)" to permission prompts.
- 2026-05-14 discovery: tilde allowlist patterns match absolute file_path args for Write/Edit (Bash is the rewrite exception).

## Discussion

### Round 1 — is the problem still live post-migration?

🏗️ **Archie:** The 2026-05-11 migration already routed skill work → dotclaude-skills and diary → claude-diary. This meeting runs from `~/src/dotclaude-skills/` — no prompt. Residual `~/.claude/`-cwd cases are narrow: editing `CLAUDE.md`/`settings.json`, committing the `~/.claude` repo, and 4 meta-notes. None strictly require cwd=`~/.claude/` — all editable via tilde/absolute paths; git via `git -C ~/.claude`.

⚙️ **Sage:** The unresolved sub-question from May: does H3 FORCE a prompt on every write (H3a) or only DECORATE prompts that already fire from an allowlist miss (H3b)?

😈 **Riku:** That sub-question is load-bearing. If H3b, fix is trivial (ensure targets are allowlisted). If H3a, allowlisting is futile and we choose (b) vs (c). Don't pick before knowing which world we're in.

✂️ **Petra:** Cost reality, unchanged: ~1–3 prompts/session, fast approval, migration shrank blast radius. The real question is whether this beats a one-line convention.

### Round 2 — H3a vs H3b and what gates the decision

🏗️ **Archie:** The 2026-05-10 amendment leans H3b — the triggering Write was a relative path against a tilde-absolute allowlist entry → allowlist miss → prompt → cwd-guard added option 2. Consistent with H3b, not proof.

😈 **Riku:** This time we run a controlled ~30-second probe — not a passive multi-week wait. From the current sibling cwd, attempt an allowlisted write to a real file inside `~/.claude/`. Silent → H3b. Prompts → H3a. Decisive and reversible.

⚙️ **Sage:** H3 itself splits: H3-target (guard fires because target file is inside `~/.claude/`) vs H3-cwd (fires because cwd is `~/.claude/`). Opposite fixes — the probe disambiguates both.

✂️ **Petra:** If H3b → "audit allowlist coverage," no policy needed. If H3a → (b) vs (c). Probe gates everything.

> *Tobias:* "Probe first, then branch."

### Round 3 — probe design + branch conventions

🏗️ **Archie:** Test 1 (this session): from cwd=`~/src/dotclaude-skills/`, Edit a real (non-symlink) allowlisted file in `~/.claude/` — e.g. `user-profile.md` (`Edit(~/.claude/skills/meeting/user-profile.md)` is in the allowlist). Silent → H3-cwd confirmed, migration convention is the answer. Prompts → H3-target, accept-as-UX forced for config files.

😈 **Riku:** Note: `settings.json` and `CLAUDE.md` have NO allowlist entries by design — those prompts are the guard working correctly and are NOT the target of this fix.

✂️ **Petra:** Both branches converge on a `CLAUDE.md` convention edit + closing TODO items 2 & 3. Branch A (cwd-based): "never launch Claude with cwd=`~/.claude/`." Branch B (target-based): "accept the guard, won't-fix-by-design."

## Probe execution

**Test 1:** Edit `~/.claude/skills/meeting/user-profile.md` (real file, allowlist-covered) from cwd=`~/src/dotclaude-skills/`.

**Result: SILENT** — no permission prompt fired.

**Interpretation:** The guard is **H3-cwd** (cwd-based), not H3-target. Editing `~/.claude/` files from a sibling cwd is clean when the path is allowlisted. Branch A selected.

Side-observation: `~/.claude/skills/meeting/format.md` and other P2 symlinks block at the *symlink layer* ("Refusing to write through symlink"), not the permissions layer — a distinct, pre-existing guard. Only real files in `~/.claude/` are reachable directly.

## Decisions

- **D1 — Branch A: cwd-based guard confirmed.** The "edit own settings" option fires when and only when cwd is `~/.claude/`. Allowlist coverage is effective from sibling cwds.
- **D2 — Convention in `~/.claude/CLAUDE.md`:** "Never launch Claude with cwd=`~/.claude/`. Edit `~/.claude/` files via tilde/absolute paths from a sibling cwd; use `git -C ~/.claude` for VCS." Added 2026-05-21.
- **D3 — `settings.json`/`CLAUDE.md` prompts are the guard working as intended** and are NOT a target of this fix. Both remain un-allowlisted.
- **D4 — Close TODO items 2 and 3** in `~/src/dotclaude-skills/TODO.md`. Both items addressed by D1–D2.

Out of scope: removing the guard; allowlisting `settings.json`/`CLAUDE.md`; rerouting meta-notes to a different repo.

## Action items

- [x] **AI-1 — Probe** — ran in-session; result: silent (H3-cwd confirmed).
- [x] **AI-2 — `~/.claude/CLAUDE.md` convention** — "~/.claude/ cwd convention" paragraph added under Git sync strategy.
- [ ] **AI-3 — Close TODO items 2 and 3** in `~/src/dotclaude-skills/TODO.md`.
