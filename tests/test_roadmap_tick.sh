#!/usr/bin/env bash
# roadmap:5b12 — Driver-side ROADMAP checkbox tick (roadmap-tick.sh).
# Under the one-writer integrator model (id:ae08/5b12), execute/hard children no longer
# tick their own checkbox; the integrator ticks from the returned worked_ids. This tests
# the mechanical tick helper hermetically (mktemp only; no ~/.claude/network mutation).
#   1. Single id: an open "- [ ] … id:X" line flips to "- [x]".
#   2. Multiple ids (CSV): each named open item flips; unnamed open items are LEFT.
#   3. Idempotent: re-running on an already-ticked id is a clean no-op (still [x], one copy).
#   4. Absent id: an id with no open checkbox line is a no-op, exit 0, file unchanged.
#   5. Body preserved: the item's Acceptance/sub-bullet lines are byte-identical after tick.
#   6. Only the FIRST open line per id is flipped; a "gated-on:X"/"children-of:X" ref line
#      (no literal "id:X") is never mistaken for the item's own checkbox.
#   7. No worked ids / no ROADMAP: clean no-op exit 0.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/relay/scripts/roadmap-tick.sh"

pass() { printf 'PASS: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*"; exit 1; }

[[ -x "$SCRIPT" ]] || fail "roadmap-tick.sh not found/executable at $SCRIPT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# ── Test 1: single id flips its open checkbox ──
r1="$tmp/r1"; mkdir -p "$r1"
cat > "$r1/ROADMAP.md" <<'EOF'
# Roadmap

## Current

- [ ] First item [ROUTINE] <!-- id:aaaa -->
  - **Acceptance**: does the thing.
- [ ] Second item [HARD] <!-- id:bbbb -->
EOF
bash "$SCRIPT" "$r1" "aaaa" >/dev/null
grep -q '^- \[x\] First item .* <!-- id:aaaa -->' "$r1/ROADMAP.md" || fail "T1: id:aaaa not ticked"
grep -q '^- \[ \] Second item .* <!-- id:bbbb -->' "$r1/ROADMAP.md" || fail "T1: id:bbbb wrongly touched"
pass "T1: single id ticks only its own open checkbox"

# ── Test 2: CSV of multiple ids ──
r2="$tmp/r2"; mkdir -p "$r2"
cat > "$r2/ROADMAP.md" <<'EOF'
# Roadmap

- [ ] Item A <!-- id:1111 -->
- [ ] Item B <!-- id:2222 -->
- [ ] Item C <!-- id:3333 -->
EOF
bash "$SCRIPT" "$r2" "1111,3333" >/dev/null
grep -q '^- \[x\] Item A <!-- id:1111 -->' "$r2/ROADMAP.md" || fail "T2: id:1111 not ticked"
grep -q '^- \[ \] Item B <!-- id:2222 -->' "$r2/ROADMAP.md" || fail "T2: id:2222 wrongly ticked"
grep -q '^- \[x\] Item C <!-- id:3333 -->' "$r2/ROADMAP.md" || fail "T2: id:3333 not ticked"
pass "T2: CSV ticks each named item, leaves the rest"

# ── Test 3: idempotent re-run ──
bash "$SCRIPT" "$r2" "1111" >/dev/null
n=$(grep -c '^- \[x\] Item A <!-- id:1111 -->' "$r2/ROADMAP.md")
[[ "$n" -eq 1 ]] || fail "T3: re-tick produced $n lines (expected 1)"
pass "T3: re-running on an already-ticked id is idempotent"

# ── Test 4: absent id is a clean no-op ──
r4="$tmp/r4"; mkdir -p "$r4"
cat > "$r4/ROADMAP.md" <<'EOF'
# Roadmap

- [ ] Only item <!-- id:cccc -->
EOF
before=$(cat "$r4/ROADMAP.md")
bash "$SCRIPT" "$r4" "dead" >/dev/null || fail "T4: absent id exited non-zero"
after=$(cat "$r4/ROADMAP.md")
[[ "$before" == "$after" ]] || fail "T4: file changed on absent id"
pass "T4: absent id is a no-op, exit 0, file unchanged"

# ── Test 5: item body preserved byte-identical (only checkbox char changes) ──
r5="$tmp/r5"; mkdir -p "$r5"
cat > "$r5/ROADMAP.md" <<'EOF'
# Roadmap

- [ ] Body item <!-- id:dddd -->
  - **Acceptance**: line one.
  - **Done-check**: `tests/run-tests.sh tests/test_x.sh`
  - **Context**: relay/scripts/x.sh
EOF
bash "$SCRIPT" "$r5" "dddd" >/dev/null
grep -q '  - \*\*Acceptance\*\*: line one.' "$r5/ROADMAP.md" || fail "T5: Acceptance body altered"
grep -q '  - \*\*Done-check\*\*: `tests/run-tests.sh tests/test_x.sh`' "$r5/ROADMAP.md" || fail "T5: Done-check body altered"
grep -q '  - \*\*Context\*\*: relay/scripts/x.sh' "$r5/ROADMAP.md" || fail "T5: Context body altered"
grep -q '^- \[x\] Body item <!-- id:dddd -->' "$r5/ROADMAP.md" || fail "T5: checkbox not flipped"
pass "T5: item body preserved; only the checkbox char changes"

# ── Test 6: a reference line (gated-on:/children-of:) is never mistaken for the item ──
r6="$tmp/r6"; mkdir -p "$r6"
cat > "$r6/ROADMAP.md" <<'EOF'
# Roadmap

- [ ] Real item <!-- gated-on:eeee --> <!-- id:ffff -->
- [ ] Other item <!-- children-of:ffff --> <!-- id:9999 -->
EOF
bash "$SCRIPT" "$r6" "ffff" >/dev/null
grep -q '^- \[x\] Real item .* <!-- id:ffff -->' "$r6/ROADMAP.md" || fail "T6: id:ffff own item not ticked"
grep -q '^- \[ \] Other item .* <!-- id:9999 -->' "$r6/ROADMAP.md" || fail "T6: children-of:ffff line wrongly ticked"
pass "T6: reference tokens (gated-on/children-of) never match as the item's own id"

# ── Test 7: no ids / no ROADMAP is a clean no-op ──
bash "$SCRIPT" "$r6" "" >/dev/null 2>&1 || fail "T7: empty ids exited non-zero"
r7="$tmp/r7"; mkdir -p "$r7"
bash "$SCRIPT" "$r7" "aaaa" >/dev/null 2>&1 || fail "T7: missing ROADMAP exited non-zero"
pass "T7: empty ids and missing ROADMAP are clean no-ops"

echo "ok"
