#!/usr/bin/env python3
"""
persona-state.py — update docs/meeting-notes/persona-state.yml and mirror to web/persona-state.json.

Usage:
    # Write this session's delta to persona-events/<session>.json (zero contention)
    python3 persona-state.py shard --root <ROOT> --session <SESSION_ID> --slug <SLUG>

    # Fold all shards into persona-state.yml under flock, then GC shards
    python3 persona-state.py collapse --root <ROOT>

    # Legacy single-session update (equivalent to shard+collapse in one step)
    python3 persona-state.py update --root <ROOT> --slug <SLUG>

Delta JSON on stdin (for shard/update):
{
  "personas": {
    "riku":  {"decision_id": "D2", "option": "label", "stance": "advocated", "valence": 1},
    "archie": {"decision_id": "D2", "option": "label", "stance": "opposed",   "valence": -1}
  },
  "project_stats": {"conviction": 1, "wisdom": 0, "tech_debt": 1}
}

Gate: if <root>/docs/meeting-notes/persona-state.yml does not exist, exit 0 silently.
Unknown persona keys in the delta are skipped (forward-compat).
Shard files live in <root>/persona-events/ — add that directory to the project .gitignore.
"""
import argparse
import fcntl
import json
import sys
from pathlib import Path

import yaml

MAX_EVENTS = 5


def _header(text: str) -> str:
    """Return the leading comment/blank block before the first YAML data line."""
    lines = text.splitlines(keepends=True)
    for i, line in enumerate(lines):
        s = line.strip()
        if s and not s.startswith('#'):
            return ''.join(lines[:i])
    return text


def _load(yml_path: Path) -> tuple[dict, str]:
    text = yml_path.read_text()
    return yaml.safe_load(text), _header(text)


def _save_yaml(yml_path: Path, state: dict, header: str) -> None:
    body = yaml.safe_dump(state, default_flow_style=False, allow_unicode=True, sort_keys=False)
    tmp = yml_path.with_suffix('.yml.tmp')
    tmp.write_text(header + body)
    tmp.replace(yml_path)


def _save_json(json_path: Path, state: dict) -> None:
    data = {
        "project_stats": state.get("project_stats", {}),
        "personas": {
            name: {"affinity": pdata.get("affinity", 0)}
            for name, pdata in state.get("personas", {}).items()
        },
    }
    tmp = json_path.with_suffix('.json.tmp')
    tmp.write_text(json.dumps(data, indent=2) + '\n')
    tmp.replace(json_path)


def _apply_delta(state: dict, slug: str, delta: dict) -> None:
    for name, info in delta.get("personas", {}).items():
        if name not in state.get("personas", {}):
            continue
        pdata = state["personas"][name]
        events = list(pdata.get("events") or [])
        events.append({
            "meeting_slug": slug,
            "decision_id": info.get("decision_id", ""),
            "option":       info.get("option", ""),
            "stance":       info.get("stance", "uninvolved"),
            "valence":      info.get("valence", 0),
        })
        pdata["events"] = events[-MAX_EVENTS:]
        pdata["affinity"] = pdata.get("affinity", 0) + info.get("valence", 0)

    stats = state.setdefault("project_stats", {})
    for key, inc in delta.get("project_stats", {}).items():
        stats[key] = stats.get(key, 0) + inc


def shard(root: Path, session_id: str, slug: str, delta: dict) -> None:
    """Append this session's delta to persona-events/<session_id>.json (zero contention)."""
    shard_dir = root / "persona-events"
    shard_dir.mkdir(exist_ok=True)
    shard_path = shard_dir / f"{session_id}.json"
    shard_path.write_text(json.dumps({"slug": slug, "delta": delta}))


def collapse(root: Path) -> None:
    """Under flock, fold all persona-events shards into persona-state.yml + JSON mirror, then GC shards."""
    yml_path = root / "docs" / "meeting-notes" / "persona-state.yml"
    if not yml_path.exists():
        return

    shard_dir = root / "persona-events"
    if not shard_dir.exists():
        return

    shards = sorted(shard_dir.glob("*.json"))
    if not shards:
        return

    lock_path = shard_dir / ".lock"
    with open(lock_path, "w") as lock_fd:
        fcntl.flock(lock_fd, fcntl.LOCK_EX)
        # Re-read under lock — another collapse may have cleared some shards
        shards = sorted(shard_dir.glob("*.json"))
        if not shards:
            return

        state, header = _load(yml_path)
        for shard_path in shards:
            try:
                record = json.loads(shard_path.read_text())
                _apply_delta(state, record["slug"], record["delta"])
            except (json.JSONDecodeError, KeyError, OSError):
                pass  # corrupt shard — still deleted below

        _save_yaml(yml_path, state, header)
        json_target = root / "web" / "persona-state.json"
        if json_target.parent.exists():
            _save_json(json_target, state)

        for shard_path in shards:
            try:
                shard_path.unlink()
            except OSError:
                pass


def update(root: Path, slug: str, delta: dict) -> None:
    """Legacy single-session update (equivalent to shard+collapse in one step)."""
    yml_path = root / "docs" / "meeting-notes" / "persona-state.yml"
    if not yml_path.exists():
        return

    state, header = _load(yml_path)
    _apply_delta(state, slug, delta)
    _save_yaml(yml_path, state, header)
    json_target = root / "web" / "persona-state.json"
    if json_target.parent.exists():
        _save_json(json_target, state)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="cmd")

    p_shard = sub.add_parser("shard", help="Write this session's delta to persona-events/<session>.json")
    p_shard.add_argument("--root",    required=True, help="Project root (contains docs/meeting-notes/)")
    p_shard.add_argument("--session", required=True, help="Session ID (used as shard filename)")
    p_shard.add_argument("--slug",    required=True, help="Meeting slug (e.g. 2026-06-05-1100-foo)")

    p_collapse = sub.add_parser("collapse", help="Fold all persona-events shards into persona-state.yml under flock")
    p_collapse.add_argument("--root", required=True, help="Project root (contains docs/meeting-notes/)")

    p_update = sub.add_parser("update", help="Legacy: apply a delta from stdin directly (no shard file)")
    p_update.add_argument("--root", required=True, help="Project root (contains docs/meeting-notes/)")
    p_update.add_argument("--slug", required=True, help="Meeting slug (e.g. 2026-06-03-1556-todo-classifier)")

    args = parser.parse_args()

    if args.cmd == "shard":
        try:
            delta = json.load(sys.stdin)
        except json.JSONDecodeError as e:
            print(f"persona-state: invalid JSON on stdin: {e}", file=sys.stderr)
            sys.exit(1)
        shard(Path(args.root), args.session, args.slug, delta)
    elif args.cmd == "collapse":
        collapse(Path(args.root))
    elif args.cmd == "update":
        try:
            delta = json.load(sys.stdin)
        except json.JSONDecodeError as e:
            print(f"persona-state: invalid JSON on stdin: {e}", file=sys.stderr)
            sys.exit(1)
        update(Path(args.root), args.slug, delta)
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
