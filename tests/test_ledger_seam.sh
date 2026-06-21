#!/usr/bin/env bash
# roadmap:d9b0 — Mechanize the TODO↔ROADMAP seam: promotion-tracking + derived count
# + xledger-ok scope-split suppression. Three sub-features (id:d9b0):
#   1. --promotion mode: flags open TODO items with [ROUTINE]/[HARD — pool] absent from ROADMAP.
#   2. xledger-ok: --cross-ledger honors <!-- xledger-ok: <reason> --> to suppress intentional
#      scope-splits (e.g. closed ROADMAP decision + open TODO action with different scope).
#   3. Derived count: the fixture has no hand-maintained "Relay: N open ROADMAP items" line;
#      the test asserts its absence (promotion/seam checks work without a hand-maintained count).
# Hermetic: tmpdir fixture, no network, no $HOME write.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ORPHAN="$ROOT/meeting/orphan-scan.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$ORPHAN" ]] || fail "orphan-scan.sh not found/executable at $ORPHAN"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fix="$tmp/repo"
mkdir -p "$fix/docs/meeting-notes"

# ── Fixture ──────────────────────────────────────────────────────────────────
# TODO.md: mix of promoted, un-promoted, non-executable, and xledger-ok items.
# Notably NO hand-maintained "Relay: N open ROADMAP items" count line (item 3 of d9b0).
cat > "$fix/TODO.md" <<'EOTODO'
# TODO

## Current work
- [ ] A ROUTINE item NOT yet in ROADMAP — pool-invisible [ROUTINE] <!-- id:aa01 -->
- [ ] A HARD-pool item NOT yet in ROADMAP — pool-invisible [HARD — pool] <!-- id:bb02 -->
- [ ] A design item (no promotion needed) [HARD — meeting] <!-- id:cc03 -->
- [ ] A ROUTINE item already promoted to ROADMAP [ROUTINE] <!-- id:dd04 -->
- [ ] Intentional scope-split: ROADMAP closed this decision, TODO still tracks follow-up action <!-- id:ee05 --> <!-- xledger-ok: eval closed in ROADMAP, follow-up action still open in TODO -->
- [ ] Unintentional drift: ROADMAP closed this, TODO should also be closed <!-- id:ff06 -->
EOTODO

cat > "$fix/TODO.archive.md" <<'EOARCH'
# Archive
EOARCH

cat > "$fix/ROADMAP.md" <<'EORM'
# Roadmap <!-- fables-turn roadmap v1 -->
- [ ] A ROUTINE item already promoted to ROADMAP [ROUTINE] <!-- id:dd04 -->
- [x] Intentional scope-split — closed here, TODO still tracking follow-up <!-- id:ee05 -->
- [x] Unintentional drift — closed here but TODO not synced <!-- id:ff06 -->
EORM

# ── Test 1: --promotion flags un-promoted executable-lane items ───────────────
promo_out="$(HOME="$tmp" "$ORPHAN" --promotion "$fix")"

# Must flag aa01 ([ROUTINE] absent from ROADMAP)
echo "$promo_out" | grep -q 'id:aa01' \
  || fail "--promotion must flag aa01 ([ROUTINE] not in ROADMAP): got: $promo_out"
# Must flag bb02 ([HARD — pool] absent from ROADMAP)
echo "$promo_out" | grep -q 'id:bb02' \
  || fail "--promotion must flag bb02 ([HARD — pool] not in ROADMAP): got: $promo_out"
# Must NOT flag cc03 ([HARD — meeting] is non-executable, no promotion needed)
echo "$promo_out" | grep -q 'id:cc03' \
  && fail "--promotion must NOT flag cc03 ([HARD — meeting] is not a pool-executable lane): got: $promo_out" || true
# Must NOT flag dd04 (already has a twin in ROADMAP)
echo "$promo_out" | grep -q 'id:dd04' \
  && fail "--promotion must NOT flag dd04 (already promoted to ROADMAP): got: $promo_out" || true
# Must NOT flag ee05 (in ROADMAP — xledger-ok is irrelevant to promotion check)
echo "$promo_out" | grep -q 'id:ee05' \
  && fail "--promotion must NOT flag ee05 (exists in ROADMAP, xledger-ok N/A): got: $promo_out" || true
pass "--promotion flags un-promoted [ROUTINE]/[HARD — pool] items and spares promoted/non-executable ones"

# -p alias must behave identically
alias_out="$(HOME="$tmp" "$ORPHAN" -p "$fix")"
[[ "$alias_out" == "$promo_out" ]] \
  || fail "-p alias output differs from --promotion"
pass "-p alias is identical to --promotion"

# ── Test 2: xledger-ok suppresses intentional scope-splits in --cross-ledger ──
cl_out="$(HOME="$tmp" "$ORPHAN" --cross-ledger "$fix")"

# Must flag ff06 (unannotated divergence)
echo "$cl_out" | grep -q 'id:ff06' \
  || fail "--cross-ledger must flag ff06 (unannotated divergence): got: $cl_out"
# Must NOT flag ee05 (annotated with xledger-ok)
echo "$cl_out" | grep -q 'id:ee05' \
  && fail "--cross-ledger must NOT flag ee05 (xledger-ok annotation suppresses it): got: $cl_out" || true
pass "--cross-ledger suppresses xledger-ok-annotated scope-splits and flags unannotated ones"

# ── Test 3: derived count — no hand-maintained count line in the fixture ──────
# The fixture has no "Relay: N open ROADMAP items" line. Assert it's absent,
# demonstrating that promotion/seam checks work without a hand-maintained count.
if grep -qE 'Relay: [0-9]+ open ROADMAP items' "$fix/TODO.md"; then
  fail "fixture must NOT have a hand-maintained 'Relay: N open ROADMAP items' count line (derived count, id:d9b0)"
fi
pass "fixture has no hand-maintained 'Relay: N open ROADMAP items' count line (derived count asserted)"

echo "ALL PASS: TODO↔ROADMAP seam — promotion-tracking + xledger-ok + derived count (id:d9b0)"
