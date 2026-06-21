#!/usr/bin/env bash
# check-no-silent-swallow.sh — flag silent error-swallowing in skill scripts.
#
# Mechanization audit (id:4347, meeting 2026-06-21): a step that swallows a
# command's failure silently turns a loud error into a false negative (the
# id:4e14 regression: an LLM `/relay reconcile --all` sweep `2>/dev/null`'d git
# errors and reported "clean"). This is the deterministic guard: it greps skill
# *.sh/*.py for the swallow patterns and reports any occurrence that is NOT
# accompanied by an inline justification.
#
# A match is a VIOLATION unless it carries `# swallow-ok: <reason>` where <reason>
# is non-empty, on the SAME line or the line immediately above. An empty reason
# (`# swallow-ok:` with nothing after) still fails — the point is the reason.
#
# I/O contract:
#   check-no-silent-swallow.sh [ROOT]
#     ROOT given  -> scan every *.sh/*.py under ROOT (a `tests/` path component is
#                    skipped: test fixtures legitimately contain the pattern text).
#     ROOT absent -> scan the known skill dirs under the repo root.
#   Default mode is ADVISORY: print a summary (files scanned, violation count,
#     per-pattern breakdown, sample of locations) and EXIT 0. Use this to size +
#     annotate the existing corpus before flipping the gate on.
#   --enforce (or SWALLOW_BAN_ENFORCE=1): EXIT 1 when violations > BASELINE
#     (env SWALLOW_BAN_BASELINE, default 0). The documented flip path: once the
#     legitimate swallows carry `# swallow-ok:` annotations, set the baseline to 0
#     and wire `--enforce` into the suite so any NEW un-annotated swallow fails.
#
# This script does not itself swallow errors (it is the thing it checks for).
set -euo pipefail

SKILL_DIRS=(meeting git-diary-workflow todo-update meeting-cross relay projects hooks statusline tools)

ENFORCE="${SWALLOW_BAN_ENFORCE:-0}"
BASELINE="${SWALLOW_BAN_BASELINE:-0}"
ROOT=""
for arg in "$@"; do
  case "$arg" in
    --enforce) ENFORCE=1 ;;
    -*) echo "unknown flag: $arg" >&2; exit 2 ;;
    *) ROOT="$arg" ;;
  esac
done

# Collect candidate files.
files=()
if [ -n "$ROOT" ]; then
  [ -d "$ROOT" ] || { echo "no such root: $ROOT" >&2; exit 2; }
  while IFS= read -r -d '' f; do files+=("$f"); done < <(
    find "$ROOT" -type f \( -name '*.sh' -o -name '*.py' \) -not -path '*/tests/*' -print0
  )
else
  REPO_ROOT="$(git rev-parse --show-toplevel)"
  for d in "${SKILL_DIRS[@]}"; do
    [ -d "$REPO_ROOT/$d" ] || continue
    while IFS= read -r -d '' f; do files+=("$f"); done < <(
      find "$REPO_ROOT/$d" -type f \( -name '*.sh' -o -name '*.py' \) -not -path '*/tests/*' -print0
    )
  done
fi

# The swallow patterns (extended-regex), and a human label for each.
PATTERNS=('2>/dev/null' '\|\| *true' '\|\| *:')
LABELS=('2>/dev/null' '|| true' '|| :')

# A line is annotated if IT, or the line directly above it, carries
# `# swallow-ok:` followed by at least one non-space character.
ANNOT_RE='#[[:space:]]*swallow-ok:[[:space:]]*[^[:space:]]'

total=0
declare -a per_pattern=(0 0 0)
samples=()

for f in "${files[@]:-}"; do
  [ -n "$f" ] || continue
  # Read the file once into an array so we can look at the previous line.
  mapfile -t lines < "$f"
  n=${#lines[@]}
  for ((i = 0; i < n; i++)); do
    line="${lines[i]}"
    # Skip pure-comment lines (a `#`-leading line can't itself swallow).
    case "${line#"${line%%[![:space:]]*}"}" in '#'*) continue ;; esac
    for pi in 0 1 2; do
      if printf '%s' "$line" | grep -qE "${PATTERNS[pi]}"; then
        # annotated on the same line?
        if printf '%s' "$line" | grep -qE "$ANNOT_RE"; then continue; fi
        # annotated on the line directly above?
        if [ "$i" -gt 0 ] && printf '%s' "${lines[i-1]}" | grep -qE "$ANNOT_RE"; then continue; fi
        total=$((total + 1))
        per_pattern[pi]=$(( per_pattern[pi] + 1 ))
        if [ "${#samples[@]}" -lt 15 ]; then
          samples+=("${f}:$((i + 1)): ${LABELS[pi]}")
        fi
        break  # count a line once even if it matches >1 pattern
      fi
    done
  done
done

echo "no-silent-swallow check — ${#files[@]} skill script(s) scanned"
echo "  un-annotated swallows: $total"
echo "  by pattern:  2>/dev/null=${per_pattern[0]}  || true=${per_pattern[1]}  || :=${per_pattern[2]}"
if [ "$total" -gt 0 ]; then
  echo "  sample (first ${#samples[@]}):"
  for s in "${samples[@]}"; do echo "    $s"; done
  echo "  annotate a legitimate one with a trailing '# swallow-ok: <reason>' (non-empty)."
fi

if [ "$ENFORCE" = "1" ]; then
  if [ "$total" -gt "$BASELINE" ]; then
    echo "ENFORCE: $total un-annotated swallow(s) > baseline $BASELINE — FAIL" >&2
    exit 1
  fi
  echo "ENFORCE: within baseline ($total <= $BASELINE) — ok"
fi
exit 0
