#!/usr/bin/env bash
# roadmap:798d — unpromoted-scan.sh's twin check must recognize a ROADMAP item as
# twinned even when its own `<!-- id:XXXX -->` marker is NOT line-terminal because a
# trailing gate note follows it (id:1b1a's handback-followup.py inserts the note AFTER
# the marker: `<!-- id:XXXX --> — 🚧 GATED (auto, id:3801; ...)`).
#
# THE BUG (INBOUND routed:8911 from zkWhale relay handoff relay-20260717-182134-8632):
# unpromoted-scan.sh's twin regex (line ~269) anchors the marker to END-OF-LINE
# (`<!-- id:$token -->[[:space:]]*$`). handback-followup.py's gate_line (id:1b1a)
# deliberately inserts its gate note AFTER the id marker (the marker is not always
# line-terminal). So once an item is auto-GATED, its ROADMAP marker no longer ends the
# line and the end-of-line-strict twin check MISSES it — the TODO source with that id
# re-surfaces as phantom `promote` backlog every relay round, and the pool re-dispatches
# a no-op handoff (observed live: zkWhale id:4148/4944). This is the SAME hidden/phantom-
# backlog family as id:2dea / id:1312, reached from the opposite side (a false-NEGATIVE
# twin miss, where id:1312 was a false-POSITIVE prose match).
#
# THE FIX (798d): anchor the twin check on the `<!-- id:$token -->` HTML-comment marker
# form REGARDLESS of trailing notes — drop the `[[:space:]]*$` end-anchor. The comment-
# marker form is itself the anchor that prevents the id:1312 prose false-match (a bare
# `id:XXXX` mention in prose is never `<!-- id:XXXX -->`), so this fix must NOT regress
# test_unpromoted_scan_anchoring.sh (roadmap:1312).
#
# RED until the end-of-line anchor is relaxed to tolerate a trailing gate note. Hermetic.
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

# ROADMAP (ids are 4-hex tokens — the scan only recognizes `[0-9a-f]{4}` markers):
#  a1aa — twinned, marker followed by a real handback-followup gate note (id:1b1a shape).
#  a2bb — twinned, marker followed by a `— needs /relay human` gate note (human route).
#  cccc — twinned the ordinary way (marker IS line-terminal): regression control.
#  dddd — NOT an item; its id is only NAMED in another item's bare prose (id:1312 control).
cat > "$FIX/ROADMAP.md" <<'EOF'
# Roadmap

## Items
- [ ] [HARD — decision gate] auto-gated item <!-- id:a1aa --> — 🚧 GATED (auto, id:3801; route:decision-gate): premise needs a design ruling — needs a /meeting
- [ ] [HARD — decision gate] another gated item <!-- id:a2bb --> — 🚧 GATED (auto, id:3801; route:human): needs /relay human
- [x] [ROUTINE] a plainly twinned item <!-- id:cccc -->
- [ ] [ROUTINE] unrelated work — the follow-up seam is tracked as id:dddd, filed separately <!-- id:cafe -->
EOF

# TODO: all five ids are OPEN backlog lines.
cat > "$FIX/TODO.md" <<'EOF'
# TODO

## Current
- [ ] auto-gated in ROADMAP with a trailing gate note — MUST count as twinned [ROUTINE] <!-- id:a1aa -->
- [ ] auto-gated (human route) with a trailing gate note — MUST count as twinned [ROUTINE] <!-- id:a2bb -->
- [ ] plainly twinned — line-terminal ROADMAP marker [ROUTINE] <!-- id:cccc -->
- [ ] only mentioned in ROADMAP prose — must STILL be reported [ROUTINE] <!-- id:dddd -->
- [ ] absent from ROADMAP entirely [ROUTINE] <!-- id:beef -->
EOF
git -C "$FIX" add -A; git -C "$FIX" commit -qm init

rc=0; out="$("$SH" "$FIX" 2>/dev/null)" || rc=$?
[[ "$rc" -eq 0 ]] || fail "report-only: must exit 0 even with findings; got $rc"
pass "report-only (exit 0)"

# THE POINT (798d): a ROADMAP item whose marker is followed by a gate note is a REAL twin.
# The TODO source MUST NOT be reported as un-twinned backlog — otherwise the pool
# re-dispatches a phantom no-op handoff every round.
grep -qP '\ta1aa\t' <<<"$out" \
  && fail "id a1aa IS twinned in ROADMAP (marker + trailing gate note, id:1b1a shape) but was reported as un-twinned backlog — the end-of-line-strict twin check misses auto-gated items (798d):
$out"
pass "auto-gated twin (decision-gate note after marker) → suppressed"

grep -qP '\ta2bb\t' <<<"$out" \
  && fail "id a2bb IS twinned in ROADMAP (marker + trailing human-route gate note) but was reported as un-twinned backlog (798d):
$out"
pass "auto-gated twin (human-route note after marker) → suppressed"

# Regression control 1: an ordinary line-terminal marker still suppresses (true-twin).
grep -qP '\tcccc\t' <<<"$out" \
  && fail "id cccc has an ordinary line-terminal ROADMAP marker but was reported — the fix broke true-twin suppression:
$out"
pass "control: plainly-twinned id (line-terminal marker) → still suppressed"

# Regression control 2 (id:1312): a bare prose mention must NOT twin — still reported.
grep -qP '\tdddd\t' <<<"$out" \
  || fail "id dddd is only MENTIONED in ROADMAP prose (bare id:dddd, no <!-- --> marker) but was treated as twinned — the fix must not relax anchoring onto bare prose (regresses id:1312):
$out"
pass "control: bare prose mention does NOT twin → still reported"

# Regression control 3: an absent id is still reported at all (the scan works).
grep -qP '\tbeef\tpromote\t' <<<"$out" \
  || fail "id beef is absent from ROADMAP but was not reported as promote:
$out"
pass "control: id absent from ROADMAP → reported (promote)"

echo "ALL PASS"
