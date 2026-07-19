#!/usr/bin/env bash
# relay/scripts/render-verdict.sh — display-label renderer for a classify-verdict JSON (id:ac7f)
#
# Usage: render-verdict.sh < classify-verdict.json   (JSON object on stdin)
#
# Reads ONE classify-verdict JSON object on stdin and prints a single DISPLAY LABEL:
#   verdict == "idle"  → "drained"
#   any other verdict  → the verdict string VERBATIM
#
# This is the ONLY sanctioned emitter of the word "drained" (design 2026-07-19-1152 D1):
# `drained` is a render-alias OVER `idle`, NOT a classify-verdict enum value. Once id:ac7f's
# classify-repo count change lands (an open @wire item on a primary executor lane counts
# toward actionable_routine_open), a repo with an open @wire half already yields verdict=idle
# ONLY when that half is zero — so rendering idle→"drained" is quoted from the classifier,
# never authored freehand as prose. No new cascade value is added (D1: drained would
# near-duplicate idle — drift bait).
#
# SIDE-EFFECT-FREE: reads stdin, prints one line to stdout. No git, no filesystem writes.
set -euo pipefail

verdict="$(python3 -c 'import sys, json; print(json.load(sys.stdin).get("verdict", ""))')"

if [[ "$verdict" == "idle" ]]; then
  echo "drained"
else
  echo "$verdict"
fi
