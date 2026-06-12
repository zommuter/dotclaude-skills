# 2026-06-12 — fables-executor skill: design the shape

**Started:** 2026-06-12 14:04
**Session:** c75bfe9b-9ea7-46e8-a04a-e23d9b9bcd10
**Mode:** Class 2 planning record (no meeting was held — plan-mode output)
**Topic:** Design and implement a standalone versioned `fables-executor` skill that delivers the relay executor contract to executor sessions, replacing the verbatim-copy-into-CLAUDE.md approach.

## Context

TODO id:fba6 called for a versioned `SKILL.md` that executor sessions load directly instead of reading a generated `CLAUDE.md` relay contract section. The motivation: make each executor child self-contained and testable, and reduce drift risk (a 30-line verbatim block copied into every managed repo carries high drift surface). Dispatched as Class 2 from no-arg `/meeting` 2026-06-12.

## Plan

**Key constraint surfaced in planning:** skills are trigger-gated, not passively loaded. The harness injects `CLAUDE.md` into every session's system context automatically; it does NOT inject skill bodies. Moving the contract fully into a skill would break the passive guarantee that every executor session sees the anti-gaming deterrent (rule 3: reviewer diffs test files against last `fable-ckpt-*` tag).

**Chosen shape (B): thin versioned pointer + skill.**
- `CLAUDE.md` retains a mandatory ~2-line pointer (`## Relay contract <!-- fables-executor contract vN -->` + "Load the fables-executor skill before working on any item").
- The full contract (5 rules + ROADMAP item format + RELAY_LOG conventions) lives in `fables-executor/SKILL.md`.
- Pointer drift risk ≈ one integer, vs 30-line block drift risk. Review mode's staleness check: compare `vN` in pointer vs. `vN` in skill marker.
- Shape (A) — skill fully replaces embed — rejected: executor may never load it; kills anti-gaming deterrent.
- Shape (C) — skill as source only, embed unchanged — rejected: conventions.md is already that source; doesn't improve self-containment.

**Versioning:** canonical version marker `<!-- fables-executor contract vN -->` on the `## Executor contract` heading in SKILL.md. No `version:` frontmatter field (no consumer reads it). Bump rule: increment vN only when a rule or artifact format changes in a way an in-flight executor must know; documented in the skill as a `## Maintenance` note.

**Scope:** relocation + delivery refactor, behavior unchanged. Also migrated this repo's own `CLAUDE.md` block to the thin pointer (live end-to-end). Other managed repos refreshed on their next review turn.

## Implementation findings

All 8 test assertions pass. Notable: `grep -q` in a `set -o pipefail` pipeline causes a broken-pipe exit when the pattern is found early — fixed by capturing `make help` output into a variable before grepping.

Files changed:
- NEW: `fables-executor/SKILL.md` — frontmatter + 5 rules verbatim + ROADMAP/RELAY_LOG format + Maintenance note
- NEW: `tests/test_fables_executor.sh` — 8 hermetic assertions (install, symlink, help, status, version-consistency, conventions-block-gone)
- `Makefile` — `fables-executor` added to `SKILLS`, manifest vars defined
- `fables-turn/references/conventions.md` — fenced 5-rule block replaced by pointer-to-skill note
- `fables-turn/references/handoff.md` — C1 updated to write thin pointer
- `fables-turn/references/review.md` — step 4 updated to check/refresh pointer vN
- `dotclaude-skills/CLAUDE.md` — 22-line verbatim block → 2-line pointer (`<!-- fables-executor contract v1 -->`)
- `ROADMAP.md` — item id:7691 added and ticked `[x]`

## Decisions

- **D1 — Delivery shape (B): thin pointer + skill.** CLAUDE.md retains a mandatory ~2-line versioned pointer; full contract in `fables-executor/SKILL.md`. *Out of scope:* full skill-replaces-embed (shape A); skill-as-source-only (shape C).
- **D2 — Versioning: HTML-comment marker, manual bump.** Canonical `<!-- fables-executor contract vN -->` in SKILL.md; CLAUDE.md pointer echoes `vN`. No frontmatter version field; no auto-bump tooling. Bump rule in skill `## Maintenance`.
- **D3 — Scope: relocation + delivery refactor.** Rules unchanged; conventions.md block replaced; handoff/review refs updated; fables-executor in Makefile SKILLS; this repo's CLAUDE.md migrated to pointer. *Out of scope:* migrating other managed repos, rewriting executor behavior.

## Action items

- [x] Create `fables-executor/SKILL.md` and register in Makefile. <!-- id:fba6 -->
- [ ] Note: `id:15e9` gate condition "fables-executor skill exists (id:fba6)" is now met — `/meeting` relay-awareness can be designed when Fable-class session is available.
