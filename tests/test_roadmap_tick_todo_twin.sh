#!/usr/bin/env bash
# Defect-fix test — no `# roadmap:` header on purpose (its failures always count).
#
# DEFECT: the single-id-two-views invariant (an id present in BOTH TODO.md and ROADMAP.md
# keeps a CONSISTENT checkbox) lost its mechanical owner when contract-v12 moved the
# execute child's ROADMAP tick into the driver. `integrate.sh` and `roadmap-tick.sh` both
# contained ZERO occurrences of "TODO.md"; the only surviving "tick the TODO twin too"
# instruction lived in an LLM prompt (relay-loop.js's review child), which `--exclude review`
# can disable. Live consequence: id:e68f/bc2b/b018/4a76 all drifted to TODO:[ ] ROADMAP:[x].
#
# FIX: roadmap-tick.sh — the script that already owns the ROADMAP tick — now also ticks the
# id's TODO.md twin when one exists, through the flock'd meeting/md-merge.py (never a
# hand-rolled sed on a shared non-union ledger), anchored on the id MARKER (never a bare
# token), and LOUD on a real failure.
#
#   1. Twin present: ROADMAP [ ] + TODO [ ] → BOTH flip.
#   2. Twin absent (TODO.md exists, no such id) → clean no-op, exit 0, TODO byte-identical.
#   3. No TODO.md at all → clean no-op, exit 0.
#   4. Mid-line marker with trailing prose (cf. id:a955) → flips, prose preserved.
#   5. Repair path: ROADMAP already [x], TODO still [ ] → TODO converges.
#   6. id:e166 guard: after the write the marker still sits on a line STARTING with a
#      checkbox (a multi-line `--append` payload is what moved it off before).
#   7. Bare-token prose mention of another id (cf. id:c97c) is never mistaken for a twin.
#   8. Already-ticked twin is idempotent; unrelated TODO items are never touched.
# fails-against: rev 67d526b6c470 -- the tree as it stood immediately before the commit that
#   added this test, i.e. the pre-fix relay/scripts/roadmap-tick.sh. Derived + verified by tests/verify-negative-cases.py.
# fails-against-rev: 67d526b6c470 -- relay/scripts/roadmap-tick.sh
# fails-against-assertion: T1: TODO twin id:aaaa not ticked

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/relay/scripts/roadmap-tick.sh"

pass() { printf 'PASS: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*"; exit 1; }

[[ -x "$SCRIPT" ]] || fail "roadmap-tick.sh not found/executable at $SCRIPT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# ── Test 1: twin present — both ledgers flip ──
r1="$tmp/r1"; mkdir -p "$r1"
cat > "$r1/ROADMAP.md" <<'EOF'
# Roadmap

- [ ] Do the thing [ROUTINE] <!-- id:aaaa -->
  - **Acceptance**: it works.
EOF
cat > "$r1/TODO.md" <<'EOF'
# TODO

## Current

- [ ] Do the thing (design rationale) <!-- id:aaaa -->
- [ ] Unrelated item <!-- id:bbbb -->
EOF
bash "$SCRIPT" "$r1" "aaaa" >/dev/null
grep -q '^- \[x\] Do the thing \[ROUTINE\] <!-- id:aaaa -->' "$r1/ROADMAP.md" \
    || fail "T1: ROADMAP id:aaaa not ticked"
grep -q '^- \[x\] Do the thing (design rationale) <!-- id:aaaa -->' "$r1/TODO.md" \
    || fail "T1: TODO twin id:aaaa not ticked"
grep -q '^- \[ \] Unrelated item <!-- id:bbbb -->' "$r1/TODO.md" \
    || fail "T1: unrelated TODO item id:bbbb wrongly touched"
pass "T1: twin present — ROADMAP and TODO both flip, siblings untouched"

# ── Test 2: twin ABSENT is a clean no-op (normal case, e.g. id:087b) ──
r2="$tmp/r2"; mkdir -p "$r2"
cat > "$r2/ROADMAP.md" <<'EOF'
# Roadmap

- [ ] Roadmap-only item <!-- id:cccc -->
EOF
cat > "$r2/TODO.md" <<'EOF'
# TODO

- [ ] Something else entirely <!-- id:dddd -->
EOF
before2="$(cat "$r2/TODO.md")"
bash "$SCRIPT" "$r2" "cccc" >/dev/null || fail "T2: missing twin exited non-zero"
grep -q '^- \[x\] Roadmap-only item <!-- id:cccc -->' "$r2/ROADMAP.md" \
    || fail "T2: ROADMAP id:cccc not ticked"
[[ "$before2" == "$(cat "$r2/TODO.md")" ]] || fail "T2: TODO.md changed though no twin exists"
pass "T2: absent twin is a clean no-op, exit 0, TODO byte-identical"

# ── Test 3: no TODO.md at all ──
r3="$tmp/r3"; mkdir -p "$r3"
cat > "$r3/ROADMAP.md" <<'EOF'
# Roadmap

- [ ] Lonely item <!-- id:eeee -->
EOF
bash "$SCRIPT" "$r3" "eeee" >/dev/null || fail "T3: missing TODO.md exited non-zero"
[[ ! -e "$r3/TODO.md" ]] || fail "T3: roadmap-tick CREATED a TODO.md"
grep -q '^- \[x\] Lonely item <!-- id:eeee -->' "$r3/ROADMAP.md" || fail "T3: ROADMAP not ticked"
pass "T3: no TODO.md is a clean no-op (nothing created)"

# ── Test 4: MID-line marker with trailing prose (cf. id:a955) ──
r4="$tmp/r4"; mkdir -p "$r4"
cat > "$r4/ROADMAP.md" <<'EOF'
# Roadmap

- [ ] Mid-marker item <!-- id:a955 --> — extra prose after the marker
EOF
cat > "$r4/TODO.md" <<'EOF'
# TODO

- [ ] Mid-marker item <!-- id:a955 --> — trailing rationale prose (2026-08-21)
EOF
bash "$SCRIPT" "$r4" "a955" >/dev/null
grep -q '^- \[x\] Mid-marker item <!-- id:a955 --> — trailing rationale prose (2026-08-21)$' \
    "$r4/TODO.md" || fail "T4: mid-line-marker TODO twin not ticked verbatim"
pass "T4: mid-line marker with trailing prose flips, prose preserved byte-for-byte"

# ── Test 5: repair path — ROADMAP already [x], TODO still [ ] ──
r5="$tmp/r5"; mkdir -p "$r5"
cat > "$r5/ROADMAP.md" <<'EOF'
# Roadmap

- [x] Already shipped <!-- id:1234 -->
EOF
cat > "$r5/TODO.md" <<'EOF'
# TODO

- [ ] Already shipped (drifted twin) <!-- id:1234 -->
EOF
bash "$SCRIPT" "$r5" "1234" >/dev/null || fail "T5: repair path exited non-zero"
grep -q '^- \[x\] Already shipped (drifted twin) <!-- id:1234 -->' "$r5/TODO.md" \
    || fail "T5: drifted TODO twin not converged to [x]"
pass "T5: an already-[x] ROADMAP item still converges its drifted TODO twin"

# ── Test 6: id:e166 guard — the marker stays ON a checkbox-leading line ──
# run-tests.sh's item_open() reads the checkbox at line start; a payload that moves the
# marker onto a continuation line silently breaks expected-red accounting.
awk '/<!-- id:1234 -->/ { if ($0 !~ /^- \[[ xX]\]/) { print "MOVED"; exit 1 } }' "$r5/TODO.md" \
    || fail "T6: id marker no longer sits on a line starting with a checkbox"
[[ "$(grep -c '<!-- id:1234 -->' "$r5/TODO.md")" -eq 1 ]] \
    || fail "T6: id:1234 marker duplicated in TODO.md"
pass "T6: id:e166 guard — marker still on a checkbox-leading line, exactly one copy"

# ── Test 7: a bare-token prose mention (cf. id:c97c) is not a twin ──
r7="$tmp/r7"; mkdir -p "$r7"
cat > "$r7/ROADMAP.md" <<'EOF'
# Roadmap

- [ ] Real item <!-- id:5678 -->
EOF
cat > "$r7/TODO.md" <<'EOF'
# TODO

- [ ] A different item that merely mentions id:5678 in prose <!-- id:9abc -->
EOF
before7="$(cat "$r7/TODO.md")"
bash "$SCRIPT" "$r7" "5678" >/dev/null || fail "T7: exited non-zero"
[[ "$before7" == "$(cat "$r7/TODO.md")" ]] \
    || fail "T7: a bare-token prose mention of id:5678 was ticked as its twin"
pass "T7: bare-token prose mention is never mistaken for the id's own twin"

# ── Test 8: idempotent re-run over an already-converged pair ──
bash "$SCRIPT" "$r1" "aaaa" >/dev/null || fail "T8: re-run exited non-zero"
n=$(grep -c '^- \[x\] Do the thing (design rationale) <!-- id:aaaa -->' "$r1/TODO.md")
[[ "$n" -eq 1 ]] || fail "T8: re-run produced $n twin lines (expected 1)"
grep -q '^- \[ \] Unrelated item <!-- id:bbbb -->' "$r1/TODO.md" \
    || fail "T8: re-run touched an unrelated item"
pass "T8: re-running over a converged pair is idempotent"

echo "ok"
