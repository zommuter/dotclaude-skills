#!/usr/bin/env bash
# decision-brief/docket.sh (id:6fda) -- the READ-ONLY collector behind /decision-brief.
#
# It answers ONE question: which open ledger items are genuinely waiting on the OWNER's
# judgment, ranked by what they block? It produces a machine-readable DOCKET; the skill's
# strong turn then reads each item's detail note AND the ratified source behind it, writes
# the brief, and puts at most four of them to the owner in ONE AskUserQuestion call.
#
# This script NEVER decides anything, NEVER writes a ledger, and NEVER spawns a model.
# The one write path in this skill is the `draft-answer` subcommand below, which refuses
# to apply anything without an explicit owner confirmation and refuses outright in an
# unattended context.
#
# ---------------------------------------------------------------------------------------
# WHY THIS IS NOT A SECOND COLLECTOR (use-existing-tools)
# ---------------------------------------------------------------------------------------
# Enumeration and bucketing are DELEGATED to relay/scripts/gather-human-backlog.sh, the
# canonical cross-repo human-backlog collector, which already reads the lane out of the
# bracket tag against the id:78ff shared vocabulary and already has a `human_decision`
# bucket distinct from `hard_meeting`. Re-deriving that here would be a third copy of a
# contract that two consumers already have to agree on.
#
# What this script ADDS is an ANCHORED re-resolution of every candidate row's lane, and
# that addition is load-bearing rather than decorative. The collector matches lane tags
# with an UNANCHORED awk `match()` that takes the earliest-positioned tag in the line
# (gather-human-backlog.sh:608-637), and `[ROUTINE]` is not in its match set at all -- so
# an item that OPENS `- [ ] [ROUTINE] ...` and later mentions `[INPUT - decision]` in its
# trailing audit-trail prose buckets as `human_decision`. That is the same over-report
# measured on 2026-09-11, where a bare grep for `[MECHANICAL]` reported 9 items against a
# true count of 3: six carried the word in trailing prose while their primary lane was
# something else. Every candidate row is therefore re-resolved here with
# `leading_lane_run` + `mask_backticks` from relay/scripts/lib-lane-anchor.sh, and a row
# whose ANCHORED primary lane is not a decision lane is dropped as SUPPRESSED with a named
# reason -- never silently, and always counted in the coverage footer.
#
# ---------------------------------------------------------------------------------------
# THE CALIBRATION GATE -- why this script can refuse to tell you anything
# ---------------------------------------------------------------------------------------
# `leading_lane_run` reads its vocabulary out of the caller-supplied global array
# `all_lane_tags`. SOURCING lib-lane-anchor.sh does NOT populate that array -- only a
# successful `lane_vocab_scrape <doc>` call does. A probe that sources the library and
# forgets the scrape therefore returns "no lane" for EVERY line on earth, and reports a
# clean, confident, entirely false zero. That was hit live on 2026-09-11.
#
# An unpopulated probe is an unreached fixture, not a negative control. So before any row
# or any count is emitted, `calibrate()` runs three controls with KNOWN answers:
#
#   positive  `- [ ] [ROUTINE] ...`              must resolve to a NON-EMPTY leading run
#   positive  both dash spellings of a lane tag  must BOTH resolve (tolerant read)
#   negative  leading prose, lane tag in the tail must resolve to an EMPTY leading run
#
# The negative control is as necessary as the positives: a probe that answers "yes" to
# everything passes both positives and is exactly as broken. If ANY control fails the
# script prints `CALIBRATION<TAB>FAILED<TAB><which>`, a loud stderr line, and EXITS 3
# having emitted no ROW and no COVERAGE line at all. Refusing to report a count is the
# whole point: a wrong count looks like an answer.
#
# ---------------------------------------------------------------------------------------
# OUTPUT -- tab-separated, one record per line, first field is the record type
# ---------------------------------------------------------------------------------------
#   CALIBRATION <status> <detail>
#       Always the FIRST line on a successful run (status `ok`).
#   ROW <rank> <repo> <ledger> <id> <lane> <blocks_n> <blocks_ids> <detail_note> <summary>
#       A decision genuinely waiting on the owner. Ranked by declared dependants, then by
#       whether it is promoted to ROADMAP.md. `ledger` is TODO.md / ROADMAP.md / `-`;
#       `detail_note` is a repo-relative path or `-`; `blocks_ids` is a CSV or `-`.
#   SUPPRESSED <repo> <id> <reason> <summary>
#       A candidate the collector offered that this script dropped, with a NAMED reason:
#         lane-mention-not-primary   the anchored primary lane is not a decision lane
#         lane-after-detail-pointer  a real lane tag, but it sits AFTER the `-- detail:`
#                                    pointer where every anchored reader is blind to it
#                                    (id:0d7c relocation defect) -- a ledger bug to fix at
#                                    the source, never a lane for this tool to guess
#         owner-answered             carries @owner-answered (use --include-answered)
#   COVERAGE <key> <value>
#       The honest footer. A clean pass is NEVER "no decisions pending" -- it is "no
#       decisions the ledgers EXPRESS in a form this collector reads", and the coverage
#       keys are what let the skill say which of the two it found.
#
# ---------------------------------------------------------------------------------------
# USAGE
# ---------------------------------------------------------------------------------------
#   docket.sh [scan] [--repo NAME]... [--include-answered] [--max N]
#   docket.sh draft-answer --repo-path DIR --id XXXX --answer TEXT --answer-src SRC
#                          [--date YYYY-MM-DD] [--apply --owner-confirmed]
#   docket.sh calibrate            run the calibration controls only; exit 0 or 3
#
# Exit codes: 0 ok · 2 usage · 3 CALIBRATION REFUSAL · 4 write refused (no owner
# confirmation) · 5 write refused (unattended context) · 6 repo enumeration failed.
#
# Env: $RELAY_TOML and $SRC_DIR are read (and defaulted) exactly as every other relay
# script defaults them, and are honoured by the hermetic tests.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The relay scripts live beside this skill once installed (~/.claude/skills/relay/scripts)
# and one directory up in the source tree. Try both, loudly.
_find_relay_scripts() {
  local candidate
  for candidate in \
    "$SCRIPT_DIR/../relay/scripts" \
    "$HOME/.claude/skills/relay/scripts"
  do
    [[ -d "$candidate" ]] && { (cd "$candidate" && pwd); return 0; }
  done
  return 1
}

RELAY_SCRIPTS="${DECISION_BRIEF_RELAY_SCRIPTS:-$(_find_relay_scripts || true)}"
if [[ -z "$RELAY_SCRIPTS" || ! -d "$RELAY_SCRIPTS" ]]; then
  echo "docket.sh: FATAL -- cannot locate relay/scripts (looked beside the skill and in ~/.claude/skills/relay/scripts). Run 'make install-relay'." >&2
  exit 2
fi

LANE_ANCHOR="$RELAY_SCRIPTS/lib-lane-anchor.sh"
OWN_REPOS_LIB="$RELAY_SCRIPTS/lib-own-repos.sh"
TYPED_EDGES="$RELAY_SCRIPTS/lib-typed-edges.sh"
COLLECTOR="$RELAY_SCRIPTS/gather-human-backlog.sh"
LANES_DOC="${DECISION_BRIEF_LANES_DOC:-$RELAY_SCRIPTS/../references/hard-lanes.md}"
MD_MERGE="${DECISION_BRIEF_MD_MERGE:-$SCRIPT_DIR/../meeting/md-merge.py}"

for lib in "$LANE_ANCHOR" "$OWN_REPOS_LIB" "$TYPED_EDGES"; do
  [[ -r "$lib" ]] || { echo "docket.sh: FATAL -- missing required library: $lib" >&2; exit 2; }
done

# shellcheck source=/dev/null
source "$LANE_ANCHOR"
# shellcheck source=/dev/null
source "$OWN_REPOS_LIB"
# shellcheck source=/dev/null
source "$TYPED_EDGES"

SRC_DIR="${SRC_DIR:-$HOME/src}"
RELAY_TOML="${RELAY_TOML:-$HOME/.config/relay/relay.toml}"
export SRC_DIR RELAY_TOML

TAB=$'\t'

emit() { printf '%s\n' "$*"; }

# TSV-safe: collapse tabs and newlines out of any field we did not build ourselves.
tsv_clean() { printf '%s' "$1" | tr '\t\n' '  ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'; }

# ======================================================================================
# CALIBRATION
# ======================================================================================
# Returns 0 only when the lane probe demonstrably discriminates. Any other outcome is a
# refusal, never a degraded-but-usable mode.
calibrate() {
  local detail

  if ! lane_vocab_scrape "$LANES_DOC" >/dev/null 2>&1; then
    emit "CALIBRATION${TAB}FAILED${TAB}lane_vocab_scrape refused the vocabulary doc at $LANES_DOC"
    echo "docket.sh: CALIBRATION REFUSAL -- lane_vocab_scrape could not read the lane vocabulary SSOT ($LANES_DOC). Refusing to report a count; an unscraped probe reports 'no lane' for every line." >&2
    return 3
  fi

  if [[ ${#all_lane_tags[@]} -eq 0 ]]; then
    emit "CALIBRATION${TAB}FAILED${TAB}all_lane_tags is EMPTY after the scrape"
    echo "docket.sh: CALIBRATION REFUSAL -- all_lane_tags is empty after lane_vocab_scrape. Refusing to report a count." >&2
    return 3
  fi

  # Positive control 1: a line whose primary lane is known to be [ROUTINE].
  if [[ -z "$(leading_lane_run '- [ ] [ROUTINE] calibration control line')" ]]; then
    emit "CALIBRATION${TAB}FAILED${TAB}positive control [ROUTINE] resolved to NO lane"
    echo "docket.sh: CALIBRATION REFUSAL -- the [ROUTINE] positive control resolved to no lane. The probe is unpopulated or broken; refusing to report a count." >&2
    return 3
  fi

  # Positive control 2: BOTH dash spellings must read (tolerant read / canonical emit).
  local hyphen_run emdash_run
  hyphen_run="$(leading_lane_run '- [ ] [INPUT - decision] calibration control line')"
  emdash_run="$(leading_lane_run '- [ ] [INPUT — decision] calibration control line')"
  if [[ -z "$hyphen_run" || -z "$emdash_run" ]]; then
    emit "CALIBRATION${TAB}FAILED${TAB}dual-delimiter control failed (hyphen='${hyphen_run}' emdash='${emdash_run}')"
    echo "docket.sh: CALIBRATION REFUSAL -- the probe does not read BOTH dash spellings of [INPUT - decision]. Refusing to report a count; a delimiter-blind reader silently drops every un-migrated ledger line." >&2
    return 3
  fi

  # Negative control: a probe that says yes to everything passes both positives above and
  # is exactly as broken. A lane tag in TRAILING prose is not a lane.
  if [[ -n "$(leading_lane_run '- [ ] Prose first, and only later a mention of [INPUT - decision] in the tail')" ]]; then
    emit "CALIBRATION${TAB}FAILED${TAB}negative control resolved to a lane (probe is unanchored)"
    echo "docket.sh: CALIBRATION REFUSAL -- the negative control resolved to a lane, so the probe is unanchored and would over-report. Refusing to report a count." >&2
    return 3
  fi

  # Control 5 -- the CLASSIFIER, not just the probe. Non-emptiness of the leading run is
  # NOT enough: a classifier that reads the run correctly and then parses the wrong token
  # out of it passes every control above and reports a docket of zero. That happened on
  # 2026-09-11 (see primary_decision_lane), so the control asserts the EXACT value.
  local parsed
  parsed="$(primary_decision_lane '- [ ] [INPUT - decision] classifier control')"
  if [[ "$parsed" != '[INPUT - decision]' ]]; then
    emit "CALIBRATION${TAB}FAILED${TAB}classifier control parsed '${parsed}', expected '[INPUT - decision]'"
    echo "docket.sh: CALIBRATION REFUSAL -- the lane CLASSIFIER mis-parses a known [INPUT - decision] line (got '${parsed}'). Refusing to report a count." >&2
    return 3
  fi
  parsed="$(primary_decision_lane '- [ ] [INPUT — meeting] classifier control')"
  if [[ "$parsed" != '[INPUT - meeting]' ]]; then
    emit "CALIBRATION${TAB}FAILED${TAB}em-dash classifier control parsed '${parsed}', expected '[INPUT - meeting]'"
    echo "docket.sh: CALIBRATION REFUSAL -- the lane classifier mis-parses the em-dash spelling (got '${parsed}'). Refusing to report a count." >&2
    return 3
  fi

  # Control 6 -- the classifier must also say NO. A [ROUTINE] item is not the owner's
  # decision; a classifier that answers yes to everything passes controls 1-5.
  parsed="$(primary_decision_lane '- [ ] [ROUTINE] classifier negative control')"
  if [[ -n "$parsed" ]]; then
    emit "CALIBRATION${TAB}FAILED${TAB}classifier negative control returned '${parsed}' for a [ROUTINE] item"
    echo "docket.sh: CALIBRATION REFUSAL -- the lane classifier claims a [ROUTINE] item is an owner decision. Refusing to report a count." >&2
    return 3
  fi

  # Controls 7-8 -- the DECORATION shapes the corpus actually uses. Both were measured as
  # false negatives on 2026-09-11 before strip_leading_decorations existed: ten items write
  # the lane inside the title's bold run, three prefix it with `[HIGH PRIORITY]`.
  parsed="$(primary_decision_lane '- [ ] **[INPUT — decision]** bold-wrapped control')"
  if [[ "$parsed" != '[INPUT - decision]' ]]; then
    emit "CALIBRATION${TAB}FAILED${TAB}bold-wrapped control parsed '${parsed}', expected '[INPUT - decision]'"
    echo "docket.sh: CALIBRATION REFUSAL -- the classifier misses a lane tag inside the title's bold run (got '${parsed}'). Refusing to report a count." >&2
    return 3
  fi
  parsed="$(primary_decision_lane '- [ ] [HIGH PRIORITY] [INPUT — decision] flag-prefixed control')"
  if [[ "$parsed" != '[INPUT - decision]' ]]; then
    emit "CALIBRATION${TAB}FAILED${TAB}flag-prefixed control parsed '${parsed}', expected '[INPUT - decision]'"
    echo "docket.sh: CALIBRATION REFUSAL -- the classifier misses a lane tag behind a non-lane bracket flag (got '${parsed}'). Refusing to report a count." >&2
    return 3
  fi

  # Control 9 -- decoration stripping must NOT step over a word. This is the control that
  # keeps controls 7-8 from re-opening the over-report they were added beside.
  parsed="$(primary_decision_lane '- [ ] **Some title** that later mentions [INPUT — decision] in its tail')"
  if [[ -n "$parsed" ]]; then
    emit "CALIBRATION${TAB}FAILED${TAB}decoration control stepped over prose and returned '${parsed}'"
    echo "docket.sh: CALIBRATION REFUSAL -- decoration stripping stepped over a word and found a trailing prose mention. Refusing to report a count; this is the over-report the anchoring exists to prevent." >&2
    return 3
  fi

  detail="vocab=$LANES_DOC tags=${#all_lane_tags[@]} controls=10/10"
  emit "CALIBRATION${TAB}ok${TAB}${detail}"
  return 0
}

# ======================================================================================
# LANE CLASSIFICATION (anchored)
# ======================================================================================
# primary_decision_lane <item-text> -- echo the canonical spaced-hyphen lane tag when the
# item's ANCHORED primary lane is a lane the owner personally decides, else nothing.
#
# Reading accepts BOTH dash spellings (lane_vocab_scrape put both in all_lane_tags);
# emission is ALWAYS the spaced-hyphen form, because the pre-commit lane-vocab ratchet
# blocks a commit that ADDS an old-vocab tag.
# A LANE TAG CONTAINS SPACES, so the first tag of the run CANNOT be taken with
# `${run%% *}` -- that splits inside `[INPUT - meeting]` and yields `[INPUT`, which
# matches nothing and reports "not a decision lane" for every item on earth. Measured on
# 2026-09-11 against this repo: the space-splitting version suppressed all 158 candidates
# and reported a confident docket of zero. The run is therefore matched by PREFIX against
# each known spelling instead, longest-first so `[HARD - decision gate]` is never shadowed.
#
# The calibration gate now asserts the full parse, not merely non-emptiness, because
# non-emptiness is what that version passed.
# strip_leading_decorations <text> -- drop the LEADING run of non-lane decoration so the
# anchored lane probe sees the lane tag that a human reads as leading.
#
# `leading_lane_run` requires the bracket at the very START of the item text, and MEASURED
# on this repo 2026-09-11 that dropped 13 items whose lane is unambiguously leading: ten
# written `**[INPUT - decision]** ...` (the tag inside the title's bold run) and three
# written `[HIGH PRIORITY] [INPUT - decision] ...`. Suppressing those as "prose mentions"
# is the opposite error from the over-report and just as wrong.
#
# The rule is STRUCTURAL, not an enumeration of today's decoration names: strip emphasis
# markers, a leading symbol/emoji run, and any COMPLETE `[...]` bracket that is not itself
# a recognized lane tag. The repo's own bracket taxonomy has exactly three leading classes
# (tools/ledger-shrink.py `_protected_spans`: lane tags, `[INBOUND ...]` provenance,
# `[HIGH PRIORITY]` flags), so "bracket that is not a lane" covers both decoration classes
# and any decoration minted later -- an enumeration of the current names is the id:d35a
# regression a shape-anchored rule exists to prevent.
#
# The anti-over-report guarantee SURVIVES because nothing here steps over a WORD: the loop
# stops at the first alphanumeric character, so `- [ ] Prose that mentions [INPUT - decision]`
# still resolves to no lane. Bounded at 12 iterations; the lane tag itself is never stripped.
strip_leading_decorations() {
  local s="$1" i tag rest first is_lane
  # Drop a checkbox prefix explicitly rather than letting the symbol branch nibble it.
  [[ "$s" =~ ^-[[:space:]]\[[[:space:]xX]\][[:space:]]*(.*)$ ]] && s="${BASH_REMATCH[1]}"
  for (( i=0; i<12; i++ )); do
    s="${s#"${s%%[![:space:]]*}"}"
    is_lane=0
    for tag in "${all_lane_tags[@]}"; do
      [[ "$s" == "$tag"* ]] && { is_lane=1; break; }
    done
    [[ $is_lane -eq 1 ]] && break
    case "$s" in
      '**'*|'__'*) s="${s:2}"; continue ;;
      '*'*|'_'*)   s="${s:1}"; continue ;;
      '['*)
        rest="${s#*]}"
        [[ "$rest" != "$s" ]] || break
        s="$rest"; continue ;;
    esac
    first="${s:0:1}"
    [[ -n "$first" ]] || break
    # Stop at real content; otherwise drop one leading symbol (emoji, punctuation).
    case "$first" in
      [[:alnum:]]|'`'|'('|'"'|"'") break ;;
      *) s="${s:1}" ;;
    esac
  done
  printf '%s' "$s"
}

# lane_after_detail_pointer <item-text> -- true when the item has a recognized lane tag
# that sits AFTER its `-- detail:` pointer.
#
# This is a KNOWN LEDGER DEFECT, not a prose mention, and the two must not share a
# suppression reason. A line-shrink that re-appends kept tokens to the TAIL leaves the
# item's real lane after the pointer, where every anchored reader (this one,
# roadmap-lint 3(g), PARKED-POOL-LANE) sees no lane at all -- the silent escape CLAUDE.md
# records under id:0d7c. MEASURED here 2026-09-11: six open items in this repo's TODO.md
# are in exactly that shape, e.g. `id:2a3d` and `id:1968`.
#
# The right handling is to REFUSE TO GUESS and say so loudly. Reading the trailing tag as
# the primary lane would re-open the over-report; dropping it as "prose" hides a real
# defect. So it gets its own reason and its own coverage counter, and the fix belongs at
# the source line, not here.
lane_after_detail_pointer() {
  local text="$1" masked tail tag
  masked="$(mask_backticks "$text")"
  case "$masked" in
    *'-- detail:'*) tail="${masked#*-- detail:}" ;;
    *) return 1 ;;
  esac
  for tag in "${all_lane_tags[@]}"; do
    [[ "$tail" == *"$tag"* ]] && return 0
  done
  return 1
}

# anchored_lane_run <item-text> -- the raw leading lane run, decorations stripped. Used to
# tell "this item HAS a leading lane, it just is not a decision lane" (e.g. `[ROUTINE]`,
# which is a correct and uninteresting suppression) apart from "this item has NO leading
# lane at all" (which is where the id:0d7c relocation defect hides). Those two need
# different suppression reasons because they need opposite remedies: the first is nothing
# to fix, the second is a source line to repair.
anchored_lane_run() {
  local masked
  masked="$(mask_backticks "$1")"
  masked="$(strip_leading_decorations "$masked")"
  leading_lane_run "$masked"
}

primary_decision_lane() {
  local text="$1" masked run
  masked="$(mask_backticks "$text")"
  masked="$(strip_leading_decorations "$masked")"
  run="$(leading_lane_run "$masked")"
  [[ -n "$run" ]] || return 0
  # leading_lane_run space-joins with a TRAILING space, so every tag in the run is
  # followed by exactly one space; a `"$tag "*` prefix test cannot match a partial tag.
  case "$run" in
    '[HARD - decision gate] '*|'[HARD — decision gate] '*) printf '%s' '[INPUT - decision]' ;;
    '[INPUT - decision] '*|'[INPUT — decision] '*)         printf '%s' '[INPUT - decision]' ;;
    '[INPUT - meeting] '*|'[INPUT — meeting] '*)           printf '%s' '[INPUT - meeting]' ;;
    '[HARD - meeting] '*|'[HARD — meeting] '*)             printf '%s' '[INPUT - meeting]' ;;
    *) : ;;
  esac
  return 0
}

# ======================================================================================
# BLOCKS -- "what does this item hold up?"
# ======================================================================================
# Builds, per repo, a map from a gating id to the CSV of open item ids that declare
# `<!-- gated-on:... -->` on it. Edges are read through the shared id:46f6 engine, so a
# bare `gated-on:xxxx` in prose is never an edge.
#
# HONEST LIMIT, restated in the coverage footer and again in SKILL.md: most items carry no
# typed edge at all, so a `blocks_n` of 0 means "no DECLARED dependant", never "blocks
# nothing". Gate-graph fan-out ranking proper is id:c3f6 and is not built here.
declare -A BLOCKED_BY=()

build_blocks_map() {
  local repo_root="$1" ledger line gated tok own
  for ledger in "$repo_root/TODO.md" "$repo_root/ROADMAP.md"; do
    [[ -r "$ledger" ]] || continue
    while IFS= read -r line; do
      [[ "$line" == *'<!-- gated-on:'* ]] || continue
      gated="$(typed_edges_gated_of_line "$line")"
      [[ -n "$gated" ]] || continue
      own="$(typed_edges_own_id_of_line "$line")"
      [[ -n "$own" ]] || own="?"
      # The `\n` in the printf below is LOAD-BEARING: without a trailing newline `read`
      # drops the FINAL token, and for a single-token payload like `gated-on:a08d` that is
      # the ONLY token, so the edge vanishes and the item reports "blocks nothing".
      # MEASURED 2026-09-11 on this repo: 43 edge-bearing lines collapsed to 7 keys.
      while IFS= read -r tok; do
        [[ -n "$tok" ]] || continue
        if [[ -n "${BLOCKED_BY[$tok]:-}" ]]; then
          case ",${BLOCKED_BY[$tok]}," in
            *",$own,"*) : ;;
            *) BLOCKED_BY[$tok]="${BLOCKED_BY[$tok]},$own" ;;
          esac
        else
          BLOCKED_BY[$tok]="$own"
        fi
      done < <(printf '%s\n' "$gated" | tr ',' '\n')
    done < "$ledger"
  done
}

# ======================================================================================
# SCAN
# ======================================================================================
cmd_scan() {
  local include_answered=0 max=0
  local -a want_repos=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo)             want_repos+=("${2:-}"); shift 2 || return 2 ;;
      --include-answered) include_answered=1; shift ;;
      --max)              max="${2:-0}"; shift 2 || return 2 ;;
      -h|--help)          usage; return 0 ;;
      *) echo "docket.sh: unknown argument: $1" >&2; usage; return 2 ;;
    esac
  done

  # CALIBRATE BEFORE COUNTING. Not after, not alongside.
  calibrate || return 3

  # --- repo enumeration -----------------------------------------------------------
  # own_repos REQUIRES $RELAY_TOML/$SRC_DIR and its exit status MUST be checked here: a
  # bare `while ...; done < <(own_repos)` discards a subshell's status and yields zero
  # repos, silently, on a corrupt relay.toml (id:0fa0 finding (a)). Capture, then test.
  local repo_lines repo_rc
  local -a repo_names=()
  local -A repo_path_of=()
  repo_lines="$(own_repos)"; repo_rc=$?
  if [[ $repo_rc -ne 0 ]]; then
    echo "docket.sh: FATAL -- own_repos failed (rc=$repo_rc) reading $RELAY_TOML. Refusing to scan a repo set we could not enumerate." >&2
    emit "COVERAGE${TAB}enumeration${TAB}FAILED rc=$repo_rc toml=$RELAY_TOML"
    return 6
  fi

  local rname rroot
  while IFS=$'\t' read -r rname rroot; do
    [[ -n "$rname" ]] || continue
    if [[ ${#want_repos[@]} -gt 0 ]]; then
      local wanted=0 w
      for w in "${want_repos[@]}"; do [[ "$w" == "$rname" ]] && wanted=1; done
      [[ $wanted -eq 1 ]] || continue
    fi
    repo_names+=("$rname")
    repo_path_of["$rname"]="$rroot"
  done <<< "$repo_lines"

  if [[ ${#repo_names[@]} -eq 0 ]]; then
    emit "COVERAGE${TAB}repos_scanned${TAB}0"
    emit "COVERAGE${TAB}note${TAB}relay.toml declared no matching confirmed own repo; this is an EMPTY SCOPE, not an empty docket"
    return 0
  fi

  # --- collection (delegated, NEVER truncated) -------------------------------------
  # gather-human-backlog.sh's caller contract (id:da87) forbids piping it through
  # head/tail: rows are emitted per repo in a fixed order and a truncated TSV reads as a
  # legitimate "nothing to do". Capture the whole stream to a file, then filter.
  # A temp DIRECTORY, so the cleanup is the sanctioned `rm -rf "$dir"` idiom rather than a
  # single-file force flag (tools/check-no-bare-rm-f.sh).
  local rawdir raw collector_rc
  rawdir="$(mktemp -d)"
  raw="$rawdir/backlog.tsv"
  # shellcheck disable=SC2064
  trap "rm -rf '$rawdir'" RETURN
  # The collector's stderr is CAPTURED, never discarded: its ERROR lines are the id:415b
  # untagged-lane loud reject, and `2>/dev/null` on a collector whose whole contract is
  # "fail loudly" is the no-silent-swallow anti-pattern.
  local collector_err="$rawdir/backlog.err"
  "$COLLECTOR" "${repo_names[@]}" >"$raw" 2>"$collector_err"
  collector_rc=$?
  # A NONZERO collector is the id:415b untagged-lane LOUD reject, which fires AFTER every
  # row is emitted. We keep the rows and report the status; we never swallow it.

  local -a rows=()
  local -a suppressed=()
  local n_candidates=0 n_suppressed_lane=0 n_suppressed_answered=0 n_suppressed_trailing=0

  # FIELD ORDER, from gather-human-backlog.sh's own contract: repo, PATH, kind,
  # box_summary. The second field is the repo PATH, not a ledger filename -- reading it as
  # one makes every `*ROADMAP.md` test silently false.
  local kind_field repo_field repo_path_field summary_field
  local cur_repo=""
  while IFS=$'\t' read -r repo_field repo_path_field kind_field summary_field; do
    [[ -n "$repo_field" ]] || continue
    case "$kind_field" in
      human_decision|hard_meeting) : ;;
      *) continue ;;
    esac
    n_candidates=$((n_candidates + 1))

    local item_id lane note_rel blocks_ids blocks_n root_dir ledger_file
    root_dir="${repo_path_of[$repo_field]:-${repo_path_field:-$SRC_DIR/$repo_field}}"
    item_id="$(typed_edges_own_id_of_line "$summary_field")"
    [[ -n "$item_id" ]] || item_id="-"

    # ANCHORED re-resolution. This is where the collector's unanchored earliest-match is
    # corrected; a trailing-prose lane mention drops out here, LOUDLY and counted.
    lane="$(primary_decision_lane "$summary_field")"
    if [[ -z "$lane" ]]; then
      local anchored_run reason
      anchored_run="$(anchored_lane_run "$summary_field")"
      if [[ -n "$anchored_run" ]]; then
        # A leading lane IS present, it is simply not one the owner personally decides
        # (typically [ROUTINE]). Nothing to fix; the collector's unanchored match is what
        # offered it. This is the over-report correction working as intended.
        reason="not-a-decision-lane"
        n_suppressed_lane=$((n_suppressed_lane + 1))
      elif lane_after_detail_pointer "$summary_field"; then
        reason="lane-after-detail-pointer"
        n_suppressed_trailing=$((n_suppressed_trailing + 1))
      else
        reason="lane-mention-not-primary"
        n_suppressed_lane=$((n_suppressed_lane + 1))
      fi
      suppressed+=("SUPPRESSED${TAB}${repo_field}${TAB}${item_id}${TAB}${reason}${TAB}$(tsv_clean "$summary_field")")
      continue
    fi

    if [[ $include_answered -eq 0 && "$summary_field" == *'@owner-answered:'* ]]; then
      n_suppressed_answered=$((n_suppressed_answered + 1))
      suppressed+=("SUPPRESSED${TAB}${repo_field}${TAB}${item_id}${TAB}owner-answered${TAB}$(tsv_clean "$summary_field")")
      continue
    fi

    if [[ "$cur_repo" != "$repo_field" ]]; then
      BLOCKED_BY=()
      build_blocks_map "$root_dir"
      cur_repo="$repo_field"
    fi

    blocks_ids="${BLOCKED_BY[$item_id]:-}"
    if [[ -n "$blocks_ids" ]]; then
      blocks_n="$(printf '%s\n' "$blocks_ids" | tr ',' '\n' | grep -c . || true)"
    else
      blocks_ids="-"; blocks_n=0
    fi

    note_rel="-"
    if [[ "$item_id" != "-" && -r "$root_dir/docs/ledger-notes/$item_id.md" ]]; then
      note_rel="docs/ledger-notes/$item_id.md"
    fi

    # Which ledger the item lives in has to be DERIVED -- the collector does not emit it.
    # Resolve it by the anchored marker, ROADMAP first (single-id-two-views: an id present
    # in both is a promoted item, and ROADMAP is the execution view).
    ledger_file="-"
    local promoted=0
    if [[ "$item_id" != "-" ]]; then
      if [[ -r "$root_dir/ROADMAP.md" ]] && grep -qF -- "<!-- id:$item_id -->" "$root_dir/ROADMAP.md"; then
        ledger_file="ROADMAP.md"; promoted=1
      elif [[ -r "$root_dir/TODO.md" ]] && grep -qF -- "<!-- id:$item_id -->" "$root_dir/TODO.md"; then
        ledger_file="TODO.md"
      fi
    fi

    # SECONDARY sort key: an item already promoted to ROADMAP.md is one the relay is ready
    # to act on, so a pending decision on it is nearer to blocking real execution than the
    # same decision on a TODO-only item. WEAK signal, stated as one in the coverage footer
    # -- the CONSEQUENCE judgment belongs to the brief, which reads the note, not to this
    # sort.
    rows+=("${blocks_n}${TAB}${promoted}${TAB}${repo_field}${TAB}${ledger_file}${TAB}${item_id}${TAB}${lane}${TAB}${blocks_n}${TAB}${blocks_ids}${TAB}${note_rel}${TAB}$(tsv_clean "$summary_field")")
  done < "$raw"

  # --- rank and emit ---------------------------------------------------------------
  local rank=0 emitted=0 sorted_line
  if [[ ${#rows[@]} -gt 0 ]]; then
    while IFS= read -r sorted_line; do
      [[ -n "$sorted_line" ]] || continue
      rank=$((rank + 1))
      [[ $max -gt 0 && $rank -gt $max ]] && break
      # Drop the TWO sort keys (blocks_n, promoted) before emitting.
      sorted_line="${sorted_line#*"$TAB"}"
      emit "ROW${TAB}${rank}${TAB}${sorted_line#*"$TAB"}"
      emitted=$((emitted + 1))
    done < <(printf '%s\n' "${rows[@]}" | sort -t"$TAB" -k1,1nr -k2,2nr -k3,3 -s)
  fi

  local s
  if [[ ${#suppressed[@]} -gt 0 ]]; then
    for s in "${suppressed[@]}"; do emit "$s"; done
  fi

  emit "COVERAGE${TAB}repos_scanned${TAB}${#repo_names[@]}"
  emit "COVERAGE${TAB}collector_exit${TAB}${collector_rc}"
  [[ $collector_rc -ne 0 ]] && \
    emit "COVERAGE${TAB}collector_warning${TAB}gather-human-backlog.sh exited ${collector_rc} -- usually the id:415b untagged-lane LOUD reject. Rows above are complete; the lane gap is real and should be fixed at the source."
  if [[ -s "$collector_err" ]]; then
    emit "COVERAGE${TAB}collector_stderr_lines${TAB}$(grep -c . "$collector_err" || echo 0)"
    # Replay it on OUR stderr so nothing is lost, then point at it in the footer.
    sed 's/^/gather-human-backlog: /' "$collector_err" >&2
  fi
  emit "COVERAGE${TAB}candidates${TAB}${n_candidates}"
  emit "COVERAGE${TAB}docketed${TAB}${emitted}"
  emit "COVERAGE${TAB}suppressed_lane_mention${TAB}${n_suppressed_lane}"
  emit "COVERAGE${TAB}suppressed_lane_after_detail_pointer${TAB}${n_suppressed_trailing}"
  [[ $n_suppressed_trailing -gt 0 ]] && \
    emit "COVERAGE${TAB}ledger_defect${TAB}${n_suppressed_trailing} item(s) carry a lane tag AFTER their -- detail: pointer, where every anchored reader is blind to it (id:0d7c relocation defect). Fix at the source line; this tool refuses to guess their lane."
  emit "COVERAGE${TAB}suppressed_owner_answered${TAB}${n_suppressed_answered}"
  emit "COVERAGE${TAB}gated_on_edges_indexed${TAB}${#BLOCKED_BY[@]}"
  emit "COVERAGE${TAB}ranking${TAB}primary key = DECLARED gated-on dependants; tiebreak = promoted to ROADMAP.md. An item with no typed edge ranks 0, which means 'no DECLARED dependant', NEVER 'blocks nothing' -- most items carry no typed edge, so this ordering is a WEAK prior and the consequence judgment belongs to the brief, not to this sort (gate-graph fan-out ranking proper is id:c3f6, not built)"
  emit "COVERAGE${TAB}scope${TAB}what the ledgers EXPRESS as a decision lane; a decision recorded only as prose in a note is NOT found here"
  return 0
}

# ======================================================================================
# DRAFT-ANSWER -- the propose-then-confirm write path
# ======================================================================================
# The `@owner-answered:YYYY-MM-DD` marker plus its mandatory `<!-- answer-src:... -->`
# citation is OWNER-ONLY by contract (executor-contract.md rule 8, hard-lanes.md "Who may
# write it"). Its entire value is that only a genuine owner action writes it, so the
# default here is REFUSE:
#
#   no --apply                       -> print the proposed line and the exact command; write nothing
#   --apply without --owner-confirmed-> exit 4, loudly
#   --apply in an unattended context -> exit 5, loudly, EVEN WITH the confirmation flag
#
# The unattended refusal is deliberately NOT overridable. Under --afk or in a pool there is
# no owner to answer an AskUserQuestion, so a confirmation flag there can only have been
# set by an agent, which is precisely the marker-forgery this contract exists to prevent.
cmd_draft_answer() {
  local repo_path="" item_id="" answer="" answer_src="" adate="" apply=0 confirmed=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo-path)       repo_path="${2:-}"; shift 2 || return 2 ;;
      --id)              item_id="${2:-}"; shift 2 || return 2 ;;
      --answer)          answer="${2:-}"; shift 2 || return 2 ;;
      --answer-src)      answer_src="${2:-}"; shift 2 || return 2 ;;
      --date)            adate="${2:-}"; shift 2 || return 2 ;;
      --apply)           apply=1; shift ;;
      --owner-confirmed) confirmed=1; shift ;;
      -h|--help)         usage; return 0 ;;
      *) echo "docket.sh: unknown argument: $1" >&2; return 2 ;;
    esac
  done

  [[ -n "$repo_path" && -n "$item_id" && -n "$answer" && -n "$answer_src" ]] || {
    echo "docket.sh draft-answer: --repo-path, --id, --answer and --answer-src are ALL mandatory. A marker with no citation is worthless (hard-lanes.md)." >&2
    return 2
  }
  [[ -d "$repo_path" ]] || { echo "docket.sh draft-answer: no such repo path: $repo_path" >&2; return 2; }
  [[ -n "$adate" ]] || adate="$(date '+%Y-%m-%d')"

  local ledger existing=""
  for ledger in "$repo_path/TODO.md" "$repo_path/ROADMAP.md"; do
    [[ -r "$ledger" ]] || continue
    # `grep -m1` rather than `grep | head -1`: a producer piped into an early-exiting
    # consumer under `pipefail` is the id:81d5 shape the repo lints for.
    existing="$(grep -m1 -F -- "<!-- id:$item_id -->" "$ledger" || true)"
    [[ -n "$existing" ]] && break
  done
  if [[ -z "$existing" ]]; then
    echo "docket.sh draft-answer: no anchored '<!-- id:$item_id -->' line in $repo_path/{TODO,ROADMAP}.md. Refusing to invent one." >&2
    return 2
  fi

  # md-merge.py addresses a line ONLY by an anchored marker or a `## ` heading, and it
  # REFUSES a multi-marker line (id:6059). Check that here so the refusal is understood
  # rather than merely inherited.
  local marker_count
  marker_count="$(grep -o '<!-- id:[0-9a-f]\{4\} -->' <<<"$existing" | wc -l | tr -d ' ')"
  if [[ "$marker_count" != "1" ]]; then
    echo "docket.sh draft-answer: the target line carries $marker_count anchored id markers; md-merge.py REFUSES a multi-marker line (id:6059). Surface this to the owner; do not hand-edit." >&2
    return 2
  fi

  local proposed
  proposed="${existing%%<!-- id:$item_id -->}"
  proposed="${proposed% }"
  proposed="${proposed} @owner-answered:${adate} <!-- answer-src:${answer_src} --> <!-- id:${item_id} -->"

  echo "-- PROPOSED (nothing written) -------------------------------------------------"
  echo "repo:    $repo_path"
  echo "id:      $item_id"
  echo "answer:  $answer"
  echo "current: $existing"
  echo "propose: $proposed"
  echo "-------------------------------------------------------------------------------"

  if [[ $apply -eq 0 ]]; then
    echo "Not applied. Re-run with --apply --owner-confirmed ONLY after the owner has answered the AskUserQuestion in this session."
    return 0
  fi

  if [[ -n "${RELAY_AFK:-}${RELAY_RUN_ID:-}${RELAY_POOL:-}${DECISION_BRIEF_UNATTENDED:-}" ]]; then
    echo "docket.sh draft-answer: REFUSED -- unattended context detected (RELAY_AFK/RELAY_RUN_ID/RELAY_POOL/DECISION_BRIEF_UNATTENDED). @owner-answered is owner-only and there is no owner here to answer. Surface the decision instead; do not write." >&2
    return 5
  fi

  if [[ $confirmed -eq 0 ]]; then
    echo "docket.sh draft-answer: REFUSED -- --apply requires --owner-confirmed. Propose-then-confirm: the verdict is the owner's and only a genuine owner action writes @owner-answered." >&2
    return 4
  fi

  [[ -x "$MD_MERGE" || -r "$MD_MERGE" ]] || {
    echo "docket.sh draft-answer: md-merge.py not found at $MD_MERGE" >&2; return 2; }

  python3 "$MD_MERGE" update-ids --file "$ledger" <<JSON
{"updates": [{"id": "$item_id", "line": $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$proposed")}]}
JSON
  local rc=$?
  if [[ $rc -eq 0 ]]; then
    echo "Applied to $ledger under md-merge.py's flock."
  else
    echo "docket.sh draft-answer: md-merge.py exited $rc; nothing is claimed to have been written." >&2
  fi
  return $rc
}

usage() {
  sed -n '/^# USAGE/,/^# Env:/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

main() {
  local sub="${1:-scan}"
  case "$sub" in
    scan)          shift || true; cmd_scan "$@" ;;
    calibrate)     calibrate ;;
    draft-answer)  shift; cmd_draft_answer "$@" ;;
    -h|--help)     usage ;;
    --*)           cmd_scan "$@" ;;
    *)             echo "docket.sh: unknown subcommand: $sub" >&2; usage; return 2 ;;
  esac
}

main "$@"
