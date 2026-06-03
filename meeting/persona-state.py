#!/usr/bin/env python3
"""
persona-state.py — update docs/meeting-notes/persona-state.yml and mirror to web/persona-state.json.

Usage:
    python3 persona-state.py update --root <ROOT> --slug <SLUG>

Delta JSON on stdin:
{
  "personas": {
    "riku":  {"decision_id": "D2", "option": "label", "stance": "advocated", "valence": 1},
    "archie": {"decision_id": "D2", "option": "label", "stance": "opposed",   "valence": -1}
  },
  "project_stats": {"conviction": 1, "wisdom": 0, "tech_debt": 1}
}

Gate: if <root>/docs/meeting-notes/persona-state.yml does not exist, exit 0 silently.
Unknown persona keys in the delta are skipped (forward-compat).
"""
import argparse
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


def update(root: Path, slug: str, delta: dict) -> None:
    yml_path = root / "docs" / "meeting-notes" / "persona-state.yml"
    if not yml_path.exists():
        return

    state, header = _load(yml_path)

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

    _save_yaml(yml_path, state, header)
    _save_json(root / "web" / "persona-state.json", state)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="cmd")
    p = sub.add_parser("update", help="Apply a delta from stdin to persona-state.yml + JSON mirror")
    p.add_argument("--root",  required=True, help="Project root (contains docs/meeting-notes/)")
    p.add_argument("--slug",  required=True, help="Meeting slug (e.g. 2026-06-03-1556-todo-classifier)")
    args = parser.parse_args()

    if args.cmd == "update":
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
