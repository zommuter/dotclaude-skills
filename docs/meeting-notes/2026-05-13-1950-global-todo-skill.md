# 2026-05-13 — Global TODO skill / cross-project task tracking

**Started:** 2026-05-13 19:50
**Session:** 8722d113-ec82-4c6f-a11d-e045dfac5472
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime — standing for dotclaude-skills)
**Topic:** Decide whether to build a `/todo` skill for cross-project add/list/close, defer in favour of existing infra (`todo-update` + `project_manager`), or adopt GH Issues for shareable repos.

## Agenda

1. Problem framing — what unmet friction exists *given* `todo-update` (write) + `project_manager` (read)?
2. Cross-project homeless items — is `~/.claude/TODO.md` the right venue or should it be structured?
3. Options inventory — defer / `/todo` skill / GH Issues / hybrid / lever-first.
4. Decision criterion — minimum evidence that flips the answer.
5. MVP scope of chosen option.

## Discussion

### 1 — Problem framing

Archie mapped the current state: `todo-update` (mandatory after-prompt skill) owns the write side and TODO.md format; `project_manager` (built 2026-05-13) owns the cross-project read side via `proj` CLI + `/projects` skill. The "unmet friction" claim in the original TODO predates `project_manager`.

Riku enumerated the operations on TODO.md: add (works via Edit), close (works via Edit), list (works via `/projects` + cat), cross-repo migrate (mildly awkward). None individually warrants a new skill.

Petra applied the N=2 test to a hypothetical `/todo` skill — no real second consumer beyond Claude-via-Edit. Cross-machine sync of `~/.claude/TODO.md` is already covered by the dotfiles repo.

Sage noted that a `/todo add` slash command would save the user maybe 4 seconds of typing (Claude already drives TODO writes via Edit) — not the win the original TODO assumed.

Archie raised one genuine friction: adding an item to a non-cwd project from inside another session (cross-repo Edit). Riku endorsed "observe before preventing" per the CLAUDE.md heuristic — count the events before building.

**Tobias intervention:** the real friction is **finding/dedup in long TODOs**, not cross-repo add.

### 2 — Finding & dedup as the actual problem

Archie surveyed TODO.md sizes — `.claude` short, dotclaude-skills moderate, zkm/helferli longer; Done sections grow unboundedly because `todo-update` only moves items down, never archives.

Riku decomposed the "finding/dedup" complaint into three sub-problems:
- (A) Pre-add lookup — no enforcement; duplicates trivially possible.
- (B) Find-an-existing-item on close — slow on long files.
- (C) Done section bloat — old `[x]` entries crowd out signal.

Petra ranked lowest-cost fixes: (C) archive script — biggest improvement, smallest blast radius. (B) becomes easier once (C) is solved. (A) needs near-match detection; prefix-grep is the cheap version.

Sage offered two skill-runtime patterns: procedure-in-SKILL.md (cheap, may be skipped under load) vs. separate skill with logic (heavier, format-drift risk).

Riku flagged the procedure-skip failure mode (Sonnet skips steps under load) but said it's not worse than today.

### 2b — Deeper trade-off review

After user pushback toward Option 3 (full /todo skill) and pointers to (a) the existing global CLAUDE.md workflow, (b) GH Issues on backlog, (c) possible zkm-query reuse, the personas re-evaluated:

Sage: `todo-update` already owns TODO.md format. Adding a `/todo` slash command creates a second touchpoint with protocol-drift risk (same shape as the `discoveries.md` Edit-vs-append.sh drift, resolved by mandating `append.sh`).

Archie surfaced two binding prior decisions:
- **2026-05-13 zkm/per-plugin-todo-topology** — keep a single central TODO.md; trigger GH Issues migration only on first outside PR/issue. The user's own recent anti-premature-tracker stance.
- **dotclaude-skills/TODO.md F1–F3** — write-to-GH-Issues falls out of the F1–F3 read-side work *for free* once topology-3 fires.

Riku named two failure modes for Option 3:
- F1: reinvents issue tracking (user-named risk).
- F2: invocation friction *higher* than Edit — Claude (not user) is the actual writer; slash command adds parse/compose/handle overhead.

Petra applied the real N=2: no second consumer where `/todo add` beats Edit. Cross-repo Edit works today; fuzzy dedup is the F1-issue.

Archie rejected zkm-query-as-fuzzy-backend on coupling grounds — meta-skill must not depend on a project-specific tool. Cross-project schema leverage is about schema join points (rfc5322, iso13616), not application-consumer coupling. `grep -i` on short `[ ]` lines is enough.

Sage reframed as lever-first (per user profile): extend existing levers (`todo-update`, `project_manager`/`proj`, `grep`) rather than add a new top-level skill. → **Option 5**: `proj grep '<pattern>'` for cross-project search + archive + grep-before-add in `todo-update`.

Riku said the "leaning toward 3 yet overengineered" gut-check was well-calibrated. Option 3 is the symptom of "I want a tool" when the operation is well-served by Edit + stricter procedure.

### 3 — MVP scope of Option 5

Archie laid out three sub-deliverables, independently shippable:
- **S1** `archive-done.sh` (Bash, in `todo-update/`) — moves `[x]` entries with parseable `on YYYY-MM-DD` ≥30 days old to sibling `TODO.archive.md` under `## YYYY-MM` headers. Idempotent; safe-default-keep on undated entries.
- **S2** `todo-update` SKILL.md amendments — Step 2 grep-before-add guidance (~3 lines) + Step 4 (new) call to S1.
- **S3** `proj grep '<pattern>'` (new subcommand in project_manager CLI) — cross-project line search over `TODO.md` + `TODO.archive.md`, case-insensitive substring; default `[ ]` only, `--all` includes `[x]`/free text.

Riku flagged risks: S2 procedure-skip (mitigated by terse leading guidance); S1 inflation of `TODO.archive.md` (revisit if any project exceeds 200 lines in 3 months); S3 `grep` verb semantics (document as case-insensitive substring).

Petra explicitly out-of-scoped: GH Issues read/write (separate F1–F3 work), cross-project auto-merge, meeting-note `## Action items` grep (`proj show` already counts M-orphans), retention-threshold tuning before first cycle.

Sage on sequencing: S1+S2 co-ship to dotclaude-skills (one logical change); S3 ships separately in project_manager.

### 4 — Decision criterion (when to revisit)

- → Option 3 (full /todo) if: S2 procedure skipped >50% of relevant sessions AND prefix-grep proven insufficient.
- → Option 6 (defer to GH Issues) if: topology-3 trigger fires AND F1–F3 lands. S5 deliverables remain useful.
- → Re-tune archive threshold if: `TODO.archive.md` exceeds 200 lines on any project within 3 months → year-buckets.
- Date-trigger: 2026-08-13 — check S2 dedup adoption, `proj grep` usage count. Retire S3 if zero invocations.

### Amendment session — migrate `todo-update` to `dotclaude-skills`

**Tobias:** Should `todo-update` move to dotclaude-skills like `meeting`, `git-diary-workflow`?

Sage: yes — `todo-update` is the only user-defined skill not on the publish path, and we're about to add `archive-done.sh` to it.

Archie: migration shape mirrors `2026-05-11-1520-diary-skill-migration`:
- Move SKILL.md to `~/src/dotclaude-skills/todo-update/SKILL.md` (verbatim first commit).
- Add `archive-done.sh` in same dir as second commit.
- P2 symlinks in `~/.claude/skills/todo-update/`.
- Add README.md (install + chmod +x), update top-level README skills table + Makefile (verify install loop).

Riku: Step 1c in `git-diary-workflow/SKILL.md` already auto-commits substantive changes in any `~/src/dotclaude-skills/<skill>/` spec file — new `todo-update/` falls in for free. Migration-provenance pattern (verbatim then evolve) applies.

Petra: bundle with S1+S2 v0 ship to avoid editing `archive-done.sh` in two places later.

**Tobias decision:** Migrate as a *separate ship* (S4 first, then S1+S2 follow-up) for git granularity and clean migration-provenance commits.

## Decisions

- **D1 — Option chosen: lever-first (Option 5) + standing posture defer to GH Issues (Option 6).** No new `/todo` top-level skill. Cross-project read stays on `/projects`; format ownership stays on `todo-update`. Out of scope: full `/todo add/list/close` skill, fuzzy semantic match, GH Issues integration (gated by topology-3 trigger).
- **D2 — S1 archive-done.sh**: Bash script in `~/src/dotclaude-skills/todo-update/`. Moves `[x] foo — verified ... on YYYY-MM-DD` entries ≥30 days old to sibling `TODO.archive.md` under `## YYYY-MM` headers. Idempotent. Lines without parseable date stay in `TODO.md` (safe-default). Allowlist: `Bash(~/.claude/skills/todo-update/archive-done.sh)` global. Out of scope: non-date-suffix archival, retention beyond 30 days configurable.
- **D3 — S2 todo-update amendments**: Add Step 2 grep-before-add guidance (~3 lines) + Step 4 calling S1 opportunistically (once per session, skip if file <50 lines). Out of scope: Stop-hook enforcement of grep — escalate only if procedure-skip rate >50%.
- **D4 — S3 proj grep**: New subcommand in `~/src/project_manager/src/project_manager/cli.py`. Iterates `include.toml` projects; case-insensitive substring grep over `TODO.md` + `TODO.archive.md`; default `[ ]` lines; `--all` includes `[x]`/free text; output `<project>:<line>`. Out of scope: scoring/ranking, semantic match, meeting-note grep (separate v2 `--meetings` flag).
- **D5 — S4 migration**: Move `todo-update` SKILL.md to `~/src/dotclaude-skills/todo-update/` as a verbatim first commit, add README + Makefile/top-level README updates, install P2 symlinks. Ships *before* S1+S2 as a separate session for git granularity. Out of scope: bundling commit 1 (verbatim) with commit 2 (archive-done.sh + amendments).
- **D6 — Sequencing**: S4 first (verbatim migration). Then S1+S2 in a follow-up session targeting the new `~/src/dotclaude-skills/todo-update/` location. S3 ships independently in project_manager (any order vs. S1/S2/S4).
- **D7 — Revisit trigger**: 2026-08-13 (3 months) — check S2 dedup adoption + `proj grep` usage. Retire S3 if zero invocations. Re-tune S1 threshold if any `TODO.archive.md` >200 lines.

## Acknowledged future scope (not v0)

1. Full `/todo` skill — only if procedure-skip rate >50% AND prefix-grep proven insufficient.
2. GH Issues read/write integration — falls out of F1–F3 read-side work when topology-3 trigger fires.
3. Meeting-note `## Action items` grep via `proj grep --meetings`.
4. Fuzzy semantic dedup — only if prefix-grep proves insufficient.
5. Year-bucketed archive sections — if any `TODO.archive.md` exceeds 200 lines within 3 months.

## Action items

- [ ] **S4 — migrate todo-update to dotclaude-skills** (separate session, first): create `~/src/dotclaude-skills/todo-update/SKILL.md` verbatim from `~/.claude/skills/todo-update/SKILL.md`; add `README.md` (install + chmod +x); update top-level `README.md` skills table; update `Makefile` install target if explicit-per-skill; P2 symlink `~/.claude/skills/todo-update/SKILL.md → ~/src/dotclaude-skills/todo-update/SKILL.md`. Contract: `ls -la ~/.claude/skills/todo-update/` shows symlink; skill still loads (`/todo-update` not invocable but `todo-update` skill triggers).
- [ ] **S1 — archive-done.sh** (after S4, in `~/src/dotclaude-skills/todo-update/`): Bash script with the spec in D2; allowlist entry `Bash(~/.claude/skills/todo-update/archive-done.sh)`. Contract: synthetic `TODO.md` round-trip (old-dated `[x]` moves; fresh and undated stay; idempotent re-run).
- [ ] **S2 — todo-update SKILL.md amendments** (with S1): Step 2 grep-before-add (~3 lines) + Step 4 archive call (skip if file <50 lines). Contract: SKILL.md reads consistently; archive call falls through cleanly on small files.
- [ ] **S3 — proj grep subcommand** (in `~/src/project_manager/`, any order vs. above): add to `cli.py`; matches over `TODO.md` + `TODO.archive.md` (case-insensitive substring); default `[ ]` only; `--all` flag. Contract: `proj grep "settings"` returns matches across ≥2 projects formatted `<project>:<line>`.
- [ ] **Revisit on 2026-08-13**: check S2 dedup adoption rate + `proj grep` invocation count. Retire S3 if zero uses. Re-tune S1 threshold if any `TODO.archive.md` >200 lines.
