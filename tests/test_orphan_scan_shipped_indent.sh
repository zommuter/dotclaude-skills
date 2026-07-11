#!/usr/bin/env bash
# roadmap:431f — orphan-scan.sh --shipped never sees INDENTED sub-items. The shipped
# driver greps `^- \[ \] ` anchored at column 0 (and the typed-edge local_state map
# uses `^- \[[ xX]\] ` col-0 too), so an item nested under a parent
# (`  - [ ] … <!-- id -->`) is never classified into any --shipped class. Contract:
# widen the anchor to `^\s*- \[ \] ` so an indented umbrella item with a `children:`
# marker whose children are all [x] is reported UMBRELLA-READY, while pre-existing
# col-0 behaviour is unchanged.
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

# A col-0 control umbrella (child closed) — must be UMBRELLA-READY today and stay so.
# An INDENTED umbrella (child closed) — invisible today (the 431f gap), must become
# UMBRELLA-READY after the anchor is widened.
cat > "$repo/TODO.md" <<'EOF'
# TODO
## Current
- [x] closed child of the col-0 umbrella <!-- id:c0c0 -->
- [ ] col-0 umbrella parent <!-- children:c0c0 --> <!-- id:aa00 -->
- [ ] a real parent line
  - [x] closed child of the indented umbrella <!-- id:c1c1 -->
  - [ ] indented umbrella parent <!-- children:c1c1 --> <!-- id:bb11 -->
EOF
git -C "$repo" add -A
git -C "$repo" commit -q -m "fixture"

out="$(HOME="$tmp" timeout 30 "$ORPHAN" --shipped "$repo")"

# Col-0 umbrella: pre-existing behaviour, still UMBRELLA-READY.
grep -q 'id:aa00.*UMBRELLA-READY' <<<"$out" \
  || { echo "regression: col-0 umbrella id:aa00 must be UMBRELLA-READY"; echo "got: $out"; exit 1; }

# Indented umbrella: the id:431f gap — must be classified once the anchor is widened.
grep -q 'id:bb11.*UMBRELLA-READY' <<<"$out" \
  || { echo "must report indented umbrella id:bb11 as UMBRELLA-READY (431f anchor-widening)"; echo "got: $out"; exit 1; }

echo ok
