# 2026-05-28 — `/meeting --cross-project` architecture decision

**Started:** 2026-05-28 11:38
**Session:** 66a9264f-d615-4240-8f3f-a8c99c103bea
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime — project-standing per `meeting-style.md`)
**Topic:** Resolve D7 deferral from `~/src/project_manager/docs/meeting-notes/2026-05-14-0954-proj-launch-and-meta-meeting.md` — architecture for cross-project meeting capability.

## Agenda
1. Re-confirm the contamination concern given evolved infrastructure (F-B, broker, meeting-live sibling).
2. Architecture: flag-on-existing (α), split + composition with shared classify.sh (β), or full duplicate (γ).
3. Spec sharing: how much of /meeting's SKILL.md and helpers are shared vs. forked.
4. Class 3 dispatch handoff — Skill-invoke vs. inline canonical steps.

## Discussion

### Agenda 1 — Contamination concern still load-bearing?

Archie reviewed: D7 deferred on Tobias's contamination concern (cross-project context biasing single-project flow → false execution). Since then F-B opaque IDs, broker/global-daemon, and meeting-live sibling have shipped. Concern unchanged in principle.

Riku invoked [[meta-skill-isolation-instinct]] pre-emption (Confidence: low, Pre-emption-eligible: yes) — directional evidence for split, but original framing was "deferred" not "decided"; ratification required here.

Petra ran N=2: separate-skill consumers are (1) daily no-arg cross-mode invocation, (2) future `proj rnd` integration in D7 spec — met. Flag-route abstraction is internal (no new file/allowlist/symlink); cost asymmetry favours flag.

Sage framed the precedent: meeting-live is also a sibling skill (planned AI-5 backmerge). Project history shows: split when piloting risky integration; fold back to canonical after stabilisation.

Archie identified the deciding question: is cross-mode's step set (a) per-project loop of canonical steps, or (b) novel cross-project steps? Sage answered: ~70% reuse (per-project classification), ~30% novel (global bucket synthesis, connection candidates).

Mixed picture argued against pure-flag (pollutes single-project read path with 30% novel logic gated by flag) and against pure-duplicate (loses 70% shared logic). Petra proposed lever-first refinement: canonical stays unchanged; /meeting-cross is a NEW skill that composes — invokes canonical /meeting for Class 3 dispatch on converged single-project items, calls a shared `classify.sh` for per-project classification.

Riku raised: (1) Skill-from-skill invocation cost, (2) token cost of N canonical invocations (load-bearing per [[resource-gating-fluency]]), (3) "global bucket" requires classification-only mode (canonical commits decisions).

Sage refined: shared logic lifted out of canonical SKILL.md into `classify.sh` (a sibling script); both skills call it. Slims canonical and gives /meeting-cross its primary lever.

Archie named three options:
- **α (flag-on-existing):** --cross-project flag/subject on canonical; top-of-skill branch.
- **β (split + composition):** new /meeting-cross; lift shared classify.sh; cross-skill orchestrates; dispatches single converged item to canonical via Skill tool.
- **γ (full duplicate):** independent /meeting-cross, no shared script.

N=2 cleanly met on classify.sh extraction (canonical + cross). Personas converged: β.

**Tobias decision:** β, but raised sequencing question — should the split happen only AFTER /meeting-live backmerge?

### Agenda 1b — Sequencing

Sage: strong yes. meeting-live/ is P2-symlinked sibling with active divergence (broker mode); extracting classify.sh now means updating both SKILL.md files in lockstep → drift on drift.

Archie outlined clean topology:
1. Now → AI-5 trigger: finish meeting-live pilot; on success (≥5k token savings, ≥1 successful live meeting), fold deltas into canonical, delete sibling.
2. Then: extract classify.sh from canonical SKILL.md (single file touch).
3. Then: build /meeting-cross as second consumer.

Petra: N=2 strictness — don't extract classify.sh in step 2 until consumer 2 (cross-skill) actually arrives. Fold steps 2+3 into one session: extract + build, with separate commits inside.

Riku: counter — internal refactor sequencing inside one session matches [[migration-provenance-instinct]] when separate commits are made. Accepted.

Riku raised gate-failure risk: if AI-5 never fires, /meeting-cross blocks forever. Need date fallback.

Petra proposed 2026-08-28 (3-month gate). **Tobias tightened to 1-month re-eval (2026-06-28).**

### Agenda 4 — Class 3 dispatch (Agenda 3 absorbed into β)

Archie: when cross-mode converges on single Class 3 item for project X, two options — (i) Skill-tool invoke canonical /meeting <subject>, (ii) inline canonical steps in cross-skill.

Sage: (i) is the composition route consistent with β; needs canonical to honour an `MEETING_ROOT_OVERRIDE` env var so cwd-anchored helpers hit project X's repo without `cd` (which triggers permission prompts per CLAUDE.md). One-line change to canonical setup-step-1.

Riku: [[resource-gating-fluency]] pre-emption confirmed — env var clean, no `cd` prompt.

Petra: N=2 met (canonical default + cross-skill override). Adopt (i).

Archie: D7's "cross-write to other project's TODO" concern dissolves — canonical writes to its own (overridden) <root> naturally; nothing to append.

Riku: cross-meeting audit log (which projects scanned, why X won) — brief "cross-classification record" note in dotclaude-skills/docs/meeting-notes/; substantive note in project X.

**Tobias decision:** Option (i) confirmed. Raised forward concern: depending on meeting complexity, should the handoff be to a fresh session via handover file (avoid ctx bloat) rather than inline same-session dispatch?

### Amendment — Ctx-bloat handoff

Sage outlined three mitigation routes: (A) handover file → fresh session, (B) /clear or /compact between, (C) status-quo inline + observe.

Riku: [[empirical-pilot-preference]] pre-emption — don't design mitigation before evidence. v0 cost table says ~100k tokens for design meeting; +50k cross-load is ~150k, well below window.

Petra: forward-flag with empirical threshold. Spec: instrument first 3 cross-meetings with `cost-of.sh`; if any exceeds 250k tokens, design handover-file mechanism (Option A).

**Tobias accepted forward-flag without modification.**

## Decisions

- **D1 — Architecture: β (split + composition).** New `/meeting-cross` skill at `~/src/dotclaude-skills/meeting-cross/`, P2-symlinked to `~/.claude/skills/meeting-cross/`. Shared per-project classification logic lifted into `~/src/dotclaude-skills/meeting/classify.sh` (P2-symlinked), called by both canonical /meeting (no-arg mode) and /meeting-cross. Cross-skill orchestrates per-project classification, picks one converged item, dispatches Class 3 candidates to canonical /meeting <subject> via Skill tool. *Out of scope:* α (flag-on-existing) and γ (full duplicate). **Decision provenance:** ratified by Zommuter (AskUserQuestion turn 1).

- **D2 — Sequencing: gate on AI-5 backmerge + 1-month re-eval.** /meeting-cross construction blocked until AI-5 backmerge fires (meeting-live folded into canonical). Re-eval gate at **2026-06-28**: if AI-5 hasn't fired by then, reconsider whether to build cross-skill against the surviving sibling-topology (eating drift cost). *Out of scope:* building now ("Build now, eat drift" rejected) and strict gate without re-eval. **Decision provenance:** ratified by Zommuter (AskUserQuestion turn 2).

- **D3 — Dispatch: Skill-tool invoke + MEETING_ROOT_OVERRIDE env var.** /meeting-cross dispatches converged Class 3 items by invoking canonical /meeting <subject> via the Skill tool, setting `MEETING_ROOT_OVERRIDE=<project-X-root>`. Canonical's setup-step-1 reads `<root> = $MEETING_ROOT_OVERRIDE ?: git rev-parse --show-toplevel` — one-line change, gated by env var presence so non-cross invocations unaffected. Routing-trail note at `~/src/dotclaude-skills/docs/meeting-notes/<date>-<id>-cross-classification.md` (lightweight); substantive meeting note at project X's venue per existing venue rule. *Out of scope:* inline canonical steps in cross-skill, and `cd && /meeting` (resource-gating). **Decision provenance:** ratified by Zommuter (AskUserQuestion turn 3).

- **D4 — Ctx-bloat: forward-flag with empirical threshold.** Inline dispatch is the v1 default. First 3 cross-meetings instrument the dispatch with `cost-of.sh`; if any single combined session exceeds 250k tokens, design handover-file mechanism (cross-skill writes `~/.claude/handover/<id>.md`; user resumes in fresh session) before further cross-meetings. *Out of scope:* designing handover mechanism now, /compact-between approaches. **Decision provenance:** ratified by Zommuter (AskUserQuestion turn 3 amendment).

## Action items

- [ ] **Update `/meeting --cross-project` TODO entry** with D1/D2/D3/D4 — record β + AI-5 gate + 2026-06-28 re-eval + dispatch design + ctx-bloat forward-flag. File: `~/src/dotclaude-skills/TODO.md`. Contract: existing TODO entry references this meeting note; no new design surface left open. <!-- id:4f01 -->

- [ ] **At AI-5 backmerge (or 2026-06-28 re-eval — whichever fires first): open `/meeting-cross-implementation` session.** Tasks within: (1) extract `classify.sh` from canonical `/meeting/SKILL.md` no-arg branch; (2) build `/meeting-cross/` skill (SKILL.md, P2 symlinks, allowlist entries); (3) one-line `MEETING_ROOT_OVERRIDE` change to canonical setup-step-1; (4) routing-trail-note shape spec. File: `~/src/dotclaude-skills/meeting-cross/SKILL.md` (new). Contract: cross-skill invokes canonical via Skill tool successfully against a 2-project test set. <!-- id:c3fd -->

- [ ] **2026-06-28 re-eval checkpoint** — check whether AI-5 backmerge has fired. If yes, build /meeting-cross immediately. If no, decide between (a) build /meeting-cross against sibling-topology (eat drift) or (b) extend deferral with explicit new gate. File: `~/src/dotclaude-skills/TODO.md`. Contract: re-eval recorded in a meeting note dated 2026-06-28 (or replaced by completion if AI-5 fires sooner). <!-- id:b4fd -->

- [ ] **Instrument first 3 /meeting-cross runs with cost-of.sh** — after dispatch completes, log combined-session token cost. If any of the first 3 exceeds 250k tokens, file follow-up to design handover-file mechanism (Option A in Amendment) before further cross-meetings. File: `~/src/dotclaude-skills/meeting-cross/SKILL.md` (post-implementation step). Contract: 3 cost-of.sh entries collected; threshold gate logged in meeting note. <!-- id:b427 -->

- [ ] **`MEETING_ROOT_OVERRIDE` env var documented in canonical SKILL.md** — when implementation lands, add a one-line note in `~/src/dotclaude-skills/meeting/SKILL.md` setup-step-1 that `<root>` honours the env var override (used by /meeting-cross). Contract: `grep MEETING_ROOT_OVERRIDE ~/.claude/skills/meeting/SKILL.md` returns the doc line. <!-- id:8237 -->
