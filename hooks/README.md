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
          {"type": "command", "command": "python3 ~/.claude/hooks/parallel-edit-detector.py"}
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

`SessionStart` and `PostToolUse` are inline commands (no script files in this repo). `Stop` and `Notification` reference the installed scripts. `PreToolUse` references `pathspec-drop-guard.py` which only blocks on a confirmed pathspec drop; all other Bash calls pass through silently.
