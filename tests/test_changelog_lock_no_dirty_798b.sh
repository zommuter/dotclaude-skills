#!/usr/bin/env bash
# roadmap:798b — `changelog-append.sh` must NEVER put a file in the target repo's WORKING
# TREE. Today it flocks `$repo/.changelog.lock` (changelog-append.sh:85) and leaves it there
# forever; its own header comment at :23 claims the path "matches the *.lock gitignore", which
# is FALSE for the repos it actually runs in (verified 2026-08-10: puzzle-pwa/.gitignore has no
# lock entry at all; zkm/plugins/zkm-stt/.gitignore ignores only `.git-lock-push.lock`). The
# consequence is not cosmetic: the pool's dirty-guard drops a dirty repo BEFORE classification,
# so running the changelog deriver permanently and invisibly excludes the repo from every
# future round (run relay-20260810-103858-20326: puzzle-pwa, yinyang-puzzle, zkm-stt).
#
# THE REQUIREMENT THIS SPEC PINS — and why "rm the lock on exit" does not satisfy it:
#   (1) The working tree must be clean of lock artefacts at ALL TIMES, not merely afterwards.
#       The dirty-guard is an asynchronous SAMPLER (gather-repo-state.sh runs `git status` from
#       a different process); a lock that exists only "during" the append is still observable
#       by a concurrent discovery round, and still parks the repo. Test (C) polls `git status`
#       WHILE appends run, so a remove-on-exit fix is correctly rejected.
#   (2) Mutual exclusion must be PRESERVED. Unlinking a flock'd path is the classic
#       unlink-race: B has the inode open and is blocked in flock(); A unlinks and releases;
#       C opens the now-absent path, CREATES A DIFFERENT INODE, and locks that — B and C are
#       then both inside the critical section. Test (B) exercises real concurrency and requires
#       zero lost updates.
#   Both are satisfied at once by the pattern three siblings in this very repo already use —
#   put the lock in the repo's GIT DIR, not its working tree: ckpt-tag.sh:155
#   (`$gitdir/relay-ckpt.lock`), version-bump.sh:147 (`$gitdir/version-bump.lock`),
#   diary-append.sh:116 (`$_git_dir/diary.lock`). Nothing is unlinked, nothing is gitignored,
#   `git status` never sees it. This spec asserts the REQUIREMENT, not that mechanism, so any
#   implementation that keeps the tree clean and mutual exclusion intact passes.
#
# Hermetic: mktemp -d fixture git repos (one deliberately WITHOUT any .gitignore, the
# puzzle-pwa shape), HOME overridden, no network, never touches ~/.claude or a real repo.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CA="$SRC_DIR/relay/scripts/changelog-append.sh"

pass=0; fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); }
bad() { echo "BAD: $*"; fail=$((fail+1)); }

[[ -x "$CA" ]] || { echo "FAIL: changelog-append.sh missing/not executable at $CA"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"

mkrepo() {   # mkrepo <dir> [<gitignore-contents>]
  local dir="$1"
  mkdir -p "$dir"
  git init -q "$dir"
  printf '# Changelog\n' > "$dir/CHANGELOG.md"
  if [[ $# -ge 2 ]]; then printf '%s\n' "$2" > "$dir/.gitignore"; fi
  git -C "$dir" add -A
  git -C "$dir" -c user.email=t@e -c user.name=t commit -q -m init
}

# Untracked/modified paths git reports, one per line, basename only.
dirty_paths() { git -C "$1" status --porcelain | sed 's/^...//' | sed 's#.*/##'; }

# ── (A) A single append must leave the tree carrying ONLY the CHANGELOG.md edit. ────────────
#        Two fixture shapes: NO .gitignore at all (puzzle-pwa), and the partial one that
#        ignores a DIFFERENT lock (zkm-stt). The fix must not depend on either.
for shape in nogitignore partialgitignore; do
  repo="$TMP/$shape"
  case "$shape" in
    nogitignore)      mkrepo "$repo" ;;
    partialgitignore) mkrepo "$repo" '.git-lock-push.lock' ;;
  esac
  "$CA" "$repo" --summary "first close" --ids "798b" --date 2026-08-10 >/dev/null

  residue="$(dirty_paths "$repo" | grep -v '^CHANGELOG.md$' || true)"
  if [[ -z "$residue" ]]; then
    ok "($shape) after an append the tree carries ONLY the CHANGELOG.md edit"
  else
    bad "id:798b: ($shape) changelog-append.sh dirtied the repo with: $(tr '\n' ' ' <<<"$residue")"
  fi

  # Named explicitly: the lock file the item is about must not exist in the working tree.
  [[ ! -e "$repo/.changelog.lock" ]] \
    && ok "($shape) no .changelog.lock left in the working tree" \
    || bad "id:798b: ($shape) $repo/.changelog.lock persists — the dirty-guard will park this repo forever"

  # Nothing lock-shaped ANYWHERE in the working tree (a renamed lock is the same defect).
  strays="$(find "$repo" -path "$repo/.git" -prune -o -name '*.lock' -print 2>/dev/null || true)"
  [[ -z "$strays" ]] \
    && ok "($shape) no *.lock artefact anywhere in the working tree" \
    || bad "id:798b: ($shape) lock artefact(s) left in the working tree: $(tr '\n' ' ' <<<"$strays")"

  # The append itself must still have WORKED — a fix that no-ops is not a fix.
  grep -qF 'first close' "$repo/CHANGELOG.md" \
    && ok "($shape) the bullet was actually appended" \
    || bad "id:798b: ($shape) the append did not land — the fix must not break the deriver"
done

# ── (B) MUTUAL EXCLUSION under real concurrency: N writers, zero lost updates. ──────────────
#        This is the assertion an unlink-based fix must survive. Two inodes for "the" lock
#        means two writers in the read-modify-write critical section and a dropped bullet.
conc_repo="$TMP/concurrent"
mkrepo "$conc_repo"
N=10
ROUNDS=3
for r in $(seq 1 "$ROUNDS"); do
  pids=()
  for i in $(seq 1 "$N"); do
    "$CA" "$conc_repo" --summary "round${r}-writer${i}" --date 2026-08-10 >/dev/null 2>&1 &
    pids+=($!)
  done
  for p in "${pids[@]}"; do wait "$p" || true; done
done

missing=0
for r in $(seq 1 "$ROUNDS"); do
  for i in $(seq 1 "$N"); do
    grep -qF "round${r}-writer${i}" "$conc_repo/CHANGELOG.md" || { missing=$((missing+1)); }
  done
done
if [[ "$missing" -eq 0 ]]; then
  ok "concurrency: all $((N*ROUNDS)) concurrent bullets survived (mutual exclusion holds)"
else
  bad "id:798b: LOST UPDATE — $missing of $((N*ROUNDS)) concurrent bullets vanished; mutual exclusion is broken (the unlink race)"
fi

# Exactly one date bucket header — a torn read-modify-write duplicates it.
hdrs=$(grep -c '^## 2026-08-10$' "$conc_repo/CHANGELOG.md" || true)
[[ "$hdrs" -eq 1 ]] \
  && ok "concurrency: exactly one '## 2026-08-10' bucket header (no torn write)" \
  || bad "id:798b: $hdrs '## 2026-08-10' headers — concurrent writers tore the file"

# ...and the tree is still clean afterwards.
residue="$(dirty_paths "$conc_repo" | grep -v '^CHANGELOG.md$' || true)"
[[ -z "$residue" ]] \
  && ok "concurrency: tree still carries only the CHANGELOG.md edit" \
  || bad "id:798b: after concurrent appends the tree is dirty with: $(tr '\n' ' ' <<<"$residue")"

# ── (C) The tree must be clean DURING the run, not only after it. The dirty-guard samples
#        asynchronously, so a transiently-present lock still parks the repo. This is the case
#        that distinguishes "remove the lock on exit" from a real fix. ─────────────────────
poll_repo="$TMP/polled"
mkrepo "$poll_repo"
hits_file="$TMP/poll-hits.txt"
: > "$hits_file"

(
  for i in $(seq 1 25); do
    git -C "$poll_repo" status --porcelain 2>/dev/null \
      | sed 's/^...//' \
      | grep -E '(^|/)[^/]*\.lock$' >> "$hits_file" || true
    sleep 0.01
  done
) &
poller=$!

for i in $(seq 1 12); do
  "$CA" "$poll_repo" --summary "polled-$i" --date 2026-08-10 >/dev/null 2>&1 || true
done
wait "$poller" 2>/dev/null || true

if [[ ! -s "$hits_file" ]]; then
  ok "no lock file was EVER observable to a concurrent \`git status\` sampler during the run"
else
  bad "id:798b: a lock file was visible to \`git status\` DURING the run ($(sort -u "$hits_file" | tr '\n' ' ')) — an async dirty-guard sample still parks the repo; removing it on exit is not sufficient"
fi

# ── (D) The false claim in the source must not survive the fix (CLAUDE.md: a code comment
#        asserting behaviour is a derived doc, and this one is wrong). ─────────────────────
if grep -q 'matches the \*.lock gitignore' "$CA"; then
  bad "id:798b: changelog-append.sh still asserts the lockfile 'matches the *.lock gitignore' — verified false for puzzle-pwa and zkm-stt; the comment must go with the fix"
else
  ok "the false 'matches the *.lock gitignore' claim is gone from the source"
fi

echo "---"
echo "summary: $pass ok, $fail bad"
[[ "$fail" -eq 0 ]] || exit 1
echo "ALL PASS: changelog-append.sh never dirties the target repo and keeps mutual exclusion (id:798b)"
