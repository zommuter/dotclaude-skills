#!/usr/bin/env bash
# roadmap-lint.sh — a GRAMMAR validator for OPEN ROADMAP items (id:09a3).
#
# Usage:
#   roadmap-lint.sh [<roadmap-path> | <repo-root>]
#     no arg          → lint <cwd repo>/ROADMAP.md (git rev-parse --show-toplevel)
#     a *.md file     → lint that file directly
#     a directory     → lint <dir>/ROADMAP.md
#
# WHY (audit 2026-06-23, user directive): rather than detecting a FIXED list of
# specific known issues, the relay should reject ANYTHING that doesn't match the
# proper open-item syntax — a POSITIVE grammar (extends id:415b
# grammar-tightening-with-loud-rejection). `gather-human-backlog.sh` already
# LOUD-rejects an untagged `[HARD]`, but is blind to (a) an open `- [ ]` item with
# NO class tag at all (e.g. a `[SEVERE]` item with no relay lane — invisible to BOTH
# the loop AND `/relay human`) and (b) a malformed/unknown lane outside the `[HARD]`
# family. A grammar catches every deviation, not just the ones we thought to look for.
#
# THE GRAMMAR (an open `- [ ]` top-level item under an ACTIVE section must match ALL):
#   1. a recognized class/lane tag — `[ROUTINE]` OR one of the hard-lanes.md lanes
#      (`[HARD — pool|meeting|hands|decision gate]`), optionally combined with an
#      `[INTENSIVE — <resource>]` modifier;
#   2. an `id:XXXX` (4-hex) token.
# Items under a GATED / DEFERRED / DONE / ICEBOX / ARCHIVE heading are EXEMPT
# (explicitly parked — not executor-classifiable by design). Closed `- [x]` items are
# NEVER linted. Continuation/indented lines are NEVER linted (only top-level `- [ ]`).
#
# The recognized lane set is READ from `relay/references/hard-lanes.md` (the single
# source of truth, id:78ff) — no second copy of the vocabulary lives here.
#
# OUTPUT: reports EVERY non-conforming active open item GENERICALLY (the offending
# line + its id if present + which grammar clause failed) to stdout, and EXITS
# NONZERO when any are found. A fully conforming ROADMAP is a clean zero-exit no-op.
# Details are also appended to ~/.claude/logs/relay-roadmap-lint.log.
#
# The lint does NOT auto-rewrite items — it surfaces violations for the strong/human
# turn to assign the lane (mirrors id:78ff's "back-fill belongs to each repo's next
# handoff/review/human" precedent).
set -euo pipefail

# --- resolve the ROADMAP path -------------------------------------------------
arg="${1:-}"
if [[ -z "$arg" ]]; then
  root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  roadmap="$root/ROADMAP.md"
elif [[ -d "$arg" ]]; then
  roadmap="$arg/ROADMAP.md"
else
  roadmap="$arg"
fi

[[ -f "$roadmap" ]] || { echo "roadmap-lint: no ROADMAP at $roadmap" >&2; exit 2; }

# --- recognized lane vocabulary, READ from hard-lanes.md (single source) -------
# Locate hard-lanes.md relative to THIS script (sibling references dir), so the
# lint never carries a private copy of the lane spelling.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
lanes_doc="$script_dir/../references/hard-lanes.md"

# Extract every `[HARD — <lane>]` marker from the canonical doc → an alternation
# of recognized hard-lane suffixes. Falls back to the documented set if the doc is
# somehow unreadable (fail-safe: never crash the lint on a missing doc, but log it).
hard_lanes=""
if [[ -f "$lanes_doc" ]]; then
  # Markers look like `[HARD — pool]`, `[HARD — decision gate]`, … (em dash U+2014).
  hard_lanes="$(grep -oE '\[HARD — [a-z][a-z ]*[a-z]\]' "$lanes_doc" | sort -u || true)"
fi
if [[ -z "$hard_lanes" ]]; then
  echo "roadmap-lint: WARNING — could not read lanes from $lanes_doc; using built-in fallback set" >&2
  hard_lanes=$'[HARD — pool]\n[HARD — meeting]\n[HARD — hands]\n[HARD — decision gate]'
fi

# Build a bash regex alternation of the lane suffixes (the part after `[HARD — `).
# e.g. "pool|meeting|hands|decision gate"
lane_alt="$(printf '%s\n' "$hard_lanes" \
  | sed -E 's/^\[HARD — (.*)\]$/\1/' \
  | paste -sd'|' -)"

# A recognized class/lane tag: [ROUTINE] OR [HARD — <recognized lane>].
# (The [INTENSIVE — …] modifier is orthogonal and may co-occur; we only require ONE
#  recognized class/lane tag to be present.)
class_re="\[ROUTINE\]|\[HARD — (${lane_alt})\]"

# A 4-hex id token, the canonical `<!-- id:XXXX -->` or a bare `id:XXXX`.
id_re='id:[0-9a-fA-F]{4}'

# --- section gating -----------------------------------------------------------
# An item is EXEMPT when its nearest preceding `## ` / `### ` heading names a parked
# bucket. Match case-insensitively on the heading text.
is_exempt_heading() {
  local h="$1"
  shopt -s nocasematch
  local exempt=1
  if [[ "$h" =~ (gated|deferred|done|icebox|archive|parked) ]]; then
    exempt=0
  fi
  shopt -u nocasematch
  return $exempt
}

# --- scan ---------------------------------------------------------------------
violations=0
report=""
in_exempt_section=0
heading_is_item=0

while IFS= read -r line; do
  # Track the active/exempt section from headings.
  if [[ "$line" =~ ^##+[[:space:]] ]]; then
    if is_exempt_heading "$line"; then
      in_exempt_section=1; heading_is_item=0
    else
      in_exempt_section=0
      # Heading-as-item (id:c095): a `## [LANE] Title <!-- id -->` heading IS the work
      # item — it owns the lane+id, and its child `- [ ]`/`- [x]` lines are STATUS
      # markers, not separate items (collaib's convention). Recognize it by a class tag
      # in the heading; its `- [ ]` children are then skipped below. The heading itself
      # must still carry an id (positive grammar — a heading-item missing its id is a
      # violation, so nothing hides).
      if [[ "$line" =~ $class_re ]]; then
        heading_is_item=1
        if ! [[ "$line" =~ $id_re ]]; then
          violations=$((violations + 1))
          report+="  - [<no id>] heading-as-item MISSING its id token"$'\n'
          report+="      ${line}"$'\n'
        fi
      else
        heading_is_item=0
      fi
    fi
    continue
  fi

  # Only TOP-LEVEL open checkbox items (`- [ ] …`, no leading indent) are linted.
  # Closed `- [x]` and indented continuation lines are skipped.
  [[ "$line" =~ ^-[[:space:]]\[[[:space:]]\][[:space:]] ]] || continue

  # Status sub-line of a heading-as-item (id:c095) — the heading already owns the
  # lane+id, so its bare `- [ ] Open` / `- [x] Done` status marker is not a violation.
  [[ "$heading_is_item" -eq 1 ]] && continue

  # Section-exempt items are explicitly parked → never linted.
  [[ "$in_exempt_section" -eq 1 ]] && continue

  # Grammar clause 1: a recognized class/lane tag.
  has_class=0
  [[ "$line" =~ $class_re ]] && has_class=1

  # Grammar clause 2: a 4-hex id token.
  has_id=0
  [[ "$line" =~ $id_re ]] && has_id=1

  # --- semantic checks (case c / case d) — only when a recognised class tag is present -----
  if [[ "$has_class" -eq 1 ]]; then
    # Case (c): tag/prose lane DISAGREEMENT — an item must carry exactly ONE recognised
    # lane bracket; if the prose also mentions a different lane bracket the tag is stale
    # (the tag is authority; the disagreement is a loud error, never a silent no-op).
    _lc=0; _lf=()
    echo "$line" | grep -qF '[ROUTINE]' && { _lc=$((_lc+1)); _lf+=('[ROUTINE]'); }
    while IFS= read -r _hl; do
      [[ -z "$_hl" ]] && continue
      echo "$line" | grep -qF "$_hl" && { _lc=$((_lc+1)); _lf+=("$_hl"); }
    done <<< "$hard_lanes"
    if [[ "$_lc" -gt 1 ]]; then
      violations=$((violations + 1))
      echo "roadmap-lint: ERROR — tag/prose lane conflict: item prose disagrees with tag lane (multiple lane brackets found: ${_lf[*]})" >&2
      echo "  $line" >&2
    fi

    # Case (d): free-typed [INTENSIVE] — INTENSIVE is valid ONLY on a [HARD — pool] item
    # (derivability criterion id:db39); pairing it with any other lane is a loud error.
    if echo "$line" | grep -qE '\[INTENSIVE — [^]]+\]'; then
      if ! echo "$line" | grep -qF '[HARD — pool]'; then
        violations=$((violations + 1))
        echo "roadmap-lint: ERROR — [INTENSIVE — ...] free-typed on a non-pool item; INTENSIVE must be derivable ([HARD — pool] required, per id:db39)" >&2
        echo "  $line" >&2
      fi
    fi
  fi

  [[ "$has_class" -eq 1 && "$has_id" -eq 1 ]] && continue

  # Build the violation report line.
  violations=$((violations + 1))
  # Extract the id if present, for a stable handle in the report.
  idtoken=""
  if [[ "$line" =~ ($id_re) ]]; then
    idtoken="${BASH_REMATCH[1]}"
  fi
  reasons=()
  [[ "$has_class" -eq 0 ]] && reasons+=("NO recognized class/lane tag ([ROUTINE] or [HARD — ${lane_alt}])")
  [[ "$has_id" -eq 0 ]] && reasons+=("MISSING its id token")
  reason_str="$(IFS='; '; echo "${reasons[*]}")"
  handle="${idtoken:-<no id>}"
  report+="  - [${handle}] ${reason_str}"$'\n'
  report+="      ${line}"$'\n'
done < "$roadmap"

# --- log (best-effort) --------------------------------------------------------
log="$HOME/.claude/logs/relay-roadmap-lint.log"
mkdir -p "$(dirname "$log")" 2>/dev/null || true
{
  printf '%s\troadmap-lint\t%s\tviolations=%d\n' \
    "$(date -Iseconds 2>/dev/null || date)" "$roadmap" "$violations"
} >> "$log" 2>/dev/null || true

# --- result -------------------------------------------------------------------
if [[ "$violations" -gt 0 ]]; then
  echo "roadmap-lint: $violations open ROADMAP item(s) violate the grammar in $roadmap"
  printf '%s' "$report"
  echo "Fix at source: assign a recognized lane tag ([ROUTINE] / [HARD — ${lane_alt}]) and a 4-hex id: token, or park the item under a gated/deferred heading."
  exit 1
fi

# Clean no-op.
exit 0
