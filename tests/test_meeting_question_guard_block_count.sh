#!/usr/bin/env bash
# NO `# roadmap:` header on purpose — this is a DEFECT-FIX test, not the spec for an
# open ROADMAP item, so its failures always count (CLAUDE.md §Testing).
#
# Defect (second round, id:2419): the guard's log shows 17 of 26 blocks recurring
# within the SAME session, 30-90 min apart — the model complies with each block
# then fails identically at the next decision point. Nothing recorded that a block
# had already happened. This test covers the fix: hooks/meeting-question-guard.py
# now persists a per-session block counter in the marker file and echoes it into
# the BLOCK_MESSAGE ("This is BLOCK #N in this session.").
#
# This test exercises the REAL hook script end-to-end, same pattern as
# tests/test_meeting_question_guard_29bc.sh (which it deliberately does not
# duplicate — see that file for the other cases: compliant turns, escape
# hatches, fail-open, etc).
# fails-against: rev c52ee7f029d7 -- the tree as it stood immediately before the commit that
#   added this test, i.e. the pre-fix hooks/meeting-question-guard.py. Derived + verified by tests/verify-negative-cases.py.
# fails-against-rev: c52ee7f029d7 -- hooks/meeting-question-guard.py
# fails-against-assertion: malformed marker: expected 'BLOCK #1' (degraded), got:

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/hooks/meeting-question-guard.py"

pass=0; fail=0
ok()  { echo "  PASS: $1"; pass=$((pass+1)); }
bad() { echo "  FAIL: $1"; fail=$((fail+1)); }

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# Hermetic: same redirection pattern as test_meeting_question_guard_29bc.sh —
# the hook logs under $HOME/.claude/logs and reads its marker from
# $CLAUDE_MEETING_GUARD_DIR, both redirected into the temp tree.
export HOME="$tmpdir/home"
export CLAUDE_MEETING_GUARD_DIR="$tmpdir/markers"
mkdir -p "$HOME" "$CLAUDE_MEETING_GUARD_DIR"
unset MEETING_STOP_GUARD MEETING_STOP_GUARD_MIN_CHARS || true

LONG_PROSE="$(python3 -c 'print("## Discussion — agenda item 2: where the ledger lives. " * 40)')"

# Same fixture builder as test_meeting_question_guard_29bc.sh, trimmed to the
# one shape this file needs: an open meeting, trailing bare prose, no question.
make_defect_transcript() {  # $1 out-path  $2 model
  python3 - "$1" "$2" "$LONG_PROSE" <<'PY'
import json, sys
out, model, long_prose = sys.argv[1:4]
rows = []
def user_text(t):
    rows.append({"type": "user", "isSidechain": False,
                 "message": {"role": "user", "content": t}})
def assistant(blocks):
    rows.append({"type": "assistant", "isSidechain": False,
                 "message": {"role": "assistant", "model": model, "content": blocks}})

user_text("<command-message>meeting</command-message>\n"
          "<command-name>/meeting</command-name>\n"
          "<command-args>id:2419</command-args>")
user_text("Right, and what about the conflict-handback case?")
assistant([{"type": "text", "text": long_prose}])

with open(out, "w") as fh:
    for r in rows:
        fh.write(json.dumps(r) + "\n")
PY
}

run_hook() {  # $1 transcript path, $2 session id
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

# --- 1. first block in a session reports #1 ---------------------------------
make_defect_transcript "$tmpdir/a.jsonl" claude-opus-5
run_hook "$tmpdir/a.jsonl" sess-count-a
if [[ $HOOK_RC -eq 2 ]]; then ok "block 1: still blocks (exit 2)"
else bad "block 1: expected exit 2, got $HOOK_RC"; fi
if grep -q "This is BLOCK #1 in this session." <<<"$HOOK_ERR"; then
  ok "block 1: reports BLOCK #1"
else bad "block 1: expected 'BLOCK #1', got: ${HOOK_ERR:0:300}"; fi

# --- 2. a second block in the SAME session reports #2 -----------------------
run_hook "$tmpdir/a.jsonl" sess-count-a
if [[ $HOOK_RC -eq 2 ]]; then ok "block 2 (same session): still blocks (exit 2)"
else bad "block 2: expected exit 2, got $HOOK_RC"; fi
if grep -q "This is BLOCK #2 in this session." <<<"$HOOK_ERR"; then
  ok "block 2 (same session): reports BLOCK #2"
else bad "block 2: expected 'BLOCK #2', got: ${HOOK_ERR:0:300}"; fi

# --- 3. a block in a DIFFERENT session reports #1 again (per-session) -------
run_hook "$tmpdir/a.jsonl" sess-count-b
if [[ $HOOK_RC -eq 2 ]]; then ok "block in a different session: still blocks (exit 2)"
else bad "different-session block: expected exit 2, got $HOOK_RC"; fi
if grep -q "This is BLOCK #1 in this session." <<<"$HOOK_ERR"; then
  ok "different session starts its own counter at #1 (per-session, not global)"
else bad "different-session block: expected 'BLOCK #1', got: ${HOOK_ERR:0:300}"; fi

# --- 4. forward-scoping sentence is present in the block message ------------
if grep -q "not a one-off fix" <<<"$HOOK_ERR"; then
  ok "block message states the standing (forward-scoping) rule"
else bad "block message missing the forward-scoping sentence: ${HOOK_ERR:0:300}"; fi

# --- 5. a malformed marker file still blocks, still counts, never crashes ---
sess5="sess-count-malformed"
marker5="$CLAUDE_MEETING_GUARD_DIR/claude-meeting-guard-${sess5}.json"
printf '{not valid json' > "$marker5"
run_hook "$tmpdir/a.jsonl" "$sess5"
if [[ $HOOK_RC -eq 2 ]]; then ok "malformed marker: still blocks (fail-open discipline is about ALLOWING, not disabling the block)"
else bad "malformed marker: expected exit 2, got $HOOK_RC (stderr: ${HOOK_ERR:0:200})"; fi
if grep -q "This is BLOCK #1 in this session." <<<"$HOOK_ERR"; then
  ok "malformed marker: counter degrades to a fresh #1 instead of crashing"
else bad "malformed marker: expected 'BLOCK #1' (degraded), got: ${HOOK_ERR:0:300}"; fi

# --- 6. a missing marker directory does not crash the hook (write fails) ----
# CLAUDE_MEETING_GUARD_DIR points at a path that cannot be created (its parent
# is a file, not a directory) — bump_block_count's write must fail closed to
# "omit the count", never propagate.
sess6="sess-count-nowrite"
blockfile="$tmpdir/not-a-dir"
: > "$blockfile"
payload="$(python3 -c 'import json,sys; print(json.dumps({
  "session_id": sys.argv[1], "transcript_path": sys.argv[2],
  "hook_event_name": "Stop", "stop_hook_active": False,
  "cwd": "/repo"}))' "$sess6" "$tmpdir/a.jsonl")"
set +e
HOOK_ERR="$(CLAUDE_MEETING_GUARD_DIR="$blockfile/sub" printf '%s' "$payload" | \
  CLAUDE_MEETING_GUARD_DIR="$blockfile/sub" python3 "$HOOK" 2>&1 >/dev/null)"
HOOK_RC=$?
set -e
if [[ $HOOK_RC -eq 2 ]]; then ok "unwritable marker dir: still blocks, does not crash"
else bad "unwritable marker dir: expected exit 2 (block, no crash), got $HOOK_RC (stderr: ${HOOK_ERR:0:200})"; fi
if grep -q "You ended this turn" <<<"$HOOK_ERR"; then
  ok "unwritable marker dir: block message still renders without a count line"
else bad "unwritable marker dir: block message malformed: ${HOOK_ERR:0:300}"; fi

echo "  ---- $pass passed, $fail failed"
[[ $fail -eq 0 ]]
