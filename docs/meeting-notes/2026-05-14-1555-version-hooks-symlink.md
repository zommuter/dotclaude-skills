# 2026-05-14 — Version ~/.claude/hooks in dotclaude-skills + symlink

**Started:** 2026-05-14 15:55
**Session:** 30586b2c-4654-4a99-8315-43885bab4cc5
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime / harness)
**Topic:** Should `~/.claude/hooks/*` scripts be versioned in `dotclaude-skills/hooks/` and P2-symlinked into `~/.claude/hooks/`, mirroring the skills pattern?

## Agenda
1. Scope: script files only, or also settings.json hook registrations?
2. Portability triage: which scripts are publishable as-is?
3. Layout: flat `hooks/` directory vs. per-hook subdirs?
4. Install/onboarding: Makefile entry + README integration?

## Discussion

### Agenda 1 — Scope

🏗️ **Archie:** Mirror the existing skills topology — `dotclaude-skills/<skill>/` holds scripts; `settings.json` stays machine-local. Hooks have the same shape: registration (which event fires which command) is intrinsically machine-local (references `$HOME`, `xdotool`, etc.). Script files themselves can be portable.

⚙️ **Sage:** Harness mechanics: allowlist entries like `Bash(~/.claude/hooks/meeting-cost-logger.sh)` match on the **typed path**, not the resolved symlink target — swapping the file for a symlink changes neither allowlist matching nor settings.json registration. Zero migration cost on the harness side.

😈 **Riku** (pre-empt, drift-aversion): leaving `meeting-cost-logger.sh` un-versioned in `~/.claude/hooks/` while its fix history lives in dotclaude-skills meeting notes *is* a drift source — exact pattern resolved by the gist→repo migration.

😈 **Riku** (pre-empt, migration-provenance): first commit in `dotclaude-skills/hooks/` must be verbatim copies of the live files; rename/edits happen in commit 2.

✂️ **Petra:** Out of scope: settings.json hook-registration versioning. Different sync target; bundle with scripts doubles complexity without doubling value.

**Tobias (D1):** Scripts + settings.json snippet. Document the registration block in `hooks/README.md` so a fresh machine can wire the hooks up without spelunking — onboarding clarity earns the small drift risk. (Not generating or syncing settings.json itself.)

### Agenda 2 — Portability triage

Hook landscape observed:
- `~/.claude/hooks/meeting-cost-logger.sh` — bash, CLAUDE_SESSION_ID + `~/.claude/logs/`, portable
- `~/.claude/hooks/parallel-edit-detector.py` — Python, reads harness-provided `transcript_path`, needs sanity read
- `~/.claude/notify-hook.sh` — XFCE/X11/gdbus/xdotool/wmctrl/notify-send + hard-coded icon path, DE-coupled
- settings.json inline hooks (SessionStart, PostToolUse) — no script files; documented in README

🏗️ **Archie:** All three scripts in scope; `notify-hook.sh` can ship with a DE-tag in the filename to signal the coupling.

✂️ **Petra:** N=2 for versioning `notify-hook.sh` is not met today (only zomni is XFCE/X11). But naming it `notify-hook.linux-x11.sh` is the single-concrete-file call — no abstraction.

😈 **Riku:** Privacy check: `meeting-cost-logger.sh` is clean. `parallel-edit-detector.py` needs a verify pass. Per [low-paranoia-infra-disclosure] profile entry, `$HOME` and `~/.claude/` references don't need scrubbing.

**Tobias (D2):** Version all three; `notify-hook.sh` ships as `notify-hook.linux-x11.sh`. Concrete symlink map:
- `~/.claude/hooks/meeting-cost-logger.sh` → `dotclaude-skills/hooks/meeting-cost-logger.sh`
- `~/.claude/hooks/parallel-edit-detector.py` → `dotclaude-skills/hooks/parallel-edit-detector.py`
- `~/.claude/notify-hook.sh` → `dotclaude-skills/hooks/notify-hook.linux-x11.sh` (current location preserved → no settings.json edit)

### Agenda 3 — Layout

🏗️ **Archie + ✂️ Petra:** Skills earned per-skill subdirs because they have multiple files. Hooks are one-script units. Flat `dotclaude-skills/hooks/` + one README.

⚙️ **Sage:** settings.json `command` paths stay verbatim. No allowlist churn.

😈 **Riku:** README should NOT duplicate script header comments. Thin index only: name, one-line purpose, prerequisites, settings.json snippet. Deeper docs belong in the script header.

**Tobias (D3):** Flat dir + one README.

### Agenda 4 — Install/onboarding

🏗️ **Archie:** Add `install-hooks` Makefile target: `mkdir -p ~/.claude/hooks/` + 3 explicit `ln -sf` lines. Include in default `install`.

⚙️ **Sage:** `install-hooks` differs from `install-meeting`: targets *files* not a directory, one outlier path (`notify-hook.sh → ~/.claude/` not `~/.claude/hooks/`). Three explicit lines, no generic pattern.

✂️ **Petra:** Inline three lines is correct at N=3 with one outlier. Abstraction cost > duplication cost.

😈 **Riku:** Settings.json snippet in README: registration block only (event → command line), not surrounding scaffolding. Include both script-based (Stop, Notification) AND inline snippets (SessionStart, PostToolUse) — completes the agenda-1 answer without adding new script files to the repo.

**Tobias (D4):** Full integration: Makefile install-hooks + default install, top-level README Hooks section, hooks/README.md with snippet.

## Decisions

- **D1 — Scope:** Version portable hook scripts in `dotclaude-skills/hooks/`. Ship settings.json registration snippet in `hooks/README.md` (event → command lines only). Live `~/.claude/settings.json` stays machine-local. *Out of scope:* generating/syncing settings.json.
- **D2 — Triage:** Three scripts in scope: `meeting-cost-logger.sh`, `parallel-edit-detector.py`, `notify-hook.linux-x11.sh`. *Out of scope:* DE abstraction layer; Wayland/macOS variants until a second DE machine exists.
- **D3 — Layout:** Flat `dotclaude-skills/hooks/` directory with three scripts + one README. *Out of scope:* per-hook subdirs.
- **D4 — Install:** `install-hooks` Makefile target (3 `ln -sf` lines + `mkdir -p`), in default `install`. Hooks section in top-level README. hooks/README.md covers per-hook purpose + full settings.json snippet. *Out of scope:* per-script sub-targets; generic symlink patterns.

**Migration shape:** Commit 1 = verbatim copies. Commit 2 = rename `notify-hook.sh → notify-hook.linux-x11.sh` + README + Makefile + top-level README. Commit 3 = replace `~/.claude/` files with symlinks.

## Action items

- [ ] **AI-1** — Verbatim first commit: copy `~/.claude/hooks/meeting-cost-logger.sh`, `~/.claude/hooks/parallel-edit-detector.py`, `~/.claude/notify-hook.sh` into `dotclaude-skills/hooks/` unchanged (preserve permissions). Contract: zero content diff vs live; `git show --stat` lists exactly 3 files.
- [ ] **AI-2** — Sanity-pass `parallel-edit-detector.py` for hard-coded paths/UUIDs before publish. Scrub if found, defer publish otherwise.
- [ ] **AI-3** — Rename `hooks/notify-hook.sh → hooks/notify-hook.linux-x11.sh` via `git mv`. Contract: `git log --follow` traces to verbatim commit.
- [ ] **AI-4** — Add `hooks/README.md`: one-paragraph per hook (name, purpose, prerequisites) + settings.json snippet covering Stop + Notification (script-based) + SessionStart + PostToolUse (inline).
- [ ] **AI-5** — Add Makefile `install-hooks` target: `mkdir -p ~/.claude/hooks/` + 3 `ln -sf` lines; add to default `install`. Contract: idempotent; `readlink` resolves to dotclaude-skills paths.
- [ ] **AI-6** — Top-level README Hooks section: row table (hook name, one-line purpose, link to hooks/README.md), after Skills section. Contract: 3 rows visible on GitHub.
- [ ] **AI-7** — Replace live files with symlinks (same session as or after AI-1..AI-6). Contract: `ls -la` shows symlinks.
- [ ] **AI-8** — Post-symlink verification: confirm `meeting-cost.log` gets a new entry after next Stop; confirm notify-send fires on next permission prompt. Contract: one new log line; one visible notification.
- [ ] **AI-9** — Discard historical orphan: `2026-05-08-meeting-skill.md:71 Save this meeting's key decisions to project auto-memory` — superseded by current memory workflow.
