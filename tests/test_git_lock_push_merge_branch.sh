#!/usr/bin/env bash
# Tests for git-lock-push.sh --merge-branch mode (TODO id:3558: "Independent-session
# flock'd merge-to-canonical"). No roadmap item — this is a TODO/meeting-note build,
# not a ROADMAP [ROUTINE] item, so no `# roadmap:XXXX` header / EXPECTED-RED gating
# applies; failures here always count.
#
# Contract under test (D5.6, docs/meeting-notes/2026-06-04-1144-worktree-per-session-d5.md):
# each independent session commits in its OWN git worktree, then merges back into the
# shared canonical checkout under the repo's existing per-repo flock via
# `git-lock-push.sh --merge-branch <branch>`. Two sessions merging DISJOINT changes
# concurrently must both land (no lost update); two sessions merging a genuine
# same-path CONFLICT must have the second one fail loud (merge aborted, branch/commit
# preserved for manual resolution) rather than silently last-writer-wins (D5.2 — the
# plumbing-CAS approach was rejected specifically for this silent-loss failure mode).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOCK_PUSH="$REPO_ROOT/git-diary-workflow/git-lock-push.sh"

pass=0; fail=0

ok() { echo "  PASS: $1"; pass=$((pass+1)); }
fail_msg() { echo "  FAIL: $1"; fail=$((fail+1)); }

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

bare="$tmpdir/remote.git"
canon="$tmpdir/canon"   # the canonical checkout both independent sessions merge into
git init --bare -q "$bare"
git init -q "$canon"
git -C "$canon" config user.email "test@test"
git -C "$canon" config user.name "Test"
git -C "$canon" remote add origin "$bare"

echo "init" > "$canon/README"
git -C "$canon" add README
git -C "$canon" commit -q -m "init"
git -C "$canon" push -q --set-upstream origin main >/dev/null 2>&1

# ── Test 1: two independent-session worktrees, DISJOINT files, concurrent
#            flock'd merge-to-canonical — no lost update ─────────────────────
echo "Test 1: concurrent disjoint-file merges both land (no lost update)"

wtA="$tmpdir/wtA"
wtB="$tmpdir/wtB"
git -C "$canon" worktree add -q -b session-a "$wtA" main
git -C "$canon" worktree add -q -b session-b "$wtB" main

echo "a" > "$wtA/file-a.txt"
git -C "$wtA" add file-a.txt
git -C "$wtA" commit -q -m "session A: add file-a"

echo "b" > "$wtB/file-b.txt"
git -C "$wtB" add file-b.txt
git -C "$wtB" commit -q -m "session B: add file-b"

outA="$tmpdir/outA.log"
outB="$tmpdir/outB.log"
"$LOCK_PUSH" "$canon" --merge-branch session-a -m "merge session-a" >"$outA" 2>&1 &
pidA=$!
"$LOCK_PUSH" "$canon" --merge-branch session-b -m "merge session-b" >"$outB" 2>&1 &
pidB=$!
rcA=0; wait "$pidA" || rcA=$?
rcB=0; wait "$pidB" || rcB=$?

if [[ "$rcA" -eq 0 && "$rcB" -eq 0 ]]; then
  ok "both concurrent disjoint merges exited 0"
else
  fail_msg "a disjoint merge failed (rcA=$rcA rcB=$rcB); outA=$(cat "$outA"); outB=$(cat "$outB")"
fi

if [[ -f "$canon/file-a.txt" && -f "$canon/file-b.txt" ]]; then
  ok "both files present in canonical checkout after concurrent merge (no lost update)"
else
  a_state="MISSING"; [[ -f "$canon/file-a.txt" ]] && a_state="present"
  b_state="MISSING"; [[ -f "$canon/file-b.txt" ]] && b_state="present"
  fail_msg "a file is missing after concurrent merge (lost update): file-a=$a_state file-b=$b_state"
fi

remote_file_a="$(git -C "$bare" show main:file-a.txt 2>/dev/null || echo MISSING)"
remote_file_b="$(git -C "$bare" show main:file-b.txt 2>/dev/null || echo MISSING)"
if [[ "$remote_file_a" == "a" && "$remote_file_b" == "b" ]]; then
  ok "both merges reached the remote"
else
  fail_msg "remote missing a merged file (remote_file_a=$remote_file_a remote_file_b=$remote_file_b)"
fi

if flock -n -x "$canon/.git-lock-push.lock" true 2>/dev/null; then
  ok "lock released after both merges completed"
else
  fail_msg "lock file still held after both merges completed"
fi

# ── Test 2: genuine same-path conflict — second merge fails loud, does NOT
#            silently drop the losing side (D5.2 no-lost-update-by-silence) ──
echo "Test 2: conflicting same-file edit aborts the 2nd merge (fail-loud, no silent drop)"

wtC="$tmpdir/wtC"
wtD="$tmpdir/wtD"
git -C "$canon" worktree add -q -b session-c "$wtC" main
git -C "$canon" worktree add -q -b session-d "$wtD" main

echo "session-c-version" > "$wtC/README"
git -C "$wtC" add README
git -C "$wtC" commit -q -m "session C: rewrite README"

echo "session-d-version" > "$wtD/README"
git -C "$wtD" add README
git -C "$wtD" commit -q -m "session D: rewrite README"

rcC=0
"$LOCK_PUSH" "$canon" --merge-branch session-c -m "merge session-c" >"$tmpdir/outC.log" 2>&1 || rcC=$?
if [[ "$rcC" -eq 0 ]]; then
  ok "first conflicting-file merge (session-c) lands cleanly"
else
  fail_msg "session-c merge unexpectedly failed: $(cat "$tmpdir/outC.log")"
fi

outD="$tmpdir/outD.log"
rcD=0
"$LOCK_PUSH" "$canon" --merge-branch session-d -m "merge session-d" >"$outD" 2>&1 || rcD=$?

if [[ "$rcD" -ne 0 ]]; then
  ok "conflicting session-d merge exits non-zero (fail-loud, not silently merged)"
else
  fail_msg "conflicting session-d merge exited 0 — should have failed loud on conflict"
fi

canon_readme="$(cat "$canon/README")"
if [[ "$canon_readme" == "session-c-version" ]]; then
  ok "canonical README retains session-c's content (session-d not silently applied/lost)"
else
  fail_msg "canonical README unexpectedly changed to: $canon_readme"
fi

if [[ -z "$(git -C "$canon" status --porcelain --untracked-files=no)" ]]; then
  ok "canonical checkout left clean after the aborted merge (no half-merged conflict markers)"
else
  fail_msg "canonical checkout left dirty after aborted merge: $(git -C "$canon" status --porcelain)"
fi

if git -C "$canon" show-ref --verify -q refs/heads/session-d; then
  ok "session-d branch preserved (untouched) for manual resolution"
else
  fail_msg "session-d branch was lost/deleted by the failed merge"
fi

# ── Test 3: --merge-branch without explicit --ff-only, remote-ahead — the
#            merge commit must SURVIVE (not rebase-flattened away) and no
#            force-push happens (Fable-review finding 4) ─────────────────────
echo "Test 3: --merge-branch (no explicit --ff-only) on remote-ahead does not rebase-flatten the merge"

# A third party pushes directly to the bare remote, advancing main WITHOUT
# canon's knowledge -- this is the "remote is ahead" divergence scenario.
third="$tmpdir/third"
git clone -q "$bare" "$third"
git -C "$third" config user.email "test@test"
git -C "$third" config user.name "Test"
echo "third-party-change" > "$third/third.txt"
git -C "$third" add third.txt
git -C "$third" commit -q -m "third party: advance main independently"
git -C "$third" push -q origin main

wtE="$tmpdir/wtE"
git -C "$canon" worktree add -q -b session-e "$wtE" main
echo "e" > "$wtE/file-e.txt"
git -C "$wtE" add file-e.txt
git -C "$wtE" commit -q -m "session E: add file-e"

# canon's local main is now BEHIND the remote (third party pushed ahead of it),
# and about to gain a --no-ff merge commit of session-e. Deliberately omit
# --ff-only to prove --merge-branch mode implies it.
before_head="$(git -C "$canon" rev-parse HEAD)"
outE="$tmpdir/outE.log"
rcE=0
"$LOCK_PUSH" "$canon" --merge-branch session-e -m "merge session-e" >"$outE" 2>&1 || rcE=$?

merge_commit="$(git -C "$canon" rev-parse HEAD)"
parent_count="$(git -C "$canon" log -1 --format=%P "$merge_commit" | wc -w)"
if [[ "$merge_commit" != "$before_head" && "$parent_count" -eq 2 ]]; then
  ok "the --no-ff merge commit exists locally with 2 parents (not flattened away)"
else
  fail_msg "merge commit missing or not a 2-parent merge (merge_commit=$merge_commit parents=$parent_count); log=$(git -C "$canon" log --oneline -5)"
fi

if git -C "$canon" show "$merge_commit:file-e.txt" >/dev/null 2>&1; then
  ok "session-e's file survives on canon's local main after the merge"
else
  fail_msg "session-e's file missing from canon's local main after the merge"
fi

remote_third="$(git -C "$bare" show main:third.txt 2>/dev/null || echo MISSING)"
if [[ "$remote_third" == "third-party-change" ]]; then
  ok "remote's third-party commit is untouched (no force-push clobbered it)"
else
  fail_msg "remote's third-party commit was overwritten/lost: $remote_third"
fi

remote_has_file_e="$(git -C "$bare" show main:file-e.txt 2>/dev/null || echo MISSING)"
if [[ "$remote_has_file_e" == "MISSING" ]]; then
  ok "session-e's merge was NOT pushed (remote diverged -> committed-locally-not-pushed, loud, per --ff-only fallback)"
else
  fail_msg "session-e's merge was pushed despite remote divergence: $remote_has_file_e"
fi

if [[ "$rcE" -eq 0 ]]; then
  ok "the divergence fallback exits 0 (non-fatal — work is committed locally)"
else
  fail_msg "unexpected non-zero exit on divergence fallback: rcE=$rcE; out=$(cat "$outE")"
fi

# ── Test 4: --merge-branch with no following value must error loudly, never
#            silently degrade to legacy mode ─────────────────────────────────
echo "Test 4: --merge-branch with no value errors loudly (not silent legacy-mode degrade)"

outF="$tmpdir/outF.log"
rcF=0
"$LOCK_PUSH" "$canon" --merge-branch >"$outF" 2>&1 || rcF=$?

if [[ "$rcF" -ne 0 ]]; then
  ok "--merge-branch with no value exits non-zero"
else
  fail_msg "--merge-branch with no value exited 0 (silently degraded to legacy mode)"
fi

if grep -qi "merge-branch" "$outF" && grep -qi "requires\|missing\|branch name" "$outF"; then
  ok "--merge-branch with no value prints an explanatory error"
else
  fail_msg "--merge-branch with no value did not print an explanatory error; out=$(cat "$outF")"
fi

echo ""
echo "Results: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
