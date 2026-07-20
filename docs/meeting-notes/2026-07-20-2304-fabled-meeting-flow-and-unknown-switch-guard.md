# 2026-07-20 — `--fabled` Fable-in-meeting flow + unknown-switch guard (7e87, 7681)

**Started:** 2026-07-20 23:04
**Session:** f8ca6319-77a4-49d8-8e08-6e265f40c408
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), 🜛 Fable-5 (closing adversarial subagent)
**Topic:** Mechanize the Fable-assisted meeting flow (7e87, unified with the inbound 8df5) and decide where/how unknown skill switches must warn (7681) — coupled, because a new `--fabled` flag must be recognized or it trips the guard 7681 builds.

## Surfaced discoveries
- **id:8df5** (INBOUND routed:5c06 from loderite): the same feature as 7e87, richer — per-decision + adversarial + closing Fable *subagent* passes, one shared repo-state digest, "Fable reliable as subagent not driver (reasoning-extraction refusal)." → unified into 7e87 here.
- This session's live evidence: a manual *closing* Fable pass caught a real hardening (log field-ordering) at ~52k tok, but fired after ratification → advisory only.
- [[feedback-fable-optional-not-gate]]: Fable optional, never a gate. CLAUDE.md per-prompt ctx-multiplier rule.

## Agenda
1. 7681 — where does the unknown-switch guard live, and warn-and-proceed vs abort?
2. 7e87 ↔ 8df5 — unify; pick the v1 Fable firing topology + digest + degrade.
3. Coupling — `--fabled` registers in 7681's known-flags manifest.

## Discussion
😈 **Riku (7681):** A global CLAUDE.md directive is prose-replacing-prose — the id:0e56/de36 "a check nothing invokes isn't a check" failure. The fix must be mechanical and fire.
🏗️ **Archie (7681):** Per-skill validation duplicates+drifts; a shared `validate-flags.sh <skill> -- "$@"` + per-skill known-flags manifest, called at setup, is deterministic and single-sourced. `/meeting` + `/relay` = N=2 real consumers today.
✂️ **Petra (7681):** Key only on leading-dash tokens; warn-and-**proceed** (drop the unknown flag, don't fold into subject) — match the privacy-gate warn-first philosophy; a typo neither blocks nor corrupts the subject.
🏗️ **Archie (7e87):** 8df5 and 7e87 are the same feature — unify. The fork is *where Fable fires*: (A) closing-only, (B) selective per-decision (before the AskUserQuestion, so it can shape the call), (C) full multi-pass (8df5).
😈 **Riku (7e87):** Catch-rate concentrates on chewy decisions; per-every-decision is waste (this session's D1 field-choice was low-controversy). C is ~5× the ctx multiplier with no evidence it beats A.
✂️ **Petra (7e87):** v1 = A (closing pass) + the shared repo-state digest (the real efficiency win), opt-in `--fabled` (never default), silent degrade if Fable down. Gate B/C on evidence.

## Fable closing pass (dogfooded — the v1 feature applied to this meeting's own decisions)
Ran the ratified v1 (one closing Fable-5 subagent + a shared repo-state digest incl. the ratified decisions). Verdict **CONCERNS** — four real holes that would have re-created the silent-flag bug this meeting exists to kill. The owner ratified all as amendments. This dogfood is itself evidence the closing-pass topology has value (it materially improved the meeting). The findings are folded into the final decisions below; provenance:
- D1: flag-value **arity** unspecified → a dash-starting value (`--exclude -x`) false-drops; **`--cross` exact-whole-arg** semantics must be preserved, not widened by a generic manifest; the "call it at setup" instruction is **prose that can no-op** → require a displayed warning artifact + a coverage test (SKILL.md `--flags` ⊆ manifest); ship manifest+enforcement atomically.
- D2: warn-and-drop is **dangerous for mode-changing flags** — `/relay --af` (typo for `--afk`), user walks away → dropped, warning seen by nobody → runs **attended**. → near-miss (edit-distance ≤2 of a mode-changing flag) escalates.
- D3: **"silent degrade" literally re-creates 7681** → must be LOUD; the evidence gate was **un-fireable** (needed the gated-off per-decision pass) → pre-register a countable trigger; the **digest must be built at closing time** incl. ratified text. Concurs Fable-as-subagent avoids the reasoning-extraction refusal.
- Cross-cutting degeneracy: a typo'd `/meeting --fable` (D2 drop) and a correct `/meeting --fabled` with Fable down (D3 silent) produce identical no-Fable outcomes — the loud-degrade + near-miss-ask fixes each break it from one side; both adopted.

## Decisions (final — Fable amendments folded in)
- **D1 — Unknown-switch guard = shared helper (ratified + amended):** build `validate-flags.sh <skill> -- "$@"` + a per-skill **known-flags manifest** (each entry records the flag AND whether it *takes a value*, so a dash-starting value isn't false-dropped), called at each skill's setup. `/meeting` manifest lists `--cross` (with **exact-whole-arg** semantics preserved — `--cross` fires cross-mode only when it is the entire argument) and `--fabled`; `/relay` gets its own. Enforcement must be **mechanically verifiable**: the pre-agenda warning is a **required displayed artifact** (like orphan-scan candidates), and a **coverage test** asserts every `--flag` grep'd from a SKILL.md exists in that skill's manifest (kills drift + the bootstrap-ordering hazard — ship manifest+enforcement atomically). N=2 (meeting+relay). *Out of scope:* global CLAUDE.md directive (rejected — prose no-ops); non-dash-prefixed subject content.
- **D2 — Guard behaviour = warn+drop, with a near-miss escalation (ratified + amended):** an unrecognized **leading-dash** token → LOUD pre-agenda warning listing known flags; the unknown flag is **dropped** (not folded into the subject) and the skill proceeds. **Amendment:** if the unknown flag is within **edit-distance ≤2 of a mode-changing flag** (`--afk`, `--cross`, `--fabled`, `-d`), escalate instead — **AskUserQuestion when attended, abort when not** — so a walk-away `--afk` typo can't silently run attended/non-conservative. *Out of scope:* escalating *every* unknown flag (over-heavy for cosmetic typos); mid-string dash content.
- **D3 — 7e87 = opt-in `--fabled` closing pass, unified with 8df5 (ratified + amended):** v1 is an opt-in `--fabled` flag that runs **one closing adversarial Fable-5 subagent pass** fed a **shared repo-state digest built at closing time** (including the ratified decisions verbatim). **LOUD degrade** if Fable unavailable ("Fable unavailable — `--fabled` pass skipped", recorded in the note) — never silent. Per-decision (B) and full multi-pass (C, 8df5) are **gated on a pre-registered countable trigger: ≥2 closing-pass findings that force reopening/amending an already-ratified decision** (this session's hardening-only findings would NOT count — the metric discriminates). Fable is advisory, never a gate. *Out of scope:* Fable as meeting *driver* (reasoning-extraction refusal — subagent only); default-on.
- **Coupling:** `--fabled` (and `--cross`) live in `/meeting`'s manifest, so D1's guard never warns on them. Build order: **7681 first** (helper + manifest + coverage test), then **7e87** adds `--fabled` to the manifest + the closing-pass plumbing → 7e87 gated-on 7681.

## Action items
- [ ] 7681: build `validate-flags.sh` + per-skill known-flags manifest (arity-aware) + wire into `/meeting` and `/relay` setup as a displayed warning artifact; near-miss (≤2 edit-distance of a mode-flag) → ask/abort; coverage test (SKILL.md flags ⊆ manifest). <!-- id:7681 -->
- [ ] 7e87 (unifies 8df5): opt-in `--fabled` closing Fable-5 subagent pass + closing-time shared repo-state digest + LOUD degrade; register `--fabled` in the meeting manifest; pre-register the ≥2-forced-amendments gate for per-decision/multi-pass. Gated on 7681. <!-- id:7e87 -->
- [ ] Absorb 8df5 into 7e87 (same feature; keep the routed:5c06 provenance). <!-- id:8df5 -->
