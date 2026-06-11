---
name: meeting-cross
description: Deprecated alias — use /meeting --cross instead. Cross-project meeting: scan all registered projects' TODO.md files, surface the highest-priority item globally, and dispatch.
---

# Meeting-Cross — deprecated alias

Use `/meeting --cross` instead. This alias exists only during the transition period.

**Removal trigger:** delete this skill (dir + symlink) after `/meeting --cross` has been used successfully twice. See `docs/meeting-notes/2026-06-11-0950-meeting-cross-as-cross-switch.md`. <!-- id:4f5f -->

## At invocation

1. Perform canonical `/meeting` setup: run steps 1–7 in `~/.claude/skills/meeting/SKILL.md` (find root → metadata → git hygiene check → format spec → personas → discoveries → profile → broker). **Skip the `--cross` conditional at step 2 — this alias handles the cross path directly.**
2. Read `~/.claude/skills/meeting/cross-mode.md` and follow it for all project discovery, classification, dispatch, and routing-trail steps.
