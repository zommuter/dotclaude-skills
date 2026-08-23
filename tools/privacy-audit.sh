#!/usr/bin/env bash
# privacy-audit.sh — TREE-scoped privacy audit (id:9bfc part (a)).
#
# The pre-push gate (hooks/pre-push-privacy-gate.sh) scans the pushed DIFF. That is correct
# for a pre-push hook and useless for answering "what is ALREADY exposed": a line published
# in an earlier push never appears in a later diff, so the gate reports 1 finding for a repo
# carrying dozens. This walks the whole tracked TREE instead.
#
# TWO deliberate differences from the gate, both learned the hard way (2026-08-23):
#
#   1. It does NOT print the matched pattern by default. The gate reports `pattern<TOKEN>`
#      with the private pattern spelled out, so pasting gate output into a tracked file in a
#      PUBLIC repo publishes the very string the pattern file exists to protect. That is not
#      hypothetical — it happened, in the ledger item about this defect. Patterns are shown
#      as `#<n>` (their index in the pattern file). `--show-patterns` opts in, for terminal
#      use only; never redirect that into a tracked file. The RESOLVED report — pattern
#      verbatim, counts, files — is written to a PRIVATE log outside any repo
#      (~/.claude/logs/privacy-audit.log, same convention as the gate's own log), so the
#      index is always resolvable without the terminal output carrying the secret.
#   2. It enumerates files via `git ls-files`, NOT a filesystem walk — `.claude/worktrees/`
#      holds other branches' checkouts and would poison the counts (the id:b818 class).
#
# Usage:
#   tools/privacy-audit.sh                      # audit the working tree's tracked files
#   tools/privacy-audit.sh --rev <rev>          # audit a committed tree instead
#   tools/privacy-audit.sh --skip <ERE>         # ignore patterns matching this (repeatable)
#   tools/privacy-audit.sh --show-patterns      # print patterns verbatim (terminal ONLY)
#   tools/privacy-audit.sh --files              # list matching files per pattern
#   tools/privacy-audit.sh --no-log             # suppress the private resolved log
#   tools/privacy-audit.sh --lint-patterns      # audit the PATTERN FILE itself, scan nothing
#   PRIVACY_AUDIT_LOG=<path>                    # override the private log location
#
# PATTERN-AUTHORING RULE (id:9bfc part (b)) — enforced by --lint-patterns:
#   A SHORT, UNANCHORED literal pattern matches inside longer words and buries the real hits
#   in noise. That is not theoretical: a 3-character name pattern matched inside a common
#   English word 63 times with ZERO standalone occurrences, and on 2026-08-22 that noise
#   camouflaged a genuine hit on the very line that documented the noise. Anchor short
#   literals with \b (`\bFoo\b`), or make them specific enough not to collide.
#   The pattern file is PRIVATE and never committed, so this is an authoring rule plus a
#   lint over whatever file is loaded — not a committed pattern edit.
#
# To resolve an index: read the private log (`tail ~/.claude/logs/privacy-audit.log`), or
# re-run with --show-patterns. Never paste either into a tracked file.
#
# Exit: 0 = no findings, 1 = findings, 2 = usage/setup error.
set -euo pipefail

PATTERNS_FILE="${PRIVACY_GATE_PATTERNS:-${XDG_CONFIG_HOME:-$HOME/.config}/dotclaude-skills/privacy-patterns.txt}"
REV=""
SHOW_PATTERNS=0
SHOW_FILES=0
DO_LOG=1
LINT_ONLY=0
META_ONLY=0
META_RANGE="HEAD"
AUDIT_LOG="${PRIVACY_AUDIT_LOG:-$HOME/.claude/logs/privacy-audit.log}"
SKIPS=()

# A literal shorter than this, with no \b anchor and no regex metacharacter to make it
# specific, is treated as collision-prone by --lint-patterns.
PRIVACY_AUDIT_SHORT_LEN="${PRIVACY_AUDIT_SHORT_LEN:-6}"

# lint_patterns <pattern-file> — prints one line per collision-prone pattern (INDEX ONLY,
# never the pattern) and returns 1 if any were found. Split out so the test suite can drive
# it over a SYNTHETIC pattern file; the real one is private and never committed.
lint_patterns() {
  local pf="$1" i=0 bad=0 p
  while IFS= read -r p; do
    i=$((i + 1))
    [ -z "$p" ] && continue
    # Anchored already? \b at either end, or a ^/$ anchor.
    case "$p" in
      *'\b'*|'^'*|*'$') continue ;;
    esac
    # Contains regex metacharacters that make it specific enough (classes, quantifiers,
    # alternation, escapes like \. — a bare literal has none of these).
    if printf '%s' "$p" | grep -qE '[][(){}|+*?\\]'; then continue; fi
    if [ "${#p}" -lt "$PRIVACY_AUDIT_SHORT_LEN" ]; then
      printf 'pattern #%d: SHORT (%d chars) and UNANCHORED — will match inside longer words; anchor it with \\b\n' \
        "$i" "${#p}"
      bad=$((bad + 1))
    fi
  done < "$pf"
  [ "$bad" -eq 0 ]
}

# Driven by the test suite: lint a given file and exit, scanning nothing.
if [ "${PRIVACY_AUDIT_LINT_SELFTEST:-}" != "" ]; then
  lint_patterns "$PRIVACY_AUDIT_LINT_SELFTEST"
  exit $?
fi

while [ $# -gt 0 ]; do
  case "$1" in
    --rev) REV="${2:?--rev needs a revision}"; shift 2 ;;
    --skip) SKIPS+=("${2:?--skip needs an ERE}"); shift 2 ;;
    --show-patterns) SHOW_PATTERNS=1; shift ;;
    --files) SHOW_FILES=1; shift ;;
    --no-log) DO_LOG=0; shift ;;
    --lint-patterns) LINT_ONLY=1; shift ;;
    --metadata) META_ONLY=1; META_RANGE="${2:-HEAD}"; [ $# -ge 2 ] && shift 2 || shift ;;
    -h|--help) sed -n '2,28p' "$0"; exit 0 ;;
    *) echo "privacy-audit: unknown arg: $1" >&2; exit 2 ;;
  esac
done

[ -r "$PATTERNS_FILE" ] || { echo "privacy-audit: no pattern file at $PATTERNS_FILE" >&2; exit 2; }
root=$(git rev-parse --show-toplevel) || exit 2
cd "$root"

tmp=$(mktemp -d); trap 'rm -rf -- "$tmp"' EXIT

# The resolved log carries the private patterns verbatim, so REFUSE to write it anywhere git
# could COMMIT it — that is the exact mistake this tool exists to stop. Being inside a repo is
# fine if the path is ignored (the default ~/.claude/logs/ is: `logs/` is in that repo's
# .gitignore, same as the gate's own log); being inside a repo UNIGNORED is not.
if [ "$DO_LOG" -eq 1 ]; then
  mkdir -p -- "$(dirname -- "$AUDIT_LOG")" 2>/dev/null || true
  _logdir=$(dirname -- "$AUDIT_LOG")
  if git -C "$_logdir" rev-parse --show-toplevel >/dev/null 2>&1 \
     && ! git -C "$_logdir" check-ignore -q "$AUDIT_LOG" 2>/dev/null; then
    echo "privacy-audit: REFUSING to write the resolved log to a path git could commit: $AUDIT_LOG" >&2
    echo "privacy-audit: it is inside a repo and NOT gitignored. Set PRIVACY_AUDIT_LOG to an" >&2
    echo "privacy-audit: ignored or outside-repo path, add it to .gitignore, or pass --no-log." >&2
    exit 2
  fi
  printf '=== %s  repo=%s  rev=%s\n' \
    "$(date -u +%Y%m%dT%H%M%SZ)" "$root" "${REV:-<working tree>}" >> "$AUDIT_LOG"
fi

# Pattern list: strip comments/blanks and the `private-host:` directives, which are consumed
# by relay/scripts/lib-private-remote.sh and are NOT content patterns.
grep -vE '^[[:space:]]*(#|$)' "$PATTERNS_FILE" | grep -vE '^[[:space:]]*private-host:' > "$tmp/pats" || true
[ -s "$tmp/pats" ] || { echo "privacy-audit: pattern file has no content patterns" >&2; exit 2; }

# --- metadata scope -----------------------------------------------------------------------
# File content is NOT the whole repo. Commit MESSAGES and author/committer IDENTITY are
# published too, and neither the pre-push gate nor the tree scan above can see them. That is
# not a hypothetical gap: a tree scan of this repo reported 2 occurrences of a private domain
# while 975 commit messages carried it, and the author identity — invisible to both — carried
# a personal address on every one of 3608 commits.
if [ "$META_ONLY" -eq 1 ]; then
  git rev-parse --verify -q "$META_RANGE" >/dev/null 2>&1 || \
    { echo "privacy-audit: bad rev/range: $META_RANGE" >&2; exit 2; }
  git log --format='%an%n%ae%n%cn%n%ce' "$META_RANGE" > "$tmp/ident" 2>/dev/null || true
  git log --format='%B' "$META_RANGE" > "$tmp/msgs" 2>/dev/null || true
  ncommits=$(git rev-list --count "$META_RANGE" 2>/dev/null || echo 0)
  echo "privacy-audit: metadata scope — $ncommits commit(s) in '$META_RANGE'"

  echo "distinct author/committer identities:"
  sort -u "$tmp/ident" | sed 's/^/      /'

  meta_hits=0; i=0
  while IFS= read -r pat; do
    i=$((i + 1))
    ni=$(grep -cE -e "$pat" "$tmp/ident" 2>/dev/null || true)
    nm=$(grep -cE -e "$pat" "$tmp/msgs" 2>/dev/null || true)
    [ "${ni:-0}" -eq 0 ] && [ "${nm:-0}" -eq 0 ] && continue
    meta_hits=$((meta_hits + ni + nm))
    printf '#%-6s identity-field lines: %-6d commit-message lines: %d\n' "$i" "${ni:-0}" "${nm:-0}"
    [ "$DO_LOG" -eq 1 ] && printf '#%d\tMETADATA ident=%d msg=%d\tpattern=%s\n' \
      "$i" "${ni:-0}" "${nm:-0}" "$pat" >> "$AUDIT_LOG"
  done < "$tmp/pats"

  echo "---"
  if [ "$meta_hits" -eq 0 ]; then echo "privacy-audit: metadata clean"; exit 0; fi
  echo "privacy-audit: $meta_hits metadata hit(s). NOTE: identity is fixable going forward with"
  echo "\`git config user.email\`, but existing commits change only via a full-history rewrite."
  exit 1
fi

if [ "$LINT_ONLY" -eq 1 ]; then
  if lint_patterns "$tmp/pats"; then
    echo "privacy-audit: all patterns are anchored or specific enough"
    exit 0
  fi
  echo "---"
  echo "Anchor these with \\b. An unanchored short literal buries real hits in substring noise"
  echo "(id:9bfc): that is how a genuine leak went unnoticed on 2026-08-22."
  exit 1
fi

# File list — tracked paths only.
if [ -n "$REV" ]; then
  git ls-tree -r --name-only -z "$REV" > "$tmp/files"
else
  git ls-files -z > "$tmp/files"
fi

total_findings=0
total_files_flagged=0
idx=0
while IFS= read -r pat; do
  idx=$((idx + 1))
  skip=0
  for s in ${SKIPS+"${SKIPS[@]}"}; do
    # herestring, not a pipe: `grep -q` exits at the first match and would SIGPIPE a
    # producer under `pipefail` (id:81d5 lint).
    if grep -qE -- "$s" <<<"$pat"; then skip=1; break; fi
  done
  [ "$skip" -eq 1 ] && continue

  : > "$tmp/hits"
  while IFS= read -r -d '' f; do
    if [ -n "$REV" ]; then
      content=$(git show "$REV:$f" 2>/dev/null) || continue
    else
      [ -f "$f" ] || continue
      content=$(cat -- "$f" 2>/dev/null) || continue
    fi
    n=$(printf '%s\n' "$content" | grep -cE -e "$pat" 2>/dev/null || true)
    [ "${n:-0}" -gt 0 ] && printf '%s\t%s\n' "$n" "$f" >> "$tmp/hits"
  done < "$tmp/files"

  [ -s "$tmp/hits" ] || continue
  occ=$(awk -F'\t' '{s+=$1} END{print s+0}' "$tmp/hits")
  nf=$(wc -l < "$tmp/hits")
  total_findings=$((total_findings + occ))
  total_files_flagged=$((total_files_flagged + nf))

  label="#$idx"
  [ "$SHOW_PATTERNS" -eq 1 ] && label="#$idx  $pat"
  printf '%-28s %5d occurrence(s) in %d file(s)\n' "$label" "$occ" "$nf"
  if [ "$SHOW_FILES" -eq 1 ]; then
    # capture-then-slice: `head` must not be the direct consumer of a pipe (id:81d5 lint).
    _sorted=$(sort -t"$(printf '\t')" -k1,1nr "$tmp/hits")
    head -20 <<<"$_sorted" | sed 's/^/      /'
  fi
  if [ "$DO_LOG" -eq 1 ]; then
    { printf '#%d\t%d occurrence(s) in %d file(s)\tpattern=%s\n' "$idx" "$occ" "$nf" "$pat"
      sort -t"$(printf '\t')" -k1,1nr "$tmp/hits" | sed 's/^/\t/'
    } >> "$AUDIT_LOG"
  fi
done < "$tmp/pats"

echo "---"
if [ "$total_findings" -eq 0 ]; then
  echo "privacy-audit: clean (${REV:-working tree})"
  exit 0
fi
echo "privacy-audit: $total_findings occurrence(s) across $total_files_flagged file-hits (${REV:-working tree})"
if [ "$DO_LOG" -eq 1 ]; then
  echo "Resolve indices from the PRIVATE log (never paste it into a tracked file): $AUDIT_LOG"
else
  echo "Pattern indices refer to $PATTERNS_FILE; re-run with --show-patterns in a TERMINAL to resolve them."
fi
exit 1
