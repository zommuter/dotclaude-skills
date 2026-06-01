# 2026-06-01 — Discoveries citation eye-audit

**Started:** 2026-06-01 13:31
**Session:** bf391c7a-672f-4609-8434-06de643cb3a1
**Mode:** Class 2 planning record (no meeting was held — plan-mode output)
**Topic:** 4-week citations eye-audit of discoveries.md; decide whether to build citation-logging Stop hook.

## Context

Follow-up from `2026-05-08-2058-discoveries-audit.md` decision: "If ≥1 citation found across meeting notes 2026-05-09 → 2026-06-05: plan citation-hook follow-up. If zero: treat `(retro)` entries as cull candidates."

Audit date: 2026-06-01 (4 days before the 2026-06-05 gate; earlier is fine).
discoveries.md at audit time: 242 lines, ~65 entries.

## Plan

Grep all meeting notes in `docs/meeting-notes/` dated 2026-05-09 through 2026-06-01 for "discover" occurrences, then inspect for genuine citations (i.e., discovery entries being surfaced as relevant to a decision, not mere references to "the discoveries file" as infrastructure).

## Implementation findings

**Citation count: 7+ instances across 17 meeting notes scanned.**

Explicit "## Surfaced discoveries" sections (the standard header format, already in use organically):
1. `2026-05-10-1658-publish-meeting-skill.md` — 3 entries surfaced (symlink-follow, Bash-shape-sensitive, `$CLAUDE_SESSION_ID` heredoc rules)
2. `2026-05-14-1015-skill-ctx-bloat-audit.md` — 4 entries surfaced (Stop-hook transcript_path, Bash shape-sensitive, symlink-follow, README not in P2 loop)

Inline recall references (discoveries cited mid-discussion to inform a decision):
3. `2026-05-14-1713-class1-sweep.md` — "per `2026-05-11-1024-allowlist-path-resolution` discovery" (cwd-relative Write allowlist)
4. `2026-05-14-1204-stray-todo-merge.md` — "per ctx-bloat discovery" (Sage pre-empting with the 83-line SKILL.md size finding)
5. `2026-05-15-1121-todo-update-prune-empty-sections.md` — "the 2026-05-14 77%-bypass discovery"
6. `2026-05-20-1645-meeting-skill-broker-integration.md` — "Discovery 2026-05-10 (glob-swallow)" used to scope broker-curl allowlist pattern
7. `2026-05-21-1037-avoid-claude-cwd.md` — "2026-05-14 discovery: tilde allowlist patterns match absolute file_path args"

**Verdict: protocol says "plan citation-hook follow-up."**

Also noted: the "## Surfaced discoveries" section was appearing organically in meeting notes but was not in `format.md`'s template — a drift source that would make future grep-based audits harder.

## Decisions

- **Citations confirmed.** discoveries.md is actively used — both surfaced at meeting start (7 entries across 2 meetings) and recalled inline mid-discussion (5+ instances).
- **No Stop hook yet.** Manual eye-audit is cheap and sufficient at current discovery count (~65 entries). Automated logging adds per-session overhead with unclear payoff until the file grows significantly.
- **Gate for Stop hook design.** Open `/meeting citation-logging-hook` when ≥1 of: (a) discoveries.md reaches 100 entries, (b) 6-month eye-audit (≈2026-12-01) finds >5 cited entries per meeting on average.
- **Standardize "## Surfaced discoveries" in format.md template.** Cheapest immediate improvement: makes future eye-audits grep-reliable without building any hook infrastructure. Omit the section if no discoveries were surfaced (not mandatory). Added to `format.md` this session.
- **`(retro)` entries retained.** They were cited (`2026-05-14-1015` surfaced a retro entry); not cull candidates.

## Action items

- [x] Scan meeting notes 2026-05-09 → 2026-06-01 for citations — done this session.
- [x] Add `## Surfaced discoveries` to `format.md` template — done this session.
- [x] Close audit TODO item; add condition-triggered citation-hook planning item to `TODO.md` <!-- id:ab70 --> — done this session.
