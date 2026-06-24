#!/usr/bin/env bash
# roadmap:9221 — orphan-scan.sh --cross-ledger must key STRICTLY on the
# token-bearing line (the line carrying <!-- id:XXXX -->). It must NOT
# be confused by:
#   (a) the same token appearing on a DIFFERENT line in TODO.archive.md
#       (a reused/recycled id that was closed, then reused for a new open item)
#   (b) the same token referenced in prose on other checkbox lines
#
# False-positive scenario (from dogfooding relay-doctor --all on isochrone):
#   TODO.md:          - [ ] new open item <!-- id:f4a7 -->
#   TODO.archive.md:  - [x] old archived item <!-- id:f4a7 -->  ← SAME token, different item
#   ROADMAP.md:       - [ ] open item <!-- id:f4a7 -->
# Result WITHOUT fix: todo_state[f4a7] = 'x' (archive overwrites TODO.md), ROADMAP = ' '
#   → false DRIFT: "TODO:[x] ROADMAP:[ ]"
# Result WITH fix:  todo_state[f4a7] = ' ' (first/active wins), ROADMAP = ' '
#   → CLEAN (correct)
#
# Genuine drift scenario (must still be caught):
#   TODO.md:    - [ ] open item <!-- id:abcd -->
#   ROADMAP.md: - [x] done in roadmap <!-- id:abcd -->
#   → DRIFT: "TODO:[ ] ROADMAP:[x]" (correct)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORPHAN="$ROOT/meeting/orphan-scan.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fix="$tmp/repo"
mkdir -p "$fix/docs/meeting-notes"

# --- Scenario (a): same token in TODO.md (open) and TODO.archive.md (closed)
# The primary/active line in TODO.md is the authoritative state.
# When both agree with ROADMAP, must report CLEAN.
cat > "$fix/TODO.md" <<'EOF'
# TODO
## Current
- [ ] new open item <!-- id:aa11 -->
- [ ] another open item, closed in roadmap <!-- id:bb22 -->
EOF
cat > "$fix/TODO.archive.md" <<'EOF'
# Archive
- [x] old archived item that was closed — same token as new open item above <!-- id:aa11 -->
EOF
cat > "$fix/ROADMAP.md" <<'EOF'
# Roadmap
## Items
- [ ] new open item [ROUTINE] <!-- id:aa11 -->
- [x] done item [ROUTINE] <!-- id:bb22 -->
EOF

out="$(HOME="$tmp" "$ORPHAN" --cross-ledger "$fix")"

# aa11: TODO.md says [ ], ROADMAP says [ ] — AGREE. archive's [x] is the OLD item.
# Must NOT flag aa11 as drift.
if grep -q 'id:aa11' <<<"$out"; then
  echo "FAIL: must NOT flag id:aa11 — TODO.md (active/first) is [ ], ROADMAP is [ ]; archive's [x] is a different archived item"
  echo "got: $out"
  exit 1
fi
echo "PASS: id:aa11 not flagged — active TODO.md wins over archive (scenario a)"

# bb22: TODO.md says [ ], ROADMAP says [x] — DISAGREE. Must flag.
if ! grep -q 'id:bb22' <<<"$out"; then
  echo "FAIL: must flag id:bb22 — genuine drift (TODO:[ ] ROADMAP:[x])"
  echo "got: $out"
  exit 1
fi
echo "PASS: id:bb22 flagged — genuine drift still caught"

# --- Scenario (b): token appears in prose on other checkbox lines
# The prose references must not affect the state attribution of the primary line.
rm -f "$fix/TODO.md" "$fix/TODO.archive.md" "$fix/ROADMAP.md"
cat > "$fix/TODO.md" <<'EOF'
# TODO
## Current
- [ ] main item with children <!-- id:cc33 -->
- [ ] child A (see id:cc33 parent) — own id <!-- id:cc33a -->
- [x] child B (see id:cc33 parent) — own id, done <!-- id:cc33b -->
EOF
cat > "$fix/TODO.archive.md" <<'EOF'
# Archive
EOF
cat > "$fix/ROADMAP.md" <<'EOF'
# Roadmap
## Items
- [ ] main item with children [ROUTINE] <!-- id:cc33 -->
- [ ] child A [ROUTINE] (DEP: id:cc33) <!-- id:cc33a -->
- [x] child B done [ROUTINE] <!-- id:cc33b -->
EOF

out2="$(HOME="$tmp" "$ORPHAN" --cross-ledger "$fix")"

# cc33: TODO.md says [ ], ROADMAP says [ ] — AGREE.
# Prose references on child lines must not confuse the primary state.
if grep -q 'id:cc33[^ab]' <<<"$out2" || grep -qE 'id:cc33 ' <<<"$out2"; then
  # only flag if 'id:cc33' appears NOT as 'id:cc33a' or 'id:cc33b'
  # simpler: the exact token cc33 (4 hex chars) in the output
  true  # we'll check explicitly below
fi
# The 4-hex token is 'cc33' — check it's not flagged
if echo "$out2" | grep -qE 'id:cc33[^0-9a-f]|id:cc33$'; then
  echo "FAIL: must NOT flag id:cc33 — primary lines agree ([ ] in both ledgers)"
  echo "got: $out2"
  exit 1
fi
echo "PASS: id:cc33 not flagged — prose references on sibling lines do not affect primary token state (scenario b)"

# cc33a: both [ ] — AGREE; cc33b: both [x] — AGREE. Neither should be flagged.
for tk in cc33a cc33b; do
  if echo "$out2" | grep -q "id:$tk"; then
    echo "FAIL: must NOT flag id:$tk — states agree in both ledgers"
    echo "got: $out2"
    exit 1
  fi
done
echo "PASS: id:cc33a and id:cc33b not flagged — states agree"

# --- Scenario (c): original cross-ledger cases still work correctly
rm -f "$fix/TODO.md" "$fix/TODO.archive.md" "$fix/ROADMAP.md"
cat > "$fix/TODO.md" <<'EOF'
# TODO
- [ ] open in todo, closed in roadmap <!-- id:1111 -->
- [ ] open in both ledgers <!-- id:2222 -->
EOF
cat > "$fix/TODO.archive.md" <<'EOF'
# Archive
- [x] archived, also done in roadmap <!-- id:6666 -->
EOF
cat > "$fix/ROADMAP.md" <<'EOF'
# Roadmap
- [x] open in todo, closed in roadmap [ROUTINE] <!-- id:1111 -->
- [ ] open in both ledgers [ROUTINE] <!-- id:2222 -->
- [x] archived, also done in roadmap [ROUTINE] <!-- id:6666 -->
EOF

out3="$(HOME="$tmp" "$ORPHAN" --cross-ledger "$fix")"

# 1111: TODO=[ ], ROADMAP=[x] → must flag
if ! grep -q 'id:1111' <<<"$out3"; then
  echo "FAIL: id:1111 must still be flagged (genuine drift)"
  echo "got: $out3"
  exit 1
fi
# 2222 and 6666 agree → must NOT flag
for tk in 2222 6666; do
  if grep -q "id:$tk" <<<"$out3"; then
    echo "FAIL: id:$tk must NOT be flagged (states agree)"
    echo "got: $out3"
    exit 1
  fi
done
echo "PASS: existing cross-ledger cases still work (1111 flagged, 2222/6666 clean)"

echo "ALL PASS: id:9221 orphan-scan --cross-ledger strict token-line keying"
