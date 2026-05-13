---
name: projects
description: Show the personal project dashboard — recent activity, open task counts, prioritization. Trigger when asked about project status, what to work on next, or which projects have open tasks. Keywords: projects, dashboard, proj, overview, TODO, prioritize, what should I work on.
---

# Projects skill

Surfaces the `proj` dashboard inside a Claude Code session.

## Usage

Run with no arguments to show the current dashboard:

```
/projects
```

Run with `refresh` to re-scan all projects first:

```
/projects refresh
```

## Skill instructions (Claude Code)

1. Check if `proj` is on PATH: run `which proj`. If not found, suggest `uv tool install --editable ~/src/project_manager`.
2. If the argument is `refresh` (or `refresh --write`): run `proj refresh --write` and report how many projects were scanned.
3. Otherwise: run `proj show` and present the output to the user.
4. Offer to help pick a project to work on: "Want me to `cd` into the top-priority project? Run `cd \"$(proj pick)\"`."

## Notes

- Cache lives at `~/.cache/project_manager/state.json`. If it looks stale (header says "scanned Xh ago"), suggest `proj refresh`.
- `PROJECTS.md` in `~/src/project_manager/PROJECTS.md` is the committed markdown snapshot — useful for cross-machine reads.
- To pause a project: edit `~/.config/project_manager/include.toml`, set `paused = true`.
