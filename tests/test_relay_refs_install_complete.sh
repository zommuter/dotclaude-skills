#!/usr/bin/env bash
# roadmap:69ef — every relay reference doc must be in the Makefile install manifest.
#
# WHY (audit 2026-06-23): the Makefile `relay_FILES` manifest is an EXPLICIT list, not
# a glob. `relay/references/hard-lanes.md` (added by id:78ff after the last install)
# was never added to it, so `make install-relay` does NOT symlink it into
# ~/.claude/skills/relay/references/ — the file 404s at the install path while
# gather-human-backlog.sh's error messages and references/human.md point readers to it.
# Generalize the guard: a new reference doc must never be silently left un-installed.
#
# Asserts: every `relay/references/*.md` file in the repo appears in the Makefile's
# `relay_FILES` manifest (as `references/<name>`).
#
# Hermetic: pure static read of the checked-in Makefile + references dir.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MK="$SRC_DIR/Makefile"
REFS_DIR="$SRC_DIR/relay/references"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$MK" ]]      || fail "Makefile not found at $MK"
[[ -d "$REFS_DIR" ]] || fail "relay/references dir not found at $REFS_DIR"

# Extract the line-continued `relay_FILES := ...` block from the Makefile (joins the
# backslash-continued lines into one space-separated string).
manifest="$(awk '
  /^relay_FILES[[:space:]]*:=/ { cap=1 }
  cap {
    line=$0
    cont=(line ~ /\\[[:space:]]*$/)
    sub(/\\[[:space:]]*$/, "", line)
    printf "%s ", line
    if (!cont) exit
  }
' "$MK")"
[[ -n "$manifest" ]] || fail "could not find a relay_FILES := manifest in the Makefile"

missing=0
for f in "$REFS_DIR"/*.md; do
  base="references/$(basename "$f")"
  if ! grep -qF -- "$base" <<<"$manifest"; then
    echo "FAIL: $base is NOT listed in the Makefile relay_FILES manifest (will not be installed)" >&2
    missing=1
  fi
done
[[ "$missing" -eq 0 ]] \
  || fail "one or more relay/references/*.md docs are absent from relay_FILES — add them so make install-relay symlinks them"

pass "every relay/references/*.md is present in the relay_FILES install manifest"
echo "ALL PASS: relay references install-completeness (roadmap:69ef)"
