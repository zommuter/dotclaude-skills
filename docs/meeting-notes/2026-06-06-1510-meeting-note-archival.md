# 2026-06-06 — Meeting-note archival skill (deferred; gate re-armed)

**Started:** 2026-06-06 15:09
**Session:** 5e3669a9-aef5-4e67-84b4-d4d20062b511
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime — project-standing)
**Topic:** Design the meeting-note archival skill; triggered by volume gate firing at 50 notes in `docs/meeting-notes/`.

## Surfaced discoveries
- [2026-05-10 .claude] P2 per-file symlink pattern: symlink public-safe specs/scripts into `~/.claude/skills/<skill>/`; accumulators stay local.
- [2026-05-08 .claude] Claude Code follows symlinks in `~/.claude/skills/`.
- [2026-05-08 .claude] `Stop` hooks receive `transcript_path` — relevant if a hook trigger is ever chosen.

## Agenda
1. Is archival warranted now (all notes <1mo; 0 qualify by the age criterion)?
2. Archival criterion — count-based, age-based, or hybrid?
3. Orphan-scan / gh-audit coverage if notes move to `archive/`.
4. Mechanism + trigger re-spec.

## Discussion

### Item 1 — Is archival warranted now?
- **Archie:** Count trigger (≥50) fired honestly, but age criterion (>3mo) archives ZERO today — the two metrics desynchronised.
- **Riku:** Only consumer reading all 50 notes is orphan-scan, which collapses 1,300 lines → a few-line stdout digest. No measured context or runtime pain in this repo. Min evidence to build: over-gate scan runtime here — absent.
- **Sage:** Confirmed — dotclaude-skills not in the over-gate list (zkm ~2,600ms, helferli ~1,200ms; this repo fast).
- **Petra:** "Observe before preventing." Build → zero files first run, no measured cost = premature. N=2 consumers of `archive/`: nobody.
- **Archie:** Gate will fire every meeting at 50 notes = noise. Fix the gate even if build is deferred.
- **Riku:** Agreed — cheap correct action is sharpen the trigger, not build machinery.

### Item 2 — Criterion and cost controlled
- **Petra:** Real cost is orphan-scan runtime; age is a poor proxy. Honest criterion = "fully-resolved AND old" — else archival could hide live orphans.
- **Archie:** Simpler: age-only but orphan-scan keeps reading `archive/` for un-closed IDs.
- **Riku:** Invariant — **archiving must not change orphan-scan's verdict** (silent-miss is the flagged failure mode from the 2026-05-14 bloat audit).
- **Sage:** Teaching orphan-scan to recurse `**/*.md` into `archive/` is one line, near-zero cost, removes silent-miss risk. But then archival only buys cosmetic tidiness.
- **Petra:** If scan still reads archived notes, archival = cosmetic only. Not worth a skill at this stage.

**Decision point 1 → Defer build, sharpen the gate.**

### Items 3+4 — Gate re-spec (since build is deferred)
- **Archie:** Change gate to `count ≥ 50 AND oldest note > 3 months` so firing implies work-to-do; gate age = archive horizon, kept in sync.
- **Riku:** Phrase as a build-warrant, not a per-meeting alarm — record "deferred, gate re-armed" in the TODO line so it isn't re-litigated.
- **Sage:** Trigger is prose in the classifier TODO. Fix = one TODO-line edit. Won't re-fire before ~2026-08-08.
- **Petra:** Whole change this session = one TODO line + this note. No script, allowlist, or symlink.
- **Archie:** Cross-link to "Caching for orphan-scan.sh" TODO — its >1s runtime signal is the real build-warrant for archival.
- **Riku:** Recorded invariant for future build: orphan-scan must **recurse into `archive/`, never skip it**.

**Decision point 2 → 3-month horizon** for gate age and archive cutoff.

## Decisions
- **Defer the archival skill build.** Rationale: volume gate fired at 50 notes, all <1 month old → 3-month archive criterion moves zero files; dotclaude-skills orphan-scan not over the 1s runtime gate; "observe before preventing" + N=2 (no consumer of `archive/`) → premature.
- **Re-spec trigger** (prose-only change to TODO): open `/meeting meeting-note-archival` when `docs/meeting-notes/` has **≥50 notes AND at least one note is older than 3 months**. Won't re-fire before ~2026-08-08.
- **Archive horizon = 3 months** when eventually built (gate age == archive cutoff).
- **Build-invariant (recorded for future implementer):** archival must NOT change orphan-scan's verdict. The eventual script must teach orphan-scan / `--reverse` / `gh-audit` to **recurse into `archive/` (`**/*.md`), never skip it**. Cosmetic move only; coverage preserved.
- **Real build-warrant:** the "Caching for orphan-scan.sh" TODO tracks dotclaude-skills scan runtime. If this repo joins zkm/helferli over the 1s gate, *that* is when archival becomes worth building — cross-link the two TODO lines.
- **Out of scope:** archival script, the "fully-resolved AND old" orphan-state-coupled criterion (over-machined for a no-measured-cost problem), and `archive-done.sh` (lives in `todo-update`, unrelated).

## Action items
- [x] Update the "Meeting-note archival skill" TODO line: re-spec trigger to `≥50 notes AND oldest note >3 months old`; record deferral + gate re-arm; cross-reference this note and the orphan-scan caching TODO. Completed in-session. <!-- id:af88 -->
