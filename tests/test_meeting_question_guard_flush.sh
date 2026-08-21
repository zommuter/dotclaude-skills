#!/usr/bin/env bash
# NO `# roadmap:` header on purpose — DEFECT-FIX test, failures always count
# (CLAUDE.md §Testing).
#
# Defect (id:2419, second round — found 2026-08-19): hooks/meeting-question-guard.py
# shipped 2026-08-13 and blocked NOTHING for six days. Its log held 50 firings, all
# `WARN … trailing segment is empty`, zero BLOCK, zero SKIP.
#
# Cause: the Stop hook chain runs BEFORE the harness appends the just-ended turn's
# assistant lines to the session JSONL. `trailing_segment()` therefore saw a
# transcript ending at a `user` entry and returned [] on every single turn.
# Measured on a live session transcript: the cost logger (first in the same Stop
# chain) recorded wc -l = 83, and the turn's own 3159-char assistant `text` was
# line 84.
#
# Why the 16/16-green suite missed it: EVERY fixture in
# test_meeting_question_guard_29bc.sh writes the trailing assistant entry BEFORE
# invoking the hook — a state the live harness never presents at Stop time. The
# suite tested a premise, not the environment. (MEMORY: green suite ≠ verified.)
#
# This file is that missing negative control. Its fixtures withhold the trailing
# turn on the first read and append it from a BACKGROUND writer, reproducing the
# real ordering. A hook without the flush-wait fails test 1 here.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/hooks/meeting-question-guard.py"

pass=0; fail=0
ok()  { echo "  PASS: $1"; pass=$((pass+1)); }
bad() { echo "  FAIL: $1"; fail=$((fail+1)); }

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

export HOME="$tmpdir/home"
export CLAUDE_MEETING_GUARD_DIR="$tmpdir/markers"
mkdir -p "$HOME" "$CLAUDE_MEETING_GUARD_DIR"
unset MEETING_STOP_GUARD MEETING_STOP_GUARD_MIN_CHARS MEETING_STOP_GUARD_WAIT || true

LOG="$HOME/.claude/logs/meeting-question-guard.log"
LONG_PROSE="$(python3 -c 'print("## Discussion — agenda item 2: where the ledger lives. " * 40)')"

# --------------------------------------------------------------------------- #
# Fixture: a transcript that STOPS at the user entry — i.e. exactly what the
# hook sees when the Stop chain fires. The trailing assistant turn is written
# to a SEPARATE file, to be appended later by the background writer.
#   $1 base path   $2 model   $3 trailing (prose|question)
# --------------------------------------------------------------------------- #
make_pending() {
  python3 - "$1" "$2" "$3" "$LONG_PROSE" <<'PY'
import json, sys
base, model, trailing, long_prose = sys.argv[1:5]

def a(blocks):
    return {"type": "assistant", "isSidechain": False,
            "message": {"role": "assistant", "model": model, "content": blocks}}

def u(text):
    return {"type": "user", "isSidechain": False,
            "message": {"role": "user", "content": [{"type": "text", "text": text}]}}

rows = [
    u("let's plan the ledger"),
    a([{"type": "text", "text": "Sure."}]),
    u("<command-name>/meeting</command-name>\n<command-args>ledger</command-args>"),
    a([{"type": "text", "text": "## Attendees\n" + long_prose[:400]},
       {"type": "tool_use", "id": "toolu_q0", "name": "AskUserQuestion",
        "input": {"questions": [{"question": "Which store?", "header": "Store",
                                 "multiSelect": False,
                                 "options": [{"label": "A", "description": "a"},
                                             {"label": "B", "description": "b"}]}]}}]),
    # The user entry the transcript ENDS on at Stop time (a tool_result).
    {"type": "user", "isSidechain": False,
     "message": {"role": "user",
                 "content": [{"type": "tool_result", "tool_use_id": "toolu_q0",
                              "content": "A"}]}},
]

with open(base, "w") as fh:
    for r in rows:
        fh.write(json.dumps(r) + "\n")

if trailing == "question":
    pending = a([{"type": "text", "text": long_prose},
                 {"type": "tool_use", "id": "toolu_q1", "name": "AskUserQuestion",
                  "input": {"questions": [{"question": "Next?", "header": "Next",
                                           "multiSelect": False,
                                           "options": [{"label": "X", "description": "x"},
                                                       {"label": "Y", "description": "y"}]}]}}])
else:
    pending = a([{"type": "text", "text": long_prose}])

# Realistic split: the harness writes `thinking` and `text` as SEPARATE lines,
# so the segment grows across two appends and the settle rule is exercised.
think = a([{"type": "thinking", "thinking": "considering the options"}])
with open(base + ".pending", "w") as fh:
    fh.write(json.dumps(think) + "\n")
    fh.write(json.dumps(pending) + "\n")
PY
}

# Append the withheld turn after $2 seconds, one line at a time (as the harness does).
start_writer() {  # $1 base path, $2 delay secs
  (
    sleep "$2"
    while IFS= read -r line; do
      printf '%s\n' "$line" >> "$1"
      sleep 0.08
    done < "$1.pending"
  ) &
  WRITER_PID=$!
}

run_hook() {  # $1 transcript, $2 session id
  local payload rc
  payload="$(python3 -c 'import json,sys; print(json.dumps({
    "session_id": sys.argv[1], "transcript_path": sys.argv[2],
    "hook_event_name": "Stop", "stop_hook_active": False,
    "cwd": "/repo"}))' "$2" "$1")"
  set +e
  HOOK_ERR="$(printf '%s' "$payload" | python3 "$HOOK" 2>&1 >/dev/null)"
  rc=$?
  set -e
  HOOK_RC=$rc
}

# --- 1. THE DEFECT: turn not yet flushed at Stop time, lands 0.4s later -> BLOCK --
# This is the case that produced 50/50 no-ops in production.
make_pending "$tmpdir/f1.jsonl" claude-opus-5 prose
start_writer "$tmpdir/f1.jsonl" 0.4
run_hook "$tmpdir/f1.jsonl" flush-1
wait "$WRITER_PID" 2>/dev/null || true
if [[ $HOOK_RC -eq 2 ]]; then
  ok "BLOCKS a bare-prose turn that was still unflushed when the Stop hook fired"
else
  bad "expected exit 2 (the production defect), got $HOOK_RC — the guard is a no-op again (stderr: ${HOOK_ERR:0:160})"
fi

# --- 2. same ordering, but the turn DOES carry AskUserQuestion -> no block --------
make_pending "$tmpdir/f2.jsonl" claude-opus-5 question
start_writer "$tmpdir/f2.jsonl" 0.4
run_hook "$tmpdir/f2.jsonl" flush-2
wait "$WRITER_PID" 2>/dev/null || true
if [[ $HOOK_RC -eq 0 ]]; then
  ok "does not block a compliant turn that flushed late"
else
  bad "expected exit 0 for a late-flushed compliant turn, got $HOOK_RC (stderr: ${HOOK_ERR:0:200})"
fi

# --- 3. the segment must SETTLE: block reflects the whole turn, not a partial read -
# The writer emits `thinking` first and `text` second. A hook that judged the first
# non-empty read would see 0 chars of text and skip below the threshold.
if grep -q "BLOCK" "$LOG" && ! grep -q "trailing prose 0 <" "$LOG"; then
  ok "waits for the segment to settle (judges the full turn, not the first partial line)"
else
  bad "hook judged a partial segment — log shows: $(grep -c BLOCK "$LOG" 2>/dev/null || echo 0) blocks, $(head -1 < <(grep -o 'trailing prose [0-9]* <' "$LOG" 2>/dev/null) )"
fi

# --- 4. turn NEVER flushes -> fail open, but LOUDLY (NOFLUSH, not silence) --------
# Guards id:4347: a detector whose resolution silently no-ops is the anti-pattern
# this whole hook exists to avoid. If harness ordering ever regresses beyond the
# wait budget, the log must say so.
make_pending "$tmpdir/f4.jsonl" claude-opus-5 prose   # no writer started
MEETING_STOP_GUARD_WAIT=0.5 run_hook "$tmpdir/f4.jsonl" flush-4
if [[ $HOOK_RC -eq 0 ]]; then
  ok "fails OPEN when the turn never flushes (does not block on an unseen turn)"
else
  bad "expected exit 0 when the turn never appears, got $HOOK_RC"
fi
if grep -q "NOFLUSH.*flush-4" "$LOG"; then
  ok "records NOFLUSH loudly when the turn never appears (no silent no-op)"
else
  bad "no NOFLUSH line for session flush-4 — the failure is silent (id:4347 anti-pattern); log tail: $(tail -2 "$LOG" 2>/dev/null)"
fi

# --- 5. the wait must not stall a NON-meeting session -----------------------------
# The cheap pre-check has to run before the wait, or every Stop in every session
# pays the full budget.
python3 - "$tmpdir/f5.jsonl" <<'PY'
import json, sys
rows = [{"type": "user", "isSidechain": False,
         "message": {"role": "user", "content": [{"type": "text", "text": "fix a typo"}]}}]
with open(sys.argv[1], "w") as fh:
    for r in rows:
        fh.write(json.dumps(r) + "\n")
PY
t0=$(date +%s%N)
MEETING_STOP_GUARD_WAIT=5 run_hook "$tmpdir/f5.jsonl" flush-5
t1=$(date +%s%N)
elapsed_ms=$(( (t1 - t0) / 1000000 ))
if [[ $HOOK_RC -eq 0 && $elapsed_ms -lt 1000 ]]; then
  ok "returns immediately outside a meeting window (${elapsed_ms}ms, no wait paid)"
else
  bad "non-meeting Stop paid the wait budget: rc=$HOOK_RC elapsed=${elapsed_ms}ms (must be <1000ms)"
fi

echo "  ---- $pass passed, $fail failed"
[[ $fail -eq 0 ]]
