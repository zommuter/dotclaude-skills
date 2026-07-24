#!/usr/bin/env bash
# relay/scripts/lib-typed-edges.sh — the shared id:46f6 typed-edge resolution engine.
#
# Extracted from meeting/orphan-scan.sh (id:46f6, meeting note
# docs/meeting-notes/2026-07-10-1430-typed-ledger-edges-umbrella-closure.md) so that a
# SECOND consumer — classify-repo.sh's `gated-on:` executor-readiness gate (id:65f5) —
# resolves typed edges through the SAME engine rather than a second inline copy
# (use-existing-tools). One engine, two callers.
#
# All markers are COMMENT-ANCHORED (form C): `<!-- gated-on:a,b -->`,
# `<!-- children:a,b -->`, `<!-- id:XXXX -->`. A bare or backticked `gated-on:xxxx`
# mention in prose is NOT an edge — this is the id:4da4/0d58 bare-substring trap the
# anchoring exists to close. Tokens are 4 hex digits.
#
# Source it (`source lib-typed-edges.sh`); it defines functions only, runs nothing.

# --- Anchored per-line extractors (echo the CSV payload, or nothing) ----------
# Only the comment-wrapped form matches; prose/backticked mentions never do.
typed_edges_children_of_line() { grep -oP '(?<=<!-- children:)[0-9a-f,]+(?= -->)' <<<"$1" || true; }
typed_edges_gated_of_line()    { grep -oP '(?<=<!-- gated-on:)[0-9a-f,]+(?= -->)' <<<"$1" || true; }
# An item's OWN id: the FIRST `<!-- id:XXXX -->` comment on the line (by convention only
# the item's own trailing id is comment-wrapped; body-prose ids are bare).
typed_edges_own_id_of_line()   { grep -oP '(?<=<!-- id:)[0-9a-f]{4}(?= -->)' <<<"$1" | head -1 || true; }
# id:8913 — settled-decision detection edges. Anchored ONLY: a bare `id:XXXX` mention
# or a backticked bare token (`e647`) under a Decisions heading is NOT an edge (the
# refuted D1(ii) bare-grep design, meeting 2026-07-24-0929) — these extractors only
# ever match the comment-wrapped form, exactly like the extractors above.
# `<!-- settles:XXXX -->` — authored on a meeting-note `## Decisions` bullet: this
# decision settles ledger item XXXX.
typed_edges_settles_of_line()    { grep -oP '(?<=<!-- settles:)[0-9a-f,]+(?= -->)' <<<"$1" || true; }
# `<!-- decided-in:<note-relpath> -->` — authored on the ledger item itself: a backref
# to the meeting note that decided it. The relpath has no spaces or `-->` by construction.
typed_edges_decided_in_of_line() { grep -oP '(?<=<!-- decided-in:)[^[:space:]]+(?= -->)' <<<"$1" || true; }

# --- token → checkbox-state resolution map ------------------------------------
# typed_edges_build_state_map <assoc-array-name> <file>...
#   Populates the named associative array: token → checkbox state ('x' when the
#   resolving line is `- [x]`, else ' ') for every `<!-- id:XXXX -->`-bearing checkbox
#   line across <file>... FIRST-WINS, so an active ledger entry beats a recycled archive
#   id (id:9221). Missing/unreadable files are skipped (grep -h … 2>/dev/null): a repo
#   without a TODO.archive.md is a normal state, not an error.
#
#   The CALLER decides the file set — that is the only difference between the two
#   consumers: orphan-scan resolves over TODO.md ∪ TODO.archive.md (ROADMAP drift is its
#   --cross-ledger job); classify-repo resolves over ROADMAP.md ∪ TODO.md ∪ TODO.archive.md
#   (an executor gate must see a target that lives only in ROADMAP).
typed_edges_build_state_map() {
  local -n _map="$1"; shift
  local l st tk
  while IFS= read -r l; do
    st=' '; [[ "$l" =~ ^[[:space:]]*-\ \[[xX]\]\  ]] && st='x'
    while read -r tk; do
      [[ -z "$tk" ]] && continue
      [[ -n "${_map[$tk]+x}" ]] || _map["$tk"]="$st"
    done < <(grep -oP '(?<=<!-- id:)[0-9a-f]{4}(?= -->)' <<<"$l" || true)
  done < <(grep -hE '^\s*- \[[ xX]\] ' "$@" 2>/dev/null || true)
}

# --- typed-edge set predicate -------------------------------------------------
# typed_edges_resolve_set <assoc-array-name> <csv>
#   Resolves a comma-separated token set against the state map. Echoes three
#   space-separated fields on one line:
#       <all_resolve:0|1> <all_closed:0|1> <dangling-token-csv>
#   where a token "resolves" iff it is a key in the map, and is "closed" iff its
#   state is 'x'. `all_resolve=0` iff any token is dangling (unresolvable); the
#   dangling tokens are listed (comma-joined) as the third field (empty when none).
#   This is the SAME predicate the umbrella (children) and gate (gated-on) branches
#   of orphan-scan compute, hoisted so both callers share it verbatim.
typed_edges_resolve_set() {
  local -n _m="$1"; local csv="$2"
  local -a toks; IFS=',' read -ra toks <<<"$csv"
  local all_resolve=1 all_closed=1; local -a dangling=()
  local t
  for t in "${toks[@]}"; do
    [[ -z "$t" ]] && continue
    if [[ -n "${_m[$t]+x}" ]]; then
      [[ "${_m[$t]}" == "x" ]] || all_closed=0
    else
      all_resolve=0; all_closed=0; dangling+=("$t")
    fi
  done
  local IFS=,
  echo "$all_resolve $all_closed ${dangling[*]}"
}
