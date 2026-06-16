#!/usr/bin/env python3
"""settings-env.py — idempotently merge KEY=VALUE env entries into ~/.claude/settings.json.

The companion of tools/allowlist.py: where that merges Bash-allowlist entries into
`permissions.allow`, this merges fleet env policy into the `env` block. Used by the
Makefile `install-relay-env` target so `make install` applies shared relay policy
(e.g. RELAY_QUOTA_DECAY_7D) to EACH machine's settings.json — settings.json is
per-machine (not synced), so the SHARED source of truth is here in dotclaude-skills
and `make install` is the per-machine apply step.

Idempotent: only rewrites settings.json when a value is missing or differs. Preserves
all other keys/structure; matches allowlist.py's write style (indent=4 + trailing
newline, backup to settings.json.bak, atomic replace).

Usage:
  settings-env.py --settings ~/.claude/settings.json KEY=VALUE [KEY=VALUE ...]
  settings-env.py --mode print --settings ~/.claude/settings.json KEY=VALUE ...
"""
import argparse
import json
import os
import shutil
import sys
import tempfile
from pathlib import Path


def parse_assignments(items):
    out = {}
    for it in items:
        if "=" not in it:
            sys.exit(f"settings-env: bad KEY=VALUE pair: {it!r}")
        k, v = it.split("=", 1)
        k = k.strip()
        if not k:
            sys.exit(f"settings-env: empty key in {it!r}")
        out[k] = v
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--settings", required=True, type=Path)
    ap.add_argument("--mode", choices=["merge", "print"], default="merge")
    ap.add_argument("assignments", nargs="+", help="KEY=VALUE env entries")
    args = ap.parse_args()

    want = parse_assignments(args.assignments)

    if args.settings.exists():
        with open(args.settings) as f:
            data = json.load(f)
    else:
        data = {}

    env = data.setdefault("env", {})
    changes = {k: v for k, v in want.items() if env.get(k) != v}

    if args.mode == "print":
        print(f"settings-env: {len(want)} entr(ies) — {len(changes)} to set, "
              f"{len(want) - len(changes)} already current:")
        for k, v in want.items():
            mark = "+" if k in changes else "="
            print(f"  {mark} {k}={v}" + ("" if k in changes else f"  (have {env.get(k)!r})"))
        return

    # mode == merge
    if not changes:
        print("install-relay-env: nothing to set (all env entries already current)")
        return

    if args.settings.exists():
        shutil.copy2(args.settings, args.settings.with_suffix(".json.bak"))

    env.update(changes)
    args.settings.parent.mkdir(parents=True, exist_ok=True)
    tmp_fd, tmp_path = tempfile.mkstemp(dir=args.settings.parent, prefix=".settings-", suffix=".json")
    try:
        with os.fdopen(tmp_fd, "w") as f:
            json.dump(data, f, indent=4)
            f.write("\n")
        os.replace(tmp_path, args.settings)
    except Exception:
        os.unlink(tmp_path)
        raise
    print("install-relay-env: set " + ", ".join(f"{k}={v}" for k, v in changes.items()))


if __name__ == "__main__":
    main()
