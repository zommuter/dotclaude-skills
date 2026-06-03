# 2026-06-03 — Citation-logging hook: gate re-specification

**Started:** 2026-06-03 14:02
**Session:** 20bf8d6f-bf3c-4927-8ae2-95b2f68ef0e7
**Mode:** Class 2 planning record (no meeting was held — plan-mode output)
**Topic:** Re-specify the citation-logging hook gate after live-state check found the entry-count trigger payoff-blind.

## Context

TODO item `ab70` ("Citation-logging hook design") had a two-part gate:
(a) discoveries.md exceeds 100 entries — OR — (b) 6-month eye-audit finds >5 citations per meeting.

The item was classified as Class 2 in a no-arg `/meeting-live` dispatch on this date under the assumption the gate had not yet fired. Live-state checks falsified that assumption and surfaced a deeper metric problem.

## Plan

1. Check live entry count and line count of discoveries.md.
2. Compare against the audit's estimate and the gate threshold.
3. Evaluate whether the entry-count gate tracks the hook's actual payoff (citation frequency).
4. Decision: demote or retain the count gate?

## Implementation findings

- `grep -c '^- \[20' ~/.claude/skills/meeting/discoveries.md` → **140 entries**, well past the 100 trigger.
- File is only **259 lines** — 040c's "≥800 lines" threshold has not fired.
- The 2026-06-01 audit estimated "~65 entries" — off by ~2× (grew by 75 entries in 2 days; those were added in zkm and meeting-rpg meeting notes on 2026-06-01 and 2026-06-03).
- Citation rate measured by the 2026-06-01 audit: **7 across 17 notes ≈ 0.4 citations/meeting**. Gate (b) threshold is >5/meeting. Rate is nowhere near.
- Conclusion: entry count is a payoff-blind proxy. A file can grow rapidly (high-productivity sessions) without citations increasing proportionally. The hook's marginal value scales with *how often it would record something*, not with file size.
- Pre-gate action status: `## Surfaced discoveries` is in `format.md` lines 60–62 in both `meeting/` and `meeting-live/`. Marked `[x]` in the 2026-06-01 audit note. Done.

## Decisions

- **Entry-count trigger (a) removed.** It is a payoff-blind proxy — fired at 140 entries while citation rate was 0.4/meeting. A file growing from active sessions is not evidence the hook would get useful data.
- **Citation-rate audit is the sole gate.** Open `/meeting citation-logging-hook` when an eye-audit finds >5 surfaced/cited discoveries per meeting on average. Measurement method: count `## Surfaced discoveries` section entries + inline recall references across recent meeting notes, divide by notes scanned.
- **Re-audit checkpoint: 2026-12-01** (original 6-month date), or sooner if citations visibly spike.
- **040c thresholds unchanged.** That item tracks ctx-load cost (retrieval helper), not hook payoff. The concerns are distinct; shared-proxy divergence is now moot since the hook no longer reads entry count.
- **Current descriptive reading recorded:** 140 entries / 259 lines / ~0.4 citations per meeting (2026-06-03).

## Action items

- [x] Revise `ab70` in `TODO.md`: remove entry-count trigger, pin citation-rate as sole gate, document current reading and measurement method — done this session.
- [x] Write this planning record — done this session.
