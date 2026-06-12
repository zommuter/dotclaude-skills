#!/usr/bin/env bash
# roadmap:44ba — the γ-branch reference table in broker-mode.md must carry a
# Fable-class caveat at the table itself (footnote or blockquote): the three
# AskUserQuestion fallback rows are replaced by inline-prose numbered prompts on
# Fable-class harnesses, with a pointer to format.md §Harness-class gate.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
f="$ROOT/meeting/broker-mode.md"

# Extract only the "## γ-branch reference" section
section="$(awk '/^## γ-branch reference/{flag=1; next} /^## /{flag=0} flag' "$f")"
[[ -n "$section" ]] || { echo "γ-branch reference section not found"; exit 1; }

grep -qi 'fable' <<<"$section" \
  || { echo "no Fable mention inside the γ-branch reference section"; exit 1; }

grep -qiE 'inline[- ]prose' <<<"$section" \
  || { echo "caveat must name the inline-prose replacement for AskUserQuestion"; exit 1; }

grep -q 'format\.md' <<<"$section" \
  || { echo "caveat must point to format.md §Harness-class gate"; exit 1; }

# The caveat must reference the affected fallback construct by name
grep -q 'AskUserQuestion' <<<"$section" \
  || { echo "caveat must name AskUserQuestion (the construct it qualifies)"; exit 1; }

echo ok
