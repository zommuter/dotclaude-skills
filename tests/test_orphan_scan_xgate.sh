#!/usr/bin/env bash
# roadmap:7f30 — orphan-scan.sh needs an `<!-- xgate:TOKEN@repo -->` sibling-comment
# convention for a deliberately-unmarked CROSS-REPO gate whose blocking token lives in
# ANOTHER repo (e.g. id:50c4 gated on 508d@relay-core). Today such an item has no LOCAL
# `gated-on:` edge to point at, so it re-fires UNMARKED-GATE on every --shipped scan.
# The generic `<!-- gate-prose-only -->` marker (id:8800) suppresses the re-fire but
# DISCARDS which external token/repo blocks it. `xgate:TOKEN@repo` records that
# cross-repo dependency explicitly (parseable) AND, like gate-prose-only, bypasses the
# UNMARKED-GATE backstop — so confirming a cross-repo gate SHRINKS the detector.
#
# DECIDED 2026-07-13 (relay human, REVIEW_ME id:50c4 option a). RED until id:7f30 ships.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORPHAN="$ROOT/meeting/orphan-scan.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
repo="$tmp/repo"
mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" config user.email "test@example.com"
git -C "$repo" config user.name "Test"

: > "$repo/TODO.archive.md"
: > "$repo/ROADMAP.md"

cat > "$repo/TODO.md" <<'EOF'
# TODO
## Current
- [ ] cross-repo gate, blocking token lives in another repo <!-- xgate:508d@relay-core --> gated on the relay-core 508d publish decision <!-- id:50c4 -->
- [ ] an unconfirmed gate with gate vocabulary and no marker, gated on some future decision <!-- id:8802 -->
EOF
git -C "$repo" add -A
git -C "$repo" commit -q -m "fixture"

out="$(HOME="$tmp" timeout 30 "$ORPHAN" --shipped "$repo")"

# The xgate-marked cross-repo gate must NOT re-fire UNMARKED-GATE.
if grep -q 'id:50c4.*UNMARKED-GATE' <<<"$out"; then
  echo "FAIL: id:50c4 carries <!-- xgate:508d@relay-core --> and must NOT surface as UNMARKED-GATE"
  echo "got: $out"; exit 1
fi

# The control item (gate vocabulary, no marker) MUST still surface as UNMARKED-GATE.
grep -q 'id:8802.*UNMARKED-GATE' <<<"$out" \
  || { echo "FAIL: id:8802 (unmarked gate) must still surface as UNMARKED-GATE"; echo "got: $out"; exit 1; }

echo ok
