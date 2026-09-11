#!/usr/bin/env bash
# NO `# roadmap:` HEADER ON PURPOSE: id:fac7 is a TODO.md item with no ROADMAP.md checkbox, so
# there is no checkbox whose unticked state could make a failure here EXPECTED-RED. This is a
# defect-fix test and its failures always count.
#
# id:fac7 -- gather-repo-state.sh must decide `dirty` with the SHARED lib-clean-tree.sh
# predicate, not a bare `git status --porcelain` non-empty test, so cosmetic git-annex pointer
# noise no longer classifies a repo `blocked` and starves it of dispatch -- while every
# GENUINELY dirty tree keeps reporting dirty, which is the assertion that matters most.
#
# fails-against-rev: 48967f44b75b14a1f7566f047fcd70f8e63a03ea -- relay/scripts/gather-repo-state.sh
# fails-against-assertion: (1) cosmetic-only dirt still reported dirty=true
#
# THE REV IS PINNED TO A SHA, NOT `main` (tests/test_negative_case_moving_rev_0801.sh spells out
# why: a moving ref decays into a no-op on exactly the merge that makes the fix real).
# 48967f44 is the last commit touching this script before the fix, so substituting this ONE file
# reproduces the pre-fix behaviour exactly. That revision does not source lib-clean-tree.sh at
# all, which is the defect: the shared predicate existed (id:68e2) and this caller never asked it.
#
# THE DEFECT: `porcelain="$(git -C "$path" status --porcelain ...)"` then
# `[[ -n "$porcelain" ]] && dirty=true`, with no `git diff` cross-check. On a git-annex repo whose
# index is stale against annexed files, unlocked pointer files report ` M` while `git diff` is
# EMPTY. classify-verdict.sh folds `dirty` into `dirty_block` and the repo surfaces `blocked`.
# Measured cost: 7 code.lawless dispatches lost in run relay-20260910-234645-16942.
#
# HOW THIS FIXTURE REPRODUCES IT WITHOUT ANNEX: a `clean` filter that maps any working content
# back to the committed blob, the same device tests/test_verify_isolation_annex_cosmetic_3016.sh,
# tests/test_worktree_retire_annex_cosmetic_68e2.sh and
# tests/test_verify_isolation_empty_cosmetic_0fad.sh use. That is precisely the mechanism annex
# uses -- status compares stat/size and flags the file, while diff runs the content through
# clean() and sees equality. Case (0) REFUSES to continue unless it reproduced.
#
# A GREEN RUN ON A NON-ANNEX OR CLEAN-INDEX REPO WOULD PROVE NOTHING, which is exactly why case
# (0) is a hard stop rather than a warning. Calibrated additionally against the REAL incident
# tree ~/.cache/relay/worktrees/code.lawless/relay-20260911-103808-7255-execute-a736-0 (read
# only, never modified): tree_clean_probe returns rc=0 cosmetic=1 count=204 there.
#
# THE NARROWING IS THE POINT (cases 2-5). `git diff` NEVER shows untracked files, so a naive
# "empty diff means clean" would blind dispatch to the residue these gates mainly exist to catch.
# If only one assertion here survives, it should be (2) or (4).
#
# CASE (6) pins the deliberate fail-direction change: `git status` FAILING now reads DIRTY. It
# also pins the `-n "$porcelain"` arm added to both exemption tests -- on that path TREE_PORCELAIN
# is EMPTY, and an empty porcelain makes dirty_lock_only and dirty_untracked_only vacuously true,
# which would hand the fail-safe straight back through
# `dirty_block = dirty and not lock_only and not untracked_only`.
#
# CASE (7) pins the in-place-relaxation decision at the SECOND consumer of `dirty`: is_finished.
#
# Hermetic: mktemp -d, own HOME, own hooksPath, own GATHER_REPO_STATE_LOG, own RELAY_TOML and
# RELAY_WORKTREE_BASE, git + python3 only, no network, never touches ~/.claude or ~/.cache/relay.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
G="$ROOT/relay/scripts/gather-repo-state.sh"
CV="$ROOT/relay/scripts/classify-verdict.sh"

command -v git >/dev/null 2>&1     || { echo "SKIP: git unavailable"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 unavailable"; exit 0; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME" "$TMP/hooks"
export GATHER_REPO_STATE_LOG="$TMP/gather.log"
export RELAY_TOML="$TMP/relay.toml"
export RELAY_WORKTREE_BASE="$TMP/worktrees"
: > "$RELAY_TOML"

pass=0
ok()   { echo "ok: $*"; pass=$((pass+1)); }
fail() { echo "FAIL: $*"; echo "---- $pass ok, 1 failed ----"; exit 1; }

# mkrepo <name> -- a repo with a clean-filter'd *.bin plus an ordinary tracked file.
mkrepo() {
  local name="$1" repo="$TMP/$1"
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
  git -C "$repo" -c commit.gpgsign=false commit -qm init
  printf '%s' "$repo"
}

# Cosmetic dirt: real content in the filtered file. status flags it ' M', diff sees equality.
cosmetic() { printf 'REALCONTENTREALCONTENT' > "$1/big.bin"; }

gather() { "$G" --repo "$1" --path "$2" 2>"$TMP/err"; }

# field <json> <key> -- prints the value, or ERR when the JSON is unusable.
field() {
  printf '%s' "$1" | KEY="$2" python3 -c '
import json,os,sys
try:
    print(json.load(sys.stdin).get(os.environ["KEY"]))
except Exception:
    print("ERR")
' 2>/dev/null || echo ERR
}

verdict_of() {
  printf '%s' "$1" | python3 -c '
import json,sys
d = json.load(sys.stdin)
d.setdefault("unpromoted", {"promote": 0, "surface": 0})
print(json.dumps(d))
' 2>/dev/null | "$CV" 2>/dev/null | python3 -c '
import json,sys
try:
    print(json.load(sys.stdin).get("verdict"))
except Exception:
    print("ERR")
' 2>/dev/null || echo ERR
}

# -- (0) fixture sanity: the simulation must produce the contradiction ------------------------
R="$(mkrepo sanity)"
cosmetic "$R"
por="$(git -C "$R" status --porcelain)"
dif="$(git -C "$R" diff --stat)"
{ [ "$por" = " M big.bin" ] && [ -z "$dif" ]; } \
  || fail "(0) fixture did NOT reproduce the annex shape (porcelain='$por' diff='$dif') -- every case below is meaningless"
ok "(0) fixture reproduces the annex shape (porcelain ' M', diff empty)"

# -- (1) THE DEFECT: cosmetic-only dirt is NOT dirty, and does NOT block ----------------------
R="$(mkrepo plain)"
cosmetic "$R"
out="$(gather plain "$R")"
d="$(field "$out" dirty)"
[ "$d" = "False" ] || fail "(1) cosmetic-only dirt still reported dirty=true (got '$d') -- the repo would classify blocked and lose every dispatch"
v="$(verdict_of "$out")"
[ "$v" != "blocked" ] || fail "(1b) cosmetic-only dirt still classifies verdict=blocked -- the dispatch-starving outcome is unchanged"
ok "(1) cosmetic-only dirt reports dirty=false and does not classify blocked (verdict=$v)"

# -- (1c) VISIBILITY IS NOT LOST: the raw porcelain field still carries the entry --------------
p="$(field "$out" porcelain)"
case "$p" in
  *" M big.bin"*) ok "(1c) the raw porcelain field still reports the entry -- relaxed, not swallowed" ;;
  *) fail "(1c) the porcelain field lost the cosmetic entry ('$p') -- the relaxation became a silent swallow" ;;
esac

# -- (2) GENUINE-DIRTY CONTROL: a real tracked modification must STILL report dirty ------------
# This control matters more than the happy path: it is the id:aa93 guarantee the gate exists for.
R="$(mkrepo realmod)"
echo "uncommitted work" >> "$R/a.txt"
out="$(gather realmod "$R")"
d="$(field "$out" dirty)"
lo="$(field "$out" dirty_lock_only)"
uo="$(field "$out" dirty_untracked_only)"
{ [ "$d" = "True" ] && [ "$lo" = "False" ] && [ "$uo" = "False" ]; } \
  || fail "(2) a GENUINELY dirty tree no longer blocks (dirty=$d lock_only=$lo untracked_only=$uo) -- the relaxation swallowed real work"
v="$(verdict_of "$out")"
[ "$v" = "blocked" ] || fail "(2b) a genuinely dirty tree did not classify blocked (verdict=$v) -- id:aa93 broken"
ok "(2) genuine-dirty control: a real tracked modification still reports dirty and classifies blocked"

# -- (3) UNTRACKED residue stays dirty (git diff NEVER shows untracked) -----------------------
R="$(mkrepo untracked)"
touch "$R/stray.png"
out="$(gather untracked "$R")"
d="$(field "$out" dirty)"
uo="$(field "$out" dirty_untracked_only)"
{ [ "$d" = "True" ] && [ "$uo" = "True" ]; } \
  || fail "(3) untracked-only residue lost its dirty/untracked-only reporting (dirty=$d untracked_only=$uo) -- id:27b4 regressed"
ok "(3) untracked residue still reports dirty=true with dirty_untracked_only=true (id:27b4 intact)"

# -- (4) THE NARROWING: cosmetic noise AND an untracked file together stay dirty ---------------
R="$(mkrepo mixed)"
cosmetic "$R"
touch "$R/stray.png"
out="$(gather mixed "$R")"
d="$(field "$out" dirty)"
[ "$d" = "True" ] || fail "(4) cosmetic+untracked was relaxed to clean (dirty=$d) -- the relaxation is TOO WIDE and swallowed real residue"
ok "(4) cosmetic noise plus an untracked file still reports dirty -- the relaxation did not swallow residue"

# -- (5) STAGED change alongside cosmetic noise stays dirty ------------------------------------
R="$(mkrepo staged)"
cosmetic "$R"
echo staged >> "$R/a.txt"
git -C "$R" add a.txt
out="$(gather staged "$R")"
d="$(field "$out" dirty)"
[ "$d" = "True" ] || fail "(5) a STAGED change alongside cosmetic noise was relaxed to clean (dirty=$d)"
ok "(5) a staged change alongside cosmetic noise still reports dirty"

# -- (6) FAIL SAFE: `git status` failing reads DIRTY, and the exemptions do not undo it --------
# A BARE repo is the portable way to reach it: `rev-parse --git-dir` succeeds (so gather does not
# take its is_git=false exit) while `git status` cannot run without a work tree.
R="$TMP/bare"; mkdir -p "$R"; git -C "$R" init -q --bare
out="$(gather bare "$R")"
d="$(field "$out" dirty)"
lo="$(field "$out" dirty_lock_only)"
uo="$(field "$out" dirty_untracked_only)"
[ "$d" = "True" ] || fail "(6) an unreadable tree ('git status' failed) reported dirty=$d -- an error must never read as CLEAN (the id:a290 fail-open shape)"
{ [ "$lo" = "False" ] && [ "$uo" = "False" ]; } \
  || fail "(6b) the empty porcelain of a failed status made an exemption vacuously true (lock_only=$lo untracked_only=$uo) -- dirty_block would hand the fail-safe straight back"
v="$(verdict_of "$out")"
[ "$v" = "blocked" ] || fail "(6c) an unreadable tree did not classify blocked (verdict=$v) -- the fail-safe never reached the verdict"
ok "(6) a failed 'git status' fails SAFE to dirty, both exemptions stay false, and the verdict is blocked"

# -- (7) THE IN-PLACE DECISION AT THE OTHER CONSUMER: is_finished treats cosmetic as clean ------
# `dirty` has exactly two live consumers; this is the second. A cosmetic tree has nothing to
# commit, so a drained roadmap plus cosmetic pointer noise IS a finished repo. Control below.
R="$(mkrepo finished)"
printf '# Roadmap\n\n- [x] done\n' > "$R/ROADMAP.md"
git -C "$R" add ROADMAP.md
git -C "$R" -c commit.gpgsign=false commit -qm roadmap
git -C "$R" tag -a "relay-ckpt-20260911-0000" -m "reviewer (claude-opus-5)"
cosmetic "$R"
out="$(gather finished "$R")"
f="$(field "$out" is_finished)"
[ "$f" = "True" ] || fail "(7) a drained roadmap with cosmetic-only dirt did not read is_finished (got '$f') -- the relaxation did not reach the second consumer"
# Control: the SAME repo with genuine dirt must NOT be finished.
echo "real work" >> "$R/a.txt"
out="$(gather finished "$R")"
f="$(field "$out" is_finished)"
[ "$f" = "False" ] || fail "(7b) a genuinely dirty tree read is_finished=$f -- is_finished went blind to real uncommitted work"
ok "(7) is_finished treats cosmetic dirt as clean, and genuine dirt still defeats it"

# -- (8) the relaxation is RECORDED, never silent ----------------------------------------------
grep -q 'cosmetic git-annex pointer noise' "$GATHER_REPO_STATE_LOG" \
  || fail "(8) the cosmetic relaxation left no trace in GATHER_REPO_STATE_LOG -- a silent relaxation is exactly the no-silent-swallow failure class"
ok "(8) the cosmetic relaxation is recorded in the log"

echo "---- $pass ok, 0 failed ----"
exit 0
