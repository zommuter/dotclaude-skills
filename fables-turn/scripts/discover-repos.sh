#!/usr/bin/env bash
# discover-repos.sh — classify ~/src git repos for the fables-turn relay. Read-only.
#
# Usage:
#   discover-repos.sh                — all git repos under $SRC_DIR
#   discover-repos.sh repo [repo...] — only the named repos
#
# Output (TSV, one repo per line):
#   name  path  classification  dirty  last_commit  last_ckpt_tag
#
# classification: own | clone | needs_review
#   own          — every remote points at fievel/fievel.local or
#                  github.com/zommuter, or no remote and every commit author
#                  is the user
#   clone        — only third-party remotes, clean tree
#   needs_review — mixed remotes (own fork/mirror + foreign upstream) or a
#                  dirty clone: possibly a fork the user actively works in —
#                  surface for a human call, never auto-include
# Overrides in relay.toml ([repos.<name>] classification = "...") always win.
#
# Repo list source: ~/.cache/project_manager/state.json when fresher than 24 h
# (so `proj refresh` stays the single scanner), else a glob of $SRC_DIR/*/.git.
# This script never writes state — the orchestrator updates relay.toml after
# user confirmation.
set -euo pipefail

SRC_DIR="${SRC_DIR:-$HOME/src}"
STATE_JSON="${STATE_JSON:-$HOME/.cache/project_manager/state.json}"
RELAY_TOML="${RELAY_TOML:-$HOME/.config/fables-turn/relay.toml}"

# Authors that count as "the user" for the no-remote heuristic.
OWN_AUTHOR_RE='^(Zommuter|Tobias Kienzler|Claude([ -].*)?)$'
# Remotes that count as "own infrastructure".
OWN_REMOTE_RE='(fievel(\.local)?[:/]|github\.com[:/ ]*[Zz]ommuter/)'

# --- repo list -------------------------------------------------------------
repo_paths() {
  if [[ -f "$STATE_JSON" ]] && find "$STATE_JSON" -mmin -1440 | grep -q .; then
    python3 -c '
import json, sys
for v in json.load(open(sys.argv[1])).values():
    print(v["path"])
' "$STATE_JSON"
  else
    for d in "$SRC_DIR"/*/; do
      [[ -e "$d/.git" ]] && echo "${d%/}"
    done
  fi
}

# --- relay.toml overrides: lines of "<name>\t<classification>" --------------
overrides() {
  [[ -f "$RELAY_TOML" ]] || return 0
  python3 -c '
import sys, tomllib
with open(sys.argv[1], "rb") as f:
    data = tomllib.load(f)
for name, entry in data.get("repos", {}).items():
    c = entry.get("classification")
    if c:
        print(f"{name}\t{c}")
' "$RELAY_TOML"
}

declare -A OVERRIDE
while IFS=$'\t' read -r name cls; do
  [[ -n "$name" ]] && OVERRIDE["$name"]="$cls"
done < <(overrides)

# --- per-repo classification -------------------------------------------------
classify() {
  local path="$1" name remotes dirty cls authors
  name="$(basename "$path")"

  git -C "$path" rev-parse --git-dir >/dev/null 2>&1 || return 0

  dirty=no
  [[ -n "$(git -C "$path" status --porcelain 2>/dev/null | head -1)" ]] && dirty=yes

  if [[ -n "${OVERRIDE[$name]:-}" ]]; then
    cls="${OVERRIDE[$name]}"
  else
    remotes="$(git -C "$path" remote -v 2>/dev/null || true)"
    if [[ -n "$remotes" ]]; then
      if grep -qiE "$OWN_REMOTE_RE" <<<"$remotes"; then
        if grep -viE "$OWN_REMOTE_RE" <<<"$remotes" | grep -q .; then
          cls=needs_review   # own fork/mirror + foreign upstream
        else
          cls=own
        fi
      else
        cls=clone
      fi
    else
      # No remote: own iff every commit author matches the user.
      authors="$(git -C "$path" log --format='%an' 2>/dev/null | sort -u || true)"
      if [[ -n "$authors" ]] && ! grep -qvE "$OWN_AUTHOR_RE" <<<"$authors"; then
        cls=own
      else
        cls=clone
      fi
    fi
    # A dirty clone may be a fork the user works in — surface, never auto-skip.
    [[ "$cls" == clone && "$dirty" == yes ]] && cls=needs_review
  fi

  local last_commit last_ckpt
  last_commit="$(git -C "$path" log -1 --format=%cs 2>/dev/null || echo -)"
  last_ckpt="$(git -C "$path" tag -l 'fable-ckpt-*' 2>/dev/null | sort | tail -1)"
  [[ -z "$last_ckpt" ]] && last_ckpt=-

  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$name" "$path" "$cls" "$dirty" "$last_commit" "$last_ckpt"
}

if (( $# > 0 )); then
  for name in "$@"; do
    if [[ -e "$SRC_DIR/$name/.git" ]]; then
      classify "$SRC_DIR/$name"
    else
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$SRC_DIR/$name" missing - - - >&2
    fi
  done
else
  while IFS= read -r path; do
    classify "$path"
  done < <(repo_paths)
fi
