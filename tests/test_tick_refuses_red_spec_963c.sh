#!/usr/bin/env bash
# roadmap:963c — roadmap-tick.sh must REFUSE (revert + exit non-zero) a tick that would
# turn a `# roadmap:<id>`-headed spec test from EXPECTED-RED into a REAL failure. An
# executor's own `worked_ids` self-report is untrusted; the guard re-verifies against the
# item's own spec, mechanically, via the repo's OWN tests/run-tests.sh (never a second
# reimplementation of its expected-red mapping).
#
# Builds a hermetic fixture repo (mktemp only) with:
#   - a minimal tests/run-tests.sh reproducing the real one's item_open()+expected-red
#     exit-code contract (0 = no real failures; 1 = at least one real failure) — the
#     narrow slice roadmap-tick.sh actually depends on, not the full parallel/hermeticity
#     harness, which is orthogonal to what this test verifies.
#   - one open [ROUTINE] item (id:dead) whose `# roadmap:dead` spec test FAILS
#     unconditionally (i.e. still fails even once the item is ticked) — ticking it must be
#     REFUSED and reverted.
#   - one open [ROUTINE] item (id:cafe) whose `# roadmap:cafe` spec test PASSES —
#     ticking it must succeed normally.
#   - one open [ROUTINE] item (id:beef) with NO spec test at all — ticking it must be
#     completely unaffected by this guard (byte-identical to pre-963c behaviour).
#   - ids are 4-hex tokens (roadmap-tick.sh's own well-formedness gate rejects anything else).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/relay/scripts/roadmap-tick.sh"

pass() { printf 'PASS: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*"; exit 1; }

[[ -x "$SCRIPT" ]] || fail "roadmap-tick.sh not found/executable at $SCRIPT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

repo="$tmp/fixture"
mkdir -p "$repo/tests"

cat > "$repo/ROADMAP.md" <<'EOF'
# Roadmap

- [ ] Item that must stay red [ROUTINE] <!-- id:dead -->
- [ ] Item that verifies clean [ROUTINE] <!-- id:cafe -->
- [ ] Item with no spec test [ROUTINE] <!-- id:beef -->
EOF

# Minimal, faithful slice of the real tests/run-tests.sh: same `# roadmap:XXXX` /
# item_open() / expected-red exit-code contract, none of the parallelism, duration-cache
# or hermeticity-snapshot machinery (irrelevant to what roadmap-tick.sh calls out for).
cat > "$repo/tests/run-tests.sh" <<'RUNNER'
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROADMAP="$ROOT/ROADMAP.md"
item_open() {
  local token="$1"
  [[ -f "$ROADMAP" ]] || return 1
  grep -qE "^- \[ \] .*<!-- id:${token} -->" "$ROADMAP"
}
fail=0
for f in "$@"; do
  name="$(basename "$f")"
  token="$(head -1 < <(grep -oE '# roadmap:[0-9a-fA-F]{4}' "$f") | sed 's/.*roadmap://')" || true
  out="$(bash "$f" 2>&1)"; rc=$?
  if [[ "$rc" == 0 ]]; then
    echo "PASS $name"
  else
    if [[ -n "${token:-}" ]] && item_open "$token"; then
      echo "EXPECTED-RED $name"
    else
      echo "FAIL $name"
      printf '%s\n' "$out"
      fail=1
    fi
  fi
done
exit "$fail"
RUNNER
chmod +x "$repo/tests/run-tests.sh"

cat > "$repo/tests/test_dead_963c.sh" <<'EOF'
#!/usr/bin/env bash
# roadmap:dead — deliberately fails unconditionally (this is the fixture's whole point).
echo "asserting something that is still false"
exit 1
EOF

cat > "$repo/tests/test_cafe_963c.sh" <<'EOF'
#!/usr/bin/env bash
# roadmap:cafe — deliberately passes.
exit 0
EOF

# ── Test 1: an id whose spec test is still RED after ticking is REFUSED and reverted ──
if bash "$SCRIPT" "$repo" "dead" >"$tmp/out1" 2>&1; then
  fail "T1: roadmap-tick.sh exited 0 ticking id:dead — expected a non-zero refusal"
fi
grep -q '^- \[ \] Item that must stay red .* <!-- id:dead -->' "$repo/ROADMAP.md" \
  || fail "T1: id:dead checkbox was not reverted to open"
grep -qi 'REFUSED' "$tmp/out1" || fail "T1: refusal was not LOUD (no REFUSED in output)"
grep -q 'dead' "$tmp/out1" || fail "T1: refusal message did not name id:dead"
grep -q 'test_dead_963c.sh' "$tmp/out1" || fail "T1: refusal message did not name the spec test file"
pass "T1: a still-red spec after ticking is REFUSED, checkbox reverted, and LOUD"

# ── Test 2: an id whose spec test passes ticks normally ──
bash "$SCRIPT" "$repo" "cafe" >"$tmp/out2" 2>&1 || fail "T2: roadmap-tick.sh exited non-zero ticking id:cafe"
grep -q '^- \[x\] Item that verifies clean .* <!-- id:cafe -->' "$repo/ROADMAP.md" \
  || fail "T2: id:cafe was not ticked"
pass "T2: an id whose spec test is green ticks normally"

# ── Test 3: an id with no spec test at all is completely unaffected by the guard ──
bash "$SCRIPT" "$repo" "beef" >"$tmp/out3" 2>&1 || fail "T3: roadmap-tick.sh exited non-zero ticking id:beef"
grep -q '^- \[x\] Item with no spec test .* <!-- id:beef -->' "$repo/ROADMAP.md" \
  || fail "T3: id:beef was not ticked"
pass "T3: an id with no spec test ticks normally, unaffected by the guard"

# ── Test 4: a batch CSV mixing a red and a clean id refuses only the red one, ticks the
#    other, and still exits non-zero overall (the batch-level signal integrate.sh reads).
r4="$tmp/fixture2"; mkdir -p "$r4/tests"
cp "$repo/tests/run-tests.sh" "$r4/tests/run-tests.sh"
chmod +x "$r4/tests/run-tests.sh"
cp "$repo/tests/test_dead_963c.sh" "$r4/tests/"
cat > "$r4/tests/test_1234_963c.sh" <<'EOF'
#!/usr/bin/env bash
# roadmap:1234
exit 0
EOF
cat > "$r4/ROADMAP.md" <<'EOF'
# Roadmap

- [ ] Still red [ROUTINE] <!-- id:dead -->
- [ ] Clean [ROUTINE] <!-- id:1234 -->
EOF
if bash "$SCRIPT" "$r4" "dead,1234" >"$tmp/out4" 2>&1; then
  fail "T4: batch tick exited 0 despite one refused id"
fi
grep -q '^- \[ \] Still red .* <!-- id:dead -->' "$r4/ROADMAP.md" || fail "T4: id:dead not reverted in batch"
grep -q '^- \[x\] Clean .* <!-- id:1234 -->' "$r4/ROADMAP.md" || fail "T4: id:1234 not ticked in batch"
pass "T4: a batch refuses only the red id, ticks the clean one, exits non-zero overall"

echo "ok"
