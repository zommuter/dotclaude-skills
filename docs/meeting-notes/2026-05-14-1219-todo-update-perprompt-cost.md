# 2026-05-14 — Empirical check: is /todo-update's "every prompt" invocation a ctx problem?

**Started:** 2026-05-14 12:19
**Session:** 26458eba-6188-44b2-98ce-8e81cef1fbaf
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime, project-standing)
**Topic:** Assess whether `/todo-update`'s mandatory "after every prompt" invocation is a real ctx-cost problem, and what (if anything) to change.

## Agenda

1. Cost reality-check — is per-prompt load actually a problem?
2. *(Mooted by Item 1 result)* What does /todo-update need to do per-prompt vs occasionally?
3. *(Mooted)* Candidate mitigations menu.
4. *(Mooted)* Decision + re-eval trigger.

## Discussion

### Item 1 — Cost reality-check (in three rounds)

**Round 1 — positions stated:**

- 🏗️ **Archie:** Ground truth — `/todo-update/SKILL.md` is 99 lines (was 83 in the morning audit; grew when the stray-TODO subdir-warn was added). Trigger is CLAUDE.md prose ("after every substantive prompt → diary, todo-update"). Per-invocation load ~150–400 lines (SKILL.md + TODO.md). If invoked ~30×/session, floor ~100k tokens — roughly top-3 ctx multiplier.
- ⚙️ **Sage:** Frontmatter description already paid every prompt (cheap). The recurring cost is the body, which only loads when the Skill tool fires. TODO.md size varies materially: zkm/helferli sit at ~150–250 lines vs 48 here.
- 😈 **Riku:** The morning's audit labelled `/todo-update` a multiplier *by inspection*, not measurement. No incident on record. Don't fix speculative problems.
- ✂️ **Petra:** The multiplier argument is deterministic by construction, but magnitude depends on invocation rate, which we haven't measured.

**Round 2 — n=3 measurement:**

Scanned three recent transcripts — one dotclaude-skills session (a5b3c6e1, ~64 turns), one zkm (86ca14e8, ~90 turns), one helferli (8795fd80, ~77 turns). Result: only 1 `Skill("todo-update")` call across ~230 turns, and that one was inside this morning's meeting (meta-invocation). zkm and helferli had zero. Session A had 8 direct `Edit(TODO.md)` calls — the user's own task-work, not skill output.

User flagged n=3 as statistically thin and demanded a proper-sample re-run. (Consistent with CLAUDE.md's "pilot sample size and conservative thresholds" heuristic; also directly relevant to today's Methodology feedback — profile-entry candidate.)

**Round 3 — n=100 measurement (14 days, 7,014 turns, 5 projects):**

| Project | Sessions | Turns | `Skill(todo-update)` | `Skill(git-diary)` | TODO edits |
|---|---:|---:|---:|---:|---:|
| zkm | 53 | 4,264 | 51 | 54 | 182 |
| helferli | 30 | 1,791 | 20 | 19 | 89 |
| project-manager | 10 | 438 | 5 | 5 | 33 |
| dotclaude-skills | 6 | 378 | 4 | 5 | 44 |
| ai-codebench | 1 | 143 | 1 | 1 | 6 |
| **TOTAL** | **100** | **7,014** | **81** | **84** | **354** |

Key ratios:
- `Skill(todo-update)` per session: **0.81** (mirrors `git-diary-workflow` at 0.84 — they fire as an end-of-session pair, not per-prompt).
- `Skill(todo-update)` per turn: **1.2%** — far from "every prompt."
- TODO edits per session: **3.5**; per Skill call: **4.4** — most TODO edits bypass the skill body.
- Concrete cost: ~81 × 99 lines ≈ 8,000 lines body-load over 14 days, ~160k tokens, ~5–10 cents compute. Real but **not a top-3 ctx multiplier**.

Personas' conclusions:

- ⚙️ **Sage:** The de-facto cadence is once-per-session — "after every prompt" is CLAUDE.md's intent, but the model fires it once at end-of-work. This is probably the right cadence, reached by accident.
- 😈 **Riku:** The morning's discovery wording had the right *formula* (size × prompt count) but the wrong *multiplier value* (~1/session, not ~30/prompt). The principle stands; the worked example overstated. The inverse concern is more real: 77% of TODO edits skip the body, so procedural rules don't load on ~270/354 edits.
- ✂️ **Petra:** Guidance-leak finding: N=2 for lifting verification-rule + no-reorder to CLAUDE.md. But user chose to defer (Option 2, "amend only").
- 🏗️ **Archie:** The 8 session-A edits applied the verification-rule correctly on general competence. SKILL.md body is mostly redundant for per-edit behaviour; useful only for edge cases (PROGRESS.md migration, subdir-warn).

## Decisions

- **D1** — Original framing falsified. `/todo-update`'s empirical Skill-invocation multiplier is ~1 per session, not ~30 per prompt. The general "after-every-prompt mandatory skill is a ctx multiplier" rule stands; `/todo-update` is not a current instance of it in the magnitude the audit implied.
- **D2** — Amend morning's discovery entry (via `append.sh`). No SKILL.md / CLAUDE.md edits.
- **D3** — Guidance-leak observation noted but not actioned. Future trigger: a real incident of model-violated TODO hygiene → re-open `/meeting todo-invariants-to-claude-md`.
- **D4** — Methodology feedback: user challenged n=3 when n=100 was equally cheap. Profile-entry.

## Action items

- [ ] Amend `~/.claude/skills/meeting/discoveries.md` γ-class entry from 2026-05-14 — add correction line noting empirical multiplier ~1/session over n=100, correcting the "×prompt-count" framing. Via `append.sh`. See this meeting note.
- [ ] Add user-profile entry: "proper-sample-first measurement — challenges low-n samples when large-n is cheaply available." To `~/.claude/skills/meeting/user-profile.md`. See this meeting note.

## Out of scope (explicit)

- Lifting verification-rule + no-reorder from SKILL.md to CLAUDE.md (declined by user — Option 2 only).
- Any change to `/todo-update` SKILL.md, the CLAUDE.md trigger directive, or invocation cadence.
- Investigation of the 270+ skill-less TODO edits for hygiene violations (declined).
- `/git-diary-workflow` parallel analysis (similar empirical pattern; separate audit if/when warranted).
