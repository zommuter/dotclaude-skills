#!/usr/bin/env bash
# roadmap:76d2 — provisioned artifact symlinks must not dirty the worktree.
#
# RED SPEC authored at handoff 2026-08-12. provision-worktree.sh:29-30 creates .venv /
# node_modules as SYMLINKS. The idiomatic gitignore form is the trailing-slash DIRECTORY
# pattern (`.venv/`), and git does NOT match a symlink against it. So the provisioned symlink
# shows as `?? .venv`, verify-isolation.sh (id:f682) correctly refuses the merge, and the
# child's work parks unmerged.
#
# Live loss in run relay-20260812-001727-5554: linguistic-universals branch
# relay/relay-20260812-001727-5554-execute-4d35-0 holds 2 real commits (id:4d35 construct_class
# + ValidityAnchor schema) that never reached main. The executor did nothing wrong — contract
# rule 5b told it to gitignore throwaway and the repo already had (`.gitignore:7` = `.venv/`).
#
# FIX SHAPE (pinned deliberately): the provisioner writes the names it creates into the
# WORKTREE'S OWN `.git/info/exclude` — per-worktree, local, never committed, no repo's
# .gitignore touched. The isolation gate must NOT be given a name-based carve-out: its value is
# that it special-cases nothing, and a carve-out would also hide a genuine breach.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SH="$SRC_DIR/relay/scripts/provision-worktree.sh"
GATE="$SRC_DIR/relay/scripts/verify-isolation.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SH" ]] || fail "provision-worktree.sh not found/executable at $SH"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"
mkdir -p "$REPO"
git init -q "$REPO"

# The exact real-world shape: a trailing-slash DIRECTORY pattern, which is the idiomatic form.
printf '.venv/\nnode_modules/\n' > "$REPO/.gitignore"
mkdir -p "$REPO/.venv" "$REPO/node_modules"
: > "$REPO/.venv/pyvenv.cfg"
: > "$REPO/node_modules/.package-lock.json"
git -C "$REPO" add .gitignore
git -C "$REPO" -c user.email=t@e.invalid -c user.name=t commit -q -m init

WT="$TMP/wt"
"$SH" "$REPO" "$WT" relay/test-76d2 >/dev/null 2>&1 || fail "provision-worktree.sh failed on a clean provision"

# Sanity: the symlinks were actually created (else this test proves nothing).
[[ -L "$WT/.venv" ]] || fail "no .venv symlink was created — fixture does not reproduce the case"
[[ -L "$WT/node_modules" ]] || fail "no node_modules symlink was created — fixture does not reproduce the case"
pass "the provisioner created both artifact symlinks"

# ── THE RED ASSERTION ─────────────────────────────────────────────────────────────────────
status="$(git -C "$WT" status --porcelain)"
[[ -z "$status" ]] \
  || fail "the provisioned worktree is DIRTY straight after provisioning — verify-isolation.sh will refuse the merge and the child's work will park unmerged. git status --porcelain:
$(sed 's/^/    /' <<<"$status")"
pass "a freshly provisioned worktree is CLEAN (the symlinks are ignored)"

# The isolation gate itself must now pass on it — that is the property that was lost.
if [[ -x "$GATE" ]]; then
  "$GATE" "$WT" >/dev/null 2>&1 \
    || fail "verify-isolation.sh still refuses a freshly provisioned worktree"
  pass "verify-isolation.sh accepts a freshly provisioned worktree"
fi

# ── the gate must NOT have been weakened: a genuine dirty edit still fails ────────────────
echo "real uncommitted source change" > "$WT/somefile.py"
if [[ -x "$GATE" ]]; then
  if "$GATE" "$WT" >/dev/null 2>&1; then
    fail "verify-isolation.sh now PASSES a genuinely dirty worktree — the gate was weakened instead of the provisioner fixed"
  fi
  pass "a genuinely dirty worktree is still refused (gate not weakened)"
fi
rm -- "$WT/somefile.py"

# ── the fix must be per-worktree and NOT touch the repo's committed .gitignore ────────────
git -C "$REPO" diff --quiet -- .gitignore \
  || fail "the repo's .gitignore was modified — the fix must be worktree-local (.git/info/exclude), not a commit to the repo"
[[ -z "$(git -C "$REPO" status --porcelain)" ]] \
  || fail "provisioning dirtied the MAIN checkout — it must only ever touch the worktree"
pass "the repo's committed .gitignore and main checkout are untouched"

# ── a repo with NO such artifacts is still a clean no-op (the deliberate best-effort path) ─
REPO2="$TMP/repo2"; mkdir -p "$REPO2"; git init -q "$REPO2"
git -C "$REPO2" -c user.email=t@e.invalid -c user.name=t commit -q --allow-empty -m init
WT2="$TMP/wt2"
"$SH" "$REPO2" "$WT2" relay/test-76d2-b >/dev/null 2>&1 \
  || fail "provisioning a repo with no node_modules/.venv now FAILS — the best-effort no-op path regressed"
[[ -z "$(git -C "$WT2" status --porcelain)" ]] || fail "a repo with no artifacts produced a dirty worktree"
pass "a repo with neither artifact class is still a clean no-op"

echo "ALL PASS: provisioned symlinks no longer dirty the worktree (76d2)"
