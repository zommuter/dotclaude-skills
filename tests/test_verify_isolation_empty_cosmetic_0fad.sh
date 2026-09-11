#!/usr/bin/env bash
# NO `# roadmap:` HEADER ON PURPOSE: id:0fad is a TODO.md item with no ROADMAP.md checkbox, so
# there is no checkbox whose unticked state could make a failure here EXPECTED-RED. This is a
# defect-fix test and its failures always count.
#
# id:0fad -- verify-isolation.sh's id:1b13 EMPTY-worktree breach check must ask the SAME
# "is this tree clean?" question as its (c) branch, via the shared lib-clean-tree.sh predicate,
# so cosmetic git-annex pointer noise is not reported as an isolation BREACH -- while every
# GENUINELY dirty empty worktree keeps failing loud, which is the assertion that matters most.
#
# fails-against-rev: 71d9d2719fb215dedf5087a1e76f4e845a00335a -- relay/scripts/verify-isolation.sh
# fails-against-assertion: (1) cosmetic-only empty worktree was called a BREACH
#
# THE REV IS PINNED TO A SHA, NOT `main` (tests/test_negative_case_moving_rev_0801.sh spells out
# why: a moving ref decays into a no-op on exactly the merge that makes the fix real).
# 71d9d271 is the last commit touching this script before the fix. That revision ALREADY sources
# lib-clean-tree.sh (id:68e2 landed there) and already uses it on the (c) branch, so substituting
# this one file reproduces the pre-fix behaviour exactly: the bug is that the b0 branch never
# CALLED the shared predicate, not that the predicate was missing.
#
# THE DEFECT: the b0 branch tested `[ -n "$(git status --porcelain)" ]` with no `git diff`
# cross-check, and it runs BEFORE the commits-beyond-base test's filter-aware probe, so on a
# git-annex repo it short-circuited to "breach" before the correct predicate was ever consulted.
# Measured 2026-09-11 on zomni (pool run relay-20260911-103808-7255, code.lawless unit a736):
# handbackCode=21 "breach-shaped (id:1b13)" listing ` M` annexed PNGs under
# docs/research/img/card-match/ with workCreated:false -- a child that legitimately did nothing.
# Its worktree measured ahead=0 porcelain=204 diff=0.
#
# HOW THIS FIXTURE REPRODUCES IT WITHOUT ANNEX: a `clean` filter that maps any working content
# back to the committed blob, the same device tests/test_verify_isolation_annex_cosmetic_3016.sh
# and tests/test_worktree_retire_annex_cosmetic_68e2.sh use. That is precisely the mechanism
# annex uses -- status compares stat/size and flags the file, while diff runs the content
# through clean() and sees equality. Case (0) refuses to continue unless it reproduced.
#
# A GREEN RUN ON A NON-ANNEX OR CLEAN-INDEX REPO WOULD PROVE NOTHING, which is exactly why
# case (0) is a hard stop rather than a warning.
#
# THE NARROWING IS THE POINT (cases 2-5): the id:1b13 semantic is OWNER-DECIDED and must
# survive. An empty worktree that is GENUINELY dirty is the closest signature to "the child
# worked but never committed" and must keep failing loud. `git diff` NEVER shows untracked
# files, so a naive "empty diff means clean" would blind this gate to the residue it mainly
# exists to catch. Case (2) is the genuine-breach control; if only one assertion here
# survives, it should be (2) or (4).
#
# CASE (6) pins the OTHER half of the semantic: a cosmetic tree is relaxed to the id:8b1f
# clean-sized-out shape (no commits + nothing to lose), NOT to "merge it" -- it must fall
# THROUGH to the b1/b2/b3 main-moved discrimination, so a cosmetic tree whose main ALSO moved
# by a non-merge commit still exits 2.
#
# Hermetic: mktemp -d, own HOME, own hooksPath, own log path, git + coreutils only, no network,
# never touches ~/.claude or ~/.cache/relay.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
V="$ROOT/relay/scripts/verify-isolation.sh"

command -v git >/dev/null 2>&1 || { echo "SKIP: git unavailable"; exit 0; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME" "$TMP/hooks"
export VERIFY_ISOLATION_LOG="$TMP/verify.log"

pass=0
ok()   { echo "ok: $*"; pass=$((pass+1)); }
fail() { echo "FAIL: $*"; echo "---- $pass ok, 1 failed ----"; exit 1; }

# mkcase <name> -> echoes "<repo> <worktree> <base-branch>"
# A repo with a clean-filter'd *.bin, plus a LINKED worktree sitting on a throwaway branch at
# exactly the base commit, so `git log base..HEAD` is EMPTY (the b0/b1/b2/b3 family).
mkcase() {
  local name="$1" repo="$TMP/$1/repo" wt="$TMP/$1/wt" br
  mkdir -p "$repo"
  git -C "$repo" init -q .
  git -C "$repo" config user.email t@e
  git -C "$repo" config user.name t
  git -C "$repo" config core.hooksPath "$TMP/hooks"
  git -C "$repo" config filter.fake.clean 'printf POINTER'
  git -C "$repo" config filter.fake.smudge cat
  printf '*.bin filter=fake\n' > "$repo/.gitattributes"
  printf 'POINTER' > "$repo/big.bin"
  echo tracked > "$repo/a.txt"
  git -C "$repo" add -A
  git -C "$repo" commit -qm init
  br="$(git -C "$repo" symbolic-ref --short HEAD)"
  git -C "$repo" worktree add -q "$wt" -b "relay/$name"
  printf '%s %s %s\n' "$repo" "$wt" "$br"
}

# Cosmetic dirt: real content in the filtered file. status flags it ' M', diff sees equality.
cosmetic() { printf 'REALCONTENTREALCONTENT' > "$1/big.bin"; }

run() { "$V" "$1" --base "$2" >"$TMP/out" 2>"$TMP/err"; echo $?; }
outerr() { tr '\n' ' ' < "$TMP/out"; tr '\n' ' ' < "$TMP/err"; }

# -- (0) fixture sanity: the simulation must produce the contradiction ------------------------
read -r R W B <<< "$(mkcase sanity)"
cosmetic "$W"
por="$(git -C "$W" status --porcelain)"
dif="$(git -C "$W" diff --stat)"
cnt="$(git -C "$W" log --oneline "$B"..HEAD | grep -c . || true)"
{ [ "$por" = " M big.bin" ] && [ -z "$dif" ] && [ "$cnt" = "0" ]; } \
  || fail "(0) fixture did NOT reproduce the annex shape (porcelain='$por' diff='$dif' commits=$cnt) -- every case below is meaningless"
ok "(0) fixture reproduces the annex shape on an EMPTY worktree (porcelain ' M', diff empty, 0 commits ahead)"

# -- (1) THE DEFECT: empty worktree + cosmetic-only dirt is NOT a breach -----------------------
read -r R W B <<< "$(mkcase plain)"
cosmetic "$W"
rc="$(run "$W" "$B")"
if [ "$rc" != "0" ] || ! grep -q 'cosmetic git-annex pointer noise' "$TMP/out"; then
  fail "(1) cosmetic-only empty worktree was called a BREACH (rc=$rc): $(outerr)"
fi
grep -q 'legitimate no-op review' "$TMP/out" \
  || fail "(1b) cosmetic tree did not fall THROUGH to the b1 no-op-review verdict: $(outerr)"
ok "(1) cosmetic-only empty worktree passes with a note, and falls through to the b1 verdict"

# -- (2) GENUINE-BREACH CONTROL: a real unstaged modification must STILL fail loud -------------
# This is the id:1b13 semantic itself. It is owner-decided and the relaxation must not touch it.
read -r R W B <<< "$(mkcase realmod)"
echo "uncommitted work" >> "$W/a.txt"
rc="$(run "$W" "$B")"
{ [ "$rc" = "2" ] && grep -q 'breach-shaped (id:1b13)' "$TMP/out" && grep -q ' M a.txt' "$TMP/out"; } \
  || fail "(2) a GENUINELY dirty empty worktree no longer fails loud (rc=$rc) -- the id:1b13 semantic was broken: $(outerr)"
ok "(2) genuine-breach control: real uncommitted work still exits 2 as breach-shaped (id:1b13), naming the entry"

# -- (3) UNTRACKED residue still breaches (git diff NEVER shows untracked) ---------------------
read -r R W B <<< "$(mkcase untracked)"
touch "$W/stray.txt"
rc="$(run "$W" "$B")"
{ [ "$rc" = "2" ] && grep -q 'breach-shaped (id:1b13)' "$TMP/out"; } \
  || fail "(3) untracked residue in an empty worktree did not breach (rc=$rc) -- the gate went blind to real residue: $(outerr)"
ok "(3) untracked residue in an empty worktree still exits 2 as breach-shaped"

# -- (4) THE NARROWING: cosmetic noise AND untracked together still breaches -------------------
read -r R W B <<< "$(mkcase mixed)"
cosmetic "$W"
touch "$W/stray.txt"
rc="$(run "$W" "$B")"
{ [ "$rc" = "2" ] && grep -q 'breach-shaped (id:1b13)' "$TMP/out"; } \
  || fail "(4) cosmetic+untracked was waved through (rc=$rc) -- the relaxation is TOO WIDE and swallowed real residue: $(outerr)"
ok "(4) cosmetic noise plus an untracked file still breaches -- the relaxation did not swallow residue"

# -- (5) STAGED change still breaches ----------------------------------------------------------
read -r R W B <<< "$(mkcase staged)"
cosmetic "$W"
echo staged >> "$W/a.txt"
git -C "$W" add a.txt
rc="$(run "$W" "$B")"
{ [ "$rc" = "2" ] && grep -q 'breach-shaped (id:1b13)' "$TMP/out"; } \
  || fail "(5) a STAGED change alongside cosmetic noise was waved through (rc=$rc): $(outerr)"
ok "(5) a staged change alongside cosmetic noise still breaches"

# -- (6) the relaxation is 'clean-sized-out', NOT 'merge it': b2 must still fire ----------------
# A cosmetic tree falls through to the main-moved discrimination. If main advanced by a
# NON-MERGE, non-ledger commit, that is still the isolation-breach signature and must exit 2.
read -r R W B <<< "$(mkcase mainmoved)"
cosmetic "$W"
echo "written straight to main" >> "$R/a.txt"
git -C "$R" commit -qam "direct-to-main commit"
rc="$(run "$W" "$B")"
{ [ "$rc" = "2" ] && grep -q 'NON-MERGE commit' "$TMP/out"; } \
  || fail "(6) cosmetic dirt suppressed the b2 main-moved breach (rc=$rc) -- the relaxation became 'merge it' instead of clean-sized-out: $(outerr)"
ok "(6) a cosmetic tree still exits 2 when main advanced by a non-merge commit (b2 intact)"

echo "---- $pass ok, 0 failed ----"
exit 0
