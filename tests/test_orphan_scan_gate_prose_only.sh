#!/usr/bin/env bash
# roadmap:8800 — orphan-scan.sh UNMARKED-GATE backstop needs a durable suppressor
# for gates whose blocking condition is an EXTERNAL prose condition (not a local
# TODO-id dependency). Such an item has no local `gated-on:` edge to add, so it
# re-fires UNMARKED-GATE on every --shipped scan with no non-hacky resolution.
# A `<!-- gate-prose-only -->` marker records "this prose gate is confirmed,
# intentionally has no typed edge" and, like the typed-edge markers (has_typed),
# BYPASSES the UNMARKED-GATE backstop — so confirming a prose-only gate SHRINKS the
# detector instead of re-litigating it every run.
#
# INBOUND routed:1cda from zkm. RED until id:8800 ships.
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
- [ ] confirmed prose-only external gate, no local id dep <!-- gate-prose-only --> gated on the upstream vendor shipping their API <!-- id:8801 -->
- [ ] an unconfirmed gate with gate vocabulary and no marker, gated on some future decision <!-- id:8802 -->
EOF
git -C "$repo" add -A
git -C "$repo" commit -q -m "fixture"

out="$(HOME="$tmp" timeout 30 "$ORPHAN" --shipped "$repo")"

# The confirmed prose-only gate must NOT re-fire UNMARKED-GATE (the marker suppresses it).
if grep -q 'id:8801.*UNMARKED-GATE' <<<"$out"; then
  echo "FAIL: id:8801 carries <!-- gate-prose-only --> and must NOT surface as UNMARKED-GATE"
  echo "got: $out"; exit 1
fi

# The control item (gate vocabulary, no marker) MUST still surface as UNMARKED-GATE.
grep -q 'id:8802.*UNMARKED-GATE' <<<"$out" \
  || { echo "FAIL: id:8802 (unmarked gate) must still surface as UNMARKED-GATE"; echo "got: $out"; exit 1; }

echo ok
