#!/usr/bin/env bash
# pre-commit-lane-vocab.sh (id:9ef7) — a git `pre-commit` hook that BLOCKS a commit whose
# `git diff --cached` ADDED lines introduce an old-vocab lane tag
# (`[HARD — pool|meeting|hands|decision gate]`) as a TAG (not prose) — exit nonzero, naming
# the new-vocab replacement. Existing old-vocab tags (context / pre-existing / unchanged
# lines) WARN only — grandfathered, never block. New-vocab tags never fire.
#
# Owner chose HARD-DENY (TODO id:9ef7) — unlike the WARN+LOG privacy gate (id:ebd0), this
# hook actually blocks. `git commit --no-verify` is the escape hatch.
#
# Tag-vs-prose classification reuses the id:4da4-anchored parser idiom (mask_backticks +
# leftmost-tag-by-byte-position), the SAME technique `relay/scripts/lane-convert.sh` and
# `relay/scripts/roadmap-lint.sh` (first_lane_tag, strip=1) use — NOT a fresh grep. A
# backtick-quoted lane mention in an added PROSE line (e.g. a "re-laned `[HARD — pool]`"
# note) is masked out before the scan, so it never counts as a live tag (id:0d58 class).
# Only a CHECKBOX line's (`- [ ]`/`- [x]`) genuine PRIMARY lane tag — the leftmost
# recognized lane bracket once backtick spans are masked — can trigger a block.
#
# The old→new mapping mirrors `relay/scripts/lane-convert.sh`'s auto-rename table:
#   [HARD — pool]           → [HARD]
#   [HARD — meeting]        → [INPUT — meeting]
#   [HARD — decision gate]  → [INPUT — decision]
#   [HARD — hands]          → (no auto-default; four candidates, pick by judgment — see
#                              lane-convert.sh's NEEDS JUDGMENT message)
#
# Self-gated to relay-onboarded repos via `relay/scripts/lib-own-repos.sh` (honors the
# `# path:` comment override) — mirrors `hooks/pre-push-privacy-gate.sh`'s relay-scoping so
# the global `core.hooksPath` install stays convenient (one install, no per-repo onboarding)
# without firing inside every throwaway/hermetic-test repo. FAIL-OPEN TO SCAN, same as the
# privacy gate: relay.toml absent/unparseable, unknown repo root, or a missing helper never
# skips the scan — only a PRESENT, PARSEABLE relay.toml that does NOT list this repo skips.
#
# Env:
#   LANE_VOCAB_RELAY_TOML   override for $RELAY_TOML (default ~/.config/relay/relay.toml)
#   LANE_VOCAB_ALL_REPOS=1  scan every repo, ignoring the own-repo set
#
# Git calls a pre-commit hook with no args, cwd = repo root (or below it); this hook does
# not depend on cwd beyond that.
set -uo pipefail   # not -e: an internal hiccup must never silently pass OR silently block —
                    # every exit path below is explicit.

SELF="$(readlink -f "$0" 2>/dev/null || echo "$0")"
# This repo's own root (holds relay/, hooks/, …) — kept distinct from the $SRC_DIR name
# lib-own-repos.sh expects (that one means "~/src, the repos root"), so the two never
# collide when own_lib is sourced below.
HOOK_REPO_DIR="$(cd "$(dirname "$SELF")/.." && pwd)"

notice() { printf 'lane-vocab: %s\n' "$*" >&2; }

# ── Relay-scoping: only run inside repos in the relay OWN-repo set ─────────────────────
if [[ "${LANE_VOCAB_ALL_REPOS:-}" != "1" ]]; then
  repo_top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  RELAY_TOML="${LANE_VOCAB_RELAY_TOML:-${RELAY_TOML:-${XDG_CONFIG_HOME:-$HOME/.config}/relay/relay.toml}}"
  own_lib="$HOOK_REPO_DIR/relay/scripts/lib-own-repos.sh"
  if [[ -n "$repo_top" && -f "$RELAY_TOML" && -r "$own_lib" ]]; then
    SRC_DIR="${SRC_DIR:-$HOME/src}"   # lib-own-repos.sh's own $SRC_DIR contract (repos root)
    own_out=""; own_rc=0
    own_out="$(RELAY_TOML="$RELAY_TOML" SRC_DIR="$SRC_DIR"; source "$own_lib" && own_repos 2>/dev/null)" || own_rc=$?
    if [[ "$own_rc" -eq 0 ]]; then   # parsed cleanly → membership is authoritative
      member=0
      while IFS=$'\t' read -r _name p; do
        [[ -n "$p" ]] || continue
        rp="$(readlink -f "$p" 2>/dev/null || echo "$p")"
        [[ "$rp" == "$repo_top" ]] && { member=1; break; }
      done <<< "$own_out"
      if [[ "$member" -eq 0 ]]; then
        notice "repo '$repo_top' is not in the relay own-repo set — no-op (LANE_VOCAB_ALL_REPOS=1 to scan all)."
        exit 0
      fi
    fi
    # own_rc != 0 (relay.toml parse error) → fall through to SCAN (fail-open)
  fi
  # relay.toml absent / repo root unknown / helper unreadable → fall through to SCAN
fi

# ── id:4da4-anchored lane-tag vocabulary (mirrors lane-convert.sh / roadmap-lint.sh) ────
lanes_doc="$HOOK_REPO_DIR/relay/references/hard-lanes.md"

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
while IFS= read -r _hl; do [[ -n "$_hl" ]] && all_lane_tags+=("$_hl"); done <<< "$hard_lanes"
while IFS= read -r _il; do [[ -n "$_il" ]] && all_lane_tags+=("$_il"); done <<< "$input_lanes"

# old-vocab tags = the [HARD — <lane>] set (everything in hard_lanes); new-vocab [HARD]
# (bare) is never old-vocab.
declare -A old_vocab_replacement=(
  ["[HARD — pool]"]="[HARD]"
  ["[HARD — meeting]"]="[INPUT — meeting]"
  ["[HARD — decision gate]"]="[INPUT — decision]"
)
# [HARD — hands] has no 1:1 auto-default (fragments across 4 candidates, mirrors
# lane-convert.sh's NEEDS JUDGMENT handling) — named specially below.

# mask_backticks <str> — replace every backtick-quoted span (backticks included) with '#'
# filler of the SAME LENGTH, so byte positions line up with the original. A tag found only
# inside a masked span is a prose MENTION, not a live lane tag.
mask_backticks() {
  local s="$1" out="" c i in_tick=0
  for (( i=0; i<${#s}; i++ )); do
    c="${s:i:1}"
    if [[ "$c" == '`' ]]; then
      in_tick=$((1 - in_tick)); out+='#'
    elif [[ "$in_tick" -eq 1 ]]; then
      out+='#'
    else
      out+="$c"
    fi
  done
  printf '%s' "$out"
}

# first_lane_tag <line> — leftmost recognized lane tag by byte position, AFTER masking
# backtick-quoted spans (mirrors roadmap-lint.sh's first_lane_tag strip=1 / lane-convert.sh's
# rename_rest anchoring idiom). Only fires on a CHECKBOX line's rest-of-line text.
first_lane_tag() {
  local line="$1" masked tag prefix pos best_pos=-1 best_tag=""
  masked="$(mask_backticks "$line")"
  for tag in "${all_lane_tags[@]}"; do
    case "$masked" in
      *"$tag"*)
        prefix="${masked%%"$tag"*}"; pos=${#prefix}
        if [[ "$best_pos" -lt 0 || "$pos" -lt "$best_pos" ]]; then
          best_pos=$pos; best_tag="$tag"
        fi ;;
    esac
  done
  printf '%s' "$best_tag"
}

# ── Collect ADDED lines from the staged diff ────────────────────────────────────────────
diff_out="$(git diff --cached -U0 --no-color 2>/dev/null || true)"

violations=""
while IFS= read -r dl; do
  [[ "$dl" == +++* ]] && continue
  [[ "$dl" == +* ]] || continue
  content="${dl:1}"
  # Only a `- [ ]`/`- [x]` checkbox line carries a genuine lane tag.
  [[ "$content" =~ ^-[[:space:]]\[[[:space:]xX]\][[:space:]]+(.*)$ ]] || continue
  rest="${BASH_REMATCH[1]}"
  tag="$(first_lane_tag "$rest")"
  [[ -n "$tag" ]] || continue
  if [[ -n "${old_vocab_replacement[$tag]:-}" ]]; then
    violations+="  ${tag} → ${old_vocab_replacement[$tag]}    | ${content}"$'\n'
  elif [[ "$tag" == "[HARD — hands]" ]]; then
    violations+="  ${tag} → (no auto-default — pick one of [MECHANICAL] / [INPUT — access] / [INPUT — decision] / [INPUT — meeting], see lane-convert.sh)    | ${content}"$'\n'
  fi
done <<< "$diff_out"

if [[ -n "$violations" ]]; then
  {
    echo "lane-vocab: BLOCKED — a staged (added) line introduces an old-vocab lane tag."
    echo "lane-vocab: replace it with the new-vocab tag named below, or use --no-verify to skip this check."
    printf '%s' "$violations"
  } >&2
  exit 1
fi

exit 0
