#!/usr/bin/env bash
# roadmap:78df
# RED spec (authored by /relay handoff 2026-07-19, apex) for id:78df — the spec-completeness
# handoff consumer-enumeration aid (af48 child C4). Origin: chidiai
# `red-spec-verified-named-consumers` — a RED spec is bounded by the consumers its author
# enumerated, so surface every reader of the artifact the spec governs.
#
# Contract under test — a NEW relay/scripts/consumer-enum.sh:
#   consumer-enum.sh <artifact> [root]
#   lists (one path per line, exit 0) every file under [root] (default the repo toplevel,
#   excluding .git) whose CONTENT references <artifact>. It is a LISTING AID, NOT A GATE:
#   it never fails on "missing" consumers; a nonexistent artifact simply lists nothing and
#   still exits 0.
#
# EXPECTED-RED while roadmap:78df is unticked. consumer-enum.sh does not exist yet.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CE="$ROOT/relay/scripts/consumer-enum.sh"
[[ -x "$CE" ]] || { echo "consumer-enum.sh missing (RED): $CE"; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# Fixture tree: 3 readers of `edges.json`, 1 non-reader. (git dir present to prove exclusion.)
mkdir -p "$tmp/.git" "$tmp/sub"
printf 'loads and reads edges.json at startup\n'      > "$tmp/reader1.sh"
printf "with open('edges.json') as f: pass\n"          > "$tmp/sub/reader2.py"
printf 'The edges.json contract is locked.\n'          > "$tmp/doc.md"
printf 'nothing relevant here\n'                       > "$tmp/unrelated.txt"
printf 'edges.json appears in a stray git object\n'    > "$tmp/.git/OBJ"  # must be excluded

# --- listing: exactly the 3 readers, .git excluded, exit 0 --------------------------------
out="$("$CE" edges.json "$tmp")" || { echo "FAIL: consumer-enum must exit 0 as a listing aid"; exit 1; }
n="$(printf '%s\n' "$out" | grep -c . || true)"
[[ "$n" -eq 3 ]] || { echo "FAIL: expected 3 readers of edges.json, listed $n:"; printf '%s\n' "$out"; exit 1; }
for want in reader1.sh reader2.py doc.md; do
  printf '%s\n' "$out" | grep -q "$want" || { echo "FAIL: reader '$want' missing from the enumeration"; exit 1; }
done
printf '%s\n' "$out" | grep -q 'unrelated.txt' && { echo "FAIL: non-reader unrelated.txt must NOT be listed"; exit 1; }
printf '%s\n' "$out" | grep -q '\.git/' && { echo "FAIL: .git contents must be excluded"; exit 1; }

# --- aid-not-gate: a nonexistent artifact lists nothing and STILL exits 0 -----------------
out2="$("$CE" no_such_artifact_xyz.json "$tmp")" || { echo "FAIL: nonexistent artifact must still exit 0 (aid, not gate)"; exit 1; }
[[ -z "$(printf '%s' "$out2" | tr -d '[:space:]')" ]] || { echo "FAIL: nonexistent artifact must list nothing, got: $out2"; exit 1; }

echo "PASS: consumer-enumeration aid (78df)"
