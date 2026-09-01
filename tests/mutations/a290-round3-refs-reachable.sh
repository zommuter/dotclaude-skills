#!/usr/bin/env bash
# tests/mutations/a290-round3-refs-reachable.sh -- the declared negative case of
# tests/test_submodule_force_hatch_a290.sh's DANGLING-OBJECT axis (case V).
#
# It narrows guard 5 back to the ROUND-3 question: instead of "does every gitlink MERGED
# SUPERPROJECT HISTORY names still resolve after the force", it only considers gitlinks that the
# private store's OWN REFS reach. That is the exact blind spot the owner's 2026-09-01 option (B)
# ruling exists to close: an executor bumps a submodule, the bump is merged, then it AMENDS the
# submodule commit -- the original object goes DANGLING, is invisible to `rev-list --all`, and the
# force destroys an object a merged commit on main still names.
#
# DELIBERATELY NARROW. The full round-3 predicate ALSO refused whenever a private store had no
# shared counterpart (the over-refusal case S), and a mutant carrying that half too would die at
# case S -- an earlier assertion than the one this case claims to pin, i.e. red for the wrong
# reason. This mutant leaves the over-refusal fix intact so case V is what fires.
#
# Run with cwd = a SCRATCH COPY of the tree; never against a real checkout. Exits non-zero if the
# anchor is missing: a mutation that silently no-ops is itself a vacuous fixture.
set -euo pipefail

target="relay/scripts/worktree-retire.sh"
anchor='      (( rc == 0 )) || continue          # the force cannot destroy what this store does not hold'
extra='      _r3="$(GIT_WORK_TREE="$store" git --git-dir="$store" rev-list --all 2>/dev/null || true)"; grep -Fxq "$sha" <<<"$_r3" || continue'

[[ -f "$target" ]] || { echo "mutation: $target not found (cwd=$PWD)" >&2; exit 2; }
grep -qF "$anchor" "$target" || {
  echo "mutation: anchor line not found in $target -- the mutation would silently no-op." >&2
  echo "          anchor: $anchor" >&2
  exit 2
}
python3 - "$target" "$anchor" "$extra" <<'PY'
import sys
path, anchor, extra = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path, encoding="utf-8").read()
open(path, "w", encoding="utf-8").write(text.replace(anchor + "\n", anchor + "\n" + extra + "\n", 1))
PY
