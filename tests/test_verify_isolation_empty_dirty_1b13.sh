#!/usr/bin/env bash
# roadmap:1b13 — verify-isolation.sh: an EMPTY worktree with a DIRTY tree must FAIL (exit 2).
#
# OWNER-DECIDED 2026-08-14 (`/relay human .`), re-laned [INPUT — decision] -> [ROUTINE].
# Defect (confirmed against the script's own header behaviour table, review 2026-08-14):
# branches (b1) "empty + main UNMOVED" and (b3) "empty + main advanced only by merge
# commit(s)" both `exit 0` on the "no commits beyond base" test BEFORE the (c) dirty-tree
# check ever runs. So a worktree that holds UNCOMMITTED edits but zero commits is waved
# through as a legitimate id:8e3e no-op review — the closest signature to "the child worked
# but never committed", the same family as the loderite/jobAI main-checkout breach the gate
# exists for. The owner ruled that shape is breach-shaped and must exit 2; a re-dispatch on a
# false positive is the accepted cost (consistent with the conservative direction the header
# already accepts for (b2)).
#
# Acceptance (this spec is the contract — do NOT weaken it):
#   (i)  empty worktree + DIRTY tree ⇒ exit 2 NAMING the dirty entries, under BOTH the
#        main-UNMOVED (b1) and merge-commits-only (b3) conditions.
#   (ii) empty + CLEAN + main unmoved still exits 0 — the legitimate id:8e3e no-op review
#        must NOT regress (negative control).
#   (iii) the existing (a)/(b2)/(c)/(d) cases stay green — covered by
#        tests/test_verify_isolation.sh (run the whole suite after ticking).
#   The script must stay observe-only: NO stash / reset --hard / checkout -- / clean added.
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

# ── Helper: base repo with one commit on 'main' + a worktree branched off it (empty). ──
# Sets globals REPO (main checkout) and WT (worktree). base ref for the gate = main.
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
# (i-b1) EMPTY worktree + DIRTY tree + main UNMOVED → must exit 2, naming the dirty entry.
#        Today this exits 0 ("legitimate no-op review (id:8e3e)") because the empty-branch
#        arm returns before the dirty check — that is the defect this item fixes.
# ─────────────────────────────────────────────────
make_repo_and_worktree i1
printf 'uncommitted work never committed\n' > "$WT/dirty.txt"   # untracked → dirty, 0 commits
if out="$("$SCRIPT" "$WT" --base main 2>&1)"; then
    fail "(i-b1) empty worktree + dirty tree + main unmoved should exit 2, but exited 0: $out"
else
    rc=$?
    [[ "$rc" -eq 2 ]] || fail "(i-b1) empty+dirty+main-unmoved should exit 2, got $rc: $out"
    grep -qiE 'dirty|uncommitted|isolation' <<<"$out" \
        || fail "(i-b1) exit-2 output should name the dirty/isolation failure, got: $out"
    grep -q 'dirty.txt' <<<"$out" \
        || fail "(i-b1) exit-2 output should name the dirty entry (dirty.txt), got: $out"
    pass "(i-b1) empty worktree + dirty tree + main unmoved → exit 2 + named dirty entry"
fi

# ─────────────────────────────────────────────────
# (i-b3) EMPTY worktree + DIRTY tree + main advanced ONLY by a MERGE commit since dispatch
#        → must exit 2 (dirty), naming the dirty entry. Today the merge-only arm exits 0
#        ("not this child's breach") before the dirty check runs — same defect.
# ─────────────────────────────────────────────────
make_repo_and_worktree i3
# Advance main by a --no-ff MERGE commit (another unit's integration), AFTER dispatch.
git -C "$REPO" checkout -q -b sidebranch main
printf 'side\n' > "$REPO/side.txt"
git -C "$REPO" add side.txt
git -C "$REPO" commit -qm 'side work'
git -C "$REPO" checkout -q main
git -C "$REPO" merge -q --no-ff -m 'integrate: another unit (merge commit)' sidebranch
# Sanity: the tip of main is a merge commit (2 parents).
[[ "$(git -C "$REPO" rev-list --parents -n1 HEAD | wc -w)" -eq 3 ]] \
    || fail "(i-b3) setup: expected main tip to be a merge commit"
# Now dirty the still-empty worktree.
printf 'uncommitted work never committed\n' > "$WT/dirty.txt"
if out="$("$SCRIPT" "$WT" --base main 2>&1)"; then
    fail "(i-b3) empty worktree + dirty tree + merge-only main advance should exit 2, but exited 0: $out"
else
    rc=$?
    [[ "$rc" -eq 2 ]] || fail "(i-b3) empty+dirty+merge-only should exit 2, got $rc: $out"
    grep -qiE 'dirty|uncommitted|isolation' <<<"$out" \
        || fail "(i-b3) exit-2 output should name the dirty/isolation failure, got: $out"
    grep -q 'dirty.txt' <<<"$out" \
        || fail "(i-b3) exit-2 output should name the dirty entry (dirty.txt), got: $out"
    pass "(i-b3) empty worktree + dirty tree + merge-only main advance → exit 2 + named dirty entry"
fi

# ─────────────────────────────────────────────────
# (ii) NEGATIVE CONTROL — empty + CLEAN + main unmoved must STILL exit 0 (id:8e3e no-op
#      review must not regress). Passes today AND must keep passing after the fix.
# ─────────────────────────────────────────────────
make_repo_and_worktree ii
if out="$("$SCRIPT" "$WT" --base main 2>&1)"; then
    grep -qiE 'no-op|8e3e|no commits' <<<"$out" \
        || fail "(ii) empty+clean+main-unmoved exited 0 but did not name the legitimate no-op review, got: $out"
    pass "(ii) empty + clean + main unmoved → exit 0 (id:8e3e no-op review preserved)"
else
    rc=$?
    fail "(ii) empty+clean+main-unmoved must exit 0 (no regression of id:8e3e), got $rc: $out"
fi

# ─────────────────────────────────────────────────
# (obs) observe-only: the script source must never gain a mutating git verb.
# ─────────────────────────────────────────────────
if grep -Eq 'git[^\n]*(stash|reset --hard|checkout --|clean -)' "$SCRIPT"; then
    fail "(obs) verify-isolation.sh must stay observe-only (found a mutating git verb)"
fi
pass "(obs) script stays observe-only (no stash/reset/checkout--/clean)"

pass "verify-isolation.sh empty+dirty gate (id:1b13)"
