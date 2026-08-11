#!/usr/bin/env bash
# tracker/homonym-worksheet.sh — regenerate the cross-repo homonym ADJUDICATION worksheet
# (TODO id:e977; the decision aid for id:ca24's per-token allow-list).
#
# WHAT IT DOES
#   1. runs tracker/fleet-import.sh over the confirmed own-set STRICT (empty allow-list)
#      and READ-ONLY, capturing both the merged fleet document and validate's verdict;
#   2. feeds both to tracker/homonym-worksheet.py, which renders
#        <outdir>/homonym-worksheet.md          the evidence, per token
#        <outdir>/homonym-allowlist.draft.txt   a draft allow-list, ALL TOKENS COMMENTED
#
# READ-ONLY OVER THE FLEET. Every ledger byte is read out of an immutable commit object
# via fleet-import.sh's pinned-sha phase; no own repo is written, checked out or fetched.
# tests/test_tracker_homonym_worksheet.sh asserts this with
# tests/lib/assert-repo-unchanged.sh (id:758e), not just in this comment.
#
# IT NEVER ADJUDICATES. tracker/homonym-allowlist.txt is never written. Every token in
# the draft is prefixed `# UNCONFIRMED `, so the draft pasted verbatim into the live
# allow-list still parses as STRICT. A human accepts one token by deleting that prefix.
#
# PRIVACY — WHY THE OUTPUT DOES NOT LIVE IN THIS REPO
#   dotclaude-skills is PUBLIC. The worksheet quotes item TITLES and repo names from ~49
#   repos, most of them private. So the SCRIPT is committed and the ARTIFACT is not: the
#   default output directory is ~/.cache/relay/tracker (outside every repo), and writing
#   into a git working tree is REFUSED unless --force-in-repo is given. Regenerate it
#   whenever you need it — it is cheap (a few seconds) and always current.
#
# Usage:
#   tracker/homonym-worksheet.sh [--outdir DIR] [--fleet FILE] [--keep-fleet]
#                                [--title-chars N] [--force-in-repo] [-h|--help]
#
#   --outdir         where to write the two artifacts
#                    (default $TRACKER_WORKSHEET_DIR or ~/.cache/relay/tracker)
#   --fleet          reuse an ALREADY-EXPORTED fleet document instead of re-importing.
#                    Requires --validate-log too; for a fast re-render while iterating.
#   --validate-log   the `ledger-map.py validate` stderr that goes with --fleet
#   --keep-fleet     leave the exported fleet document in --outdir (it contains private
#                    titles too — same reason it is not committed)
#   --title-chars    truncation width for titles in the summary table (default 110)
#   --force-in-repo  permit an --outdir inside a git working tree (you are on your own)
#
# Env: RELAY_TOML, SRC_DIR (passed through to fleet-import.sh), TRACKER_WORKSHEET_DIR.
#
# Exit: 0 ok · 2 usage/missing dependency · 3 the fleet import could not be read at all.
#       A validate FAILURE is the NORMAL case here (unadjudicated homonyms are exactly
#       what this script exists to list) and is not an error.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMPORT="$SCRIPT_DIR/fleet-import.sh"
RENDER="$SCRIPT_DIR/homonym-worksheet.py"
LIVE_ALLOW="$SCRIPT_DIR/homonym-allowlist.txt"

outdir="${TRACKER_WORKSHEET_DIR:-$HOME/.cache/relay/tracker}"
fleet_in=""
validate_log_in=""
keep_fleet=0
title_chars=110
force_in_repo=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --outdir) outdir="$2"; shift 2 ;;
    --fleet) fleet_in="$2"; shift 2 ;;
    --validate-log) validate_log_in="$2"; shift 2 ;;
    --keep-fleet) keep_fleet=1; shift ;;
    --title-chars) title_chars="$2"; shift 2 ;;
    --force-in-repo) force_in_repo=1; shift ;;
    -h|--help) sed -n '2,40p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "homonym-worksheet.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

for f in "$IMPORT" "$RENDER"; do
  [[ -f "$f" ]] || { echo "homonym-worksheet.sh: missing dependency: $f" >&2; exit 2; }
done
if [[ -n "$fleet_in" && -z "$validate_log_in" ]] || [[ -z "$fleet_in" && -n "$validate_log_in" ]]; then
  echo "homonym-worksheet.sh: --fleet and --validate-log must be given together" >&2
  exit 2
fi

mkdir -p "$outdir"
# PRIVACY GUARD (see header): the artifacts quote private-repo titles, so refuse to drop
# them inside a git working tree — where they would be one `git add -A` from publication.
if [[ "$force_in_repo" -eq 0 ]]; then
  if git -C "$outdir" rev-parse --show-toplevel >/dev/null 2>&1; then
    top="$(git -C "$outdir" rev-parse --show-toplevel)"
    cat >&2 <<EOF
homonym-worksheet.sh: REFUSING to write into a git working tree.

  --outdir  $outdir
  is inside $top

  The worksheet quotes item TITLES from every own repo, most of them private, and
  dotclaude-skills is a PUBLIC repo. Write it outside a repo (the default
  ~/.cache/relay/tracker), or pass --force-in-repo if you really mean it.
EOF
    exit 2
  fi
fi

tmpdir="$(mktemp -d)"
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

fleet="$tmpdir/fleet.json"
vlog="$tmpdir/validate.err"

if [[ -n "$fleet_in" ]]; then
  cp "$fleet_in" "$fleet"
  cp "$validate_log_in" "$vlog"
else
  # STRICT by construction: an EMPTY allow-list, never $LIVE_ALLOW. The worksheet must
  # list every class-A homonym in the fleet, including ones already adjudicated — an
  # artifact that silently shrank as tokens were accepted would make an old decision
  # un-re-checkable. (homonym-worksheet.py reads $LIVE_ALLOW separately, to REPORT which
  # tokens are already accepted; it is never passed to validate from here.)
  : > "$tmpdir/empty-allow.txt"
  # --state goes to a throwaway path: this is a read-only diagnostic and must not
  # disturb the durable fleet state the real import maintains.
  rc=0
  "$IMPORT" --state "$tmpdir/throwaway-state.json" \
            --out "$fleet" --emit-unvalidated \
            --allowlist-file "$tmpdir/empty-allow.txt" \
            > "$tmpdir/import.out" 2> "$vlog" || rc=$?
  # rc 3 is the EXPECTED outcome while any homonym is unadjudicated; rc 4 means some repo
  # errored (reported, other repos still imported). Anything else, or a missing document,
  # is fatal — never render a worksheet from a fleet we could not read.
  if [[ ! -s "$fleet" ]]; then
    echo "homonym-worksheet.sh: fleet-import.sh (rc=$rc) produced no fleet document — see below" >&2
    cat "$vlog" >&2
    exit 3
  fi
  if [[ "$rc" -ne 0 && "$rc" -ne 3 && "$rc" -ne 4 ]]; then
    echo "homonym-worksheet.sh: fleet-import.sh failed unexpectedly (rc=$rc) — see below" >&2
    cat "$vlog" >&2
    exit 3
  fi
  if [[ "$rc" -eq 4 ]]; then
    echo "homonym-worksheet.sh: NOTE — fleet-import.sh reported repo errors (rc=4); the worksheet covers only the repos that imported. See the log above." >&2
  fi
fi

python3 "$RENDER" \
  --fleet "$fleet" \
  --validate-log "$vlog" \
  --allowlist "$LIVE_ALLOW" \
  --title-chars "$title_chars" \
  --out-worksheet "$outdir/homonym-worksheet.md" \
  --out-draft "$outdir/homonym-allowlist.draft.txt"

if [[ "$keep_fleet" -eq 1 ]]; then
  cp "$fleet" "$outdir/fleet.json"
  cp "$vlog" "$outdir/validate.err"
  echo "homonym-worksheet.sh: kept $outdir/fleet.json + validate.err (private titles — do not commit)" >&2
fi

echo "$outdir/homonym-worksheet.md"
echo "$outdir/homonym-allowlist.draft.txt"
