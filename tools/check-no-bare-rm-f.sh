#!/usr/bin/env bash
# check-no-bare-rm-f.sh — flag NON-recursive `rm -f` / `rm --force` in skill scripts.
#
# De-cargo-cult audit (id:373e / decision D6): the user's destructive-op guardrail
# soft-denies/prompts on `rm -f`. There is NO `rm -i` alias, so a force flag on a
# SINGLE-FILE removal is a cargo-cult fossil — it suppresses a prompt that would
# never have fired and, worse, hides a missing-file error (turning a loud bug into
# a silent no-op). The sanctioned recursive-cleanup idiom
# `trap 'rm -rf "$tmpdir"' EXIT` is EXEMPT (a directory tree genuinely needs -r,
# and -f there is the standard mktemp-cleanup pattern). This is the deterministic
# regression-guard modeled on check-no-silent-swallow.sh: it greps skill *.sh/*.py
# for a force flag whose token is NON-recursive and reports any occurrence that is
# NOT accompanied by an inline justification.
#
# A VIOLATION is a line with an `rm` invocation carrying a force flag that is
# non-recursive: a flag token containing `f` but NOT `r` (e.g. `-f`, `-vf`), or
# `--force`. Recursive forms (`rm -rf`, `rm -fr`, any flags including `r`) are
# EXEMPT. A violation is cleared if IT, or the line directly above, carries
# `# force-ok: <reason>` where <reason> is non-empty. An empty reason
# (`# force-ok:` with nothing after) still fails — the point is the reason.
#
# I/O contract:
#   check-no-bare-rm-f.sh [ROOT]
#     ROOT given  -> scan every *.sh/*.py under ROOT (a `tests/` path component is
#                    skipped: test fixtures legitimately contain the pattern text).
#     ROOT absent -> scan the known skill dirs under the repo root.
#   Default mode is ADVISORY: print a summary (files scanned, violation count,
#     sample of locations) and EXIT 0.
#   --enforce (or RM_F_BAN_ENFORCE=1): EXIT 1 when violations > BASELINE
#     (env RM_F_BAN_BASELINE, default 0).
#
# This script does not itself use a bare `rm -f` (it is the thing it checks for).
set -euo pipefail

SKILL_DIRS=(meeting git-diary-workflow todo-update meeting-cross relay projects hooks statusline tools)

ENFORCE="${RM_F_BAN_ENFORCE:-0}"
BASELINE="${RM_F_BAN_BASELINE:-0}"
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

# A violation token: `rm` (word boundary) followed by a force flag that is
# NON-recursive. The `[a-qs-z]` char classes span the lowercase alphabet MINUS
# `r`, so `-rf`/`-fr`/`-rfv`/any r-bearing flag cannot match; a non-recursive
# force flag (`-f`, `-vf`, `-fv`, …) does; `--force` matches literally.
VIOLATION_RE='\brm[[:space:]]+(-[a-qs-z]*f[a-qs-z]*([[:space:]]|$)|--force)'

# A line is annotated if IT, or the line directly above it, carries
# `# force-ok:` followed by at least one non-space character.
ANNOT_RE='#[[:space:]]*force-ok:[[:space:]]*[^[:space:]]'

total=0
samples=()

for f in "${files[@]:-}"; do
  [ -n "$f" ] || continue
  mapfile -t lines < "$f"
  n=${#lines[@]}
  for ((i = 0; i < n; i++)); do
    line="${lines[i]}"
    # Skip pure-comment lines (a `#`-leading line can't itself remove anything).
    case "${line#"${line%%[![:space:]]*}"}" in '#'*) continue ;; esac
    if printf '%s' "$line" | grep -qE "$VIOLATION_RE"; then
      # annotated on the same line?
      if printf '%s' "$line" | grep -qE "$ANNOT_RE"; then continue; fi
      # annotated on the line directly above?
      if [ "$i" -gt 0 ] && printf '%s' "${lines[i-1]}" | grep -qE "$ANNOT_RE"; then continue; fi
      total=$((total + 1))
      if [ "${#samples[@]}" -lt 15 ]; then
        samples+=("${f}:$((i + 1)): ${line#"${line%%[![:space:]]*}"}")
      fi
    fi
  done
done

echo "no-bare-rm-f check — ${#files[@]} skill script(s) scanned"
echo "  non-recursive force-flag rm violations: $total"
if [ "$total" -gt 0 ]; then
  echo "  sample (first ${#samples[@]}):"
  for s in "${samples[@]}"; do echo "    $s"; done
  echo "  fix: 'rm -- \"\$f\"' (known-present) or '[ -e \"\$f\" ] && rm -- \"\$f\"' (optional),"
  echo "       or annotate with a trailing '# force-ok: <reason>' (non-empty)."
fi

if [ "$ENFORCE" = "1" ]; then
  if [ "$total" -gt "$BASELINE" ]; then
    echo "ENFORCE: $total non-recursive force-flag rm violation(s) > baseline $BASELINE — FAIL" >&2
    exit 1
  fi
  echo "ENFORCE: within baseline ($total <= $BASELINE) — ok"
fi
exit 0
