#!/usr/bin/env bash
# NO `# roadmap:` header on purpose — this is a DEFECT-FIX test, not the spec for an
# open ROADMAP item, so its failures always count (CLAUDE.md §Testing).
#
# Defect: the /meeting same-turn "transcript chunk + AskUserQuestion in ONE response"
# protocol keeps being violated (routed:29bc / TODO id:2419 — inbound from cartulary,
# plus two more regressions in the 2026-08-13 id:55f6 session on Opus). The rule is
# stated in three places in prose and prose has failed as enforcement, so it is now a
# BLOCKING Stop hook: hooks/meeting-question-guard.py.
#
# This test exercises the REAL hook script end-to-end against realistic Stop-hook stdin
# JSON and realistic session-transcript JSONL fixtures. It deliberately does NOT grep
# the hook's source — this repo already has two tests that do that (id:3a50, id:05a2)
# and both stayed green through a full revert of the code they were supposed to guard.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/hooks/meeting-question-guard.py"
MARKER_SH="$REPO_ROOT/hooks/meeting-guard-marker.sh"

pass=0; fail=0
ok()  { echo "  PASS: $1"; pass=$((pass+1)); }
bad() { echo "  FAIL: $1"; fail=$((fail+1)); }

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# Hermetic: the hook logs under $HOME/.claude/logs and reads its marker from
# $CLAUDE_MEETING_GUARD_DIR — both redirected into the temp tree. The real
# ~/.claude is never touched.
export HOME="$tmpdir/home"
export CLAUDE_MEETING_GUARD_DIR="$tmpdir/markers"
mkdir -p "$HOME" "$CLAUDE_MEETING_GUARD_DIR"
unset MEETING_STOP_GUARD MEETING_STOP_GUARD_MIN_CHARS || true

LONG_PROSE="$(python3 -c 'print("## Discussion — agenda item 2: where the ledger lives. " * 40)')"
SHORT_PROSE="Yes — that file is the flocked append helper."

# ---------------------------------------------------------------------------
# Fixture builder: writes a realistic session JSONL.
#   $1 out-path
#   $2 model            (e.g. claude-opus-5 / claude-fable-5)
#   $3 meeting          (open|closed|none)
#   $4 trailing         (prose|question|prose-short|empty)
# ---------------------------------------------------------------------------
make_transcript() {
  python3 - "$1" "$2" "$3" "$4" "$LONG_PROSE" "$SHORT_PROSE" <<'PY'
import json, sys
out, model, meeting, trailing, long_prose, short_prose = sys.argv[1:7]
rows = []
def user_text(t):
    rows.append({"type": "user", "isSidechain": False,
                 "message": {"role": "user", "content": t}})
def assistant(blocks):
    rows.append({"type": "assistant", "isSidechain": False,
                 "message": {"role": "assistant", "model": model, "content": blocks}})
def tool_result(tid):
    rows.append({"type": "user", "isSidechain": False, "isMeta": True,
                 "message": {"role": "user", "content": [
                     {"type": "tool_result", "tool_use_id": tid,
                      "content": "Your questions have been answered."}]}})

if meeting != "none":
    user_text("<command-message>meeting</command-message>\n"
              "<command-name>/meeting</command-name>\n"
              "<command-args>--fabled 55f6</command-args>")
else:
    user_text("Please refactor the classifier and run the suite.")

# A prior compliant decision point: transcript chunk + AskUserQuestion, same message,
# whose answer comes back as a tool_result (so no turn ever ended there).
assistant([{"type": "text", "text": "## Discussion — agenda item 1\n" + long_prose[:600]},
           {"type": "tool_use", "id": "toolu_prior", "name": "AskUserQuestion",
            "input": {"questions": [{"question": "Which substrate?",
                                     "header": "D1", "options": []}]}}])
tool_result("toolu_prior")
assistant([{"type": "text", "text": "Recorded D1."}])

if meeting == "closed":
    # End-of-meeting step 2: the meeting note is written. Everything after this
    # point is outside the guarded window.
    assistant([{"type": "tool_use", "id": "toolu_w", "name": "Write",
                "input": {"file_path": "/repo/docs/meeting-notes/2026-08-13-1415-x.md",
                          "content": "# note"}}])
    tool_result("toolu_w")

# The turn the Stop hook is firing on.
user_text("Right, and what about the conflict-handback case?")
if trailing == "prose":
    assistant([{"type": "text", "text": long_prose}])
elif trailing == "prose-short":
    assistant([{"type": "text", "text": short_prose}])
elif trailing == "question":
    assistant([{"type": "text", "text": long_prose},
               {"type": "tool_use", "id": "toolu_now", "name": "AskUserQuestion",
                "input": {"questions": [{"question": "Handback policy?",
                                         "header": "D2", "options": []}]}}])
elif trailing == "empty":
    pass

with open(out, "w") as fh:
    for r in rows:
        fh.write(json.dumps(r) + "\n")
PY
}

# Run the hook with a Stop payload; echo "<exit>|<stderr>" via globals.
run_hook() {  # $1 transcript path, $2 session id, $3 stop_hook_active (true/false)
  local payload rc
  payload="$(python3 -c 'import json,sys; print(json.dumps({
    "session_id": sys.argv[1], "transcript_path": sys.argv[2],
    "hook_event_name": "Stop", "stop_hook_active": sys.argv[3] == "true",
    "cwd": "/repo"}))' "$2" "$1" "$3")"
  set +e
  HOOK_ERR="$(printf '%s' "$payload" | python3 "$HOOK" 2>&1 >/dev/null)"
  rc=$?
  set -e
  HOOK_RC=$rc
}

# --- 1. THE DEFECT: meeting open, Opus, long prose, no AskUserQuestion -> BLOCK ----
make_transcript "$tmpdir/t1.jsonl" claude-opus-5 open prose
run_hook "$tmpdir/t1.jsonl" sess-1 false
if [[ $HOOK_RC -eq 2 ]]; then ok "blocks (exit 2) an open-meeting turn ending on prose with no AskUserQuestion"
else bad "expected exit 2 on the defect turn, got $HOOK_RC (stderr: ${HOOK_ERR:0:120})"; fi
if grep -q "AskUserQuestion" <<<"$HOOK_ERR"; then ok "block message names AskUserQuestion as the required next action"
else bad "block message does not tell the model what to do next: ${HOOK_ERR:0:200}"; fi

# --- 2. compliant turn: same prose but with AskUserQuestion in the same turn -------
make_transcript "$tmpdir/t2.jsonl" claude-opus-5 open question
run_hook "$tmpdir/t2.jsonl" sess-2 false
if [[ $HOOK_RC -eq 0 ]]; then ok "does not block when the turn carries an AskUserQuestion tool call"
else bad "expected exit 0 for a compliant turn, got $HOOK_RC (stderr: ${HOOK_ERR:0:200})"; fi

# --- 3. no meeting in this session -> never fires ---------------------------------
make_transcript "$tmpdir/t3.jsonl" claude-opus-5 none prose
run_hook "$tmpdir/t3.jsonl" sess-3 false
if [[ $HOOK_RC -eq 0 ]]; then ok "does not block outside a /meeting window"
else bad "expected exit 0 with no meeting active, got $HOOK_RC (stderr: ${HOOK_ERR:0:200})"; fi

# --- 4. Fable-class is EXEMPT (format.md requires prose-with-inline-options) -------
make_transcript "$tmpdir/t4.jsonl" claude-fable-5 open prose
run_hook "$tmpdir/t4.jsonl" sess-4 false
if [[ $HOOK_RC -eq 0 ]]; then ok "does not block on a Fable-class harness (exempt by format.md spec)"
else bad "expected exit 0 on Fable-class, got $HOOK_RC (stderr: ${HOOK_ERR:0:200})"; fi

# --- 4b. Fable exemption also honoured when pinned via the marker -----------------
make_transcript "$tmpdir/t4b.jsonl" claude-opus-5 open prose
bash "$MARKER_SH" start --class fable --session sess-4b >/dev/null
run_hook "$tmpdir/t4b.jsonl" sess-4b false
if [[ $HOOK_RC -eq 0 ]]; then ok "marker --class fable exempts even when the transcript model is Opus"
else bad "expected exit 0 with marker class=fable, got $HOOK_RC (stderr: ${HOOK_ERR:0:200})"; fi

# --- 5. meeting note already written -> window closed -----------------------------
make_transcript "$tmpdir/t5.jsonl" claude-opus-5 closed prose
run_hook "$tmpdir/t5.jsonl" sess-5 false
if [[ $HOOK_RC -eq 0 ]]; then ok "does not block after the meeting note has been written"
else bad "expected exit 0 once the meeting note is written, got $HOOK_RC (stderr: ${HOOK_ERR:0:200})"; fi

# --- 6. unreadable transcript -> FAIL OPEN, but loudly (exit 1, stderr non-empty) --
run_hook "$tmpdir/does-not-exist.jsonl" sess-6 false
if [[ $HOOK_RC -ne 2 ]]; then ok "fails OPEN (does not block) on an unreadable transcript"
else bad "blocked the session because it could not read its own input"; fi
if [[ -n "$HOOK_ERR" ]]; then ok "fail-open path is loud (stderr carries the reason)"
else bad "fail-open path swallowed the reason silently (id:4347)"; fi

# --- 6b. malformed payload -> fail open, loud -------------------------------------
set +e
HOOK_ERR="$(printf 'not json at all' | python3 "$HOOK" 2>&1 >/dev/null)"; HOOK_RC=$?
set -e
if [[ $HOOK_RC -ne 2 && -n "$HOOK_ERR" ]]; then ok "fails OPEN and loudly on a malformed hook payload"
else bad "malformed payload handling wrong: rc=$HOOK_RC stderr='${HOOK_ERR:0:120}'"; fi

# --- 7. escape hatches ------------------------------------------------------------
make_transcript "$tmpdir/t7.jsonl" claude-opus-5 open prose
bash "$MARKER_SH" disable --session sess-7 >/dev/null
run_hook "$tmpdir/t7.jsonl" sess-7 false
if [[ $HOOK_RC -eq 0 ]]; then ok "marker 'disable' escape hatch suppresses the block for that session"
else bad "expected exit 0 with the marker disabled, got $HOOK_RC"; fi

bash "$MARKER_SH" end --session sess-7e >/dev/null
run_hook "$tmpdir/t7.jsonl" sess-7e false
if [[ $HOOK_RC -eq 0 ]]; then ok "marker 'end' closes the meeting early"
else bad "expected exit 0 after marker end, got $HOOK_RC"; fi

set +e
HOOK_ERR="$(MEETING_STOP_GUARD=0 python3 -c 'import json,sys;print(json.dumps({"session_id":"sess-7v","transcript_path":sys.argv[1],"stop_hook_active":False}))' "$tmpdir/t1.jsonl" | MEETING_STOP_GUARD=0 python3 "$HOOK" 2>&1 >/dev/null)"
HOOK_RC=$?
set -e
if [[ $HOOK_RC -eq 0 ]]; then ok "MEETING_STOP_GUARD=0 disables the block"
else bad "expected exit 0 with MEETING_STOP_GUARD=0, got $HOOK_RC"; fi

# --- 8. a short conversational turn is not a decision point ------------------------
make_transcript "$tmpdir/t8.jsonl" claude-opus-5 open prose-short
run_hook "$tmpdir/t8.jsonl" sess-8 false
if [[ $HOOK_RC -eq 0 ]]; then ok "does not block a short clarifying answer (below the prose threshold)"
else bad "expected exit 0 for a sub-threshold turn, got $HOOK_RC"; fi

# --- 9. loop guard: never re-block a turn this hook already blocked ----------------
run_hook "$tmpdir/t1.jsonl" sess-9 true
if [[ $HOOK_RC -eq 0 ]]; then ok "honours stop_hook_active (no block loop)"
else bad "expected exit 0 when stop_hook_active is true, got $HOOK_RC"; fi

# --- 10. the block is recorded in the hook log ------------------------------------
if grep -q "BLOCK" "$HOME/.claude/logs/meeting-question-guard.log" 2>/dev/null; then
  ok "block is recorded in ~/.claude/logs/meeting-question-guard.log"
else bad "no BLOCK line in the hook log"; fi

echo "  ---- $pass passed, $fail failed"
[[ $fail -eq 0 ]]
