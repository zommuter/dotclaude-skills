#!/usr/bin/env bash
# ckpt-tag.sh — atomic fables-turn checkpoint: RELAY_LOG.md entry + annotated tag.
#
# Usage:
#   ckpt-tag.sh <repo-path> -m "summary paragraph" [-l "reviewer (fable)"]
#   echo "summary paragraph" | ckpt-tag.sh <repo-path> [-l label]
#
# Under flock (.git/relay-ckpt.lock):
#   1. Ensure .gitattributes has `RELAY_LOG.md merge=union` (created before any
#      executor ever touches the log).
#   2. Append `## YYYY-MM-DD HH:MM — <label>` + the summary to RELAY_LOG.md.
#   3. Commit ONLY those two paths (safe in a dirty tree).
#   4. Annotated tag fable-ckpt-YYYYMMDD-HHMM on that commit, summary as tag
#      message; same-minute collision appends -2, -3, ...
# Prints the tag name on stdout. Pushing is the caller's job (git-lock-push.sh).
set -euo pipefail

repo="${1:?Usage: ckpt-tag.sh <repo-path> [-m summary] [-l label]}"
shift

label="reviewer"
summary=""
while getopts "m:l:" opt; do
  case "$opt" in
    m) summary="$OPTARG" ;;
    l) label="$OPTARG" ;;
    *) echo "Usage: ckpt-tag.sh <repo-path> [-m summary] [-l label]" >&2; exit 1 ;;
  esac
done
[[ -z "$summary" ]] && summary="$(cat)"
[[ -n "$summary" ]] || { echo "ckpt-tag.sh: empty summary" >&2; exit 1; }

git -C "$repo" rev-parse --git-dir >/dev/null

gitdir="$(git -C "$repo" rev-parse --absolute-git-dir)"
stamp_min="$(date +%Y%m%d-%H%M)"
stamp_human="$(date '+%Y-%m-%d %H:%M')"

(
  flock -x 9

  attrs="$repo/.gitattributes"
  if ! grep -qsE '^RELAY_LOG\.md[[:space:]]+merge=union' "$attrs" 2>/dev/null; then
    printf 'RELAY_LOG.md merge=union\n' >> "$attrs"
  fi

  log="$repo/RELAY_LOG.md"
  if [[ ! -f "$log" ]]; then
    printf '# Relay log <!-- merge=union; append-only — never edit or reorder past entries -->\n' > "$log"
  fi
  printf '\n## %s — %s\n\n%s\n' "$stamp_human" "$label" "$summary" >> "$log"

  git -C "$repo" add -- RELAY_LOG.md .gitattributes
  if ! git -C "$repo" diff --cached --quiet; then
    git -C "$repo" commit -q -m "relay: checkpoint $stamp_min ($label)" \
      -- RELAY_LOG.md .gitattributes
  fi

  tag="fable-ckpt-$stamp_min"
  n=2
  while git -C "$repo" rev-parse -q --verify "refs/tags/$tag" >/dev/null; do
    tag="fable-ckpt-$stamp_min-$n"
    (( n++ ))
  done
  git -C "$repo" tag -a "$tag" -m "$summary

$label"
  echo "$tag"
) 9>"$gitdir/relay-ckpt.lock"
