#!/usr/bin/env bash
# roadmap:aa93 — integrator data-loss guard: a foreign-dirty main checkout must SURVIVE.
#
# Bug (observed 3× 2026-06-18): the integrate step's clean-tree check was an LLM-agent prompt,
# not a deterministic gate — a concurrent editor's tracked-but-unstaged edit vanished when the
# integrator "cleaned" the tree (stash+drop / checkout -- / reset --hard) to land its merge.
#
# This test pins the deterministic fix:
#   (A) clean-tree-gate.sh observes ONLY (never stash/checkout/reset/clean): on a foreign-dirty
#       tree it reports "dirty N" + exit 2, and the edit SURVIVES on disk untouched.
#   (B) a clean tree → "clean" + exit 0.
#   (C) --accept whitelists a declared-acceptable path so it does not block.
#   (D) relay-loop.js integrate step 1 calls the deterministic gate (not just an agent prompt),
#       aborts/defers on non-zero, and NEVER instructs stash/checkout --/reset --hard/git clean
#       on the main checkout.
#   (E) git-lock-push.sh refuses to autostash-reset a foreign-dirty tree on the rebase path.
#   (F) Makefile registers the new helper (id:5f09 lesson — no un-symlinked script).
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SH="$SRC_DIR/relay/scripts/clean-tree-gate.sh"
JS="$SRC_DIR/relay/scripts/relay-loop.js"
LOCKPUSH="$SRC_DIR/git-diary-workflow/git-lock-push.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

out=""; rc=0
run_gate() { set +e; out="$("$SH" "$@" 2>/dev/null)"; rc=$?; set -e; }

[[ -x "$SH" ]] || fail "clean-tree-gate.sh not found/executable at $SH"
export CLEAN_TREE_LOG=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# A fake "main checkout" with one committed tracked file.
git init -q "$TMP/repo"
printf 'orig\n' >"$TMP/repo/tracked.txt"
git -C "$TMP/repo" add tracked.txt
git -C "$TMP/repo" commit -qm init

# ── (B) clean tree → "clean", exit 0 ──
run_gate "$TMP/repo"
[[ "$rc" -eq 0 ]] || fail "clean tree exit code should be 0 (got $rc)"
[[ "$out" == "clean" ]] || fail "clean tree should print 'clean' (got '$out')"
pass "clean tree reports 'clean' (exit 0)"

# ── (A) foreign-dirty tracked edit → "dirty N", exit 2, AND THE EDIT SURVIVES ──
printf 'orig\nFOREIGN EDIT\n' >"$TMP/repo/tracked.txt"   # tracked, unstaged — the data-loss case
run_gate "$TMP/repo"
[[ "$rc" -eq 2 ]] || fail "foreign-dirty tree exit code should be 2 (got $rc)"
[[ "$out" == dirty\ * ]] || fail "foreign-dirty should print 'dirty N ...' (got '$out')"
# The whole point: the gate must NOT have destroyed the concurrent editor's work.
grep -q "FOREIGN EDIT" "$TMP/repo/tracked.txt" || fail "DATA LOSS: gate destroyed the foreign edit (the id:aa93 bug)"
[[ -z "$(git -C "$TMP/repo" stash list)" ]] || fail "gate stashed the foreign edit (must never stash a main checkout)"
pass "foreign-dirty tree defers (exit 2) and the concurrent edit SURVIVES (no stash, no reset)"

# ── untracked foreign file is also foreign-dirty and survives ──
printf 'new\n' >"$TMP/repo/untracked.txt"
git -C "$TMP/repo" checkout -q -- tracked.txt   # restore tracked to clean for an isolated case
run_gate "$TMP/repo"
[[ "$rc" -eq 2 ]] || fail "untracked-dirty tree exit code should be 2 (got $rc)"
[[ -f "$TMP/repo/untracked.txt" ]] || fail "DATA LOSS: gate deleted an untracked foreign file"
pass "untracked foreign file defers (exit 2) and survives (no git clean)"

# ── (C) --accept whitelists a declared-acceptable path ──
run_gate "$TMP/repo" --accept untracked.txt
[[ "$rc" -eq 0 ]] || fail "--accept of the only dirty path should yield exit 0 (got $rc)"
[[ "$out" == "clean" ]] || fail "--accept of the only dirty path should print 'clean' (got '$out')"
pass "--accept whitelists a declared-acceptable path (treated as clean)"
rm -f "$TMP/repo/untracked.txt"

# ── non-git path → exit 2 ──
run_gate "$TMP/nope"
[[ "$rc" -eq 2 ]] || fail "non-git path exit code should be 2 (got $rc)"
pass "non-git path errors out (exit 2)"

# ── (D) relay-loop.js integrate step calls the deterministic gate + bans force-clean ──
[[ -f "$JS" ]] || fail "relay-loop.js not found at $JS"
grep -q "clean-tree-gate.sh" "$JS" || fail "integrate step does not call the deterministic clean-tree-gate.sh (still an agent-only prompt — id:aa93)"
# The integrator must NEVER be told to clean a foreign tree to make room.
for verb in 'git stash' 'reset --hard' 'checkout --' 'git clean'; do
  if grep -nF "$verb" "$JS" | grep -viq 'never\|NEVER\|must not\|MUST NOT\|do not\|do NOT'; then
    fail "relay-loop.js mentions '$verb' outside an explicit prohibition — risk of force-cleaning a main checkout (id:aa93)"
  fi
done
grep -q "id:aa93" "$JS" || fail "integrate step has no id:aa93 marker (deterministic-gate rationale missing)"
pass "integrate step uses deterministic clean-tree-gate.sh and forbids force-cleaning (id:aa93)"

# ── (E) git-lock-push.sh refuses a foreign-dirty tree on the autostash/rebase path ──
[[ -f "$LOCKPUSH" ]] || fail "git-lock-push.sh not found at $LOCKPUSH"
grep -q "id:aa93" "$LOCKPUSH" || fail "git-lock-push.sh has no id:aa93 guard against autostash-resetting a foreign-dirty tree"
# The rebase path must guard dirtiness before reaching `git pull --rebase --autostash`.
awk '/--rebase --autostash/{found=1} END{exit found?0:1}' "$LOCKPUSH" || fail "git-lock-push.sh no longer has the autostash rebase path (test stale)"
grep -qE "status --porcelain" "$LOCKPUSH" || fail "git-lock-push.sh does not check the tree before the autostash path (id:aa93)"
pass "git-lock-push.sh guards the autostash/rebase path against a foreign-dirty tree (id:aa93)"

# ── (F) Makefile registration (id:5f09 lesson) ──
mk_count="$(grep -c "scripts/clean-tree-gate.sh" "$SRC_DIR/Makefile" || true)"
[[ "$mk_count" -ge 3 ]] || fail "Makefile must register clean-tree-gate.sh in relay_FILES/_EXEC/_ALLOW (3x); got $mk_count"
pass "Makefile registers clean-tree-gate.sh in relay_FILES/_EXEC/_ALLOW"

echo "ALL PASS: integrator foreign-dirty data-loss guard (id:aa93)"
