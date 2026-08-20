#!/usr/bin/env bash
# roadmap:9e50 — relay/scripts/integrate.sh, the standalone MECHANICAL integrator (seam of
# id:a955). Pins the three properties the acceptance names:
#
#   (A) FULL SEQUENCE, hermetic: lease-release → clean-tree → verify-isolation → sync-origin
#       → merge --no-ff → version-bump → changelog-append → ckpt-tag → git-lock-push →
#       worktree-retire → state-write, against a mktemp fixture repo (bare origin + main
#       checkout + child worktree). Only the network step (git-lock-push) is stubbed, with an
#       invocation-recording stub so its firing is still asserted.
#   (B) FAIL-CLOSED, DISTINCT EXITS, main unmoved: a forced non-zero injected at FOUR distinct
#       steps each yields a DISTINCT non-zero exit + a loud HANDBACK[<step>] line, and leaves
#       main's HEAD unmoved (all injected pre-merge, so "unmoved" is meaningful).
#   (C) id:aa93 enforced IN-SCRIPT (foreign-dirty main is DEFERRED, never force-cleaned — the
#       dirty file survives byte-for-byte, no merge lands) and id:6e02 cleanup scope (an
#       unrelated relay worktree SURVIVES a successful integrate — only the named pair retires).
set -uo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INT="$SRC_DIR/relay/scripts/integrate.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$INT" ]] || fail "integrate.sh not found/executable at $INT"
bash -n "$INT" || fail "integrate.sh fails bash -n"

# integrate.sh must contain NO destructive tree op (id:aa93 enforced structurally, not in a
# comment). We check the CODE lines, tolerating the header comment that names them.
if grep -vE '^\s*#' "$INT" | grep -qE 'git .*(stash|reset --hard|checkout --|clean -[a-z])'; then
  fail "id:aa93: integrate.sh contains a destructive tree op in a code line"
fi
pass "structure: parses, and no destructive tree op in any code line (id:aa93)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ── shared hermetic origin + main checkout builder ──
build_fixture() { # <dir-suffix> → sets MAIN, ORIGIN, prints main checkout path
  local sfx="$1"
  local origin="$TMP/origin-$sfx.git"
  local seed="$TMP/seed-$sfx"
  local main="$TMP/myrepo-$sfx"
  git init --bare -b main -q "$origin"
  git clone -q "$origin" "$seed" 2>/dev/null
  git -C "$seed" config user.email t@e.st
  git -C "$seed" config user.name t
  echo base > "$seed/f"
  git -C "$seed" add -A
  git -C "$seed" commit -qm base
  git -C "$seed" push -q -u origin main
  git clone -q "$origin" "$main" 2>/dev/null
  git -C "$main" config user.email t@e.st
  git -C "$main" config user.name t
  echo "$main"
}

# =====================================================================================
# (A) FULL SEQUENCE — happy path
# =====================================================================================
MAIN="$(build_fixture happy)"
WT="$TMP/wt-child"
WT_OTHER="$TMP/wt-other"       # an UNRELATED relay worktree — must survive (id:6e02)

git -C "$MAIN" worktree add -q -b relay/x "$WT" main
echo work > "$WT/g"
git -C "$WT" add -A
git -C "$WT" commit -qm "child work id:test"
CHILD_SHA="$(git -C "$WT" rev-parse HEAD)"

git -C "$MAIN" worktree add -q -b relay/other "$WT_OTHER" main

# hermetic relay config with the [repos.myrepo-happy] block state-write + ckpt-tag update
CFG="$TMP/cfg"; mkdir -p "$CFG"
REPO_NAME="$(basename "$MAIN")"
printf '[repos.%s]\nstatus = "active"\n' "$REPO_NAME" > "$CFG/relay.toml"

# stub the ONLY network step, recording that it fired
PUSH_MARK="$TMP/push-fired"
PUSH_STUB="$TMP/push-stub.sh"
cat > "$PUSH_STUB" <<EOF
#!/usr/bin/env bash
echo "\$@" > "$PUSH_MARK"
exit 0
EOF
chmod +x "$PUSH_STUB"

rc=0
out="$(FABLES_CONFIG="$CFG" INTEGRATE_GIT_LOCK_PUSH="$PUSH_STUB" \
  "$INT" --repo "$REPO_NAME" --path "$MAIN" --worktree "$WT" --branch relay/x \
         --summary "test close id:test" --run testrun \
         --label "reviewer (claude-opus-4-8, integrate)" --ids test --level patch \
         --verdict execute 2>&1)" || rc=$?
[[ $rc -eq 0 ]] || fail "(A) full sequence exited non-zero ($rc): $out"

# merge landed: the child's commit is now an ancestor of main HEAD
git -C "$MAIN" merge-base --is-ancestor "$CHILD_SHA" HEAD \
  || fail "(A) child commit is not an ancestor of main HEAD — merge did not land"
# main HEAD is past the merge: it must be a --no-ff merge OR carry the ckpt commit on top
git -C "$MAIN" log --oneline | grep -q 'merge(relay): test close id:test' \
  || fail "(A) no --no-ff merge commit on main"
# ckpt-tag fired
git -C "$MAIN" tag -l 'relay-ckpt-*' | grep -q . \
  || fail "(A) no relay-ckpt-* tag created"
CKPT="$(git -C "$MAIN" tag -l 'relay-ckpt-*' | tail -n1)"
# git-lock-push fired
[[ -f "$PUSH_MARK" ]] || fail "(A) git-lock-push step did not fire"
grep -q -- '--ff-only' "$PUSH_MARK" || fail "(A) git-lock-push not called with --ff-only"
# state-write updated relay.toml last_ckpt for THIS repo's block
grep -qF "last_ckpt = \"$CKPT\"" "$CFG/relay.toml" \
  || fail "(A) relay.toml last_ckpt not synced to $CKPT (state-write step)"
# worktree-retire removed the named worktree + merged branch
[[ ! -d "$WT" ]] || fail "(A) child worktree not retired (still on disk)"
git -C "$MAIN" show-ref --verify -q refs/heads/relay/x \
  && fail "(A) merged child branch relay/x not deleted by retire"
# id:6e02: the UNRELATED worktree + branch SURVIVE (only the named pair was retired)
[[ -d "$WT_OTHER" ]] || fail "(A/6e02) unrelated worktree was swept — id:6e02 scope violated"
git -C "$MAIN" show-ref --verify -q refs/heads/relay/other \
  || fail "(A/6e02) unrelated branch relay/other was deleted — id:6e02 scope violated"
# machine-readable success line
grep -q "merged=" <<<"$out" || fail "(A) no machine-readable merged= line on stdout"
pass "(A) full 11-step sequence integrates hermetically; ckpt tagged, state synced, id:6e02 scope respected"

# =====================================================================================
# (B) FAIL-CLOSED — forced non-zero at FOUR distinct steps → distinct exit, main unmoved
# =====================================================================================
mk_stub() { # <path> <exit-code> [stdout-line]
  cat > "$1" <<EOF
#!/usr/bin/env bash
${3:+echo "$3"}
exit $2
EOF
  chmod +x "$1"
}
PASS_STUB="$TMP/ok.sh";       mk_stub "$PASS_STUB" 0 "clean"
FAIL_STUB="$TMP/bad.sh";      mk_stub "$FAIL_STUB" 1 "boom"
DIVERGE_STUB="$TMP/div.sh";   mk_stub "$DIVERGE_STUB" 3 "diverged 1 1"

MAINB="$(build_fixture fail)"
git -C "$MAINB" worktree add -q -b relay/y "$TMP/wt-y" main
echo w > "$TMP/wt-y/h"; git -C "$TMP/wt-y" add -A; git -C "$TMP/wt-y" commit -qm "y id:test"

run_expect() { # <label> <expected-exit> <expected-step-in-msg> <env-overrides...>
  local label="$1" want="$2" step="$3"; shift 3
  local before after rc=0 msg
  before="$(git -C "$MAINB" rev-parse HEAD)"
  msg="$(env "$@" "$INT" --repo x --path "$MAINB" --worktree "$TMP/wt-y" --branch relay/y \
           --summary "s id:test" --run r --label "reviewer (claude-opus-4-8, integrate)" 2>&1)" || rc=$?
  after="$(git -C "$MAINB" rev-parse HEAD)"
  [[ $rc -eq $want ]]        || fail "(B/$label) expected exit $want, got $rc — $msg"
  grep -q "HANDBACK\[$step\]" <<<"$msg" || fail "(B/$label) missing loud HANDBACK[$step] — $msg"
  [[ "$before" == "$after" ]] || fail "(B/$label) main HEAD MOVED ($before → $after) on a pre-merge failure"
}

# clean-tree fails → exit 20
run_expect clean-tree 20 clean-tree \
  INTEGRATE_CLEAN_TREE_GATE="$FAIL_STUB"
# clean-tree ok, verify-isolation fails → exit 21
run_expect verify-isolation 21 verify-isolation \
  INTEGRATE_CLEAN_TREE_GATE="$PASS_STUB" INTEGRATE_VERIFY_ISOLATION="$FAIL_STUB"
# clean-tree + isolation ok, sync-origin reports diverged → exit 22
run_expect sync-origin 22 sync-origin \
  INTEGRATE_CLEAN_TREE_GATE="$PASS_STUB" INTEGRATE_VERIFY_ISOLATION="$PASS_STUB" \
  INTEGRATE_SYNC_ORIGIN="$DIVERGE_STUB"
# a fourth distinct step: force a merge conflict → exit 23, main unmoved (merge --abort)
# create a conflicting commit on main so relay/y cannot merge cleanly
git -C "$MAINB" checkout -q main
echo mainside > "$MAINB/h"; git -C "$MAINB" add -A; git -C "$MAINB" commit -qm "conflict seed"
run_expect merge 23 merge \
  INTEGRATE_CLEAN_TREE_GATE="$PASS_STUB" INTEGRATE_VERIFY_ISOLATION="$PASS_STUB" \
  INTEGRATE_SYNC_ORIGIN="$PASS_STUB"
pass "(B) forced failure at 4 distinct steps → distinct exits 20/21/22/23, loud handbacks, main unmoved"

# =====================================================================================
# (C) id:aa93 — REAL clean-tree gate + foreign-dirty main → DEFER, never force-clean
# =====================================================================================
MAINC="$(build_fixture aa93)"
git -C "$MAINC" worktree add -q -b relay/z "$TMP/wt-z" main
echo w > "$TMP/wt-z/k"; git -C "$TMP/wt-z" add -A; git -C "$TMP/wt-z" commit -qm "z id:test"
# a FOREIGN tracked-but-unstaged edit on main (a concurrent editor's work)
printf 'FOREIGN-EDIT-DO-NOT-DESTROY\n' > "$MAINC/f"
FOREIGN_BEFORE="$(cat "$MAINC/f")"
HEAD_BEFORE="$(git -C "$MAINC" rev-parse HEAD)"

rc=0
msg="$(FABLES_CONFIG="$TMP/cfg-aa93" INTEGRATE_GIT_LOCK_PUSH="$PUSH_STUB" \
  "$INT" --repo x --path "$MAINC" --worktree "$TMP/wt-z" --branch relay/z \
         --summary "s id:test" --run r --label "reviewer (claude-opus-4-8, integrate)" 2>&1)" || rc=$?
[[ $rc -eq 20 ]] || fail "(C/aa93) foreign-dirty main must exit 20 (clean-tree defer), got $rc — $msg"
grep -q 'HANDBACK\[clean-tree\]' <<<"$msg" || fail "(C/aa93) missing loud HANDBACK[clean-tree] — $msg"
# the foreign edit SURVIVES byte-for-byte (never stashed/checked-out/reset/cleaned)
[[ "$(cat "$MAINC/f")" == "$FOREIGN_BEFORE" ]] \
  || fail "(C/aa93) FOREIGN edit was destroyed — integrate.sh force-cleaned a dirty tree"
# no merge landed
[[ "$(git -C "$MAINC" rev-parse HEAD)" == "$HEAD_BEFORE" ]] \
  || fail "(C/aa93) main HEAD moved despite the clean-tree defer"
git -C "$MAINC" merge-base --is-ancestor "$(git -C "$TMP/wt-z" rev-parse HEAD)" HEAD \
  && fail "(C/aa93) child commit landed on main despite the defer"
pass "(C) id:aa93: foreign-dirty main is DEFERRED (exit 20), foreign edit survives, no merge"

echo "ALL PASS: roadmap:9e50 integrate.sh mechanized integrator (full sequence + fail-closed + aa93/6e02)"
