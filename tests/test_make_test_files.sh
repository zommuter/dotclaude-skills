#!/usr/bin/env bash
# roadmap:d3f8 — `make test FILES="tests/test_a.sh tests/test_b.sh"` runs exactly
# those files with unchanged PASS/FAIL/EXPECTED-RED semantics; `make test` with no
# FILES is byte-identical in behaviour (same recipe line) to the un-parameterised
# suite. Uses two REAL suite files as fixtures rather than a fabricated ROADMAP.md,
# because tests/run-tests.sh resolves ROADMAP.md relative to its own location, not
# an overridable env var — a fixture repo would silently check against the WRONG
# ledger.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pass_fixture="$ROOT/tests/test_makefile_skills.sh"      # a real, currently-green test
red_fixture="$ROOT/tests/test_md_merge_own_id_last.sh"  # roadmap:cc7e, currently open+RED

[[ -f "$pass_fixture" ]] || { echo "fixture missing: $pass_fixture"; exit 1; }
[[ -f "$red_fixture" ]] || { echo "fixture missing: $red_fixture"; exit 1; }
grep -qE '^- \[ \] .*<!-- id:cc7e -->' "$ROOT/ROADMAP.md" \
  || { echo "fixture precondition failed: id:cc7e is no longer an open ROADMAP item — pick a different currently-open RED fixture"; exit 1; }

out="$(make -C "$ROOT" -s FILES="$pass_fixture $red_fixture" test 2>&1)" \
  || { echo "make test FILES=... exited non-zero on a pass+expected-red pair"; echo "$out"; exit 1; }
grep -q "PASS   test_makefile_skills.sh" <<<"$out" \
  || { echo "pass fixture not reported PASS"; echo "$out"; exit 1; }
grep -q "EXPECTED-RED test_md_merge_own_id_last.sh" <<<"$out" \
  || { echo "red fixture not reported EXPECTED-RED"; echo "$out"; exit 1; }
grep -q "^summary: 1 passed, 0 failed, 1 expected-red" <<<"$out" \
  || { echo "summary line does not show exactly the two fixture files (FILES= didn't scope the run)"; echo "$out"; exit 1; }

# `make test` with no FILES stays the full suite: the recipe line run-tests.sh actually
# sees carries no extra args — FILES defaults empty, never accidentally narrowing.
plain="$(make -C "$ROOT" -s -n test)"
grep -qE 'tests/run-tests\.sh[[:space:]]*$' <<<"$plain" \
  || { echo "no-FILES 'make test' recipe line changed shape: $plain"; exit 1; }

echo ok
