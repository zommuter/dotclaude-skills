# 2026-05-08 — Scan past sessions/dumps for discoveries?

**Started:** 2026-05-08 20:04
**Session:** 25a896c8-d78f-47fb-bae0-43353f750b6c
**Attendees:** Archie (architect), Riku (devil's advocate), Petra (productivity), Sage (skill-runtime, ad-hoc)
**Topic:** Should the meeting skill's `discoveries.md` be seeded by scanning past Claude Code sessions, project meeting notes, and the claude.ai export?

## Context

`discoveries.md` was created today (2026-05-08) and currently holds 11 entries — all from meetings held the same day. The skill is one day old. Available corpora to mine:

- `~/.claude/projects/*/*.jsonl` — 364 session transcripts, 223 MB. Full Claude Code sessions including tool calls.
- `~/.claude/docs/meeting-notes/*.md` — 6 prior meeting notes.
- Other projects' `docs/meeting-notes/` (e.g. `~/src/zkm/`, `~/src/helferli/`).
- `~/src/claude-diary/claude.ai-export/conversations.json` (+ memories.json, projects.json) — 33 MB claude.ai export.

A "discovery" per current convention = a technical fact (tool, command, library quirk, infrastructure pattern) that may apply across projects.

## Agenda

1. Is the expected signal worth the extraction cost? (volume vs cross-project hit rate)
2. Which corpora are in scope? (Claude Code JSONL, claude.ai export, project meeting notes, all/some)
3. What extraction approach? (bulk LLM, heuristic pre-filter + LLM, manual curation, none)
4. What is the contract for an extracted entry? (format, dedup, attribution to source session)

## Discussion

### Item 1 — Signal vs cost

**Archie:** The corpora differ sharply. Claude Code JSONL is codebase-grounded — every entry has file paths, commands, exit codes. That's where we found things like `transcript_path` containing tool calls and `$CLAUDE_SESSION_ID` always being set. Across 364 sessions, the prior probability that *some* yield a cross-project fact is high. The claude.ai export is general-chat — most of it is research/Q&A without code. The meeting-notes corpus is 6 files I can re-read in one read tool call.

**Riku:** "The prior probability is high" is not a measurement. We have **one day** of `discoveries.md` data — 11 entries from ~5 meetings. That's ~2 discoveries per meeting, but every one of those came from active work where the lens was already on. Mining a passive transcript is a different task. What's the minimum evidence that would change this decision? I'd want a pilot: sample 10 random sessions, count how many yield even one cross-project fact. If it's <30%, the bulk scan is not warranted at any cost.

**Petra:** Scope check. This is N=2: who consumes `discoveries.md`? Right now it's loaded by the meeting skill at audit time, plus possibly future search. That's one consumer. Adding 100 entries makes audit-time loading slower and noisier — every meeting would have a wall of "potentially relevant" entries the model has to filter. Until we have a second consumer (search? a `/discover` skill? a periodic review?), bigger ≠ better.

**Sage:** The skill loads `discoveries.md` verbatim into context at every meeting setup. At 11 entries it's ~80 lines. At 200 entries it'd be ~1500 lines — that pushes against the meeting-skill's lean spec. A volume-based threshold matters here.

**Riku:** And there's a sampling bias: a session where I solved a hard problem will phrase the discovery clearly *in passing*; a session where I struggled and then moved on probably never frames the takeaway. So scanning skews toward solved problems, which we're least likely to need to remember (the code already encodes the solution).

**Archie:** Counter: the meeting-notes corpus is small and curated. Mining the 6 prior meeting notes is cheap (one Read each) and the discoveries inside are already formatted as decisions. That's a different proposition from mining 223MB of JSONL.

### Item 2 — Corpora in scope

**Archie:** Three tiers:
- Tier A — project meeting notes across `~/src/*/docs/meeting-notes/`. Small, structured, high signal.
- Tier B — Claude Code JSONL. Large, semi-structured, mixed signal.
- Tier C — claude.ai export. Large, unstructured, low expected signal for *technical-infrastructure* discoveries.

**Petra:** Tier A is already partly captured — half the existing entries cite zkm/helferli meeting notes. The discoveries.md format already requires "see <path>", which means they've been pulled in as the corresponding meetings happened. A separate scan duplicates the natural flow.

**Riku:** What does Tier C actually contain that's unique? The claude.ai export is web-app conversations — usually reading/research/explaining. Tier B has all the work that touches a real machine. The disjoint set Tier C has is "things I researched but never built" — it's hard to argue those are discoveries about *this* environment.

**Sage:** One concrete Tier C value: `memories.json` from claude.ai may contain claude.ai's own memory entries — which are explicitly user-saved facts, already curated by past-Claude. That's high-signal-per-byte even if low total volume.

### Item 3 — Extraction approach

**Archie:** If we do anything, the cheapest credible plan is:
1. Skim `~/src/claude-diary/claude.ai-export/memories.json` once — it's curated, small.
2. Skim project meeting notes outside `~/.claude/` (zkm, helferli) once — already structured.
3. Skip JSONL bulk scan unless a pilot says otherwise.

**Riku:** Pilot test for Tier B: sample 10 sessions uniformly at random, ask "does this session contain a cross-project technical fact not already in `discoveries.md`?" If hit rate ≥30%, plan a heuristic-filtered scan. If <30%, file a `defer` decision and move on. Cost of pilot: ~1 session worth of attention.

**Petra:** Even simpler: rule that *new* discoveries enter `discoveries.md` only via meetings. No retroactive scan. Past data stays as-is; the meeting skill builds the corpus going forward. This is the do-nothing option and it's not obviously wrong.

**Archie:** "No retroactive scan" leaves real value on the floor. The Tier A scan (project meeting notes) is essentially free — one read per file, ~10 files total. Skipping it is over-correction.

**Sage:** Hybrid: do the cheap Tier A pass now, defer Tier B behind a pilot, skip Tier C except `memories.json`.

### Item 4 — Entry contract

**Archie:** Existing format: `- [YYYY-MM-DD <project>] <one-sentence finding> — see <source-path>`. Source-path is meant to be a meeting note. For retroactively extracted entries from JSONL there's no meeting note — should source be the session ID? A session JSONL path?

**Riku:** If we extract from JSONL, source must be `~/.claude/projects/<project>/<session-id>.jsonl` so the claim is auditable. Without a back-pointer, a reviewer can't verify. Date should be the session date, not the extraction date.

**Petra:** Add a marker for retroactively-mined entries — e.g. a `(retro)` tag — so they can be batch-removed if the experiment fails. Without that, mixing them with meeting-sourced entries makes rollback a manual diff.

### Amendment — RAG for discoveries.md

**Sage:** RAG would mean embedding each entry and retrieving top-k at meeting setup, decoupling corpus size from context cost.

**Archie:** Non-trivial footprint: embed store (sqlite-vss / chroma / flat npy), embed-on-write hook, retrieval call. zkm already runs BGE-M3 locally — infrastructure exists.

**Riku:** Premature. File is 21 lines today; trigger should be measurable, not vibes.

**Petra:** Defer with explicit trigger: entry count ≥100 OR line count ≥800. Whichever fires first opens `/meeting RAG-for-discoveries`.

**Sage:** Agreed.

### Pilot spec (Tier B)

- Sample: 10 sessions uniformly at random from `~/.claude/projects/*/*.jsonl`.
- Reader: one Claude Code session, one yes/no question per sample plus the fact if yes.
- Threshold: ≥30% (3/10) → plan heuristic-filtered Tier B scan in follow-up meeting. <30% → defer indefinitely.
- Output: append all yes-findings to `discoveries.md` with `(retro)` tag regardless of threshold.

### Entry contract (retro)

```
- [YYYY-MM-DD <project>] (retro) <fact> — see ~/.claude/projects/<project>/<session-id>.jsonl
```
- Date = session date from JSONL timestamps.
- Project = derived from directory name.
- `(retro)` tag for grep-based rollback.
- Source = full JSONL path.

Rule: retro entry only if not already in `discoveries.md` and would have warranted a meeting-sourced entry.

## Decisions

- **Tier A pass (project meeting notes)**: read all `~/src/*/docs/meeting-notes/*.md` files outside `~/.claude/`; extract any cross-project technical facts not yet in `discoveries.md`. Out of scope: re-deriving project-specific design rationale. Format: standard (not `(retro)`-tagged) — these cite meeting-note paths.
- **memories.json pass**: read `~/src/claude-diary/claude.ai-export/memories.json` once; extract cross-project technical facts. Source path = the export path. Out of scope: `conversations.json`, `projects.json`, `users.json`.
- **JSONL pilot**: sample 10 random sessions from `~/.claude/projects/*/*.jsonl`; measure hit rate per pilot spec above. Threshold ≥30% triggers a follow-up meeting on heuristic-filtered Tier B scan. Out of scope: bulk LLM scan in this session.
- **claude.ai conversations.json**: skipped. Low signal density for technical-infrastructure facts; revisit only if a specific search need arises.
- **Retro entry format**: `(retro)` tag + JSONL session-path source for any pilot-extracted entries. Date = session date, not extraction date.
- **RAG deferral**: no embedding/retrieval infrastructure now. Trigger for re-meeting: `discoveries.md` reaches ≥100 entries OR ≥800 lines.

## Action items

- [ ] Tier A scan: list `~/src/*/docs/meeting-notes/*.md` outside `~/.claude/`; read each; append cross-project facts to `~/.claude/skills/meeting/discoveries.md`. Contract: every appended line cites the meeting-note path; no duplicates of existing entries.
- [ ] memories.json scan: read `~/src/claude-diary/claude.ai-export/memories.json`; append cross-project facts to `discoveries.md` with source = export path.
- [x] JSONL pilot: **2/10 sessions yielded discoveries (20% hit rate, below 30% threshold → no Tier B scan planned)**. 3 retro entries appended to `discoveries.md`. Completed 2026-05-08.
- [ ] Update TODO.md: add RAG-for-discoveries volume-triggered revisit item.
