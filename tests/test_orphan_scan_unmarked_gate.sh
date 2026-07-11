#!/usr/bin/env bash
# roadmap:4245 — surface the two deliberately-unmarked cross-repo gate edges as
# UNMARKED-GATE in orphan-scan.sh --shipped. The typed-edge pass left id:7df1 and
# id:50c4 without a local `gated-on:` marker on purpose: their gate tokens live in
# project_manager / relay-core and cannot resolve locally, so they must surface as
# UNMARKED-GATE (to be resolved via routed:/inbox), never as a local gated-on: edge.
#
# This encodes the 7df1-shaped case: an INDENTED item carrying `🚧 GATED (DEP: …)`
# gate vocabulary and NO local `gated-on:` marker must be reported UNMARKED-GATE.
# (It DEPENDS on id:431f's anchor-widening so an indented gated item is visible at all.)
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
- [ ] a real parent line
  - [ ] finalizer, cross-repo gate token lives in another repo 🚧 GATED (DEP: 3ef7 + cross-repo re-tag) <!-- id:7df1 -->
- [ ] a col-0 item with a local gated-on: marker MUST NOT be UNMARKED-GATE <!-- gated-on:c0de --> <!-- id:9999 -->
- [x] the local gate token, closed <!-- id:c0de -->
EOF
git -C "$repo" add -A
git -C "$repo" commit -q -m "fixture"

out="$(HOME="$tmp" timeout 30 "$ORPHAN" --shipped "$repo")"

# The indented, deliberately-unmarked cross-repo gate must surface as UNMARKED-GATE.
grep -q 'id:7df1.*UNMARKED-GATE' <<<"$out" \
  || { echo "must report indented cross-repo gate id:7df1 as UNMARKED-GATE (4245; needs 431f anchor)"; echo "got: $out"; exit 1; }

# An item carrying a proper local `gated-on:` marker is NOT an unmarked gate.
if grep -q 'id:9999.*UNMARKED-GATE' <<<"$out"; then
  echo "must NOT report id:9999 (has a local gated-on: marker) as UNMARKED-GATE"; echo "got: $out"; exit 1
fi

echo ok
