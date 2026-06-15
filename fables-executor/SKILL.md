---
name: fables-executor
description: Deprecated alias — use /relay executor instead. The lean executor contract was merged into the relay skill and now loads via /relay executor.
---

# fables-executor — deprecated alias

**DEPRECATED: renamed + merged.** Use `/relay executor` instead. The 5-rule executor
contract was merged into the `relay` skill and now lives at
`~/.claude/skills/relay/references/executor-contract.md` (loaded by `/relay executor`).
This alias exists only so in-flight executor sessions and old `## Relay contract`
pointers (`<!-- fables-executor contract v2 -->`) don't break during the transition.

If you are an executor session: load `/relay executor` (i.e. read
`~/.claude/skills/relay/references/executor-contract.md`) and follow its rules exactly.

The contract version was bumped to `<!-- relay-executor contract v3 -->` by the rename.
Stale v2 pointers in managed repos auto-migrate the next time each repo is reviewed.
See TODO id:1cb4 for the rename rationale.

**Removal trigger:** delete this alias (dir + symlink) once invocations/cron/pointers
have migrated to `/relay executor`.
