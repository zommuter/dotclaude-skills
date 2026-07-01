# Human review queue <!-- budget: 15 min -->

Judgment calls encoded in red tests — confirm or correct the interpretation.
Max ~10 open boxes; the reviewer prunes resolved ones each review turn.

(All prior boxes — the 8 confirmed 2026-06-12, the 2026-06-21 flaky-test decision,
and the two 2026-06-29 inbox dead-letters routed:6976/routed:4097 (ingested →
TODO id:319b / id:8567) — were resolved and pruned; latest prune by the
2026-07-01 fable catch-up review.)

- [x] id:8e3e — CONFIRMED + IMPLEMENTED 2026-07-01 (Fable orchestrator): fix direction
  independently re-derived by the bugfix child and implemented same night — relay-loop.js
  "Already up to date" ⇒ checkpoint at reviewed tip via new `ckpt-tag.sh -c`, never handback;
  suite 158 green (test_ckpt_tag_commit_target.sh). Empty review = free confirmation that the
  window is clean; it MUST close the window. Re-checkable: next zero-commit review should
  produce a ckpt, not a handback. Original finding: integrator "Duplicate dispatch" mislabel
  on a ZERO-COMMIT review branch
  (2026-07-01 20:36, run relay-20260701-202806-14640): the review child branched at the
  TRUE then-HEAD (33169ee, verified against commit timestamps — NOT a stale-state read),
  made zero commits (clean window), main advanced meanwhile (65ce4ea, an interactive
  session) → integrator saw tip-already-ancestor, handed back "Duplicate dispatch", and
  SKIPPED the checkpoint, so the audited window never closed and the next discovery
  re-dispatches a strong review. Promoted as ROADMAP id:8e3e [HARD — pool] (checkpoint
  the reviewed TIP, not main HEAD). Confirm the fix direction — esp. that an empty
  review should checkpoint at the branch tip rather than hand back.
- [x] id:0a3b — DONE (one-time correction) 2026-07-01: orchestrator set last_ckpt/last_strong_ckpt
  to relay-ckpt-20260701-2317 (this review's checkpoint), strong_model=claude-fable-5,
  fable_rechecked=2026-07-01, with a dated comment in relay.toml. The DURABLE fix (ckpt-tag.sh
  syncing relay.toml) remains open as ROADMAP id:0a3b [ROUTINE] + red spec. Original finding:
  relay.toml [repos.dotclaude-skills] last_ckpt/last_strong_ckpt stuck at
  relay-ckpt-20260701-1635 while tags 1948/2019/2110 exist: those three checkpoints were
  minted by supervised sessions via ckpt-tag.sh, which never writes relay.toml (only the
  pool integrator does, relay-loop.js:1426). Verified benign for discovery (gather reads
  git tags), but the id:e030 Fable-recheck queue misses out-of-pool strong checkpoints.
  Promoted as ROADMAP id:0a3b [ROUTINE] + red spec tests/test_ckpt_tag_toml.sh. The
  STALE VALUES THEMSELVES still need a one-time correction in ~/.config/relay/relay.toml
  (orchestrator's file — this review did not edit it): last_ckpt should be the latest
  real tag once this review is checkpointed.
- [ ] id:6e02 — LIVE-worktree sweep incident (2026-07-01 ~22:56): this review's own
  explicitly-created worktree + branch were deleted ~1 min after creation, mid-test-run,
  WHILE ~/.config/relay/claims/dotclaude-skills.json held a live claim (22:55:01). The
  child recovered (recreated + marker commit so tip≠main). No relay-loop was running
  (events end 20:45); reconcile log shows nothing at 22:5x — most consistent with an
  orchestrator-side cleanup treating a zero-commit branch (tip==main, `branch -d`-able)
  as an integrated leftover. Filed as TODO id:6e02 [HARD — meeting] (sweeps must honor
  claims; child setup should marker-commit first). Orchestrator: please confirm/deny
  running a worktree cleanup at ~22:56 so the finding pins the actual actor.
  ORCHESTRATOR ANSWER 2026-07-01: NOT the orchestrator (this session ran no cleanup at
  22:5x). Actor pinned by the bugfix child: run relay-20260701-225242-28925's dotclaude-skills
  integrator (dispatched 22:52:45, lease-refused handback ~22:56) applied its "tip-is-ancestor
  ⟹ integrated leftover" cleanup to a branch it didn't create, AFTER releasing the lease.
  Cleanup is now scoped to own-runId artifacts only (relay-loop.js, merged 2026-07-01); the
  remaining DESIGN CALL — destructive cleanup under-the-lease vs release-first (id:ebfb
  ordering) — is TODO id:6613 [HARD — meeting]. Box stays open only for that meeting call.
