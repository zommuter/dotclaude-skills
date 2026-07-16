#!/usr/bin/env bash
# roadmap:1312 — unpromoted-scan.sh's twin check must be ANCHORED to an item's own trailing
# `<!-- id:XXXX -->` marker, not a bare substring grep over all of ROADMAP.md.
#
# The defect: line ~262 does `grep -qF "id:$token" <<<"$roadmap_content" && continue`, matched
# against the WHOLE ROADMAP. So ordinary explanatory prose that merely MENTIONS a token —
# "…separate seam tracked as id:2b63" — makes that token register as already-twinned, and the
# item silently drops out of the backlog scan entirely. Observed 2026-07-16: the zkm handoff
# child self-inflicted this (prose mention dropped `df4e` from `laned` to 0 rows) and caught it
# only by re-running the scan instead of trusting its own commit.
#
# That is EXACTLY the id:2dea hidden-backlog failure the scan exists to prevent, reachable by
# ordinary prose. Same hazard class as the inbox-done substring match ([[todo-routing]]) and
# md-merge's fail-open append ([[md-merge-1b1a]]). scan-routed.sh already anchors its twin
# check to the marker for this reason; unpromoted-scan never got the same fix.
#
# RED until the twin check is anchored. Hermetic: a fixture repo under mktemp -d.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SH="$ROOT/relay/scripts/unpromoted-scan.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SH" ]] || fail "unpromoted-scan.sh not found/executable at $SH"

FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
git -C "$FIX" init -q
git -C "$FIX" config user.email t@e.st; git -C "$FIX" config user.name t

# ROADMAP: `aaaa` is genuinely twinned (its own marker). `dead` is NOT an item here — it is
# only NAMED in another item's explanatory prose. `beef` has no presence at all.
cat > "$FIX/ROADMAP.md" <<'EOF'
# Roadmap

## Items
- [x] [ROUTINE] a genuinely twinned item <!-- id:aaaa -->
- [ ] [ROUTINE] some unrelated work — note: the follow-up seam is tracked as id:dead, filed separately <!-- id:cafe -->
EOF

# TODO: all three are OPEN [ROUTINE] backlog.
cat > "$FIX/TODO.md" <<'EOF'
# TODO

## Current
- [ ] twinned for real — has its own ROADMAP marker [ROUTINE] <!-- id:aaaa -->
- [ ] ONLY mentioned in ROADMAP prose — must still be reported [ROUTINE] <!-- id:dead -->
- [ ] absent from ROADMAP entirely [ROUTINE] <!-- id:beef -->
EOF
git -C "$FIX" add -A; git -C "$FIX" commit -qm init

rc=0; out="$("$SH" "$FIX" 2>/dev/null)" || rc=$?
[[ "$rc" -eq 0 ]] || fail "report-only: must exit 0 even with findings; got $rc"
pass "report-only (exit 0)"

# Control 1: a REAL twin (own trailing marker) is still suppressed. Anchoring must not
# regress the true-positive suppression that makes the twin check useful at all.
grep -qP '\taaaa\t' <<<"$out" && fail "id aaaa has a REAL ROADMAP twin (own marker) but was reported — anchoring broke true-twin suppression:
$out"
pass "control: genuinely-twinned id (own marker) → still suppressed"

# Control 2: a token absent from ROADMAP is reported (the scan works at all).
grep -qP '\tbeef\tpromote\t' <<<"$out" || fail "id beef is absent from ROADMAP but was not reported as promote:
$out"
pass "control: id absent from ROADMAP → reported (promote)"

# THE POINT: `dead` appears in ROADMAP only inside another item's PROSE. It has no item of
# its own, so it is un-promoted backlog and MUST be reported. The bare-substring twin check
# suppresses it — the silent hidden-backlog defect.
grep -qP '\tdead\t' <<<"$out" \
  || fail "id dead is only MENTIONED in another item's ROADMAP prose (no marker of its own) but was silently treated as twinned and dropped from the scan — this is the id:2dea hidden-backlog failure reachable by ordinary prose (id:1312):
$out"
pass "prose-only mention does NOT twin an item — it is still reported as backlog"

echo "ALL PASS"
