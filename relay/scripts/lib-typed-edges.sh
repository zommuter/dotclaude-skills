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
# An item's OWN id — the single `<!-- id:XXXX -->` comment on the line.
#
# id:6059 — this used to be `| head -1` (FIRST wins). That was a silent POSITIONAL GUESS,
# and there is no safe positional rule: `<!-- id:X -->` means BOTH "this line IS X" and
# "this line REFERS to X" with identical syntax. A body that QUOTES a marker puts the own
# id LAST (this repo, TODO.md's `id:f346`); a TRAILING REFERENCE puts it FIRST (loderite
# ROADMAP.md L211/L229/L628, routed:3ad9 — three OPEN items each ending
# `<!-- id:XXXX --> <!-- id:50f3 -->` where 50f3 is a CLOSED item). Either guess
# mis-attributes one of the two shapes.
#
# So a multi-marker line resolves to NOTHING and says so on stderr. Empty is what every
# caller already handles for an id-less line, and it is the under-dispatch-safe /
# fail-open direction (gather-repo-state.sh skips the item; resolve-gates.sh emits no
# row). The real fix is a define-vs-refer grammar — routed:20ce / cartulary id:344d,
# NOT decided here. (Note gather-repo-state.sh:527 documents this helper as "the LAST
# marker"; that claim was never true of the code and is now wrong in the other
# direction — flagged for central correction, that file is not edited here.)
typed_edges_own_id_of_line() {
  local _te_ids
  _te_ids="$(grep -oP '(?<=<!-- id:)[0-9a-f]{4}(?= -->)' <<<"$1" || true)"
  if [[ "$(wc -l <<<"$_te_ids")" -gt 1 ]]; then
    echo "lib-typed-edges: AMBIGUOUS own id — line carries multiple anchored id markers ($(tr '\n' ' ' <<<"$_te_ids")); REFUSING to attribute it (id:6059): $1" >&2
    return 0
  fi
  printf '%s' "$_te_ids"
}
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
# `<!-- owner-hold:REASON -->` (id:d119) — an explicit owner decision that this item's
# gated-on target is INTENTIONALLY unclearable (e.g. the owner wants dispatch held back
# regardless of whether the technical gate ever resolves). REASON has no spaces, same
# token grammar as gated-on's CSV — free-text notes belong in the item's own body, not
# inside the comment. roadmap-lint's DEAD-GATE rule (3(d)) reads this to distinguish a
# deliberate hold from a genuinely dead/mistaken gate; it is SCOPED to that lint only —
# classify-repo.sh's dispatch gate does NOT read it (a separate, coordinated follow-up).
typed_edges_owner_hold_of_line() { grep -oP '(?<=<!-- owner-hold:)[^[:space:]]+(?= -->)' <<<"$1" || true; }

# --- DEP-prose vs typed gated-on (id:3f7e) ------------------------------------
# `(DEP: <id>)` / `(DEP <id>)` prose gate-annotations are NOT edges — same
# id:4da4/0d58 bare-substring trap the anchored extractors above exist to close.
# classify-repo.sh correctly ignores them; the hazard is an item whose ONLY gate
# is this untyped prose, so nothing mechanical ever sees it as blocked/unblocked.
# typed_edges_dep_prose_ids_of_line <line> — every 4-hex id immediately following
# a `(DEP:` / `(dep ` opener (case-insensitive on "dep", optional `id:` prefix),
# one per parenthetical. Backtick-quoted spans are masked first (sed strip) so a
# `(DEP: xxxx)` example inside a code span — documentation, not a live annotation
# — is never matched, mirroring the mask_backticks idiom used elsewhere.
typed_edges_dep_prose_ids_of_line() {
  local masked
  masked="$(sed -E 's/`[^`]*`//g' <<<"$1")"
  grep -oiP '\(dep:?\s*(?:id:)?\K[0-9a-f]{4}' <<<"$masked" || true
}

# typed_edges_dep_prose_untyped_of_line <line> — the subset of
# typed_edges_dep_prose_ids_of_line's ids that are NOT also present in this same
# line's `<!-- gated-on:… -->` marker (comma-joined output, empty when every DEP-
# prose id is typed, or when the line carries no DEP prose at all). This is the
# WARN condition id:3f7e enforces: prose says "gated on X" but no typed edge does.
typed_edges_dep_prose_untyped_of_line() {
  local line="$1" gated_csv dep_id out=() found=0
  gated_csv="$(typed_edges_gated_of_line "$line")"
  while IFS= read -r dep_id; do
    [[ -z "$dep_id" ]] && continue
    found=1
    case ",$gated_csv," in
      *",$dep_id,"*) ;;                # typed — not a violation
      *) out+=("$dep_id") ;;
    esac
  done < <(typed_edges_dep_prose_ids_of_line "$line")
  [[ "$found" -eq 0 ]] && return 0
  local IFS=,
  echo "${out[*]}"
}

# --- token → checkbox-state resolution map ------------------------------------
# typed_edges_build_state_map <assoc-array-name> <file>...
#   Populates the named associative array: token → checkbox state ('x' when the
#   resolving line is `- [x]`, else ' ') for every `<!-- id:XXXX -->`-bearing checkbox
#   line across <file>... FIRST-WINS, so an active ledger entry beats a recycled archive
#   id (id:9221). Missing/unreadable files are skipped (grep -h … 2>/dev/null): a repo
#   without a TODO.archive.md is a normal state, not an error.
#
#   The CALLER decides the file set. Both current consumers now resolve over all three
#   ledgers (id:9be0 added ROADMAP.md to orphan-scan's resolution map so a dependency on
#   a relay seam — which lives only in ROADMAP.md — is typeable): orphan-scan resolves
#   over TODO.md ∪ TODO.archive.md ∪ ROADMAP.md (first-wins in that order; ROADMAP-vs-TODO
#   *disagreement* about a shared id's checkbox state is still `--cross-ledger`'s job, not
#   this map's); classify-repo resolves over ROADMAP.md ∪ TODO.md ∪ TODO.archive.md (an
#   executor gate must see a target that lives only in ROADMAP).
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
