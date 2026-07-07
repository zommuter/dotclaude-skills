# 2026-07-07 — Stale-ledger drift: root cause + reconciliation detector

**Started:** 2026-07-07 11:38
**Session:** 1fa48c3d-c2f4-439f-9378-8bbb363853b3
**Mode:** Investigation findings (background Opus diagnostic agent, read-only) — not a persona meeting
**Topic:** Why did shipped-and-tested TODO items (id:6f61, id:b67e) sit unticked for 8 days, and what deterministic detector prevents recurrence.

## Context
A no-subject `/meeting` dispatched three executors; two of the three items (id:6f61 flock memory-writes, id:b67e pathspec-drop-guard) turned out already-shipped — code + passing tests, deployed live 2026-06-29 — yet never ticked `[x]` in `TODO.md`. Symptom: the design ledger lags behind what's actually deployed. A read-only Opus agent measured the spread and diagnosed the cause.

## Findings

### Symptom is NARROW (n≈2), not widespread
200 open `- [ ]` items; deep-checked the ~15 that carry `shipped`/`REMAINING`/`awaiting` or name a concrete artifact/test. Only **6f61, b67e** are true stale-shipped (both re-ticked 2026-07-07); **a354** is soft (artifact `docs/relay.md` done, gate = "awaiting user read-through"). Every other "shipped"-flavored item is legitimately open — gated on an observe-window (quota-sample), a verify-on-recurrence trigger (API-failsafe, fable-standin), or a genuine partial-remainder. **"Artifact exists" alone is a high-false-positive signal** — a naive detector would flag all of those.

### Root cause (reconstructed, all 2026-06-29)
- **17:17 `07a061d`** — code for 6f61 + b67e + ef77 lands (one commit, no TODO edit).
- **17:19 `e5ef692`** — batch write-back ticks 9 C1 items and *deliberately* leaves 6f61/b67e open with a progress-note ("…global memory-instruction wiring pending", "…settings.json enable pending"). **Correct at the time** — the code shipped but adoption hadn't.
- **18:42 `~/.claude b87ae5f5`** — 6f61 activation completes (global `CLAUDE.md` rewired to call `memory-append.sh`).
- **18:45 `~/.claude 18bae1f9`** — b67e activation completes (`pathspec-drop-guard` enabled in `~/.claude/settings.json`).

Both pending clauses cleared ~90 min later — **but the completions landed in `~/.claude`, while the checkboxes live in `dotclaude-skills`.** Three compounding gaps:
1. **No watcher on a deferred-completion clause.** A point-in-time write-back never returns when a "pending/REMAINING" condition later clears. (Generalized "REMAINING sub-notes are never re-evaluated.")
2. **Cross-repo split hid it from the relay.** Activation landed in a different repo than the ledger, and both items had **no ROADMAP mirror** — `/relay review`'s tick-on-mirror-close only fires on a ROADMAP twin, so no relay pass ever looked at them.
3. **Nothing reconciles TODO against on-disk state.** `todo-update` Step 3 ticks only reactively in-session (`todo-update/SKILL.md:77-86`, "no tick without verification"); `orphan-scan.sh --reverse` explicitly skips open items (`orphan-scan.sh:141`) and correlates by token, never against artifact/test existence.

Net: a **missing reconciliation of a deferred completion condition**, aggravated by cross-repo completion and the absent ROADMAP mirror.

## Decisions
- **D1 — Build a report-only reconciliation detector by EXTENDING `orphan-scan.sh` (no NIH), not a new tool.** New `--shipped` mode, two low-false-positive classes, never auto-ticks:
  - **TICK-READY** — open `[ ]` item linking a `tests/test_*.sh` (via `# roadmap:`/name match) that passes green, AND whose body has **no** gating lexeme (case-insensitive `REMAIN|pending|activation|observe|verify|awaiting|gated|re-evaluate|let it run`). → "ready to tick, no gate excuse."
  - **GATE-STALE** — open item that **does** carry a gating lexeme AND whose line is **≥14 days old** (git-blame). → "the pending/REMAINING clause may have lapsed — re-check." *This age-nudge is specifically what would have surfaced 6f61/b67e (their prose honestly said "pending", so a lexeme filter alone suppresses them).*
- **D2 — Both classes are required.** TICK-READY alone would not have caught the motivating incident; GATE-STALE alone misses the forgot-to-tick hazard. Build both.
- **D3 — Report-only, wired into two consumers.** Surfaced in `/relay review` step 5 (reverse-handoff already shells `orphan-scan.sh` there) and by `todo-update`. No checkbox is auto-flipped — honors `todo-update`'s "no tick without verification" and observe-before-preventing. Complements the *inverse* guard (todo-update done-verification guard, gated id:8aba) which blocks premature `[x]`.
- **Rejected (A):** naive "artifact-exists ⇒ stale" scan — high FP (would flag every observe/verify-gated item), NIH. **Deferred (C):** cross-repo activation-completion breadcrumb via the shared inbox — speculative infra for an n≈2 failure, and it re-relies on the same human step that was missed; revisit if GATE-STALE surfaces this class ≥2–3 more times.
- **Out of scope:** auto-ticking; migrating any ledger; the cross-repo breadcrumb (deferred).

## Action items
- [ ] **Build `orphan-scan.sh --shipped` reconciliation detector** [ROUTINE] — TICK-READY + GATE-STALE classes (D1/D2), report-only, wired into `/relay review` step 5 + `todo-update` (D3); hermetic test `tests/test_orphan_scan_shipped.sh` (green-test+no-lexeme→TICK-READY; lexeme+aged→GATE-STALE; observe-gated recent→neither; genuinely-open→neither). Cites this note. <!-- id:b3ee -->
