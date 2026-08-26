#!/usr/bin/env bash
# test_base_ref_resolution_758a.sh — defect-fix test for TODO id:758a (no roadmap item;
# this is a TODO-tracked bug fix, not a ROADMAP-tracked feature, so failures always count).
#
# Invariant under test (owner ruling 2026-08-26, quoted): "clearly always the actually
# checked-out branch must be used, never a hard-coded 'use main, try master'". Covers both
# relay/scripts/stranded-branch-scan.sh and relay/scripts/verify-isolation.sh, which both
# used to resolve their default base as origin/main -> main(/master-adjacent hard guess),
# and both now derive it from `git symbolic-ref --short HEAD` (falling back to origin/HEAD
# only when HEAD is detached/unborn) — see id:8739 (integrate.sh:455-465) for the reference
# fail-closed posture this mirrors.
#
# Fixture shape mirrors the real git-annex failure (run relay-20260826-122101-7415): a repo
# whose only branch is NOT named main or master — here 'annex-dotgit' — so pre-fix code
# (origin/main -> main) has nothing to resolve to and must hard-fail.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SBS="$ROOT/relay/scripts/stranded-branch-scan.sh"
VISO="$ROOT/relay/scripts/verify-isolation.sh"

pass() { printf 'PASS: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*"; exit 1; }

[[ -x "$SBS" ]] || fail "stranded-branch-scan.sh not found/executable at $SBS"
[[ -x "$VISO" ]] || fail "verify-isolation.sh not found/executable at $VISO"

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

# ── Fixture: a repo whose ONLY branch is 'annex-dotgit' — no main, no master anywhere,
#    reproducing the git-annex shape (master exists there too, but points at a stale
#    mirror; the minimal reproduction just needs "no main"). ──
REPO="$tmp/annexlike"
mkdir -p "$REPO"
git -C "$REPO" init -q -b annex-dotgit
git -C "$REPO" config user.email t@example.com
git -C "$REPO" config user.name tester
printf 'seed\n' > "$REPO/file.txt"
git -C "$REPO" add file.txt
git -C "$REPO" commit -qm 'seed'

# ─────────────────────────────────────────────────────────────────────────────
# NEGATIVE CONTROL: reproduce the PRE-FIX resolution order inline (origin/main -> hard
# 'main', matching stranded-branch-scan.sh's old lines 69-79) and confirm it fails, and
# fails for the RIGHT reason (base ref 'main' does not resolve), against this fixture.
# This proves the fixture actually exercises the bug rather than passing vacuously.
# ─────────────────────────────────────────────────────────────────────────────
old_resolve() {
  local repo="$1" base=""
  if git -C "$repo" rev-parse --verify -q origin/main >/dev/null 2>&1; then
    base="origin/main"
  else
    base="main"
  fi
  if ! git -C "$repo" rev-parse --verify -q "$base" >/dev/null 2>&1; then
    echo "base ref '$base' does not resolve in '$repo'" >&2
    return 2
  fi
  printf '%s\n' "$base"
}

if old_out="$(old_resolve "$REPO" 2>&1)"; then
  fail "negative control: pre-fix origin/main->main resolution should have FAILED on a repo with no main/master branch, but it produced base='$old_out'"
else
  old_rc=$?
  [[ "$old_rc" -eq 2 ]] || fail "negative control: pre-fix logic should exit 2, got $old_rc: $old_out"
  grep -q "base ref 'main' does not resolve" <<<"$old_out" \
    || fail "negative control: expected 'main does not resolve' failure text, got: $old_out"
  pass "negative control: pre-fix origin/main->main resolution correctly FAILS on annex-dotgit-only repo ($old_out)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# stranded-branch-scan.sh: with no --base, must derive 'annex-dotgit' from HEAD and
# succeed (exit 0, no matches — nothing has been created off it yet).
# ─────────────────────────────────────────────────────────────────────────────
if out="$("$SBS" "$REPO" --verdict review --item zzzz 2>&1)"; then
  [[ -z "$out" ]] || fail "stranded-branch-scan.sh: expected no matches on a fresh repo, got: $out"
  pass "stranded-branch-scan.sh: derives checked-out branch 'annex-dotgit' as base (no --base), exits 0"
else
  rc=$?
  fail "stranded-branch-scan.sh: should exit 0 deriving base from HEAD on annex-dotgit-only repo, got rc=$rc: $out"
fi

# Sanity: a relay branch off annex-dotgit with real commits IS detected once base is
# correctly derived as 'annex-dotgit' (proves the derivation is actually being used, not
# just tolerated).
git -C "$REPO" worktree add -q -b "relay/r1-review-zzzz-0" "$tmp/wt-stranded" annex-dotgit
printf 'work\n' > "$tmp/wt-stranded/new.txt"
git -C "$tmp/wt-stranded" add new.txt
git -C "$tmp/wt-stranded" commit -qm 'child work' >/dev/null
if out="$("$SBS" "$REPO" --verdict review --item zzzz 2>&1)"; then
  grep -q "relay/r1-review-zzzz-0" <<<"$out" \
    || fail "stranded-branch-scan.sh: expected to detect the stranded branch with base=annex-dotgit, got: $out"
  pass "stranded-branch-scan.sh: correctly detects a stranded branch measured against the derived base ($out)"
else
  fail "stranded-branch-scan.sh: unexpected non-zero exit detecting the stranded branch"
fi

# ─────────────────────────────────────────────────────────────────────────────
# verify-isolation.sh: a worktree branched off 'annex-dotgit' (no --base) must resolve
# base='annex-dotgit' from the worktree's own HEAD and correctly report the child's
# commit as "beyond base" — never a hard exit-2 "does not resolve" failure.
# ─────────────────────────────────────────────────────────────────────────────
WT="$tmp/annexlike-wt"
git -C "$REPO" worktree add -q -b "annexlike-child" "$WT" annex-dotgit
printf 'work\n' > "$WT/childwork.txt"
git -C "$WT" add childwork.txt
git -C "$WT" commit -qm 'child work'
if out="$("$VISO" "$WT" 2>&1)"; then
  pass "verify-isolation.sh: derives checked-out branch 'annex-dotgit' as base (no --base), exits 0 ($out)"
else
  rc=$?
  fail "verify-isolation.sh: should exit 0 deriving base from HEAD on annex-dotgit-only repo, got rc=$rc: $out"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Both scripts: no line may ASSIGN 'master' as a ref value (guard against the guess-list
# regression this item explicitly rejects). Comments and error-message text are allowed to
# mention 'master' (they do, to explain WHY it's rejected and to name it in a refusal
# message) — only a literal ref assignment (base="master" or similar) matters.
# ─────────────────────────────────────────────────────────────────────────────
for f in "$SBS" "$VISO"; do
  if grep -Eq '(base|default_branch)="master"|:-"?master"?[ }]' "$f"; then
    fail "$(basename "$f"): found a literal 'master' ref assignment — must not contain a 'master' guess-list fallback (id:758a)"
  fi
done
pass "neither script assigns 'master' as a fallback ref"

pass "base-ref resolution: checked-out-branch invariant (id:758a)"
