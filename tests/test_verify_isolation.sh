#!/usr/bin/env bash
# roadmap:f682 — Relay pre-integrate isolation gate (relay/scripts/verify-isolation.sh).
#
# Observed 2026-07-14 (loderite R2 consumer handoff): a spawned child created its worktree
# correctly but wrote every edit to the target's MAIN checkout, so its worktree stayed EMPTY
# (0 commits beyond base) — a no-op "commit in worktree" whose self-report was wrong. This
# gate lets the integrator (invariant 5) detect that BEFORE merging an empty branch.
#
# Contract (mirrors clean-tree-gate.sh: observe-only, fail-safe, exit 0 = safe / exit 2 = fail):
#   verify-isolation.sh <worktree> [--base <ref>]   (default --base origin/main → default branch)
#   (a) worktree has ≥1 commit beyond base AND clean tree  → print ok, exit 0.
#   (b) EMPTY worktree (no commits beyond base)            → exit 2, names isolation failure.
#   (c) worktree has commits beyond base but a DIRTY tree  → exit 2.
#   (d) non-existent / non-git path                        → exit 2 (stderr message).
#   The script must NEVER mutate (no stash / reset / checkout -- / clean).
#
# Hermetic: mktemp only, no ~/.claude, no network.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/relay/scripts/verify-isolation.sh"

pass() { printf 'PASS: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*"; exit 1; }

[[ -x "$SCRIPT" ]] || fail "verify-isolation.sh not found/executable at $SCRIPT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# ── Helper: a base repo with one commit on 'main', plus a worktree branched off it ──
# Sets globals: REPO (main checkout), WT (worktree path). base ref for the gate = main.
make_repo_and_worktree() {
    local name="$1"
    REPO="$tmp/$name"
    WT="$tmp/$name-wt"
    mkdir -p "$REPO"
    git -C "$REPO" init -q -b main
    git -C "$REPO" config user.email t@example.com
    git -C "$REPO" config user.name tester
    printf 'seed\n' > "$REPO/file.txt"
    git -C "$REPO" add file.txt
    git -C "$REPO" commit -qm 'seed'
    git -C "$REPO" worktree add -q -b "$name-child" "$WT" main
}

# ─────────────────────────────────────────────────
# (a) worktree with a commit beyond base + clean tree → exit 0
# ─────────────────────────────────────────────────
make_repo_and_worktree a
printf 'work\n' > "$WT/new.txt"
git -C "$WT" add new.txt
git -C "$WT" commit -qm 'child work'
if out="$("$SCRIPT" "$WT" --base main 2>&1)"; then
    pass "(a) non-empty clean worktree → exit 0 ($out)"
else
    fail "(a) non-empty clean worktree should exit 0, got non-zero: $out"
fi

# ─────────────────────────────────────────────────
# (b) EMPTY worktree (no commits beyond base) → exit 2, names the isolation failure
# ─────────────────────────────────────────────────
make_repo_and_worktree b
if out="$("$SCRIPT" "$WT" --base main 2>&1)"; then
    fail "(b) empty worktree should exit 2, but exited 0: $out"
else
    rc=$?
    [[ "$rc" -eq 2 ]] || fail "(b) empty worktree should exit 2, got $rc: $out"
    grep -qiE 'empty|isolation|no commit' <<<"$out" \
        || fail "(b) exit-2 output should name the empty/isolation failure, got: $out"
    pass "(b) empty worktree → exit 2 + named failure"
fi

# ─────────────────────────────────────────────────
# (c) worktree has a commit beyond base but a DIRTY tree → exit 2
# ─────────────────────────────────────────────────
make_repo_and_worktree c
printf 'work\n' > "$WT/new.txt"
git -C "$WT" add new.txt
git -C "$WT" commit -qm 'child work'
printf 'uncommitted\n' > "$WT/dirty.txt"   # untracked → dirty
if "$SCRIPT" "$WT" --base main >/dev/null 2>&1; then
    fail "(c) dirty worktree should exit 2, but exited 0"
else
    rc=$?
    [[ "$rc" -eq 2 ]] || fail "(c) dirty worktree should exit 2, got $rc"
    pass "(c) dirty worktree → exit 2"
fi

# ─────────────────────────────────────────────────
# (d) non-existent / non-git path → exit 2
# ─────────────────────────────────────────────────
if "$SCRIPT" "$tmp/does-not-exist" --base main >/dev/null 2>&1; then
    fail "(d) missing path should exit 2, but exited 0"
else
    rc=$?
    [[ "$rc" -eq 2 ]] || fail "(d) missing path should exit 2, got $rc"
    pass "(d) missing/non-git path → exit 2"
fi

# ─────────────────────────────────────────────────
# (e) observe-only: the script source must never mutate the tree
# ─────────────────────────────────────────────────
if grep -Eq 'git[^\n]*(stash|reset --hard|checkout --|clean -)' "$SCRIPT"; then
    fail "(e) verify-isolation.sh must be observe-only (found a mutating git verb)"
fi
pass "(e) script is observe-only (no stash/reset/checkout--/clean)"

pass "verify-isolation.sh: isolation gate (f682)"
