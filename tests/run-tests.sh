#!/usr/bin/env bash
# run-tests.sh — plain-bash test runner for dotclaude-skills.
#
# Usage:
#   tests/run-tests.sh                      # full suite
#   tests/run-tests.sh tests/test_foo.sh …  # subset
#
# Each tests/test_*.sh is an independent bash script: exit 0 = pass.
# Expected-red semantics (see CLAUDE.md §Testing):
#   A FAILING test file whose `# roadmap:XXXX` item is still UNTICKED in
#   ROADMAP.md is reported EXPECTED-RED and does not fail the suite — red tests
#   are the executable spec for open roadmap items. Once the item's checkbox is
#   ticked, its failures are real failures. Passing tests always count.
# Exit code: 0 if no real failures, 1 otherwise.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROADMAP="$ROOT/ROADMAP.md"

if [[ $# -gt 0 ]]; then
  files=("$@")
else
  files=("$ROOT"/tests/test_*.sh)
fi

pass=0 fail=0 xred=0
failed_names=()

item_open() {
  # roadmap item with this token exists and is unticked
  local token="$1"
  [[ -f "$ROADMAP" ]] || return 1
  grep -qE "^- \[ \] .*<!-- id:${token} -->" "$ROADMAP"
}

for f in "${files[@]}"; do
  [[ -f "$f" ]] || { echo "SKIP   $f (not found)"; continue; }
  name="$(basename "$f")"
  token="$(grep -oE '# roadmap:[0-9a-f]{4}' "$f" | head -1 | sed 's/.*roadmap://')" || true
  if out="$(bash "$f" 2>&1)"; then
    echo "PASS   $name"
    (( ++pass ))
  else
    if [[ -n "${token:-}" ]] && item_open "$token"; then
      echo "EXPECTED-RED $name (roadmap:$token still open — red test is the spec)"
      (( ++xred ))
    else
      echo "FAIL   $name"
      printf '%s\n' "$out" | sed 's/^/       | /'
      failed_names+=("$name")
      (( ++fail ))
    fi
  fi
done

echo
echo "summary: $pass passed, $fail failed, $xred expected-red (open roadmap items)"
if (( fail > 0 )); then
  printf 'failed: %s\n' "${failed_names[*]}"
  exit 1
fi
exit 0
