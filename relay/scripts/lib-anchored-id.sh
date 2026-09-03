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
# `<!-- id:XXXX -->` (optional internal whitespace, 4 hex digits). Body-prose mentions
# of other ids (seam ids, "dep: id:XXXX") are bare, un-wrapped text and never count.
ANCHORED_ID_MARKER_RE='<!--[[:space:]]*id:([0-9a-fA-F]{4})[[:space:]]*-->'

# --- TWO MARKERS ON ONE LINE: AMBIGUOUS — REFUSE LOUDLY, never guess (id:6059) --
# The convention above assumed only the item's own trailing id is ever comment-wrapped.
# That assumption is FALSE in practice, and there is NO SAFE POSITIONAL RULE, because
# `<!-- id:X -->` carries two OPPOSITE meanings with IDENTICAL syntax — "this line IS X"
# (define) and "this line REFERS to X" (refer). Both shapes are live, and they place the
# item's own id at opposite ends:
#
#   BODY QUOTES A MARKER  → the own id is LAST.
#   TRAILING REFERENCE    → the own id is FIRST.
#
# BOTH ORIGINAL EXAMPLES WENT STALE AND WERE REPLACED 2026-09-03. Recorded because the
# rot is the point, not an embarrassment: this is load-bearing prose in a shared library,
# and a GREEN consumer never re-reads it. Same class as resolve-gates.sh's header (said
# three ledgers while the code spanned four) and loderite's expect() failure message
# (structurally unreadable -- a passing test never prints it).
#   - It cited loderite's ROADMAP.md L211/L229/L628 as ending `<!-- id:XXXX --> <!-- id:50f3 -->`.
#     VERIFIED 2026-09-03: those lines carry ZERO id markers and that file has ZERO
#     two-marker lines. The shape is absent, not drifted.
#   - It cited THIS repo's `id:f346` for the quotes-a-marker shape. That line now carries
#     exactly ONE marker: today's id:0d7c shrink relocated the quoting prose into its note.
#     Worth knowing as a side effect -- moving bodies off head lines REMOVES this hazard
#     from the ledger, which is why the live population keeps shrinking.
#
# LIVE EXAMPLE, verified 2026-09-03 (re-verify before citing; that is the whole lesson):
#   TODO.md:679 (`routed:b52e`) carries FOUR markers -- 2f81 7756 2f81 7756 -- and this
#   library refuses it with status 3. The line is an annotation ABOUT id-misattribution,
#   and its own text says `2f81` "would land HERE instead of on the archived item that owns
#   it" (tracked as id:cc7e). So the act of DOCUMENTING a marker defect manufactured a
#   multi-marker line for every counter: the residue is the cost of the explanation. Until
#   the schema-not-sigil grammar lands, de-literalise a quoted marker.
#
# So LAST is wrong for the second shape exactly as FIRST is wrong for the first. Picking
# either is a silent WRONG ATTRIBUTION, and on a write path that is corruption — this is
# how roadmap-tick.sh performed an owner-reserved close of the WRONG item. Therefore this
# matcher REFUSES: it resolves NO id for a multi-marker line, returns a distinct status
# (3), and names the file/line/candidates on stderr. Loud refusal beats a wrong answer.
#
# This is a HOLDING position, not the fix. The real dissolution is a grammar that
# distinguishes define from refer (schema-not-sigil) — filed cross-repo as routed:20ce /
# cartulary id:344d, and NOT decided here. Until then, de-literalise quoted markers and
# spell references with a typed edge (`<!-- gated-on:XXXX -->`, `<!-- children:XXXX -->`)
# or a bare backticked token; roadmap-lint.sh flags offending lines (MULTI-ID).
#
# OWN_ID_AMBIGUOUS is the return status callers should special-case; 1 stays "no marker".
OWN_ID_AMBIGUOUS=3

# marker_tokens_of_line <line> <kind> — print every anchored <kind> token on <line>,
# one per line, in file order. <kind> is `id` or `routed`. Used by the own-* resolvers
# to detect (and name) the ambiguous multi-marker case.
marker_tokens_of_line() {
  grep -oE "<!--[[:space:]]*$2:[0-9a-fA-F]{4}[[:space:]]*-->" <<<"$1" \
    | grep -oE '[0-9a-fA-F]{4}' || true
}

# own_id_of_line <line> [context] — print "id:XXXX" for <line>'s own `<!-- id:XXXX -->`
# marker. A bare `id:XXXX` mention with no HTML-comment wrapper does NOT count.
#   exit 0 — resolved, token on stdout
#   exit 1 — no anchored marker at all
#   exit $OWN_ID_AMBIGUOUS (3) — MORE THAN ONE marker: refuses to guess, prints nothing
#            on stdout and names every candidate on stderr (see the note above; there is
#            no safe positional rule). Optional <context> (e.g. "TODO.md:412") is echoed
#            in the message so the caller's location reaches the operator.
own_id_of_line() {
  local line="$1" ctx="${2:-}" toks
  mapfile -t toks < <(marker_tokens_of_line "$line" id)
  case "${#toks[@]}" in
    0) return 1 ;;
    1) printf 'id:%s' "${toks[0]}"; return 0 ;;
  esac
  echo "lib-anchored-id: AMBIGUOUS own id${ctx:+ at $ctx} — line carries ${#toks[@]} anchored id markers (${toks[*]}) and the grammar cannot tell 'this line IS X' from 'this line REFERS to X'; REFUSING to attribute it (id:6059). De-literalise a quoted marker, or spell a reference as a typed edge." >&2
  return "$OWN_ID_AMBIGUOUS"
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
# check — so a fourth copy is not written. Originally modelled on scan-routed.sh's twin
# check (its `grep -qsE -- "(routed|id):$tok([^0-9a-f]|$)"`), which anchors on the marker
# PREFIX + a trailing token boundary instead of a bare substring — **that prefix anchor
# was never ownership, and the difference destroyed data; see the id:c97c block below,
# which replaces the predicate for `token_marker_in_*`**. A bare
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
# Same three-way contract as own_id_of_line: 0 resolved / 1 absent / 3 ambiguous.
own_routed_of_line() {
  local line="$1" ctx="${2:-}" toks
  mapfile -t toks < <(marker_tokens_of_line "$line" routed)
  case "${#toks[@]}" in
    0) return 1 ;;
    1) printf 'routed:%s' "${toks[0]}"; return 0 ;;
  esac
  echo "lib-anchored-id: AMBIGUOUS own routed token${ctx:+ at $ctx} — line carries ${#toks[@]} anchored routed markers (${toks[*]}); REFUSING to attribute it (id:6059)." >&2
  return "$OWN_ID_AMBIGUOUS"
}

# own_token_of_line <line> [context] — print "id:XXXX" or "routed:XXXX" for <line>'s own
# marker, whichever kind it is.
#   exit 0 — resolved / exit 1 — no marker / exit $OWN_ID_AMBIGUOUS (3) — refused, loud.
# An INBOUND ingest stub legitimately carries BOTH kinds (`<!-- routed:AAAA --> …
# <!-- id:BBBB -->`): they are distinct namespaces with distinct meanings ("came from"
# vs "is"), so that is NOT ambiguity — the `id:` marker is the own token, and `id:` is
# therefore consulted first. Ambiguity is two markers of the SAME kind.
own_token_of_line() {
  # `|| rc=$?` (never a bare `; rc=$?`) — this lib is sourced into `set -e` scripts,
  # where a failing command substitution in a plain assignment aborts the caller.
  local line="$1" ctx="${2:-}" tok rc=0
  tok="$(own_id_of_line "$line" "$ctx")" || rc=$?
  [[ $rc -eq 0 ]] && { printf '%s' "$tok"; return 0; }
  [[ $rc -eq "$OWN_ID_AMBIGUOUS" ]] && return "$OWN_ID_AMBIGUOUS"
  rc=0
  tok="$(own_routed_of_line "$line" "$ctx")" || rc=$?
  [[ $rc -eq 0 ]] && { printf '%s' "$tok"; return 0; }
  [[ $rc -eq "$OWN_ID_AMBIGUOUS" ]] && return "$OWN_ID_AMBIGUOUS"
  return 1
}

# _valid_tok <tok> — a token is exactly 4 hex digits. A malformed token is a LOUD
# reject (return 2) in the presence checks below, never a silent false answer.
_valid_tok() { [[ "$1" =~ ^[0-9a-fA-F]{4}$ ]]; }

# --- OWN-MARKER twin presence (id:c97c) ----------------------------------------
# The presence checks below decide whether a routed inbox item "already landed" in its
# target repo — and that verdict authorises a DESTRUCTIVE, effectively unrecoverable
# `append.sh inbox-done` (vanish-on-resolve). So the bar is not "the token occurs
# somewhere"; it is "the token is some line's OWN marker".
#
# The ORIGINAL predicate was `(routed|id):$tok([^0-9a-f]|$)`. It anchors the PREFIX and a
# trailing token boundary — enough to reject an `HHMM` filename timestamp or a longer
# hash (id:d515/1312, still rejected below) — but it does NOT require ownership, so a
# prose cross-reference inside ANOTHER item's body satisfies it:
#     ... the bigger gap is the sibling item `routed:057f` ...
# (the trailing backtick is a valid boundary). VERIFIED LIVE 2026-08-14: three inbox
# items were deleted, never filed, and had to be recovered by hand from
# `git show HEAD:todo-inbox.md`. It is SELF-INFLICTED and INTRA-RUN — `scan-routed.sh
# --apply` writes item A's INBOUND stub (citation and all) into the target TODO.md, then
# iterates on to the cited token B, re-greps the file it just wrote, and drains B. Hence
# ORDER-DEPENDENT and intermittent. The id:9fdb "refuse without a twin" guard in
# `inbox-done` calls straight into here, so it was not bypassed — it was SATISFIED BY THE
# WRONG THING. (The `id:3add` header comment above, and the global CLAUDE.md line calling
# this check "anchored to the marker, not a bare-token grep", both described an ownership
# property the code never had — doc-vs-code drift, corrected here.)
#
# THE TWO OWNING FORMS in this corpus, and only these:
#   1. an HTML-comment marker — `<!-- routed:XXXX -->` or `<!-- id:XXXX -->`;
#   2. the INGEST-STUB prefix — a checkbox line whose LEADING bracket tags include
#      `[INBOUND routed:XXXX …]`, i.e. `- [ ] [LANE] [INBOUND routed:XXXX from src] …`.
# Form 2 is load-bearing, not a nicety: it is exactly the line `scan-routed.sh --apply`
# writes when it files an item (the stub's own HTML comment carries the freshly MINTED
# target id, never the routed token), and it is the ONLY marker most already-ingested
# items carry — 176 such lines in this repo's TODO.md alone. Dropping it would make every
# past ingest re-file forever and make `inbox-done` refuse right after a successful write.
# The `^`-anchored leading-tag sequence is what keeps it honest: a mid-sentence
# "(INBOUND routed:XXXX from …)" inside a body does NOT match.
#
# A bare `routed:XXXX` / `id:XXXX` in running prose NEVER counts.

# _own_marker_re <tok> — the ERE matching <tok> in either owning form. Both alternatives
# are line-scoped, so this is safe to grep over a whole file.
_own_marker_re() {
  local tok="$1"
  printf '(<!--[[:space:]]*(id|routed):%s[[:space:]]*-->)|(^- \[[ xX]\] (\[[^]]*\] )*\[INBOUND routed:%s[^0-9a-fA-F])' \
    "$tok" "$tok"
}

# token_marker_in_text <tok>  (text on stdin) — return 0 iff <tok> is some line's OWN
# marker in the piped text (see the two owning forms above). This is scan-routed.sh's
# twin check in string form. Return 2 (loud) on a malformed <tok>; 1 if absent.
token_marker_in_text() {
  local tok="$1"
  _valid_tok "$tok" || return 2
  grep -qE -- "$(_own_marker_re "$tok")"
}

# token_marker_in_files <tok> <file>... — same own-marker check over one or more files
# (missing/unreadable files are skipped via grep -s, mirroring scan-routed.sh which greps
# TODO.md + ROADMAP.md that may not both exist). Return 2 on a malformed <tok>; 0 if
# present in any file; 1 if absent from all.
token_marker_in_files() {
  local tok="$1"; shift
  _valid_tok "$tok" || return 2
  grep -qsE -- "$(_own_marker_re "$tok")" "$@"
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
