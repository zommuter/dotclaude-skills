#!/usr/bin/env bash
# roadmap:9bec — relay-doctor.sh: the report-only relay-machinery health aggregator
# (cheap-first-slice of id:0907). Structural invariants + a hermetic functional smoke.
#
# Decisions (meeting 2026-06-24, id:0907): report-only by default (exit 0 even with
# findings; only misuse is nonzero), aggregates the already-built checks by CALLING them,
# and LISTS the not-yet-wired checks (D4) so coverage is honest. /relay health + review
# wiring (id:3eb5) and --strict (id:a883) are SEPARATE follow-on items, not asserted here.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SH="$ROOT/relay/scripts/relay-doctor.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$SH" ]] || fail "relay-doctor.sh not found at $SH"
[[ -x "$SH" ]] || fail "relay-doctor.sh not executable"
bash -n "$SH" || fail "relay-doctor.sh fails bash -n"
pass "relay-doctor.sh exists, executable, parses"

# (1) Aggregates by CALLING the canonical checks (never reimplements).
for needle in 'orphan-scan.sh' 'roadmap-lint.sh' 'relay-reconcile.sh' '69ef'; do
  grep -q "$needle" "$SH" || fail "relay-doctor does not invoke/reference the canonical check: $needle"
done
pass "aggregates the canonical checks (orphan-scan --cross-ledger, roadmap-lint, reconcile --all, refs-install)"

# (2) Report-only contract: a header/summary states report-only + exit 0 on findings.
grep -qiE 'report-only' "$SH" || fail "no report-only contract stated in relay-doctor"
grep -qE 'exit 0' "$SH" || fail "relay-doctor never exits 0 explicitly (report-only path missing)"
pass "report-only contract present (exit 0 regardless of findings)"

# (3) D4 honesty: the report LISTS not-yet-wired checks (gated coverage gaps).
grep -qiE 'not yet wired|NOT yet wired|coverage gap' "$SH" || fail "relay-doctor does not list not-yet-wired checks (D4 honesty)"
grep -qE 'e149' "$SH" || fail "the gated-checks list must name id:e149 (claim/lease staleness gap)"
pass "lists not-yet-wired checks (D4 — honest coverage, names id:e149)"

# (4) Misuse is the ONLY nonzero exit (a bad flag must reject loudly).
out_rc=0; "$SH" --definitely-not-a-flag >/dev/null 2>&1 || out_rc=$?
[[ "$out_rc" -ne 0 ]] || fail "an unknown flag must exit nonzero (misuse reject); got 0"
pass "unknown flag exits nonzero (misuse reject)"

# (5) Hermetic functional smoke: a minimal fixture git repo, scoped to itself, runs to
#     completion and exits 0 (report-only) with the summary + gated-checks sections.
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
git -C "$FIX" init -q
git -C "$FIX" config user.email t@e.st; git -C "$FIX" config user.name t
printf '# ROADMAP\n\n- [ ] a clean routine item [ROUTINE] <!-- id:aaaa -->\n' > "$FIX/ROADMAP.md"
printf '# TODO\n\n## Current\n- [ ] a clean routine item [ROUTINE] <!-- id:aaaa -->\n' > "$FIX/TODO.md"
git -C "$FIX" add -A; git -C "$FIX" commit -qm init
smoke_rc=0
smoke_out="$("$SH" "$FIX" 2>&1)" || smoke_rc=$?
[[ "$smoke_rc" -eq 0 ]] || fail "relay-doctor on a clean fixture must exit 0 (report-only); got $smoke_rc
$smoke_out"
grep -qE '=== summary ===' <<<"$smoke_out" || fail "no summary section in output"
grep -qiE 'not yet wired|NOT yet wired' <<<"$smoke_out" || fail "no gated-checks section in output"
pass "hermetic fixture run: exits 0, prints summary + gated-checks sections"

echo "ALL PASS: id:9bec relay-doctor report-only aggregator (cheap-first-slice of id:0907)"
