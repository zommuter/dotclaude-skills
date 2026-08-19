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

Second defect — the guard was a NO-OP for its first six days (fixed 2026-08-19)
------------------------------------------------------------------------------
Shipped 2026-08-13, this hook blocked NOTHING: its log held 50 firings, every one
of them `WARN … trailing segment is empty`, with zero BLOCK and zero SKIP.  The
Stop hook chain runs BEFORE the harness appends the just-ended turn's assistant
lines to the session JSONL, so `trailing_segment()` was structurally always `[]`.

Measured on a live transcript (2026-08-19): the cost logger — first in
the same Stop chain — recorded `wc -l` = 83, and line 83 was the `attachment`
following a `user` tool_result; the turn's own 3159-char assistant `text` entry
was line 84, appended afterwards.  On a second live transcript the
same pattern hid a 7515-char bare-prose meeting turn — precisely the defect this
hook exists to block.

The unit suite passed 16/16 throughout because its fixtures write the trailing
assistant entry BEFORE invoking the hook — a state the live harness never presents
at Stop time.  `tests/test_meeting_question_guard_flush.sh` is the negative
control that fixture class was missing: it withholds the trailing turn on the
first read and appends it from a background writer.

Fix: `await_trailing_segment()` polls until the turn appears and settles.  A turn
that never appears is logged at NOFLUSH — loudly, never silently (id:4347).

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
Formerly-accepted false positive, now CLOSED (2026-08-13, id:2419): the SKILL.md
step-1 warrantability self-check ("are you sure you want a meeting?") used to be a
prose yield inside the window.  SKILL.md and format.md now require it to be posed
through the same harness-class protocol as every other decision point, so it is a
question and no longer trips this guard.  With it closed, **no legitimate prose
yield exists between `/meeting` and the meeting-note Write** — every yield in that
window is a decision point.

MIN_CHARS is deliberately NOT dropped to 0 despite that.  The floor no longer
exempts a *skill step*; it exempts a *conversational* turn — a short clarifying
answer to a user question asked mid-meeting ("what is id:X?") is legitimate, is not
a decision point, and has no `AskUserQuestion` to pair with.  Dropping the floor
would block those, which is the false-block class that gets a hook disabled.  The
measured regressions sit ~7x and ~14x above 800, so the floor costs no coverage.

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
import time
from datetime import datetime, timezone

DEFAULT_MIN_CHARS = 800
LOG_REL = ".claude/logs/meeting-question-guard.log"

# --- transcript-flush wait (id:2419 second defect) ------------------------- #
# The Stop hook chain fires BEFORE the harness appends the just-ended turn's
# assistant lines to the session JSONL, so a naive read sees a transcript that
# ends at the last `user` entry and yields an EMPTY trailing segment.  Measured
# 2026-08-19: 50/50 live firings logged "trailing segment is empty" and the
# guard blocked nothing in 6 days.  See `await_trailing_segment`.
DEFAULT_WAIT_SECS = 3.0     # total budget to wait for the turn to appear
POLL_SECS = 0.05            # re-read interval
SETTLE_SECS = 0.30          # segment must stop growing this long before we judge


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


def await_trailing_segment(path: str, budget: float):
    """Re-read the transcript until the just-ended turn is visible.

    Returns `(entries, seg, waited, settled)`:
      * `entries` / `seg` — the last read, whatever state it reached.
      * `waited`  — seconds spent waiting.
      * `settled` — True iff a non-empty trailing segment appeared AND stopped
        growing for SETTLE_SECS (so we are judging a COMPLETE turn, not a
        half-written one).

    Why this exists: at Stop time the harness has not yet appended the turn's
    assistant lines, so the first read shows a transcript ending at a `user`
    entry.  The lines land shortly after; without this wait the guard evaluates
    an empty segment and can never fire (measured: 50/50 firings, 0 blocks).

    Failure is REPORTED, never silent: the caller logs a distinct NOFLUSH level
    when `settled` is False so a regression in harness ordering shows up in the
    log instead of quietly disarming the gate (id:4347).
    """
    deadline = time.monotonic() + budget
    start = time.monotonic()
    entries = load_entries(path)
    seg = trailing_segment(entries)
    stable_since = time.monotonic() if seg else None
    last_len = len(seg)

    while time.monotonic() < deadline:
        if seg and stable_since is not None and \
                time.monotonic() - stable_since >= SETTLE_SECS:
            return entries, seg, time.monotonic() - start, True
        time.sleep(POLL_SECS)
        try:
            entries = load_entries(path)
        except Exception:
            continue  # a torn read mid-append: just try again
        seg = trailing_segment(entries)
        if len(seg) != last_len:
            last_len = len(seg)
            stable_since = time.monotonic() if seg else None
        elif seg and stable_since is None:
            stable_since = time.monotonic()

    settled = bool(seg) and stable_since is not None and \
        time.monotonic() - stable_since >= SETTLE_SECS
    return entries, seg, time.monotonic() - start, settled


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

    # Cheap pre-check on the unflushed read: outside a meeting window there is
    # nothing to guard and nothing to wait for.  Re-checked below on the settled
    # entries, because the turn that WRITES the meeting note is itself invisible
    # here and would otherwise be judged as still-inside the window.
    if not is_meeting_open(entries):
        return

    try:
        budget = float(os.environ.get("MEETING_STOP_GUARD_WAIT") or DEFAULT_WAIT_SECS)
    except ValueError:
        budget = DEFAULT_WAIT_SECS

    entries, seg, waited, settled = await_trailing_segment(transcript_path, budget)

    if not settled:
        # The just-ended turn never became visible. Fail open — but LOUDLY, so a
        # harness-ordering regression shows up as a log level rather than as a
        # gate that quietly stops firing (this is exactly the defect that made
        # the guard a no-op for its first six days).
        log("NOFLUSH",
            f"session {session_id}: turn never flushed within {budget}s "
            f"(waited {waited:.2f}s, segment entries={len(seg)}) — NOT evaluated")
        return

    if not is_meeting_open(entries):
        # The meeting note was written in this very turn; the window closed.
        return

    cls = str((marker or {}).get("class") or "").strip().lower()
    if not cls:
        cls = "fable" if "fable" in last_model(entries).lower() else "default"
    if cls == "fable":
        # format.md §Interactive mode REQUIRES Fable-class to end on prose with
        # inline numbered options and to NOT call AskUserQuestion.
        log("SKIP", f"session {session_id}: fable-class harness is exempt by spec")
        return

    if segment_has_question(seg):
        log("OK", f"session {session_id}: AskUserQuestion present (waited {waited:.2f}s)")
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
