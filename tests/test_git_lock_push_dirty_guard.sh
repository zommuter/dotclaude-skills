#!/usr/bin/env bash
# roadmap:dff8 — git-lock-push.sh id:aa93 dirty-guard must tolerate UNTRACKED-ONLY
# churn (proceed with the autostash-rebase + push) and keep refusing on TRACKED
# modifications — and its refusal message must state facts, not the "(a concurrent
# edit?)" causal guess.
#
# WHY (TODO id:dff8, recurring on ~/.claude): the guard refuses on ANY porcelain
# output, but `--autostash` only stashes TRACKED changes — untracked paths carry no
# stash-reapply data-loss risk (a rebase that would overwrite an untracked file
# aborts loudly on its own). ~/.claude's untracked runtime churn (plans/,
# session-env/, sessions/, tasks/) therefore blocks every push for no safety gain.
#
# RED until the fix lands. Hermetic: local bare remote, mktemp, no network
# (idiom: test_git_lock_push_ff_only.sh).

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
work="$tmpdir/work"
git init --bare -q "$bare"
git init -q "$work"
git -C "$work" config user.email "test@test"
git -C "$work" config user.name "Test"
git -C "$work" remote add origin "$bare"

echo "init" > "$work/README"
git -C "$work" add README
git -C "$work" commit -q -m "init"
git -C "$work" push -q --set-upstream origin main >/dev/null 2>&1

# ── Test 1: untracked-only churn → push proceeds (legacy mode) ────────────────
echo "Test 1: untracked-only runtime churn does not block the push"
echo "change1" > "$work/file1"
git -C "$work" add file1
git -C "$work" commit -q -m "committed work"
local_sha="$(git -C "$work" rev-parse HEAD)"
# Simulate ~/.claude-style runtime churn: untracked files/dirs only
mkdir -p "$work/sessions" "$work/plans"
echo "runtime" > "$work/sessions/s1.jsonl"
echo "runtime" > "$work/plans/p1.md"
echo "stray" > "$work/untracked.tmp"

"$LOCK_PUSH" "$work" >/dev/null 2>&1 || true

remote_sha="$(git -C "$bare" rev-parse main 2>/dev/null || echo none)"
if [[ "$remote_sha" == "$local_sha" ]]; then
  ok "untracked-only tree: commit reached the remote"
else
  fail_msg "untracked-only tree: push was blocked (remote=$remote_sha local=$local_sha)"
fi
# The churn must survive untouched (never stashed/deleted)
if [[ -f "$work/sessions/s1.jsonl" && -f "$work/untracked.tmp" ]]; then
  ok "untracked churn left in place"
else
  fail_msg "untracked churn disappeared (stash/cleanup touched it)"
fi

# ── Test 2: tracked modification → still refuses (data-loss guard kept) ──────
echo "Test 2: tracked modification still refuses the autostash-rebase"
echo "change2" > "$work/file2"
git -C "$work" add file2
git -C "$work" commit -q -m "more committed work"
local_sha2="$(git -C "$work" rev-parse HEAD)"
echo "UNCOMMITTED tracked edit" >> "$work/README"   # tracked, dirty

out2="$("$LOCK_PUSH" "$work" 2>&1 || true)"

remote_sha2="$(git -C "$bare" rev-parse main 2>/dev/null || echo none)"
if [[ "$remote_sha2" != "$local_sha2" ]]; then
  ok "tracked-dirty tree: push refused (remote did not advance)"
else
  fail_msg "tracked-dirty tree: push went through despite tracked modification"
fi
if git -C "$work" diff --quiet -- README; then
  fail_msg "tracked edit was consumed (stash/reset lost it)"
else
  ok "tracked edit preserved in the working tree"
fi

# ── Test 3: refusal message states facts, no causal guess ─────────────────────
echo "Test 3: refusal wording drops the 'concurrent edit' guess"
if echo "$out2" | grep -qi "concurrent edit"; then
  fail_msg "refusal still asserts the unverified 'concurrent edit' cause: $(echo "$out2" | grep -i 'concurrent edit' | head -1)"
else
  ok "no 'concurrent edit' causal guess in the refusal"
fi
if echo "$out2" | grep -q "aa93"; then
  ok "refusal still cites the id:aa93 guard"
else
  fail_msg "refusal no longer cites id:aa93 (traceability lost); output: $out2"
fi

echo ""
echo "Results: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
