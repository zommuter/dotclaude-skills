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
#       AMENDED 2026-08-20 (id:27b4, owner-ratified): "foreign-dirty" here means TRACKED dirt.
#       An UNTRACKED-only tree no longer defers (exit 0) — it still SURVIVES, and the gate still
#       never cleans, so this file's data-loss purpose is intact. RELAY_STRICT_UNTRACKED=1
#       restores the old defer. Rationale + the 19-day yinyang-puzzle outage that motivated it:
#       tests/test_untracked_only_dispatchable_27b4.sh.
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

# ── untracked foreign file: SURVIVES (aa93 core) but no longer DEFERS (id:27b4) ──
# SUPERSEDED 2026-08-20 (owner-ratified): this case previously asserted exit 2. That
# assertion is explicitly retired, NOT silently weakened. The aa93 bug this file pins was a
# TRACKED-but-unstaged edit vanishing when an agent "cleaned" the tree; both core invariants
# are untouched and still asserted below — the gate never cleans, and the file SURVIVES.
# What changed is only the DEFER decision for an untracked-only tree, because blocking on it
# silently parked yinyang-puzzle for 19 days over two campaign assets (no dispatch from
# relay-ckpt-20260731-1801 until 2026-08-20). Safety is not weakened: `git merge` itself
# refuses any merge that would overwrite an untracked file. Strictness is recoverable per-run
# via RELAY_STRICT_UNTRACKED=1, asserted immediately after.
printf 'new\n' >"$TMP/repo/untracked.txt"
git -C "$TMP/repo" checkout -q -- tracked.txt   # restore tracked to clean for an isolated case
run_gate "$TMP/repo"
[[ "$rc" -eq 0 ]] || fail "untracked-only tree should NOT defer since id:27b4 (got $rc)"
[[ -f "$TMP/repo/untracked.txt" ]] || fail "DATA LOSS: gate deleted an untracked foreign file"
pass "untracked-only tree does NOT defer (id:27b4) and still SURVIVES (no git clean)"

# strictness is still available per-run — the escape hatch must actually work
RELAY_STRICT_UNTRACKED=1 run_gate "$TMP/repo"
[[ "$rc" -eq 2 ]] || fail "RELAY_STRICT_UNTRACKED=1 must restore the pre-27b4 defer (got $rc)"
[[ -f "$TMP/repo/untracked.txt" ]] || fail "DATA LOSS: strict mode deleted an untracked file"
pass "RELAY_STRICT_UNTRACKED=1 restores the strict untracked defer, still without cleaning"

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

# ── (D) the integrate step calls the deterministic gate + bans force-clean ──
# id:087b RELOCATION — the integrator is no longer an LLM prompt inside relay-loop.js; it is
# relay/scripts/integrate.sh, dispatched as one mechanical hop. That STRENGTHENS id:aa93: a
# shell script cannot decide to "clean the tree to make room", so the ban is now the total
# ABSENCE of those ops from executable code rather than a prohibition an agent might reweigh.
# Both files are still checked: integrate.sh for the gate + the absent destructive ops,
# relay-loop.js for the dispatch that makes the gate reachable at all.
INTEG="$SRC_DIR/relay/scripts/integrate.sh"
[[ -f "$JS" ]] || fail "relay-loop.js not found at $JS"
[[ -x "$INTEG" ]] || fail "integrate.sh not found/executable at $INTEG"
grep -q "clean-tree-gate.sh" "$INTEG" || fail "integrate.sh does not call the deterministic clean-tree-gate.sh (id:aa93)"
grep -q 'relay/scripts/integrate.sh' "$JS" || fail "relay-loop.js does not dispatch integrate.sh — the clean-tree gate is wired to nothing"
# integrate.sh must contain NO destructive tree op in any CODE line (comments naming the
# banned ops are the rationale, and are tolerated — this is the same check as
# tests/test_integrate_sh_mechanized.sh).
if grep -vE '^\s*#' "$INTEG" | grep -qE 'git .*(stash|reset --hard|checkout --|clean -[a-z])'; then
  fail "id:aa93: integrate.sh contains a destructive tree op in a code line"
fi
# relay-loop.js must never be told to clean a foreign tree to make room either.
for verb in 'git stash' 'reset --hard' 'checkout --' 'git clean'; do
  if grep -nF "$verb" "$JS" | grep -viq 'never\|NEVER\|must not\|MUST NOT\|do not\|do NOT'; then
    fail "relay-loop.js mentions '$verb' outside an explicit prohibition — risk of force-cleaning a main checkout (id:aa93)"
  fi
done
grep -q "id:aa93" "$INTEG" || fail "integrate.sh has no id:aa93 marker (deterministic-gate rationale missing)"
grep -q "id:aa93" "$JS" || fail "relay-loop.js has no id:aa93 marker (the defer-don't-clean rule must stay named at the dispatch site)"
pass "integrate step uses deterministic clean-tree-gate.sh, carries no destructive tree op, and is dispatched from relay-loop.js (id:aa93)"

# ── (E) git-lock-push.sh refuses a foreign-dirty tree on the rebase path ──
[[ -f "$LOCKPUSH" ]] || fail "git-lock-push.sh not found at $LOCKPUSH"
grep -q "id:aa93" "$LOCKPUSH" || fail "git-lock-push.sh has no id:aa93 guard against rebasing over a foreign-dirty tree"
# The rebase path must guard dirtiness before reaching `git pull --rebase`, and the
# `--autostash` flag must stay GONE (dropped 2026-07-08, user-ratified): after the id:aa93
# guard + id:dff8 carve-out it was dead code everywhere except the check→pull race window,
# where it silently stashed+popped a foreign tracked edit — the exact aa93 hazard. Plain
# --rebase makes that race refuse loudly.
awk '/git pull --rebase/{found=1} END{exit found?0:1}' "$LOCKPUSH" || fail "git-lock-push.sh no longer has the rebase pull path (test stale)"
# Match the flag ON the pull command only — the script's comments may (and do) name it.
! grep -qE "pull --rebase.*--autostash|--autostash.*pull --rebase" "$LOCKPUSH" || fail "git-lock-push.sh reintroduced --autostash on the pull (dropped 2026-07-08: silent foreign-stash in the check->pull race window, id:aa93)"
grep -qE "status --porcelain" "$LOCKPUSH" || fail "git-lock-push.sh does not check the tree before the rebase path (id:aa93)"
# Race backstop: a refused-to-start pull warns + exits 0; a mid-rebase conflict must exit 1
# LOUD (never exit-0 over a wedged rebase state).
grep -q "rebase-merge" "$LOCKPUSH" || fail "git-lock-push.sh rebase-failure wrap lacks the rebase-in-progress (conflict) loud-exit branch"
pass "git-lock-push.sh guards the rebase path against a foreign-dirty tree, sans autostash (id:aa93)"

# ── (F) Makefile registration (id:5f09 lesson) ──
mk_count="$(grep -c "scripts/clean-tree-gate.sh" "$SRC_DIR/Makefile" || true)"
[[ "$mk_count" -ge 3 ]] || fail "Makefile must register clean-tree-gate.sh in relay_FILES/_EXEC/_ALLOW (3x); got $mk_count"
pass "Makefile registers clean-tree-gate.sh in relay_FILES/_EXEC/_ALLOW"

echo "ALL PASS: integrator foreign-dirty data-loss guard (id:aa93)"
