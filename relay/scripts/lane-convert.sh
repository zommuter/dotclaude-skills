#!/usr/bin/env bash
# lane-convert.sh (id:4f02) — deterministic TEXT transform of the old venue-keyed
# `[HARD — <lane>]` vocabulary onto the new capability-keyed vocabulary (see
# relay/references/hard-lanes.md "North star — capability-keyed vocabulary").
#
# WHY (meeting 2026-07-02-1924 decision 2, amendment "rename mapping — [HARD — hands]
# has no auto-default"): B1 is the SAFETY-NET-FIRST half of the wave-2b lane rename.
# This converter AUTO-APPLIES only the THREE unambiguous 1:1 renames on the exact
# bracket strings — it is a plain text transform, NOT a lane-parser (it never inspects
# item semantics, just string-matches the bracket spelling):
#
#   [HARD — pool]           → [HARD]
#   [HARD — meeting]        → [INPUT — meeting]
#   [HARD — decision gate]  → [INPUT — decision]
#
# `[HARD — hands]` is NEVER auto-converted — it fragments across FOUR candidate
# destinations by per-item human judgment ([MECHANICAL] / [INPUT — access] /
# [INPUT — decision] / [INPUT — meeting]). Every `[HARD — hands]` line is LEFT
# UNCHANGED in the output and FLAGGED on stderr (file:line + id + the four
# candidates), deferring the decision to M3 (id:3ef7) / human — the converter emits
# NO default for hands.
#
# [ROUTINE] / [MECHANICAL] / [INTENSIVE — <res>] and the `🚧 route:*` auto-gate
# aliases pass through UNCHANGED.
#
# Idempotent: re-running on already-converted output is a no-op on stdout (a
# still-present `[HARD — hands]` re-flags on stderr but its text is never rewritten).
#
# --reorder mode (id:4b37, D2 — ISOLATED unit, NOT bolted onto the rename flow above):
# on each `- [ ]`/`- [x]` CHECKBOX line ONLY, moves the anchored PRIMARY lane token
# (the leftmost recognized bare lane tag, ignoring backtick'd MENTIONS — same anchoring
# idiom as roadmap-lint.sh's `first_lane_tag` strip=1 reader) plus any lane-tag-ADJACENT
# `[INTENSIVE — <res>]` modifier (order preserved) to immediately after the checkbox.
# Everything else — title/body prose, non-lane `[bracket]`s, backtick'd mentions, the
# trailing `<!-- id:XXXX -->` — is left in place; whitespace at the lift site is
# normalized to a single space. Idempotent (already-first ⇒ no-op). Composable with
# --in-place. Non-checkbox lines (headings, prose, `  - **Why**:` sub-bullets) are
# NEVER touched, even if they mention a lane tag.
#
# Usage:
#   lane-convert.sh <ledger-file>                        # converted text on stdout
#   lane-convert.sh --in-place <ledger-file>              # rewrite the file in place (B2c)
#   lane-convert.sh --reorder <ledger-file>               # tag-first reorder, stdout
#   lane-convert.sh --in-place --reorder <ledger-file>    # reorder, rewrite in place
set -euo pipefail

in_place=0
reorder=0
file=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --in-place) in_place=1; shift ;;
    --reorder)  reorder=1; shift ;;
    *) file="$1"; shift ;;
  esac
done

if [[ -z "$file" || ! -f "$file" ]]; then
  echo "lane-convert.sh: usage: lane-convert.sh [--in-place] [--reorder] <ledger-file>" >&2
  exit 2
fi

id_re='id:[0-9a-fA-F]{4}'

# --- shared: recognized lane-tag vocabulary, read from hard-lanes.md -----------
# Mirrors roadmap-lint.sh's extraction (single source of truth, id:78ff) — no
# second hardcoded copy of the lane spelling lives here.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
lanes_doc="$script_dir/../references/hard-lanes.md"

hard_lanes=""
if [[ -f "$lanes_doc" ]]; then
  hard_lanes="$(grep -oE '\[HARD — [a-z][a-z ]*[a-z]\]' "$lanes_doc" | sort -u || true)"
fi
if [[ -z "$hard_lanes" ]]; then
  hard_lanes=$'[HARD — pool]\n[HARD — meeting]\n[HARD — hands]\n[HARD — decision gate]'
fi

input_lanes=""
if [[ -f "$lanes_doc" ]]; then
  input_lanes="$(grep -oE '\[INPUT — [a-z]+\]' "$lanes_doc" | sort -u || true)"
fi
if [[ -z "$input_lanes" ]]; then
  input_lanes=$'[INPUT — meeting]\n[INPUT — decision]\n[INPUT — access]'
fi

all_lane_tags=("[ROUTINE]" "[MECHANICAL]" "[HARD]")
while IFS= read -r _hl; do
  [[ -n "$_hl" ]] && all_lane_tags+=("$_hl")
done <<< "$hard_lanes"
while IFS= read -r _il; do
  [[ -n "$_il" ]] && all_lane_tags+=("$_il")
done <<< "$input_lanes"

# mask_backticks <str> — replace every backtick-quoted span (backticks included)
# with '#' filler of the SAME LENGTH, so positions in the masked string line up
# byte-for-byte with the original. A tag found only inside a masked span is a
# prose MENTION, not a live lane, and must not be matched.
mask_backticks() {
  local s="$1" out="" c i in_tick=0
  for (( i=0; i<${#s}; i++ )); do
    c="${s:i:1}"
    if [[ "$c" == '`' ]]; then
      in_tick=$((1 - in_tick))
      out+='#'
    elif [[ "$in_tick" -eq 1 ]]; then
      out+='#'
    else
      out+="$c"
    fi
  done
  printf '%s' "$out"
}

# find_tag_pos <haystack> <tag...> — leftmost byte position + tag string among
# the given tags in haystack; sets globals TAG_POS (-1 if none) and TAG.
find_tag_pos() {
  local hay="$1"; shift
  local tag prefix pos best_pos=-1 best_tag=""
  for tag in "$@"; do
    case "$hay" in
      *"$tag"*)
        prefix="${hay%%"$tag"*}"
        pos=${#prefix}
        if [[ "$best_pos" -lt 0 || "$pos" -lt "$best_pos" ]]; then
          best_pos=$pos; best_tag="$tag"
        fi ;;
    esac
  done
  TAG_POS=$best_pos
  TAG="$best_tag"
}

# reorder_line <rest> — given the text AFTER the checkbox marker ("- [ ] "),
# returns the reordered text (primary lane cluster first, single-space
# normalized), or the input unchanged if no recognized primary lane is found.
reorder_rest() {
  local rest="$1" masked
  masked="$(mask_backticks "$rest")"
  find_tag_pos "$masked" "${all_lane_tags[@]}"
  local primary_pos="$TAG_POS" primary_tag="$TAG"
  if [[ "$primary_pos" -lt 0 ]]; then
    printf '%s' "$rest"
    return
  fi
  local primary_end=$((primary_pos + ${#primary_tag}))
  local cluster_start=$primary_pos cluster_end=$primary_end cluster="$primary_tag"

  # Adjacent-AFTER: primary tag immediately followed (whitespace only) by an
  # `[INTENSIVE — <res>]` modifier.
  local after="${rest:primary_end}"
  if [[ "$after" =~ ^([[:space:]]+)(\[INTENSIVE[[:space:]]—[[:space:]][^]]*\]) ]]; then
    local ws1="${BASH_REMATCH[1]}" itag="${BASH_REMATCH[2]}"
    cluster_end=$((primary_end + ${#ws1} + ${#itag}))
    cluster="$primary_tag $itag"
  else
    # Adjacent-BEFORE: an `[INTENSIVE — <res>]` immediately precedes the primary
    # tag (whitespace only in between).
    local masked_before="${masked:0:primary_pos}"
    if [[ "$masked_before" =~ ^(.*)(\[INTENSIVE[[:space:]]—[[:space:]][^]]*\])([[:space:]]+)$ ]]; then
      local pre="${BASH_REMATCH[1]}" itag="${BASH_REMATCH[2]}"
      cluster_start=${#pre}
      cluster="$itag $primary_tag"
    fi
  fi

  local left="${rest:0:cluster_start}" right="${rest:cluster_end}"
  # Trim trailing whitespace off left, leading whitespace off right. Strip via the
  # [[:space:]] bracket-expression (NOT a literal ' '): a leading/trailing TAB
  # satisfies the [[:space:]]* loop guard but `${var# }` would never consume it,
  # spinning forever (audit Run 70). Match the guard and the strip on the same class.
  while [[ "$left" == *[[:space:]] ]]; do left="${left%[[:space:]]}"; done
  while [[ "$right" == [[:space:]]* ]]; do right="${right#[[:space:]]}"; done

  local remainder="$left"
  if [[ -n "$left" && -n "$right" ]]; then
    remainder+=" $right"
  else
    remainder+="$right"
  fi

  if [[ -n "$remainder" ]]; then
    printf '%s %s' "$cluster" "$remainder"
  else
    printf '%s' "$cluster"
  fi
}

if [[ "$reorder" -eq 1 ]]; then
  out=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^(-[[:space:]]\[[[:space:]xX]\][[:space:]]+)(.*)$ ]]; then
      prefix="${BASH_REMATCH[1]}"
      rest="${BASH_REMATCH[2]}"
      line="${prefix}$(reorder_rest "$rest")"
    fi
    out+="${line}"$'\n'
  done < "$file"

  if [[ "$in_place" -eq 1 ]]; then
    printf '%s' "$out" > "$file"
  else
    printf '%s' "$out"
  fi
  exit 0
fi

out=""
lineno=0
had_hands=0
while IFS= read -r line || [[ -n "$line" ]]; do
  lineno=$((lineno + 1))

  # [HARD — hands] is fan-out-ambiguous — NEVER auto-converted. Flag on stderr,
  # leave the line byte-for-byte unchanged.
  if [[ "$line" == *'[HARD — hands]'* ]]; then
    had_hands=1
    idtoken=""
    if [[ "$line" =~ ($id_re) ]]; then
      idtoken="${BASH_REMATCH[1]}"
    fi
    echo "lane-convert: NEEDS JUDGMENT — $file:$lineno (${idtoken:-<no id>}) [HARD — hands] fragments across four candidates — pick ONE by per-item judgment:" >&2
    echo "  [MECHANICAL] (a daemon can run it, no LLM/human) | [INPUT — access] (credential/hardware/physical) | [INPUT — decision] (human decides, no design session) | [INPUT — meeting] (needs design judgment)" >&2
    echo "  $line" >&2
  else
    # The three unambiguous 1:1 renames.
    line="${line//\[HARD — pool\]/[HARD]}"
    line="${line//\[HARD — meeting\]/[INPUT — meeting]}"
    line="${line//\[HARD — decision gate\]/[INPUT — decision]}"
  fi

  out+="${line}"$'\n'
done < "$file"

if [[ "$in_place" -eq 1 ]]; then
  printf '%s' "$out" > "$file"
else
  printf '%s' "$out"
fi

if [[ "$had_hands" -eq 1 ]]; then
  echo "lane-convert: one or more [HARD — hands] items were left unchanged — resolve them by hand (M3, id:3ef7)." >&2
fi

exit 0
