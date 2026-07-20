#!/usr/bin/env bash
# roadmap-lint.sh — a GRAMMAR validator for OPEN ROADMAP items (id:09a3).
#
# Usage:
#   roadmap-lint.sh [--strict] [<roadmap-path> | <repo-root>]
#     no arg          → lint <cwd repo>/ROADMAP.md (git rev-parse --show-toplevel)
#     a *.md file     → lint that file directly
#     a directory     → lint <dir>/ROADMAP.md
#     --strict        → escalate the two DOCTRINE rules (DECOMPOSED-CONTAINER,
#                       DECIDED-LEFT-OPEN, id:8504/dafa) from report-only WARN to hard
#                       violations (nonzero exit). Without it those two rules are still
#                       emitted LOUD to stderr but do not fail the run; the GRAMMAR
#                       rules (class tag + id) always fail nonzero regardless.
#
# DOCTRINE rules (mechanize-first — each past LLM triage becomes a mechanical rule):
#   3(a) DECOMPOSED-CONTAINER: an OPEN `- [ ]` item whose body says DECOMPOSED (its
#        work was split into seams) must NOT carry a dispatchable/meeting lane — the
#        seams are the work. Tick it (superseded-by-seams) or mark it `@container`
#        (collectors exclude that marker). Fires LOUD; nonzero only under --strict.
#   3(b) DECIDED-LEFT-OPEN: an OPEN `- [ ]` item whose body records a conclusion
#        (DEFERRED / SUPERSEDED / "decided <YYYY-MM-DD>") is a decided item left open —
#        close it or drop the marker. Fires LOUD; nonzero only under --strict.
#   Both run only on OPEN items in ACTIVE sections (parked/exempt sections are skipped),
#   and NEVER silently filter — the offending line always prints to stderr.
#
# RECOGNIZED non-lane markers (id:a505): `@container` (DECOMPOSED parent), `@manual`
# (human must run/verify), and `@needs-auth` (blocked on a human-held secret /
# interactive-auth wall — see relay/references/hard-lanes.md) are KNOWN markers,
# orthogonal to the lane grammar. An item carrying `@needs-auth` alongside a valid lane
# tag + id is well-formed — the marker is NEVER flagged as an unknown/untagged token.
# (The AI-free lister that filters `@needs-auth` boxes is id:1750, not this validator.)
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

# --- resolve args: an optional --strict flag + at most one path ---------------
# --strict (id:8504/dafa) turns the two DOCTRINE rules below (DECOMPOSED-CONTAINER,
# DECIDED-LEFT-OPEN) from report-only WARN into hard violations (nonzero exit). The
# grammar rules (class tag + id) ALWAYS fail nonzero; --strict only escalates the two
# doctrine rules, so the everyday lint stays green while they are still emitted LOUD.
strict=0
arg=""
for a in "$@"; do
  case "$a" in
    --strict) strict=1 ;;
    *) arg="$a" ;;
  esac
done
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

# shellcheck source=relay/scripts/lib-anchored-id.sh
source "$script_dir/lib-anchored-id.sh"

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

# --- DUAL-VOCAB WINDOW (id:4f02, meeting 2026-07-02-1924 decision 2) -----------
# The target capability-keyed vocabulary (`[HARD]` bare + `[INPUT — meeting|decision|
# access]`) is ALSO read from hard-lanes.md's north-star section, so both spellings
# stay ERROR-free during the migration window without a second hardcoded copy here.
# Extract every `[INPUT — <kind>]` marker from the doc → an alternation of
# recognized INPUT kinds.
input_lanes=""
if [[ -f "$lanes_doc" ]]; then
  input_lanes="$(grep -oE '\[INPUT — [a-z]+\]' "$lanes_doc" | sort -u || true)"
fi
if [[ -z "$input_lanes" ]]; then
  echo "roadmap-lint: WARNING — could not read INPUT lanes from $lanes_doc; using built-in fallback set" >&2
  input_lanes=$'[INPUT — meeting]\n[INPUT — decision]\n[INPUT — access]'
fi
input_alt="$(printf '%s\n' "$input_lanes" \
  | sed -E 's/^\[INPUT — (.*)\]$/\1/' \
  | paste -sd'|' -)"

# A recognized class/lane tag: [ROUTINE] OR the [MECHANICAL] capability tag (id:7616 —
# pure-compute work no LLM/human runs; a daemon dispatches it, an LLM session reviews
# the artifact; A3 gated) OR a recognized lane in EITHER vocabulary during the dual-vocab
# window (id:4f02): the OLD venue-keyed `[HARD — <lane>]` spelling, or the NEW
# capability-keyed spelling — bare `[HARD]` or `[INPUT — <kind>]`. Neither vocabulary is
# a violation while the window is open; the window closes (old → ERROR) at the tail of
# B2 (id:8111), not here.
# The [INTENSIVE — …] modifier is orthogonal and may co-occur on ANY recognised lane —
# operative on dispatchable lanes (ROUTINE/pool/HARD/MECHANICAL), advisory-inert on human
# lanes (hands/meeting/decision gate/INPUT — *). A lane-less INTENSIVE item has no
# recognized class tag and is therefore caught by the missing-class-tag grammar below
# (id:9062).
class_re="\[ROUTINE\]|\[MECHANICAL\]|\[HARD\]|\[HARD — (${lane_alt})\]|\[INPUT — (${input_alt})\]"

# --- TAG-FIRST-AMONG-TRAILING lint (id:ad8a) -----------------------------------
# INVARIANT (id:4da4/id:0d58 PRIMARY-LANE anchoring): an item's genuine capability
# lane is the FIRST recognized lane-tag on the line. classify-repo.sh's LANE_TAGS
# `min()` anchors on the RAW first-position lane-tag (no backtick strip);
# gather-repo-state.sh's roadmap_primary_lane (id:1bbd) anchors on the first
# lane-tag AFTER stripping backtick-quoted spans. These two readers silently
# split-brain when a prose/backtick'd lane bracket precedes the genuine tag —
# classify-repo mis-anchors on the prose one while gather anchors on the genuine
# one. WARN (report-only) surfaces the disagreement without blocking the loop,
# per "observe before preventing" and because the id:4f02/8111 dual-vocab window
# actively churns lane-tag spellings.
all_lane_tags=("[ROUTINE]" "[MECHANICAL]" "[HARD]")
while IFS= read -r _hl; do
  [[ -n "$_hl" ]] && all_lane_tags+=("$_hl")
done <<< "$hard_lanes"
while IFS= read -r _il; do
  [[ -n "$_il" ]] && all_lane_tags+=("$_il")
done <<< "$input_lanes"

# first_lane_tag <line> <strip:0|1> — leftmost recognized lane-tag by byte
# position; strip=1 removes backtick-quoted spans first (mirrors id:1bbd),
# strip=0 leaves them (mirrors classify-repo.sh's raw min() scan).
first_lane_tag() {
  local line="$1" strip="$2" search tag prefix pos best_pos=-1 best_tag=""
  if [[ "$strip" -eq 1 ]]; then
    search="$(printf '%s' "$line" | sed -E 's/`[^`]*`//g')"
  else
    search="$line"
  fi
  for tag in "${all_lane_tags[@]}"; do
    case "$search" in
      *"$tag"*)
        prefix="${search%%"$tag"*}"; pos=${#prefix}
        if [[ "$best_pos" -lt 0 || "$pos" -lt "$best_pos" ]]; then
          best_pos=$pos; best_tag="$tag"
        fi ;;
    esac
  done
  printf '%s' "$best_tag"
}

# leading_lane_run <line> — the CONTIGUOUS run of recognized lane brackets at the
# very start of the item text (immediately after `- [ ] `/`- [x] `). A lane bracket
# appearing after any prose word is trailing audit-trail prose, not a live second
# lane on the item (id:1781) — this helper isolates just the leading run so callers
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

# item_id <line> — the item's OWN canonical id. ANCHORED (id:521f) to the
# `<!-- id:XXXX -->` HTML-comment marker via lib-anchored-id.sh's own_id_of_line —
# a bare `id:XXXX` prose mention (a dep citation, a seam id in a DECOMPOSED body)
# is NEVER used as the item's own id. Only when a line carries no HTML-comment
# marker at all does this fall back to the first bare `id:XXXX` token, purely so a
# malformed/legacy line still gets SOME display handle in a report line rather
# than an unconditional `<no id>` — that fallback is never used to satisfy the
# "has an id" grammar clause (see has_own_id_marker call sites below), only for
# display.
item_id() {
  local l="$1" tok
  if tok="$(own_id_of_line "$l")"; then printf '%s' "$tok"; return; fi
  if [[ "$l" =~ id:([0-9a-fA-F]{4}) ]]; then printf 'id:%s' "${BASH_REMATCH[1]}"; fi
}

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

# Slurp into an array (not a `read` pipe) so the heading-as-item detector (id:c095)
# can LOOK AHEAD at a heading's children before deciding whether the heading owns
# the lane+id itself, or is merely a descriptive SECTION title (id:dfe4 refinement).
mapfile -t _rl_lines < "$roadmap"

# section_has_tagged_child <start-index> — TRUE (return 0) when the span from
# <start-index> up to the NEXT `## ` heading (or EOF) contains at least one
# top-level checkbox line (`- [ ]` OR `- [x]`) that carries its OWN class tag AND
# its OWN id token on that SAME line. When true, the enclosing `## [LANE] …`
# heading is a descriptive SECTION title over already-tagged+ided children, NOT a
# heading-as-item — the child already satisfies the grammar on its own and the
# heading itself is not required to carry an id (id:dfe4). Returns FALSE (1) only
# when every child in the span is a BARE status marker (no own tag+id) — the
# genuine c095 shape (heading owns the lane+id over bare markers).
section_has_tagged_child() {
  local start="$1" j _sl
  for ((j = start; j < ${#_rl_lines[@]}; j++)); do
    _sl="${_rl_lines[$j]}"
    [[ "$_sl" =~ ^##+[[:space:]] ]] && return 1
    if [[ "$_sl" =~ ^-[[:space:]]\[[[:space:]xX]\][[:space:]] ]]; then
      [[ "$_sl" =~ $class_re ]] && has_own_id_marker "$_sl" && return 0
    fi
  done
  return 1
}

for ((_rl_i = 0; _rl_i < ${#_rl_lines[@]}; _rl_i++)); do
  line="${_rl_lines[$_rl_i]}"
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
      # violation, so nothing hides) — UNLESS the children themselves already carry
      # their OWN class tag + id, in which case the heading is a descriptive SECTION
      # title, not an item, and must NOT be flagged for a missing id (id:dfe4).
      if [[ "$line" =~ $class_re ]] && ! section_has_tagged_child $((_rl_i + 1)); then
        heading_is_item=1
        if ! has_own_id_marker "$line"; then
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

  # Grammar clause 2: the item's OWN `<!-- id:XXXX -->` marker (id:521f — anchored;
  # a bare prose-cited `id:XXXX` elsewhere on the line does NOT satisfy this).
  has_id=0
  has_own_id_marker "$line" && has_id=1

  # --- DOCTRINE rules (mechanize-first: each past LLM triage → a mechanical rule) ---
  # Both are LOUD (stderr) ALWAYS; they add to `violations` (nonzero exit) ONLY under
  # --strict, never silently filter. They run on OPEN, ACTIVE-section items only
  # (exempt sections already `continue`d above) — an item legitimately parked under a
  # Deferred/Gated/Icebox heading does NOT fire.
  _dr_label="WARN"; [[ "$strict" -eq 1 ]] && _dr_label="ERROR"

  # Rule 3(a) DECOMPOSED-CONTAINER (id:8504): an OPEN item whose body says DECOMPOSED
  # (its work was split into seams) must NOT carry a dispatchable/meeting lane — the
  # seams are the work, the parent is just a container. It must be TICKED
  # (superseded-by-seams) or carry an explicit `@container` marker that collectors
  # exclude (gather-human-backlog.sh skips `@container`). A decomposed parent still
  # wearing a live lane double-counts against its own seams.
  if [[ "$line" == *DECOMPOSED* && "$has_class" -eq 1 && "$line" != *@container* ]]; then
    _dc_id="$(item_id "$line")"
    echo "roadmap-lint: ${_dr_label} — DECOMPOSED-CONTAINER: open item ${_dc_id:-<no id>} says DECOMPOSED (into seams) yet still carries a dispatchable/meeting lane — a decomposed parent is a CONTAINER, its seams are the work; tick it (superseded-by-seams) or add an @container marker (collectors exclude it)" >&2
    echo "  $line" >&2
    [[ "$strict" -eq 1 ]] && violations=$((violations + 1))
  fi

  # Rule 3(b) DECIDED-LEFT-OPEN (id:dafa): an OPEN item whose body records a
  # conclusion (DEFERRED / SUPERSEDED / "decided <YYYY-MM-DD>") is a decided item
  # left un-ticked. LOUD: close it (tick + done-note) or drop the marker.
  decided_re='[Dd]ecided [0-9]{4}-[0-9]{2}-[0-9]{2}'
  if [[ "$line" == *DEFERRED* || "$line" == *SUPERSEDED* || "$line" =~ $decided_re ]]; then
    _do_id="$(item_id "$line")"
    echo "roadmap-lint: ${_dr_label} — DECIDED-LEFT-OPEN: open item ${_do_id:-<no id>} carries a decided/deferred/superseded marker but is still open — close it (tick + done-note) or drop the marker" >&2
    echo "  $line" >&2
    [[ "$strict" -eq 1 ]] && violations=$((violations + 1))
  fi

  # --- semantic checks (case c / case d) — only when a recognised class tag is present -----
  if [[ "$has_class" -eq 1 ]]; then
    # Case (c): tag/prose lane DISAGREEMENT — an item must carry exactly ONE recognised
    # lane bracket; if the prose also mentions a different lane bracket the tag is stale
    # (the tag is authority; the disagreement is a loud error, never a silent no-op).
    # [MECHANICAL] is a CAPABILITY lane in this count too (id:7616) — a
    # [MECHANICAL] + [HARD — pool] item carries two capability lanes on one item,
    # exactly like two [HARD — *] tags would, and is rejected here.
    # Only BARE (non-backtick'd) lane tags count (id:9078) — a lane tag mentioned
    # inside a backtick-quoted span (e.g. documenting `[HARD]` as an example) is
    # prose, not a second live lane on the item, and must not inflate the count.
    # Mirrors first_lane_tag's strip=1 idiom (id:1bbd/ad8a).
    # AND only the LEADING contiguous lane-bracket run counts (id:1781) — a lane
    # bracket appearing after any prose word (e.g. audit-trail text like "(was
    # [HARD — pool] before, re-laned to [ROUTINE])") is trailing prose, not a
    # second live lane, and must not trip the conflict either.
    _bare="$(leading_lane_run "$(printf '%s' "$line" | sed -E 's/`[^`]*`//g')")"
    _lc=0; _lf=()
    echo "$_bare" | grep -qF '[ROUTINE]' && { _lc=$((_lc+1)); _lf+=('[ROUTINE]'); }
    echo "$_bare" | grep -qF '[MECHANICAL]' && { _lc=$((_lc+1)); _lf+=('[MECHANICAL]'); }
    # Bare new-vocab [HARD] (id:4f02) — counted separately from the old `[HARD — *]`
    # spellings below so an item carrying BOTH (e.g. `[HARD — pool]` + `[HARD]`) is
    # correctly flagged as a two-lane conflict, never silently merged into one.
    echo "$_bare" | grep -qF '[HARD]' && { _lc=$((_lc+1)); _lf+=('[HARD]'); }
    while IFS= read -r _hl; do
      [[ -z "$_hl" ]] && continue
      echo "$_bare" | grep -qF "$_hl" && { _lc=$((_lc+1)); _lf+=("$_hl"); }
    done <<< "$hard_lanes"
    # New-vocab [INPUT — <kind>] lanes (id:4f02 dual-vocab window) count the same way.
    while IFS= read -r _il; do
      [[ -z "$_il" ]] && continue
      echo "$_bare" | grep -qF "$_il" && { _lc=$((_lc+1)); _lf+=("$_il"); }
    done <<< "$input_lanes"
    if [[ "$_lc" -gt 1 ]]; then
      violations=$((violations + 1))
      echo "roadmap-lint: ERROR — tag/prose lane conflict: item prose disagrees with tag lane (multiple lane brackets found: ${_lf[*]})" >&2
      echo "  $line" >&2
    fi

    # Case (d): [INTENSIVE — <resource>] on any recognised lane — ACCEPTED (id:9062,
    # meeting 2026-06-30-2238). INTENSIVE is operative on relay-dispatchable lanes
    # ([ROUTINE], [HARD — pool]) and advisory-inert on human lanes (hands/meeting/
    # decision gate/@manual). The dispatch hazard is already neutralised by gather's
    # top_intensive exclusion (id:a707), so a lint loud-reject is redundant AND wrong.
    # A lane-less [INTENSIVE] item (no recognised class tag) is already rejected by
    # the has_class=0 path above — no further check needed here.
    # (Supersedes the former id:db39 pool-only restriction.)

    # Case (tag-first, id:ad8a): the genuine (backtick-stripped) primary lane must
    # be the RAW first-position lane-tag too, else classify-repo.sh (no strip) and
    # gather-repo-state.sh (strip) silently anchor on different lanes. WARN only —
    # report-only, never increments `violations` / the nonzero exit. Wording must
    # name the ORDERING (first/precede/anchor) so it stays grep-separable from the
    # case-c "conflict"/"multiple lane brackets" message above (id:297b).
    _raw_first="$(first_lane_tag "$line" 0)"
    _genuine_first="$(first_lane_tag "$line" 1)"
    if [[ -n "$_genuine_first" && "$_raw_first" != "$_genuine_first" ]]; then
      echo "roadmap-lint: WARN — tag-first-among-trailing: a prose/backtick'd lane bracket precedes the genuine lane tag, so classify-repo's raw anchor disagrees with gather's primary-lane anchor (raw-first='${_raw_first}' genuine-first='${_genuine_first}')" >&2
      echo "  $line" >&2
    fi

    # Case (TAG-NOT-FIRST, id:4b37, d259 endgame (C)): the genuine lane tag must be
    # the FIRST non-whitespace token immediately after the checkbox, not merely the
    # leftmost among trailing tags (that's ad8a's split-brain check above — this one
    # fires on POSITION alone, even with zero backtick divergence, e.g. a title that
    # precedes an already-anchored, unambiguous tag). WARN-only (report-only, exit 0)
    # during the dual-vocab window — the flip to ERROR is 7df1's window-close step,
    # once the ledger has actually been run through `lane-convert --reorder`.
    if [[ -n "$_genuine_first" && "$line" =~ ^-\ \[\ \]\ (.*)$ ]]; then
      _after_checkbox="${BASH_REMATCH[1]}"
      # Trim leading whitespace AND markdown emphasis markers (*, _) directly
      # wrapping the tag (id:be0e — `**[ROUTINE] Title**` must anchor on the
      # BRACKET, not the literal first byte; a bold/italic wrapper touching the
      # tag is formatting, not a title/prose token preceding it).
      # Strip via a bracket-expression, NOT a literal ' ': a leading TAB
      # satisfies the loop guard but `${var# }` would never consume it → infinite
      # loop (audit Run 70). Guard and strip must match the same character class.
      while [[ "$_after_checkbox" == [[:space:]*_]* ]]; do _after_checkbox="${_after_checkbox:1}"; done
      if [[ "$_after_checkbox" != "$_genuine_first"* ]]; then
        _tnf_id="$(item_id "$line")"
        echo "roadmap-lint: WARN — TAG-NOT-FIRST: the lane tag '${_genuine_first}' is not the first token after the checkbox on ${_tnf_id:-<no id>} (report-only during the dual-vocab window; run lane-convert --reorder to fix)" >&2
        echo "  $line" >&2
      fi
    fi
  fi

  [[ "$has_class" -eq 1 && "$has_id" -eq 1 ]] && continue

  # Build the violation report line.
  violations=$((violations + 1))
  # Extract the id (anchored to the item's own marker; see item_id) for a stable
  # handle in the report — id:521f: this used to be an unanchored first-match
  # grab, which misattributed a violation to a CITED id when the line's own
  # trailing marker came later on the line.
  idtoken="$(item_id "$line")"
  reasons=()
  [[ "$has_class" -eq 0 ]] && reasons+=("NO recognized class/lane tag ([ROUTINE] / [HARD] / [HARD — ${lane_alt}] / [INPUT — ${input_alt}] / [MECHANICAL])")
  [[ "$has_id" -eq 0 ]] && reasons+=("MISSING its id token")
  reason_str="$(IFS='; '; echo "${reasons[*]}")"
  handle="${idtoken:-<no id>}"
  report+="  - [${handle}] ${reason_str}"$'\n'
  report+="      ${line}"$'\n'
done

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
  echo "Fix at source: assign a recognized lane tag ([ROUTINE] / [HARD] / [HARD — ${lane_alt}] / [INPUT — ${input_alt}] / [MECHANICAL]) and a 4-hex id: token, or park the item under a gated/deferred heading."
  exit 1
fi

# Clean no-op.
exit 0
