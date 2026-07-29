#!/usr/bin/env bash
# roadmap:a225 — mechanical edge→enforcer coverage checker for a mermaid .mmd diagram.
#
# Parses transition edges mechanically from the given .mmd file (never a hand-maintained
# list — that would drift from the drawing). Each edge line is expected to carry a trailing
# annotation comment on the FOLLOWING line:
#   %% enforced-by: <test-file>[, <test-file>...]
#   %% enforced-by: NONE — <reason>
#
# Exit 0  = every edge is either annotated with an existing test file, or explicitly
#           declares NONE with a reason (reported, not fatal).
# Exit 1  = at least one edge has no annotation at all, OR names a test file that does not
#           exist under tests/ (a false coverage claim is worse than none).
#
# See tests/test_diagram_edges_enforced_a225.sh for the pinned contract this implements.

set -uo pipefail
# Ignore SIGPIPE: callers commonly pipe our (verbose, multi-line) stdout into
# `grep -q` for a single match, which closes its read end early. Under a caller's
# `set -o pipefail` that would otherwise turn our own SIGPIPE-killed exit (128+13)
# into the pipeline's reported status even though the grep itself matched — a false
# failure signal, not a real one. Ignoring SIGPIPE makes writes past a closed pipe a
# harmless no-op instead.
trap '' PIPE

usage() { echo "usage: $0 <diagram.mmd>" >&2; exit 2; }
[[ $# -eq 1 ]] || usage
MMD="$1"
[[ -f "$MMD" ]] || { echo "FAIL: no such file: $MMD" >&2; exit 1; }

# Tests directory is resolved relative to THIS script's own repo, not the input file's
# location — the input .mmd may live in a scratch/tmp dir (unit tests of this checker).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)/tests"

# An edge line: not a comment (%%), and carries a mermaid transition arrow (-->, -.->).
is_edge_line() {
  local line="$1"
  local trimmed="${line#"${line%%[![:space:]]*}"}"
  [[ "$trimmed" == %%* ]] && return 1
  [[ "$line" == *"-->"* || "$line" == *".->"* ]]
}

mapfile -t LINES < "$MMD"
n=${#LINES[@]}

fail=0
unenforced_count=0
enforced_count=0

for ((i = 0; i < n; i++)); do
  line="${LINES[$i]}"
  is_edge_line "$line" || continue

  edge_desc="$(echo "$line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  next="${LINES[$((i + 1))]:-}"
  next_trimmed="$(echo "$next" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"

  if [[ "$next_trimmed" != %%\ enforced-by:* ]]; then
    echo "UNENFORCED (no annotation): $edge_desc"
    fail=1
    continue
  fi

  ann="${next_trimmed#%% enforced-by:}"
  ann="$(echo "$ann" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"

  if [[ "$ann" == NONE* ]]; then
    echo "UNENFORCED (declared NONE): $edge_desc -- $ann"
    unenforced_count=$((unenforced_count + 1))
    continue
  fi

  # comma-separated list of test files; every one must exist under tests/.
  IFS=',' read -ra names <<< "$ann"
  bad=0
  for raw in "${names[@]}"; do
    name="$(echo "$raw" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [[ -z "$name" ]] && continue
    if [[ ! -f "$TESTS_DIR/$name" ]]; then
      echo "FAIL: enforced-by names nonexistent test '$name' for edge: $edge_desc"
      fail=1
      bad=1
    fi
  done
  if [[ $bad -eq 0 ]]; then
    echo "ENFORCED: $edge_desc -- enforced-by: $ann"
    enforced_count=$((enforced_count + 1))
  fi
done

echo "---"
echo "summary: $enforced_count enforced, $unenforced_count unenforced (declared NONE)"

[[ $fail -eq 0 ]] || exit 1
exit 0
