#!/usr/bin/env bash
# (No roadmap token — this test tracks TODO id:b67e and always counts.)
# Hermetic tests for hooks/pathspec-drop-guard.py:
#   (1) a genuine pathspec drop (typo'd path arg not in staged set) IS blocked
#   (2) an ordinary diary-style partial-staging commit (all path args staged) is NOT blocked
#   (3) a bare 'git commit -m "..."' (no path args) is NOT blocked
#   (4) a staged-directory prefix matches correctly and is NOT blocked
#   (5) an unstaged-but-tracked file referenced as path arg IS blocked
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$ROOT/hooks/pathspec-drop-guard.py"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$GUARD" ]] || fail "pathspec-drop-guard.py not found at $GUARD"
pass "guard script exists"

# ── helpers ──────────────────────────────────────────────────────────────────

# Construct a PreToolUse JSON payload for a Bash tool call
make_payload() {
    local cmd="$1"
    printf '{"session_id":"test","tool_name":"Bash","tool_input":{"command":%s}}' \
        "$(printf '%s' "$cmd" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"
}

# Run the guard from a given directory; return stdout
run_guard() {
    local repo_dir="$1"
    local payload="$2"
    (cd "$repo_dir" && printf '%s' "$payload" | python3 "$GUARD")
}

# ── set up a bare temp git repo ───────────────────────────────────────────────

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email "test@test"
git -C "$REPO" config user.name "Test"

# Create and commit an initial set of tracked files
touch "$REPO/diary.md" "$REPO/todo.md" "$REPO/notes.py" "$REPO/other.py"
git -C "$REPO" add .
git -C "$REPO" commit -q -m "initial"

# Modify files so they have tracked changes
echo "diary content" > "$REPO/diary.md"
echo "todo content"  > "$REPO/todo.md"
echo "notes content" > "$REPO/notes.py"
echo "other content" > "$REPO/other.py"

# Stage diary.md and todo.md; leave notes.py and other.py unstaged
git -C "$REPO" add diary.md todo.md

# ── test 1: pathspec typo is BLOCKED ─────────────────────────────────────────
# diary.md is staged, but diar.md (typo) is not → should block
PAYLOAD="$(make_payload 'git commit -m "msg" diary.md diar.md')"
OUT="$(run_guard "$REPO" "$PAYLOAD")"
[[ -n "$OUT" ]] || fail "test1: expected block output, got nothing"
DECISION="$(printf '%s' "$OUT" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read()).get("decision",""))')"
[[ "$DECISION" == "block" ]] || fail "test1: expected decision=block, got '$DECISION'"
pass "test1: pathspec typo 'diar.md' is blocked"

# ── test 2: diary-style partial commit is NOT blocked ────────────────────────
# diary.md and todo.md are both staged; other staged files intentionally omitted.
PAYLOAD="$(make_payload 'git commit -m "diary: update" diary.md todo.md')"
OUT="$(run_guard "$REPO" "$PAYLOAD")"
[[ -z "$OUT" ]] || fail "test2: expected no output (allow), got: $OUT"
pass "test2: diary-style commit with all path-args staged is not blocked"

# ── test 3: bare commit (no explicit path args) is NOT blocked ───────────────
PAYLOAD="$(make_payload 'git commit -m "refactor: all staged"')"
OUT="$(run_guard "$REPO" "$PAYLOAD")"
[[ -z "$OUT" ]] || fail "test3: expected no output for bare commit, got: $OUT"
pass "test3: bare 'git commit -m ...' (no path args) is not blocked"

# ── test 4: directory prefix matches staged files ─────────────────────────────
# Stage a file inside a subdirectory; commit using the directory prefix
mkdir -p "$REPO/subdir"
echo "subfile content" > "$REPO/subdir/file.md"
git -C "$REPO" add "$REPO/subdir/file.md"

PAYLOAD="$(make_payload 'git commit -m "add subdir file" subdir/')"
OUT="$(run_guard "$REPO" "$PAYLOAD")"
[[ -z "$OUT" ]] || fail "test4: expected no output for dir-prefix commit, got: $OUT"
pass "test4: directory prefix 'subdir/' matches staged 'subdir/file.md', not blocked"

# ── test 5: unstaged-but-tracked file as path arg IS blocked ─────────────────
# notes.py is tracked and modified but NOT staged → specifying it in commit args is suspicious
PAYLOAD="$(make_payload 'git commit -m "partial" diary.md notes.py')"
OUT="$(run_guard "$REPO" "$PAYLOAD")"
[[ -n "$OUT" ]] || fail "test5: expected block output, got nothing"
DECISION="$(printf '%s' "$OUT" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read()).get("decision",""))')"
[[ "$DECISION" == "block" ]] || fail "test5: expected decision=block for unstaged path arg, got '$DECISION'"
pass "test5: unstaged-but-tracked 'notes.py' as path arg is blocked"

# ── test 6: '--' separator correctly separates flags from paths ───────────────
PAYLOAD="$(make_payload 'git commit -m "dashdash" -- diary.md todo.md')"
OUT="$(run_guard "$REPO" "$PAYLOAD")"
[[ -z "$OUT" ]] || fail "test6: '--' separator: expected no output, got: $OUT"
pass "test6: '--' separator correctly identified; staged paths not blocked"

# ── test 7: non-git command is not intercepted ───────────────────────────────
PAYLOAD="$(make_payload 'echo git commit -m "not a commit"')"
OUT="$(run_guard "$REPO" "$PAYLOAD")"
[[ -z "$OUT" ]] || fail "test7: expected no output for non-git command, got: $OUT"
pass "test7: non-git command not intercepted"

# ── test 8: non-Bash tool is not intercepted ─────────────────────────────────
NON_BASH='{"session_id":"test","tool_name":"Read","tool_input":{"file_path":"/tmp/x"}}'
OUT="$(run_guard "$REPO" "$NON_BASH")"
[[ -z "$OUT" ]] || fail "test8: expected no output for non-Bash tool, got: $OUT"
pass "test8: non-Bash tool not intercepted"

# ── test 9: heredoc commit message containing double quotes is NOT blocked ───
# Regression for routed:b213: shlex.split() on the raw command treated the literal
# double quotes inside the heredoc body as shell quotes, re-bracketing the rest
# of the message into bogus pathspec args, which wrongly blocked the commit.
# A *multi-word* quoted phrase is required to reproduce: a single-word phrase
# re-concatenates into one token and never surfaced the bug.
MSG_CMD='git commit -m "$(cat <<'"'"'EOF'"'"'
Correct the "canonical version" mis-citation.
EOF
)"'
PAYLOAD="$(make_payload "$MSG_CMD")"
OUT="$(run_guard "$REPO" "$PAYLOAD")"
[[ -z "$OUT" ]] || fail "test9: heredoc message with double quotes must NOT block, got: $OUT"
pass "test9: heredoc commit message with inner double quotes is not blocked"

# ── test 10: heredoc message with a literal single quote is NOT blocked ──────
MSG_CMD='git commit -m "$(cat <<'"'"'EOF'"'"'
it'"'"'s a mis-citation, not a "load bearing claim"
EOF
)"'
PAYLOAD="$(make_payload "$MSG_CMD")"
OUT="$(run_guard "$REPO" "$PAYLOAD")"
[[ -z "$OUT" ]] || fail "test10: heredoc message with single quote must NOT block, got: $OUT"
pass "test10: heredoc commit message with inner single quote is not blocked"

# ── test 11: the guard still blocks a real typo (no substitution present) ─────
# Guards the fix against over-reach: bailing on '$('/heredoc must not disable
# the plain-command path that id:b67e exists for.
PAYLOAD="$(make_payload 'git commit -m "msg" diary.md diar.md')"
OUT="$(run_guard "$REPO" "$PAYLOAD")"
[[ -n "$OUT" ]] || fail "test11: plain typo must still block after the b213 fix"
pass "test11: b213 bail does not disable the plain-command typo guard"

echo "ALL PASS"
