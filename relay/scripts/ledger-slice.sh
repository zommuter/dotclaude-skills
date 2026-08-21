#!/usr/bin/env bash
# relay/scripts/ledger-slice.sh — id:e68f. HOST-side ledger slicer.
#
# Before dispatching a child, the orchestrator extracts exactly what that one unit needs —
# the dispatched item's own block, its typed `gated-on:` / `children:` / `children-of:` edge
# lines, the defining line of each edge TARGET, the item's TODO.md twin (single-id-two-views),
# and a short repo-state header — writes it to a file, and hands the child the PATH.
#
# WHAT THIS IS, AND IS NOT (correction id:9663, meeting 2026-08-21 `--fabled` F5):
# this LOWERS THE DEFAULT prompt/read size. It is NOT an enforcement. The child holds Read/Bash
# and the repo checkout, and per the banked deny-probe id:5937 auto mode denies essentially
# nothing outside protected paths — nothing here stops a child opening ROADMAP.md at its
# canonical path. Do not describe the slice as a guard against over-reading; it is a cheaper
# default, and the honest claim stops there.
#
# WHY A HOST SCRIPT: relay-loop.js runs inside the Workflow sandbox, which has no filesystem
# (id:2ec4) — it cannot read a ledger or write a tmp file. Same shape as classify-repo.sh /
# provision-worktree.sh: relay-loop.js dispatches it as a mechanical model:'bash' hop and
# captures the printed path.
#
# ANCHORING: every id lookup goes through the comment-anchored id:46f6 engine
# (lib-typed-edges.sh) — NEVER a bare `grep id:XXXX`. A bare token grep matches a prose
# mention in some OTHER item's body (the define-vs-refer defect; id:c97c cost three
# unrecoverable inbox deletions that way).
#
# Usage: ledger-slice.sh --repo <name> --path <repo-path> --id <4-hex> [--out <file>]
#   --out omitted ⇒ a run-stable path under ~/.cache/relay/slices/ is minted and printed.
# Prints the slice path on stdout. SIDE-EFFECT-FREE apart from writing that one file.
# Exit 0 = slice written; 2 = misuse; 4 = the id owns no ROADMAP.md item (LOUD, never a
# silent empty slice — id:4347).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-typed-edges.sh
source "$SCRIPT_DIR/lib-typed-edges.sh"

repo=""; path=""; id=""; out=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) repo="${2:-}"; shift 2 ;;
    --path) path="${2:-}"; shift 2 ;;
    --id)   id="${2:-}";   shift 2 ;;
    --out)  out="${2:-}";  shift 2 ;;
    *) echo "ledger-slice.sh: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
[[ -n "$path" && -n "$id" ]] || { echo "ledger-slice.sh: --path and --id are required" >&2; exit 2; }
[[ "$id" =~ ^[0-9a-fA-F]{4}$ ]] || { echo "ledger-slice.sh: --id must be 4 hex digits (got '$id')" >&2; exit 2; }
id="${id,,}"
repo="${repo:-$(basename "$path")}"

roadmap="$path/ROADMAP.md"
todo="$path/TODO.md"
[[ -f "$roadmap" ]] || { echo "ledger-slice.sh: no ROADMAP.md at $roadmap — nothing to slice" >&2; exit 4; }

if [[ -z "$out" ]]; then
  out="${RELAY_SLICE_DIR:-$HOME/.cache/relay/slices}/${repo}-${id}.md"
fi
mkdir -p "$(dirname "$out")"

# --- anchored lookups ---------------------------------------------------------
# `children-of:` is a live edge spelling that lib-typed-edges.sh does not (yet) extract;
# same comment-anchored grammar, kept local rather than widening the shared lib under a
# sibling executor's in-flight edits to it.
edges_children_of_kind_of_line() { grep -oP '(?<=<!-- children-of:)[0-9a-f,]+(?= -->)' <<<"$1" || true; }

# owning_line_of <token> <file>... — print "<file>:<lineno>\t<line>" for the FIRST checkbox
# line in <file>... whose OWN anchored `<!-- id:token -->` marker is <token>. First file wins
# (live ledgers before archives), mirroring resolve-gates.sh's precedence.
owning_line_of() {
  local tok="$1"; shift
  local f ln n
  for f in "$@"; do
    [[ -f "$f" ]] || continue
    while IFS= read -r n; do
      ln="${n#*:}"; n="${n%%:*}"
      [[ "$ln" =~ ^[[:space:]]*-\ \[[\ xX]\]\  ]] || continue
      [[ "$(typed_edges_own_id_of_line "$ln")" == "$tok" ]] || continue
      printf '%s:%s\t%s\n' "$(basename "$f")" "$n" "$ln"
      return 0
    done < <(grep -nF -- "id:$tok" "$f" || true)
  done
  return 1
}

# --- locate the dispatched item in ROADMAP.md ---------------------------------
item_lineno=""
while IFS= read -r n; do
  line="${n#*:}"; n="${n%%:*}"
  [[ "$line" =~ ^[[:space:]]*-\ \[[\ xX]\]\  ]] || continue
  [[ "$(typed_edges_own_id_of_line "$line")" == "$id" ]] || continue
  item_lineno="$n"
  break
done < <(grep -nF -- "id:$id" "$roadmap" || true)

if [[ -z "$item_lineno" ]]; then
  echo "ledger-slice.sh: id:$id owns no ROADMAP.md checkbox item in $repo ($roadmap) — refusing to write an empty slice a child would read as 'no work here' (id:4347)" >&2
  exit 4
fi

mapfile -t RM < "$roadmap"
last=$(( ${#RM[@]} - 1 ))
idx=$(( item_lineno - 1 ))

# Preceding SIBLING typed-edge comments: the id:46f6 grammar allows an edge either on the
# item's own line or on bare comment lines immediately above it. Walk back over those only.
start=$idx
while (( start > 0 )); do
  prev="${RM[$((start-1))]}"
  [[ "$prev" =~ ^[[:space:]]*\<!--.*--\>[[:space:]]*$ ]] || break
  start=$(( start - 1 ))
done

# The item's own block: the checkbox line plus its indented continuation/sub-bullets.
end=$idx
while (( end < last )); do
  nxt="${RM[$((end+1))]}"
  [[ "$nxt" =~ ^[[:space:]]+[^[:space:]] ]] || break
  end=$(( end + 1 ))
done

block=()
for ((i = start; i <= end; i++)); do block+=("${RM[$i]}"); done

# --- collect typed edge tokens from the block --------------------------------
edge_tokens=()
for l in "${block[@]}"; do
  for csv in "$(typed_edges_gated_of_line "$l")" "$(typed_edges_children_of_line "$l")" "$(edges_children_of_kind_of_line "$l")"; do
    [[ -z "$csv" ]] && continue
    IFS=',' read -ra toks <<<"$csv"
    for t in "${toks[@]}"; do [[ -n "$t" ]] && edge_tokens+=("${t,,}"); done
  done
done
# de-dup, drop a self-edge
declare -A seen=(); uniq_tokens=()
for t in "${edge_tokens[@]:-}"; do
  [[ -z "$t" || "$t" == "$id" || -n "${seen[$t]:-}" ]] && continue
  seen[$t]=1; uniq_tokens+=("$t")
done

# --- write the slice ----------------------------------------------------------
tmp="$(mktemp "${out}.XXXXXX")"
trap '[ -e "$tmp" ] && rm -- "$tmp"' EXIT
{
  echo "# Ledger slice — ${repo} id:${id}"
  echo
  echo "## Repo state"
  echo "- repo: ${repo}"
  echo "- path: ${path}"
  echo "- dispatched item: id:${id} (ROADMAP.md:${item_lineno})"
  echo "- ROADMAP.md: $( [[ -f "$roadmap" ]] && wc -c < "$roadmap" || echo 0 ) B; TODO.md: $( [[ -f "$todo" ]] && wc -c < "$todo" || echo 0 ) B"
  echo "- generated by relay/scripts/ledger-slice.sh (id:e68f)"
  echo
  echo "> This slice is the DEFAULT context for this unit, not a boundary (id:9663): the"
  echo "> ledgers remain readable at their canonical paths. Read them only if this slice is"
  echo "> genuinely insufficient, and say so in your handback if it was."
  echo
  echo "## Dispatched item (ROADMAP.md)"
  echo
  printf '%s\n' "${block[@]}"
  echo
  echo "## Typed edges"
  echo
  if (( ${#uniq_tokens[@]} == 0 )); then
    echo "_(none — this item carries no gated-on: / children: / children-of: edge)_"
  else
    for t in "${uniq_tokens[@]}"; do
      if row="$(owning_line_of "$t" "$roadmap" "$todo" "$path/ROADMAP.archive.md" "$path/TODO.archive.md")"; then
        echo "- id:${t} — ${row%%$'\t'*}"
        echo "  ${row#*$'\t'}"
      else
        # LOUD but not fatal, mirroring resolve-gates.sh: a dangling target is reported,
        # never silently dropped and never a forever-block.
        echo "- id:${t} — DANGLING: resolves to no item line in this repo's ledgers"
      fi
    done
  fi
  echo
  echo "## TODO.md twin (design ledger, same id)"
  echo
  if row="$(owning_line_of "$id" "$todo")"; then
    echo "${row#*$'\t'}"
  else
    echo "_(none — this id has no TODO.md entry)_"
  fi
} > "$tmp"

mv -- "$tmp" "$out"
trap - EXIT
printf '%s\n' "$out"
