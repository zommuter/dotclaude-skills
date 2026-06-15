#!/usr/bin/env bash
# gather-human-backlog.sh — collect open human-triage backlog across relay.toml
# `classification = "own"` repos for /relay human. Read-only.
#
# Usage:
#   gather-human-backlog.sh                — all confirmed own repos in relay.toml
#   gather-human-backlog.sh repo [repo...] — only the named repos
#
# Output (TSV, one open box per line):
#   repo  path  kind  box_summary
#
# kind:
#   review_me — an open `- [ ]` box in the repo's REVIEW_ME.md
#   manual    — an open `- [ ]` box tagged `@manual` (REVIEW_ME.md or ROADMAP.md);
#               a human must RUN it, so it is NEVER auto-tickable (surface only).
#
# box_summary is the box text with the leading `- [ ] ` stripped and whitespace
# collapsed (TSV-safe: tabs/newlines become spaces). Closed `- [x]` boxes are
# never emitted. The script never writes state and never spawns a model — it is
# the read-only collector; the strong turn does the classification/answering.
#
# Repo paths come from relay.toml's `[repos.<name>]` entries with
# classification = "own", honoring an optional `path = "..."` override per repo
# (default path is $SRC_DIR/<name>). Excluded/clone repos are skipped.
set -euo pipefail

SRC_DIR="${SRC_DIR:-$HOME/src}"
RELAY_TOML="${RELAY_TOML:-$HOME/.config/fables-turn/relay.toml}"

# --- own repos from relay.toml: lines of "<name>\t<path>" -------------------
# Honors `classification = "own"` and an optional per-repo `path =` override
# (the `# path:` convention recorded as a real TOML key).
own_repos() {
  [[ -f "$RELAY_TOML" ]] || return 0
  SRC_DIR="$SRC_DIR" python3 -c '
import os, sys, tomllib
src = os.environ["SRC_DIR"]
with open(sys.argv[1], "rb") as f:
    data = tomllib.load(f)
for name, entry in data.get("repos", {}).items():
    if entry.get("classification") != "own":
        continue
    path = entry.get("path") or os.path.join(src, name)
    print(f"{name}\t{path}")
' "$RELAY_TOML"
}

# --- emit open boxes for one file --------------------------------------------
# $1 repo name, $2 repo path, $3 file path, $4 default kind (review_me|manual)
emit_boxes() {
  local name="$1" path="$2" file="$3" default_kind="$4"
  [[ -f "$file" ]] || return 0
  # Read open boxes only ('- [ ]'); classify @manual lines as kind=manual.
  while IFS= read -r line; do
    local summary kind
    # strip leading '- [ ] ' and collapse whitespace (tabs/newlines → spaces)
    summary="$(printf '%s' "$line" | tr '\t\n' '  ' | sed -E 's/^[[:space:]]*- \[ \] //; s/[[:space:]]+/ /g; s/^ //; s/ $//')"
    kind="$default_kind"
    if printf '%s' "$line" | grep -qi '@manual'; then
      kind=manual
    fi
    printf '%s\t%s\t%s\t%s\n' "$name" "$path" "$kind" "$summary"
  done < <(grep -nE '^[[:space:]]*- \[ \] ' "$file" 2>/dev/null | sed -E 's/^[0-9]+://')
}

# --- scan one repo -----------------------------------------------------------
scan_repo() {
  local name="$1" path="$2"
  [[ -d "$path" ]] || return 0
  # REVIEW_ME.md: every open box (default kind review_me; @manual upgrades to manual).
  emit_boxes "$name" "$path" "$path/REVIEW_ME.md" review_me
  # ROADMAP.md: only open boxes tagged @manual need a human to RUN them.
  if [[ -f "$path/ROADMAP.md" ]]; then
    while IFS= read -r line; do
      printf '%s' "$line" | grep -qi '@manual' || continue
      local summary
      summary="$(printf '%s' "$line" | tr '\t\n' '  ' | sed -E 's/^[[:space:]]*- \[ \] //; s/[[:space:]]+/ /g; s/^ //; s/ $//')"
      printf '%s\t%s\t%s\t%s\n' "$name" "$path" manual "$summary"
    done < <(grep -nE '^[[:space:]]*- \[ \] ' "$path/ROADMAP.md" 2>/dev/null | sed -E 's/^[0-9]+://')
  fi
}

# --- dispatch ----------------------------------------------------------------
if (( $# > 0 )); then
  # Named repos: resolve each against relay.toml's path override, else $SRC_DIR/<name>.
  declare -A PATH_OF
  while IFS=$'\t' read -r n p; do
    [[ -n "$n" ]] && PATH_OF["$n"]="$p"
  done < <(own_repos)
  for name in "$@"; do
    scan_repo "$name" "${PATH_OF[$name]:-$SRC_DIR/$name}"
  done
else
  while IFS=$'\t' read -r name path; do
    [[ -n "$name" ]] && scan_repo "$name" "$path"
  done < <(own_repos)
fi
