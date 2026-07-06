#!/usr/bin/env bash
# roadmap:25aa — integrator `-c` anchor: when a review/recheck branch CARRIES commits, the
# checkpoint tag must anchor on the POST-MERGE tip (the run's own merged commits inside the
# audited window), NOT on the child's branch tip / base. This is the carries-commits COMPLEMENT
# of id:8e3e (zero-commit branch → tag the reviewed tip, unchanged). Folds TODO id:962d
# (llm-from-scratch second occurrence: tag pointed at the previous checkpoint commit instead of
# its own post-merge commit).
#
# The integrate() `-c` decision lives inside an LLM agent prompt (relay-loop.js), so this file
# pins it two ways: (A) a STRUCTURE check that the prompt states the merged-tip rule symmetrically
# and warns against carrying `-c <reviewedTip>` into the carries-commits case; (B) a hermetic
# BEHAVIORAL fixture that the mechanism the prompt now relies on — default ckpt-tag (no -c) after
# a --no-ff merge — actually lands the tag on the post-merge tip that CONTAINS the merged commits.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JS="$SRC_DIR/relay/scripts/relay-loop.js"
CT="$SRC_DIR/relay/scripts/ckpt-tag.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$JS" ]] || fail "relay-loop.js not found at $JS"
[[ -x "$CT" ]] || fail "ckpt-tag.sh not found/executable at $CT"

# --- engine-edit safety: the whole file must still parse (template-literal-lint hazard) ---
command -v node >/dev/null && {
  node --check "$JS" || fail "relay-loop.js fails node --check"
  LINT="$SRC_DIR/relay/scripts/lint-workflow-templates.mjs"
  [[ -f "$LINT" ]] && { node "$LINT" "$JS" >/dev/null || fail "relay-loop.js fails the template-literal lint"; }
}
pass "relay-loop.js parses + template-lint clean"

# --- (A) structure: the integrate() prompt states the carries-commits merged-tip rule ---
# The zero-commit id:8e3e rule stays; the id:25aa carries-commits complement is added symmetrically.
grep -q 'id:8e3e' "$JS" || fail "id:8e3e zero-commit rule text vanished from the integrate() prompt"
grep -q 'id:25aa' "$JS" || fail "id:25aa carries-commits rule missing from the integrate() prompt"
# The carries-commits branch must anchor on the POST-MERGE tip.
grep -qi 'post-merge tip' "$JS" \
  || fail "id:25aa: integrate() prompt must name the POST-MERGE tip as the carries-commits anchor"
# It must explicitly warn against carrying the zero-commit `-c <reviewedTip>` into this case
# (anchoring behind the merge = the run's own commits outside the audited window forever).
grep -qi 'OUTSIDE the audited window' "$JS" \
  || fail "id:25aa: prompt must warn that -c <reviewedTip> here leaves merged commits OUTSIDE the audited window"
pass "(A) integrate() prompt states the carries-commits merged-tip rule symmetrically to id:8e3e"

# --- (B) behavioral: default ckpt-tag (no -c) after a --no-ff merge tags the post-merge tip ---
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export FABLES_CONFIG="$TMP/cfg"   # hermetic: no relay.toml → watermark sync is a logged no-op

R="$TMP/repo"; mkdir -p "$R"
git -C "$R" init -q
git -C "$R" config user.email t@e.st
git -C "$R" config user.name t
echo base > "$R/f"; git -C "$R" add -A; git -C "$R" commit -qm base
base="$(git -C "$R" rev-parse HEAD)"

# A review/recheck child branch that CARRIED commits (REVIEW_ME prune + its own RELAY_LOG commit).
git -C "$R" checkout -q -b relay/review-x
echo prune > "$R/REVIEW_ME.md"; git -C "$R" add -A; git -C "$R" commit -qm "prune REVIEW_ME"
echo log > "$R/RELAY_LOG.md"; git -C "$R" add -A; git -C "$R" commit -qm "child RELAY_LOG"
branch_tip="$(git -C "$R" rev-parse HEAD)"

# Integrator step 2: --no-ff merge onto main → a merge commit is the new post-merge tip.
git -C "$R" checkout -q master 2>/dev/null || git -C "$R" checkout -q main
git -C "$R" merge --no-ff relay/review-x -m "merge(relay): review-x" -q
merge_commit="$(git -C "$R" rev-parse HEAD)"
[[ "$merge_commit" != "$branch_tip" ]] || fail "(B) fixture: --no-ff did not create a merge commit"

# Integrator step 3, carries-commits case: DEFAULT ckpt-tag (NO -c).
tag="$("$CT" "$R" -m "carries-commits recheck checkpoint" -l "reviewer (claude-opus-4-8, integrate)" 2>/dev/null)" \
  || fail "(B) ckpt-tag.sh failed"
tag_target="$(git -C "$R" rev-parse "$tag^{commit}")"

# The tag must land on the post-merge tip, and that tip must CONTAIN the merge (and thus the
# child's own merged commits) — never behind it on the base or the pre-merge branch tip.
[[ "$tag_target" != "$base" ]] \
  || fail "(B) tag anchored on the BASE commit — the run's own merged commits sit outside the audited window (id:25aa bug)"
[[ "$tag_target" != "$branch_tip" ]] \
  || fail "(B) tag anchored on the pre-merge branch tip, behind the merge commit (id:25aa bug)"
git -C "$R" merge-base --is-ancestor "$merge_commit" "$tag_target" \
  || fail "(B) tag target does not contain the --no-ff merge commit — merged commits are unaudited (id:25aa bug)"
git -C "$R" merge-base --is-ancestor "$branch_tip" "$tag_target" \
  || fail "(B) tag target does not contain the child's own commits (id:25aa bug)"
pass "(B) default ckpt-tag after --no-ff merge anchors on the post-merge tip containing the merged commits"

echo "ALL PASS: roadmap:25aa integrator -c merged-tip anchor (carries-commits complement of id:8e3e)"
