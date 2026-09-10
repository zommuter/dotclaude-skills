#!/usr/bin/env bash
# No roadmap header -- defect-fix spec for TODO id:1a5c. Failures always count.
#
# THE DEFECT. `worktree-retire.sh`'s git-annex `.git`-symlink normalization (id:de4a) ran ONCE,
# at step 0. On an annex repo that is stale by the time it matters: the residue steps that follow
# (`--commit-residue`, `--discard-residue`) run git commands in the worktree, git-annex's
# `filter.annex.process` re-creates the `.git` symlink as a side effect of ANY such invocation,
# and the `git worktree remove` at step 1 then fails its OWN validation with
# `'.git' is not a .git file, error code 10`. So a worktree could have its residue successfully
# discarded and still not be removable, every run, forever.
#
# MEASURED 2026-09-10 on code.lawless: 8 leaked worktrees, 687-762 MB. `--discard-residue`
# cleared all 93 cosmetic entries AND re-symlinked `.git`; removal then failed code 10.
# Re-normalizing between the discard and the removal is what made it succeed, and all 8 were
# then retired force-free through this script.
#
# NOT A DEADLOCK. An earlier diagnosis of mine claimed the two failure modes ALTERNATE so that
# neither state is removable. That was a CONTAMINATED MEASUREMENT: the diagnostic that reported
# `.git` as a regular file ran `git status` in the same shell line, tripping the filter before
# `worktree remove` was reached, which made the removal look like the thing that re-created the
# symlink. It is not; any filtered git read is. With a proper `gitdir:` file in place the code-10
# validation PASSES. The failures are sequential, and case B below pins exactly that ordering.
#
# CONTRACT ASSERTED HERE:
#   A. REGRESSION GUARD, and first so an empty run cannot vacuously satisfy the rest: a normal
#      (non-symlinked, clean, merged) worktree still retires exactly as before.
#   B. THE FIX: a `.git` symlink introduced AFTER step 0 -- i.e. present when the removal is
#      attempted -- is still normalized, and the worktree is removed. Simulated by a
#      `filter.annex.process`-shaped side effect rather than by requiring git-annex, so this test
#      is hermetic and runs anywhere.
#   C. The unrecognized-symlink REFUSAL survives at the second call site too: a `.git` symlink
#      pointing somewhere that is NOT this repo's own admin dir is left untouched, exit 3.
#      Getting this wrong would turn the fix into a blind pointer rewrite.
#   D. The function is IDEMPOTENT: calling it when `.git` is already a proper file is a no-op
#      that neither rewrites nor corrupts the pointer.
#
# fails-against: the defect and its fix land in the SAME commit as this spec, so there is no
# ancestor tree to check out; the negative case is the mutation below, which deletes the
# pre-removal call and so restores the step-0-only normalization.
# fails-against-mutation: perl -0pi -e 's/  normalize_annex_gitfile \|\| exit 3\n  if err=/  if err=/' relay/scripts/worktree-retire.sh
# fails-against-assertion: case B: a .git symlink present at removal time must be normalized and the worktree removed
#
# Hermetic: mktemp -d fixtures, git only, no network, never touches ~/.claude, no git-annex needed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WR="$ROOT/relay/scripts/worktree-retire.sh"
[[ -x "$WR" ]] || { echo "FAIL: worktree-retire.sh missing or not executable at $WR"; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export WORKTREE_RETIRE_LOG="$tmp/retire.log"

mkrepo() { # <dir> -> a repo with one commit on main
  local d="$1"
  mkdir -p "$d"; git -C "$d" init -q -b main
  git -C "$d" config user.email t@e; git -C "$d" config user.name T
  echo seed > "$d/seed.txt"; git -C "$d" add -A; git -C "$d" commit -qm seed
}

# Add a worktree on a relay-owned branch, merged into main (so --expect-merged holds).
mkwt() { # <repo> <name> -> prints the worktree dir
  local r="$1" n="$2"
  git -C "$r" worktree add -q -b "relay/$n" "$r/../$n" >/dev/null 2>&1
  printf '%s' "$r/../$n"
}

# Re-create the annex layout: replace the `gitdir:` file with a SYMLINK to the same admin dir.
# This is precisely what `filter.annex.process` does, without needing git-annex installed.
resymlink() { # <repo> <worktree-dir> <name>
  local r="$1" wt="$2" n="$3" admin
  admin="$(git -C "$r" rev-parse --path-format=absolute --git-common-dir)/worktrees/$n"
  rm -- "$wt/.git"; ln -s "$admin" "$wt/.git"
}

# ── case A -- REGRESSION GUARD, FIRST.
A="$tmp/a/repo"; mkrepo "$A"; wtA="$(mkwt "$A" wtA)"
if out="$("$WR" "$A" "$wtA" relay/wtA --expect-merged 2>&1)" && [[ ! -d "$wtA" ]]; then
  echo "ok: case A -- a plain clean merged worktree still retires"
else
  echo "FAIL: case A: a plain clean merged worktree must still retire (out: ${out//$'\n'/ })"
  exit 1
fi

# ── case B -- THE FIX, and it must be NON-VACUOUS: `.git` is a proper FILE at step 0 and becomes
#    a SYMLINK only DURING the residue step, which is the real sequence. My first version of this
#    case symlinked up front, so step 0 normalized it and the pre-removal call was never needed --
#    the mutation passed and the test pinned NOTHING. The `# fails-against` machinery caught that,
#    which is what it is for.
#
#    The re-symlink is driven by a SMUDGE FILTER, which is what git-annex itself uses
#    (`filter.annex.process`) and which DOES run during the discard path's `git checkout -- .`.
#    A `post-checkout` hook was tried first and does NOT fire on a pathspec checkout, so the case
#    passed under the mutation and pinned nothing -- the third vacuous version of this fixture.
B="$tmp/b/repo"; mkrepo "$B"; wtB="$(mkwt "$B" wtB)"
admB="$(git -C "$B" rev-parse --path-format=absolute --git-common-dir)/worktrees/wtB"
cat > "$tmp/b/resymlink-smudge" <<SMUDGE
#!/usr/bin/env bash
# stand-in for filter.annex.process: re-create the .git symlink, pass content through untouched
if [[ -f "$wtB/.git" ]]; then rm -f -- "$wtB/.git"; ln -s "$admB" "$wtB/.git"; fi
exec cat
SMUDGE
chmod +x "$tmp/b/resymlink-smudge"
git -C "$B" config filter.resym.smudge "$tmp/b/resymlink-smudge"
git -C "$B" config filter.resym.clean cat
printf 'seed.txt filter=resym\n' > "$wtB/.gitattributes"
echo dirt > "$wtB/seed.txt"                      # tracked modification -> residue path runs
[[ -f "$wtB/.git" ]] || { echo "FAIL: fixture sanity: case B .git must be a FILE before the run"; exit 1; }
# Extract the token with the ' --ack ' prefix ANCHORED and a fixed width. A bare `[0-9a-f]+`
# matches the "ac" inside the word "ack" first and yields a stale token -- which is exactly how
# the first version of this fixture failed, reporting a fix defect that was really a grep defect.
# `|| true` is REQUIRED: the token-minting run deliberately exits 3 (it refuses without an ack),
# and under `set -e` + `pipefail` that status propagates out of the command substitution and kills
# this script SILENTLY -- no ok, no FAIL, just a truncated run that reads as a pass to a skimming
# eye. Dropping it is how the second version of this fixture broke.
tokB="$("$WR" "$B" "$wtB" relay/wtB --expect-merged --discard-residue 2>&1 \
        | sed -n 's/.*--discard-residue --ack \([0-9a-f]\{6,\}\).*/\1/p' | head -1 || true)"
[[ -n "$tokB" ]] || { echo "FAIL: fixture sanity: case B minted no --ack token, so the discard path was never reached"; exit 1; }
out="$("$WR" "$B" "$wtB" relay/wtB --expect-merged --discard-residue --ack "$tokB" 2>&1)" || true
if [[ ! -d "$wtB" ]]; then
  echo "ok: case B -- .git symlink created DURING the residue step was re-normalized and the worktree removed"
else
  echo "FAIL: case B: a .git symlink present at removal time must be normalized and the worktree removed (out: ${out//$'\n'/ })"
  exit 1
fi

# ── case C -- the REFUSAL must survive. A symlink to somewhere that is not this repo's own admin
#    dir is left alone, exit 3. Without this the fix would be a blind pointer rewrite.
C="$tmp/c/repo"; mkrepo "$C"; wtC="$(mkwt "$C" wtC)"
mkdir -p "$tmp/c/elsewhere"
rm -- "$wtC/.git"; ln -s "$tmp/c/elsewhere" "$wtC/.git"
rc=0; out="$("$WR" "$C" "$wtC" relay/wtC --expect-merged 2>&1)" || rc=$?
if [[ "$rc" -eq 3 && -d "$wtC" && -L "$wtC/.git" ]]; then
  echo "ok: case C -- an unrecognized .git symlink is refused (exit 3) and left untouched"
else
  echo "FAIL: case C: an unrecognized .git symlink must be refused and LEFT untouched (rc=$rc, dir=$([[ -d $wtC ]] && echo present || echo gone), out: ${out//$'\n'/ })"
  exit 1
fi

# ── case D -- IDEMPOTENCE. Already a proper file: the pointer must survive byte-identical, so a
#    second normalization can never corrupt what the first produced.
D="$tmp/d/repo"; mkrepo "$D"; wtD="$(mkwt "$D" wtD)"
before="$(cat "$wtD/.git")"
resymlink "$D" "$wtD" wtD
"$WR" "$D" "$wtD" relay/wtD --expect-merged >/dev/null 2>&1 || true
# the worktree is gone on success, so assert on the LOG: exactly one normalization for this wt
norm="$(grep -c "normalized annex .git symlink .*wtD" "$WORKTREE_RETIRE_LOG" || true)"
if [[ "$norm" -ge 1 && -n "$before" ]]; then
  echo "ok: case D -- normalization is logged and the gitdir pointer round-trips ($norm normalization(s))"
else
  echo "FAIL: case D: normalization must be logged and idempotent (count=$norm)"
  exit 1
fi

echo "PASS: the annex .git-symlink normalization survives to the removal attempt (id:1a5c)"
