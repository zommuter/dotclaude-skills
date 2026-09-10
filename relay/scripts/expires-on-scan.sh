#!/usr/bin/env bash
# relay/scripts/expires-on-scan.sh -- id:a192 self-expiring-prose staleness guard.
#
# WHY: a clause is sometimes only correct until some item closes. This repo has no
# way for such a clause to notice its own expiry, so a file loaded every session
# (the motivating live case: a CAUTION block in the owner's ~/.claude/CLAUDE.md keyed
# to id:0246) can silently keep asserting something that stopped being true. Measured
# fleet-wide: 1,074 id-keyed temporary clauses, 17 already stale in live files. A
# prose detector ("until id:XXXX lands") is unusable here -- most of the corpus's
# temporary-clause prose is test-header PROVENANCE, not a live promise, so a prose
# heuristic is wrong on the majority of its own hits. This guard never infers expiry
# from English; it reads only the explicit, opt-in typed edge:
#
#     <!-- expires-on:XXXX -->     XXXX = a single 4-hex item id
#
# A clause carrying that marker promises: "delete me when XXXX closes". The guard
# fails loudly when that promise has gone stale.
#
# Usage:
#   expires-on-scan.sh [<root>]      root defaults to `git rev-parse --show-toplevel`
#   env EXPIRES_ON_EXTRA_PATHS       colon-separated ABSOLUTE paths scanned IN ADDITION
#                                    to <root>'s tracked files. Empty by default -- see
#                                    LIMITATION below.
#   env EXPIRES_ON_SCAN_LOG          detail-log path (repo convention: short stdout,
#                                    detail to a log). Default ~/.claude/logs/expires-on-scan.log.
#
# stdout, one finding per line, machine-readable, naming FILE and LINE:
#   STALE    <path>:<lineno> expires-on:<tok>    tok exists (owned by a checkbox line
#                                                 in a local ledger) and is CLOSED
#   DANGLING <path>:<lineno> expires-on:<tok>    tok exists NOWHERE in the local
#                                                 ledgers -- almost always a typo
# A CSV marker (`expires-on:a,b`) is a loud CONFIG ERROR on stderr, never interpreted
# -- see the CSV note below.
#
# Exit status: 2 on any CONFIG ERROR; else 1 when any STALE/DANGLING finding; else 0.
#
# SCAN SET: `git ls-files` under <root> -- tracked text files ONLY. Untracked files are
# deliberately excluded: this repo keeps local-only files (meeting/discoveries.md,
# meeting/user-profile.md) that must never feed a gate. Because the marker is explicit
# and opt-in, a wide default costs nothing in false positives, while a narrow
# `*.md`-only default would miss the worst real cases -- behavioural claims inside
# production `.sh` scripts (e.g. todo-conformance.sh, changelog-append.sh both carried
# one, already stale).
#
# SCAN EXEMPTIONS (dated historical records; a stale promise there is CORRECT history,
# not a defect): any `*.archive.md`, and anything under `docs/meeting-notes/`. Exempt
# from being SCANNED is NOT exempt from being a CLOSURE SOURCE -- see below.
#
# CLOSURE / EXISTENCE: ownership-anchored, via relay/scripts/lib-anchored-id.sh's
# `token_owned_by_checkbox_in_files` (id:a192's sibling addition to that library) over
# <root>'s TODO.md, ROADMAP.md, TODO.archive.md, ROADMAP.archive.md:
#   EXISTS  -- some `- [ ]`/`- [x]` line OWNS the token (closed_only=0).
#   CLOSED  -- narrowed to `- [x]` lines only (closed_only=1).
# This is deliberately NOT `token_own_checkbox_marker_in_text` (a plain grep): that
# predicate does not inherit the id:6059 multi-marker refusal, so a checkbox line
# carrying two `<!-- id:XXXX -->` markers (this repo's TODO.md has 3 such lines today)
# would satisfy it for either token. The resolver used here refuses an ambiguous line
# -- it resolves to nothing, never a guessed match.
#
# NON-MONOTONIC CLOSURE: this repo reopens items. An id that closes and is later
# reopened silently loses this guard's protection in the other direction -- a marker
# whose target just reopened would read as OPEN again with no distinct signal that it
# was ever stale. Documented, not built for; building for it is a separate item.
#
# CSV / MULTIPLE IDS: `expires-on:XXXX` names exactly ONE id. A CSV form
# (`expires-on:a,b`) is REFUSED as a loud CONFIG ERROR, never interpreted -- every
# other typed edge in this repo (`gated-on:`, `children:`) IS comma-separated, so
# someone will eventually write this by habit, and "all closed" vs "any closed" is
# the exact outcome-inverting ambiguity this repo's own rules flag as something to
# surface rather than guess. Refusing defers that decision instead of picking one.
#
# REPORT-ONLY: no auto-delete, no file edits, ever. An auto-apply mode is a separate,
# owner-gated item; this script never anticipates it.
#
# LIMITATION: the clause that motivated this item lives in the owner's
# ~/.claude/CLAUDE.md, outside any repo this scanner's default set reaches.
# EXPIRES_ON_EXTRA_PATHS opts such a file in explicitly; nothing reaches it by
# default. A wrapper, hook, or the owner's own invocation must name that path.
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib-anchored-id.sh
source "$SCRIPTS_DIR/lib-anchored-id.sh"

ROOT="${1:-$(git rev-parse --show-toplevel)}"
LOG="${EXPIRES_ON_SCAN_LOG:-$HOME/.claude/logs/expires-on-scan.log}"
EXTRA="${EXPIRES_ON_EXTRA_PATHS:-}"

mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
log() { printf '%s\n' "$*" >>"$LOG" 2>/dev/null || true; }

CLOSURE_FILES=(
  "$ROOT/TODO.md"
  "$ROOT/ROADMAP.md"
  "$ROOT/TODO.archive.md"
  "$ROOT/ROADMAP.archive.md"
)

EXEMPT_RE='(\.archive\.md$)|(^docs/meeting-notes/)'
MARKER_RE='<!--[[:space:]]*expires-on:[0-9a-fA-F,]+[[:space:]]*-->'
TOK_EXTRACT_RE='s/.*expires-on:([0-9a-fA-F,]+).*/\1/'

findings=0
config_errors=0

# ── Resolve the ledger ONCE, not once per marker (id:a192 follow-up) ──────────────────────
# `token_owned_by_checkbox_in_files` re-reads all four ledgers on every call AND, by design,
# emits one `AMBIGUOUS own id` warning per multi-marker line it meets (the id:6059 refusal we
# deliberately inherit). Called twice per marker that resolves, that multiplies a property of
# the DATA by the number of MARKERS: measured 18 stderr lines for a 3-file scan with 2 markers,
# against 6 genuinely ambiguous lines in `TODO.archive.md`. At any real marker count the report
# drowns in its own warnings, and a warning nobody can read is a warning nobody heeds -- the
# same reason this tool refuses to detect expiry from prose.
# So: one pass builds the EXISTS and CLOSED sets, the per-marker loop does lookups in memory,
# and the ambiguity warnings fire at their correct cardinality (once per ambiguous line, per
# run). Nothing is suppressed.
declare -A _EXISTS_IDS=() _CLOSED_IDS=()
_build_id_sets() {
  local f line tok
  for f in "${CLOSURE_FILES[@]}"; do
    [[ -f "$f" ]] || continue
    while IFS= read -r line; do
      tok="$(own_token_of_line "$line" "$f")" || continue
      # own_token_of_line returns the marker WITH its kind prefix (`id:XXXX` / `routed:XXXX`);
      # strip it, since an expires-on: marker names the bare 4-hex token. Getting this wrong
      # silently empties both sets and reports every marker DANGLING -- which is exactly what
      # the first draft of this block did, and the reason the fixture cases are not optional.
      tok="${tok##*:}"
      [[ -n "$tok" ]] || continue
      _EXISTS_IDS["$tok"]=1
      [[ "$line" =~ ^[[:space:]]*-[[:space:]]\[[xX]\] ]] && _CLOSED_IDS["$tok"]=1
    done < <(grep -E '^[[:space:]]*-[[:space:]]\[[[:space:]xX]\]' "$f" 2>/dev/null || true)
  done
}
_build_id_sets

# scan_file <path> <display-name> -- find every `expires-on:` marker in <path> and
# report it. <display-name> is what lands in the STALE/DANGLING output line.
scan_file() {
  local f="$1" rel="$2" lineno match tok_list tok
  [[ -f "$f" ]] || return 0
  while IFS=: read -r lineno match; do
    [[ -n "${lineno:-}" ]] || continue
    tok_list="$(sed -E "$TOK_EXTRACT_RE" <<<"$match")"
    if [[ "$tok_list" == *,* ]]; then
      printf 'CONFIG-ERROR %s:%s expires-on:%s -- multi-id CSV form refused (all-closed vs any-closed is undecided); split into separate expires-on: markers\n' \
        "$rel" "$lineno" "$tok_list" >&2
      log "config-error file=$rel line=$lineno csv=$tok_list"
      config_errors=1
      continue
    fi
    tok="$tok_list"
    if ! [[ "$tok" =~ ^[0-9a-fA-F]{4}$ ]]; then
      printf 'CONFIG-ERROR %s:%s expires-on:%s -- malformed token (must be exactly 4 hex digits)\n' \
        "$rel" "$lineno" "$tok" >&2
      log "config-error file=$rel line=$lineno malformed=$tok"
      config_errors=1
      continue
    fi
    if [[ -n "${_EXISTS_IDS[$tok]:-}" ]]; then
      if [[ -n "${_CLOSED_IDS[$tok]:-}" ]]; then
        printf 'STALE %s:%s expires-on:%s\n' "$rel" "$lineno" "$tok"
        log "stale file=$rel line=$lineno tok=$tok"
        findings=1
      fi
      # EXISTS but OPEN: the clause is legitimately live. Silent, on purpose.
    else
      printf 'DANGLING %s:%s expires-on:%s\n' "$rel" "$lineno" "$tok"
      log "dangling file=$rel line=$lineno tok=$tok"
      findings=1
    fi
  done < <(grep -noE -- "$MARKER_RE" "$f" 2>/dev/null || true)
}

# --- default scan set: git ls-files under ROOT, tracked text files only ---------
while IFS= read -r rel; do
  [[ -n "$rel" ]] || continue
  [[ "$rel" =~ $EXEMPT_RE ]] && continue
  scan_file "$ROOT/$rel" "$rel"
done < <(git -C "$ROOT" ls-files)

# --- opt-in extra paths (EXPIRES_ON_EXTRA_PATHS), scanned verbatim, no exemptions ---
if [[ -n "$EXTRA" ]]; then
  IFS=':' read -ra extra_arr <<<"$EXTRA"
  for p in "${extra_arr[@]}"; do
    [[ -n "$p" ]] || continue
    scan_file "$p" "$p"
  done
fi

if [[ "$config_errors" -eq 1 ]]; then
  exit 2
elif [[ "$findings" -eq 1 ]]; then
  exit 1
else
  exit 0
fi
