# Hooks

Scripts for Claude Code's event hooks. Install with `make install-hooks` from the repo root.

Registration snippets are in the `settings.json` section below. Deeper documentation lives in each script's header comments.

## Scripts

### `meeting-cost-logger.sh`

**Event:** Stop  
**Purpose:** Logs one CSV line per session to `~/.claude/logs/meeting-cost.log` — session ID, project dir, turn count, transcript size (KB), and whether a meeting note was written. Used to calibrate the effort-estimate table in `meeting/format.md`.  
**Prerequisites:** `jq`, `bash`

### `parallel-edit-detector.py`

**Event:** Stop  
**Purpose:** Reads the session transcript, extracts `Edit`/`Write` tool calls, and checks whether any committed files contain changes not explained by those calls. Appends suspects to `~/.claude/logs/parallel-edit-suspects.log`; writes a `review-due.flag` at 50 entries.  
**Prerequisites:** Python 3, `git`, `~/.claude/` must be a git repo

### `pathspec-drop-guard.py`

**Event:** PreToolUse (Bash)  
**Purpose:** Blocks a `git commit` call when the command includes explicit file-path arguments and at least one of those arguments does NOT match any currently staged file. Catches pathspec typos (e.g. `git commit foo.p` instead of `git commit foo.py`) and forgotten `git add` cases. Silent on ordinary partial-staging / diary-style commits — a commit that names only staged files is never blocked. Tracks TODO id:b67e.  
**Prerequisites:** Python 3, `git`

### `memory-index-sync.py`

**Event:** PostToolUse (Write, Edit, NotebookEdit)  
**Purpose:** Regenerates a project's `MEMORY.md` / `MEMORY.archive.md` index (via `tools/memory-index.py --dir <dir> --write`) every time a per-memory `*.md` file is written or edited, so a newly written memory can never end up without an index pointer. That gap is the exact bug that once left three memories invisible to recall (TODO id:2e6d): `tools/memory-index.py` made a dropped pointer unrepresentable, but nothing ran it. This hook wires it in. It fires **only** when the edited file's parent directory is named `memory` AND contains a `MEMORY.md`, and the file is a `*.md` other than `MEMORY.md` / `MEMORY.archive.md` — a strict no-op for every other file in every other project (that last exclusion also prevents recursion: the generator only writes the two index files, which the hook ignores). PostToolUse cannot block (the write already landed), so every loud path is "stderr + exit 2", which Claude sees. The fail-open/fail-loud split follows one rule — **once the edited file is known to be a memory file, the index is stale by construction, so silence is never an option** (id:4347, no silent swallow): *fail-open (exit 0)* for anything that means "not our file" — unparseable payload, other tool, no `file_path`, non-memory dir, the index files themselves; *fail-loud (exit 2)* for a generator validation failure (`feedback-*` marked archived, newline in a hook), a **missing generator**, and an **unexpected generator crash** — each of these leaves the index stale, and the message says so.  
**Prerequisites:** Python 3 (`tools/memory-index.py` is stdlib-only)

### `meeting-question-guard.py`

**Event:** Stop  
**Purpose:** **BLOCKS** (exit 2) a `/meeting` turn that ended on bare transcript prose without a same-turn `AskUserQuestion` call — the mechanical enforcement of the rule stated three times in prose (`meeting/SKILL.md` step 5, the `--fabled` step 0f.5, `meeting/format.md` §Interactive mode) and violated anyway across multiple sessions and models (`routed:29bc` / TODO `id:2419`, plus two more regressions in the 2026-08-13 `id:55f6` session). Warn-only was rejected: `id:4347` bans the detector whose resolution silently no-ops, and the observation window is already closed by three logged recurrences.
**Trigger (narrow by construction):** a `/meeting` window is open in the transcript (a `/meeting` slash command or `Skill(skill="meeting")` occurred and no `Write` to `docs/meeting-notes/*.md` has happened since) **and** the harness class is not Fable **and** the turn's trailing assistant segment has no `AskUserQuestion` `tool_use` block **and** that segment carries ≥ `MEETING_STOP_GUARD_MIN_CHARS` (default 800) characters of visible text. A *compliant* decision point never fires this hook at all: `AskUserQuestion` returns its answer as a `tool_result`, so the turn does not end there. Empirically, replaying the hook over every yield point of the real `id:55f6` session gives 12 yields → 2 blocks, both of them the reported regressions (11176 and 5617 chars of prose), 0 false positives.
**Fable exemption:** `format.md` §Interactive mode *requires* Fable-class runs to end on prose with inline numbered options and to NOT call `AskUserQuestion`; firing there would enforce a spec violation. Class comes from the marker file if pinned, else from the last assistant entry's `message.model`.
**Fails OPEN, loudly:** an unreadable transcript, a malformed payload, or a missing `transcript_path` exits **1** — the turn is allowed to end, stderr is shown to the user, and the reason is appended to `~/.claude/logs/meeting-question-guard.log`. It never blocks a session because it could not read its own input.
**Escape hatch:** `MEETING_STOP_GUARD=0` in the environment, or `bash ~/.claude/hooks/meeting-guard-marker.sh disable` for one session.
**Prerequisites:** Python 3 (stdlib only)

### `meeting-guard-marker.sh`

**Event:** none — a helper invoked by hand or by the `meeting` skill, read by `meeting-question-guard.py`.  
**Purpose:** Writes/reads the session-scoped marker at `${CLAUDE_MEETING_GUARD_DIR:-${TMPDIR:-/tmp}}/claude-meeting-guard-<session_id>.json` (outside every repo tree, so it can never be committed). `start [--class fable|default]` pins the harness class, `end` marks the meeting closed early, `disable` is the per-session escape hatch, `status`/`path` inspect it. **The marker can only ever reduce firing — it never arms the guard.** That asymmetry is deliberate: the guard's arming condition is derived from the transcript, so a forgotten `start` cannot silently disarm it (the `id:4347` anti-pattern one level up) and a forgotten `end` cannot block the rest of the session.  
**Prerequisites:** `bash`

### `notify-hook.linux-x11.sh`

**Event:** Notification  
**Platform:** XFCE / X11 (uses `notify-send`, `gdbus`, `wmctrl`, `xdotool`, `$DISPLAY`)  
**Purpose:** Desktop notification when Claude needs input or a permission decision. Auto-dismisses when Claude resumes. Shows project name + short session ID; clicking "Focus Terminal" raises the window.  
**Prerequisites:** `notify-send` (libnotify), `gdbus`, `wmctrl`, `xdotool`, a Claude icon at `~/.local/share/icons/claude.png`

## settings.json registration

Add to `~/.claude/settings.json` (or merge into the existing `hooks` object):

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {"type": "command", "command": "bash ~/.claude/hooks/meeting-cost-logger.sh"},
          {"type": "command", "command": "python3 ~/.claude/hooks/parallel-edit-detector.py"},
          {"type": "command", "command": "python3 ~/.claude/hooks/meeting-question-guard.py"}
        ]
      }
    ],
    "Notification": [
      {
        "hooks": [
          {"type": "command", "command": "~/.claude/notify-hook.sh"}
        ]
      }
    ],
    "SessionStart": [
      {
        "hooks": [
          {"type": "command", "command": "jq -r '\"export CLAUDE_SESSION_ID=\" + .session_id' >> \"$CLAUDE_ENV_FILE\""},
          {"type": "command", "command": "jq -r '.session_id' | xargs -I{} sh -c 'echo \"${WINDOWID:-$(xdotool getactivewindow 2>/dev/null)}\" > /tmp/claude-wid-{}'"}
        ]
      }
    ],
    "PostToolUse": [
      {
        "hooks": [
          {"type": "command", "command": "jq -r '.session_id' | xargs -I{} touch /tmp/claude-resume-{}"}
        ]
      },
      {
        "matcher": "Write|Edit|NotebookEdit",
        "hooks": [
          {"type": "command", "command": "python3 ~/.claude/hooks/memory-index-sync.py"}
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {"type": "command", "command": "python3 ~/.claude/hooks/pathspec-drop-guard.py"}
        ]
      }
    ]
  }
}
```

`meeting-question-guard.py` is the only hook here that can BLOCK a turn (`Stop`, exit 2). It is a strict no-op outside an open `/meeting` window, and fails open (exit 1, loud) on any internal error — see its entry above for the exact trigger and the escape hatch.

`SessionStart` and the first `PostToolUse` entry are inline commands (no script files in this repo); the second `PostToolUse` entry (matcher `Write|Edit|NotebookEdit`) references `memory-index-sync.py`, which is a strict no-op for every non-memory file. `Stop` and `Notification` reference the installed scripts. `PreToolUse` references `pathspec-drop-guard.py` which only blocks on a confirmed pathspec drop; all other Bash calls pass through silently.
