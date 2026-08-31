#!/usr/bin/env bash
# lane-delimiter-scan.sh (id:70bc) -- the em-dash delimiter migration's MECHANICAL
# completion detector.
#
# WHY IT EXISTS: several readers already accept BOTH delimiters
# (mechanical-orphan-scan.sh:98, gather-human-backlog.sh:403), so a half-applied
# migration is silently absorbed and looks identical to a finished one. "The suite is
# green" therefore does NOT mean "the migration finished". Without this detector,
# dropping the dual-vocab tolerance has no closing condition that can be CHECKED
# rather than asserted, and there is no rollback signal.
#
# WHY `grep -c '—'` IS NOT THE ANSWER: ledger prose legitimately QUOTES the old
# spellings in audit trails, and a global string ban would make it impossible to
# write the history of this very migration. The detector distinguishes a LIVE lane
# tag from a PROSE MENTION using the SAME anchoring roadmap-lint.sh rule 3(g)
# adopted in 7a86cdb3 -- the contiguous run of recognized lane brackets at the START
# of the item text, after backtick-quoted spans are masked and `[INTENSIVE - <res>]`
# resource brackets are folded, so a resource-FIRST item does not stop the run dead.
# That anchoring is NOT reimplemented here: it is the shared `leading_lane_run` in
# relay/scripts/lib-lane-anchor.sh, which roadmap-lint.sh sources too. A second
# divergent copy is exactly the failure class this migration exists to fix.
#
# Usage:
#   lane-delimiter-scan.sh [--live-only] <ledger-file>...
#     prints  <file>:<lineno>: <tag>  (<id>)      per LIVE em-dash-delimited lane tag
#     prints  <file>:<lineno>: <tag> (prose)      per backtick'd/trailing MENTION
#     --live-only  suppresses the (prose) lines; this is the closing-condition mode
#     exit 0 = no LIVE findings; 1 = at least one; 2 = usage/IO error
#
# Prose mentions NEVER affect the exit code, in either mode.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=relay/scripts/lib-lane-anchor.sh
source "$script_dir/lib-lane-anchor.sh"

live_only=0
files=()
for a in "$@"; do
  case "$a" in
    --live-only) live_only=1 ;;
    -h|--help)
      echo "usage: lane-delimiter-scan.sh [--live-only] <ledger-file>..." >&2
      exit 2 ;;
    *) files+=("$a") ;;
  esac
done

if [[ ${#files[@]} -eq 0 ]]; then
  echo "lane-delimiter-scan: usage: lane-delimiter-scan.sh [--live-only] <ledger-file>..." >&2
  exit 2
fi

lanes_doc="$script_dir/../references/hard-lanes.md"
lane_vocab_scrape "$lanes_doc" || exit 2

# The resource axis is orthogonal to the lane axis, so `[INTENSIVE - <res>]` is
# deliberately NOT part of the lane vocabulary -- which would make leading_lane_run
# stop dead at a resource-FIRST item and let its lane escape (roadmap-lint.sh rule
# 3(g) strips the brackets for exactly that reason). Here the brackets are FOLDED to
# a fixed sentinel instead of stripped, because their delimiter is precisely what
# this scan is looking for: folding keeps them inside the run so the run's own
# em-dash count answers the question.
all_lane_tags+=("[INTENSIVE—X]" "[INTENSIVE-X]")

# count_emdash <str> -- occurrences of U+2014. Each recognized lane bracket in a run
# carries exactly one (lane names never do), so this counts live old-delimiter tags.
count_emdash() {
  local s="$1" n=0
  while [[ "$s" == *—* ]]; do n=$((n + 1)); s="${s#*—}"; done
  printf '%d' "$n"
}

EM_TAG_RE='(\[(HARD|INPUT|INTENSIVE)[[:space:]]*—[^]]*\])'

findings=0
rc=0
for f in "${files[@]}"; do
  if [[ ! -e "$f" ]]; then
    echo "lane-delimiter-scan: cannot read $f" >&2
    rc=2
    continue
  fi
  if [[ ! -f "$f" ]]; then
    echo "lane-delimiter-scan: not a regular file: $f" >&2
    rc=2
    continue
  fi
  if [[ ! -r "$f" ]]; then
    echo "lane-delimiter-scan: cannot read $f" >&2
    rc=2
    continue
  fi
  lineno=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    lineno=$((lineno + 1))
    [[ "$line" == *—* ]] || continue

    # Every em-dash-delimited lane bracket ON THIS LINE, left to right.
    occ=()
    scan_rest="$line"
    while [[ "$scan_rest" =~ $EM_TAG_RE ]]; do
      m="${BASH_REMATCH[1]}"
      occ+=("$m")
      scan_rest="${scan_rest#*"$m"}"
    done
    [[ ${#occ[@]} -gt 0 ]] || continue

    # How many of them are LIVE? Only a top-level checkbox item carries a lane tag,
    # and only the leading run of it is live. The run is a PREFIX of the line, so the
    # first N em-dash brackets on the line are exactly the live ones.
    live=0
    if [[ "$line" =~ ^-[[:space:]]\[[[:space:]xX]\][[:space:]] ]]; then
      prepped="$(mask_backticks "$line")"
      prepped="$(printf '%s' "$prepped" \
        | sed -E 's/\[INTENSIVE[[:space:]]*—[[:space:]]*[^]]*\]/[INTENSIVE—X]/g; s/\[INTENSIVE[[:space:]]*-[[:space:]]*[^]]*\]/[INTENSIVE-X]/g')"
      live="$(count_emdash "$(leading_lane_run "$prepped")")"
    fi

    idtok=""
    [[ "$line" =~ \<!--[[:space:]]*id:([0-9a-fA-F]{4})[[:space:]]*--\> ]] && idtok="id:${BASH_REMATCH[1]}"

    for ((i = 0; i < ${#occ[@]}; i++)); do
      if [[ $i -lt $live ]]; then
        findings=$((findings + 1))
        if [[ -n "$idtok" ]]; then
          printf '%s:%d: %s  (%s)\n' "$f" "$lineno" "${occ[$i]}" "$idtok"
        else
          printf '%s:%d: %s\n' "$f" "$lineno" "${occ[$i]}"
        fi
      elif [[ "$live_only" -eq 0 ]]; then
        printf '%s:%d: %s (prose)\n' "$f" "$lineno" "${occ[$i]}"
      fi
    done
  done < "$f"
done

[[ $rc -eq 2 ]] && exit 2
[[ $findings -gt 0 ]] && exit 1
exit 0
