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
# NOT unified with scan-routed.sh / unpromoted-scan.sh's anchored checks (id:521f
# decision, recorded so this isn't re-litigated): those two solve a DIFFERENT
# problem shape — "does a SPECIFIC KNOWN token appear as some line's own marker",
# a presence check over a whole file/string (unpromoted-scan.sh is end-of-line-
# strict; scan-routed.sh is `routed:`-OR-`id:`-prefixed and spans two files) — not
# "extract the UNKNOWN owning id from THIS one line", tolerant of trailing prose
# AFTER the marker (e.g. `<!-- id:659c --> — 🚧 GATED (auto, id:3801; ...)`), which
# is what roadmap-lint needs. Forcing all three into one function would mean
# rewriting the other two scripts' already-shipped, tested (id:1312/d515)
# file-level grep passes into per-line loops for a stylistic dedup with no
# behavioural need — out of scope/risk for a ROUTINE item. This file is the
# reusable PRIMITIVE for the extraction shape; a future item can migrate other
# callers onto it if their anchoring semantics ever converge.

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
