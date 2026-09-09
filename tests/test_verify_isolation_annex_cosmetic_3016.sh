#!/usr/bin/env bash
# roadmap:3016 — verify-isolation.sh must not call a git-annex worktree DIRTY on cosmetic
# pointer noise, and must STILL catch every real dirt.
#
# fails-against-rev: 478d70d2 -- relay/scripts/verify-isolation.sh
# fails-against-assertion: (1) cosmetic-only tree did not pass
#
# THE REV IS PINNED TO A SHA, NOT `main`, AND THAT IS LOAD-BEARING (review run
# relay-20260909-143257-21736). This line read `main` as authored, which was the pre-fix tip
# when the branch was cut. Once d5e096a5 merged, `main` CARRIED THE FIX, so the declared
# negative case applied the fixed file to itself and the test passed against it --
# `make verify-negatives` reported `VACUOUS -- the test PASSES against its declared negative
# case`. A moving ref in a `fails-against-rev:` declaration is self-defeating by construction:
# it decays into a no-op on exactly the merge that makes the fix real, and it decays SILENTLY,
# because the opt-in runner is not part of `make test`. 478d70d2 is the last commit touching
# this file before the fix; never re-spell this as a branch name.
#
# Measured against that revision: exactly ONE FAIL line fires, and it is the declared one.
# Cases 2-5 PASS against the pre-fix code, and that is correct rather than vacuous — the old
# predicate was over-STRICT, so it necessarily catches every case that must fail. They are
# regression guards on the NEW code not being too LOOSE, which is the failure direction this
# change actually risks. Case 5 is the one that would catch it.
#
# THE DEFECT: `(c)` tested `[ -n "$(git status --porcelain)" ]` with no `git diff` cross-check.
# On git-annex, unlocked pointer files report ` M` while `git diff` is EMPTY — the index holds
# the pointer blob, the worktree holds real content, and annex could not update the index at
# checkout. annex's own message: "only a cosmetic problem affecting git status ... you can run:
# git-annex restage". Reproduced live 2026-09-09 on code.lawless (run
# relay-20260909-115705-28382, unit id:6df0): 77 paths ` M`, `git diff --stat` 0 lines, index
# blob 99 B against a 5297 B working PNG. The gate refused the merge, so an execute unit handed
# back on EVERY round on an annex repo.
#
# HOW THIS FIXTURE REPRODUCES IT WITHOUT ANNEX: a `clean` filter that maps any working content
# back to the committed blob. That is precisely the mechanism annex uses — status compares
# stat/size and flags the file, while diff runs the content through clean() and sees equality.
# Verified in-fixture below: index blob 7 B, worktree 22 B, porcelain ` M`, diff empty. So the
# test needs no annex binary and is hermetic.
#
# THE NARROWING IS THE POINT (case 5): `status --porcelain` also reports UNTRACKED files, which
# `git diff` NEVER shows. A naive "empty diff ⇒ clean" would blind the gate to untracked
# residue — which is most of what it exists to catch, since a child writing to the wrong tree
# leaves exactly that. Case 5 pins that the relaxation does NOT swallow untracked when both are
# present. If only one assertion here survives, it should be that one.
#
# Hermetic: mktemp -d, git + coreutils only, no network, never touches ~/.claude.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
V="$ROOT/relay/scripts/verify-isolation.sh"

pass=0; fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); }
bad() { echo "FAIL: $*"; fail=$((fail+1)); }

command -v git >/dev/null 2>&1 || { echo "SKIP: git unavailable"; exit 0; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
R="$TMP/repo"; mkdir -p "$R" "$TMP/hooks"

git -C "$R" init -q .
git -C "$R" config user.email t@e
git -C "$R" config user.name t
git -C "$R" config core.hooksPath "$TMP/hooks"     # neutralise any global hooksPath
git -C "$R" config filter.fake.clean 'printf POINTER'
git -C "$R" config filter.fake.smudge cat
printf '*.bin filter=fake\n' > "$R/.gitattributes"
printf 'POINTER' > "$R/big.bin"
echo tracked > "$R/a.txt"
git -C "$R" add .gitattributes big.bin a.txt
git -C "$R" commit -qm init
BASE="$(git -C "$R" rev-parse HEAD)"
git -C "$R" checkout -q -b work
echo more >> "$R/a.txt"; git -C "$R" add a.txt; git -C "$R" commit -qm work

run() { "$V" "$R" --base "$BASE" >"$TMP/out" 2>"$TMP/err"; echo $?; }

# ── Fixture sanity: the simulation must actually produce the contradiction ──────────────────
printf 'REALCONTENTREALCONTENT' > "$R/big.bin"
por="$(git -C "$R" status --porcelain)"
dif="$(git -C "$R" diff --stat)"
if [ "$por" = " M big.bin" ] && [ -z "$dif" ]; then
  ok "fixture reproduces annex shape (porcelain ' M', diff empty)"
else
  bad "fixture did NOT reproduce the annex shape (porcelain='$por' diff='$dif') -- every case below is meaningless"
  echo "---- $pass ok, $fail failed ----"; exit 1
fi

# ── (1) cosmetic-only ⇒ CLEAN (the fix) ────────────────────────────────────────────────────
rc="$(run)"
if [ "$rc" = "0" ] && grep -q 'cosmetic git-annex pointer noise' "$TMP/out"; then
  ok "(1) cosmetic pointer noise passes the gate, with a note naming restage"
else
  bad "(1) cosmetic-only tree did not pass (rc=$rc): $(head -1 "$TMP/out" "$TMP/err" | tr '\n' ' ')"
fi

# ── (2) REAL unstaged modification ⇒ DIRTY ─────────────────────────────────────────────────
echo dirty >> "$R/a.txt"
rc="$(run)"
[ "$rc" = "2" ] && ok "(2) real modification still fails the gate (rc=2)" \
                || bad "(2) real modification did NOT fail (rc=$rc)"
git -C "$R" checkout -- a.txt

# ── (3) UNTRACKED file ⇒ DIRTY (diff never shows it) ───────────────────────────────────────
touch "$R/stray.txt"
rc="$(run)"
[ "$rc" = "2" ] && ok "(3) untracked file still fails the gate (rc=2)" \
                || bad "(3) untracked file did NOT fail (rc=$rc) -- the gate is blind to residue"
rm -- "$R/stray.txt"

# ── (4) STAGED change ⇒ DIRTY ──────────────────────────────────────────────────────────────
echo staged >> "$R/a.txt"; git -C "$R" add a.txt
rc="$(run)"
[ "$rc" = "2" ] && ok "(4) staged change still fails the gate (rc=2)" \
                || bad "(4) staged change did NOT fail (rc=$rc)"
git -C "$R" reset -q HEAD -- a.txt; git -C "$R" checkout -- a.txt

# ── (5) THE NARROWING: cosmetic noise AND untracked together ⇒ DIRTY ───────────────────────
# The relaxation must not swallow the untracked entry just because the modified ones are
# cosmetic. This is the assertion that separates a correct fix from a dangerous one.
touch "$R/stray.txt"
rc="$(run)"
if [ "$rc" = "2" ]; then
  ok "(5) cosmetic noise + untracked together still fails -- relaxation did not swallow residue"
else
  bad "(5) cosmetic+untracked passed (rc=$rc) -- the relaxation is TOO WIDE and blinds the gate"
fi
rm -- "$R/stray.txt"

echo "---- $pass ok, $fail failed ----"
[ "$fail" -eq 0 ] || exit 1
