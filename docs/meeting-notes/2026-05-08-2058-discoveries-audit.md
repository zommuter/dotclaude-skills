# 2026-05-08 — Discoveries corpus audit + pilot result review

**Started:** 2026-05-08 20:58
**Session:** 46b11e6a-2a2a-4a61-bfb4-7619a87c3654
**Attendees:** Archie (architect), Riku (devil's advocate), Petra (productivity), Sage (skill-runtime, project-standing)
**Topic:** Audit `~/.claude/skills/meeting/discoveries.md` for cross-project value; interpret the JSONL-pilot result (2/10 hit rate); decide keep / cull / restructure.

## Past-meetings audit

All open action items in prior `~/.claude/docs/meeting-notes/*.md` are tracked in `~/.claude/TODO.md`. The `2026-05-08-2004-discoveries-retro-scan.md` action items are all either checked or tracked (Tier A scan ✓, JSONL pilot ✓, RAG-deferral item present). No orphans.

## Context

`discoveries.md` is one day old. Current state:
- 21 entries, 31 lines.
- Composition by source: 8 from Tier A scan (zkm + helferli meeting notes), 3 `(retro)` from JSONL pilot, ~10 from organic same-day meetings.
- Composition by domain: 5 ESP-specific (only relevant in helferli), 4 multimodal/embedding ML (only zkm), 4 Claude Code mechanics, 6 generic Python/CLI/git, 2 generic LLM.

Pilot result (from `2026-05-08-2004-discoveries-retro-scan.md`):
- 2/10 sampled JSONL sessions yielded discoveries (20% hit rate).
- Pre-set threshold: ≥30% triggers follow-up Tier B bulk scan; <30% defers indefinitely.
- 3 retro entries extracted from the 2 yielding sessions.

## Agenda

1. Pilot interpretation: is 20% a true "no" or noise? Was 30% the right threshold?
2. Cross-project audit: are the 21 entries genuinely cross-project, or has drift set in?
3. Going-forward contract: keep all sources, or change the rules?

## Discussion

### Item 1 — Pilot result interpretation

**Archie:** Pilot was well-specified — uniform random sample, binary yes/no, fixed threshold. 2/10 < 30% → protocol says "defer Tier B." The 3 extracted retro entries are orthogonal to deferral.

**Riku:** With n=10, 95% binomial CI for 20% sample rate is ~[2.5%, 55.6%]. Threshold 30% is inside that interval. The pilot cannot distinguish a true 20% from a true 30%. "Defer" was the correct protocol step, but treating 20% as confident "no signal" is overreading. What would have moved us: ≥50% rate.

**Petra:** Threshold's purpose was to avoid committing to the *bulk scan* — asymmetric costs. Miss-some-retro is recoverable; burn-a-session is not. Conservative threshold justified regardless of CI width.

**Sage:** Pilot measured *presence*, not *usefulness*. The 3 retro entries need to prove themselves by being cited at future meeting time. Verdict is months out.

**Riku:** Falsifiability: if across 10–20 meetings no retro entry is cited, the experiment failed regardless of extraction count. Need a check-in mechanism.

**Archie:** Log corpus citations; audit after ~20 meetings.

**Petra:** Simpler: eye-audit in 4 weeks. No new infrastructure. If signal, build the hook.

**Riku:** If 4-week eyeball says zero citations, no hook would have discriminated anyway. Sequence: eye-audit → upgrade to hook iff signal exists.

**User:** Eye-audit first; build citation-logging hook only if signal exists. Audit date: 2026-06-05.

### Item 2 — Cross-project audit

**Archie:** 9/21 entries are project-bound today: ESP-specific (5), multimodal/embedding ML (4). 12 are genuinely universal: Claude Code mechanics, generic Python/CLI/git, generic LLM behaviour.

**Petra:** N=2 fails for the 9 project-bound. Cull — they duplicate local meeting-notes.

**Riku:** Wrong frame. `discoveries.md` bridges *time*, not project-space. Future ESP-adjacent project won't know to look in helferli's notes. Culling loses cross-project recall.

**Archie:** Growth concern: 21 same-day → 100-entry RAG trigger within weeks at current rate. Volume controls needed before then.

**Sage:** Until RAG: prune (lossy) or tag (lossless, future-filterable).

**Petra:** Tag with `(local)` mirroring the `(retro)` convention. Borderline cases default to *not* `(local)`.

**Archie:** Rule for `(local)`: tied to a software stack only one project currently uses (ESP-IDF, esp-agents-firmware). General-purpose ML model facts stay untagged.

**User:** Tag with `(local)`. Retro-tag the 9 project-bound entries; new entries follow the convention.

### Item 3 — Citation-logging implementation

**Sage:** Path A (Stop hook, every session) vs Path B (meeting-skill instruction, per meeting).

**Riku:** Path A captures non-meeting recall — richer signal.

**Petra:** Cost is paid at meeting-load time. Measure where the cost lives.

**Archie:** Either path needs a keyword index per entry (substring match on full line is brittle).

**Petra:** Building infra to measure infra. Eye-audit first; instrument only if eye-audit shows activity.

**Riku:** Falsifiability — if 4-week eyeball says zero citations, no hook would discriminate.

**User:** Eye-audit first; hook iff signal. (Overrides earlier "build hook" call once implementation detail was exposed.)

## Decisions

- **Pilot verdict accepted.** 2/10 = 20% < 30% → no Tier B JSONL bulk scan. Already in TODO.md. Out of scope: re-piloting at larger n.
- **Overall corpus: keep, with tagging.** All 21 current entries retained. None deleted.
- **`(local)` tag introduced.** Definition: tied to a software stack only one currently active project uses. Borderline cases default to untagged. Mirrors `(retro)` convention.
- **Retro-tag pass.** Apply `(local)` to: 5 ESP entries (all `[helferli]`), BGE-M3, aya-expanse-8b, Qwen2-VL-2B/Florence-2, face-detection/recognition (all `[zkm]`). All other entries remain untagged.
- **Citation tracking: 4-week eye-audit.** On 2026-06-05, re-read `discoveries.md` and check meeting notes 2026-05-09 → 2026-06-05 for citations. If ≥1 citation found: plan citation-hook follow-up. If zero: treat retro entries as cull candidates.
- **RAG trigger unchanged.** Re-meeting when ≥100 entries OR ≥800 lines.
- **Going-forward entry rule.** New discoveries via meetings (primary) or ad-hoc. Project-bound entries must carry `(local)`. JSONL retro-extraction deferred indefinitely.

## Action items

- [x] **Tag retro pass**: apply `(local)` to the 9 project-bound entries in `discoveries.md`. Completed this session.
- [x] **Update discoveries.md header**: add tag-rule documentation. Completed this session.
- [ ] **Schedule 2026-06-05 eye-audit**: via `schedule` skill — "re-read `discoveries.md`; check meeting notes 2026-05-09 → 2026-06-05 for citations; if ≥1, plan citation-hook follow-up; if 0, plan retro-entry cull."
- [x] **Update TODO.md**: add eye-audit item, confirm RAG-trigger wording. Completed this session.
