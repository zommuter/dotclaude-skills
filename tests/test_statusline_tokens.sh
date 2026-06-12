#!/usr/bin/env bash
# roadmap:2520 — statusline shows the session token total in the context
# segment as <pct>%(<tokens>), tokens humanized (115000 → 115k, 9500 → 9.5k,
# 730 → 730). No new network calls; must work with HOME at an empty temp dir.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/statusline/statusline-command.sh"
FIXTURE="$ROOT/tests/fixtures/statusline-input.json"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

strip_ansi() { sed -e 's/\x1b\[[0-9;]*m//g'; }

# Fixture: 110000 input + 5000 output = 115000 tokens of 200000 → 58%(115k)
out="$(HOME="$tmp" bash "$SCRIPT" < "$FIXTURE")" || { echo "statusline script failed"; exit 1; }
line1="$(head -1 <<<"$out" | strip_ansi)"

grep -qF '58%(115k)' <<<"$line1" \
  || { echo "expected context segment '58%(115k)' in: $line1"; exit 1; }

# Sub-10k value gets one decimal: 6000+3500=9500 → 9.5k (context 4.75% → 5%)
jq '.context_window.total_input_tokens = 6000 | .context_window.total_output_tokens = 3500' \
  "$FIXTURE" > "$tmp/mid.json"
line1b="$(HOME="$tmp" bash "$SCRIPT" < "$tmp/mid.json" | head -1 | strip_ansi)"
grep -qF '(9.5k)' <<<"$line1b" \
  || { echo "expected '(9.5k)' for 9500 tokens in: $line1b"; exit 1; }

# Sub-1000 value stays plain
jq '.context_window.total_input_tokens = 500 | .context_window.total_output_tokens = 230' \
  "$FIXTURE" > "$tmp/small.json"
line1c="$(HOME="$tmp" bash "$SCRIPT" < "$tmp/small.json" | head -1 | strip_ansi)"
grep -qF '(730)' <<<"$line1c" \
  || { echo "expected '(730)' for 730 tokens in: $line1c"; exit 1; }

echo ok
