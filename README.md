# dotclaude-skills

Public Claude Code skills by [@zommuter](https://github.com/zommuter).

## Skills

| Skill | Description |
|---|---|
| [meeting](meeting/) | Structured design meetings with named personas (Archie, Riku, Petra); `--cross` mode scans all registered projects |
| [git-diary-workflow](git-diary-workflow/) | Commits, pushes, and appends a diary entry after every substantive prompt |
| [todo-update](todo-update/) | Updates TODO.md after every substantive prompt — mandatory alongside git-diary-workflow |
| [fables-turn](fables-turn/) | Reviewer side of the relay: autonomous pool (bare `/fables-turn`), handoff, and anti-gaming review modes |
| [fables-executor](fables-executor/) | Versioned executor contract loaded by Sonnet sessions working in relay-managed repos |
| [projects](projects/) | Personal project dashboard — recent activity, open task counts, prioritization |

## The fables relay

A strong reviewer model prepares repos (docs, roadmap, failing tests as the
spec) and audits finished work; cheap executor sessions grind the well-specified
items in between. **[docs/fables-relay.md](docs/fables-relay.md)** is the
user-facing guide: run modes, what every artifact means (ROADMAP.md,
RELAY_LOG.md, REVIEW_ME.md, `fable-ckpt-*` tags, relay.toml, RELAY_STATUS.md),
and what the human does between turns.

## Statusline & tools

- [statusline/](statusline/) — quota/cost/model statusline with pricing-window
  indicator and session token total (`statusline-command.sh`, reads JSON on stdin).
- [tools/](tools/) — `allowlist.py` (settings.json Bash-allowlist generator) and
  `ctx-budget.sh` (advisory SKILL.md token-budget audit).

## Hooks

Event hook scripts for Claude Code. See [hooks/README.md](hooks/README.md) for settings.json registration snippets.

| Hook | Description |
|---|---|
| [meeting-cost-logger.sh](hooks/README.md#meeting-cost-loggersh) | Stop hook: logs per-session turn/token counts and whether a meeting note was written |
| [parallel-edit-detector.py](hooks/README.md#parallel-edit-detectorpy) | Stop hook: detects committed file changes not explained by the session's tool calls |
| [notify-hook.linux-x11.sh](hooks/README.md#notify-hooklinux-x11sh) | Notification hook: desktop notification for permission prompts (XFCE/X11) |

## Install

```bash
git clone https://github.com/zommuter/dotclaude-skills.git ~/src/dotclaude-skills
cd ~/src/dotclaude-skills
make install            # all skills, hooks, and allowlist entries
make install-meeting    # one skill
make install-hooks      # hooks only
make help               # list available targets
```

`make install` calls `make install-allowlist` which merges the required `Bash(...)` entries into
`~/.claude/settings.json` (backup → `settings.json.bak`). The merge is idempotent: re-running
`make install-allowlist` adds nothing if all entries are already present. Use
`make print-allowlist` for a read-only preview (shows `+` for missing, `=` for existing).

See each skill's `README.md` for skill-specific notes (local-only files, etc.).  
See [hooks/README.md](hooks/README.md) for hook prerequisites and additional settings.json snippets.

## Publishing pattern

Each skill directory contains the **public-safe spec files** only. Personal accumulator files (`discoveries.md`, `user-profile.md`) are kept as local-only files in `~/.claude/skills/<skill>/` and never committed here.

The recommended install uses **per-file symlinks** (P2 pattern): `~/.claude/skills/<skill>/$f → ~/src/dotclaude-skills/<skill>/$f` for each spec file. This means the live skill *is* the published version — no manual sync, no drift.

See each skill's `README.md` for install instructions.

## Licence

MIT — do what you want, attribution appreciated.
