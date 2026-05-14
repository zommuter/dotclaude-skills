# 2026-05-14 — Stray TODO.md merge + /todo-update + /meeting subdir handling

**Started:** 2026-05-14 12:04
**Session:** a5b3c6e1-aed2-4162-a4d3-e01203fe9465
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime — standing per project override)
**Topic:** Merge accidental `git-diary-workflow/TODO.md` into root `TODO.md`; amend `/todo-update` and `/meeting` to detect/warn about subdirectory TODO.md files; defer subproject topology to F1–F3.

## Agenda

1. Mechanical merge of the stray file
2. `/todo-update`: detect/warn about subdir TODO.md files — enforcement level
3. `/meeting`: should no-arg classifier / orphan-scan see subdir TODO.md files?
4. Subproject topology (forward-flag): stray vs. legitimate sub-repo TODO.md

## Discussion

### Item 1 — Mechanical merge

🏗️ **Archie:** The stray file exists in git history (commit c81abd2, 2026-05-13) with one well-specified item — `git-lock-push.sh` fails with `fatal: couldn't find remote ref claude` on first push of a new branch with no upstream. Root TODO.md uses prefix-namespaced sections (`## meeting skill`) — same convention zkm settled on. Natural home: add `## git-diary-workflow` section, paste the item, `git rm git-diary-workflow/TODO.md`.

✂️ **Petra:** N=1 on item content, mechanical merge. Out of scope: editing item text, fixing the bug, back-rewriting commit c81abd2.

😈 **Riku:** (1) Item text is well-specified — preserving it in root TODO.md is the goal. (2) If other repos also have stray TODO.md files, the detection question (Item 2) is load-bearing.

⚙️ **Sage:** No skill-runtime concern. The `git rm` happens in the next git-diary-workflow run.

### Item 2 — /todo-update stray detection

🏗️ **Archie:** Three enforcement levels: (α) ignore, (β) warn, (γ) block/auto-merge. Concrete (β) shape:
```bash
find . -mindepth 2 -maxdepth 3 -name TODO.md \
  -not -path './.git/*' -not -path '*/node_modules/*' \
  -not -path '*/.venv/*' -not -path '*/*/.git/*' 2>/dev/null
```

✂️ **Petra:** N=1 incident today; zkm explicitly chose against per-plugin TODOs. Strongest legitimate case is a git submodule → Item 4. N=1 doesn't earn γ, does earn β at ~5 bash lines.

😈 **Riku:** False-positive shape: `-not -path '*/*/.git/*'` skips sub-repo `.git/` contents but doesn't walk ancestors perfectly (git submodule `.git` is a file, not a dir). Current heuristic is good enough for today; submodule-aware walker deferred to Item 4.

⚙️ **Sage:** todo-update SKILL.md is 83 lines, mandatory-per-prompt — per ctx-bloat discovery, every line × prompt density. ~10 added lines is tolerable. Initially leaned toward sibling helper (orphan-scan pattern), but at N=2 consumers (todo-update + meeting) an inline `find` is cheaper than a new script + allowlist + P2 symlink + Makefile entry. Conceded on Archie's argument.

### Item 3 — /meeting symmetric warning

🏗️ **Archie:** Two interpretations: (i) classifier reads union of all TODO.md files; (ii) orphan-scan verifies against union. Petra's N=2 argument applies — speculative without Item 4 settled. Scope to warn-only, symmetric to /todo-update.

😈 **Riku:** Without symmetric warning, /meeting's orphan-scan could be the place a missed TODO.md item goes invisible. Warn-only is the right minimum.

⚙️ **Sage/Archie consensus:** Inline `find` duplicated in 2 SKILL.md files. Extract to sibling script at N=3 consumers or first filter-list divergence incident. Drift risk acceptable — filter list is minimal and divergence shows up as noisy warning.

### Item 4 — Subproject topology (forward-flag)

Three cases: (A) stray (today's bug), (B) sub-repo (separate `.git/` dir), (C) git submodule (`.git` is a file). Today's `-not -path '*/*/.git/*'` heuristic catches (B) imperfectly. Correct detection needs ancestor-walking for `.git` files/dirs. This is exactly the F1–F3 forward-flag already in TODO.md ("GH-issue audit + sub-repo discovery in orphan check"). The `.git`-ancestor primitive folds into that meeting. Cross-link added to F1–F3 entry.

## Decisions

- **D1 — Merge stray file mechanically**: add `## git-diary-workflow` section to root TODO.md; `git rm git-diary-workflow/TODO.md`. Out of scope: fixing the bug, rewriting history.
- **D2 — /todo-update Step 1.5 warn-only**: inline `find` + warning between Step 1 and Step 2. Enforcement: warn only. Out of scope: submodule detection, auto-merge.
- **D3 — /meeting symmetric warning**: same `find` invocation prefixed to no-arg-mode Step 1, before classifier. Classification proceeds against root TODO.md only. Out of scope: classifying subdir items, union-scan.
- **D4 — Defer subproject topology to F1–F3**: cross-link added to existing F1–F3 TODO entry. No new entry.
- **D5 — No sibling helper script**: inline `find` duplicated in 2 files. Re-evaluate at N=3 consumers.

## Action items

- [x] **Merge stray TODO.md into root** — `## git-diary-workflow` section added to root TODO.md; `git rm git-diary-workflow/TODO.md` done. Contract met: only root TODO.md remains.
- [x] **Add Step 1.5 to todo-update/SKILL.md** — inline `find` + warning per D2 spec. Synthetic test confirmed: stray fires, root-only stays silent.
- [x] **Add subdir-warn step to meeting/SKILL.md** — identical `find` invocation in no-arg-mode Step 1 per D3 spec.
- [x] **Cross-link to F1–F3** — annotation appended to GH-issue audit TODO entry: "extend stray-TODO `find` heuristic (D2/D3) to use `.git`-ancestor walker when F1–F3 ships — same primitive."
