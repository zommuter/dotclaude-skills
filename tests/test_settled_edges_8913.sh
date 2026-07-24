#!/usr/bin/env bash
# roadmap:8913 — anchored settles:/decided-in: typed-edge grammar + orphan-scan
# --settled/--unbackrefed (meeting 2026-07-24-0929, parent id:968c).
#
# --settled reports a meeting-note `<!-- settles:XXXX -->` edge ONLY when its target
# is still OPEN in the ledger union; a bare `id:XXXX` mention or a backticked bare
# token under a Decisions heading is NEVER an edge (the refuted D1(ii) bare-grep
# design). --unbackrefed reports OPEN `[* — meeting]`/`[INPUT — decision]` ledger
# items with NO `decided-in:` backref (presence-only, never a date comparison).
#
# Hermetic: all fixtures live in mktemp -d; never touches ~/.claude or the network.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORPHAN="$ROOT/meeting/orphan-scan.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

repo="$tmp/repo"
mkdir -p "$repo/docs/meeting-notes" "$repo/tests"
: > "$repo/TODO.archive.md"

# --- Fixture meeting note: a `## Decisions` section exercising all four bullet
# shapes the RED spec requires: an anchored settles: edge onto an OPEN item, an
# anchored settles: edge onto a CLOSED item, a bare `id:XXXX` mention (mirrors the
# real 2026-07-23-2320 note's id:010c case — "Filed as id:cccc" under Decisions,
# reporting it is the refuted design), and a backticked bare token with no `id:`
# prefix at all (mirrors the real 2026-07-17-1541 founding e647/b8fa note).
cat > "$repo/docs/meeting-notes/2026-01-01-0000-fixture-settled-8913.md" <<'EOF'
# Fixture meeting note

## Decisions

- **D1** — settled the frobnicator bug; the fix is item aaaa. <!-- settles:aaaa -->
- **D2** — settled the other bug; the fix is item bbbb, already shipped. <!-- settles:bbbb -->
- **D3** — filed as id:cccc; the standard remedy is scoped in that item, not decided here.
- **D4** — already settled the hard part, see `dddd` for the mechanism.

## Action items

- [ ] some unrelated action item <!-- id:9999 -->
EOF

cat > "$repo/TODO.md" <<'EOF'
# TODO
## Current
- [ ] item aaaa, fixed by D1 <!-- id:aaaa -->
- [x] item bbbb, fixed by D2 <!-- id:bbbb -->
- [ ] item cccc, merely cited (bare mention) under D3 <!-- id:cccc -->
- [ ] item dddd, merely cited (backticked bare token) under D4 <!-- id:dddd -->
- [ ] [INPUT — decision] a decision item with no backref <!-- id:eeee -->
- [ ] [INPUT — meeting] a meeting item WITH a decided-in backref <!-- decided-in:docs/meeting-notes/2026-01-01-0000-fixture-settled-8913.md --> <!-- id:ffff -->
- [x] [INPUT — decision] a closed decision item, no backref (must not fire — not open) <!-- id:1111 -->
- [ ] [ROUTINE] an ordinary item, no meeting/decision lane tag (must not fire) <!-- id:2222 -->
EOF
: > "$repo/ROADMAP.md"

git -C "$repo" init -q
git -C "$repo" config user.email "test@example.com"
git -C "$repo" config user.name "Test"
git -C "$repo" add -A
git -C "$repo" commit -q -m fixture

run() {
  set +e
  OUT="$(HOME="$tmp" ORPHAN_SCAN_LIMIT=0 "$ORPHAN" "$1" "$repo" 2>&1)"
  RC=$?
  set -e
}
fail() { echo "FAIL: $1"; echo "--- exit=$RC out ---"; echo "$OUT"; exit 1; }

# --- --settled ------------------------------------------------------------------
run --settled

echo "$OUT" | grep -q 'id:aaaa.*SETTLED-BUT-OPEN' \
  || fail "id:aaaa carries an anchored settles: edge and is OPEN — must fire SETTLED-BUT-OPEN"

echo "$OUT" | grep -q 'id:bbbb' \
  && fail "id:bbbb's settles: edge resolves to a CLOSED ([x]) item — must NOT fire"

echo "$OUT" | grep -q 'id:cccc' \
  && fail "id:cccc is only a BARE id: mention under Decisions (no settles: edge, mirrors the real id:010c ground truth) — must NOT fire"

echo "$OUT" | grep -q 'id:dddd\|dddd' \
  && fail "id:dddd is only a backticked BARE token under Decisions (mirrors the real e647/b8fa founding note) — must NOT fire"

# --- --unbackrefed ----------------------------------------------------------------
run --unbackrefed

echo "$OUT" | grep -q 'id:eeee.*UNBACKREFED' \
  || fail "id:eeee is OPEN, tagged [INPUT — decision], no decided-in: marker — must fire UNBACKREFED"

echo "$OUT" | grep -q 'id:ffff' \
  && fail "id:ffff carries a decided-in: backref — must NOT fire"

echo "$OUT" | grep -q 'id:1111' \
  && fail "id:1111 is CLOSED ([x]) — must NOT fire even though it lacks a backref"

echo "$OUT" | grep -q 'id:2222' \
  && fail "id:2222 carries no [* — meeting]/[INPUT — decision] lane tag — must NOT fire"

echo ok
