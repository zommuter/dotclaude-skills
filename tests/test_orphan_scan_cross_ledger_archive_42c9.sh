#!/usr/bin/env bash
# DEFECT-FIX test — no `# roadmap:XXXX` header on purpose: `routed:42c9` is tracked
# in TODO.md (<!-- id:f3c2 -->) and has no ROADMAP twin, so there is no checkbox to
# key EXPECTED-RED off. Failures here always count.
#
# ARCHIVE BLIND SPOT (routed:42c9, from loderite
# docs/meeting-notes/2026-08-13-1847-gate-topology-stale-gates-and-ledger-drift.md,
# item 3b / D2 / A4):
#
#   `orphan-scan.sh --cross-ledger` builds the TODO-side state map from the UNION
#   TODO.md + TODO.archive.md, but the ROADMAP-side map from `ROADMAP.md` ALONE.
#   That asymmetry is the bug. Once an archiver sweeps a closed ROADMAP item out of
#   the live file, its disagreement with a still-open TODO twin becomes UNDETECTABLE
#   and the scan reports CLEAN. Loderite had 4 such ids and the scan said CLEAN.
#
# The per-id stub emitted by `roadmap-archive.sh` (id:cd9c, shipped) mitigates this
# for items THIS repo's archiver moves from now on, but it does not close the hole:
#   * historically-archived items carry no stub (loderite's 333, restored by hand);
#   * other repos run their own archivers;
#   * `id:36f7` (owner-decided) makes stubs SELECTIVE — an unreferenced archived id
#     will get no stub at all.
# So the scan itself must read the archive.
#
# The item's second clause is asserted too: the fix must read SUPPRESSION MARKERS
# "wherever they live", i.e. an `<!-- xledger-ok: … -->` on the line inside
# ROADMAP.archive.md must suppress, or the widened scan turns every already-marked
# intentional split into a fresh false positive (the mute-training hazard D2's
# ordering exists to prevent).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORPHAN="$ROOT/meeting/orphan-scan.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fix="$tmp/repo"
mkdir -p "$fix/docs/meeting-notes"

fail() { echo "FAIL: $*"; echo "--- scan output ---"; echo "$out"; exit 1; }

cat > "$fix/TODO.md" <<'EOF'
# TODO
## Current
- [ ] shipped-in-roadmap, never ticked in TODO <!-- id:aa01 -->
- [ ] deliberate scope split, marked in the ARCHIVE <!-- id:aa02 -->
- [ ] reopened here; live ROADMAP agrees it is open <!-- id:aa03 -->
- [ ] genuinely open in both live ledgers <!-- id:aa04 -->
EOF

cat > "$fix/TODO.archive.md" <<'EOF'
# TODO archive
EOF

cat > "$fix/ROADMAP.md" <<'EOF'
# Roadmap
## Items
- [ ] reopened seam, still open in the live queue <!-- id:aa03 -->
- [ ] genuinely open in both live ledgers <!-- id:aa04 -->
EOF

cat > "$fix/ROADMAP.archive.md" <<'EOF'
# Roadmap archive
- [x] shipped and swept out of the live file <!-- id:aa01 -->
- [x] closed here, TODO half is a different scope <!-- xledger-ok: deliberate scope split --> <!-- id:aa02 -->
- [x] an OLD closed item recycling aa03's token <!-- id:aa03 -->
EOF

out="$(HOME="$tmp" "$ORPHAN" --cross-ledger "$fix")"

# --- Case 1 — THE DEFECT. aa01 is [ ] in TODO.md and [x] only in ROADMAP.archive.md.
# Archive-blind, the ROADMAP map has no aa01 at all, the token is skipped, CLEAN.
grep -q 'id:aa01' <<<"$out" \
  || fail "id:aa01 NOT flagged — a ROADMAP item archived out of the live file no longer collides with its still-open TODO twin (routed:42c9 archive blind spot)"
grep -qE 'id:aa01 .*TODO:\[ \] ROADMAP:\[x\]' <<<"$out" \
  || fail "id:aa01 flagged with the wrong states — expected TODO:[ ] ROADMAP:[x]"
echo "PASS: an archived-only ROADMAP twin is compared against its open TODO twin"

# --- Case 2 — suppression markers must be read INSIDE ROADMAP.archive.md.
grep -q 'id:aa02' <<<"$out" \
  && fail "id:aa02 flagged despite an <!-- xledger-ok: … --> marker on its ROADMAP.archive.md line — the widened scan is blind to suppressions living in the archive (routed:42c9, second clause)"
echo "PASS: <!-- xledger-ok: … --> inside ROADMAP.archive.md suppresses"

# --- Case 3 — first-wins must survive the widening: the LIVE ROADMAP.md line is
# authoritative over a recycled token in ROADMAP.archive.md, mirroring the id:9221
# rule already applied on the TODO side. aa03 is [ ] live and [ ] in TODO → CLEAN.
grep -q 'id:aa03' <<<"$out" \
  && fail "id:aa03 flagged — a recycled token in ROADMAP.archive.md overwrote the ACTIVE ROADMAP.md state; live must win (id:9221 first-wins, ROADMAP side)"
echo "PASS: live ROADMAP.md wins over a recycled id in ROADMAP.archive.md"

# --- Case 4 — negative control: no spurious flag for an id open in both live files.
grep -q 'id:aa04' <<<"$out" \
  && fail "id:aa04 flagged — both ledgers say [ ]; the widening invented a divergence"
echo "PASS: agreeing live ledgers stay clean"

# --- Case 5 — a repo with NO ROADMAP.archive.md must behave exactly as before
# (a missing archive is a normal state, not an error).
fix2="$tmp/repo2"
mkdir -p "$fix2"
cat > "$fix2/TODO.md" <<'EOF'
# TODO
- [ ] open in todo, closed in roadmap <!-- id:bb01 -->
EOF
cat > "$fix2/ROADMAP.md" <<'EOF'
# Roadmap
- [x] closed <!-- id:bb01 -->
EOF
out="$(HOME="$tmp" "$ORPHAN" --cross-ledger "$fix2")"
grep -q 'id:bb01' <<<"$out" \
  || fail "id:bb01 NOT flagged in a repo with no ROADMAP.archive.md — the pre-existing behaviour regressed"
echo "PASS: a missing ROADMAP.archive.md is a normal state"

echo "OK: test_orphan_scan_cross_ledger_archive_42c9.sh"
