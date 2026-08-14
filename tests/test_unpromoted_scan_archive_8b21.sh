#!/usr/bin/env bash
# DEFECT-FIX test — no `# roadmap:XXXX` header on purpose: `routed:8b21` is tracked
# in TODO.md (<!-- id:b36d -->) and has no ROADMAP twin, so there is no checkbox to
# key EXPECTED-RED off. Failures here always count.
#
# ARCHIVE BLIND SPOT (routed:8b21, from escapement):
#
#   `unpromoted-scan.sh` decides "does this open TODO id have a ROADMAP twin?" by
#   grepping `$path/ROADMAP.md` ALONE (roadmap_content, scan_repo). Once
#   `roadmap-archive.sh` sweeps the shipped `- [x]` item into ROADMAP.archive.md,
#   the twin disappears, and an open TODO line whose work ALREADY SHIPPED is
#   re-reported as `promote` — i.e. re-dispatched, forever, every round.
#
# Note the asymmetry this shares with routed:42c9: the TODO side of the fleet's
# scanners reads its archive; the ROADMAP side does not.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCAN="$ROOT/relay/scripts/unpromoted-scan.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
repo="$tmp/fixrepo"
mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" config user.email t@example.invalid
git -C "$repo" config user.name t

fail() { echo "FAIL: $*"; echo "--- scan output ---"; echo "$out"; exit 1; }

cat > "$repo/TODO.md" <<'EOF'
# TODO
## Current
- [ ] [ROUTINE] **already shipped; twin was archived out of ROADMAP.md** <!-- id:cc01 -->
- [ ] [ROUTINE] **genuinely un-promoted, exists in no ROADMAP file** <!-- id:cc02 -->
- [ ] [ROUTINE] **twinned in the LIVE roadmap** <!-- id:cc03 -->
EOF

cat > "$repo/ROADMAP.md" <<'EOF'
# Roadmap
## Items
- [ ] [ROUTINE] twinned in the live roadmap <!-- id:cc03 -->
EOF

cat > "$repo/ROADMAP.archive.md" <<'EOF'
# Roadmap archive
- [x] [ROUTINE] shipped and swept out of the live file <!-- id:cc01 -->
EOF

out="$(HOME="$tmp" UNPROMOTED_SCAN_LOG="$tmp/scan.log" RELAY_TOML="$tmp/none.toml" "$SCAN" "$repo")"

# --- Case 1 — THE DEFECT: cc01's twin lives only in ROADMAP.archive.md.
grep -qP '\tcc01\t' <<<"$out" \
  && fail "cc01 reported — an ALREADY-SHIPPED item whose ROADMAP twin was archived is re-flagged for promotion/re-dispatch (routed:8b21 archive blind spot)"
echo "PASS: a ROADMAP.archive.md twin counts as twinned"

# --- Case 2 — negative control: a genuinely un-twinned id must STILL be reported,
# so the fix cannot be a blanket suppression.
grep -qP '\tcc02\tpromote\t' <<<"$out" \
  || fail "cc02 NOT reported as promote — the archive widening suppressed genuine un-promoted backlog"
echo "PASS: genuinely un-twinned backlog is still reported"

# --- Case 3 — pre-existing live-twin behaviour intact.
grep -qP '\tcc03\t' <<<"$out" \
  && fail "cc03 reported — a live ROADMAP.md twin must suppress, as before"
echo "PASS: live ROADMAP.md twin still suppresses"

# --- Case 4 — a repo with NO ROADMAP.archive.md behaves exactly as before.
repo2="$tmp/fixrepo2"
mkdir -p "$repo2"
git -C "$repo2" init -q
git -C "$repo2" config user.email t@example.invalid
git -C "$repo2" config user.name t
cat > "$repo2/TODO.md" <<'EOF'
# TODO
- [ ] [ROUTINE] **un-promoted, no archive file exists** <!-- id:dd01 -->
EOF
printf '# Roadmap\n' > "$repo2/ROADMAP.md"
out="$(HOME="$tmp" UNPROMOTED_SCAN_LOG="$tmp/scan.log" RELAY_TOML="$tmp/none.toml" "$SCAN" "$repo2")"
grep -qP '\tdd01\tpromote\t' <<<"$out" \
  || fail "dd01 NOT reported in a repo with no ROADMAP.archive.md — pre-existing behaviour regressed"
echo "PASS: a missing ROADMAP.archive.md is a normal state"

# --- Case 5 — the twin check must stay ANCHORED inside the archive too (id:1312):
# a bare `id:XXXX` mentioned in another archived item's PROSE must NOT count as a twin.
repo3="$tmp/fixrepo3"
mkdir -p "$repo3"
git -C "$repo3" init -q
git -C "$repo3" config user.email t@example.invalid
git -C "$repo3" config user.name t
cat > "$repo3/TODO.md" <<'EOF'
# TODO
- [ ] [ROUTINE] **only ever MENTIONED in archived prose** <!-- id:ee01 -->
EOF
printf '# Roadmap\n' > "$repo3/ROADMAP.md"
cat > "$repo3/ROADMAP.archive.md" <<'EOF'
# Roadmap archive
- [x] [ROUTINE] some other shipped item, whose body says the rest is tracked as id:ee01 <!-- id:ee99 -->
EOF
out="$(HOME="$tmp" UNPROMOTED_SCAN_LOG="$tmp/scan.log" RELAY_TOML="$tmp/none.toml" "$SCAN" "$repo3")"
grep -qP '\tee01\tpromote\t' <<<"$out" \
  || fail "ee01 NOT reported — a BARE prose mention inside ROADMAP.archive.md was accepted as a twin; the archive read must keep the id:1312 anchoring"
echo "PASS: the archive twin check stays anchored on <!-- id:XXXX --> (id:1312)"

echo "OK: test_unpromoted_scan_archive_8b21.sh"
