#!/usr/bin/env bash
# tests/mutations/a290-strip-locale-pin.sh -- the declared negative case of
# tests/test_submodule_force_hatch_a290.sh's locale axis (case L).
#
# It removes the `LC_ALL=C` pin from the submodule-refusal PROBE in worktree-retire.sh. git's
# refusal is a TRANSLATED string, so without the pin the verbatim comparison misses under a
# non-C locale and the hatch falls through to the generic dirty-tree advice that id:a290
# exists to eliminate. This is the mutant that case L must kill -- and that a fixture-sanity
# probe killed FIRST until the harness pinned its own locale (TODO id:a73c instance (b)).
#
# Run with cwd = a SCRATCH COPY of the tree; never against a real checkout. Exits non-zero if
# the anchor is missing: a mutation that silently no-ops is itself a vacuous fixture.
set -euo pipefail

target="relay/scripts/worktree-retire.sh"
anchor='  if err="$(LC_ALL=C git -C "$repo" worktree remove "$wt" 2>&1)"; then'
mutant='  if err="$(git -C "$repo" worktree remove "$wt" 2>&1)"; then'

[[ -f "$target" ]] || { echo "mutation: $target not found (cwd=$PWD)" >&2; exit 2; }
grep -qF "$anchor" "$target" || {
  echo "mutation: anchor line not found in $target -- the mutation would silently no-op." >&2
  echo "          anchor: $anchor" >&2
  exit 2
}
python3 - "$target" "$anchor" "$mutant" <<'PY'
import sys
path, anchor, mutant = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path, encoding="utf-8").read()
open(path, "w", encoding="utf-8").write(text.replace(anchor + "\n", mutant + "\n", 1))
PY
