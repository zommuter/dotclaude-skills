# Strong-model audit — Run 21 (2026-06-19-2155)

ROADMAP id:401c (recurring strong-model audit). Strong-execute child, model
`claude-opus-4-8`, run `relay-20260619-191539-21573`.

## Window

First-seen change since Run 20's own audit commit `39592e8`
(`39592e8..HEAD`). `git diff --name-only 39592e8..HEAD`:

- `RELAY_LOG.md` — the Run 20 strong-execute checkpoint paragraph + the
  review-mode `relay-20260619-191539` ledger-only checkpoint.
- `TODO.md` — two newly-minted design items: id:81cb (statusline writes a
  per-session model-readable ctx/cost/quota state file) and id:daf0
  (screenshots of skills in action + README refresh, root + per-skill), plus
  the new `## docs & presentation` section header.

`git diff --name-only 39592e8..HEAD -- '*.sh' '*.py' '*.js'` is **EMPTY**.

## Verdict: clean — LEDGER-ONLY window (Runs 11/12/16/17/18/19/20 class)

### Pass 1 — Code review
No code, scripts, or Python in the window. No correctness/quoting/race/edge-case
surface to review.

### Pass 2 — Security audit
No new code at any system boundary. No injection/path/secrets/permission surface
introduced. The two new TODO items are design specs (not yet code); both are
purely-local, additive sketches (a `/tmp` per-session JSON write keyed by
`.session_id`; committed `docs/img/` screenshots) — security review applies when
they are built, not as ledger entries. id:daf0 itself names the relevant guard
(design-q (b): "avoid leaking private data in captures — scrub or use a demo
fixture"), so the privacy hazard is already flagged for the build pass.

### Pass 3 — Design coherence
- **New items internally sound.** id:81cb correctly observes the statusline
  receives the live `context_window.*` object on stdin but the model never sees
  it, and proposes a session-id-keyed state file — the `.session_id`/`$CLAUDE_SESSION_ID`
  key both sides agree on is correct (the statusline today parses only
  `.transcript_path`). No contradiction with the existing `/tmp/claude-usage-*`
  cache pattern it cites. id:daf0 (docs/screenshots) is a coherent docs-pass spec;
  its per-skill README-vs-SKILL.md boundary note is consistent with the repo's
  CLAUDE.md = config-root convention.
- **Cross-ledger coherent.** 0 open ROUTINE; 3 executable HARD in ROADMAP —
  dba3/401c/3346; the 4th `[ ]` HARD line de4e is the DEFERRED distributed-orchestrator
  design entry, not executable. All three executable HARD ids are `[ ]` in BOTH
  ROADMAP and TODO. The id:d5e0 summary line agrees (Run 17's drift fix — dropping
  the CLOSED id:10c0, adding id:dba3 — still holds).
- **One coherence drift fixed inline (Run 4/8/17 class).** The TODO id:401c MIRROR
  line (TODO.md) still read "Latest ✓ Run 19 2026-06-19-2117"; Run 20 had since
  run (ledger-only). Refreshed the mirror line to Run 21 so a future strong session
  isn't misled about the latest audit point. (The d5e0 provenance phrase "updated by
  id:401c Run 17 audit" is accurate history, not a contradiction — Runs 18-21 were
  ledger-only and did not need to re-touch d5e0; left as-is.)

## Tracked flakes — behaved as documented
- id:16e9 (`test_relay_claim_liveness.sh`, roadmap:7570) — did NOT recur.
- id:05e8 (`test_git_lock_push_slash_branch.sh`) — flaked ONCE on the first full
  `tests/run-tests.sh` (75/1), then GREEN in isolation AND on an immediate
  full-suite rerun (76/0) — exactly the fetch/push-timing-under-load flake id:05e8
  predicts. NOT a feature defect, NOT new contention.

Suite: 76/0 on a clean rerun.

## Outcome
No new TODO/ROADMAP findings. No inline code fix (no code in window). One inline
coherence-drift fix (the 401c mirror line). Item id:401c stays open by design
(recurring); Run 21 appended to its run log.
