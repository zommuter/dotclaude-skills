#!/usr/bin/env bash
# tests/mutations/a73c-exit-status-only.sh -- the declared negative case of
# tests/test_negative_case_runner_a73c.sh.
#
# It reverts tests/verify-negative-cases.py to MECHANISM-(1)-EQUIVALENT behaviour: any
# non-zero exit against the declared revision/mutation counts as proof, regardless of WHICH
# assertion fired. That is precisely the blind spot TODO id:a73c exists to close, and it is
# the behaviour under which all three of the 2026-09-01 live instances looked fine.
#
# A mutation script is run by the runner with cwd = a SCRATCH COPY of the tree; it must never
# be run against a real checkout. Exits non-zero (loudly) if the anchor line is not found --
# a mutation that silently no-ops is itself a vacuous fixture.
set -euo pipefail

target="tests/verify-negative-cases.py"
anchor='        hit = [w for w in wanted if fl and w in fl[-1]]'

[[ -f "$target" ]] || { echo "mutation: $target not found (cwd=$PWD)" >&2; exit 2; }
grep -qF "$anchor" "$target" || {
  echo "mutation: anchor line not found in $target -- the mutation would silently no-op." >&2
  echo "          anchor: $anchor" >&2
  exit 2
}
python3 - "$target" "$anchor" <<'PY'
import sys
path, anchor = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8").read()
mutant = "        hit = [True]  # MUTANT (a73c): exit status alone counts as proof\n"
open(path, "w", encoding="utf-8").write(text.replace(anchor + "\n", mutant, 1))
PY
