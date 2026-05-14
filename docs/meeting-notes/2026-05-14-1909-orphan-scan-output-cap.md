# 2026-05-14 — orphan-scan output cap + recency sort

**Started:** 2026-05-14 19:09
**Session:** e947792b-d718-48f9-8ca5-5b20c80f416c
**Mode:** Class 2 planning record (no meeting was held — plan-mode output)
**Topic:** Cap orphan-scan.sh stdout to prevent context-window flooding.

## Context

`orphan-scan.sh` returned ~39 candidates in the 2026-05-14-1909 meeting no-arg
audit, filling a significant slice of an already-loaded context window. Second
complaint about this (prior: `2026-05-14-1803-orphan-scan-accumulation.md`).

Root cause: the script appended every unmatched candidate to `output_lines[]`
with no sort or cap; 20 meeting notes × multiple `[ ]` items each = 39 lines.
All notes span only 6 days (2026-05-08 → 2026-05-14), so a date-prefix
recency filter would not have helped here.

**Also identified during audit:** `orphan-scan.sh should not require bash prefix`
TODO was stale — shebang + executable bit were already correct. Closed in TODO.md.
Also surfaced hooks orphans AI-1/4/5 (dotclaude-skills/hooks/ never set up) and
added them to `## hooks` in TODO.md.

## Plan

Three changes to `meeting/orphan-scan.sh`:
1. Iterate via `ls -r1` (reverse lex = newest-first by YYYY-MM-DD-HHMM prefix).
2. Hard output cap, default 10, overridable via `ORPHAN_SCAN_LIMIT` env var
   (0 = unlimited escape hatch).
3. When cap clips output, append one summary line:
   `# orphan-scan: N more candidates suppressed (cap=M); set ORPHAN_SCAN_LIMIT=0 for full output`.

Log line unchanged; `cand4`/`cand5` counters count full corpus (unaffected by cap).

## Implementation findings

- Script was already `chmod +x` with correct shebang — prefix TODO closed.
- Default run (cap=10): 10 candidates + summary "29 more suppressed" — 11 lines total.
- `ORPHAN_SCAN_LIMIT=3`: 3 candidates + "36 more suppressed".
- `ORPHAN_SCAN_LIMIT=0`: 39 lines (full, unchanged).
- Log line: `cand4=39` reflects full corpus as intended.
- Candidates sorted newest-first confirmed (2026-05-14-1739, 2026-05-14-1713, ...).
- Runtime: 489 ms — within ≥1s gate for caching discussion; no action needed yet.

## Decisions

- Output cap defaults to 10; `ORPHAN_SCAN_LIMIT` env var overrides.
- Zero = unlimited; no other special values.
- Log line stats are never capped — re-eval gate remains intact.
- Recency filter (date-prefix cutoff) explicitly deferred — all notes today are recent;
  would not have helped; add only if noise floor grows past cap even after it.

## Action items

- [x] Edit `meeting/orphan-scan.sh`: recency sort + output cap + suppression line.
- [x] Close stale `orphan-scan.sh should not require bash prefix` in TODO.md.
- [x] Add hooks orphans AI-1/4/5 to `## hooks` in TODO.md.
