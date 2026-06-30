#!/usr/bin/env bash
# roadmap:07be
# DEFECT-FIX regression for gather-repo-state.sh's execve overflow. Found 2026-06-30 while
#  dogfooding the classifier: gather-repo-state.sh's emit() passes large field values (the
#  ROADMAP content etc.) to python3 via ENV VARS; a single env string over MAX_ARG_STRLEN
#  (128KB) breaks execve with "Argument list too long". Today real repos survive because the
#  emitted `roadmap` field is a ~94KB subset, but a repo with >128KB of ROADMAP content crashes
#  gather — and thus the whole classify-repo.sh chain. Same class as the id:3f0f wrapper fix.
#  Fix: pass large blobs to python via a temp file / stdin, never env/argv; output stays
#  byte-identical.)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
G="$ROOT/relay/scripts/gather-repo-state.sh"
[[ -x "$G" ]] || { echo "gather-repo-state.sh missing"; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export RELAY_TOML="$tmp/relay.toml"; : > "$RELAY_TOML"
export RELAY_WORKTREE_BASE="$tmp/wt"

R="$tmp/bigroadmap"; mkdir -p "$R"
git -C "$R" init -q; git -C "$R" config user.email t@e; git -C "$R" config user.name t

# A ROADMAP.md whose content well exceeds the 128KB MAX_ARG_STRLEN limit, so the value gather
# tries to hand python via an env var overflows execve.
{
  echo "# Roadmap"; echo "## Items"
  echo "- [ ] [ROUTINE] one real open item <!-- id:0001 -->"
  for i in $(seq 1 3500); do
    printf -- "  - **Why**: %s padding %04d to push the roadmap blob past MAX_ARG_STRLEN\n" \
      "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" "$i"
  done
} > "$R/ROADMAP.md"
printf '# TODO\n## Current\n' > "$R/TODO.md"
git -C "$R" add -A; git -C "$R" commit -qm init

sz=$(wc -c < "$R/ROADMAP.md")
[[ "$sz" -gt 131072 ]] || { echo "fixture ROADMAP only $sz bytes — must exceed 128KB"; exit 1; }

# gather must emit valid JSON, not die with "Argument list too long".
out="$("$G" --repo bigroadmap --path "$R" 2>"$tmp/err")" || {
  echo "gather FAILED on a large ROADMAP (the regression): $(cat "$tmp/err")"; exit 1; }
python3 -c 'import sys,json;o=json.load(sys.stdin);assert o.get("is_git") is True, o;assert "open_hard_pool" in o, o' <<<"$out" \
  || { echo "gather emitted invalid/incomplete JSON on a large ROADMAP"; exit 1; }

echo "PASS test_gather_repo_state_large"
