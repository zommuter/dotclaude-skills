#!/usr/bin/env bash
# relay/scripts/lib-state-claim.sh — shared two-directional state-claim contradiction
# predicate (id:5533, AMENDS id:dafa). One engine, two callers — roadmap-lint.sh's
# DECIDED-LEFT-OPEN doctrine rule and todo-conformance.sh's TODO.md check MUST return
# the SAME verdict on identical line text, so both source this file instead of hand-
# rolling their own word list (mirrors lib-typed-edges.sh's "one engine, two callers"
# pattern, id:65f5).
#
# Two directions detected on an OPEN `- [ ]` item line:
#
#   (i)  VISIBLE-TEXT self-assertion — the item's own prose (outside any HTML
#        comment) asserts a terminal state about ITSELF: RESOLVED / DECIDED
#        <YYYY-MM-DD> / SUPERSEDED / DONE / CLOSED / DEFERRED. NOT a violation when
#        the assertion is SCOPED to a different id ("id:XXXX is SUPERSEDED by this"
#        — the terminal word applies to the CITED id, not to this item).
#
#   (ii) HTML-COMMENT close — one of the item's HTML comments asserts a close (any
#        of the same terminal words, or "closed YYYY-MM-DD") while the checkbox and
#        visible text both still say open. Evidence: loderite id:0e99 (via
#        routed:fb6e) — a close recorded ONLY in a comment held a ledger open for a
#        day, invisible to anything that reads visible text only.
#
# PRESENCE-only, never a date/git-blame comparison (the same lesson id:8913's D1(i)
# already learned: an edit-detecting rule is self-defeating).
#
# Source it (`source lib-state-claim.sh`); it defines functions only, runs nothing.

STATE_CLAIM_TERMINAL_RE='RESOLVED|SUPERSEDED|DONE|CLOSED|DEFERRED'
STATE_CLAIM_DECIDED_RE='[Dd]ecided[[:space:]]+[0-9]{4}-[0-9]{2}-[0-9]{2}'
STATE_CLAIM_CLOSED_DATE_RE='closed[[:space:]]+[0-9]{4}-[0-9]{2}-[0-9]{2}'

# state_claim_visible_text <line> — <line> with every `<!-- ... -->` HTML comment
# stripped. This repo's convention never nests a literal `>` inside a marker
# comment, so a simple non-`>` body match is sufficient (mirrors the anchored-id
# marker regexes' assumption elsewhere in this family).
state_claim_visible_text() {
  sed -E 's/<!--[^>]*-->//g' <<<"$1"
}

# state_claim_comments <line> — echoes each HTML-comment BODY (the text between
# `<!--` and `-->`) on its own line, or nothing if <line> has none.
state_claim_comments() {
  grep -oP '(?<=<!--)[^>]*(?=-->)' <<<"$1" || true
}

# state_claim_direction_i <line> — return 0 (VIOLATION) iff the line's VISIBLE
# text asserts a terminal state about the item itself; return 1 otherwise. A
# scoped assertion ("id:XXXX is SUPERSEDED") is stripped out before the check, so
# a decision note that only describes ANOTHER id's fate never fires here.
state_claim_direction_i() {
  local line="$1" visible stripped
  visible="$(state_claim_visible_text "$line")"
  stripped="$(sed -E "s/id:[0-9a-fA-F]{4}[[:space:]]+is[[:space:]]+(${STATE_CLAIM_TERMINAL_RE}|${STATE_CLAIM_DECIDED_RE})//g" <<<"$visible")"
  [[ "$stripped" =~ $STATE_CLAIM_TERMINAL_RE ]] && return 0
  [[ "$stripped" =~ $STATE_CLAIM_DECIDED_RE ]] && return 0
  return 1
}

# state_claim_direction_ii <line> — return 0 (VIOLATION) iff any HTML comment on
# <line> asserts a close (a terminal word, or "closed YYYY-MM-DD") while the
# checkbox is open. Callers are expected to only invoke this on an OPEN `- [ ]`
# line (the checkbox-open half of the precondition) — this function only
# inspects the comment bodies for the close-assertion half.
state_claim_direction_ii() {
  local line="$1" c
  while IFS= read -r c; do
    [[ -z "$c" ]] && continue
    if [[ "$c" =~ $STATE_CLAIM_TERMINAL_RE ]] || [[ "$c" =~ $STATE_CLAIM_DECIDED_RE ]] \
       || [[ "$c" =~ $STATE_CLAIM_CLOSED_DATE_RE ]]; then
      return 0
    fi
  done < <(state_claim_comments "$line")
  return 1
}

# state_claim_violation <line> — the single shared entrypoint both callers use.
# Echoes a comma-joined list of the fired direction tags ("i", "ii", "i,ii"), or
# an empty string when the line is clean. Callers should only invoke this on an
# OPEN `- [ ]` checkbox line.
state_claim_violation() {
  local line="$1"; local -a fired=()
  state_claim_direction_i "$line" && fired+=("i")
  state_claim_direction_ii "$line" && fired+=("ii")
  local IFS=,
  echo "${fired[*]}"
}

# state_claim_in_baseline <id> <baseline_file> — the WARN→ERROR boundary check
# (id:cb3e, gated on id:5533 shipping). Return 0 iff <id> (a bare 4-hex token, no
# `id:` prefix) appears as its own line in <baseline_file> (blank lines and `#`
# comment lines are ignored); return 1 otherwise (including a missing/unreadable
# file — fail OPEN to "not baselined", i.e. a missing baseline file makes every
# violation a "new" one rather than silently grandfathering everything).
#
# Membership is by ID ONLY, never by line text — a whole-line rewrite (the
# mandated edit path for `/meeting` write-back, `/relay human`, and `todo-update`,
# via `meeting/md-merge.py`, which replaces WHOLE LINES by id token) keeps the
# SAME id, so a baselined item stays correctly baselined even after its prose is
# rewritten wholesale. This is precisely what killed the earlier `git blame`
# author-time approach, which dates the last EDIT rather than the item's creation.
#
# KNOWN WEAKNESS: a stale baseline silently RE-GRANDFATHERS — an id captured here
# stays WARN-forever even if its violation is later re-introduced or changes
# shape. There is no expiry; regenerating the baseline is a deliberate, separate
# act (never automatic), same disclosure as the file's own header.
state_claim_in_baseline() {
  local id="$1" file="$2"
  [[ -n "$id" && -f "$file" ]] || return 1
  grep -vE '^[[:space:]]*(#|$)' "$file" | grep -qxF "$id"
}
