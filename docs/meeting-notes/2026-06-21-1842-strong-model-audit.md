# Strong-model audit — Run 25 (2026-06-21 18:42)

**Item**: ROADMAP id:401c (recurring strong-model audit — code review, security, design coherence).
**Window**: `99a1f2e..HEAD` (first-seen change since Run 24's own audit merge `99a1f2e`).
**Model/role**: claude-opus-4-8, relay HARD-execute child (id:da26), run relay-20260621-183505-11008.

## Verdict: CLEAN — LEDGER-ONLY window

This is a LEDGER-ONLY window (Runs 11/12/16–24 class). `git diff --name-only 99a1f2e..HEAD
-- '*.sh' '*.py' '*.js'` is **EMPTY** — no shell/Python/JS code changed, so passes (1)
code-review and (2) security have **no surface** this turn.

First-seen changes in the window:
- `RELAY_LOG.md` — three appended checkpoint paragraphs (Run 23 + Run 24 strong-execute, and
  the 2026-06-21 18:42 reviewer review entry). Internally consistent (verdict + suite count
  76/0 each).
- `ROADMAP.md` — the Run 24 run-log line (+12) AND a real design-state change (`01e54c4`):
  id:dba3 re-tagged `[HARD — strong model]` → `[HARD — decision gate]` with an inline
  `🚧 GATED (auto, id:3801; route:human)` note.

## Pass 1 — code review

No code. N/A.

## Pass 2 — security

No code at any system boundary changed (no new injection / path / jq / secrets / permission
surface). `gaming-scan.sh . 99a1f2e` clean — no DELETED_TEST / ADDED_SKIP / REMOVED_ASSERT.

## Pass 3 — design coherence

**The id:dba3 gate change (`01e54c4`) is the sole design-state delta — verified COHERENT.**
The auto-gate (handback-followup.py, id:3801) moved id:dba3 to `[HARD — decision gate]` route:human
because closing it requires seeding the model-probe baseline (id:23e9), which needs the dedicated
`claude-probe` OS user (id:d0c0 — `useradd`/`sudo`, forbidden for an unattended relay child) plus
real Opus/Sonnet/Haiku token runs. This is internally consistent with:
- the existing id:dba3 body ("Close this item once id:2d01+c345+040a+23e9 land and the baseline
  is seeded");
- the open id:23e9 ("Seed + close id:dba3 … seeding still gated on id:c345 + id:040a");
- project memory (`model-probe-quality-instrument`, id:dba3 design half resolved; seeding gated).
The route:human classification is correct — a relay child cannot create an OS user or run real
billed token batches, so the item is genuinely un-doable autonomously. No contradiction; the gate
will fire for a human `/relay human` session, not silently. **No gate that can never fire.**

**Cross-ledger coherence** (ROADMAP ↔ TODO): 0 open ROUTINE; open executable HARD = id:401c only
(this item) — id:dba3 now decision-gated, id:3346 gated/do-not-start, id:de4e DEFERRED
(non-executable). The TODO id:d5e0 summary agrees ("3 open ROADMAP items, all HARD … id:dba3 HARD
gated"), and Run 17's drift fix holds. The TODO id:401c MIRROR line read "Latest ✓ Run 24" on
arrival.

**One coherence drift fixed inline (Run 4/8/17/21/22/23/24 class)** — refreshed the TODO id:401c
mirror line from "Latest ✓ Run 24" to "Latest ✓ Run 25".

## Suite

`tests/run-tests.sh`: **76 passed, 0 failed, 0 expected-red**. Both standing tracked flakes
(id:16e9 `test_relay_claim_liveness.sh`, id:05e8 `test_git_lock_push_slash_branch.sh`) did NOT
recur on this run.

## Outcome

No new code/security defects (no code surface). One design-state change (id:dba3 gate) verified
coherent and correctly routed to human. One inline mirror-line drift fix. Item id:401c stays open
by design (recurring). No new TODO/ROADMAP items needed; no finding dropped.
