# 2026-05-11 — Move diary skill and scripts into dotclaude-skills

**Started:** 2026-05-11 15:20
**Session:** ce704429-080f-4613-8ad6-616c45fcf74f
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime — project-standing)
**Topic:** Publish `git-diary-workflow/SKILL.md`, `git-lock-push.sh`, and `diary-append.sh` into `~/src/dotclaude-skills/` using the established P2 symlink pattern.

## Agenda

1. Scope: which files move?
2. Layout: where in dotclaude-skills?
3. Sync mechanism: P2 symlinks
4. Caller reference updates
5. Allowlist deltas

## Discussion

### Item 1 — Scope

Candidates: (a) SKILL.md, (b) git-lock-push.sh (general-purpose, `REPO_PATH` arg confirms no claude-diary coupling), (c) diary-append.sh (hardcodes `DIARY_DIR` but is parameterisable).

Personas recommended (a)+(b) only — diary-append.sh is coupled to DIARY.md. User overrode: all three. Consistent with profile *Scope tolerance* and *Drift aversion* — moving only two files leaves SKILL.md with a `~/src/claude-diary/...` reference that looks like an oversight.

**Decision:** Move all three. Parameterise diary-append.sh:24 to `DIARY_DIR="${DIARY_REPO_DIR:-$HOME/src/claude-diary}"`.

### Item 2 — Layout

Three options: (A) bundle in `git-diary-workflow/` subdir, (B) shared `bin/` at repo root, (C) two skill subdirs.

All four personas converged on (A) — matches `meeting/` precedent (SKILL.md siblings: append.sh, cost-of.sh). User raised: "would git-lock-push be worth upgrading to an actual skill?" Personas: no — a SKILL.md for it would be `--help` text, not a skill; adding one creates a fourth doc location for "how to use git-lock-push" alongside the script header, SKILL.md usage, and CLAUDE.md mention.

**Decision:** Bundle all three in `git-diary-workflow/`. `git-lock-push.sh` is a helper, not a skill.

### Item 3 — Sync mechanism

P2 per-file symlinks from `~/.claude/skills/git-diary-workflow/{SKILL.md,git-lock-push.sh,diary-append.sh}` → `~/src/dotclaude-skills/git-diary-workflow/$same`. Old files at `~/src/claude-diary/{git-lock-push,diary-append}.sh` deleted — no shim, no deprecation pointer (drift aversion).

### Item 4 — Caller reference updates

All four SKILL.md hardcoded paths updated (L42/L77/L104/L121) plus `~/.claude/CLAUDE.md` "git sync strategy" section. All references now use `~/.claude/skills/git-diary-workflow/` as the install path. Prose gotcha in SKILL.md de-hardcoded too.

### Item 5 — Allowlist

**Removed:** `Bash(~/src/claude-diary/diary-append.sh -m * -p * -f .diary-entry.*)` and `Bash(~/src/claude-diary/git-lock-push.sh ~/.claude)`.

**Added:**
- `Bash(~/.claude/skills/git-diary-workflow/diary-append.sh -m * -p * -f .diary-entry.*)`
- `Bash(~/.claude/skills/git-diary-workflow/git-lock-push.sh)` — bare invocation (Step 1)
- `Bash(~/.claude/skills/git-diary-workflow/git-lock-push.sh *)` — with any arg (covers Step 1b `~/.claude`, Step 1c `~/src/dotclaude-skills`, any project)

## Decisions

1. All three files moved to `~/src/dotclaude-skills/git-diary-workflow/`.
2. `diary-append.sh:24` parameterised with `DIARY_DIR="${DIARY_REPO_DIR:-$HOME/src/claude-diary}"`.
3. P2 symlinks in place; old claude-diary copies deleted.
4. All five caller references updated to `~/.claude/skills/git-diary-workflow/`.
5. Allowlist updated: old claude-diary entries removed, new skill-install-path entries added.
6. `/add-dir ~/src/dotclaude-skills` (dotclaude-skills git write allowlist) deferred — remains open TODO.
7. Out of scope: standalone git-lock-push skill, README cross-reference, tagging.

## Action items

- [x] Create `~/src/dotclaude-skills/git-diary-workflow/` with SKILL.md, git-lock-push.sh, diary-append.sh.
- [x] Parameterise diary-append.sh:24.
- [x] Edit SKILL.md — replace all `~/src/claude-diary/` script references with `~/.claude/skills/git-diary-workflow/`.
- [x] P2 symlinks from `~/.claude/skills/git-diary-workflow/{SKILL.md,git-lock-push.sh,diary-append.sh}`.
- [x] Delete `~/src/claude-diary/{git-lock-push,diary-append}.sh`.
- [x] Update `~/.claude/CLAUDE.md` git sync strategy reference.
- [x] Update `~/.claude/settings.json` allowlist.
- [ ] Update TODO.md (this session).
- [ ] End-to-end verification: diary-append.sh still writes to `~/src/claude-diary/DIARY.md` (confirmed by this session's diary step).
