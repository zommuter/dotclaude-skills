#!/usr/bin/env bash
# disjoint-greenlight.sh — mechanical disjoint-path greenlight for
# `/relay . --parallel N` (id:5367, id:ebbe child, meeting
# 2026-07-19-2035 D4).
#
# Concurrent execution of candidate units is greenlit MECHANICALLY and
# FAIL-CLOSED: only when every candidate unit's declared file-set is
# non-empty AND the sets are pairwise disjoint does `plan` print
# "concurrent"; any empty/undeclared set, any overlap, or fewer than two
# units forces "serial". `merge-check` re-enforces the same fail-closed
# rule at merge time: a 2nd worktree's touched paths are checked against
# the already-merged diff, and any intersection is a HANDBACK signal
# (never auto-resolved — see id:2062, the serial integrator that
# consumes this).
#
# Usage:
#   disjoint-greenlight.sh plan
#     Reads TSV on stdin, one candidate unit per line:
#       <id><TAB><comma-joined declared paths>
#     Prints exactly one word to stdout: "concurrent" or "serial". Exit 0
#     on well-formed input (even when the verdict is "serial"). Malformed
#     input (a line with no tab) exits nonzero with ERROR on stderr.
#
#   disjoint-greenlight.sh merge-check --touched <file> --merged <file>
#     <file>s are newline-delimited path lists. Disjoint → exit 0, empty
#     stdout. Any intersection → exit 1, the intersecting paths (one per
#     line) on stdout — the handback evidence.
set -uo pipefail

err() { echo "ERROR: $*" >&2; }

cmd_plan() {
  local line id paths_csv
  local -a all_paths=()
  local -a unit_ids=()
  local -a unit_pathsets=()
  local nunits=0

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    if [[ "$line" != *$'\t'* ]]; then
      err "malformed plan line (no tab): $line"
      return 1
    fi
    id="${line%%$'\t'*}"
    paths_csv="${line#*$'\t'}"
    unit_ids+=("$id")
    unit_pathsets+=("$paths_csv")
    nunits=$((nunits + 1))
  done

  if [[ "$nunits" -lt 2 ]]; then
    echo "serial"
    return 0
  fi

  # Fail-closed: any empty declared set → serial.
  local i
  for ((i = 0; i < nunits; i++)); do
    if [[ -z "${unit_pathsets[$i]// /}" ]]; then
      echo "serial"
      return 0
    fi
  done

  # Pairwise disjointness check across all declared paths.
  declare -A seen=()
  local csv p
  for ((i = 0; i < nunits; i++)); do
    csv="${unit_pathsets[$i]}"
    IFS=',' read -r -a paths <<< "$csv"
    for p in "${paths[@]}"; do
      [[ -z "$p" ]] && continue
      if [[ -n "${seen[$p]:-}" ]]; then
        echo "serial"
        return 0
      fi
      seen["$p"]=1
    done
  done

  echo "concurrent"
  return 0
}

cmd_merge_check() {
  local touched_file="" merged_file=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --touched) touched_file="$2"; shift 2 ;;
      --merged) merged_file="$2"; shift 2 ;;
      *) err "merge-check: unknown argument: $1"; return 1 ;;
    esac
  done

  if [[ -z "$touched_file" || -z "$merged_file" ]]; then
    err "merge-check requires --touched <file> --merged <file>"
    return 1
  fi
  if [[ ! -f "$touched_file" ]]; then
    err "merge-check: --touched file not found: $touched_file"
    return 1
  fi
  if [[ ! -f "$merged_file" ]]; then
    err "merge-check: --merged file not found: $merged_file"
    return 1
  fi

  declare -A merged_paths=()
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    merged_paths["$line"]=1
  done < "$merged_file"

  local -a overlaps=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    if [[ -n "${merged_paths[$line]:-}" ]]; then
      overlaps+=("$line")
    fi
  done < "$touched_file"

  if [[ "${#overlaps[@]}" -eq 0 ]]; then
    return 0
  fi

  printf '%s\n' "${overlaps[@]}"
  return 1
}

main() {
  local subcmd="${1:-}"
  shift || true
  case "$subcmd" in
    plan) cmd_plan "$@" ;;
    merge-check) cmd_merge_check "$@" ;;
    *) err "unknown subcommand: ${subcmd:-<none>} (expected 'plan' or 'merge-check')"; return 1 ;;
  esac
}

main "$@"
