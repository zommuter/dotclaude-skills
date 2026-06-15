---
name: fables-turn
description: Deprecated alias — use /relay instead. Renamed from fables-turn to relay (model-agnostic; Opus is apex, Fable an optional bonus). The relay handoff/review/human orchestrator now lives at /relay.
---

# fables-turn — deprecated alias

**DEPRECATED: renamed.** Use `/relay` instead (the relay orchestrator: `handoff` /
`review` / `human` modes, plus the autonomous default pool). This alias exists only so
in-flight invocations, cron jobs, and old pointers don't break during the transition.

Forward intent to `/relay` with the same arguments:

- `/fables-turn` → `/relay`
- `/fables-turn handoff …` → `/relay handoff …`
- `/fables-turn review …` → `/relay review …`
- `/fables-turn human …` → `/relay human …`

Load `~/.claude/skills/relay/SKILL.md` and follow it. See TODO id:1cb4 for the rename
rationale (Fable is no longer the apex tier — Opus is — so "fables" is a misnomer;
"relay" matches relay.toml / RELAY_LOG.md / relay-loop.js / RELAY_STATUS.md).

**Removal trigger:** delete this alias (dir + symlink) once invocations/cron/pointers
have migrated to `/relay`.
