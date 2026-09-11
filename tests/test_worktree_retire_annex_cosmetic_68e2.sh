#!/usr/bin/env bash
# NO `# roadmap:` HEADER ON PURPOSE: id:68e2 is a TODO.md item with no ROADMAP.md checkbox, so
# there is no checkbox whose unticked state could make a failure here EXPECTED-RED. This is a
# defect-fix test and its failures always count.
#
# id:68e2 -- worktree-retire.sh must not call a git-annex worktree DIRTY on cosmetic pointer
# noise, and must STILL refuse every real residue.
#
# fails-against-rev: ecb6c22ccfc9a6508980a5d0b8c1f6daa759b411 -- relay/scripts/worktree-retire.sh
# fails-against-assertion: (1) cosmetic-only worktree was NOT retired
#
# THE REV IS PINNED TO A SHA, NOT `main` (tests/test_negative_case_moving_rev_0801.sh spells out
# why: a moving ref decays into a no-op on exactly the merge that makes the fix real).
# ecb6c22c is the last commit touching this script before the fix. That revision does not source
# lib-clean-tree.sh at all, so substituting the file alone reproduces the pre-fix behaviour
# exactly; the new lib sitting unused in the tree changes nothing there.
#
# THE DEFECT: three gates tested `[ -n "$(git status --porcelain)" ]` with no `git diff`
# cross-check, while verify-isolation.sh answered the same question with the id:3016
# filter-aware predicate. On a git-annex repo the two disagreed about the very same worktree.
# Measured 2026-09-11 on zomni (pool run relay-20260910-234645-16942, code.lawless): three of
# four worktrees reported 204 porcelain entries, ALL ` M`, with an empty `git diff`, an empty
# `git diff --cached` and zero commits ahead of main; the fourth, from the same run, was a
# genuinely empty control. They were never reaped.
#
# HOW THIS FIXTURE REPRODUCES IT WITHOUT ANNEX: a `clean` filter that maps any working content
# back to the committed blob, the same device tests/test_verify_isolation_annex_cosmetic_3016.sh
# uses. That is precisely the mechanism annex uses -- status compares stat/size and flags the
# file, while diff runs the content through clean() and sees equality. Case (0b) additionally
# pins that `git worktree remove` ITSELF refuses such a tree, which is why the fix needs the
# index refresh and not only the relaxed predicate.
#
# THE NARROWING IS THE POINT (cases 2, 3, 6): `status --porcelain` also reports UNTRACKED files,
# which `git diff` NEVER shows. A naive "empty diff means clean" would blind these gates to the
# residue they mainly exist to catch. If only one assertion here survives, it should be (3).
#
# Hermetic: mktemp -d, own HOME, own hooksPath, own log path, git + coreutils only, no network,
# never touches ~/.claude or ~/.cache/relay.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RETIRE="$ROOT/relay/scripts/worktree-retire.sh"

command -v git >/dev/null 2>&1 || { echo "SKIP: git unavailable"; exit 0; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME" "$TMP/hooks"
export WORKTREE_RETIRE_LOG="$TMP/retire.log"

pass=0
ok()   { echo "ok: $*"; pass=$((pass+1)); }
fail() { echo "FAIL: $*"; echo "---- $pass ok, 1 failed ----"; exit 1; }

# mkcase <name> [--unmerged] -> echoes "<repo> <wt> <branch>"
# A repo with a clean-filter'd *.bin, plus a linked worktree on relay/<name> whose branch is an
# ancestor of main (so retire deletes it) unless --unmerged (so retire parks it).
mkcase() {
  local name="$1" unmerged="${2:-}" repo="$TMP/$1/repo" wt="$TMP/$1/wt" br="relay/$1"
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
  git -C "$repo" worktree add -q "$wt" -b "$br"
  if [ -n "$unmerged" ]; then
    echo extra >> "$wt/a.txt"
    git -C "$wt" commit -q -am "unmerged work"
  fi
  printf '%s %s %s\n' "$repo" "$wt" "$br"
}

# Make the worktree cosmetically dirty: real content in the filtered file. status flags it,
# diff does not.
cosmetic() { printf 'REALCONTENTREALCONTENT' > "$1/big.bin"; }

run_retire() { "$RETIRE" "$@" >"$TMP/out" 2>"$TMP/err"; echo $?; }

# -- (0) fixture sanity: the simulation must produce the contradiction ------------------------
read -r R W B <<< "$(mkcase sanity)"
cosmetic "$W"
por="$(git -C "$W" status --porcelain)"
dif="$(git -C "$W" diff --stat)"
[ "$por" = " M big.bin" ] && [ -z "$dif" ] \
  || fail "(0) fixture did NOT reproduce the annex shape (porcelain='$por' diff='$dif') -- every case below is meaningless"
ok "(0) fixture reproduces the annex shape (porcelain ' M', diff empty)"

# -- (0b) sanity: git's OWN removal check refuses that tree ------------------------------------
# This is why the relaxed predicate alone is not the whole fix: the gates could call the tree
# clean and the removal would still refuse. If this ever stops holding, the refresh step in
# worktree-retire.sh (0b) is dead weight and should be revisited rather than kept on faith.
if git -C "$R" worktree remove "$W" >/dev/null 2>&1; then
  fail "(0b) git worktree remove ACCEPTED a cosmetically dirty tree -- the premise of the fix's refresh step no longer holds"
fi
ok "(0b) git worktree remove itself refuses a cosmetically dirty tree (so a relaxed gate alone would not retire it)"

# -- (1) THE DEFECT: a cosmetic-only worktree retires, with no flags at all --------------------
read -r R W B <<< "$(mkcase plain)"
cosmetic "$W"
rc="$(run_retire "$R" "$W" "$B")"
if [ "$rc" != "0" ] || [ -e "$W" ]; then
  fail "(1) cosmetic-only worktree was NOT retired (rc=$rc, present=$([ -e "$W" ] && echo yes || echo no)): $(tr '\n' ' ' < "$TMP/out")$(tr '\n' ' ' < "$TMP/err")"
fi
ok "(1) cosmetic-only worktree retires with no flags (rc=0, worktree gone)"

# -- (2) UNTRACKED residue still blocks (constraint: git diff never shows untracked) ----------
read -r R W B <<< "$(mkcase untracked)"
touch "$W/stray.txt"
rc="$(run_retire "$R" "$W" "$B")"
{ [ "$rc" = "3" ] && [ -e "$W" ] && [ -e "$W/stray.txt" ]; } \
  || fail "(2) untracked residue did not surface-and-leave (rc=$rc) -- the gate went blind to real residue"
ok "(2) untracked residue still surfaces and leaves the worktree on disk (rc=3)"

# -- (3) THE NARROWING: cosmetic noise AND untracked together still blocks ---------------------
read -r R W B <<< "$(mkcase mixed)"
cosmetic "$W"
touch "$W/stray.txt"
rc="$(run_retire "$R" "$W" "$B")"
{ [ "$rc" = "3" ] && [ -e "$W/stray.txt" ]; } \
  || fail "(3) cosmetic+untracked was retired anyway (rc=$rc) -- the relaxation is TOO WIDE and swallowed real residue"
ok "(3) cosmetic noise plus an untracked file still blocks -- relaxation did not swallow residue"

# -- (4) --discard-residue on a cosmetic tree demands NO owner token ---------------------------
read -r R W B <<< "$(mkcase discard)"
cosmetic "$W"
rc="$(run_retire "$R" "$W" "$B" --discard-residue)"
if [ "$rc" != "0" ] || grep -qi 'REFUSED' "$TMP/err"; then
  fail "(4) --discard-residue on a cosmetic-only tree still demanded an owner-authorized token (rc=$rc): $(tr '\n' ' ' < "$TMP/err")"
fi
ok "(4) --discard-residue on a cosmetic-only tree needs no --ack token and retires"

# -- (5) --commit-residue on a cosmetic tree mints NO commit -----------------------------------
# Unmerged so the branch PARKS and its commit count stays readable after the retire.
read -r R W B <<< "$(mkcase commit --unmerged)"
cosmetic "$W"
before="$(git -C "$R" rev-list --count "$B")"
rc="$(run_retire "$R" "$W" "$B" --commit-residue)"
after="$(git -C "$R" rev-list --count "relay/orphan/$(basename "$W")" 2>/dev/null || echo -1)"
{ [ "$rc" = "0" ] && [ "$after" = "$before" ]; } \
  || fail "(5) --commit-residue on a cosmetic-only tree did not park cleanly without a new commit (rc=$rc before=$before after=$after)"
ok "(5) --commit-residue on a cosmetic-only tree parks with NO residue commit minted"

# -- (6) real residue with --commit-residue IS still committed ---------------------------------
read -r R W B <<< "$(mkcase realresidue --unmerged)"
echo "genuinely new work" > "$W/new.txt"
before="$(git -C "$R" rev-list --count "$B")"
rc="$(run_retire "$R" "$W" "$B" --commit-residue)"
after="$(git -C "$R" rev-list --count "relay/orphan/$(basename "$W")" 2>/dev/null || echo -1)"
{ [ "$rc" = "0" ] && [ "$after" = "$((before + 1))" ]; } \
  || fail "(6) real residue was NOT preserved by --commit-residue (rc=$rc before=$before after=$after) -- work would have been lost"
ok "(6) real residue is still committed and parked by --commit-residue"

# -- (7) FAIL SAFE: an unreadable index never reads as clean or as discardable ------------------
if [ "$(id -u)" -eq 0 ]; then
  ok "(7) SKIPPED as root (chmod 000 does not deny root)"
else
  read -r R W B <<< "$(mkcase unreadable)"
  idx="$R/.git/worktrees/$(basename "$W")/index"
  chmod 000 "$idx"
  rc="$(run_retire "$R" "$W" "$B" --discard-residue)"
  chmod 600 "$idx"
  { [ "$rc" = "3" ] && [ -e "$W" ]; } \
    || fail "(7) --discard-residue on a worktree whose index cannot be read did not refuse (rc=$rc) -- an empty status read as clean is the id:a290 round-3 fail-open shape"
  ok "(7) an unreadable index refuses the discard branch and leaves the worktree alone"
fi

echo "---- $pass ok, 0 failed ----"
exit 0
