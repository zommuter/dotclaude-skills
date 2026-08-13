#!/usr/bin/env python3
"""
Stop hook: BLOCK a `/meeting` turn that ended on bare transcript prose without a
same-turn `AskUserQuestion` call.

The defect (routed:29bc / TODO id:2419)
---------------------------------------
`meeting/SKILL.md` (## With a subject argument, steps 4-5), the `--fabled` step
0f.5, and `meeting/format.md` §Interactive mode all state the same rule three
times: on Sonnet/Opus/Haiku the facilitator must emit the verbatim transcript
chunk as visible chat content AND call `AskUserQuestion` **in the same response**
— "never end a turn on bare prose and send the question in a subsequent turn".
It keeps failing anyway: filed as routed:29bc (inbound from cartulary, two
corrections in one 2026-08-12 session) and it regressed twice more in the
2026-08-13 id:55f6 session on Opus.  Prose has now failed as an enforcement
mechanism across multiple sessions and multiple models, so the rule moves from
prose to a mechanical, BLOCKING gate (global CLAUDE.md §"Mechanize-first; reserve
the LLM for loud failures"; id:4347 bans the detector whose resolution silently
no-ops, and a warn-only variant here would be exactly that).

Why blocking rather than warn-only: a correct warning emitted ~6300 times over 22
days with zero response is a dead CHANNEL, not a bad message (banked discovery,
relay-core 2026-08-11).  The observe-first heuristic is already satisfied — the
window is routed:29bc plus two same-day recurrences.

Trigger (deliberately narrow)
-----------------------------
Fires only when ALL of these hold:

  1. A `/meeting` window is OPEN in this session's transcript — a `/meeting`
     slash-command entry or a `Skill(skill="meeting")` tool call has occurred,
     and no meeting note (`Write` to `docs/meeting-notes/*.md`) has been written
     since.  The note write is end-of-meeting step 2, i.e. the point past which
     every remaining prompt is an `AskUserQuestion`-driven classification step.
  2. The harness class is NOT Fable.  `format.md` §Interactive mode deliberately
     requires Fable-class runs to end on prose with inline numbered options and
     to NOT call `AskUserQuestion`; firing there would enforce a spec violation.
     Class comes from the marker file when present, else from the last assistant
     entry's `message.model` (`claude-fable-*` → exempt).
  3. The turn's trailing assistant segment contains no `tool_use` block named
     `AskUserQuestion`.
  4. That segment's visible text is at least MIN_CHARS long (default 800).

Why the trailing segment is the right window, and why (4) is needed
-------------------------------------------------------------------
`AskUserQuestion` returns the user's choice as a `tool_result`, so a COMPLIANT
decision point does not end the turn at all — the model continues in the same
turn and the Stop hook never fires there.  Stop fires only where the assistant
genuinely yields to a fresh user message, which inside an open meeting window is
either a true decision point (must carry the question) or a short conversational
aside.  Empirically, on the real 2026-08-13 id:55f6 transcript there were exactly
two such yields between `/meeting` and the note write — both of them the reported
regressions, at 11176 and 5617 characters of prose.  MIN_CHARS=800 keeps a short
clarifying answer (the only plausible legitimate yield) out of the trigger while
sitting ~7x below the observed defects.  Note that arming only after the first
`AskUserQuestion` of the meeting was considered and REJECTED: in that transcript
the first regression preceded every `AskUserQuestion`, so that variant would have
missed the very incident it was built for.

Turns deliberately NOT guarded
------------------------------
  • Everything before `/meeting` and everything after the meeting note is
    written (setup of a later task, the profile/memory/persona classification
    steps, the closing summary) — outside the window.
  • Every compliant decision point (no Stop event fires there at all).
  • Fable-class sessions, entirely.
  • Any turn ending in under MIN_CHARS of prose — a clarifying answer to a user
    question mid-meeting is a legitimate conversational turn.
Known accepted false-positive: the SKILL.md step-1 warrantability self-check
("are you sure you want a meeting?") is a prose yield inside the window.  It is
rare, it is itself a question that would be better posed via `AskUserQuestion`,
and the block is recoverable in one turn.

Escape hatch
------------
  • `MEETING_STOP_GUARD=0` (or `off`/`false`) in the environment — disables
    globally for the session.
  • `bash ~/.claude/hooks/meeting-guard-marker.sh disable` — writes
    `{"disabled": true}` to this session's marker file, disabling the block for
    that session only.  `… end` marks the meeting closed early; `… start
    [--class fable|default]` pins the harness class explicitly.
    Marker path: `$CLAUDE_MEETING_GUARD_DIR` (default `$TMPDIR`, else `/tmp`) /
    `claude-meeting-guard-<session_id>.json` — session-scoped, outside every repo
    tree, so nothing can be committed by accident.
  A marker can only ever REDUCE firing: it never arms the guard on its own.  That
  asymmetry is deliberate — the marker would otherwise be written by the same
  model that already fails to follow the prose rule, so a forgotten marker write
  would silently disarm the gate (the id:4347 anti-pattern one level up), and a
  forgotten marker removal would block every later turn in the session.

Exit codes
----------
  0 — allow the turn to end (not a meeting, compliant turn, exempt, or below
      threshold).
  2 — BLOCK; the stderr message is fed back to the model.
  1 — hook-internal failure (unreadable/malformed transcript or payload).  This
      FAILS OPEN — the turn is allowed to end — but stderr is shown to the user
      rather than swallowed, and the reason is appended to
      `~/.claude/logs/meeting-question-guard.log` (id:4347: no silent swallow).
"""

import json
import os
import sys
from datetime import datetime, timezone

DEFAULT_MIN_CHARS = 800
LOG_REL = ".claude/logs/meeting-question-guard.log"


# --------------------------------------------------------------------------- #
# logging
# --------------------------------------------------------------------------- #
def log(level: str, msg: str) -> None:
    """Append one line to the hook log.  Never raises."""
    try:
        home = os.environ.get("HOME") or ""
        if not home:
            return
        path = os.path.join(home, LOG_REL)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        ts = datetime.now(timezone.utc).astimezone().strftime("%Y-%m-%d %H:%M:%S")
        with open(path, "a", encoding="utf-8") as fh:
            fh.write(f"{ts}\t{level}\t{msg}\n")
    except Exception:
        pass  # logging must never break the hook


def fail_open(reason: str) -> None:
    """Hook-internal failure: allow the turn, but say so loudly (exit 1)."""
    log("FAILOPEN", reason)
    print(
        "meeting-question-guard: FAILED OPEN (turn allowed) — " + reason,
        file=sys.stderr,
    )
    sys.exit(1)


# --------------------------------------------------------------------------- #
# marker file
# --------------------------------------------------------------------------- #
def marker_path(session_id: str) -> str:
    base = os.environ.get("CLAUDE_MEETING_GUARD_DIR") or os.environ.get("TMPDIR") or "/tmp"
    return os.path.join(base, f"claude-meeting-guard-{session_id}.json")


def read_marker(session_id: str):
    """Return the marker dict, or None when absent/unreadable."""
    if not session_id:
        return None
    path = marker_path(session_id)
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
        return data if isinstance(data, dict) else None
    except FileNotFoundError:
        return None
    except Exception as exc:
        # A corrupt marker must not arm OR silently disarm anything: report it
        # and treat it as absent (the transcript-derived path still applies).
        log("WARN", f"unreadable marker {path}: {exc!r}")
        return None


# --------------------------------------------------------------------------- #
# transcript parsing
# --------------------------------------------------------------------------- #
def content_blocks(entry: dict) -> list:
    """Normalize an entry's message content to a list of block dicts."""
    msg = entry.get("message")
    if not isinstance(msg, dict):
        return []
    content = msg.get("content")
    if isinstance(content, str):
        return [{"type": "text", "text": content}]
    if isinstance(content, list):
        return [b for b in content if isinstance(b, dict)]
    return []


def load_entries(path: str) -> list:
    """Parse the session JSONL into main-thread user/assistant entries.

    Sidechain (subagent) entries are excluded — a subagent's turns are not the
    meeting facilitator's turns, and SubagentStop is a different event anyway.
    Individually malformed lines are skipped (a partially-flushed tail line is
    normal); a transcript we cannot open at all is a fail-open condition and is
    raised to the caller.
    """
    entries = []
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                data = json.loads(line)
            except Exception:
                continue
            if not isinstance(data, dict):
                continue
            if data.get("isSidechain"):
                continue
            if data.get("type") not in ("user", "assistant"):
                continue
            entries.append(data)
    return entries


def is_meeting_open(entries: list) -> bool:
    """True iff a /meeting invocation has occurred with no meeting note since."""
    start = None
    note = None
    for i, entry in enumerate(entries):
        blocks = content_blocks(entry)
        if entry.get("type") == "user":
            text = " ".join(str(b.get("text", "")) for b in blocks)
            if "<command-name>/meeting</command-name>" in text or \
               "<command-name>meeting</command-name>" in text:
                start = i
            continue
        for block in blocks:
            if block.get("type") != "tool_use":
                continue
            name = block.get("name")
            inp = block.get("input") if isinstance(block.get("input"), dict) else {}
            if name == "Skill" and str(inp.get("skill", "")).strip() == "meeting":
                start = i
            elif name in ("Write", "NotebookEdit"):
                fp = str(inp.get("file_path", ""))
                if "docs/meeting-notes/" in fp and fp.endswith(".md") \
                        and not fp.endswith("meeting-style.md"):
                    note = i
    if start is None:
        return False
    return note is None or note < start


def last_model(entries: list) -> str:
    for entry in reversed(entries):
        if entry.get("type") != "assistant":
            continue
        msg = entry.get("message")
        if isinstance(msg, dict) and msg.get("model"):
            return str(msg["model"])
    return ""


def trailing_segment(entries: list) -> list:
    """Assistant entries after the last user entry (real prompt or tool_result).

    This is exactly the run of assistant messages the model produced before
    yielding, i.e. the turn the Stop hook is firing on.
    """
    seg = []
    for entry in reversed(entries):
        if entry.get("type") == "user":
            break
        seg.append(entry)
    seg.reverse()
    return seg


def segment_has_question(seg: list) -> bool:
    for entry in seg:
        for block in content_blocks(entry):
            if block.get("type") == "tool_use" and block.get("name") == "AskUserQuestion":
                return True
    return False


def segment_text(seg: list) -> str:
    out = []
    for entry in seg:
        for block in content_blocks(entry):
            if block.get("type") == "text":
                out.append(str(block.get("text", "")))
    return "".join(out)


# --------------------------------------------------------------------------- #
# main
# --------------------------------------------------------------------------- #
BLOCK_MESSAGE = """\
BLOCKED by meeting-question-guard (routed:29bc / TODO id:2419).

You ended this turn on {n} characters of meeting transcript prose with no
AskUserQuestion call. meeting/format.md §Interactive mode (Sonnet/Opus/Haiku) and
meeting/SKILL.md step 5 both require the transcript chunk AND the AskUserQuestion
call in the SAME response — never end a turn on bare prose and send the question
in a subsequent turn.

Do this now: do NOT re-emit the prose you just wrote. Call AskUserQuestion for the
decision that prose leads to, with an embedded tl;dr (2-3 sentences of the state
of play), 3 implication-driven options derived from the personas' reasoning, and
the recommended option first and labelled "(Recommended)".

If this turn genuinely had no decision point (e.g. answering a direct question
mid-meeting), disable the guard for this session and continue:
  bash ~/.claude/hooks/meeting-guard-marker.sh disable
"""


def main() -> None:
    try:
        raw = sys.stdin.read()
    except Exception as exc:
        fail_open(f"could not read hook payload from stdin: {exc!r}")
        return

    try:
        payload = json.loads(raw)
        if not isinstance(payload, dict):
            raise ValueError("payload is not a JSON object")
    except Exception as exc:
        fail_open(f"malformed hook payload: {exc!r}")
        return

    # Never re-block a turn that this hook already blocked once (loop guard).
    if payload.get("stop_hook_active"):
        return

    env_switch = (os.environ.get("MEETING_STOP_GUARD") or "").strip().lower()
    if env_switch in ("0", "off", "false", "no"):
        log("SKIP", "disabled via MEETING_STOP_GUARD")
        return

    session_id = str(payload.get("session_id") or "")
    marker = read_marker(session_id)
    if marker is not None:
        if marker.get("disabled") is True:
            log("SKIP", f"session {session_id}: marker disabled")
            return
        if marker.get("active") is False:
            log("SKIP", f"session {session_id}: marker marks the meeting ended")
            return

    transcript_path = str(payload.get("transcript_path") or "")
    if not transcript_path:
        fail_open("hook payload carried no transcript_path")
        return
    try:
        entries = load_entries(transcript_path)
    except Exception as exc:
        fail_open(f"could not read transcript {transcript_path}: {exc!r}")
        return

    if not is_meeting_open(entries):
        return

    cls = str((marker or {}).get("class") or "").strip().lower()
    if not cls:
        cls = "fable" if "fable" in last_model(entries).lower() else "default"
    if cls == "fable":
        # format.md §Interactive mode REQUIRES Fable-class to end on prose with
        # inline numbered options and to NOT call AskUserQuestion.
        log("SKIP", f"session {session_id}: fable-class harness is exempt by spec")
        return

    seg = trailing_segment(entries)
    if not seg:
        # Either the transcript tail has not been flushed yet, or the turn ended
        # on a tool result. Do not block on an empty read — but do not swallow it.
        log("WARN", f"session {session_id}: meeting open but trailing segment is empty")
        return

    if segment_has_question(seg):
        return

    try:
        min_chars = int(os.environ.get("MEETING_STOP_GUARD_MIN_CHARS") or DEFAULT_MIN_CHARS)
    except ValueError:
        min_chars = DEFAULT_MIN_CHARS

    text = segment_text(seg)
    if len(text) < min_chars:
        log("SKIP", f"session {session_id}: trailing prose {len(text)} < {min_chars} chars")
        return

    log("BLOCK", f"session {session_id}: {len(text)} chars of prose, no AskUserQuestion")
    print(BLOCK_MESSAGE.format(n=len(text)), file=sys.stderr)
    sys.exit(2)


main()
