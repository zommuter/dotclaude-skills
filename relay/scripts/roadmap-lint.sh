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
#   3(g) PARKED-POOL-LANE (id:d35a, owner ruling 2026-08-27): the ONE rule that runs
#        INSIDE an already-exempt/parked section, not an active one. An OPEN `- [ ]`
#        item under a parked heading must NOT carry a pool-executable lane tag
#        (`[ROUTINE]` or `[HARD — pool]`) — a human/non-dispatch lane there
#        (`[HARD — meeting|hands|decision gate]`, any `[INPUT — …]`, `[MECHANICAL]`)
#        is legitimate and stays silent. This is a GRAMMAR rule, not doctrine: it
#        fails nonzero UNCONDITIONALLY, never gated behind --strict. Origin: a
#        `### Visibility-only — human lane, NOT dispatchable` heading was dispatched
#        to the pool because none of its words matched ROADMAP_PARKED_HEADING_WORDS
#        (a separate, deliberately-untouched gap) — this rule catches the orthogonal
#        mistake of a live executable tag sitting under a heading that IS recognized
#        exempt.
#
#   3(h) ANSWER-SRC (id:ca14): the owner-only DECIDED-ANSWER marker
#        `@owner-answered:YYYY-MM-DD` must be well formed and must carry a resolvable
#        citation `<!-- answer-src:<path[#anchor]|id:XXXX> -->` saying WHERE the answer
#        is recorded; an answer-src citation with no marker is equally rejected. Like
#        3(g) this is a GRAMMAR rule: nonzero UNCONDITIONALLY, never behind --strict,
#        and it runs on every checkbox line (ticked or not, parked or not) since a
#        dangling citation rots anywhere. It says nothing about whether the item should
#        be ticked: the marker settles a QUESTION inside the item, not the item. Origin:
#        loderite id:ed3a, whose body quoted the owner's own answer for 13 days while
#        the question was re-opened twice — 3(b) is WARN-only and its lexeme set does
#        not match an answer quoted as prose. See relay/references/hard-lanes.md.
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

# shellcheck source=relay/scripts/lib-lane-anchor.sh
# The SHARED lane-anchoring engine (id:70bc): `leading_lane_run` (rule 3(g)'s
# anchoring, adopted here in 7a86cdb3) and `mask_backticks` live there now, so this
# lint and relay/scripts/lane-delimiter-scan.sh can never drift apart on what counts
# as a LIVE lane tag versus a prose mention.
source "$script_dir/lib-lane-anchor.sh"
# shellcheck source=relay/scripts/lib-anchored-id.sh
source "$script_dir/lib-anchored-id.sh"
# shellcheck source=relay/scripts/lib-state-claim.sh
source "$script_dir/lib-state-claim.sh"
# shellcheck source=relay/scripts/lib-typed-edges.sh
# The SHARED id:46f6 typed-edge engine — rule 3(d) DEAD-GATE resolves `gated-on:`
# markers through it (comment-anchored form C only), never a bare substring read
# of "gated-on" (the id:4da4/0d58 trap). One engine, now three callers
# (orphan-scan.sh, resolve-gates.sh, this lint).
source "$script_dir/lib-typed-edges.sh"

# WARN→ERROR boundary baseline (id:cb3e, gated on id:5533): ids captured here at
# rule-land time stay WARN even under --strict; a "new" id (absent from the
# baseline) escalates to ERROR under --strict, same as every other doctrine rule.
# Overridable for tests (STATE_CLAIM_BASELINE); default is the checked-in snapshot
# sibling to this script.
STATE_CLAIM_BASELINE="${STATE_CLAIM_BASELINE:-$script_dir/../state-claim-baseline.txt}"

# Read the recognized lane vocabulary out of the canonical doc (id:78ff single
# source of truth) via the SHARED scraper in lib-lane-anchor.sh. There is NO
# built-in fallback set any more (id:71d6): the fallback made a broken scrape look
# like a working one, so flipping the doc's delimiter left all three readers
# enforcing the old vocabulary in silence -- the id:d35a silent-no-op class inside
# the tooling built to prevent it. An empty/unreadable doc is now FATAL and names
# the path. `lane_vocab_scrape` sets hard_lanes / input_lanes (both delimiter
# spellings of every lane), hard_lane_names / input_lane_names, and all_lane_tags.
lane_vocab_scrape "$lanes_doc" || exit 2

# A bash regex alternation of the lane NAMES (the part after the delimiter),
# e.g. "pool|meeting|hands|decision gate". Names, never spellings -- the delimiter
# is matched separately so both spellings stay recognized.
lane_alt="$(printf '%s\n' "$hard_lane_names" | paste -sd'|' -)"

# The delimiter itself, as a bash-regex fragment: an em dash OR an ASCII hyphen,
# with optional surrounding whitespace. ONE definition, used by every pattern below.
lane_delim_re='[[:space:]]*[—-][[:space:]]*'

# --- PARKED-POOL-LANE pool-executable set (id:d35a, owner ruling 2026-08-27) ---
# A `### Visibility-only — human lane, NOT dispatchable` heading was NOT recognized
# as exempt (none of its words are in ROADMAP_PARKED_HEADING_WORDS — that gap is a
# SEPARATE ruling, deliberately NOT fixed here: widening the parked-heading
# vocabulary is out of scope for this check and belongs to whoever owns id:6446/
# lib-roadmap-sections.sh). Its `[ROUTINE]`-tagged items were dispatched to the
# pool and killed two Sonnet executors. THIS check assumes a heading IS already
# recognized exempt, and catches the orthogonal mistake: a pool-executable lane
# tag sitting on an item under a heading that IS already parked.
#
# "Pool-executable" = the two dispositions the `/relay --afk` pool actually
# dispatches, per hard-lanes.md's own "Who runs it" column: [ROUTINE] (the base
# executor-tier lane) and [HARD — pool] (the "hard" verdict). Neither is a fresh
# second copy of the vocabulary: [HARD — pool] is filtered out of $hard_lanes,
# which is ALREADY sourced from hard-lanes.md a few lines up; [ROUTINE] is a bash
# literal because hard-lanes.md's `[HARD — <lane>]` table only enumerates the
# `[HARD — *]` family, never `[ROUTINE]` itself (it appears only in prose in the
# north-star table) — this mirrors the PRE-EXISTING `\[ROUTINE\]` literal in
# `class_re` above, not a new hardcode.
#
# BARE `[HARD]` IS COVERED, and is not a judgment call — it is id:4f02's
# unambiguous 1:1 rename of `[HARD — pool]` (same disposition, new spelling), and
# `lane-convert.sh` auto-applies exactly that rename with no human input. It is
# therefore the CURRENT spelling of the pool-executable lane, not a variant: under
# the north-star vocabulary `[HARD — pool]` is the legacy form the pre-commit
# ratchet (hooks/pre-commit-lane-vocab.sh) actively BLOCKS from new commits.
# Omitting it would have left the rule catching loderite dd4d S2/S3 while missing
# S1/S4/S5 — three of the five items in its own origin incident (id:d35a).
# The `\[HARD\]` alternative matches ONLY the bare form; `[HARD — meeting]` and the
# rest of the `[HARD — *]` family cannot match it (the `]` is anchored).
if grep -qxF 'pool' <<<"$hard_lane_names"; then
  pool_lane_re="\[ROUTINE\]|\[HARD\]|\[HARD${lane_delim_re}pool\]"
else
  echo "roadmap-lint: WARNING -- no 'pool' lane found in $lanes_doc; PARKED-POOL-LANE will only catch [ROUTINE] and bare [HARD]" >&2
  pool_lane_re='\[ROUTINE\]|\[HARD\]'
fi

# --- DUAL-VOCAB WINDOW (id:4f02, meeting 2026-07-02-1924 decision 2) -----------
# The target capability-keyed vocabulary (`[HARD]` bare + `[INPUT — meeting|decision|
# access]`) is ALSO read from hard-lanes.md's north-star section, so both spellings
# stay ERROR-free during the migration window without a second hardcoded copy here.
# The `[INPUT — <kind>]` kinds come from the SAME scrape above (there are FOUR:
# meeting, decision, access, author -- the deleted fallback listed only three, which
# made an `[INPUT — author]` item invisible to this lint whenever the scrape failed).
input_alt="$(printf '%s\n' "$input_lane_names" | paste -sd'|' -)"

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
# The DELIMITER is matched by $lane_delim_re (em dash OR ASCII hyphen), so a ledger
# that has not been rewritten yet lints exactly like one that has (id:71d6
# tolerant-read / canonical-emit).
class_re="\[ROUTINE\]|\[MECHANICAL\]|\[HARD\]|\[HARD${lane_delim_re}(${lane_alt})\]|\[INPUT${lane_delim_re}(${input_alt})\]"

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
# `all_lane_tags` was populated by lane_vocab_scrape above -- it carries BOTH
# delimiter spellings of every lane the doc declares, plus the three delimiter-less
# capability tags.

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

# `leading_lane_run <line>` (rule 3(g)'s anchoring) now lives in the shared
# lib-lane-anchor.sh sourced above (id:70bc) -- see the note there. It reads the
# `all_lane_tags` array built just above.

# item_id <line> — the item's OWN canonical id. ANCHORED (id:521f) to the
# `<!-- id:XXXX -->` HTML-comment marker via lib-anchored-id.sh's own_id_of_line —
# a bare `id:XXXX` prose mention (a dep citation, a seam id in a DECOMPOSED body)
# is NEVER used as the item's own id. Only when a line carries no HTML-comment
# marker at all does this fall back to the first bare `id:XXXX` token, purely so a
# malformed/legacy line still gets SOME display handle in a report line rather
# than an unconditional `<no id>` — that fallback is never used to satisfy the
# "has an id" grammar clause (see has_own_id_marker call sites below), only for
# display.
# id:6059 — a line with SEVERAL anchored markers is AMBIGUOUS (own_id_of_line exits 3);
# it gets a `<ambiguous:…>` display handle, never a positional guess, and never the bare
# fallback below (which would silently pick the first token — the very guess being
# refused). Its stderr is deliberately discarded HERE and only here: rule 3(f) MULTI-ID
# reports the same line once, with the full line and the repair instruction, whereas
# item_id is a display helper invoked several times per line — leaving it on would print
# the identical warning N times per item. This is a de-duplication, not a swallow.
item_id() {
  # `|| rc=$?` (not a bare `; rc=$?`) — a failing command substitution in a plain
  # assignment triggers errexit under this script's `set -e`, and own_id_of_line now
  # exits nonzero on BOTH the absent (1) and ambiguous (3) branches.
  local l="$1" tok rc=0
  tok="$(own_id_of_line "$l" 2>/dev/null)" || rc=$?
  case "$rc" in
    0) printf '%s' "$tok"; return ;;
    3) printf '<ambiguous:%s>' "$(marker_tokens_of_line "$l" id | tr '\n' ',' | sed 's/,$//')"; return ;;
  esac
  if [[ "$l" =~ id:([0-9a-fA-F]{4}) ]]; then printf 'id:%s' "${BASH_REMATCH[1]}"; fi
}

# --- section gating -----------------------------------------------------------
# `is_exempt_heading` moved to lib-roadmap-sections.sh (id:4b8f) so the DISPATCH counters
# share this repo's one definition of "parked" instead of each re-deriving it — the lint
# knowing a section is parked while gather-repo-state.sh's open_hard_pool did not is what
# dispatched an Opus HARD child at zkWhale every round for 6 already-gated items.
# shellcheck source=lib-roadmap-sections.sh
source "$script_dir/lib-roadmap-sections.sh"

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

# item_body_end <start-index> — index of the line AFTER the last body line for the
# item beginning at <start-index> (its own top-level checkbox line): the next
# top-level checkbox (`- [ ]`/`- [x]`) OR the next `## `/`### ` heading, whichever
# comes first, or EOF (id:213a).
item_body_end() {
  local start="$1" k _bl
  for ((k = start + 1; k < ${#_rl_lines[@]}; k++)); do
    _bl="${_rl_lines[$k]}"
    if [[ "$_bl" =~ ^##+[[:space:]] ]] || [[ "$_bl" =~ ^-[[:space:]]\[[[:space:]xX]\][[:space:]] ]]; then
      printf '%d' "$k"; return
    fi
  done
  printf '%d' "${#_rl_lines[@]}"
}

# _clause_re_match <text> — TRUE when <text> carries an Acceptance/Tests/Done-check
# clause as a bold heading. Tolerant of a QUALIFIER after the word before the
# closing `**` (e.g. `**Done-check (when built)**`, the real shape of id:89bb/8a5c)
# — matches on the bold-open + word, not the exact closing bold marker (id:213a).
_clause_re_match() {
  [[ "$1" =~ \*\*(Acceptance|Tests|Done-check)[^*]*\*\* ]]
}

# --- DETAIL-FILE POINTERS (id:e95b, the id:2ee1 rule applied to this lint) -----
# The ratified line-shrink (meeting 2026-09-01-2226, D3) relocates an item's prose
# body out of its ledger line into `docs/ledger-notes/<id>.md`, leaving a slim head
# plus a pointer. The Acceptance/Tests/Done-check clause moves WITH it, so a rule
# 3(c) that reads only the ledger body reports a perfectly workable item as
# structurally un-workable. Same shape as id:2ee1 (ledger-slice) and id:f3d2 (the
# byte gate); each was a consumer of relocated bodies that nobody had identified.
# Only the item's OWN id is followed — under D3 a body lives in exactly one file
# named for that id, so a reference to some OTHER id's note is prose, not this
# item's spec (verbatim ledger-slice.sh's rule).
LEDGER_NOTES_DIR="${LEDGER_NOTES_DIR:-docs/ledger-notes}"

# item_detail_path <id-token> <start-index> <end-index> — echo the item's own
# detail path when the head line or body points at it, else nothing. Detection
# keys on the PATH, not on the pointer's prose or dash, so a markdown link, a
# backticked path and a bare mention all resolve the same way.
item_detail_path() {
  local idtok="${1#id:}" start="$2" end="$3" rel k
  [[ -z "$idtok" ]] && return 0
  rel="${LEDGER_NOTES_DIR}/${idtok}.md"
  for ((k = start - 1; k < end; k++)); do
    [[ "${_rl_lines[$k]}" == *"$rel"* ]] && { printf '%s' "$rel"; return 0; }
  done
  return 0
}

# item_has_body_clause <id-token> <start-index> <end-index> — TRUE when the item's
# body (the half-open span [start,end)) OR its relocated detail file carries the
# clause. Exit 2 means the item points at a detail file that does NOT exist: the
# body is unreachable, so neither answer is knowable and the caller must say THAT
# rather than attribute it to a missing clause (id:4347 no-silent-swallow).
item_has_body_clause() {
  local idtok="$1" start="$2" end="$3" k _bl rel
  for ((k = start; k < end; k++)); do
    _bl="${_rl_lines[$k]}"
    _clause_re_match "$_bl" && return 0
  done
  rel="$(item_detail_path "$idtok" "$start" "$end")"
  [[ -z "$rel" ]] && return 1
  if [[ ! -f "$_rl_notes_root/$rel" ]]; then
    return 2
  fi
  while IFS= read -r _bl; do
    _clause_re_match "$_bl" && return 0
  done <"$_rl_notes_root/$rel"
  return 1
}

# has_todo_twin <id-token> <roadmap-path> — TRUE when the item's own id token
# (e.g. "id:XXXX") also appears anywhere in the sibling TODO.md or
# TODO.archive.md (single-id-two-views: a mirrored design-ledger entry means the
# item IS tracked even with no inline Acceptance/Tests/Done-check block, id:213a).
#
# id:e95b — the search extends into RELOCATED TODO bodies. The line-shrink moves an
# item's prose into `docs/ledger-notes/<id>.md`, and a twin is frequently only a
# PROSE MENTION inside some OTHER item's body, so the shrink silently removed the
# exemption from items it never touched. MEASURED 2026-09-02: `id:6958`'s only twin
# was two mentions inside `id:cce9`'s TODO body ("Found while verifying the id:6958
# archive migration"); relocating cce9 made 6958 fire as a new violation, and it was
# the last thing refusing the shrink.
#
# Scoped to `## From TODO` sections. A note's sections are named by LOGICAL ledger
# (D3), and `logical_ledger()` maps BOTH TODO.md and TODO.archive.md to "TODO", so
# that heading is exactly the two files this predicate already reads. A mention in a
# `## From ROADMAP` section is ROADMAP prose and must NOT count -- honouring the
# heading is what keeps this a verdict-PRESERVING change rather than a widening.
#
# Substring matching, deliberately: this mirrors the existing `grep -qF` semantics
# byte for byte. Whether a bare-token twin should be ANCHORED to `<!-- id:XXXX -->`
# (the id:3743 precedent) is a real and separate question, filed rather than decided
# here (owner 2026-09-02) -- a formatting migration must not smuggle in a change to
# what the lint MEANS.
_rl_note_todo_text=""

# _rl_build_note_todo_text <roadmap-path> — concatenate every note's `## From TODO`
# section into one scratch file, once. Empty (and harmless) when no notes exist.
_rl_build_note_todo_text() {
  local dir notes
  dir="$(dirname "$1")"
  notes="$dir/${LEDGER_NOTES_DIR}"
  [[ -d "$notes" ]] || return 0
  _rl_note_todo_text="$(mktemp)"
  # shellcheck disable=SC2064
  trap "[ -e '$_rl_note_todo_text' ] && rm -- '$_rl_note_todo_text'" EXIT
  find "$notes" -maxdepth 1 -name '*.md' -print0 2>/dev/null \
    | xargs -0 -r awk '
        FNR == 1 { insec = 0 }
        /^## From / { insec = ($0 ~ /^## From TODO[[:space:]]*$/); next }
        insec { print }
      ' >"$_rl_note_todo_text" 2>/dev/null || :
}

has_todo_twin() {
  local idtok="$1" roadmap_path="$2" dir
  [[ -z "$idtok" ]] && return 1
  dir="$(dirname "$roadmap_path")"
  grep -qF -- "$idtok" "$dir/TODO.md" 2>/dev/null && return 0
  grep -qF -- "$idtok" "$dir/TODO.archive.md" 2>/dev/null && return 0
  [[ -n "$_rl_note_todo_text" ]] \
    && grep -qF -- "$idtok" "$_rl_note_todo_text" 2>/dev/null && return 0
  return 1
}

# --- rule 3(d) DEAD-GATE resolution maps (id:49e0) ----------------------------
# THREE separate maps rather than one merged map: the whole point of the rule is
# WHERE a `gated-on:` target lives. A target that is a ROADMAP checkbox (open OR
# ticked) is a live/satisfied gate; one that resolves only in TODO.md was never
# promoted to the execution queue; one that resolves only in TODO.archive.md is
# retired, so the gate is permanent. Merging them (as resolve-gates.sh correctly
# does for its own, different question) would erase exactly that distinction.
_rl_dir="$(dirname "$roadmap")"
# id:e95b — detail files are resolved relative to the LEDGER's directory, the same
# root ledger-slice.sh uses, so a fixture ROADMAP in a temp dir resolves its own notes.
_rl_notes_root="$_rl_dir"
_rl_build_note_todo_text "$roadmap"
declare -A RL_GATE_ROADMAP RL_GATE_TODO RL_GATE_ARCHIVE
typed_edges_build_state_map RL_GATE_ROADMAP "$roadmap"
typed_edges_build_state_map RL_GATE_TODO    "$_rl_dir/TODO.md"
typed_edges_build_state_map RL_GATE_ARCHIVE "$_rl_dir/TODO.archive.md"

# --- rule 3(h) ANSWER-SRC (id:ca14) -------------------------------------------
# The DECIDED-ANSWER marker `@owner-answered:YYYY-MM-DD` (owner-only, the
# `@owner-accepted`/id:8089 precedent) plus its mandatory citation
# `<!-- answer-src:SOURCE -->` records that ONE QUESTION inside an item has been
# answered by the owner, when, and WHERE the answer lives. It deliberately does NOT
# mean "tick me": loderite's id:ed3a legitimately stayed open (gated children) while
# the genre question inside it was settled 13 days earlier, and during those 13 days a
# later author wrote the OPPOSITE assertion into its ROADMAP line, a meeting agenda
# re-opened it, and a session put it to the owner a third time. Rule 3(b)
# DECIDED-LEFT-OPEN could not see any of that: it is WARN-only unless --strict, and its
# lexeme set (lib-state-claim.sh: RESOLVED|SUPERSEDED|DONE|CLOSED|DEFERRED plus
# "decided <date>") matches nothing in an owner's answer quoted as prose.
#
# This rule validates only the marker's OWN grammar: well-formed date, citation
# present, citation RESOLVES. A dangling citation is the rot mode that would turn the
# marker into one more unfalsifiable claim, so findings are ERROR and count toward the
# nonzero exit UNCONDITIONALLY, never gated behind --strict. That reddens nothing that
# has not opted in: an item without the marker and without an answer-src comment is
# never examined here.
#
# ANCHORING (the id:4da4/0d58 bare-substring trap): backtick spans are masked out
# BEFORE both the marker match and the citation extraction, so documenting the marker
# in prose is inert; the citation itself is read only through the comment-anchored
# extractor typed_edges_answer_src_of_line. Never a raw-line substring.
#
# SCOPE: this runs over EVERY top-level checkbox line, ticked or not, parked section or
# not -- a dangling citation rots identically wherever it sits, and unlike the doctrine
# rules there is no "legitimately parked" reading of a malformed marker.
# It says nothing about WHO may write the marker: owner-only is a contract rule
# (relay/references/hard-lanes.md + the review.md gaming-check), not something a lint
# over ledger text can establish.
#
# SCOPE DECISION (S3, adversarial review, id:ca14 follow-up): this rule matches ONLY
# column-0 `^- [ ]`/`^- [x]` lines, same as the rest of this file's grammar checks --
# an indented continuation line (the item's BODY) is NEVER scanned, even though the
# origin incident (ed3a) had the owner's answer live in exactly such a line. This is a
# DELIBERATE, KEPT restriction, not an oversight: todo-conformance.sh's header already
# states the column-0 convention for this codebase, and lifting it here alone would
# require resolving an indented line's marker against its ENCLOSING item's id (an
# indented line carries no id of its own), which is a materially bigger change than a
# grammar fix and risks silently disagreeing with every other rule in this file that
# also stops at column 0. Reported to the owner as a follow-up rather than done here.
#
# FENCED CODE (S4) and BACKTICK SPANS (S5): a fenced ``` / ~~~ block is documentation,
# not a live line -- hard-lanes.md's own canonical example is a fenced checkbox line,
# so an author copying it must not trip a real ERROR. Fence state is tracked and
# fenced lines are skipped entirely. Within a non-fenced line, backtick masking uses
# `(`+)[^`]*\1` (a same-length backtick run on both sides) rather than a bare
# `` s/`[^`]*`//g ``, so a double-backtick span (`` `` ``, used to quote text that
# itself contains a backtick) is consumed whole instead of leaving its content exposed
# between what the old regex saw as two adjacent empty single-backtick spans.
#
# CASE (S9): marker + citation matching is case-INSENSITIVE (`grep -qiE`), mirroring
# `is_manual_marker` in gather-human-backlog.sh:251 -- `@Owner-Answered` is the same
# marker as `@owner-answered`, not a silent miss.
#
# CITATION STRENGTH (S6): the path form must resolve to a REGULAR FILE (`-f`, not
# `-e` -- a directory cites nothing) and, when a `#anchor` is present, the anchor must
# resolve to an actual heading in the target file (slugified compare), not merely be
# stripped and ignored.
_as_slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-zA-Z0-9 -]//g; s/ +/-/g' | tr '[:upper:]' '[:lower:]'
}
_as_anchor_resolves() {
  local file="$1" anchor="$2" slug hline htext
  slug="$(_as_slugify "$anchor")"
  while IFS= read -r hline || [[ -n "$hline" ]]; do
    if [[ "$hline" =~ ^#+[[:space:]]+(.*)$ ]]; then
      htext="${BASH_REMATCH[1]}"
      [[ "$(_as_slugify "$htext")" == "$slug" ]] && return 0
    fi
  done < "$file"
  return 1
}
ANSWER_MARKER_RE='(^|[^A-Za-z0-9_-])@owner-answered'
ANSWER_WELLFORMED_RE='(^|[^A-Za-z0-9_-])@owner-answered:[0-9]{4}-[0-9]{2}-[0-9]{2}($|[^A-Za-z0-9_-])'
_as_in_fence=0
for ((_as_i = 0; _as_i < ${#_rl_lines[@]}; _as_i++)); do
  _as_line="${_rl_lines[$_as_i]}"
  if [[ "$_as_line" =~ ^[[:space:]]*(\`\`\`|~~~) ]]; then
    _as_in_fence=$((1 - _as_in_fence))
    continue
  fi
  [[ "$_as_in_fence" -eq 1 ]] && continue
  [[ "$_as_line" =~ ^-[[:space:]]\[[[:space:]xX]\][[:space:]] ]] || continue
  _as_masked="$(printf '%s' "$_as_line" | sed -E 's/(`+)[^`]*\1//g')"
  _as_has_marker=0
  grep -qiE "$ANSWER_MARKER_RE" <<<"$_as_masked" && _as_has_marker=1
  _as_srcs="$(typed_edges_answer_src_of_line "$_as_masked")"
  [[ "$_as_has_marker" -eq 0 && -z "$_as_srcs" ]] && continue
  _as_id="$(item_id "$_as_line")"

  if [[ "$_as_has_marker" -eq 1 ]] && ! grep -qiE "$ANSWER_WELLFORMED_RE" <<<"$_as_masked"; then
    violations=$((violations + 1))
    echo "roadmap-lint: ERROR — ANSWER-SRC: item ${_as_id:-<no id>} carries a MALFORMED @owner-answered marker — the only accepted form is @owner-answered:YYYY-MM-DD (id:ca14)" >&2
    echo "  $_as_line" >&2
    report+="  - [${_as_id:-<no id>}] ANSWER-SRC: malformed @owner-answered marker"$'\n'
  elif [[ "$_as_has_marker" -eq 1 && -z "$_as_srcs" ]]; then
    violations=$((violations + 1))
    echo "roadmap-lint: ERROR — ANSWER-SRC: item ${_as_id:-<no id>} claims an owner answer but cites NO source — add <!-- answer-src:<path[#anchor]|id:XXXX> --> naming where the answer is recorded; an uncited answer is just another unfalsifiable claim (id:ca14)" >&2
    echo "  $_as_line" >&2
    report+="  - [${_as_id:-<no id>}] ANSWER-SRC: @owner-answered with no citation"$'\n'
  elif [[ "$_as_has_marker" -eq 0 ]]; then
    violations=$((violations + 1))
    echo "roadmap-lint: ERROR — ANSWER-SRC: item ${_as_id:-<no id>} carries an answer-src citation with NO @owner-answered:YYYY-MM-DD marker — nothing records WHO answered or WHEN; add the marker or drop the citation (id:ca14)" >&2
    echo "  $_as_line" >&2
    report+="  - [${_as_id:-<no id>}] ANSWER-SRC: citation with no @owner-answered marker"$'\n'
  fi

  while IFS= read -r _as_tok; do
    [[ -z "$_as_tok" ]] && continue
    if [[ "$_as_tok" =~ ^id:([0-9a-fA-F]{4})$ ]]; then
      _as_t="${BASH_REMATCH[1]}"
      _as_tl="${_as_t,,}"
      if [[ -n "${RL_GATE_ROADMAP[$_as_t]+x}" || -n "${RL_GATE_TODO[$_as_t]+x}" || -n "${RL_GATE_ARCHIVE[$_as_t]+x}" \
         || -n "${RL_GATE_ROADMAP[$_as_tl]+x}" || -n "${RL_GATE_TODO[$_as_tl]+x}" || -n "${RL_GATE_ARCHIVE[$_as_tl]+x}" ]]; then
        continue
      fi
      violations=$((violations + 1))
      echo "roadmap-lint: ERROR — ANSWER-SRC: item ${_as_id:-<no id>} cites answer source id:${_as_t}, which resolves NOWHERE (absent from ROADMAP.md, TODO.md and TODO.archive.md) — a dangling citation (id:ca14)" >&2
      echo "  $_as_line" >&2
      report+="  - [${_as_id:-<no id>}] ANSWER-SRC: dangling id citation id:${_as_t}"$'\n'
    else
      # Path form, repo-relative to the ledger's own directory. Must be a regular
      # FILE (`-f`); a trailing `#anchor` must resolve to an actual heading in it.
      _as_path="${_as_tok%%#*}"
      _as_anchor=""
      [[ "$_as_tok" == *#* ]] && _as_anchor="${_as_tok#*#}"
      if [[ -z "$_as_path" || ! -f "$_rl_dir/$_as_path" ]]; then
        violations=$((violations + 1))
        echo "roadmap-lint: ERROR — ANSWER-SRC: item ${_as_id:-<no id>} cites answer source ${_as_tok}, but no such FILE exists (resolved repo-relative as ${_rl_dir}/${_as_path}) — a dangling citation (id:ca14)" >&2
        echo "  $_as_line" >&2
        report+="  - [${_as_id:-<no id>}] ANSWER-SRC: dangling path citation ${_as_tok}"$'\n'
      elif [[ -n "$_as_anchor" ]] && ! _as_anchor_resolves "$_rl_dir/$_as_path" "$_as_anchor"; then
        violations=$((violations + 1))
        echo "roadmap-lint: ERROR — ANSWER-SRC: item ${_as_id:-<no id>} cites answer source ${_as_tok}, but no heading in ${_as_path} matches the #${_as_anchor} anchor — a dangling citation (id:ca14)" >&2
        echo "  $_as_line" >&2
        report+="  - [${_as_id:-<no id>}] ANSWER-SRC: dangling anchor citation ${_as_tok}"$'\n'
      fi
    fi
  done <<< "$_as_srcs"
done

for ((_rl_i = 0; _rl_i < ${#_rl_lines[@]}; _rl_i++)); do
  line="${_rl_lines[$_rl_i]}"
  # Track the active/exempt section from headings.
  # id:bb32 — heading recognition comes from lib-roadmap-sections.sh (H1..H6). This used
  # to be a local `^##+[[:space:]]`, which made an H1 `# Gated / deferred` parked for
  # gather-repo-state.sh's counter and NOT for this lint.
  if is_heading_line "$line"; then
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

  # Section-exempt items are explicitly parked → never linted for the usual
  # grammar (class tag + id) — EXCEPT for rule 3(g) PARKED-POOL-LANE just below,
  # which exists precisely BECAUSE that blanket skip hides an executable lane
  # tag under a parked heading (the id:d35a origin incident). This is the one
  # deliberate exception to the exempt-section skip; nothing else runs on these
  # lines.
  if [[ "$in_exempt_section" -eq 1 ]]; then
    # Anchor on the item's LEADING lane run, never the raw line (defect found by
    # the 2026-08-27 fleet sweep: matching $pool_lane_re against the whole line
    # produced 3 false positives in 38 fleet findings -- loderite affd/1e21 and
    # toesnail 8807 -- where the live primary lane is human ([INPUT - access] /
    # [INPUT - meeting] / a bare @container umbrella) and the only pool tag is a
    # BACKTICK'D audit-trail mention in prose, e.g. "`[ROUTINE]`-tagged there
    # historically". leading_lane_run returns only the contiguous recognized lane
    # brackets at the item's start, so trailing prose mentions cannot fire. This is
    # the same anchoring lane-convert.sh and first_lane_tag use; matching the raw
    # line was the odd one out.
    #
    # `[INTENSIVE - <res>]` is deliberately NOT in all_lane_tags (it is the
    # orthogonal RESOURCE axis, not a lane), so leading_lane_run stops dead at it
    # and a resource-first item like `[INTENSIVE - local-llm] [HARD]` would return
    # an empty run and silently escape. Convention is lane-first, but relying on
    # authoring convention is what id:d35a is about, so strip the resource brackets
    # before computing the run. Stripping cannot manufacture a violation: removing
    # a bracket can only ever leave prose where a tag would have to be.
    _pp_line="$(printf '%s' "$line" | sed -E 's/\[INTENSIVE[^]]*\]//g')"
    _pp_run="$(leading_lane_run "$_pp_line")"
    if [[ -n "$_pp_run" && "$_pp_run" =~ $pool_lane_re ]]; then
      _pp_tag="${BASH_REMATCH[0]}"
      _pp_id="$(item_id "$line")"
      violations=$((violations + 1))
      echo "roadmap-lint: ERROR — PARKED-POOL-LANE: open item ${_pp_id:-<no id>} sits under a parked/human-lane heading yet carries the pool-executable tag ${_pp_tag} — an executable lane must never appear under a parked heading (id:d35a)" >&2
      echo "  $line" >&2
      report+="  - [${_pp_id:-<no id>}] PARKED-POOL-LANE: pool-executable tag ${_pp_tag} under a parked/human-lane heading"$'\n'
      report+="      ${line}"$'\n'
    fi
    continue
  fi

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

  # Rule 3(f) MULTI-ID (id:6059, routed:b71e's real find + loderite routed:3ad9): a
  # checkbox line carrying MORE THAN ONE `<!-- id:XXXX -->` marker is AMBIGUOUS and every
  # id-resolver now REFUSES it rather than guess a position — the line addresses nothing
  # until it is repaired. Anchoring cannot fix this: `<!-- id:X -->` spells both "this
  # line IS X" and "this line REFERS to X", and the two live shapes put the own id at
  # opposite ends (a body that QUOTES a marker → last; a trailing reference → first), so
  # no positional rule is safe. Count, never dedup — the same id twice is ambiguous too.
  # Repair: de-literalise a quoted marker, or spell a reference as a typed edge
  # (gated-on:/children:/settles:) which has its own marker namespace.
  #
  # COUNT VIA THE SHARED HELPER, NOT A LOCAL `grep | wc -l`. This script runs under
  # `set -euo pipefail`, where `x="$(grep … | wc -l)"` on a line with ZERO markers is
  # FATAL: grep exits 1, pipefail propagates it, and a bare assignment is subject to
  # errexit — so the scan died mid-loop on the first id-less item and `$report` (printed
  # only at the END) was never emitted. The lint still exited nonzero, so it LOOKED like
  # it had rejected something while reporting nothing at all, and every violation on
  # every later line was lost. `marker_tokens_of_line` ends in `|| true`, so it is
  # zero-marker-safe, and reusing it keeps one spelling of the marker regex.
  _mi_count="$(marker_tokens_of_line "$line" id | wc -l)"
  if [[ "$_mi_count" -gt 1 ]]; then
    echo "roadmap-lint: ${_dr_label} — MULTI-ID: open item carries ${_mi_count} anchored id markers on ONE line — AMBIGUOUS, so id-resolvers REFUSE it and the item addresses nothing (id:6059). De-literalise the quoted marker, or spell a reference as a typed edge." >&2
    echo "  $line" >&2
    [[ "$strict" -eq 1 ]] && violations=$((violations + 1))
  fi

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

  # Rule 3(b) DECIDED-LEFT-OPEN (id:dafa, AMENDS by id:5533): an OPEN item whose
  # body records a conclusion (RESOLVED / DECIDED <YYYY-MM-DD> / SUPERSEDED / DONE
  # / CLOSED / DEFERRED) is a decided item left un-ticked — direction (i), unless
  # the assertion is scoped to a DIFFERENT id ("id:XXXX is SUPERSEDED"). Direction
  # (ii): the same conclusion recorded ONLY inside an HTML comment while the
  # checkbox and visible text still say open (loderite id:0e99 via routed:fb6e).
  # Both directions run through the shared engine (lib-state-claim.sh) so this
  # rule and todo-conformance.sh's twin check can never silently diverge.
  if state_claim_direction_i "$line"; then
    _do_id="$(item_id "$line")"
    _dr_label_i="$_dr_label"
    if state_claim_in_baseline "${_do_id#id:}" "$STATE_CLAIM_BASELINE"; then
      _dr_label_i="WARN (baselined id:cb3e)"
    fi
    echo "roadmap-lint: ${_dr_label_i} — DECIDED-LEFT-OPEN: open item ${_do_id:-<no id>} carries a decided/deferred/superseded marker but is still open — close it (tick + done-note) or drop the marker" >&2
    echo "  $line" >&2
    [[ "$strict" -eq 1 && "$_dr_label_i" != "WARN (baselined id:cb3e)" ]] && violations=$((violations + 1))
  fi
  if state_claim_direction_ii "$line"; then
    _do_id2="$(item_id "$line")"
    _dr_label_ii="$_dr_label"
    if state_claim_in_baseline "${_do_id2#id:}" "$STATE_CLAIM_BASELINE"; then
      _dr_label_ii="WARN (baselined id:cb3e)"
    fi
    echo "roadmap-lint: ${_dr_label_ii} — DECIDED-LEFT-OPEN (comment-only close): open item ${_do_id2:-<no id>} carries a close ONLY in an HTML comment while the checkbox and visible text still say open — close it for real or drop the comment marker" >&2
    echo "  $line" >&2
    [[ "$strict" -eq 1 && "$_dr_label_ii" != "WARN (baselined id:cb3e)" ]] && violations=$((violations + 1))
  fi

  # Rule 3(c) NO-ACCEPTANCE-NO-TWIN (id:213a): an OPEN item with NO Acceptance/
  # Tests/Done-check clause in its own body AND no mirrored twin in TODO.md /
  # TODO.archive.md is structurally un-workable — nothing tells an executor what
  # "done" means, and nothing else tracks it. ALL LANES (owner 2026-07-26: the
  # twin-check alone discriminates on real data — 10 of 13 acceptance-less items
  # examined were legit HARD items carrying a twin). WARN by default, ERROR under
  # --strict — a past-triage pattern mechanized, same shape as 3(a)/3(b), not a
  # positive-grammar clause that always fails.
  _nc_end="$(item_body_end "$_rl_i")"
  _nc_id="$(item_id "$line")"
  set +e
  item_has_body_clause "$_nc_id" $((_rl_i + 1)) "$_nc_end"
  _nc_rc=$?
  set -e
  if [[ "$_nc_rc" -eq 2 ]]; then
    # id:e95b — the body was relocated and the note is GONE. Reporting this as
    # "no acceptance clause" would blame the item for a broken pointer, so name
    # the real fault; the TODO twin cannot excuse it either, the file is missing.
    echo "roadmap-lint: ${_dr_label} — DETAIL-POINTER-MISSING: open item ${_nc_id:-<no id>} points at '$(item_detail_path "$_nc_id" $((_rl_i + 1)) "$_nc_end")', which does not exist — its relocated body (and any Acceptance/Tests/Done-check clause) is unreachable; restore the note or drop the pointer (id:e95b, the id:2ee1 class)" >&2
    echo "  $line" >&2
    [[ "$strict" -eq 1 ]] && violations=$((violations + 1))
  elif [[ "$_nc_rc" -ne 0 ]]; then
    if ! has_todo_twin "$_nc_id" "$roadmap"; then
      echo "roadmap-lint: ${_dr_label} — NO-ACCEPTANCE-NO-TWIN: open item ${_nc_id:-<no id>} has no Acceptance/Tests/Done-check clause in its body and no TODO.md/TODO.archive.md twin — structurally un-workable (id:213a)" >&2
      echo "  $line" >&2
      [[ "$strict" -eq 1 ]] && violations=$((violations + 1))
    fi
  fi

  # Rule 3(d) DEAD-GATE (id:49e0): a `<!-- gated-on:XXXX -->` marker whose target is
  # not a dispatchable ROADMAP item reads as "waiting" but means "never". A gated item
  # is DELIBERATELY unpickable, so it sits in the execution queue looking *scheduled*
  # while nothing distinguishes "blocked, will unblock" from "blocked forever". THREE
  # real instances surfaced in a single day (2026-07-31): a955→87f5 and 8123→1a34 (both
  # targets lived only in TODO.md, never promoted) and f6d5→8ba1 (target retired
  # 2026-07-24, archived ticked at TODO.archive.md:459 — a gate that can never open).
  # Each was caught only by a human noticing; nothing detected them.
  #
  # A target that IS a ROADMAP checkbox passes whatever its state: open ⇒ a legitimate
  # live gate; ticked ⇒ the gate is SATISFIED (the id:65f5 semantics — a DONE target
  # does not block). Everything else names BOTH ids and the remedy. OUT OF SCOPE by
  # ROADMAP directive: auto-promoting a missing target (handoff C2's judgement — the
  # lane cannot be guessed) and cross-repo gate resolution.
  _dg_csv="$(typed_edges_gated_of_line "$line")"
  # id:d119 — an explicit `<!-- owner-hold:REASON -->` marker means the gate is
  # INTENTIONALLY unclearable (owner directive), not a mistaken/dead one: suppress
  # DEAD-GATE for THIS item only. Scoped to this report-only lint's recognition of
  # the marker — classify-repo.sh's dispatch gate does not read it (separate step).
  _dg_hold="$(typed_edges_owner_hold_of_line "$line")"
  if [[ -n "$_dg_csv" && -z "$_dg_hold" ]]; then
    _dg_id="$(item_id "$line")"
    IFS=',' read -ra _dg_toks <<<"$_dg_csv"
    for _dg_t in "${_dg_toks[@]}"; do
      [[ -z "$_dg_t" ]] && continue
      # A ROADMAP checkbox (open or ticked) — not a dead gate.
      [[ -n "${RL_GATE_ROADMAP[$_dg_t]+x}" ]] && continue
      if [[ -n "${RL_GATE_ARCHIVE[$_dg_t]+x}" ]]; then
        _dg_why="it is RETIRED — archived in TODO.archive.md and not a ROADMAP item, so the gate is PERMANENT and can never open; drop or re-target the marker"
      elif [[ -n "${RL_GATE_TODO[$_dg_t]+x}" ]]; then
        _dg_why="it lives ONLY in TODO.md and was never promoted to the execution queue, so nothing in ROADMAP.md can ever clear the gate; promote it (handoff C2's call — never guess its lane) or re-target the marker"
      else
        _dg_why="it resolves NOWHERE (absent from ROADMAP.md, TODO.md and TODO.archive.md) — a dangling gate target"
      fi
      echo "roadmap-lint: ${_dr_label} — DEAD-GATE: open item ${_dg_id:-<no id>} is gated-on id:${_dg_t}, but ${_dg_why} (id:49e0)" >&2
      echo "  $line" >&2
      [[ "$strict" -eq 1 ]] && violations=$((violations + 1))
    done
  fi

  # Rule 3(e) DEP-PROSE-UNTYPED (id:3f7e): a `(DEP: <id>)` prose gate-annotation
  # that has no matching typed `<!-- gated-on:id -->` marker is INVISIBLE to
  # classify-repo.sh (which correctly never reads prose as a gate, id:65f5/4da4/
  # 0d58) — so the item gets dispatched as ready when the author believed it was
  # blocked. WARN, not ERROR (id:3f7e's own ruling — the existing backlog carries
  # this prose already; an ERROR would LOUD-reject it on day one). Never escalates
  # under --strict; the escalation, if ever, is a separate owner call.
  _dp_csv="$(typed_edges_dep_prose_untyped_of_line "$line")"
  if [[ -n "$_dp_csv" ]]; then
    _dp_id="$(item_id "$line")"
    echo "roadmap-lint: WARN — DEP-PROSE-UNTYPED: open item ${_dp_id:-<no id>} carries \"(DEP: …)\" prose naming id(s) ${_dp_csv} with no matching <!-- gated-on:${_dp_csv} --> marker — retype it as a typed gate (id:3f7e)" >&2
    echo "  $line" >&2
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
    grep -qF '[ROUTINE]' < <(echo "$_bare") && { _lc=$((_lc+1)); _lf+=('[ROUTINE]'); }
    grep -qF '[MECHANICAL]' < <(echo "$_bare") && { _lc=$((_lc+1)); _lf+=('[MECHANICAL]'); }
    # Bare new-vocab [HARD] (id:4f02) — counted separately from the old `[HARD — *]`
    # spellings below so an item carrying BOTH (e.g. `[HARD — pool]` + `[HARD]`) is
    # correctly flagged as a two-lane conflict, never silently merged into one.
    grep -qF '[HARD]' < <(echo "$_bare") && { _lc=$((_lc+1)); _lf+=('[HARD]'); }
    while IFS= read -r _hl; do
      [[ -z "$_hl" ]] && continue
      grep -qF "$_hl" < <(echo "$_bare") && { _lc=$((_lc+1)); _lf+=("$_hl"); }
    done <<< "$hard_lanes"
    # New-vocab [INPUT — <kind>] lanes (id:4f02 dual-vocab window) count the same way.
    while IFS= read -r _il; do
      [[ -z "$_il" ]] && continue
      grep -qF "$_il" < <(echo "$_bare") && { _lc=$((_lc+1)); _lf+=("$_il"); }
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
  [[ "$has_class" -eq 0 ]] && reasons+=("NO recognized class/lane tag ([ROUTINE] / [HARD] / [HARD - ${lane_alt}] / [INPUT - ${input_alt}] / [MECHANICAL])")
  [[ "$has_id" -eq 0 ]] && reasons+=("MISSING its id token")
  reason_str="$(IFS='; '; echo "${reasons[*]}")"
  handle="${idtoken:-<no id>}"
  report+="  - [${handle}] ${reason_str}"$'\n'
  report+="      ${line}"$'\n'
done

# --- SCOPE-TABLE-DRIFT (id:c480) -----------------------------------------------
# A past-triage class one level deeper than the grammar rules above: a ROADMAP
# item can carry a well-formed lane+id AND STILL make a stale factual claim about
# the CODE — specifically, a "scope table" enumerating relay-loop.js hop labels
# as either CONVERTIBLE (`model:'bash'`) or MUST-STAY (`model:'haiku'`). The live
# incident (id:c480): id:6b35's "OUT of scope ... MUST STAY `model:'haiku'`"
# bullet kept listing the `release` hop after id:f7d3 converted its dispatch to
# `model:'bash'` — an implementer following the table faithfully would have
# "restored" `model:'haiku'` and re-introduced the exact invariant violation
# f7d3 removed. This check makes that class of drift LOUD instead of invisible.
#
# Parses TWO ROADMAP shapes (never a hardcoded hop list, id:c480):
#   (a) a markdown table under a "... CONVERTIBLE ..." bullet, one hop label per
#       row, first column backtick-quoted — these MUST dispatch `model:'bash'`.
#   (b) an "OUT of scope ... MUST STAY `model:'haiku'`" bullet, a comma-separated
#       prose list of backtick-quoted hop labels (each optionally followed by a
#       "(~<line>, <note>)" parenthetical) — these MUST dispatch `model:'haiku'`.
# Then, for each hop, greps the sibling relay-loop.js for a same-line `label:`
# match (the hop name used as a PREFIX, since JS labels are often template
# literals like `release:${unit.repo}:${label}`) and compares its `model:`
# value. A variable model (e.g. `model: MECH_MODEL`) is NOT literally 'haiku' or
# 'bash', so it can't be compared either way — no violation is raised for those
# (conservative: this check only fires on a CONFIRMED literal contradiction,
# never a guess).
# sed regex-metachar escaper (delegates to sed rather than bash parameter
# substitution — a prior bash `${s//\}/\\}}`-style attempt mis-escaped `}`
# and silently produced a non-matching pattern; sed's BRE escaping is unambiguous).
_pcre_escape() {
  printf '%s' "$1" | sed -e 's/[.[\*^$()+?{}|\\]/\\&/g'
}

check_scope_table_drift() {
  local roadmap_path="$1" loop_js reqs kind hop esc dispatch
  loop_js="$(dirname "$roadmap_path")/relay/scripts/relay-loop.js"

  reqs="$(python3 - "$roadmap_path" <<'PY'
import re, sys

path = sys.argv[1]
text = open(path, encoding='utf-8').read()
out = []

# --- (a) the CONVERTIBLE hop table: markdown rows following a "|---|" separator
# that comes after a bullet mentioning CONVERTIBLE. ---
lines = text.split("\n")
saw_header = False
in_table = False
for line in lines:
    stripped = line.strip()
    if 'CONVERTIBLE' in line and 'Hop label' not in line:
        saw_header = True
        in_table = False
        continue
    if saw_header and re.match(r'^\|\s*Hop label', stripped):
        continue
    if saw_header and re.match(r'^\|[-\s|]+\|$', stripped):
        in_table = True
        continue
    if in_table:
        if stripped.startswith('|'):
            m = re.match(r'^\|\s*`([^`]+)`', stripped)
            if m:
                out.append(('bash', m.group(1)))
            continue
        in_table = False
        saw_header = False

# --- (b) the OUT-of-scope MUST-STAY-haiku bullet: a comma-separated prose list
# of backtick hop labels, each optionally followed by a "(~line, note)" aside.
# Track paren depth so a nested backtick INSIDE an aside (e.g. `<<`, `python3`,
# `$(...)`) is never mistaken for a hop label — only depth-0 backticks count. ---
m = re.search(r"MUST STAY `model:'haiku'`\*\*:\s*(.*)$", text, re.MULTILINE)
if m:
    tail = m.group(1)
    depth = 0
    i = 0
    n = len(tail)
    while i < n:
        c = tail[i]
        if c == '(':
            depth += 1; i += 1; continue
        if c == ')':
            depth = max(0, depth - 1); i += 1; continue
        if c == '`' and depth == 0:
            j = tail.find('`', i + 1)
            if j == -1:
                break
            out.append(('haiku', tail[i + 1:j]))
            i = j + 1
            continue
        i += 1

for kind, hop in out:
    print(f"{kind}\t{hop}")
PY
)"
  [[ -n "$reqs" ]] || return 0   # this ROADMAP carries no scope table — nothing to check

  if [[ ! -f "$loop_js" ]]; then
    echo "roadmap-lint: SCOPE-TABLE-DRIFT check SKIPPED — relay-loop.js not found at $loop_js (a scope table exists in $roadmap_path but there is nothing to verify it against)" >&2
    return 0
  fi

  while IFS=$'\t' read -r kind hop; do
    [[ -z "$hop" ]] && continue
    esc="$(_pcre_escape "$hop")"
    # Match the WHOLE line (not a bounded `[^}]*}` span) — a template-literal
    # label like `release:${repo}` contains its own `}` (the interpolation's
    # closing brace) BEFORE the object literal's real closing brace, so a
    # brace-bounded submatch truncates before reaching `model:` (observed
    # false-negative while developing this check). All known dispatch shapes in
    # this repo are single-line `agent(..., { label: …, model: … })` calls.
    dispatch="$(head -1 < <(grep -P "label:\s*[\`'\"]${esc}" "$loop_js") || true)"
    [[ -n "$dispatch" ]] || continue   # no matching dispatch found — nothing to compare
    if [[ "$kind" == "haiku" ]]; then
      if grep -qP "model:\s*'bash'" < <(printf '%s' "$dispatch") ; then
        violations=$((violations + 1))
        echo "roadmap-lint: ERROR — SCOPE-TABLE-DRIFT: hop '${hop}' is listed as MUST-STAY \`model:'haiku'\` but relay-loop.js dispatches it as model:'bash' — the ROADMAP scope table is STALE: ${dispatch}" >&2
      fi
    else
      if grep -qP "model:\s*'haiku'" < <(printf '%s' "$dispatch") ; then
        violations=$((violations + 1))
        echo "roadmap-lint: ERROR — SCOPE-TABLE-DRIFT: hop '${hop}' is listed as CONVERTIBLE (\`model:'bash'\`) but relay-loop.js dispatches it as model:'haiku' — the ROADMAP scope table is STALE: ${dispatch}" >&2
      fi
    fi
  done <<< "$reqs"
}

check_scope_table_drift "$roadmap"

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
  echo "Fix at source: assign a recognized lane tag ([ROUTINE] / [HARD] / [HARD - ${lane_alt}] / [INPUT - ${input_alt}] / [MECHANICAL]) and a 4-hex id: token, or park the item under a gated/deferred heading."
  exit 1
fi

# Clean no-op.
exit 0
