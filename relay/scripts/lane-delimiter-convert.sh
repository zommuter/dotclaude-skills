#!/usr/bin/env bash
# lane-delimiter-convert.sh (id:0ec3) -- the em-dash delimiter migration's CONVERTER.
#
# WHY IT EXISTS: `lane-delimiter-scan.sh` (id:70bc) detects the migration's completion but
# cannot perform it, and `lane-convert.sh` (id:4f02) is a VOCABULARY converter whose own
# output still emits `[INPUT — meeting]` with an em dash. Until this script there was NO
# delimiter converter anywhere -- a gap that made "just fix the em dashes" mean "hand-swap a
# delimiter", which the global CLAUDE.md forbids by name.
#
# WHAT IT CONVERTS, and nothing else: the U+2014 EM DASH inside a LIVE lane tag, to the
# target ASCII spaced hyphen:
#
#     [INPUT — <lane>]      -> [INPUT - <lane>]
#     [INTENSIVE — <res>]   -> [INTENSIVE - <res>]
#
# `[HARD — <lane>]` IS DELIBERATELY REFUSED, not converted. Its delimiter and its VOCABULARY
# are two different migrations, and swapping only the delimiter produces `[HARD - pool]` --
# still the retired venue-keyed vocabulary, which `hooks/pre-commit-lane-vocab.sh` BLOCKS on
# commit. So a delimiter-only pass over those lines yields output that cannot be committed.
# They need `lane-convert.sh` (id:4f02) FIRST, which renames `[HARD — pool]` -> `[HARD]` and
# `[HARD — meeting]` -> `[INPUT — meeting]`, and which deliberately emits NO default for
# `[HARD — hands]` because that one fragments across four destinations by human judgment.
# Such lines are reported on stderr and left untouched (measured 2026-09-09: 4 fleet-wide,
# against 638 `[INPUT —` and 14 `[INTENSIVE —` that convert cleanly).
#
# WHAT IT DELIBERATELY LEAVES ALONE:
#   * PROSE. Ledger prose legitimately QUOTES the old spelling -- including the
#     documentation explaining this very migration. Measured 2026-09-09: 656 live lane tags
#     against 11,979 raw em dashes in the same files, an 18x ratio. A blanket `sed` is
#     therefore ~18x wider than the migration and corrupts its own documentation.
#   * Em dashes used as PUNCTUATION anywhere, including on a checkbox line.
#   * Vocabulary. `[HARD - pool]` is NOT renamed to `[HARD]` here; that is `lane-convert.sh`'s
#     job and a separate decision.
#
# HOW IT DECIDES WHAT IS LIVE: it does NOT re-implement the predicate. It shells out to
# `lane-delimiter-scan.sh --live-only`, takes the LINE NUMBERS that tested predicate reports,
# and rewrites only those lines. One predicate, one place. If the scanner's notion of "live"
# changes, this follows automatically.
#
# SAFETY PROPERTIES:
#   * Idempotent -- a second run finds nothing live and is a no-op.
#   * Atomic per file (tmp + mv), so an interrupted run never leaves a half-written ledger.
#   * VERIFIES after writing: re-runs the scanner and FAILS LOUDLY (exit 3) if any live tag
#     remains, rather than reporting success it did not achieve.
#   * Refuses a file it cannot read or write, naming it (never a silent skip).
#
# READER PRE-CONDITION -- READ THIS BEFORE RUNNING IT ANYWHERE NEW: every consumer of the lane
# vocabulary must accept BOTH delimiters before any corpus is converted, or converted items go
# silently invisible (the id:d35a class). As of 2026-09-09 the relay readers carry the id:e8d4
# two-delimiter alternation and `project_manager`'s `scan.py` was fixed (id:0ec3) after it was
# found matching em-dash-only literals -- it had been out of scope for the S4/S4-batch-2/S5b
# seams, which were each scoped to `relay/scripts/*.sh`. A NEW consumer added later re-opens
# this hazard; check it before widening the corpus.
#
# Usage:
#   lane-delimiter-convert.sh [--dry-run] <ledger-file>...
#
#   --dry-run   report what WOULD change (file:line and the before/after tag), write nothing.
#
# Exit: 0 = converted (or nothing to do); 2 = usage/unreadable input; 3 = verification failed.

set -euo pipefail

SCAN="$(dirname "$0")/lane-delimiter-scan.sh"
[ -x "$SCAN" ] || { echo "lane-delimiter-convert: cannot find lane-delimiter-scan.sh next to me" >&2; exit 2; }

DRY=0
files=()
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    -*) echo "lane-delimiter-convert: unknown flag '$a'" >&2; exit 2 ;;
    *) files+=("$a") ;;
  esac
done
[ "${#files[@]}" -gt 0 ] || { echo "lane-delimiter-convert: usage: $0 [--dry-run] <ledger-file>..." >&2; exit 2; }

total_files=0
total_lines=0

for f in "${files[@]}"; do
  [ -r "$f" ] || { echo "lane-delimiter-convert: cannot read $f" >&2; exit 2; }

  # Line numbers the TESTED predicate calls live. Deduplicated: one line may carry two tags.
  mapfile -t lines < <("$SCAN" --live-only "$f" 2>/dev/null | sed -n "s|^${f}:\([0-9]\+\):.*|\1|p" | sort -un)
  [ "${#lines[@]}" -gt 0 ] || continue

  if [ "$DRY" -eq 1 ]; then
    for n in "${lines[@]}"; do
      before="$(sed -n "${n}p" "$f" | grep -oE '\[(HARD|INPUT|INTENSIVE) — [^]]*\]' | tr '\n' ' ')"
      after="$(printf '%s' "$before" | sed 's/ — / - /g')"
      printf '%s:%s: %s->  %s\n' "$f" "$n" "$before" "$after"
    done
    total_files=$((total_files+1)); total_lines=$((total_lines+${#lines[@]}))
    continue
  fi

  [ -w "$f" ] || { echo "lane-delimiter-convert: cannot write $f" >&2; exit 2; }

  # Rewrite ONLY the reported lines, and within them ONLY inside a recognized lane bracket.
  tmp="$(mktemp "${f}.ldc.XXXXXX")"
  LINES="$(printf '%s\n' "${lines[@]}" | paste -sd, -)" \
  awk -v want="$(printf '%s\n' "${lines[@]}" | paste -sd, -)" '
    BEGIN { n=split(want,a,","); for (i=1;i<=n;i++) sel[a[i]]=1 }
    {
      if (NR in sel) {
        # Bracket-scoped: only the delimiter between a recognized head and its lane word.
        # `[HARD — ` is NOT converted -- see the header: delimiter-only there produces the
        # retired venue-keyed vocabulary, which the pre-commit ratchet blocks.
        gsub(/\[INPUT — /,     "[INPUT - ")
        gsub(/\[INTENSIVE — /, "[INTENSIVE - ")
      }
      print
    }
  ' "$f" > "$tmp"

  mv -- "$tmp" "$f"
  total_files=$((total_files+1)); total_lines=$((total_lines+${#lines[@]}))

  # VERIFY: nothing this script claims to convert may remain live. `[HARD — ` is EXPECTED to
  # remain (deliberately refused above) and is reported, not counted as a failure -- but it is
  # reported LOUDLY, because a silent deferral is how a half-migration hides.
  # `|| true` on each filter: under `pipefail`, a grep that matches nothing exits 1 and would
  # abort the assignment under `set -e` -- which is precisely the all-clear case here.
  remaining="$({ "$SCAN" --live-only "$f" 2>/dev/null || true; } | { grep -vE '\[HARD — ' || true; } | wc -l)"
  if [ "$remaining" -ne 0 ]; then
    echo "lane-delimiter-convert: VERIFICATION FAILED for $f -- $remaining convertible live tag(s) remain" >&2
    "$SCAN" --live-only "$f" 2>/dev/null | grep -vE '\[HARD — ' >&2 || true
    exit 3
  fi
  deferred="$({ "$SCAN" --live-only "$f" 2>/dev/null || true; } | { grep -cE '\[HARD — ' || true; })"
  if [ "${deferred:-0}" -ne 0 ]; then
    echo "lane-delimiter-convert: $f -- $deferred [HARD — <lane>] tag(s) LEFT for lane-convert.sh (vocabulary migration first)" >&2
  fi
done

if [ "$DRY" -eq 1 ]; then
  echo "lane-delimiter-convert: DRY RUN -- would convert $total_lines line(s) across $total_files file(s)"
else
  # Deliberately says CONVERTIBLE, not "live": `[HARD — <lane>]` tags are still live and are
  # reported per-file above. A summary that claimed "0 live" while refusing tags would be the
  # same count-disagrees-with-its-label defect this session filed twice (id:95c8, id:0ec3).
  echo "lane-delimiter-convert: converted $total_lines line(s) across $total_files file(s); 0 convertible live tag(s) remain"
fi
