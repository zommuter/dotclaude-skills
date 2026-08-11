#!/usr/bin/env bash
# relay/scripts/validate-flags.sh — shared arg-guard for /meeting and /relay setup
# (roadmap id:7681, design docs/meeting-notes/2026-07-20-2304-fabled-meeting-flow-and-unknown-switch-guard.md D1/D2).
#
# Usage:
#   validate-flags.sh <skill> -- <args...>               runtime guard: prints CLEANED
#                                                          args to stdout, warns/escalates
#                                                          to stderr. <skill> in {meeting,relay}.
#   validate-flags.sh <skill> --coverage <skill-md-path>  drift guard: exit 0 iff every
#                                                          invocation flag documented in
#                                                          <skill-md-path> is present in
#                                                          that skill's manifest.
#
# Runtime guard behaviour:
#   - Non-dash tokens (subject content) always pass through untouched.
#   - A KNOWN leading-dash flag (per known-flags-<skill>.tsv) passes through unchanged;
#     if its manifest entry is arity=1 ("takes a value"), the FOLLOWING token is treated
#     as that flag's value and preserved verbatim even if it itself starts with a dash
#     (e.g. `--exclude -x` — `-x` is the value, not an unknown flag).
#   - An UNKNOWN leading-dash flag within edit-distance <=2 of a MODE-CHANGING flag
#     (--afk / --cross / --fabled / -d) is a near-miss: it ESCALATES (non-zero exit,
#     reserved exit 2) instead of silently warning-and-dropping, naming the suspected
#     flag on stderr, so the caller can ask/abort rather than silently mis-route a typo'd
#     mode switch.
#   - Any OTHER unknown leading-dash flag: LOUD warning to stderr naming the flag and
#     LISTING the skill's known flags (a required displayed artifact), then DROPS it
#     (never folded into the subject) and proceeds (exit 0).
#
# Manifests are plain TSV: `<flag><TAB><takes_value 0|1>`, one per skill, co-located in
# this directory (known-flags-meeting.tsv / known-flags-relay.tsv) — see REVIEW_ME.md
# id:7681 for the --coverage grep-scoping rationale (the one real judgment call here).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Mode-changing flags a near-miss escalates toward (D2 — deliberately NOT every unknown).
MODE_FLAGS=(--afk --cross --fabled -d)
# Scope-changing flags (id:f475): dropping these silently can invert the run's
# scope just as badly as a mode mis-route (e.g. `--except` typo'd for `--exclude`
# leaves its value as a bare positional, which reads as `--only <repo>` — the
# exact inverse of "every repo but this one"). A near-miss of one of these
# escalates exactly like a MODE_FLAGS near-miss.
SCOPE_FLAGS=(--exclude --only --priority)
ESCALATE_FLAGS=("${MODE_FLAGS[@]}" "${SCOPE_FLAGS[@]}")

usage() {
  echo "usage: validate-flags.sh <skill> -- <args...>" >&2
  echo "       validate-flags.sh <skill> --coverage <skill-md-path>" >&2
  exit 64
}

[[ $# -ge 1 ]] || usage
skill="$1"; shift

case "$skill" in
  meeting|relay) : ;;
  *) echo "validate-flags.sh: unknown skill '$skill' (expected meeting|relay)" >&2; exit 64 ;;
esac

MANIFEST="$SCRIPT_DIR/known-flags-${skill}.tsv"
[[ -f "$MANIFEST" ]] || { echo "validate-flags.sh: manifest not found: $MANIFEST" >&2; exit 64; }

# --- load manifest: flag<TAB>takes_value(0|1); skip blank/# lines ---
declare -A KNOWN_ARITY=()
while IFS=$'\t' read -r flag arity; do
  [[ -z "$flag" || "$flag" == \#* ]] && continue
  KNOWN_ARITY["$flag"]="$arity"
done < "$MANIFEST"

known_flags_list() {
  local IFS=' '
  echo "${!KNOWN_ARITY[*]}"
}

# --- Levenshtein edit distance (small strings; plain bash DP) ---
edit_distance() {
  local a="$1" b="$2"
  local la=${#a} lb=${#b}
  local -a prev cur
  local i j cost del ins sub m
  for ((j = 0; j <= lb; j++)); do prev[j]=$j; done
  for ((i = 1; i <= la; i++)); do
    cur[0]=$i
    for ((j = 1; j <= lb; j++)); do
      if [[ "${a:i-1:1}" == "${b:j-1:1}" ]]; then cost=0; else cost=1; fi
      del=$((prev[j] + 1))
      ins=$((cur[j-1] + 1))
      sub=$((prev[j-1] + cost))
      m=$del
      (( ins < m )) && m=$ins
      (( sub < m )) && m=$sub
      cur[j]=$m
    done
    for ((j = 0; j <= lb; j++)); do prev[j]=${cur[j]}; done
  done
  echo "${prev[lb]}"
}

# nearest_escalate_flag <token> — prints the nearest ESCALATE_FLAGS entry (mode-
# or scope-changing) if within its per-flag edit-distance threshold, else prints
# nothing. Threshold scales with the candidate's length (min 2): a short flag
# like `--afk` keeps the original tight <=2 near-miss window, while a longer
# flag like `--exclude` allows a plausible whole-word misspelling (id:f475 —
# `--except` for `--exclude` is edit-distance 4, not 2 as first estimated) without
# opening the gate to unrelated far-off tokens (id:f475 test 6: --qqqqzzzz stays
# well outside even the widened threshold for every candidate).
nearest_escalate_flag() {
  local tok="$1" best="" bestd=999 d f thresh
  for f in "${ESCALATE_FLAGS[@]}"; do
    d=$(edit_distance "$tok" "$f")
    thresh=$(( ${#f} / 2 ))
    (( thresh < 2 )) && thresh=2
    if (( d <= thresh && d < bestd )); then bestd=$d; best=$f; fi
  done
  if [[ -n "$best" ]]; then
    echo "$best"
  fi
}

# =========================== --coverage mode ===========================
if [[ "${1:-}" == "--coverage" ]]; then
  skillmd="${2:-}"
  [[ -n "$skillmd" && -f "$skillmd" ]] || { echo "validate-flags.sh --coverage: SKILL.md path required and must exist" >&2; exit 64; }

  scoped=""
  case "$skill" in
    relay)
      # Region 1: the "Invocation:" fence — the top-level launch syntax. EXCLUDE
      # the inject/stop lines: their bracketed tokens (--item/--verdict/--prompt,
      # --now) are SUBCOMMAND-owned arguments, not top-level guard flags (see
      # REVIEW_ME id:7681 — a naive whole-fence grep pulls these in and is
      # unsatisfiable against the pinned manifest).
      fence="$(awk '/^Invocation:/{f=1; next} f && /^```/{c++; if (c == 2) exit; next} f && c == 1' "$skillmd" \
        | grep -v -E '/relay (inject|stop)\b')"
      # Region 2: the "## Configuration knobs" table, FIRST column only — the
      # Effect/description prose column mentions unrelated flags in passing text
      # (e.g. "`--exclude`-everything-else workaround") and must NOT be scanned,
      # or the manifest would need to bloat with flags mentioned only in prose.
      table_col1="$(awk '/^## Configuration knobs/{f=1; next} f && /^## /{exit} f && /^\|/{print}' "$skillmd" \
        | awk -F'|' '{print $2}')"
      scoped="$fence
$table_col1"
      ;;
    meeting)
      # meeting/SKILL.md has no formal invocation fence; its invocation flags are
      # documented inline, at the exact point the skill argument itself is
      # inspected (today just --cross; --fabled will land the same way per
      # id:7e87, gated-on 7681). Scoping to this marker avoids the dozens of
      # helper-script prose flags (--mode, --apply, --query, --reverse, …) a
      # naive whole-file grep would pull in (see REVIEW_ME id:7681).
      scoped="$(grep -i "skill argument" "$skillmd")"
      ;;
  esac

  # Extract long (--foo) and short (-x) dash tokens from the scoped text only.
  found="$(echo "$scoped" | grep -oE -- '--[a-zA-Z][a-zA-Z0-9-]*|(^|[^a-zA-Z0-9_-])-[a-zA-Z]([^a-zA-Z0-9_-]|$)' \
    | grep -oE -- '--[a-zA-Z][a-zA-Z0-9-]*|-[a-zA-Z]' | sort -u)"

  missing=""
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    if [[ -z "${KNOWN_ARITY[$f]+x}" ]]; then
      missing="$missing $f"
    fi
  done <<< "$found"

  if [[ -n "$missing" ]]; then
    echo "validate-flags.sh --coverage: $skill manifest ($MANIFEST) is missing:$missing (documented as an invocation flag in $skillmd)" >&2
    exit 1
  fi
  exit 0
fi

# =========================== runtime guard mode ===========================
if [[ "${1:-}" != "--" ]]; then
  usage
fi
shift  # consume the -- separator

out=()
skip_next_as_value=0
escalated=0

args=("$@")
nargs=${#args[@]}
i=0
while (( i < nargs )); do
  tok="${args[$i]}"

  if [[ "$skip_next_as_value" -eq 1 ]]; then
    out+=("$tok")
    skip_next_as_value=0
    (( i++ ))
    continue
  fi

  if [[ "$tok" != -* ]]; then
    out+=("$tok")
    (( i++ ))
    continue
  fi

  # id:2047: split a `--flag=value` token into (`--flag`, `value`) BEFORE the
  # known-flag lookup, for any arity-1 manifest flag — the whole-token lookup
  # below never matches a token containing `=`, so an explicit `--quota-7d=45`
  # silently fell through to the unknown-flag path and got dropped, quietly
  # loosening a deliberately-tightened cap back to the default. Split on the
  # FIRST `=` only, so a value that itself contains `=` (`--exclude=a=b`)
  # survives intact. An arity-0 flag written with `=` (`--afk=1`) is a real
  # error, not a silent drop — surface it and stop, exactly like a near-miss
  # escalation, rather than let it fall through to the unknown-flag warn+drop.
  if [[ "$tok" == *=* ]]; then
    flagpart="${tok%%=*}"
    valpart="${tok#*=}"
    if [[ -n "${KNOWN_ARITY[$flagpart]+x}" ]]; then
      if [[ "${KNOWN_ARITY[$flagpart]}" == "1" ]]; then
        out+=("$flagpart" "$valpart")
        (( i++ ))
        continue
      else
        echo "validate-flags.sh: '$tok' — '$flagpart' takes no value (arity 0) and cannot be written with '=' for skill '$skill'." >&2
        exit 2
      fi
    fi
  fi

  if [[ -n "${KNOWN_ARITY[$tok]+x}" ]]; then
    out+=("$tok")
    [[ "${KNOWN_ARITY[$tok]}" == "1" ]] && skip_next_as_value=1
    (( i++ ))
    continue
  fi

  # unknown leading-dash token
  suspect="$(nearest_escalate_flag "$tok")"
  if [[ -n "$suspect" ]]; then
    echo "validate-flags.sh: '$tok' is a near-miss of the mode/scope-changing flag '$suspect' for skill '$skill' — escalating instead of silently dropping. Confirm intent (did you mean '$suspect'?)." >&2
    escalated=1
    break
  fi

  echo "validate-flags.sh: unknown flag '$tok' for skill '$skill' — warning and dropping it, proceeding. Known flags: $(known_flags_list)" >&2
  # dropped: intentionally NOT appended to out, and NOT folded into subject text.
  (( i++ ))

  # id:f475: a dropped unknown flag's presumed VALUE must not leak through as a
  # bare positional (that is how `--except <repo>` silently became `--only
  # <repo>` — the exact inverse of the intended scope). If the next token does
  # NOT itself start with `-`, it is the dropped flag's presumed value: drop it
  # too, rather than emitting it as a standalone positional.
  if (( i < nargs )) && [[ "${args[$i]}" != -* ]]; then
    echo "validate-flags.sh: also dropping '${args[$i]}' — presumed value of the dropped unknown flag '$tok' (would otherwise leak as a bare positional and silently change scope)." >&2
    (( i++ ))
  fi
done

if [[ "$escalated" -eq 1 ]]; then
  exit 2
fi

echo "${out[*]}"
exit 0
