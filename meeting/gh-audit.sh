#!/usr/bin/env bash
# gh-audit.sh — sibling to orphan-scan.sh, find-todos.sh
# Usage: gh-audit.sh open [<root-dir>]
#        gh-audit.sh search <query> [<root-dir>]
# open:   lists open issues + open PRs for the repo at <root-dir>.
#         Feeds the advisory orphan/past-meetings audit block.
# search: lists all-state issues + PRs matching <query> via gh native --search.
#         Feeds the surfaced-discoveries block in subject mode.
# Fail-soft: exits 0 with no stdout if no GitHub remote found, gh unavailable,
#   or gh returns an error. Never mutates any GitHub state.
# Writes one TSV log line to ~/.claude/logs/meeting-gh-audit.log per run.
set -euo pipefail

SUBCOMMAND="${1:-}"
if [[ "$SUBCOMMAND" != "open" && "$SUBCOMMAND" != "search" ]]; then
  echo "usage: gh-audit.sh open [<root>] | gh-audit.sh search <query> [<root>]" >&2
  exit 1
fi
shift

QUERY=""
if [[ "$SUBCOMMAND" == "search" ]]; then
  QUERY="${1:-}"
  [[ -z "$QUERY" ]] && { echo "gh-audit.sh search: query required" >&2; exit 1; }
  shift
fi

ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
LOG="$HOME/.claude/logs/meeting-gh-audit.log"
mkdir -p "$(dirname "$LOG")"

limit="${GH_AUDIT_LIMIT:-10}"
start_ms=$(date +%s%3N)
issues=0
prs=0
candidates=0

# --- detect GitHub remote ---
REPO=""
while IFS= read -r line; do
  url=$(echo "$line" | awk '{print $2}')
  # match https://github.com/owner/repo.git or git@github.com:owner/repo.git
  if [[ "$url" =~ github\.com[:/]([^/]+/[^/.]+)(\.git)?$ ]]; then
    REPO="${BASH_REMATCH[1]}"
    break
  fi
done < <(git -C "$ROOT" remote -v 2>/dev/null | grep '(fetch)' || true)

runtime_ms=$(( $(date +%s%3N) - start_ms ))

if [[ -z "$REPO" ]]; then
  printf '%s\t%s\tmode=%s\trepo=none\tissues=0\tprs=0\tcandidates=0\truntime_ms=%d\n' \
    "$(date -Iseconds)" "$(basename "$ROOT")" "$SUBCOMMAND" "$runtime_ms" >> "$LOG"
  exit 0
fi

# fail-soft gh availability check
if ! command -v gh &>/dev/null; then
  printf '%s\t%s\tmode=%s\trepo=%s\tissues=0\tprs=0\tcandidates=0\truntime_ms=%d\n' \
    "$(date -Iseconds)" "$(basename "$ROOT")" "$SUBCOMMAND" "$REPO" "$runtime_ms" >> "$LOG"
  exit 0
fi

output_lines=()

emit() {
  local kind="$1" number="$2" title="$3" url="$4"
  if [[ "$limit" -gt 0 && "${#output_lines[@]}" -ge "$limit" ]]; then
    return
  fi
  output_lines+=("$kind #$number  $title  $url")
}

# fetch issues
if [[ "$SUBCOMMAND" == "open" ]]; then
  state_flag="--state open"
  search_flag=""
else
  state_flag="--state all"
  search_flag="--search $(printf '%q' "$QUERY")"
fi

# gh issue list
issue_json=$(gh issue list --repo "$REPO" $state_flag ${search_flag:+--search "$QUERY"} \
  --json number,title,url --limit 100 2>/dev/null || echo "[]")
while IFS= read -r item; do
  num=$(echo "$item" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['number'])")
  title=$(echo "$item" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['title'])")
  url=$(echo "$item" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['url'])")
  emit "issue" "$num" "$title" "$url"
  (( issues++ )) || true
done < <(echo "$issue_json" | python3 -c "
import sys, json
for item in json.load(sys.stdin):
    print(json.dumps(item))
" 2>/dev/null || true)

# gh pr list
pr_json=$(gh pr list --repo "$REPO" $state_flag ${search_flag:+--search "$QUERY"} \
  --json number,title,url --limit 100 2>/dev/null || echo "[]")
while IFS= read -r item; do
  num=$(echo "$item" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['number'])")
  title=$(echo "$item" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['title'])")
  url=$(echo "$item" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['url'])")
  emit "pr" "$num" "$title" "$url"
  (( prs++ )) || true
done < <(echo "$pr_json" | python3 -c "
import sys, json
for item in json.load(sys.stdin):
    print(json.dumps(item))
" 2>/dev/null || true)

candidates="${#output_lines[@]}"
total=$(( issues + prs ))

for line in "${output_lines[@]}"; do
  printf '%s\n' "$line"
done

suppressed=$(( total - candidates ))
if [[ "$limit" -gt 0 && "$suppressed" -gt 0 ]]; then
  echo "# gh-audit: $suppressed more items suppressed (cap=$limit); set GH_AUDIT_LIMIT=0 for full output"
fi

runtime_ms=$(( $(date +%s%3N) - start_ms ))
printf '%s\t%s\tmode=%s\trepo=%s\tissues=%d\tprs=%d\tcandidates=%d\truntime_ms=%d\n' \
  "$(date -Iseconds)" "$(basename "$ROOT")" "$SUBCOMMAND" "$REPO" "$issues" "$prs" "$candidates" "$runtime_ms" \
  >> "$LOG"
