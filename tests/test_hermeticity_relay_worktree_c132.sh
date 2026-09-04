#!/usr/bin/env bash
# roadmap:c132
#
# RED SPEC for ROADMAP id:c132 -- authored by relay handoff C3, 2026-09-04. It is red
# today by construction; its redness IS the spec while the item is open.
#
# No `# fails-against-*` declaration: this is a roadmap-spec file, and
# `tests/verify-negative-cases.py` skips that bucket while the item is open (id:7c82).
#
# THE DEFECT, observed live 2026-09-04. `make test` reported a HERMETICITY BREACH
# (id:b54b) while all 578 tests passed. Nothing leaked: the drift was a RELAY worktree,
# created by a concurrent `/relay review` child in its documented location.
#
# `tests/run-tests.sh`'s `snapshot_repo_state()` already excludes harness worktrees under
# `.claude/worktrees/`, with a comment saying why: an agent starting or finishing mid-run
# would otherwise trip a SPURIOUS breach. That reasoning applies verbatim to relay
# worktrees, which live under `$RELAY_WORKTREE_BASE` (default `~/.cache/relay/worktrees`)
# -- deliberately outside the repo tree, per the relay SKILL.md invariant 4 -- and are not
# excluded. Any `/relay` run concurrent with `make test` therefore reports a breach, which
# is the pool's normal shape, and a guard that fires on legitimate activity trains the
# operator to ignore it.
#
# DERIVE THE PATH, DO NOT HARDCODE IT. A literal `~/.cache/relay/worktrees` here would
# repeat id:d4d3 -- a path constant that silently stops matching when the location moves.
# Case (A) runs with `RELAY_WORKTREE_BASE` pointed somewhere else entirely, so a
# hardcoded literal cannot satisfy it.
#
# DO NOT WEAKEN IT FURTHER. Excluding one well-known external root is not the same as
# making the backstop advisory: cases (B) and (C) pin that a worktree or a `relay/*` ref
# leaked INTO the cwd repo still fails the suite unconditionally.
#
# Drives the REAL tests/run-tests.sh against a throwaway git repo; the live repo is only
# read. Hermetic: everything happens under mktemp, no network.
set -uo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_TESTS="$SRC_DIR/tests/run-tests.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$RUN_TESTS" ]] || fail "setup: run-tests.sh not found at $RUN_TESTS"

TMP="$(mktemp -d)"; trap 'rm -rf -- "$TMP"' EXIT

REPO="$TMP/scratch-repo"
git init -q -b main "$REPO"
git -C "$REPO" config user.email t@e.st
git -C "$REPO" config user.name t
echo base >"$REPO/f"
git -C "$REPO" add -A
git -C "$REPO" commit -qm base
mkdir -p "$REPO/tests"

# The relay worktree root for this run: NOT the default location, so nothing can satisfy
# case (A) by matching a hardcoded literal.
RELAY_BASE="$TMP/relay-root/worktrees"
mkdir -p "$RELAY_BASE"

# A fixture standing in for a concurrent relay child that registers its worktree in the
# MIDDLE of the suite run -- the exact timing that makes this drift, rather than a
# pre-existing worktree the before-snapshot would already contain.
cat >"$REPO/tests/test_relay_child_starts.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
git branch relay/20260904-child
git worktree add -q "$RELAY_BASE/scratch-repo/relay-20260904-child" relay/20260904-child
echo "ALL PASS: concurrent relay child fixture (intentional, for the c132 spec)"
EOF
chmod +x "$REPO/tests/test_relay_child_starts.sh"

# =====================================================================================
# (A) THE DEFECT: a relay worktree appearing mid-run is NOT a breach.
# =====================================================================================
rc=0
out="$(cd "$REPO" && RELAY_WORKTREE_BASE="$RELAY_BASE" bash "$RUN_TESTS" \
        "$REPO/tests/test_relay_child_starts.sh" 2>&1)" || rc=$?
if grep -q 'HERMETICITY BREACH' <<<"$out"; then
  fail "(A) a relay worktree under \$RELAY_WORKTREE_BASE tripped the hermeticity backstop -- \`.claude/worktrees/\` is excluded for this exact stated reason and the relay root is not"
fi
[[ $rc -eq 0 ]] || fail "(A) run-tests.sh exited $rc although only a relay worktree appeared: $out"
pass "(A) a relay worktree registered mid-run does not trip the backstop"

# Retire the relay worktree before the control cases so each starts clean.
git -C "$REPO" worktree remove --force "$RELAY_BASE/scratch-repo/relay-20260904-child" >/dev/null 2>&1 || true
git -C "$REPO" worktree prune >/dev/null 2>&1 || true
git -C "$REPO" branch -D relay/20260904-child >/dev/null 2>&1 || true

# =====================================================================================
# (B) THE CONTROL: a worktree leaked INSIDE the cwd repo still fails, unconditionally.
# =====================================================================================
cat >"$REPO/tests/test_inrepo_worktree_leak.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
git branch relay/in-repo-leak
git worktree add -q "$REPO/leaked-here" relay/in-repo-leak
echo "ALL PASS: in-repo leak fixture (intentional, for the c132 spec)"
EOF
chmod +x "$REPO/tests/test_inrepo_worktree_leak.sh"
rc=0
out="$(cd "$REPO" && RELAY_WORKTREE_BASE="$RELAY_BASE" bash "$RUN_TESTS" \
        "$REPO/tests/test_inrepo_worktree_leak.sh" 2>&1)" || rc=$?
[[ $rc -ne 0 ]] || fail "(B) run-tests.sh exited 0 despite a fixture leaking a worktree into the cwd repo -- the exclusion widened the guard instead of narrowing it"
grep -q 'HERMETICITY BREACH' <<<"$out" || fail "(B) no HERMETICITY BREACH for an in-repo worktree leak: $out"
pass "(B) an in-repo worktree leak still fails the suite"

git -C "$REPO" worktree remove --force "$REPO/leaked-here" >/dev/null 2>&1 || true
git -C "$REPO" worktree prune >/dev/null 2>&1 || true
git -C "$REPO" branch -D relay/in-repo-leak >/dev/null 2>&1 || true

# =====================================================================================
# (C) THE OTHER HALF OF THE SNAPSHOT: a leaked relay/* ref is untouched by this change.
# =====================================================================================
cat >"$REPO/tests/test_ref_leak.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
git branch relay/leaked-ref
echo "ALL PASS: ref leak fixture (intentional, for the c132 spec)"
EOF
chmod +x "$REPO/tests/test_ref_leak.sh"
rc=0
out="$(cd "$REPO" && RELAY_WORKTREE_BASE="$RELAY_BASE" bash "$RUN_TESTS" \
        "$REPO/tests/test_ref_leak.sh" 2>&1)" || rc=$?
[[ $rc -ne 0 ]] || fail "(C) a leaked relay/* ref no longer fails the suite -- the worktree exclusion must not touch the ref half of the snapshot"
grep -q 'refs/heads/relay/leaked-ref' <<<"$out" || fail "(C) the breach report did not name the leaked ref: $out"
pass "(C) a leaked relay/* ref still fails the suite and is named"

echo "ALL PASS: id:c132 relay worktrees are excluded from the hermeticity backstop"
