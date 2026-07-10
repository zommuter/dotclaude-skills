#!/usr/bin/env bash
# (No roadmap token — this test tracks TODO id:2e6d and always counts.)
# Hermetic tests for hooks/memory-index-sync.py, the PostToolUse hook that
# regenerates a project's MEMORY.md index whenever a memory file is written, so a
# newly written memory can never end up without an index pointer (the bug that
# left three memories invisible to recall).
#
# ABSOLUTE: never touches the real ~/.claude memory dir — every fixture is a
# mktemp -d. Covers: end-to-end pointer dissolution; MEMORY.md no-op (no
# recursion); non-memory dir no-op; non-edit tool no-op; malformed payload;
# the loud path (feedback-* archived); and idempotence.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$ROOT/hooks/memory-index-sync.py"
GEN="$ROOT/tools/memory-index.py"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$HOOK" ]] || fail "hook not found at $HOOK"
[[ -f "$GEN" ]] || fail "generator not found at $GEN"
pass "hook + generator scripts exist"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Build a JSON payload: <tool_name> <file_path>
make_payload() {
    local tool_name="$1" file_path="$2"
    python3 -c 'import json,sys; print(json.dumps({"tool_name": sys.argv[1], "tool_input": {"file_path": sys.argv[2]}}))' \
        "$tool_name" "$file_path"
}

# Run the hook on a payload; capture stdout/stderr/exit into globals.
# Returns the hook exit code (does not abort under set -e).
run_hook() {
    local payload="$1"
    HOOK_OUT=""; HOOK_ERR=""; HOOK_RC=0
    HOOK_OUT="$(printf '%s' "$payload" | python3 "$HOOK" 2>"$TMP/stderr")" || HOOK_RC=$?
    HOOK_ERR="$(cat "$TMP/stderr")"
    return 0
}

# Create a memory dir with a seed MEMORY.md so is_memory_file()'s discriminator
# (parent named "memory" AND MEMORY.md present) is satisfied.
new_memory_dir() {
    local d="$1"
    mkdir -p "$d/proj/memory"
    printf '# Project memory\n\n> seed\n\n' > "$d/proj/memory/MEMORY.md"
    echo "$d/proj/memory"
}

write_memory_file() {
    # <memory dir> <basename> <hook-text>
    local dir="$1" base="$2" hook="$3"
    printf -- '---\nhook: %s\n---\n\nbody\n' "$hook" > "$dir/$base"
}

# ── test 1: pointer dissolution, end-to-end ──────────────────────────────────
D1="$(new_memory_dir "$TMP/t1")"
write_memory_file "$D1" "new-fact.md" "a newly written memory with no pointer yet"
grep -q "new-fact.md" "$D1/MEMORY.md" && fail "test1: pointer present before hook (bad fixture)"
run_hook "$(make_payload Write "$D1/new-fact.md")"
[[ "$HOOK_RC" -eq 0 ]] || fail "test1: expected exit 0, got $HOOK_RC (stderr: $HOOK_ERR)"
grep -q "new-fact.md" "$D1/MEMORY.md" || fail "test1: pointer NOT added to MEMORY.md after hook"
pass "test1: memory write with missing pointer → MEMORY.md gains the pointer"

# ── test 2: Write to MEMORY.md itself is a no-op (no recursion) ───────────────
D2="$(new_memory_dir "$TMP/t2")"
BEFORE="$(cat "$D2/MEMORY.md")"
run_hook "$(make_payload Write "$D2/MEMORY.md")"
[[ "$HOOK_RC" -eq 0 ]] || fail "test2: expected exit 0, got $HOOK_RC"
[[ -z "$HOOK_OUT" ]] || fail "test2: expected no stdout, got: $HOOK_OUT"
AFTER="$(cat "$D2/MEMORY.md")"
[[ "$BEFORE" == "$AFTER" ]] || fail "test2: MEMORY.md changed — hook recursed on its own output"
pass "test2: Write to MEMORY.md is a no-op (no recursion)"

# ── test 3: file in a non-memory directory is a no-op ────────────────────────
D3="$TMP/t3/notes"
mkdir -p "$D3"
printf -- '---\nhook: x\n---\n' > "$D3/thing.md"
# Sentinel: an index-shaped file that MUST NOT be created by the generator here.
run_hook "$(make_payload Write "$D3/thing.md")"
[[ "$HOOK_RC" -eq 0 ]] || fail "test3: expected exit 0, got $HOOK_RC"
[[ ! -e "$D3/MEMORY.md" ]] || fail "test3: generator invoked in a non-memory dir (MEMORY.md created)"
pass "test3: write in non-memory dir → generator not invoked, exit 0"

# ── test 4: non-edit tool (Read) is a no-op ──────────────────────────────────
D4="$(new_memory_dir "$TMP/t4")"
write_memory_file "$D4" "unread.md" "should not be indexed via a Read"
run_hook "$(make_payload Read "$D4/unread.md")"
[[ "$HOOK_RC" -eq 0 ]] || fail "test4: expected exit 0, got $HOOK_RC"
grep -q "unread.md" "$D4/MEMORY.md" && fail "test4: Read tool triggered a regeneration"
pass "test4: tool_name=Read → no-op"

# ── test 5: malformed JSON payload → exit 0, no crash ────────────────────────
run_hook 'this is not json {'
[[ "$HOOK_RC" -eq 0 ]] || fail "test5: expected exit 0 on malformed payload, got $HOOK_RC (stderr: $HOOK_ERR)"
pass "test5: malformed JSON payload → exit 0, no crash"

# ── test 6: LOUD path — feedback-* memory marked archived ────────────────────
# The generator exits 2 when a feedback-* memory is archived; the hook must
# surface that on stderr and exit non-zero (PostToolUse cannot block, so the
# loud stderr+nonzero is the chosen contract).
D6="$(new_memory_dir "$TMP/t6")"
printf -- '---\nhook: a durable user preference\nmetadata:\n  archived: true\n---\n\nbody\n' \
    > "$D6/feedback-something.md"
run_hook "$(make_payload Write "$D6/feedback-something.md")"
[[ "$HOOK_RC" -ne 0 ]] || fail "test6: expected non-zero exit on validation failure, got 0"
[[ "$HOOK_RC" -eq 2 ]] || fail "test6: expected exit 2 (loud), got $HOOK_RC"
printf '%s' "$HOOK_ERR" | grep -q "feedback-something.md" \
    || fail "test6: generator's stderr not surfaced (no filename in: $HOOK_ERR)"
printf '%s' "$HOOK_ERR" | grep -q "id:2e6d" \
    || fail "test6: hook diagnostic (id:2e6d) not on stderr"
pass "test6: feedback-* archived → loud stderr + exit 2"

# ── test 7: idempotence — running twice leaves MEMORY.md byte-identical ───────
D7="$(new_memory_dir "$TMP/t7")"
write_memory_file "$D7" "idem.md" "idempotence check"
run_hook "$(make_payload Write "$D7/idem.md")"
[[ "$HOOK_RC" -eq 0 ]] || fail "test7: first run expected exit 0, got $HOOK_RC"
FIRST="$(cat "$D7/MEMORY.md")"
run_hook "$(make_payload Edit "$D7/idem.md")"
[[ "$HOOK_RC" -eq 0 ]] || fail "test7: second run expected exit 0, got $HOOK_RC"
SECOND="$(cat "$D7/MEMORY.md")"
[[ "$FIRST" == "$SECOND" ]] || fail "test7: MEMORY.md differs between runs (not idempotent)"
pass "test7: hook is idempotent (MEMORY.md byte-identical across two runs)"

# ── test 8: generator MISSING is LOUD, not fail-open ─────────────────────────
# Once the payload is known to be a memory file, the index is stale by
# construction. Silently skipping the sync would re-create the exact bug this
# hook closes (a memory with no pointer, invisible to recall — id:4347).
# Simulate by copying the hook somewhere with no ../tools/ sibling.
ORPHAN_HOOK="$TMP/orphan/hooks/memory-index-sync.py"
mkdir -p "$(dirname "$ORPHAN_HOOK")"
cp "$HOOK" "$ORPHAN_HOOK"
[[ ! -f "$TMP/orphan/tools/memory-index.py" ]] || fail "test8: fixture leaked a generator"

D8="$(new_memory_dir "$TMP/t8")"
printf -- '---\nhook: some fact\n---\n\nbody\n' > "$D8/lonely.md"
set +e
ERR8="$(make_payload Write "$D8/lonely.md" | python3 "$ORPHAN_HOOK" 2>&1 >/dev/null)"
RC8=$?
set -e
[[ "$RC8" -eq 2 ]] || fail "test8: expected loud exit 2 when generator is missing, got $RC8"
printf '%s' "$ERR8" | grep -q "generator missing" \
    || fail "test8: expected a 'generator missing' diagnostic, got: $ERR8"
printf '%s' "$ERR8" | grep -qi "stale" \
    || fail "test8: diagnostic must say the index is now stale, got: $ERR8"
pass "test8: generator missing → LOUD exit 2 (no silent index rot)"

echo "ALL PASS"
