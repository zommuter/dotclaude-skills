# 2026-05-14 — Disable orphan-scan pending proper fix

**Started:** 2026-05-14 20:16
**Session:** c1c60e7f-be0f-499e-8239-d4ab060efff4
**Mode:** Directive (no meeting held — user issued a direct instruction)
**Topic:** Suppress orphan-scan in meeting skill until F-A or F-B redesign ships

## Context

Default-mode `/meeting` ran orphan-scan as usual. Of the 10 candidates shown (28 more suppressed by cap), only 1 was a genuine orphan not in TODO.md. The rest were stale meeting-note items whose action items were already tracked (and several already closed) in TODO.md, but phrased differently enough that the 4-word key match failed.

This is the second incident. The first (2026-05-14-1803-orphan-scan-accumulation.md) addressed the union-read fix and output cap, but did not fix the root FP class: action items with different phrasing in meeting notes vs TODO.md always resurface.

User response: "Still no orphans cleanup >:( Disable it in the meeting skill until we properly fix this."

## Decisions

- Orphan-scan (`orphan-scan.sh`) disabled in `meeting/SKILL.md` in both invocation paths:
  - "With a subject" step 2: replaced with DISABLED note
  - "With no subject" step 1: scan call removed
- Re-enable only after F-A (auto-mark archived items) or F-B (hash-based item ID) ships and FP rate is demonstrably low.
- Out of scope: modifying orphan-scan.sh itself; that is deferred to the F-A/F-B design sessions.

## Action items

- [x] Disable orphan-scan in `meeting/SKILL.md` (both paths) — done this session.
- [ ] Re-enable after F-A or F-B ships. See TODO.md "Re-enable orphan-scan in SKILL.md".
- [ ] Amend `discoveries.md` γ-class entry (genuine orphan from this scan). See TODO.md.
