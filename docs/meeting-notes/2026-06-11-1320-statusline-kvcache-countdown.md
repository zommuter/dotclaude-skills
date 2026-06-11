# 2026-06-11 — Statusbar: KV-cache TTL countdown + repo move

**Started:** 2026-06-11 13:20
**Session:** 8d2c1118-cda2-4a81-a62b-7732a17c50cb
**Mode:** Class 2 planning record (no meeting was held — plan-mode output)
**Topic:** Add prompt-cache TTL countdown to the Caude statusbar and bring the script into dotclaude-skills.

## Context

Anthropic's prompt cache has a 5-minute TTL; once it lapses the next turn pays full uncached input-token cost. The statusbar had no indicator for this. Separately, `statusline-command.sh` was living only in `~/.claude/` — unversioned and untracked — while a TODO item asked to bring it into the repo.

This session bundled both: move script into the repo under the P2 symlink pattern, then add the KV-cache countdown.

## Plan

1. **Explore:** confirmed `transcript_path` is present in the live statusLine stdin JSON (other keys: `session_id`, `rate_limits`, `effort`, `thinking`, `fast_mode`, `output_style`, `version` — wider than previously documented).
2. **Activity signal:** transcript file mtime — cheap single `stat -c %Y`, no parsing needed; updates on every assistant turn.
3. **Color:** reuse existing `percent_to_gradient()` keyed on `(300 - KV_REMAIN)*100/300` (0% = fresh/green → 100% = expired/red).
4. **Display:** `KV:Mm SSs` when > 0; `KV:cold` (red) when ≤ 0; field omitted entirely when `transcript_path` absent/unreadable.
5. **Repo move (P2):** `statusline/statusline-command.sh` is the real file; `~/.claude/statusline-command.sh` is a symlink; Makefile `install-hooks` extended.

## Implementation findings

- Debug dump (`echo "$input" > /tmp/sl-stdin.json`) confirmed `transcript_path` in live statusLine stdin before shipping.
- Test with `touch -d '-6 minutes' <tmpfile>` → `KV:cold` renders correctly.
- Test with live transcript mtime → `KV:4mXXs` (green-to-orange) renders correctly.
- Existing "cache age" field (`AGE_DISPLAY`) measures `/tmp/claude-usage-cache.json` freshness — unrelated to prompt KV-cache; field names are now clearly distinct.
- Known caveat: statusline re-renders on turn completion, not on a 1 s idle tick — value is a snapshot, not a live counter during quiet periods. Ship-and-observe per "observe before preventing" heuristic.

## Decisions

- `transcript_path` from statusLine stdin is the activity source (confirmed present in live harness).
- `percent_to_gradient(expired_pct)` reused for KV color — no new color function needed.
- KV field gracefully absent when transcript unreadable — no fallback `find` needed.
- Script lives in `dotclaude-skills/statusline/statusline-command.sh`; symlink pattern matches `notify-hook.sh`.
- `settings.json` `statusLine.command` unchanged.

## Action items

- [x] Move `statusline-command.sh` to repo + symlink + Makefile entry <!-- id:aff6 -->
- [x] Add KV-cache TTL countdown field (this session)
- [ ] Close "Statusbar: verify it lives in dotclaude-skills" TODO (done here)
