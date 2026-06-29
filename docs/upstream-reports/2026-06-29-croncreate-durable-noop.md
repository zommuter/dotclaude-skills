# Bug report draft — `CronCreate { durable: true }` is a no-op (still session-only)

**Status:** FILED 2026-06-29 → https://github.com/anthropics/claude-code/issues/72238 (relay TODO id:0994)
**Reproduced:** 2026-06-29 on Claude Code **2.1.195**, Linux x86_64 (Manjaro).

---

## Title

`CronCreate { durable: true }` is silently session-only — the `durable` flag does not persist the job (contradicts the tool's own description)

## Summary

The `CronCreate` tool documents `durable: true` as: *"persist to `.claude/scheduled_tasks.json`
and survive restarts."* In practice the flag is a no-op: a job created with
`durable: true, recurring: true` is reported as **session-only**, nothing is written to
`.claude/scheduled_tasks.json`, and the job dies when the Claude session ends. The tool's
**description and its behavior disagree**, so a caller that relies on durability to survive a
session/host kill gets exactly the failure the flag is meant to prevent — silently.

## Steps to reproduce

1. In a Claude Code session, call:
   ```
   CronCreate {
     cron: "37 4 * * *",
     prompt: "test",
     recurring: true,
     durable: true
   }
   ```
2. Observe the tool result.
3. `CronList`.
4. Check for `~/.claude/scheduled_tasks.json`.

## Actual behavior

- CronCreate returns:
  > Scheduled recurring job 008deb61 (Every day at 4:37 AM). **Session-only (not written to
  > disk, dies when Claude exits).** Auto-expires after 7 days. Use CronDelete to cancel sooner.
- `CronList` shows the job tagged **`[session-only]`**.
- `~/.claude/scheduled_tasks.json` **does not exist** (no file is created).

## Expected behavior

Per the tool description, `durable: true` should persist the job to
`.claude/scheduled_tasks.json` so it survives a session/process restart — OR, if durable
scheduling is not actually supported in this build, the tool should:

- **reject** `durable: true` with a clear error, and
- have its description amended to not advertise persistence,

so callers are not silently downgraded to session-only.

## Impact / why it matters

Durable scheduling is the natural primitive for an **outage-resilient local automation loop**:
an OS-independent way to have Claude re-run a prompt on a schedule that survives a session kill
(e.g. an overnight unattended job that died on a transient API error and needs restarting). With
`durable` a no-op, the only session-kill-surviving option is an external OS scheduler
(systemd `--user` timer / cron) running `claude -p`, which then hits the non-interactive
permission wall. The silent downgrade means a user who explicitly asked for durability believes
they have outage resilience when they do not.

## Suggested fix (either is fine)

1. Implement persistence: write durable jobs to `.claude/scheduled_tasks.json` and reload them
   on startup; OR
2. If unsupported in this build, make `durable: true` an explicit error and remove the
   persistence claim from the tool description (truth-in-advertising).

## Notes

- Cross-checked: the same no-op was first observed 2026-06-22 on an earlier build; still present
  on 2.1.195. The mismatch with the **current** tool description (which now explicitly mentions
  `.claude/scheduled_tasks.json`) suggests the description was updated ahead of / without the
  implementation.
