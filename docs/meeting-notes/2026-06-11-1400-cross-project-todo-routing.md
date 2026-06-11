# 2026-06-11 — Cross-project TODO routing

**Started:** 2026-06-11 14:00
**Session:** 05103241-bb6a-464d-aca6-2a6b3c71f210
**Mode:** Class 2 planning record (no meeting was held — plan-mode output)
**Topic:** Implement a shared inbox so action items surfaced in repo X but belonging to repo Y are durably captured without violating the single-root write invariant.

## Context

TODO item `id:b30b` — items that surface in a project meeting but belong to a different project had no durable routing mechanism; they were moved manually at meeting-end and frequently lost.

Two hard constraints shaped the design:
1. `meeting/SKILL.md` (lines 69, 98) and `todo-update/SKILL.md` (line 14) both enforce "never write outside `<root>`".
2. `orphan-scan.sh` is strictly single-root: an `<!-- id:XXXX -->` minted in X's meeting note but absent from X's TODO becomes a permanent false-positive orphan.

User selected the **shared inbox, surface-only** approach: `~/.claude/todo-inbox.md` as an append-only cross-repo queue, with read-only surfacing in repo Y's meeting setup and in `/projects`. No auto-write into any repo's TODO; adoption is always user/skill-mediated.

## Plan

Explored: `meeting/append.sh` (new-id/new-ids, flock'd append, -t targets), `meeting/SKILL.md` (setup step 7, end-of-meeting step 2b, single-root invariant at lines 69/98), `todo-update/SKILL.md` (no session-start hook), `meeting/cross-mode.md` (project registry via `~/.config/project_manager/include.toml`), orphan-scan.sh (single-root union, id: namespace grep).

Design: `routed:` token namespace (distinct from `id:`) lives only in the inbox which no orphan-scan reads. In X's meeting note, routed items carry `<!-- routed:XXXX -->` with no `<!-- id:XXXX -->` — orphan-scan skips un-IDed lines by design. Y mints a fresh `id:` at adoption time.

## Implementation findings

1. `meeting/append.sh` — added `-t inbox` target (`~/.claude/todo-inbox.md`) and `inbox-done <token>` subcommand (python3 in-place flock'd flip `- [ ]` → `- [x]`).
2. `meeting/SKILL.md` — added setup step 7b (inbox surface: grep for unchecked `[<root-basename>]` lines, display read-only) and cross-repo routing sub-step in step 2b (judge home repo, route via append.sh -t inbox, record as `→ routed to <target-repo> inbox <!-- routed:TOKEN -->` with no id: token).
3. `projects/SKILL.md` — added step 4: grep inbox, group by `[<repo>]` tag, print `📥 Routed to you:` block.
4. `~/.claude/todo-inbox.md` — seeded with header comment.

Verification: inbox write, inbox-done flip, idempotent re-flip, adopted-item suppression from surface grep — all passed manually.

## Decisions

- **Inbox at `~/.claude/todo-inbox.md`** — shared runtime file, not under any repo git. Format: `- [ ] [<target>] <desc> (from <source>, <note-relpath>) <!-- routed:XXXX -->`.
- **`routed:` namespace** — distinct from `id:`, so orphan-scan (which greps `id:[0-9a-f]{4}`) never sees inbox tokens. Un-IDed meeting-note lines are skipped by orphan-scan by design.
- **Surface-only** at meeting setup (step 7b) and `/projects` dashboard — no auto-write into any repo's TODO.md. Adoption is always deliberate.
- **`todo-update` drain deferred** — per-prompt ctx cost concern (CLAUDE.md:98); revisit if items sit unadopted.
- Out of scope: periodic prune of `- [x]` lines, global id uniqueness, `/meeting --cross` homeless-item collection.

## Action items

- [x] `id:b30b` resolved — cross-project TODO routing implemented. <!-- id:2002 -->
