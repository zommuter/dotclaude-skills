# 2026-05-14 — Class 1 sweep + memory-write probe

**Started:** 2026-05-14 19:25
**Session:** 8e519cbe-3ce5-4db4-b28b-84d50a340d9d
**Mode:** Class 2 planning record (no meeting was held — plan-mode output)
**Topic:** Close stale Class 1 items; empirically test whether memory-path Write calls trigger a permission prompt.

## Context

No-arg `/meeting` invocation. All Class 1 items found to be already done but unchecked in TODO.md:
- **AI-1/3/4/5** — hooks versioning complete (`hooks/` dir, README.md, Makefile install-hooks target all present).
- **S4** — todo-update migration complete (`dotclaude-skills/todo-update/` with SKILL.md + README.md + archive-done.sh; `~/.claude/skills/todo-update/SKILL.md` symlinked).

Three orphans from orphan-scan not in TODO.md:
- AI-3 (rename notify-hook.sh) — already done, never tracked.
- AI-8 (post-symlink verify) — cost-log confirmed; notify-send unverified.
- Discoveries γ-class amendment — already appended in a prior session (false positive).

Class 2 item dispatched: "Investigate: built-in update project memory mechanism" — test whether a Write to an absolute memory path fires a permission prompt, given allowlist has only tilde-prefixed entry `Write(~/.claude/projects/*/memory/*.md)`.

## Plan

1. Close AI-1/3/4/5 and S4 in TODO.md; add AI-3 (done) and AI-8 (partial) as tracked items.
2. Empirical probe: Write `_probe.md` to `/home/tobias/.claude/projects/-home-tobias-src-dotclaude-skills/memory/`; observe whether permission prompt fires.
3. Outcome A (no prompt) → close TODO item, append discovery documenting the distinction.
4. Outcome B (prompt fires) → add absolute-path allowlist entries to settings.json.

## Implementation findings

**Outcome A** — no prompt fired. The probe write completed immediately without interruption.

This means: tilde allowlist entries (`Write(~/.claude/...)`) DO match absolute `file_path` parameters for the Write/Edit tools. The prior 2026-05-10 finding ("silently miss when file_path is absolute") was Bash-specific — Bash command strings are rewritten to cwd-relative form before matching; Write/Edit tool `file_path` parameters undergo tilde-expansion instead.

Implication: the permission prompt the user previously observed during memory updates was from the `git -C ~/.claude add/commit` step in git-diary-workflow, not the memory Write call itself.

## Decisions

- **No dedicated memory update tool exists** — exhaustive ToolSearch confirmed; Write/Edit is the correct path.
- **Tilde allowlist entries work for Write/Edit** — no absolute-path variants needed for memory paths.
- **Git-commit step for memory-only changes deferred** — the observed prompt came from git, not Write. A separate investigation is warranted only if the git-commit step continues to cause friction (it may not be running for memory updates at all, depending on how git-diary-workflow is triggered).
- Out of scope: any change to git-diary-workflow; cwd-relative allowlist patterns.

## Action items

- [x] Close AI-1/3/4/5, S4 in TODO.md — done this session.
- [x] Add AI-3 (done), AI-8 (partial notify-send) to TODO.md — done this session.
- [x] Close "Investigate project memory" TODO item — done this session.
- [x] Append discovery (Write/Edit tilde vs Bash cwd-relative distinction) — done via `append.sh`.
