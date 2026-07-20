#!/usr/bin/env bash
# roadmap:5367 — mechanical disjoint-path greenlight for `/relay . --parallel N` (id:ebbe
# child, meeting 2026-07-19-2035 D4). Concurrent executors are greenlit MECHANICALLY and
# FAIL-CLOSED: only when every candidate unit's DECLARED file-set is non-empty AND the sets
# are pairwise disjoint; any empty/undeclared set or any overlap → serial. The same script
# re-enforces at merge time: the 2nd worktree's touched paths vs the already-merged diff —
# a non-empty intersection is a HANDBACK signal, never auto-resolved.
#
# Interface under test (the spec): relay/scripts/disjoint-greenlight.sh
#   plan            reads TSV on stdin, one line per candidate unit: "<id>\t<comma-joined paths>"
#                   prints exactly one word: "concurrent" or "serial"; exit 0.
#                   Malformed input (no tab) → nonzero exit + ERROR on stderr.
#                   Fail-closed rules: <2 units → serial; any empty path-set → serial;
#                   any pairwise overlap → serial.
#   merge-check --touched <file> --merged <file>
#                   two newline-delimited path lists. Disjoint → exit 0, empty stdout.
#                   Intersection → exit 1, intersecting paths on stdout (the handback evidence).
# Hermetic: bash-only, mktemp, no git/network.
set -uo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GL="$SRC_DIR/relay/scripts/disjoint-greenlight.sh"
pass=0 fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); return 0; }
bad() { echo "BAD: $*"; fail=$((fail+1)); return 0; }

[[ -f "$GL" ]] || { echo "FAIL: relay/scripts/disjoint-greenlight.sh does not exist yet (RED spec)"; exit 1; }
[[ -x "$GL" ]] || { echo "FAIL: disjoint-greenlight.sh not executable"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# --- plan: two units, non-empty, disjoint → concurrent -------------------------
out="$(printf 'u1\trelay/scripts/a.sh,tests/test_a.sh\nu2\trelay/scripts/b.sh,tests/test_b.sh\n' | "$GL" plan)" \
  && [[ "$out" == "concurrent" ]] \
  && ok "plan: disjoint non-empty sets → concurrent" \
  || bad "plan: disjoint non-empty sets should print 'concurrent' (got: ${out:-<err>})"

# --- plan: overlap on one path → serial ----------------------------------------
out="$(printf 'u1\trelay/scripts/a.sh,tests/shared.sh\nu2\trelay/scripts/b.sh,tests/shared.sh\n' | "$GL" plan)" \
  && [[ "$out" == "serial" ]] \
  && ok "plan: overlapping sets → serial" \
  || bad "plan: overlapping sets should print 'serial' (got: ${out:-<err>})"

# --- plan: one EMPTY declared set → serial (fail-closed, undeclarable) ---------
out="$(printf 'u1\trelay/scripts/a.sh\nu2\t\n' | "$GL" plan)" \
  && [[ "$out" == "serial" ]] \
  && ok "plan: empty declared set → serial (fail-closed)" \
  || bad "plan: an empty declared file-set must force 'serial' (got: ${out:-<err>})"

# --- plan: single unit → serial (nothing to parallelize) -----------------------
out="$(printf 'u1\trelay/scripts/a.sh\n' | "$GL" plan)" \
  && [[ "$out" == "serial" ]] \
  && ok "plan: single unit → serial" \
  || bad "plan: a single unit should print 'serial' (got: ${out:-<err>})"

# --- plan: malformed line (no tab) → nonzero + ERROR on stderr -----------------
if printf 'garbage-without-tab\n' | "$GL" plan >"$TMP/o" 2>"$TMP/e"; then
  bad "plan: malformed input must exit nonzero"
else
  grep -qi 'ERROR' "$TMP/e" \
    && ok "plan: malformed input → nonzero + ERROR on stderr" \
    || bad "plan: malformed input exited nonzero but printed no ERROR on stderr"
fi

# --- merge-check: disjoint → exit 0, silent ------------------------------------
printf 'relay/scripts/b.sh\ntests/test_b.sh\n' > "$TMP/touched"
printf 'relay/scripts/a.sh\ntests/test_a.sh\n' > "$TMP/merged"
if out="$("$GL" merge-check --touched "$TMP/touched" --merged "$TMP/merged")"; then
  [[ -z "$out" ]] \
    && ok "merge-check: disjoint → exit 0, empty stdout" \
    || bad "merge-check: disjoint should print nothing (got: $out)"
else
  bad "merge-check: disjoint path lists must exit 0"
fi

# --- merge-check: intersection → exit 1 + the overlapping path on stdout -------
printf 'relay/scripts/a.sh\ndocs/x.md\n' > "$TMP/touched2"
if out="$("$GL" merge-check --touched "$TMP/touched2" --merged "$TMP/merged")"; then
  bad "merge-check: intersecting path lists must exit nonzero (handback signal)"
else
  echo "$out" | grep -qF 'relay/scripts/a.sh' \
    && ok "merge-check: intersection → exit 1 + overlapping path printed" \
    || bad "merge-check: intersection detected but overlapping path not printed (got: $out)"
fi

echo "summary: $pass ok, $fail bad"
[[ "$fail" -eq 0 ]] || exit 1
exit 0
