#!/usr/bin/env bash
# relay/scripts/resolve-gates.sh — id:65f5 classifier-side `gated-on:` resolver.
#
# For every OPEN or CLOSED ROADMAP.md item that carries a comment-anchored
# `<!-- gated-on:CSV -->` typed edge (the id:46f6 form-C grammar), resolve the target
# tokens against their checkbox state over ROADMAP.md ∪ TODO.md ∪ TODO.archive.md,
# using the SHARED id:46f6 engine (lib-typed-edges.sh) — NOT a bare substring read of
# "gated-on" (the id:4da4/0d58 trap).
#
# Usage: resolve-gates.sh <repo-path>
# Emits TSV on stdout, one row per gated item whose disposition is not a clean pass:
#     <own-id>\t<block:0|1>\t<dangling-token-csv>
#   block=1     — at least one RESOLVED target is still OPEN → the item is blocked
#                 (excluded from actionable_routine_open by the caller).
#   dangling≠"" — one or more targets are unresolvable → LOUD (the caller surfaces
#                 them on stderr) but NOT a block (never a silent forever-block).
# A fully clean edge (every target resolves AND is [x]) emits nothing.
# SIDE-EFFECT-FREE: reads ledgers only.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-typed-edges.sh
source "$SCRIPT_DIR/lib-typed-edges.sh"

path="${1:-}"
[[ -n "$path" ]] || { echo "resolve-gates.sh: <repo-path> required" >&2; exit 2; }

roadmap="$path/ROADMAP.md"
[[ -f "$roadmap" ]] || exit 0   # no ROADMAP → no gates to resolve

# id:46f6 resolution map spans ROADMAP ∪ TODO ∪ archive (the executor gate must see a
# target that lives only in ROADMAP — orphan-scan deliberately excludes ROADMAP, that is
# the one scope difference between the two callers).
declare -A EDGE_STATE
typed_edges_build_state_map EDGE_STATE \
  "$roadmap" "$path/TODO.md" "$path/TODO.archive.md"

while IFS= read -r line; do
  # Only checkbox lines can carry an item id + edge.
  [[ "$line" =~ ^[[:space:]]*-\ \[[\ xX]\]\  ]] || continue
  gated_csv="$(typed_edges_gated_of_line "$line")"
  [[ -z "$gated_csv" ]] && continue
  own_id="$(typed_edges_own_id_of_line "$line")"
  [[ -z "$own_id" ]] && continue

  read -r all_resolve _all_closed dangling_csv \
    < <(typed_edges_resolve_set EDGE_STATE "$gated_csv")

  # block iff any RESOLVED target is still open. Recompute over the resolvable subset:
  # a set can mix an open (block) target with a dangling (loud) one.
  block=0
  IFS=',' read -ra _toks <<<"$gated_csv"
  for t in "${_toks[@]}"; do
    [[ -z "$t" ]] && continue
    if [[ -n "${EDGE_STATE[$t]+x}" && "${EDGE_STATE[$t]}" != "x" ]]; then
      block=1
    fi
  done

  if (( block == 1 )) || [[ -n "$dangling_csv" ]]; then
    printf '%s\t%s\t%s\n' "$own_id" "$block" "$dangling_csv"
  fi
done < "$roadmap"
