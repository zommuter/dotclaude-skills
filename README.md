# dotclaude-skills

Public Claude Code skills by [@zommuter](https://github.com/zommuter).

## Skills

| Skill | Description |
|---|---|
| [meeting](meeting/) | Structured design meetings with named personas (Archie, Riku, Petra) |

## Publishing pattern

Each skill directory contains the **public-safe spec files** only. Personal accumulator files (`discoveries.md`, `user-profile.md`) are kept as local-only files in `~/.claude/skills/<skill>/` and never committed here.

The recommended install uses **per-file symlinks** (P2 pattern): `~/.claude/skills/<skill>/$f → ~/src/dotclaude-skills/<skill>/$f` for each spec file. This means the live skill *is* the published version — no manual sync, no drift.

See each skill's `README.md` for install instructions.

## Licence

MIT — do what you want, attribution appreciated.
