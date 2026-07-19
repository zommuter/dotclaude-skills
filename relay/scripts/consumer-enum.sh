#!/usr/bin/env bash
# consumer-enum.sh (id:78df) — handoff-time spec-completeness LISTING AID.
#
# A RED spec is bounded by the consumers its author enumerated (chidiai
# `red-spec-verified-named-consumers`): if the author forgets a reader of the artifact
# the spec governs, the spec silently under-covers. This aid surfaces every file whose
# CONTENT references an artifact, so a handoff author can cross-check the consumers the
# RED spec names against the real readers.
#
# Usage:
#   consumer-enum.sh <artifact> [root]
#     <artifact>  a filename/token to search for (matched as a literal, fixed string)
#     [root]      directory to scan, default the repo toplevel (git rev-parse), excluding .git
#
# Output: one path per line (absolute, under <root>), for every file whose content references
#   <artifact>. Sorted, deduped.
#
# LISTING AID, NOT A GATE (id:78df):
#   • It never fails on "missing" consumers and never proves coverage — it only surfaces readers.
#   • A nonexistent / unreferenced artifact simply lists nothing and STILL exits 0.
#   • The artifact's own definition file (a file whose basename == <artifact>) is excluded — a
#     file is a reader of an artifact, not of itself.
#
# Read-only: never writes, never spawns a model.
set -euo pipefail

usage() { echo "usage: consumer-enum.sh <artifact> [root]" >&2; exit 2; }

ARTIFACT="${1:-}"
[[ -n "$ARTIFACT" ]] || usage
ROOT="${2:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
[[ -d "$ROOT" ]] || { echo "consumer-enum.sh: root not a directory: $ROOT" >&2; exit 2; }

BASE="$(basename -- "$ARTIFACT")"

# grep -r: recursive; -l: files-with-matches (paths only); -F: fixed literal string;
# --exclude-dir=.git: never descend into a git object store. `|| true` because grep exits 1
# on zero matches and this is an aid (exit 0), not a gate.
grep -rlF --exclude-dir=.git -e "$ARTIFACT" -- "$ROOT" 2>/dev/null \
  | { grep -vF -- "/$BASE" || true; } \
  | sort -u || true

exit 0
