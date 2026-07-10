#!/usr/bin/env python3
"""
PostToolUse hook: keep a project's MEMORY.md index in sync with its memory files.

Problem (TODO id:2e6d)
----------------------
`tools/memory-index.py` regenerates a project's MEMORY.md / MEMORY.archive.md
index from the per-memory `*.md` files, so a dropped index pointer cannot survive
a regeneration. But nothing *ran* the generator: a newly written memory file could
still end up with no MEMORY.md pointer and be invisible to recall — the exact bug
that left three memories unreachable. This hook closes that loop: every time a
memory file is written or edited, it regenerates the index.

When it fires
-------------
Only when ALL of these hold (a strict no-op for every other file in every other
project):
  * tool_name is Write / Edit / NotebookEdit,
  * tool_input.file_path is present,
  * the file's parent directory is named `memory` AND contains a `MEMORY.md`,
  * the edited file is a `*.md` that is NOT `MEMORY.md` / `MEMORY.archive.md`.
The final exclusion also breaks recursion: the generator only writes the two index
files, which this hook ignores, so a regeneration can never re-trigger the hook.

Output contract (PostToolUse)
-----------------------------
PostToolUse cannot block — the tool already ran (see hooks/README.md and the
Claude Code hooks docs: exit code 2 "shows stderr to Claude; the tool already
ran"). So there is nothing to `{"decision": "block"}` after the fact. This hook
therefore:
  * on a clean regeneration → exits 0, prints nothing (quiet success; this runs on
    every memory write),
  * on a LOUD generator validation failure (generator exit 2 — e.g. a `feedback-*`
    memory marked archived, or a hook value containing a newline) → prints the
    generator's stderr plus a diagnostic to OUR stderr and exits 2, so Claude sees
    the failure and can fix the offending memory file.

Fail-open / fail-loud asymmetry
-------------------------------
Every plumbing failure (unparseable payload, missing memory dir, generator not
found, generator crash) is fail-OPEN: exit 0, never break the user's edit. The
ONLY loud, non-zero exit is a real validation failure the generator flagged with
exit code 2 — a memory file that is genuinely malformed and would corrupt recall.

Tracks TODO id:2e6d.
"""
import json
import subprocess
import sys
from pathlib import Path

_MEMORY_DIRNAME = "memory"
_INDEX_FILES = ("MEMORY.md", "MEMORY.archive.md")
_EDIT_TOOLS = ("Write", "Edit", "NotebookEdit")

# Generator lives at <repo>/tools/memory-index.py. This hook is installed as a
# symlink into ~/.claude/hooks, so resolve() first to follow the symlink back to
# the repo checkout, then walk up to the repo root.
GENERATOR = Path(__file__).resolve().parent.parent / "tools" / "memory-index.py"


def is_memory_file(file_path: str) -> bool:
    """True iff file_path is a per-memory `*.md` file whose index we should sync.

    Requires: parent dir named `memory` AND containing a MEMORY.md; the file is a
    `*.md` other than MEMORY.md / MEMORY.archive.md. Anything else → False (no-op).
    """
    p = Path(file_path)
    if p.name in _INDEX_FILES:
        return False
    if p.suffix != ".md":
        return False
    parent = p.parent
    if parent.name != _MEMORY_DIRNAME:
        return False
    # The MEMORY.md presence check is the discriminator that keeps this hook from
    # firing on arbitrary directories that merely happen to be named "memory".
    if not (parent / "MEMORY.md").is_file():
        return False
    return True


def main() -> int:
    try:
        payload = json.loads(sys.stdin.read())
    except Exception:
        return 0  # unparseable payload — fail-open, never break the edit

    if payload.get("tool_name") not in _EDIT_TOOLS:
        return 0

    file_path = (payload.get("tool_input") or {}).get("file_path")
    if not file_path:
        return 0

    if not is_memory_file(file_path):
        return 0

    memory_dir = str(Path(file_path).parent)

    # Past this point the file IS a memory file, so the index is now stale by
    # construction.  Skipping the sync silently would re-create the very bug this
    # hook closes (a memory with no pointer, invisible to recall — id:4347
    # no-silent-swallow).  So these are LOUD, unlike the earlier "not our file"
    # exits.  PostToolUse cannot undo the edit; exit 2 only surfaces stderr.
    if not GENERATOR.is_file():
        sys.stderr.write(
            f"memory-index-sync: generator missing at {GENERATOR} — {file_path} was "
            f"written but its MEMORY.md pointer was NOT generated. The index is now "
            f"stale; run memory-index.py --write by hand.\n")
        return 2

    try:
        result = subprocess.run(
            [sys.executable, str(GENERATOR), "--dir", memory_dir, "--write"],
            capture_output=True,
            text=True,
            timeout=30,
        )
    except Exception as exc:  # noqa: BLE001 — any launch failure leaves a stale index
        sys.stderr.write(
            f"memory-index-sync: could not run {GENERATOR} ({exc!r}) — {file_path} was "
            f"written but its MEMORY.md pointer was NOT generated. The index is now stale.\n")
        return 2

    if result.returncode == 0:
        return 0  # quiet success

    if result.returncode == 2:
        # LOUD: a genuine validation failure in a memory file. Surface it to Claude
        # via stderr + a non-zero exit (PostToolUse cannot block; the write already
        # landed, but Claude sees stderr and can repair the offending file).
        if result.stderr:
            sys.stderr.write(result.stderr)
        sys.stderr.write(
            "memory-index-sync (id:2e6d): MEMORY.md index NOT regenerated for %s — "
            "the memory file above is malformed. Fix it, then re-run "
            "`tools/memory-index.py --dir %s --write`.\n" % (memory_dir, memory_dir)
        )
        return 2

    # Any other non-zero exit is an unexpected generator crash.  It still leaves the
    # index stale for a file we know is a memory, so it is LOUD too — a silent
    # no-op here would be indistinguishable from success while recall quietly rots.
    if result.stderr:
        sys.stderr.write(result.stderr)
    sys.stderr.write(
        "memory-index-sync (id:2e6d): generator exited %d for %s — MEMORY.md index NOT "
        "regenerated and is now STALE. Run `tools/memory-index.py --dir %s --check` to "
        "see the drift.\n" % (result.returncode, file_path, memory_dir)
    )
    return 2


if __name__ == "__main__":
    sys.exit(main())
