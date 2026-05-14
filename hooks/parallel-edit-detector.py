#!/usr/bin/env python3
"""
Stop hook: detect potential parallel edits bundled into session commits.

Reads session transcript, extracts Edit/Write tool calls, then checks whether
any committed files in this session contain changes not explained by those calls.
Appends JSONL entries to ~/.claude/logs/parallel-edit-suspects.log.
Writes ~/.claude/logs/parallel-edit-review-due.flag after 50 entries.
"""
import json, sys, os, subprocess, re
from pathlib import Path
from datetime import datetime, timezone

HOME = Path.home()
LOG_FILE = HOME / ".claude/logs/parallel-edit-suspects.log"
FLAG_FILE = HOME / ".claude/logs/parallel-edit-review-due.flag"
LOG_FILE.parent.mkdir(parents=True, exist_ok=True)


def main():
    raw = sys.stdin.read()
    try:
        payload = json.loads(raw)
    except Exception:
        return

    session_id = payload.get("session_id", "")
    transcript_path = payload.get("transcript_path", "")
    if not session_id or not transcript_path:
        return
    tp = Path(transcript_path)
    if not tp.exists():
        return

    # Parse transcript: collect Edit/Write calls and session start time
    edits = {}   # abs_path -> list of old_string
    writes = {}  # abs_path -> intended content
    session_start_iso = None

    with open(tp, errors="replace") as f:
        for raw_line in f:
            try:
                entry = json.loads(raw_line)
            except Exception:
                continue
            if session_start_iso is None and entry.get("timestamp"):
                session_start_iso = entry["timestamp"]
            if entry.get("type") != "assistant":
                continue
            for item in entry.get("message", {}).get("content", []):
                if not isinstance(item, dict) or item.get("type") != "tool_use":
                    continue
                name = item.get("name")
                inp = item.get("input") or {}
                fp = inp.get("file_path", "")
                if not fp:
                    continue
                if name == "Edit":
                    edits.setdefault(fp, []).append(inp.get("old_string", ""))
                elif name == "Write":
                    writes[fp] = inp.get("content", "")

    if not session_start_iso or not (edits or writes):
        return

    # Convert session start to epoch for --since=@epoch (universally supported)
    try:
        dt = datetime.fromisoformat(session_start_iso.replace("Z", "+00:00"))
        since_epoch = int(dt.timestamp())
    except Exception:
        return

    # Find ~/.claude git repo root
    try:
        repo_root = subprocess.check_output(
            ["git", "rev-parse", "--show-toplevel"],
            cwd=str(HOME / ".claude"),
            stderr=subprocess.DEVNULL, text=True
        ).strip()
    except Exception:
        return

    # Get relative paths of files committed since session start
    try:
        log_out = subprocess.check_output(
            ["git", "-C", repo_root, "log",
             f"--since=@{since_epoch}", "--name-only", "--format=COMMIT"],
            stderr=subprocess.DEVNULL, text=True
        )
    except Exception:
        return

    committed_abs = set()
    for line in log_out.splitlines():
        line = line.strip()
        if not line or line == "COMMIT":
            continue
        committed_abs.add(os.path.join(repo_root, line))

    all_touched = set(edits) | set(writes)
    candidates = all_touched & committed_abs
    if not candidates:
        return

    iso_ts = datetime.now(timezone.utc).isoformat()
    suspects = []

    for fp in candidates:
        rel = os.path.relpath(fp, repo_root)
        try:
            patch = subprocess.check_output(
                ["git", "-C", repo_root, "log",
                 f"--since=@{since_epoch}", "-p", "--", rel],
                stderr=subprocess.DEVNULL, text=True, errors="replace"
            )
        except Exception:
            continue

        # Removed lines from the committed diff (strip the leading '-' marker)
        removed_lines = [
            l[1:] for l in patch.splitlines()
            if re.match(r"^-[^-]", l)
        ]
        if not removed_lines:
            continue

        if fp in edits:
            old_strings = edits[fp]
            # A removed line is "accounted for" if it appears as a substring
            # of any old_string (i.e. Claude intended to remove it)
            unexplained = [rl for rl in removed_lines
                           if not any(rl in old for old in old_strings)]
            if unexplained:
                suspects.append({
                    "ts": iso_ts,
                    "session": session_id,
                    "file": fp,
                    "unexplained_removed_lines": len(unexplained),
                    "total_removed_lines": len(removed_lines),
                    "suspicion": "unaccounted_removals",
                    "sample": unexplained[:3],
                })

        elif fp in writes:
            # For Write calls: check if HEAD content matches what Claude wrote
            try:
                head_content = subprocess.check_output(
                    ["git", "-C", repo_root, "show", f"HEAD:{rel}"],
                    stderr=subprocess.DEVNULL, text=True, errors="replace"
                )
            except Exception:
                continue
            if head_content != writes[fp]:
                suspects.append({
                    "ts": iso_ts,
                    "session": session_id,
                    "file": fp,
                    "suspicion": "write_mismatch_committed_vs_intended",
                })

    if suspects:
        with open(LOG_FILE, "a") as f:
            for s in suspects:
                f.write(json.dumps(s) + "\n")

    # Volume marker: flag when 50+ entries accumulated
    try:
        with open(LOG_FILE) as f:
            count = sum(1 for _ in f)
        if count >= 50 and not FLAG_FILE.exists():
            FLAG_FILE.write_text("review_due\n")
    except Exception:
        pass


main()
