#!/usr/bin/env bash
# relay/scripts/lib-anchored-id.sh — shared "extract an item's OWN id from its
# canonical trailing `<!-- id:XXXX -->` HTML-comment marker" helper (id:521f).
#
# WHY: roadmap-lint.sh used to extract an item's id via an UNANCHORED first-match
# `id:[0-9a-fA-F]{4}` grab over the whole line. A line whose PROSE cites another
# token before its own trailing marker (e.g. "dep: id:1643 ... <!-- id:4148 -->")
# misattributed violations to the cited id (zkWhale ROADMAP id:4148 reported as
# `[id:1643]`), and a line with NO own marker but SOME prose-cited id passed the
# "has an id" grammar clause clean — the loud-reject this lint exists for never
# fired. Fix: anchor extraction to the `<!-- id:XXXX -->` HTML-comment form
# specifically — a bare `id:XXXX` mention in prose never counts as the line's own id.
#
# TWO problem shapes live here, sharing the same anchored marker regexes:
#   (A) EXTRACT the UNKNOWN owning token from THIS one line — own_id_of_line /
#       own_routed_of_line / own_token_of_line — tolerant of trailing prose AFTER
#       the marker (e.g. `<!-- id:659c --> — 🚧 GATED (auto, id:3801; ...)`), which
#       is what roadmap-lint needs.
#   (B) PRESENCE of a SPECIFIC KNOWN token as an anchored `(id|routed):XXXX` marker
#       over a whole string/file — token_marker_in_text / token_marker_in_files
#       (scan-routed.sh's `routed:`-OR-`id:` twin check spanning two files) and
#       token_own_checkbox_marker_in_text (unpromoted-scan.sh's checkbox-own form).
#
# id:521f (the original) shipped only shape (A) and DEFERRED unifying (B), to avoid
# rewriting the other scripts' shipped/tested (id:1312/d515) file-level grep passes
# for a stylistic dedup. id:3add reopens that narrowly: it ADDS the shape-(B)
# primitives here (a fourth hand-rolled copy was imminent — the family now includes
# roadmap-lint's first-match id_re, unpromoted-scan's grep, inbox-done's `routed:`
# substring, md-merge's fail-open id match). This item ships + tests the PRIMITIVE
# ONLY; migrating those 4 callers onto it is a deliberately SEPARATE follow-up (keeps
# the change disjoint and avoids a broad regression across shipped grep passes).

# Canonical marker regex: an item's own id lives in an HTML comment,
# `<!-- id:XXXX -->` (optional internal whitespace, 4 hex digits). Only the FIRST
# such comment on a line is treated as the item's own marker — by convention only
# the item's own trailing id is ever HTML-comment-wrapped; body-prose mentions of
# other ids (seam ids, "dep: id:XXXX") are bare, un-wrapped text.
ANCHORED_ID_MARKER_RE='<!--[[:space:]]*id:([0-9a-fA-F]{4})[[:space:]]*-->'

# own_id_of_line <line> — print "id:XXXX" for <line>'s own `<!-- id:XXXX -->`
# marker, or print nothing (and return 1) if no such marker is present. A bare
# `id:XXXX` mention with no HTML-comment wrapper does NOT count.
own_id_of_line() {
  local line="$1"
  if [[ "$line" =~ $ANCHORED_ID_MARKER_RE ]]; then
    printf 'id:%s' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

# has_own_id_marker <line> — boolean: does <line> carry its own HTML-comment id
# marker? Same anchoring as own_id_of_line, exit-status form for callers that only
# need the boolean (e.g. a grammar's "has an id" clause).
has_own_id_marker() {
  [[ "$1" =~ $ANCHORED_ID_MARKER_RE ]]
}

# --- routed-token variant + KNOWN-token presence checks (id:3add) --------------
# The above two functions cover the FIRST hand-rolled shape (extract an item's own
# UNKNOWN id from a line). The functions below add the two OTHER shapes the same
# family of callers hand-rolls — the `routed:` extraction variant, and the "does a
# SPECIFIC KNOWN token appear as an anchored `(id|routed):XXXX` marker" presence
# check — so a fourth copy is not written. Modelled on scan-routed.sh's twin check
# (its `grep -qsE -- "(routed|id):$tok([^0-9a-f]|$)"`), which already anchors on the
# marker prefix + a trailing token boundary instead of a bare substring. A bare
# substring grep false-matches a meeting-note filename's `YYYY-MM-DD-HHMM` timestamp
# and any longer hash containing the same 4 hex chars — the silent false-clean this
# family exists to prevent (scan-routed id:d515, unpromoted-scan id:1312, inbox-done
# routed-substring). Caller migration onto these is a SEPARATE follow-up (this item
# only ships + tests the primitive; see the id:3add report).

# Routed marker: an inbox item's own routed token lives in `<!-- routed:XXXX -->`.
ANCHORED_ROUTED_MARKER_RE='<!--[[:space:]]*routed:([0-9a-fA-F]{4})[[:space:]]*-->'
# Combined: an item's own trailing marker is EITHER an id or a routed token.
ANCHORED_TOKEN_MARKER_RE='<!--[[:space:]]*(id|routed):([0-9a-fA-F]{4})[[:space:]]*-->'

# own_routed_of_line <line> — print "routed:XXXX" for <line>'s own
# `<!-- routed:XXXX -->` marker, or nothing (return 1). A bare `routed:XXXX` prose
# citation of a SIBLING item's token does NOT count; an `<!-- id:XXXX -->` marker
# does NOT count. Mirrors own_id_of_line for the routed namespace.
own_routed_of_line() {
  local line="$1"
  if [[ "$line" =~ $ANCHORED_ROUTED_MARKER_RE ]]; then
    printf 'routed:%s' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

# own_token_of_line <line> — print "id:XXXX" or "routed:XXXX" for <line>'s own
# trailing marker, whichever kind it is (id preferred if — by malformed convention —
# both appear, since the regex takes the first match), or nothing (return 1).
own_token_of_line() {
  local line="$1"
  if [[ "$line" =~ $ANCHORED_TOKEN_MARKER_RE ]]; then
    printf '%s:%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    return 0
  fi
  return 1
}

# _valid_tok <tok> — a token is exactly 4 hex digits. A malformed token is a LOUD
# reject (return 2) in the presence checks below, never a silent false answer.
_valid_tok() { [[ "$1" =~ ^[0-9a-fA-F]{4}$ ]]; }

# token_marker_in_text <tok>  (text on stdin) — return 0 iff <tok> appears anywhere
# in the piped text as an ANCHORED `(id|routed):<tok>` marker, bounded by a non-hex
# char (or end of line). This is scan-routed.sh's twin check in string form. Return
# 2 (loud) on a malformed <tok>; return 1 if absent.
token_marker_in_text() {
  local tok="$1"
  _valid_tok "$tok" || return 2
  grep -qE -- "(routed|id):$tok([^0-9a-f]|\$)"
}

# token_marker_in_files <tok> <file>... — same anchored twin check over one or more
# files (missing/unreadable files are skipped via grep -s, mirroring scan-routed.sh
# which greps TODO.md + ROADMAP.md that may not both exist). Return 2 on a malformed
# <tok>; 0 if present in any file; 1 if absent from all.
token_marker_in_files() {
  local tok="$1"; shift
  _valid_tok "$tok" || return 2
  grep -qsE -- "(routed|id):$tok([^0-9a-f]|\$)" "$@"
}

# token_own_checkbox_marker_in_text <tok>  (text on stdin) — return 0 iff some
# CHECKBOX line (`- [ ]` or `- [x]`) carries <tok> as its OWN `<!-- id:XXXX -->`
# marker. This is unpromoted-scan.sh's twin check (id:1312): a bare prose citation of
# <tok> inside ANOTHER item's body must NOT count, but trailing prose AFTER the marker
# (id:798d, e.g. `<!-- id:XXXX --> — GATED (auto, id:3801)`) still does. Return 2 on
# a malformed <tok>; 1 if no checkbox line owns the marker.
token_own_checkbox_marker_in_text() {
  local tok="$1"
  _valid_tok "$tok" || return 2
  grep -qE "^- \[[ x]\].*<!--[[:space:]]*id:${tok}[[:space:]]*-->"
}
