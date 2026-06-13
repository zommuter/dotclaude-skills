# 2026-06-13 — Fable-availability gate for the autonomous relay pool

**Started:** 2026-06-13 08:25
**Session:** 50913d1d-f615-4c45-84c8-424021b7762e
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), 🎛️ Orla (orchestration), ⚙️ Sage (skill-runtime)
**Topic:** When `claude-fable-5` is inaccessible (Fable Mythos access pulled), the unattended `/fables-turn` pool must detect it and run executor (Sonnet) work only — never silently fall back to Opus.

## Surfaced discoveries
- [2026-06-12 dotclaude-skills] STRONG_TIER knob (fable|opus) already routes review/handoff agents; execute agents are pinned to Sonnet and never receive the override.

## Agenda
1. Detection mechanism — how does the Workflow learn `STRONG_MODEL` is inaccessible?
2. Behaviour when unavailable — what does the pool do, and how is "no Opus fallback" enforced?
3. Front-door self-model guard.

## Discussion

### Item 1 — detection mechanism
- Archie: no availability check exists; `STRONG_MODEL` first used at relay-loop.js dispatch (unitPrompt/opts.model).
- Sage: `agent()` returns null after retries on a terminal model-access error — that's the signal, but costs retries.
- Orla: implicit detector = first strong unit HANDBACKs; N strong repos → N expensive failures + N orphaned worktrees. One upfront probe converts N failures → 1 cheap check + clean deferral.
- Riku: null is ambiguous (Fable-down vs. transient vs. OOM). False-negative risk.
- Orla: asymmetric cost favours trusting a negative — false negative = executors-only this run, self-corrects next turn; matches global CLAUDE.md conservative-threshold heuristic.
- Petra: reject `/v1/models` shell-script probe (oauth plumbing, new auth surface, tests wrong code path). Reuse agent-dispatch machinery; one probe agent, one boolean. No new script (N=2 fails).
- Sage: mirrors the quota-stop.sh agent-gate pattern; statically testable.

**Converging recommendation (later revised):** upfront agent-probe in Discover phase.

### Item 2 — behaviour when unavailable + no-Opus-fallback
- Petra: probe fails → filter actionable queue to `execute` only; review/handoff deferred, NOT promoted to Opus.
- Orla: rule is generic — probe tests whatever STRONG_MODEL resolves to; "no Opus fallback unless asked for Opus" falls out for free.
- Riku: deferred units must surface in RELAY_STATUS Queued with reason, not vanish.
- Archie: partition after the `actionable` sort, before the dispatch pool. Integrator/quota/drain untouched.
- Orla: zero-execute edge — probe fails + no execute units → dispatch nothing, all-deferred RELAY_STATUS, log + clean exit.
- Sage: conditional probe — only if actionable contains ≥1 review/handoff unit.
- Petra: scope fence — no cross-run cache, no retry/backoff, no model-health subsystem.

### Item 3 — front-door self-model guard
- Sage: distinct concern — front-door runs in the user's session model; tripwire for accidentally firing the pool on Opus.
- Archie: precedent = format.md §Harness-class gate. 10s window = `sleep 10`; Ctrl-C/ESC aborts pre-launch.
- Riku: warn on Opus only. Concern: forced 10s on deliberate Opus runs.
- Orla: friction is the point. Keep unconditional-on-Opus; defer opt-out until friction is real (N=2).
- Petra: front-door only, Opus-only, print + sleep 10 + proceed. Does NOT touch relay-loop.js.

### Amendment — front-door model reframes detection (user surfaced)
D2 (2026-06-12) established a THIN front door — no convention that the autonomous front-door runs on Fable. The probe-vs-flag fork:

- (a) Front-door=Sonnet → Workflow must auto-probe.
- (b) Front-door=Opus + manual `--fable-down`/`-d` → human signals it deterministically.

Key argument: the human already knows Fable is down at launch time (the Mythos access pull is multi-day, not a flicker). The flag carries known information deterministically; the probe re-discovers already-held information with OOM-ambiguity risk. Lever-first pattern from todo-infra-decision: build the primitive (`-d`), defer the automation (auto-probe) until a genuinely unattended-without-human run needs it. The flag is forward-compatible — a future probe sets `args.fableDown = true` identically.

Opus self-guard unifies cleanly: Opus + `-d` = knowingly on Opus → no warn; Opus without `-d` = possibly accidental → warn + 10s.

## Decisions

- **D1 — `--fable-down` / `-d` flag, parsed by the supervising session.** SKILL.md front-door parses the flag and passes `args.fableDown = true` into `relay-loop.js`. *Out of scope:* in-Workflow auto-probe (deferred; forward-compatible).
- **D2 — Workflow executor-only when `fableDown`.** After the `actionable` sort, partition: keep `execute` units; move `review`/`handoff` units to `state.queued` with reason `deferred: --fable-down, strong model skipped`. Dispatch pool only spawns Sonnet execute children. Integrator / quota gate / drain logic untouched. *Out of scope:* any Opus promotion of child work.
- **D3 — Zero-execute edge.** `fableDown` + no execute units → dispatch nothing, write all-deferred RELAY_STATUS, log "strong model skipped (--fable-down); no executor work", exit clean.
- **D4 — Opus self-guard at the supervising session.** SKILL.md Default-mode step 0: if model is `claude-opus-*` and `-d` not set → print warning + `sleep 10`. If `-d` is set → skip guard. Sonnet/Haiku/Fable → no warning. *Out of scope:* env opt-out (deferred until friction is real per N=2).

## Action items
- [x] SKILL.md: `--fable-down`/`-d` in invocation block + knobs table; Default-mode step 0 Opus self-guard (warn + `sleep 10`, suppressed under `-d`); thread `args.fableDown` into Workflow launch description. Completed in-session. <!-- id:025c -->
- [x] `relay-loop.js`: `FABLE_DOWN` constant from `args.fableDown`; `fableDownDeferred` partition; deferred units → `state.queued` with reason; zero-execute clean-exit. Completed in-session. <!-- id:4a96 -->
- [x] `tests/test_fable_down_flag.sh` (`# roadmap:3737`): 11 static-grep checks, all PASS; `make test` 15/15 green. Completed in-session. <!-- id:bfe2 -->
- [x] ROADMAP.md item id:3737 added and ticked (strong-model turn, this session). Completed in-session. <!-- id:3737 -->
