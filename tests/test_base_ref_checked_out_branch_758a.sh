#!/usr/bin/env bash
# roadmap:758a — Base-ref resolution must use the repo's ACTUAL checked-out branch,
# never a hard-coded `origin/main` → `main` → `master` guess (owner ruling 2026-08-26).
#
# FIRED LIVE in run relay-20260826-122101-7415: `integrate:git-annex` failed with
#   MECH-ERROR exit=2 — stranded-branch-scan.sh: base ref 'main' does not resolve
# on a repo whose real working branch is `annex-dotgit` (its `master` is a stale upstream
# mirror and there is no `origin/HEAD`). A `master` fallback would NOT have fixed it: it
# resolves, but to the WRONG base — a silent wrong answer in place of a loud failure. That
# is why the ruling is checked-out-branch, not an extended guess-list.
#
# This is PROPAGATION of an already-ratified decision (id:8739, `integrate.sh:455-465`:
# use the canonical checkout's current HEAD, "no branch-name guess, no remote round-trip",
# and REFUSE to fall back), to the two remaining offenders:
#   (1) relay/scripts/stranded-branch-scan.sh:68-74 — origin/main → hard-coded "main" → exit 2
#   (2) relay/scripts/verify-isolation.sh:78-91     — origin/main → origin/HEAD → hard-coded "main"
#
# Contract this spec pins:
#   (a) stranded-branch-scan.sh with NO --base, on a repo checked out on a branch that is
#       neither `main` nor `master`, resolves the base from HEAD and RUNS (does not exit 2).
#   (b) verify-isolation.sh with NO --base, same shape, resolves from the worktree's base
#       branch and does not die on the hard-coded "main".
#   (c) FAIL-CLOSED is preserved (id:8739 posture): when the base genuinely cannot be
#       determined (detached HEAD, no resolvable ref), the script still exits 2 LOUDLY —
#       it must never silently pick a plausible-looking ref such as `master`.
#   (d) Neither script contains a bare hard-coded "main"/"master" fallback assignment any
#       more (grep-level guard against the guess-list creeping back).
#
# Hermetic: mktemp only, no ~/.claude, no network.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCAN="$ROOT/relay/scripts/stranded-branch-scan.sh"
ISO="$ROOT/relay/scripts/verify-isolation.sh"

pass() { printf 'PASS: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*"; exit 1; }

[[ -x "$SCAN" ]] || fail "stranded-branch-scan.sh not found/executable at $SCAN"
[[ -x "$ISO" ]] || fail "verify-isolation.sh not found/executable at $ISO"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# ── Fixture: the git-annex shape — real work on a branch that is NOT main/master, a STALE
#    `master` mirror that resolves but is the wrong base, and NO origin/HEAD. ──
make_annex_shaped_repo() {
    local name="$1"
    REPO="$tmp/$name"
    mkdir -p "$REPO"
    git -C "$REPO" init -q -b master
    git -C "$REPO" config user.email t@example.com
    git -C "$REPO" config user.name tester
    printf 'stale upstream mirror\n' > "$REPO/upstream.txt"
    git -C "$REPO" add upstream.txt
    git -C "$REPO" commit -qm 'stale master mirror'
    git -C "$REPO" checkout -q -b annex-dotgit
    printf 'real work\n' > "$REPO/work.txt"
    git -C "$REPO" add work.txt
    git -C "$REPO" commit -qm 'real work on the actual checked-out branch'
}

# ─────────────────────────────────────────────────
# (a) stranded-branch-scan.sh, no --base, HEAD on `annex-dotgit` → must NOT exit 2 with
#     "base ref 'main' does not resolve". This is the exact live failure.
# ─────────────────────────────────────────────────
make_annex_shaped_repo a
set +e
out="$("$SCAN" "$REPO" --verdict execute --item abcd 2>&1)"
rc=$?
set -e
if [[ "$rc" -eq 2 ]] && grep -qiE "base ref '?(main|master)'? does not resolve" <<<"$out"; then
    fail "(a) stranded-branch-scan.sh still guesses a hard-coded base on a non-main repo: $out"
fi
grep -qiE "base ref '?main'?" <<<"$out" \
    && fail "(a) stranded-branch-scan.sh still names 'main' as the base on a repo checked out on annex-dotgit: $out"
pass "(a) stranded-branch-scan.sh resolves the base from the checked-out branch (rc=$rc)"

# ─────────────────────────────────────────────────
# (b) verify-isolation.sh, no --base, on a worktree of the same repo → must not die on the
#     hard-coded "main". The gate's own verdict (0/2) is not what is pinned here; what is
#     pinned is that it never reports a base-ref-does-not-resolve failure for `main`.
# ─────────────────────────────────────────────────
make_annex_shaped_repo b
WT="$tmp/b-wt"
git -C "$REPO" worktree add -q -b b-child "$WT" annex-dotgit
printf 'child work\n' > "$WT/child.txt"
git -C "$WT" add child.txt
git -C "$WT" commit -qm 'child work'
set +e
out="$("$ISO" "$WT" 2>&1)"
rc=$?
set -e
grep -qiE "base ref '?main'? does not resolve" <<<"$out" \
    && fail "(b) verify-isolation.sh still falls back to the hard-coded 'main': $out"
pass "(b) verify-isolation.sh resolves the base without the hard-coded 'main' (rc=$rc)"

# ─────────────────────────────────────────────────
# (c) FAIL-CLOSED preserved (id:8739 posture): a DETACHED HEAD has no checked-out branch
#     name, so the base is undeterminable — the script must exit 2 LOUDLY and must NOT
#     silently fall back to the stale `master` that happens to resolve.
# ─────────────────────────────────────────────────
make_annex_shaped_repo c
git -C "$REPO" checkout -q --detach
set +e
out="$("$SCAN" "$REPO" --verdict execute --item abcd 2>&1)"
rc=$?
set -e
[[ "$rc" -eq 2 ]] || fail "(c) detached HEAD must fail CLOSED with exit 2, got rc=$rc: $out"
grep -qiE 'base|detached|HEAD' <<<"$out" \
    || fail "(c) the exit-2 message must name the undeterminable base, got: $out"
grep -qiE "base ref '?master'? " <<<"$out" \
    && fail "(c) detached HEAD silently fell back to the stale 'master' mirror: $out"
pass "(c) undeterminable base fails CLOSED and never guesses 'master'"

# ─────────────────────────────────────────────────
# (d) Grep-level guard: no bare hard-coded main/master base assignment survives in either
#     script (the guess-list must not creep back in a later edit).
# ─────────────────────────────────────────────────
for f in "$SCAN" "$ISO"; do
    if grep -nE '^[[:space:]]*base=("|'"'"')?(main|master)("|'"'"')?[[:space:]]*$' "$f" \
       || grep -nE 'base="\$\{[a-z_]+:-(main|master)\}"' "$f"; then
        fail "(d) $(basename "$f") still contains a hard-coded main/master base fallback"
    fi
done
pass "(d) neither script carries a hard-coded main/master base fallback"

printf 'ALL PASS: base-ref resolution uses the checked-out branch (id:758a)\n'
