#!/usr/bin/env bash
# fails-against: tests/lint-pipefail-sigpipe.py before id:b818 (root.rglob("*.sh")
#   with only ".git/" pruned) — reverting the iter_shell_files() nested-checkout
#   pruning added for id:b818 makes case (1) below flag the fixture worktree file
#   and go RED.
#
# No `# roadmap:` header: this specs a test-infrastructure DEFECT (id:b818), not an
# open ROADMAP item, so its failures always count per CLAUDE.md's Testing section.
#
# id:b818 — the SIGPIPE lint's whole-tree walk (root.rglob("*.sh")) descended into
# ANY nested git checkout under the scanned root, most concretely
# `.claude/worktrees/<agent>/…` — where the Agent tool's `isolation: worktree`
# places a full second checkout of a DIFFERENT branch. A clean `main` therefore read
# as RED whenever a sibling agent's in-flight WIP happened to contain an at-risk
# site, and the suite result became non-deterministic across runs (id:b818, TODO.md).
#
# Contract asserted here (both halves):
#   (1) an unrelated NESTED checkout containing an at-risk site is IGNORED — the
#       scan over the outer root must be clean.
#   (2) the SAME at-risk site, when it lives in the tree actually UNDER TEST (the
#       outer root, however deep, as long as no nested `.git` boundary is crossed),
#       is STILL CAUGHT — the fix must not just stop scanning.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LINT="$ROOT/tests/lint-pipefail-sigpipe.py"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$LINT" ]] || fail "lint-pipefail-sigpipe.py not found at $LINT"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

mk_at_risk() {  # mk_at_risk <path>
  mkdir -p "$(dirname "$1")"
  { printf '#!/usr/bin/env bash\nset -euo pipefail\n'
    printf 'cat /etc/hosts | grep -q localhost\n'
  } > "$1"
}

outer="$tmpdir/outer-repo"
mkdir -p "$outer"

# ------------------------------------------------------------------------ case (1)
# An at-risk site ONLY inside a nested checkout (mimicking .claude/worktrees/<agent>)
# must not surface when scanning the outer root — the outer root itself is clean.
nested="$outer/.claude/worktrees/agent-sibling-example"
mkdir -p "$nested"
: > "$nested/.git"   # a `.git` FILE marks a worktree checkout, same as a real one
mk_at_risk "$nested/relay/scripts/some-wip-script.sh"

if out="$(python3 "$LINT" "$outer" 2>&1)"; then
  pass "case (1): at-risk site confined to a nested checkout is IGNORED"
else
  echo "$out"
  fail "case (1): scanning outer root flagged a site that lives ONLY in a nested checkout — the linter is not hermetic w.r.t. sibling worktrees"
fi

# ------------------------------------------------------------------------ case (2)
# The SAME shape, in-tree (no nested `.git` boundary between it and the root), must
# still be caught — the fix must not have just stopped scanning altogether.
mk_at_risk "$outer/relay/scripts/in-tree-script.sh"

if out="$(python3 "$LINT" "$outer" 2>&1)"; then
  echo "$out"
  fail "case (2): an in-tree at-risk site (same repo, no nested-checkout boundary) was NOT caught — the fix over-pruned"
else
  grep -q "in-tree-script.sh" <<< "$out" \
    || fail "case (2): lint failed, but not on the expected in-tree site: $out"
  grep -q "some-wip-script.sh" <<< "$out" \
    && fail "case (2): the nested-checkout site was ALSO reported — the fix did not prune it"
  pass "case (2): in-tree at-risk site is STILL CAUGHT, nested-checkout site stays excluded"
fi

echo "ALL PASS"
