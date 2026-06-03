# 2026-06-03 — Reverse-orphan scan

**Started:** 2026-06-03 09:52
**Session:** de86b34e-b24b-4e4f-9f6a-45ff06c898f7
**Mode:** Class 2 planning record (no meeting was held — plan-mode output)
**Topic:** Add `--reverse` mode to `orphan-scan.sh` to surface ID-bearing checked/inline lines absent from the TODO union.

## Context

The forward orphan-scan (`orphan-scan.sh`) finds unchecked (`^- [ ] `) action items in meeting notes whose `<!-- id:XXXX -->` token is absent from `TODO.md + TODO.archive.md`. Its blind spot: `- [x]` checked and inline ID-bearing lines. When Step 5b (mirror action items to TODO) is skipped, all action items stay as `- [x]` in the meeting note only — invisible to the forward scan and to `todo-update`. This caused a real failure: in the 2026-05-29 zkm synthetic-corpus meeting, Step 5b was skipped; the next `/meeting` session then mis-classified the already-done work as Class 1 (impl-ready). Confirmed: `id:9e0e`, `fc87`, `ba5e`, `590b`, `0af9`, `f918`, `c582`, `aa77` were all on `- [x]` lines in that note (though they had since been archived in TODO, which is why they didn't reproduce today).

## Plan

- **Packaging:** `--reverse` flag on existing `orphan-scan.sh` (zero new symlink/allowlist/Makefile cost).
- **Output scope:** only the blind spot — `[x]` checked and inline lines, non-overlapping with forward scan.
- **Cadence:** auto-invoked at meeting start alongside the forward scan, in both SKILL.md paths.
- Design ratified via AskUserQuestion; all three choices matched recommendations.

## Implementation findings

Changes landed in two files (canonical paths in `~/src/dotclaude-skills/`):

**`meeting/orphan-scan.sh`**: Added `--reverse`/`-r` arg parsing (shift before ROOT); branched the per-note loop — forward mode unchanged (`grep -n '^- \[ \] '`); reverse mode uses `grep -n '<!-- id:[0-9a-f]\{4\} -->'`, skips `^- [ ] ` lines via `"${text:0:6}"` prefix check, classifies remaining lines as `[x]` or `inline`, and emits `basename:lineno  [state] text`. Log `printf` gained a `mode=%s` field. No Makefile/allowlist/symlink changes needed (existing 8-form allowlist for `orphan-scan.sh` already covers `--reverse` as "with args").

**`meeting/SKILL.md`**: Added `--reverse` call (and ADVISORY label) after the existing forward-scan call in both the "With a subject" step 2 and the "With no subject" step 1.

**Verification results:**
- `orphan-scan.sh --reverse ~/src/zkm` → 2 genuine reverse-orphans found (`32a0`, `0604` — `[x]` items never mirrored); trigger-incident IDs (`9e0e`, …) absent (they were archived correctly).
- `orphan-scan.sh ~/src/zkm` (forward, no flag) → 0 candidates (unchanged).
- `orphan-scan.sh --reverse` (dotclaude-skills self) → 0 candidates (clean).
- `ORPHAN_SCAN_LIMIT=1 orphan-scan.sh --reverse ~/src/zkm` → cap + suppression notice.
- Log: `mode=forward` and `mode=reverse` rows are distinct.

## Decisions

- `--reverse` flag on existing script (not a new sibling) — zero packaging overhead; cheaply-extensible case (D5).
- Reverse scope = only the complement of the forward scan (`[x]` + inline), non-overlapping by construction.
- Auto-invoked at meeting start (both SKILL.md paths), under the same ADVISORY caveat as the forward scan.
- No auto-fix / write-back — report-only, mirrors forward-scan philosophy.

## Action items

(All resolved in-session — no items to mirror to TODO.)
