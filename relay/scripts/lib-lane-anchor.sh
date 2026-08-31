#!/usr/bin/env bash
# lib-lane-anchor.sh (id:70bc) -- the SINGLE definition of three things every lane
# reader in this repo needs, so no two readers can drift apart on them:
#
#   1. `lane_vocab_scrape <doc>`  -- read the recognized lane vocabulary OUT of
#      relay/references/hard-lanes.md (the id:78ff single source of truth) with an
#      EXPLICIT two-delimiter alternation, and FAIL LOUDLY (nonzero + a stderr
#      message naming the doc) when the scrape comes back empty. There is no
#      hardcoded fallback set anywhere: a fallback that merely gets a new delimiter
#      still makes a broken scrape look like a working one (the id:d35a silent-no-op
#      class, reproduced 2026-08-27 inside the very tooling built to prevent it).
#   2. `mask_backticks <str>`     -- replace every backtick-quoted span with
#      same-length '#' filler, so a lane bracket quoted in prose is never read as a
#      live tag (the id:4da4/0d58 anchoring trap).
#   3. `leading_lane_run <line>`  -- the contiguous run of recognized lane brackets
#      at the very START of the item text. Moved here VERBATIM from
#      roadmap-lint.sh, where rule 3(g) adopted it in 7a86cdb3 after the unanchored
#      version produced three real false positives on audit-trail prose (loderite
#      affd, loderite 1e21, toesnail 8807).
#
# Callers supply the vocabulary in the array `all_lane_tags` (lane_vocab_scrape
# populates it). This file is sourced, never executed.

# lane_vocab_scrape <lanes-doc> -- populate the globals `hard_lanes`,
# `input_lanes` and `all_lane_tags` from <lanes-doc>.
#
# DELIMITER TOLERANCE (em-dash migration, id:71d6): the scrape accepts BOTH the
# legacy em dash and the target hyphen, and the tag set it builds carries BOTH
# spellings of every lane it finds. Recognition is therefore keyed on the lane
# NAME, never on the delimiter byte -- flipping the SSOT flips what the readers
# consider canonical without making them blind to ledgers that have not been
# rewritten yet (tolerant-read / canonical-emit).
#
# Returns 1 (and prints a LOUD stderr message naming the doc path) when the doc is
# unreadable or declares no lanes at all. Callers must treat that as fatal.
lane_vocab_scrape() {
  local doc="$1" names name

  hard_lanes=""
  input_lanes=""
  hard_lane_names=""
  input_lane_names=""
  all_lane_tags=()

  if [[ ! -r "$doc" ]]; then
    echo "lane-vocab: FATAL -- cannot read the lane vocabulary source of truth at $doc; refusing to guess a lane set (id:71d6 -- the hardcoded fallbacks were deleted on purpose)" >&2
    return 1
  fi

  # `[HARD - <lane>]` / `[HARD — <lane>]`; lane names are lowercase words, possibly
  # spaced ("decision gate"). The `[HARD — *]` / `[HARD — <lane>]` meta-spellings in
  # the doc's prose cannot match (`*` and `<` are outside the character class).
  names="$(grep -oE '\[HARD[[:space:]]*[—-][[:space:]]*[a-z][a-z ]*[a-z]\]' "$doc" \
           | sed -E 's/^\[HARD[[:space:]]*[—-][[:space:]]*(.*)\]$/\1/' | sort -u || true)"
  hard_lane_names="$names"
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    hard_lanes+="[HARD - ${name}]"$'\n'
    hard_lanes+="[HARD — ${name}]"$'\n'
  done <<< "$names"
  hard_lanes="${hard_lanes%$'\n'}"

  names="$(grep -oE '\[INPUT[[:space:]]*[—-][[:space:]]*[a-z]+\]' "$doc" \
           | sed -E 's/^\[INPUT[[:space:]]*[—-][[:space:]]*(.*)\]$/\1/' | sort -u || true)"
  input_lane_names="$names"
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    input_lanes+="[INPUT - ${name}]"$'\n'
    input_lanes+="[INPUT — ${name}]"$'\n'
  done <<< "$names"
  input_lanes="${input_lanes%$'\n'}"

  if [[ -z "$hard_lanes" && -z "$input_lanes" ]]; then
    echo "lane-vocab: FATAL -- $doc declares NO lane markers; refusing to fall back to a hardcoded vocabulary (id:71d6). Fix the doc, do not guess." >&2
    return 1
  fi

  # `[ROUTINE]`, `[MECHANICAL]` and bare `[HARD]` are DELIMITER-LESS capability tags,
  # not `[HARD — <lane>]` family members, so the doc's lane table never enumerates
  # them. These three literals are the pre-existing spelling every reader already
  # carried; they are not a second copy of the LANE vocabulary.
  all_lane_tags=("[ROUTINE]" "[MECHANICAL]" "[HARD]")
  local t
  while IFS= read -r t; do [[ -n "$t" ]] && all_lane_tags+=("$t"); done <<< "$hard_lanes"
  while IFS= read -r t; do [[ -n "$t" ]] && all_lane_tags+=("$t"); done <<< "$input_lanes"
  return 0
}

# mask_backticks <str> -- replace every backtick-quoted span (backticks included)
# with '#' filler of the SAME LENGTH, so byte positions in the masked string line up
# with the original. A tag found only inside a masked span is a prose MENTION.
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

# leading_lane_run <line> -- the CONTIGUOUS run of recognized lane brackets at the
# very start of the item text (immediately after `- [ ] `/`- [x] `). A lane bracket
# appearing after any prose word is trailing audit-trail prose, not a live second
# lane on the item (id:1781) -- this helper isolates just the leading run so callers
# can count/inspect lane tags WITHOUT trailing-prose mentions inflating the count.
# Returns the matched tags space-joined (empty if the item opens with no lane tag).
leading_lane_run() {
  local line="$1" rest matched tag out=""
  if [[ "$line" =~ ^-[[:space:]]\[[[:space:]xX]\][[:space:]]*(.*)$ ]]; then
    rest="${BASH_REMATCH[1]}"
  else
    rest="$line"
  fi
  while :; do
    # trim leading whitespace
    while [[ "$rest" == [[:space:]]* ]]; do rest="${rest# }"; done
    matched=0
    for tag in "${all_lane_tags[@]}"; do
      if [[ "$rest" == "$tag"* ]]; then
        out+="$tag "
        rest="${rest#"$tag"}"
        matched=1
        break
      fi
    done
    [[ "$matched" -eq 1 ]] || break
  done
  printf '%s' "$out"
}
