#!/usr/bin/env python3
"""
Generate and (optionally) merge Claude Code Bash allowlist entries for skill scripts.

Usage:
    allowlist.py --mode print  --home HOME --src-dir SRC --dest-dir DEST --settings SETTINGS skill/script.sh ...
    allowlist.py --mode merge  --home HOME --src-dir SRC --dest-dir DEST --settings SETTINGS skill/script.sh ...

For each <skill>/<script> it generates 8 Bash allowlist entries:
    4 path forms × 2 arg shapes (bare + with trailing *)

Path forms (all derived from --home / --src-dir / --dest-dir; no hardcoded paths):
    1. tilde-dest:   ~/.claude/skills/<skill>/<script>        (symlink via tilde)
    2. abs-dest:     <DEST_DIR>/<skill>/<script>              (symlink absolute)
    3. tilde-src:    ~/<rel-from-home-to-src>/<skill>/<script> (source via tilde)
    4. abs-src:      <SRC_DIR>/<skill>/<script>               (source absolute)

--mode print:
    Emit all would-be entries to stdout, prefixed with + (new) or = (already present).
    Does not modify settings.json.

--mode merge:
    Add missing entries to settings.json under permissions.allow (idempotent set-union).
    Existing entries are never removed.
    Creates a .bak backup before writing.
    Writes atomically (temp file + os.replace).
"""

import argparse
import json
import os
import tempfile
from pathlib import Path


def entries_for(script_rel: str, home: Path, src_dir: Path, dest_dir: Path) -> list[str]:
    """Return the 8 expected allowlist entry strings for a skill/script.sh path."""
    home_str = str(home)
    src_str = str(src_dir)
    dest_str = str(dest_dir)

    # Tilde forms: replace home prefix with ~
    def to_tilde(abs_path: str) -> str:
        if abs_path.startswith(home_str + "/"):
            return "~/" + abs_path[len(home_str) + 1:]
        return abs_path

    tilde_dest = to_tilde(f"{dest_str}/{script_rel}")
    abs_dest   = f"{dest_str}/{script_rel}"
    tilde_src  = to_tilde(f"{src_str}/{script_rel}")
    abs_src    = f"{src_str}/{script_rel}"

    result = []
    for path in [tilde_dest, abs_dest, tilde_src, abs_src]:
        result.append(f"Bash({path})")
        result.append(f"Bash({path} *)")
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--mode", choices=["print", "merge"], required=True)
    parser.add_argument("--home",     required=True, help="HOME directory (absolute)")
    parser.add_argument("--src-dir",  required=True, help="dotclaude-skills source root (absolute)")
    parser.add_argument("--dest-dir", required=True, help="~/.claude/skills install root (absolute)")
    parser.add_argument("--settings", required=True, help="~/.claude/settings.json path")
    parser.add_argument("scripts", nargs="+", metavar="skill/script.sh",
                        help="Relative paths like meeting/append.sh")
    args = parser.parse_args()

    home     = Path(args.home).resolve()
    src_dir  = Path(args.src_dir).resolve()
    dest_dir = Path(args.dest_dir).resolve()
    settings = Path(args.settings)

    # Collect all expected entries, preserving generation order
    expected: list[str] = []
    seen: set[str] = set()
    for script_rel in args.scripts:
        for entry in entries_for(script_rel, home, src_dir, dest_dir):
            if entry not in seen:
                expected.append(entry)
                seen.add(entry)

    # Load current allowlist
    with open(settings) as f:
        data = json.load(f)
    current: list[str] = data.setdefault("permissions", {}).setdefault("allow", [])
    current_set: set[str] = set(current)

    new_entries = [e for e in expected if e not in current_set]

    if args.mode == "print":
        print(f"Entries for {len(args.scripts)} script(s) — "
              f"{len(expected)} total, {len(new_entries)} new, "
              f"{len(expected) - len(new_entries)} already present:\n")
        for e in expected:
            mark = "+" if e not in current_set else "="
            print(f"  {mark} {e}")
        if not new_entries:
            print("\n(nothing to add)")
        return

    # mode == merge
    if not new_entries:
        print("install-allowlist: nothing to add (all entries already present)")
        return

    # Backup
    backup = settings.with_suffix(".json.bak")
    import shutil
    shutil.copy2(settings, backup)

    # Add new entries and write atomically
    current.extend(new_entries)
    tmp_fd, tmp_path = tempfile.mkstemp(dir=settings.parent, prefix=".settings-", suffix=".json")
    try:
        with os.fdopen(tmp_fd, "w") as f:
            json.dump(data, f, indent=4)
            f.write("\n")
        os.replace(tmp_path, settings)
    except Exception:
        os.unlink(tmp_path)
        raise

    print(f"install-allowlist: added {len(new_entries)} entries (backup: {backup.name})")
    for e in new_entries:
        print(f"  + {e}")


if __name__ == "__main__":
    main()
