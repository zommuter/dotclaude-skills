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
grep -q "retire-deferred" < <(printf '%s' "$out") || fail "dirty: output must surface a retire-deferred line"
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
grep -q "retire-anomaly" < <(printf '%s' "$out") || fail "expect-merged anomaly: must surface a retire-anomaly line"
pass "--expect-merged + unmerged → loud anomaly, branch kept, exit 4 ($out)"

# ── 6b. git-annex layout: worktree .git is a SYMLINK to the admin dir → still retires (id:de4a) ──
# git-annex's smudge filter (filter.annex.process) rewrites a linked worktree's `.git` FILE
# into a SYMLINK pointing at .git/worktrees/<bn>, so `git worktree remove` fails validation
# permanently: "'<wt>/.git' is not a .git file, error code 10". Force does NOT help (validation
# precedes it), so on an annex repo EVERY relay worktree leaked forever (observed: zkWhale, the
# only annex repo among own repos, 3 dirs / 1.2G). We reproduce the layout directly rather than
# depend on git-annex being installed: the symlink IS the whole trigger.
mkwt x1
admin="$REPO/.git/worktrees/x1"
[[ -d "$admin" ]] || fail "annex-layout: precondition — admin dir $admin should exist"
[[ -f "$WTBASE/x1/.git" ]] || fail "annex-layout: precondition — .git should start as a file"
rm -- "$WTBASE/x1/.git"
ln -s "$admin" "$WTBASE/x1/.git"
[[ -L "$WTBASE/x1/.git" ]] || fail "annex-layout: precondition — .git should now be a symlink"
# Sanity: confirm stock git really does refuse this (guards against the test passing vacuously).
if git -C "$REPO" worktree remove "$WTBASE/x1" >/dev/null 2>&1; then
  fail "annex-layout: precondition — stock 'git worktree remove' unexpectedly SUCCEEDED on a symlinked .git; the bug this covers no longer reproduces"
fi
set +e
out="$("$SH" "$REPO" "$WTBASE/x1" "relay/x1" --expect-merged 2>&1)" ; rc=$?
set -e
[[ $rc -eq 0 ]] || fail "annex-layout: expected exit 0 (retired), got $rc — out: $out"
[[ ! -e "$WTBASE/x1" ]] || fail "annex-layout: worktree dir should be gone"
git -C "$REPO" show-ref --verify --quiet refs/heads/relay/x1 && fail "annex-layout: merged branch relay/x1 should be deleted"
pass "annex layout (symlinked .git) → normalized + retired, not misreported as dirty ($out)"

# ── 6c. a DIRTY annex-layout worktree is still surfaced-and-left (normalize ≠ force) ──
# The normalization must not become a backdoor that removes work: dirt still wins.
mkwt x2
admin2="$REPO/.git/worktrees/x2"
rm -- "$WTBASE/x2/.git"
ln -s "$admin2" "$WTBASE/x2/.git"
printf 'uncommitted\n' > "$WTBASE/x2/dirty.txt"
set +e
out="$("$SH" "$REPO" "$WTBASE/x2" "relay/x2" --expect-merged 2>&1)" ; rc=$?
set -e
[[ $rc -eq 3 ]] || fail "annex-layout dirty: expected exit 3 (surface+leave), got $rc — out: $out"
[[ -e "$WTBASE/x2" ]] || fail "annex-layout dirty: worktree must be LEFT on disk"
[[ -e "$WTBASE/x2/dirty.txt" ]] || fail "annex-layout dirty: uncommitted file must survive"
git -C "$REPO" show-ref --verify --quiet refs/heads/relay/x2 || fail "annex-layout dirty: branch must be kept"
pass "annex layout + dirty → surfaced and left, work intact ($out)"

# ── 7. scope: retiring one worktree never touches a sibling ──
mkwt s1
mkwt s2
"$SH" "$REPO" "$WTBASE/s1" "relay/s1" --expect-merged >/dev/null
[[ -e "$WTBASE/s2" ]] || fail "scope: sibling worktree s2 must be untouched"
git -C "$REPO" show-ref --verify --quiet refs/heads/relay/s2 || fail "scope: sibling branch relay/s2 must be untouched"
pass "single-target scope: sibling worktree+branch untouched"

# ── 8. never invokes a forbidden force op (static check of executable CODE only) ──
# The helper legitimately NAMES these verbs in prose -- in comments, and in the `msg=`/`echo`/
# `log` text a human reads when it refuses ("do NOT -D", "commit real work"). The ban has to skip
# that prose without opening a hole.
#
# REWRITTEN 2026-09-01 (TODO id:a290 round 3). The old filter dropped whole LINES matching
# `^\s*(log|echo)\b` or `(msg|hatch_refused|why|submodule_refusal)=`, which made every one of
# those six line shapes a smuggling channel -- `msg=$(git worktree remove --force "$wt")` and
# `msg=; git worktree remove --force "$wt"` both EXECUTE a force and were invisible to the ban
# (each demonstrated). The real distinction is quoting, not lines: prose lives inside a quoted
# literal, while `$( … )` / backticks are code even inside double quotes. lib-shell-code-only.py
# blanks comments and prose literals and keeps everything else. Both directions are asserted just
# below before the ban is trusted.
#
# WHAT THIS BAN DOES AND DOES NOT COVER (corrected 2026-09-01, round 4). This comment used to
# claim "a force smuggled onto ANY line is still counted". That was FALSE, and a review found
# three concrete escapes it had already missed. Two are now closed by the filter's word-like-
# literal rule (a quoted literal with no whitespace is a shell WORD, not prose, so it is emitted
# as code with its delimiters dropped), and each has a fixture in 8a below:
#
#     git "worktree" "remove" "--force" "$wt"     # quoted command words   -- NOW COUNTED
#     git worktree remove --for""ce "$wt"         # spliced empty literal  -- NOW COUNTED
#
# The third is `eval`, and it is STRUCTURAL -- unclosable by any quote-aware filter:
#
#     [[ -n "${SMUG:-}" ]] && eval "git worktree remove --force $wt"
#
# `eval` turns filter-DATA into CODE, and `eval "…"` is indistinguishable from `msg="…"` without
# a real shell parser. So it is not pretended closed: 8c bans `eval` in the helper OUTRIGHT
# (there is none today, and none is needed), which is the cheap structural answer. A green ban
# here therefore means "no forbidden verb in executable code AND no eval to launder one through",
# not "this script provably cannot force". Here-documents are the remaining known gap and are
# excluded by the `<<` assertion above.
CODEONLY="$SRC_DIR/tests/lib-shell-code-only.py"
[[ -f "$CODEONLY" ]] || fail "lib-shell-code-only.py missing at $CODEONLY"
# The filter does not parse here-documents; assert the target has none so it cannot mislead.
grep -qE '<<([^<]|$)' "$SH" && fail "worktree-retire.sh now contains a here-document; lib-shell-code-only.py does not parse those, so the force ban below would read heredoc BODY as code"

# 8a. the filter itself, both directions, on fixtures that really do execute (or really are prose)
selftest_dir="$TMP/codeonly"; mkdir -p "$selftest_dir"
cat > "$selftest_dir/smuggle.sh" <<'SMUGGLE'
msg=$(git worktree remove --force "$wt")
  msg=$(git worktree remove --force "$wt")
why=; git worktree remove --force "$wt"
hatch_refused="$(git worktree remove --force "$wt")"
echo "$(git worktree remove --force "$wt")"
log "$(git worktree remove --force "$wt")"
git "worktree" "remove" "--force" "$wt"
git worktree remove --for""ce "$wt"
git worktree remove '--force' "$wt"
SMUGGLE
# Every line above EXECUTES a real force. The last three were added 2026-09-01 (round 4): a
# quoted literal carrying no whitespace is a shell WORD, not prose -- after quote removal the
# shell runs it verbatim -- so the filter must emit it as code with the delimiters dropped.
n_smuggled="$(python3 "$CODEONLY" "$selftest_dir/smuggle.sh" | { grep -o -- 'worktree remove --force' || true; } | wc -l)"  # swallow-ok: zero matches is the FAILURE this asserts against, not an error
[[ "$n_smuggled" -eq 9 ]] \
  || fail "lib-shell-code-only.py hides a REAL force: 9 executing smuggle lines, only $n_smuggled survived the filter"
cat > "$selftest_dir/prose.sh" <<'PROSE'
# only 'git worktree remove --force' removes it, which is the op id:373e avoids
msg="git refuses to remove it without --force; a lock needs 'remove -f -f'"
  msg="... reset --hard / branch -D / git clean are all banned here ..."
why="the hatch did not fire, so no --force was issued"
hatch_refused="refusing to git worktree remove --force a tree we cannot account for"
echo "never run: git worktree remove --force"
log "surfaced: git worktree remove --force was NOT run"
submodule_refusal='fatal: working trees containing submodules cannot be moved or removed'
git -C "$repo" worktree remove "$wt"
[[ "$branch" == relay/* ]] && log "the force-free path; no --force was needed here"
PROSE
# The last two lines are the word-like rule's OTHER direction: `"$repo"`/`"$wt"`/`"$branch"` are
# word-like and are now emitted as code (correctly -- they ARE code), and that must not turn the
# legitimate force-FREE `worktree remove` into a ban hit.
n_prose="$(python3 "$CODEONLY" "$selftest_dir/prose.sh" | { grep -oE -- '--force|branch -D|reset --hard|git clean' || true; } | wc -l)"  # swallow-ok: zero matches is the PASSING case here
[[ "$n_prose" -eq 0 ]] \
  || fail "lib-shell-code-only.py flags PROSE as code ($n_prose hits): the ban would fire on legitimate surfaced text"
pass "shell-code filter verified both ways: 9/9 smuggled forces visible, 0 false positives on prose"

code="$(python3 "$CODEONLY" "$SH")"
# AMENDED 2026-09-01 (TODO id:a290, owner-ruled): ONE `git worktree remove --force` is now
# permitted — the narrow submodule escape hatch, which fires only after the helper has itself
# proved the tree CLEAN and the branch already merged, and only on git's verbatim submodule
# refusal (behaviour pinned by tests/test_submodule_force_hatch_a290.sh). Everything else in
# this ban is unchanged. Counting rather than allowing keeps it a ratchet: a second force, or a
# force anywhere but `worktree remove`, still fails here.
# Count OCCURRENCES, not matching lines: two forces on one line must read as two.
n_force="$({ grep -o -- '--force' <<<"$code" || true; } | wc -l)"  # swallow-ok: a zero count must reach the assertion below, not abort the run
n_wt_force="$({ grep -o -- 'worktree remove --force' <<<"$code" || true; } | wc -l)"  # swallow-ok: as above
[[ "$n_force" -eq 1 ]] \
  || fail "helper must carry EXACTLY ONE --force (the id:a290 submodule escape hatch); found $n_force"
[[ "$n_wt_force" -eq 1 ]] \
  || fail "helper's only permitted --force is 'git worktree remove --force' (id:a290); found $n_wt_force such"
grep -Eq -- 'branch[[:space:]]+-D\b|reset[[:space:]]+--hard|git[[:space:]]+(-C[[:space:]]+[^ ]+[[:space:]]+)?clean|git[[:space:]]+(-C[[:space:]]+[^ ]+[[:space:]]+)?stash' < <(printf '%s\n' "$code") \
  && fail "helper executes a forbidden force/destructive git verb"
pass "helper executes no forbidden destructive git verb (exactly one permitted a290 --force)"

# 8c. STRUCTURAL companion ban: no `eval`, anywhere in executable code.
# The verb ban above cannot see through `eval` -- `eval "git worktree remove --force $wt"` and
# `msg="git worktree remove --force $wt"` are the same shape to a quote-aware filter, because
# `eval` is exactly the construct that promotes filter-DATA to CODE. Rather than pretend the
# force ban covers it, ban the promotion primitive itself. The helper has never needed `eval`
# and does not use it; this keeps that true, and keeps the ban above meaningful. If `eval` ever
# becomes genuinely necessary here, this assertion is the deliberate stop that forces the
# question to be re-opened rather than quietly skipped.
grep -nE '(^|[[:space:];&|(])eval([[:space:]]|$)' <<<"$code" \
  && fail "worktree-retire.sh executes 'eval' -- that launders arbitrary text into code and makes the force ban above unenforceable. Rewrite without eval, or re-open the ban deliberately."
pass "helper contains no 'eval' (the one channel the quote-aware force ban structurally cannot cover)"

# ── 9. roadmap:8d76 — owner-authorized residue DISCARD (--discard-residue --ack <token>) ──
# This is the ONE path that destroys uncommitted work, so every guard is asserted. It exists
# because id:221f(a) moves `git * --force*` to deny, removing the raw command a human used to
# reach for; the capability has to survive that in an audited form.
export WORKTREE_RETIRE_ARCHIVE="$TMP/archive"

mkdirty() { # <name> — worktree with BOTH a tracked modification and an untracked file
  mkwt "$1"
  printf 'modified\n' >> "$WTBASE/$1/a.txt"
  printf 'untracked secret\n' > "$WTBASE/$1/leak.txt"
}

# 9a. no --ack → REFUSED, exit 3, nothing touched, and the token is printed for a second run.
mkdirty dr1
rc=0; out="$("$SH" "$REPO" "$WTBASE/dr1" "relay/dr1" --discard-residue 2>&1)" || rc=$?
[[ $rc -eq 3 ]] || fail "9a: no --ack should exit 3, got $rc"
[[ -e "$WTBASE/dr1/leak.txt" ]] || fail "9a: untracked residue must survive a refused discard"
grep -q 'REFUSED' <<<"$out" || fail "9a: refusal must say REFUSED"
grep -q -- '--ack ' <<<"$out" || fail "9a: refusal must print the token to use"
pass "9a: --discard-residue without --ack refuses (exit 3), residue intact, token printed"

# 9b. the refusal prints residue PATHS but never CONTENT — stdout is the agent transcript,
#     and the content may be exactly the private material being disposed of.
grep -q 'leak.txt' <<<"$out" || fail "9b: refusal should name the residue paths"
grep -q 'untracked secret' <<<"$out" && fail "9b: refusal must NEVER print residue CONTENT"
pass "9b: refusal names residue paths but never prints their content"

# 9c. WRONG/stale --ack → still refused. The token is bound to the residue's exact bytes.
rc=0; "$SH" "$REPO" "$WTBASE/dr1" "relay/dr1" --discard-residue --ack deadbeef1234 >/dev/null 2>&1 || rc=$?
[[ $rc -eq 3 ]] || fail "9c: stale --ack should exit 3, got $rc"
[[ -e "$WTBASE/dr1/leak.txt" ]] || fail "9c: residue must survive a stale-ack refusal"
pass "9c: a wrong --ack token refuses; residue intact"

# 9d. CORRECT --ack → residue destroyed, worktree removed, branch deleted, residue ARCHIVED
#     outside the repo. Extract the token from 9a's own refusal output (the documented flow).
# {8,} matters: the refusal ALSO contains the prose "--ack token.", and a `[0-9a-f]*` glob
# would match that with an EMPTY token and silently yield nothing.
tok="$(awk 'match($0, /--ack [0-9a-f][0-9a-f]+/) { print substr($0, RSTART+6, RLENGTH-6); exit }' <<<"$out")"
[[ -n "$tok" ]] || fail "9d: could not read the token out of the refusal message"
rc=0; out2="$("$SH" "$REPO" "$WTBASE/dr1" "relay/dr1" --discard-residue --ack "$tok" --expect-merged 2>&1)" || rc=$?
[[ $rc -eq 0 ]] || fail "9d: correct --ack should exit 0, got $rc ($out2)"
[[ ! -e "$WTBASE/dr1" ]] || fail "9d: worktree should be gone"
git -C "$REPO" show-ref --verify --quiet refs/heads/relay/dr1 && fail "9d: merged branch should be deleted"
ls "$WORKTREE_RETIRE_ARCHIVE"/*dr1* >/dev/null 2>&1 || fail "9d: residue must be archived"
grep -q 'untracked secret' "$WORKTREE_RETIRE_ARCHIVE"/*dr1* || fail "9d: archive must contain the discarded residue"
pass "9d: correct --ack discards the residue, retires the worktree, archives outside the repo"

# 9e. a NON-relay branch is never discarded from, however good the token.
git -C "$REPO" worktree add -q "$WTBASE/nr1" -b "mine/nr1"
printf 'mine\n' > "$WTBASE/nr1/untracked.txt"
rc=0; "$SH" "$REPO" "$WTBASE/nr1" "mine/nr1" --discard-residue --ack whatever >/dev/null 2>&1 || rc=$?
[[ $rc -eq 2 ]] || fail "9e: non-relay branch should be a usage refusal (exit 2), got $rc"
[[ -e "$WTBASE/nr1/untracked.txt" ]] || fail "9e: non-relay residue must be untouched"
pass "9e: --discard-residue refuses on a branch this helper does not own"

# 9f. --discard-residue and --commit-residue are mutually exclusive (one preserves, one destroys).
rc=0; "$SH" "$REPO" "$WTBASE/nr1" "relay/x" --discard-residue --commit-residue >/dev/null 2>&1 || rc=$?
[[ $rc -eq 2 ]] || fail "9f: mutually-exclusive flags should exit 2, got $rc"
pass "9f: --discard-residue + --commit-residue is refused as contradictory"

echo "ALL PASS"
