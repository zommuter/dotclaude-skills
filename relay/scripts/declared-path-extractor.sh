#!/usr/bin/env bash
# declared-path-extractor.sh — mechanical declared-path extractor feeding
# `disjoint-greenlight.sh` (id:b099, children-of:1f4f, meeting
# 2026-07-26-1922 D3).
#
# D3a (record this rule): the greenlight this feeds is a THROUGHPUT
# OPTIMIZER; the serialized integrator (`disjoint-greenlight.sh
# merge-check`) is the SAFETY NET. Never relax integrate checks "because
# greenlight already proved disjointness" — this extractor's output is an
# UNVERIFIED declaration, not a guarantee.
#
# The declared path set is NOT missing from this repo's ROADMAP.md: open
# items overwhelmingly carry path-shaped backtick tokens in their
# `**Context**` / `**Tests**` / `**Wiring**` fields already. This script
# EXTRACTS that existing signal — it does not invent a new authored field.
#
# Usage:
#   declared-path-extractor.sh extract
#     Reads one ROADMAP item's block text (the bullet + its indented
#     sub-bullets) on stdin. Scans lines that open a `**Context**`,
#     `**Tests**`, or `**Wiring**` field for backtick-quoted path-shaped
#     tokens (must contain a `/`; no whitespace, no `:`, no quote chars —
#     this excludes things like `` `model:'bash'` ``). Prints a
#     comma-joined, de-duplicated path list to stdout.
#
#     An item with NO extractable path prints the literal verdict
#     `RUN-ALONE` instead of an empty string — F3 (load-bearing): an EMPTY
#     extraction must never be read as an empty-set-is-disjoint greenlight,
#     which would turn maximal under-extraction into maximal (wrong)
#     parallelism. Callers MUST branch on this literal, never treat empty
#     stdout as "safe to parallelize".
#
#     Pure-read: writes nothing outside stdout. Exit 0 always (extraction
#     never fails on well-formed-or-not text — absence of paths is a valid
#     verdict, not an error).
#
#   declared-path-extractor.sh eval-corpus <manifest.tsv>
#     Evaluates extraction quality against a fixture corpus with known
#     ground truth. Manifest is a TSV, one unit per line:
#       <unit_id><TAB><item-block-file><TAB><actual-touched-paths-file>
#     `item-block-file` is fed to `extract`; `actual-touched-paths-file` is
#     a newline-delimited list of the paths the unit ACTUALLY touched
#     (ground truth — in real use this comes from
#     `drain-integrate.sh`'s merge-check diff).
#
#     Emits two metrics, both load-bearing (not a nicety — a subset-only
#     metric measures half the evidence):
#       - under-extraction: extracted set is a SUBSET that MISSES at least
#         one actually-touched path (extracted does not cover actual).
#       - false-serialization: for every pair of units whose DECLARED sets
#         intersect (the pair the naive greenlight would serialize), but
#         whose ACTUAL touched sets are disjoint (serializing them bought
#         nothing) — this is where an over-broad `**Context**` citation
#         (cited, not touched) shows up, and it is COUNTED here rather than
#         silently dropped.
#     Output (key=value lines, machine-readable):
#       units=<n>
#       under_extracted=<n>
#       under_extraction_rate=<0.NN>
#       declared_overlap_pairs=<n>
#       false_serialized_pairs=<n>
#       false_serialization_rate=<0.NN|n/a>
set -uo pipefail

err() { echo "ERROR: $*" >&2; }

# Extract path-shaped backtick tokens from one field line.
# A token qualifies iff: contains a '/', and contains none of
# whitespace / ':' / quote chars (excludes things like `model:'bash'`).
_extract_line_paths() {
  local line="$1"
  local -a toks
  # grab all backtick-delimited spans
  mapfile -t toks < <(grep -oE '`[^`]+`' <<<"$line" | sed -e 's/^`//' -e 's/`$//')
  local t
  for t in "${toks[@]}"; do
    [[ "$t" == *"/"* ]] || continue
    [[ "$t" =~ [[:space:]:\'\"] ]] && continue
    printf '%s\n' "$t"
  done
}

cmd_extract() {
  local -a paths=()
  local line in_field=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ \*\*(Context|Tests|Wiring)\*\* ]]; then
      in_field=1
    fi
    if [[ "$in_field" -eq 1 ]]; then
      while IFS= read -r p; do
        [[ -n "$p" ]] && paths+=("$p")
      done < <(_extract_line_paths "$line")
    fi
  done

  if [[ "${#paths[@]}" -eq 0 ]]; then
    echo "RUN-ALONE"
    return 0
  fi

  # de-duplicate, preserve first-seen order
  declare -A seen=()
  local -a uniq=()
  local p
  for p in "${paths[@]}"; do
    if [[ -z "${seen[$p]:-}" ]]; then
      seen["$p"]=1
      uniq+=("$p")
    fi
  done

  local IFS=,
  echo "${uniq[*]}"
  return 0
}

_declared_set_for() {
  # $1 = item-block-file -> prints comma-joined set or RUN-ALONE
  cmd_extract < "$1"
}

_sets_intersect() {
  # $1, $2 = comma-joined sets (or RUN-ALONE). RUN-ALONE never intersects.
  local a="$1" b="$2"
  [[ "$a" == "RUN-ALONE" || "$b" == "RUN-ALONE" ]] && return 1
  local IFS=,
  local -a A=($a)
  declare -A seen=()
  local x
  for x in "${A[@]}"; do seen["$x"]=1; done
  local -a B=($b)
  for x in "${B[@]}"; do
    [[ -n "${seen[$x]:-}" ]] && return 0
  done
  return 1
}

_covers() {
  # does declared set (arg1, comma-joined or RUN-ALONE) cover every line of
  # actual-paths file (arg2)?
  local declared="$1" actual_file="$2"
  [[ "$declared" == "RUN-ALONE" ]] && { [[ -s "$actual_file" ]] && return 1 || return 0; }
  declare -A dset=()
  local IFS=,
  local -a D=($declared)
  local x
  for x in "${D[@]}"; do dset["$x"]=1; done
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    [[ -z "${dset[$line]:-}" ]] && return 1
  done < "$actual_file"
  return 0
}

_actual_disjoint() {
  # $1, $2 = actual-touched-path files (newline-delimited)
  declare -A a1=()
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    a1["$line"]=1
  done < "$1"
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    [[ -n "${a1[$line]:-}" ]] && return 1
  done < "$2"
  return 0
}

cmd_eval_corpus() {
  local manifest="${1:-}"
  if [[ -z "$manifest" || ! -f "$manifest" ]]; then
    err "eval-corpus requires a manifest TSV path"
    return 1
  fi

  local -a ids=() items=() actuals=()
  local line id item_f actual_f
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    if [[ "$line" != *$'\t'*$'\t'* ]]; then
      err "malformed manifest line (need 2 tabs): $line"
      return 1
    fi
    id="${line%%$'\t'*}"
    local rest="${line#*$'\t'}"
    item_f="${rest%%$'\t'*}"
    actual_f="${rest#*$'\t'}"
    ids+=("$id"); items+=("$item_f"); actuals+=("$actual_f")
  done < "$manifest"

  local n="${#ids[@]}"
  local -a declared=()
  local i
  for ((i = 0; i < n; i++)); do
    declared+=("$(_declared_set_for "${items[$i]}")")
  done

  local under=0
  for ((i = 0; i < n; i++)); do
    if ! _covers "${declared[$i]}" "${actuals[$i]}"; then
      under=$((under + 1))
    fi
  done

  local pairs=0 overlap_pairs=0 false_serialized=0
  local j
  for ((i = 0; i < n; i++)); do
    for ((j = i + 1; j < n; j++)); do
      pairs=$((pairs + 1))
      if _sets_intersect "${declared[$i]}" "${declared[$j]}"; then
        overlap_pairs=$((overlap_pairs + 1))
        if _actual_disjoint "${actuals[$i]}" "${actuals[$j]}"; then
          false_serialized=$((false_serialized + 1))
        fi
      fi
    done
  done

  local under_rate false_rate
  if [[ "$n" -gt 0 ]]; then
    under_rate="$(awk -v a="$under" -v b="$n" 'BEGIN{printf "%.2f", a/b}')"
  else
    under_rate="n/a"
  fi
  if [[ "$overlap_pairs" -gt 0 ]]; then
    false_rate="$(awk -v a="$false_serialized" -v b="$overlap_pairs" 'BEGIN{printf "%.2f", a/b}')"
  else
    false_rate="n/a"
  fi

  echo "units=$n"
  echo "under_extracted=$under"
  echo "under_extraction_rate=$under_rate"
  echo "declared_overlap_pairs=$overlap_pairs"
  echo "false_serialized_pairs=$false_serialized"
  echo "false_serialization_rate=$false_rate"
  return 0
}

main() {
  local subcmd="${1:-}"
  shift || true
  case "$subcmd" in
    extract) cmd_extract "$@" ;;
    eval-corpus) cmd_eval_corpus "$@" ;;
    *) err "unknown subcommand: ${subcmd:-<none>} (expected 'extract' or 'eval-corpus')"; return 1 ;;
  esac
}

main "$@"
