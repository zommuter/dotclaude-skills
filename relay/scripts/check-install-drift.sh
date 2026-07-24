#!/usr/bin/env bash
# check-install-drift.sh (id:c5ed, routed:35eb) — per-file-symlink install-drift guard.
#
# Skills install as PER-FILE symlinks, so a newly-added canonical script only appears
# under ~/.claude/skills/<skill>/scripts/ after a `make install-<skill>` run. Nothing
# FAILS on drift today — it surfaces only as a runtime "command not found" inside an
# agent, or (the NASTIER routed:35eb recurrence) as a SILENT `set -e` death when an
# installed script `source`s a sibling that is NOT installed: the source-not-found
# kills the script mid-run and a stdout-reading caller sees clean (a FALSE-GREEN).
#
# This guard diffs a directory of canonical scripts against its install dir AND follows
# every script's `source`/`.` lines, so it catches BOTH classes:
#   (1) DIRECT drift  — a `<canonical>/*.sh` with no same-named entry in <installed>.
#   (2) SOURCE drift  — a sibling pulled in via `source "$dir/<name>.sh"` (or `. <name>.sh`)
#       that does not resolve in <installed>, EVEN WHEN the sourcing script itself is
#       installed. This is independent of the canonical∖installed set-diff: an installed
#       script may source a sibling the plain enumeration would call green.
#
# Usage:
#   check-install-drift.sh --canonical <dir> --installed <dir>
#     --canonical <dir>  directory of canonical scripts (e.g. relay/scripts/)
#     --installed <dir>  the install dir it must be mirrored into
#                        (e.g. ~/.claude/skills/relay/scripts/)
#
# Any drift → exit non-zero, naming each missing script (basename) on stderr.
# Full parity → exit 0, clean.
#
# Read-only: never writes, never spawns a model. Roots are passed by arg, so it is
# hermetic and needs no HOME override.
set -uo pipefail

usage() { echo "usage: check-install-drift.sh --canonical <dir> --installed <dir>" >&2; exit 2; }

CANON="" INSTALLED=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --canonical)  CANON="${2:-}";     shift 2 || usage ;;
    --installed)  INSTALLED="${2:-}"; shift 2 || usage ;;
    -h|--help)    usage ;;
    *) echo "check-install-drift.sh: unknown arg: $1" >&2; usage ;;
  esac
done
[[ -n "$CANON" && -n "$INSTALLED" ]] || usage
[[ -d "$CANON" ]]     || { echo "check-install-drift.sh: --canonical not a directory: $CANON" >&2; exit 2; }
[[ -d "$INSTALLED" ]] || { echo "check-install-drift.sh: --installed not a directory: $INSTALLED" >&2; exit 2; }

# Extract the basename of every `source`/`.` target that ends in .sh from one script.
# Handles `source X` and `. X`, "$var"-quoted / '$var'-quoted / bare targets, a `$dir/`
# prefix, and skips comment lines. Prints one basename per line.
source_targets() {
  local file="$1" line directive target base
  while IFS= read -r line || [[ -n "$line" ]]; do
    # skip comment-only lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    # a source directive: `source <target>` or `. <target>` (dot must be space-followed,
    # so `./foo` and `../x` are not matched)
    if [[ "$line" =~ ^[[:space:]]*(source|\.)[[:space:]]+(.+)$ ]]; then
      target="${BASH_REMATCH[2]}"
      target="${target%%[[:space:]]*}"   # first whitespace-delimited token
      target="${target//\"/}"            # strip double quotes
      target="${target//\'/}"            # strip single quotes
      base="${target##*/}"               # basename (drops any $dir/ prefix)
      [[ "$base" == *.sh ]] || continue  # only .sh siblings are install-managed here
      printf '%s\n' "$base"
    fi
  done < "$file"
}

declare -A missing=()   # basename -> reason marker (dedupe)
shopt -s nullglob
for f in "$CANON"/*.sh; do
  [[ -e "$f" ]] || continue
  base="$(basename -- "$f")"
  # (1) DIRECT: the canonical script itself must be installed.
  [[ -e "$INSTALLED/$base" ]] || missing["$base"]=1
  # (2) SOURCE: every .sh sibling it sources must resolve in the install.
  while IFS= read -r tgt; do
    [[ -n "$tgt" ]] || continue
    [[ -e "$INSTALLED/$tgt" ]] || missing["$tgt"]=1
  done < <(source_targets "$f")
done
shopt -u nullglob

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "check-install-drift.sh: install drift — ${#missing[@]} script(s) missing from $INSTALLED:" >&2
  for base in $(printf '%s\n' "${!missing[@]}" | sort); do
    echo "  MISSING: $base" >&2
  done
  exit 1
fi

echo "check-install-drift.sh: OK — $CANON fully mirrored in $INSTALLED (scripts + source targets)"
exit 0
