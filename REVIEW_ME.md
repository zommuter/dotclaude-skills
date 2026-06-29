# Human review queue <!-- budget: 15 min -->

Judgment calls encoded in red tests — confirm or correct the interpretation.
Max ~10 open boxes; the reviewer prunes resolved ones each review turn.

(All prior boxes — the 8 confirmed 2026-06-12 + the 2026-06-21 flaky-test decision —
were resolved and pruned by the 2026-06-29 review turn.)

- [ ] inbox dead-letter routed:6976 → [dotclaude-skills] (surfaced by relay-doctor scan-routed,
  report-only): "git-lock-push dirty-tree guard refinement — ignore untracked runtime files
  (plans/, session-env/) + harness-owned tracked state (history.jsonl, .last-cleanup, sessions/)
  in the aa93 porcelain check so ~/.claude pushes through when only junk is dirty; design together
  with id:3558 worktree-per-session in one focused session — refuse only on genuine tracked-content
  WIP." Class-B design prose (surface-only per id:678e). Decide: ingest into TODO.md (mint id via
  `append.sh new-id`) or resolve the routed entry as obsolete.
- [ ] inbox dead-letter routed:4097 → [dotclaude-skills] (surfaced by relay-doctor scan-routed,
  report-only): "/meeting EnterPlanMode (skill step 3) propagates session-wide plan-mode to live
  BACKGROUND agents — they get forced read-only and stall asking 'shall I proceed?' instead of
  executing (observed: a relay executor mid-run during a meeting). Fix: detect live background
  agents (TaskList) before EnterPlanMode and warn/skip, OR accumulate the meeting transcript
  without a session-wide plan-mode." Class-B design prose (surface-only per id:678e). Decide:
  ingest into TODO.md or resolve as obsolete.
