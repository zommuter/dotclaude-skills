# 2026-05-14 — Orphan-scan accumulation and false-positive reduction

**Started:** 2026-05-14 18:03
**Session:** 0a410f17-8cbe-4c8c-b37a-e8873bd8f3a5
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime, project-standing)
**Topic:** Decide how to reduce orphan-scan false-positive noise and prevent in-meeting action items from accumulating as future orphans.

## Agenda
1. Triage the current orphan-scan output — true orphans vs known noise vs already-resolved-but-mis-flagged
2. Root-cause the false-positive class — why do meeting-note action items keep showing as orphans after closure?
3. In-meeting action-item provenance — how do we prevent action items written today from becoming tomorrow's orphans?
4. Immediate vs deferred work

## Discussion

### Agenda 1 — Triage

🏗️ **Archie:** 42 candidates from 4-word-key scan. ~28 already-done masquerading as orphans (AI-1..9, S1+S2, publish-meeting-skill items), ~12 conditionally-deferred-but-tracked under different phrasing, **2 true orphans**: S4 (migrate todo-update) from `2026-05-13-1950-global-todo-skill.md:127` and cross-repo Write-allowlist verify from `2026-05-14-1739:28` + `2026-05-14-1713:48`.

😈 **Riku:** "True orphan" needs sharper definition. Was S4 intentionally dropped or forgotten? Cross-repo verify — if helferli had a meeting since 2026-05-14-1739 and no prompt fired, done-but-unrecorded.

✂️ **Petra:** Through-line: the user said "we must address this!" about the accumulation problem, not individual orphans. Triage is scaffolding; load-bearing decision is structural.

😈 **Riku:** Agreed — but two true orphans still need a parking spot. Add to TODO.md as part of this meeting's action items regardless of structural fix.

### Agenda 2 — Root-cause the false-positive class

🏗️ **Archie:** Mechanism: scan extracts 4-word keys from meeting-note `- [ ]` lines, greps against `TODO.md`. When an item ships, developer closes the TODO.md entry but leaves meeting note untouched. Meeting note retains `- [ ]`, scan flags it.

⚙️ **Sage:** Correct convention — meeting notes are frozen decision records, not live tracking surfaces. Fix on scan-side, not write-side.

😈 **Riku:** Three scan-side candidates from TODO.md: (a) strip backticks/paths, (b) first-non-punctuation label, (c) stale-cutoff. Also anchor-marker injection at write-time.

🏗️ **Archie:** Option (c) regressive — loses S4 (genuinely open, 2026-05-13). Reject.

⚙️ **Sage:** Counter: most FPs are from notes >2 weeks old; backlog is a one-time problem. Maybe do nothing structural, just clean the backlog.

🏗️ **Archie:** That gut-feel needs evidence — re-eval TODO is gated on 10 invocations precisely because we agreed to measure first.

😈 **Riku (pre-emption):** empirical-pilot preference, high confidence, pre-emption-eligible — "you'd likely want to wait for the re-eval gate rather than design the structural fix now."

### Amendment — gate already fired

**Tobias:** "How many invocations do we have logged so far?"

Bash check: `wc -l ~/.claude/logs/meeting-orphan-scan.log` → **27 invocations across 4 projects**. Gate fired 17 invocations ago.

**Process failure:** Riku's pre-emption was based on the TODO's phrasing of the gate, not its current state. The log was one `wc -l` call away. Profile entry `evidence-based-constraint-validation` (Confidence: high, Pre-emption-eligible: yes) — same anti-pattern as Arc Vulkan UD-Q4_K_M deploy check, zkm-eml credentials, helferli fork-reset minimal branch. Fourth clean instance; add to Why-evidence.

😈 **Riku:** Withdrawn. Gate has fired. Empirical-pilot preference now *demands* a design pass.

🏗️ **Archie — gate results:**

Gate (a) — runtime:
| Project | n | Median ms | Verdict |
|---|---|---|---|
| dotclaude-skills | 13 | ~400 | <500, no cache |
| helferli | 5 | ~1200 | ≥1s — caching meeting warranted |
| zkm | 7 | ~2600 | ≥1s — caching meeting warranted |
| project_manager | 1 | 187 | <500, no cache |

Gate (b) — key length: cand5 > cand4 in all zkm rows (longer key → more candidates, not fewer). **Keep 4-word key.**

⚙️ **Sage:** Gates answer different questions: gate-(a) → should we cache? gate-(b) → raise key length? **Neither resolves the FP class (28 already-done items)** — that remains the load-bearing question.

✂️ **Petra:** Gate fired → design pass in-scope. Caching → parallel TODO entry, out of today's scope.

😈 **Riku:** Live candidates: (1) backtick-strip — won't recover items already removed from TODO.md; (2) stale-cutoff — regressive; (3) anchor-marker — principled but write-side burden; (4) citation-gap invert — different invariant, larger redesign.

🏗️ **Archie:** Option 1 alone won't address AI-1..9 / S1+S2 class (already removed from TODO.md). Option 3 is the only candidate that handles the dominant FP class — but requires write-side spec change.

### Re-aim — root cause is process, not scan instrumentation

**Tobias:** *"The main issue that so many orphans are left, they must be checked ASAP after being added to TODO (or even TODO.archive.md or checked against those as well). This must stop. The orphan-scan should be a failsafe, not a 'rediscover every time' mechanism."*

Actual failure modes:
1. **Action items don't reliably land in TODO.md** → scan re-discovers them every time.
2. **Closed items get archived to TODO.archive.md** (archive-done.sh, shipped 2026-05-14) → scan only reads `TODO.md`, archived items resurface every run.

🏗️ **Archie:** Verified from `orphan-scan.sh:14`: single-file read. `TODO.archive.md` exists with 37 archived items. One-line fix: union-read both files. Many of the "28 already-done" are sitting in the archive.

😈 **Riku:** Anchor markers withdrawn — every item has exactly one home (TODO.md → TODO.archive.md); scan grep targets that union.

✂️ **Petra:** Two changes: (1) `orphan-scan.sh` union-read (1 line); (2) `SKILL.md` Step 5b mandatory mirror before ExitPlanMode.

🏗️ **Archie:** Cross-project safety: `cat ... 2>/dev/null || true` falls through silently when archive missing. No regression across projects.

**Tobias (approval):** Approved. Forward-flags added: F-A (auto-mark confirmed-archived as `[x]` in meeting notes) and F-B (hash-based item ID for meeting↔TODO correlation) — both deferred.

## Decisions

- **D1** — `orphan-scan.sh:14` reads union of `TODO.md` + `TODO.archive.md`. Out of scope: any change to scanning logic (4-word key length, backtick stripping, mtime filters) — superseded by union-read + Step 5b discipline.
- **D2** — `SKILL.md` gains Step 5b: mirror action items to TODO.md before ExitPlanMode. Class 2 records and in-session-resolved items naturally excluded. Out of scope: automated enforcement hook — discipline is checked by the next scan (the failsafe).
- **D3** — TODO.md additions: S4 (migrate todo-update), cross-repo Write verify, caching-meeting forward-flag (zkm/helferli ≥1s), F-A (auto-mark), F-B (hash-based ID). Each leads with phrasing matching source meeting-note opening words.
- **D4** — Close superseded TODO items: "Orphan-scan re-evaluation" and "Orphan-scan false-positive noise" marked `[x]`. Archive-done.sh will move them next sweep.
- **D5** — Process failure recorded: Riku pre-empted on a TODO-phrased gate without checking `~/.claude/logs/meeting-orphan-scan.log`. Add fourth instance to `evidence-based-constraint-validation` profile entry.

## Action items

- [x] **Edit `orphan-scan.sh` line 14**: union-read `TODO.md` + `TODO.archive.md`. Shipped this session. Verified: cand4 dropped 46→39 on post-change re-run. <!-- inline -->
- [x] **Edit `SKILL.md` Step 1b** (Step 5b): mandatory action-item mirror to TODO.md before ExitPlanMode. Shipped this session. <!-- inline -->
- [x] **Add S4 to TODO.md**: `**S4 — migrate todo-update to dotclaude-skills**`. Shipped this session. <!-- tracked -->
- [x] **Add cross-repo Write verify to TODO.md**: `**At next helferli meeting**` phrasing. Shipped this session. <!-- tracked -->
- [x] **Add caching-meeting forward-flag to TODO.md**: `**Caching for orphan-scan.sh**`. Shipped this session. <!-- tracked -->
- [x] **Add F-A and F-B forward-flags to TODO.md**. Shipped this session. <!-- tracked -->
- [x] **Mark superseded TODO items `[x]`**: "Orphan-scan re-evaluation" and "Orphan-scan false-positive noise". Shipped this session. <!-- inline -->
- [x] **Append `evidence-based-constraint-validation` evidence in user-profile.md**: fourth clean instance. Shipped at meeting end. <!-- inline -->
