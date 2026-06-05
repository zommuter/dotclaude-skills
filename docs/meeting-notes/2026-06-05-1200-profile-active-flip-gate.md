# 2026-06-05 — profile-active.sh flip gate cleared

**Started:** 2026-06-05 12:00
**Session:** 9a772659-be6d-46fc-9213-5e6721f47fee
**Mode:** Class 2 planning record (no meeting was held — plan-mode output)
**Topic:** Verify both conditions of the profile-active.sh flip gate and flip step 6 to --filter.

## Context

`user-profile.md` is loaded at meeting setup step 6 and persists in context for the entire meeting. Since 2026-06-01 the read goes through `profile-active.sh` in passthrough+log mode, deferring filtered output behind a two-part gate (TODO `<!-- id:f8f1 -->`). Gate: flip when **(a)** logged ratio ≤ 0.60 over ≥5 meetings AND **(b)** setup-ctx is a material fraction of meeting tokens per `cost-of.sh`.

## Plan

1. Verify condition (a): read `~/.claude/logs/meeting-profile-active.log` — 63+ entries across 4 days / dozens of meetings, all ratios 0.26–0.34, well below 0.60.
2. Verify condition (b): run `cost-of.sh` on 4 recent meeting sessions; estimate profile token contribution from per-turn multiplication.
3. If both conditions met, edit `meeting/SKILL.md` line 28 to `profile-active.sh --filter`.
4. Close TODO item `<!-- id:f8f1 -->` via `md-merge.py update-ids`.

## Implementation findings

**Condition (a):** Every logged ratio in 63 entries is 0.26–0.34 across 4 days. Baseline was 0.26 at 656 lines; current 0.34 at 846 lines (profile grew but still 66% inert). Condition clearly met.

**Condition (b):** Full profile ~846 lines / ~104 KB ≈ **~26k tokens**. Measured two meetings:
- `bf391c7a` (69 assistant turns): 5.76M total input tokens; profile contributes ~26k × ~69 ≈ 1.8M cache_read tokens ≈ **33% of meeting total**.
- `96bcbe4c` (105 assistant turns): 10.0M total input tokens; profile contributes ~26k × ~105 ≈ 2.7M ≈ **27% of meeting total**.

Both significantly above "material" threshold. Filtering to ~289 lines (~9k tokens) saves ~17k tok/turn → **~1.2M–1.7M cache_read tokens per meeting**. Condition met.

**Flip:** One-line edit to `meeting/SKILL.md` step 6 — `profile-active.sh --filter`. Logging is unconditional in the script (fires before the emit branch), so the ratio log continues for observability. No script, Makefile, or allowlist changes needed.

## Decisions
- **D1 — Gate cleared, flip to --filter:** Both conditions verified empirically 2026-06-05. Step 6 now invokes `profile-active.sh --filter`. *Out of scope:* changing the script; removing the ratio log; touching the end-of-meeting writer (it still reads the full `user-profile.md` via `md-merge.py`).

## Action items
- [x] Edit `meeting/SKILL.md` step 6 to `profile-active.sh --filter`. <!-- id:f8f1 -->
