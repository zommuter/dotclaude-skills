#!/usr/bin/env bash
# lane-convert.sh (id:4f02) — deterministic TEXT transform of the old venue-keyed
# `[HARD — <lane>]` vocabulary onto the new capability-keyed vocabulary (see
# relay/references/hard-lanes.md "North star — capability-keyed vocabulary").
#
# WHY (meeting 2026-07-02-1924 decision 2, amendment "rename mapping — [HARD — hands]
# has no auto-default"): B1 is the SAFETY-NET-FIRST half of the wave-2b lane rename.
# This converter AUTO-APPLIES only the THREE unambiguous 1:1 renames on the exact
# bracket strings — it is a plain text transform, NOT a lane-parser (it never inspects
# item semantics, just string-matches the bracket spelling):
#
#   [HARD — pool]           → [HARD]
#   [HARD — meeting]        → [INPUT — meeting]
#   [HARD — decision gate]  → [INPUT — decision]
#
# `[HARD — hands]` is NEVER auto-converted — it fragments across FOUR candidate
# destinations by per-item human judgment ([MECHANICAL] / [INPUT — access] /
# [INPUT — decision] / [INPUT — meeting]). Every `[HARD — hands]` line is LEFT
# UNCHANGED in the output and FLAGGED on stderr (file:line + id + the four
# candidates), deferring the decision to M3 (id:3ef7) / human — the converter emits
# NO default for hands.
#
# [ROUTINE] / [MECHANICAL] / [INTENSIVE — <res>] and the `🚧 route:*` auto-gate
# aliases pass through UNCHANGED.
#
# Idempotent: re-running on already-converted output is a no-op on stdout (a
# still-present `[HARD — hands]` re-flags on stderr but its text is never rewritten).
#
# Usage:
#   lane-convert.sh <ledger-file>              # converted text on stdout
#   lane-convert.sh --in-place <ledger-file>   # rewrite the file in place (B2c)
set -euo pipefail

in_place=0
if [[ "${1:-}" == "--in-place" ]]; then
  in_place=1
  shift
fi

file="${1:-}"
if [[ -z "$file" || ! -f "$file" ]]; then
  echo "lane-convert.sh: usage: lane-convert.sh [--in-place] <ledger-file>" >&2
  exit 2
fi

id_re='id:[0-9a-fA-F]{4}'

out=""
lineno=0
had_hands=0
while IFS= read -r line || [[ -n "$line" ]]; do
  lineno=$((lineno + 1))

  # [HARD — hands] is fan-out-ambiguous — NEVER auto-converted. Flag on stderr,
  # leave the line byte-for-byte unchanged.
  if [[ "$line" == *'[HARD — hands]'* ]]; then
    had_hands=1
    idtoken=""
    if [[ "$line" =~ ($id_re) ]]; then
      idtoken="${BASH_REMATCH[1]}"
    fi
    echo "lane-convert: NEEDS JUDGMENT — $file:$lineno (${idtoken:-<no id>}) [HARD — hands] fragments across four candidates — pick ONE by per-item judgment:" >&2
    echo "  [MECHANICAL] (a daemon can run it, no LLM/human) | [INPUT — access] (credential/hardware/physical) | [INPUT — decision] (human decides, no design session) | [INPUT — meeting] (needs design judgment)" >&2
    echo "  $line" >&2
  else
    # The three unambiguous 1:1 renames.
    line="${line//\[HARD — pool\]/[HARD]}"
    line="${line//\[HARD — meeting\]/[INPUT — meeting]}"
    line="${line//\[HARD — decision gate\]/[INPUT — decision]}"
  fi

  out+="${line}"$'\n'
done < "$file"

if [[ "$in_place" -eq 1 ]]; then
  printf '%s' "$out" > "$file"
else
  printf '%s' "$out"
fi

if [[ "$had_hands" -eq 1 ]]; then
  echo "lane-convert: one or more [HARD — hands] items were left unchanged — resolve them by hand (M3, id:3ef7)." >&2
fi

exit 0
