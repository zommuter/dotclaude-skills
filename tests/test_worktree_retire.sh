#!/usr/bin/env bash
# roadmap:373e — force-free worktree/branch retirement.
# Covers worktree-retire.sh hermetically: clean+merged → delete; clean+unmerged → park;
# dirty (non-ignored untracked) → surface+leave (NO force, branch untouched); gitignored-only
# residue → removed cleanly; already-gone dir → prune; --expect-merged anomaly; single-target
# scope (a sibling worktree/branch is never touched). Never runs any --force / -D op.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SH="$SRC_DIR/relay/scripts/worktree-retire.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SH" ]] || fail "worktree-retire.sh not found/executable at $SH"

export WORKTREE_RETIRE_LOG=/dev/null

# ── Hermetic repo ──
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"
WTBASE="$TMP/wt"
git init -q "$REPO"
git -C "$REPO" config user.email t@t
git -C "$REPO" config user.name t
printf 'seed\n' > "$REPO/a.txt"
printf '*.pyc\nignoreme/\n' > "$REPO/.gitignore"
git -C "$REPO" add -A
git -C "$REPO" commit -qm init

mkwt() { # <name> — add a linked worktree on branch relay/<name> at current main tip
  git -C "$REPO" worktree add -q "$WTBASE/$1" -b "relay/$1"
}

# ── 1. clean worktree + merged branch → removed + branch -d, exit 0 ──
mkwt m1
out="$("$SH" "$REPO" "$WTBASE/m1" "relay/m1" --expect-merged)" ; rc=$?
[[ $rc -eq 0 ]] || fail "clean+merged: expected exit 0, got $rc"
[[ ! -e "$WTBASE/m1" ]] || fail "clean+merged: worktree dir should be gone"
git -C "$REPO" show-ref --verify --quiet refs/heads/relay/m1 && fail "clean+merged: branch relay/m1 should be deleted"
pass "clean + merged branch → worktree removed, branch deleted ($out)"

# ── 2. clean worktree + UNMERGED branch → parked as relay/orphan/<bn>, ref survives ──
mkwt u1
( cd "$WTBASE/u1" && printf 'work\n' > new.txt && git add -A && git commit -qm "unmerged work" )
out="$("$SH" "$REPO" "$WTBASE/u1" "relay/u1")" ; rc=$?
[[ $rc -eq 0 ]] || fail "clean+unmerged: expected exit 0 (parked), got $rc"
[[ ! -e "$WTBASE/u1" ]] || fail "clean+unmerged: worktree dir should be gone"
git -C "$REPO" show-ref --verify --quiet refs/heads/relay/orphan/u1 || fail "clean+unmerged: branch should be parked as relay/orphan/u1"
git -C "$REPO" show-ref --verify --quiet refs/heads/relay/u1 && fail "clean+unmerged: original relay/u1 should be renamed away"
pass "clean + unmerged branch → parked as relay/orphan/u1, ref kept ($out)"

# ── 3. DIRTY worktree (non-ignored untracked) → surface + leave, exit 3, NOTHING touched ──
mkwt d1
printf 'uncommitted real source\n' > "$WTBASE/d1/realsource.py"
set +e
out="$("$SH" "$REPO" "$WTBASE/d1" "relay/d1")" ; rc=$?
set -e
[[ $rc -eq 3 ]] || fail "dirty: expected exit 3 (surface+leave), got $rc"
[[ -e "$WTBASE/d1" ]] || fail "dirty: worktree dir must be LEFT on disk (not force-removed)"
[[ -f "$WTBASE/d1/realsource.py" ]] || fail "dirty: uncommitted file must be preserved"
git -C "$REPO" show-ref --verify --quiet refs/heads/relay/d1 || fail "dirty: branch relay/d1 must be untouched"
printf '%s' "$out" | grep -q "retire-deferred" || fail "dirty: output must surface a retire-deferred line"
pass "dirty worktree → surfaced + left on disk, branch untouched, exit 3 ($out)"

# ── 4. gitignored-only residue → removed cleanly (gitignore hygiene), exit 0 ──
mkwt g1
mkdir -p "$WTBASE/g1/ignoreme"; printf 'junk\n' > "$WTBASE/g1/ignoreme/x"; printf 'c\n' > "$WTBASE/g1/foo.pyc"
out="$("$SH" "$REPO" "$WTBASE/g1" "relay/g1" --expect-merged)" ; rc=$?
[[ $rc -eq 0 ]] || fail "gitignored residue: expected exit 0, got $rc"
[[ ! -e "$WTBASE/g1" ]] || fail "gitignored residue: worktree should be removed (ignored files don't block)"
pass "gitignored-only residue → removed cleanly ($out)"

# ── 5. worktree dir already gone → prune path, exit 0 ──
mkwt p1
rm -rf "$WTBASE/p1"          # simulate a crash that left only the admin ref
out="$("$SH" "$REPO" "$WTBASE/p1" "relay/p1" --expect-merged)" ; rc=$?
[[ $rc -eq 0 ]] || fail "already-gone: expected exit 0 (prune+branch), got $rc"
git -C "$REPO" show-ref --verify --quiet refs/heads/relay/p1 && fail "already-gone: merged branch should be deleted after prune"
pass "already-deleted worktree dir → prune + branch handled ($out)"

# ── 6. --expect-merged but branch UNMERGED → loud anomaly, exit 4, no silent park ──
mkwt a1
( cd "$WTBASE/a1" && printf 'x\n' > z.txt && git add -A && git commit -qm ahead )
set +e
out="$("$SH" "$REPO" "$WTBASE/a1" "relay/a1" --expect-merged)" ; rc=$?
set -e
[[ $rc -eq 4 ]] || fail "expect-merged anomaly: expected exit 4, got $rc"
git -C "$REPO" show-ref --verify --quiet refs/heads/relay/orphan/a1 && fail "expect-merged anomaly: must NOT silently park"
git -C "$REPO" show-ref --verify --quiet refs/heads/relay/a1 || fail "expect-merged anomaly: branch must be kept as relay/a1"
printf '%s' "$out" | grep -q "retire-anomaly" || fail "expect-merged anomaly: must surface a retire-anomaly line"
pass "--expect-merged + unmerged → loud anomaly, branch kept, exit 4 ($out)"

# ── 7. scope: retiring one worktree never touches a sibling ──
mkwt s1
mkwt s2
"$SH" "$REPO" "$WTBASE/s1" "relay/s1" --expect-merged >/dev/null
[[ -e "$WTBASE/s2" ]] || fail "scope: sibling worktree s2 must be untouched"
git -C "$REPO" show-ref --verify --quiet refs/heads/relay/s2 || fail "scope: sibling branch relay/s2 must be untouched"
pass "single-target scope: sibling worktree+branch untouched"

# ── 8. never invokes a forbidden force op (static check of executable lines only) ──
# Strip comments, log(), echo, and msg= assignments — those legitimately mention the verbs
# in prose/surfaced text ("do NOT -D", "commit real work"). What remains is actual command
# invocations; none may carry a force/destructive git verb.
code="$(grep -vE '^[[:space:]]*#' "$SH" | grep -vE '(^[[:space:]]*(log|echo)\b|[[:space:]]*msg=)')"
printf '%s\n' "$code" | grep -Eq -- '--force|branch[[:space:]]+-D\b|reset[[:space:]]+--hard|git[[:space:]]+(-C[[:space:]]+[^ ]+[[:space:]]+)?clean|git[[:space:]]+(-C[[:space:]]+[^ ]+[[:space:]]+)?stash' \
  && fail "helper executes a forbidden force/destructive git verb"
pass "helper executes no forbidden force/destructive git verb"

echo "ALL PASS"
