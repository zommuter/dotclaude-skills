#!/usr/bin/env bash
# DEFECT-FIX test — no `# roadmap:XXXX` header on purpose: this is the third instance of
# the routed:42c9 / routed:8b21 ARCHIVE-BLINDNESS class found by surveying every ledger
# scanner, and it has no ROADMAP item of its own. Failures here always count.
#
# `resolve-gates.sh` builds its id:46f6 resolution map over
#   ROADMAP.md ∪ TODO.md ∪ TODO.archive.md
# — the ROADMAP side reads no archive. A `gated-on:` target that was a ROADMAP item,
# shipped, and got swept into ROADMAP.archive.md therefore resolves NOWHERE: it is
# reported DANGLING, `classify-repo.sh` records it in `gate_dangling` and screams on
# stderr, when the truth is "target is DONE, gate satisfied".
#
# Fail direction: noise + a misleading "dangling gate target" report, never a stuck
# dispatch (block=1 requires a RESOLVED-and-open target; dangling never sets it). That
# is why this ships with the other two rather than as an incident.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RG="$ROOT/relay/scripts/resolve-gates.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
repo="$tmp/repo"
mkdir -p "$repo"

fail() { echo "FAIL: $*"; echo "--- resolve-gates output ---"; echo "$out"; exit 1; }

cat > "$repo/ROADMAP.md" <<'EOF'
# Roadmap
## Items
- [ ] [ROUTINE] gated on a target that shipped and was archived <!-- gated-on:ff01 --> <!-- id:ff02 -->
- [ ] [ROUTINE] gated on a target that really does not exist <!-- gated-on:ff09 --> <!-- id:ff03 -->
- [ ] [ROUTINE] gated on a still-open live target <!-- gated-on:ff04 --> <!-- id:ff05 -->
- [ ] [ROUTINE] the still-open live gate target <!-- id:ff04 -->
EOF
printf '# TODO\n' > "$repo/TODO.md"

cat > "$repo/ROADMAP.archive.md" <<'EOF'
# Roadmap archive
- [x] [ROUTINE] the gate target, shipped and swept out of the live queue <!-- id:ff01 -->
EOF

out="$("$RG" "$repo")"

# --- Case 1 — THE DEFECT: ff01 is [x] in ROADMAP.archive.md, so ff02's gate is SATISFIED
# and the row must not appear at all (a fully clean edge emits nothing).
grep -q 'ff02' <<<"$out" \
  && fail "ff02 reported — its gate target ff01 is [x] in ROADMAP.archive.md, i.e. SATISFIED, but the resolution map is archive-blind so it reads as dangling"
echo "PASS: a gate target living only in ROADMAP.archive.md resolves as closed"

# --- Case 2 — negative control: a genuinely unresolvable target must STILL be dangling,
# so the fix cannot be a blanket "assume closed".
grep -qP '^ff03\t0\tff09$' <<<"$out" \
  || fail "ff03 not reported as dangling on ff09 — the archive widening swallowed a genuinely dangling gate"
echo "PASS: a genuinely dangling gate target is still reported"

# --- Case 3 — pre-existing block behaviour intact: an OPEN live target still blocks.
grep -qP '^ff05\t1\t' <<<"$out" \
  || fail "ff05 not reported as blocked on the open live target ff04"
echo "PASS: an open live gate target still blocks"

# --- Case 4 — first-wins: the LIVE ROADMAP.md state must beat a recycled token in the
# archive, mirroring the id:9221 rule the TODO side already applies.
repo2="$tmp/repo2"
mkdir -p "$repo2"
cat > "$repo2/ROADMAP.md" <<'EOF'
# Roadmap
- [ ] [ROUTINE] gated on a REOPENED target <!-- gated-on:ab01 --> <!-- id:ab02 -->
- [ ] [ROUTINE] the reopened target, open again in the live queue <!-- id:ab01 -->
EOF
printf '# TODO\n' > "$repo2/TODO.md"
cat > "$repo2/ROADMAP.archive.md" <<'EOF'
# Roadmap archive
- [x] [ROUTINE] an OLD closed item recycling ab01's token <!-- id:ab01 -->
EOF
out="$("$RG" "$repo2")"
grep -qP '^ab02\t1\t' <<<"$out" \
  || fail "ab02 not blocked — a recycled [x] in ROADMAP.archive.md overrode the ACTIVE open ROADMAP.md state (id:9221 first-wins, ROADMAP side)"
echo "PASS: live ROADMAP.md wins over a recycled id in ROADMAP.archive.md"

# --- Case 4b — live-wins in the OTHER direction. Case 4 pins live-[ ] over archive-[x];
# this pins live-[x] over archive-[ ]. Both directions are asserted deliberately: with only
# one, "live wins" would be indistinguishable from an accident of file iteration order, and
# live-vs-archive DISAGREEMENT is precisely the drift routed:42c9 is about. The rule is that
# the LIVE ledger is the current state and an archive entry is history — a token in both is
# either a recycled id or an archived-then-reopened item, and in both readings the live line
# is authoritative. A gate target closed live but open in the archive must NOT block.
repo2b="$tmp/repo2b"
mkdir -p "$repo2b"
cat > "$repo2b/ROADMAP.md" <<'EOF'
# Roadmap
- [ ] [ROUTINE] gated on a target closed in the LIVE queue <!-- gated-on:ad01 --> <!-- id:ad02 -->
- [x] [ROUTINE] the gate target, closed live <!-- id:ad01 -->
EOF
printf '# TODO\n' > "$repo2b/TODO.md"
cat > "$repo2b/ROADMAP.archive.md" <<'EOF'
# Roadmap archive
- [ ] [ROUTINE] an OLD still-open line recycling ad01's token <!-- id:ad01 -->
EOF
out="$("$RG" "$repo2b")"
grep -q 'ad02' <<<"$out" \
  && fail "ad02 reported — an archive-[ ] line overrode the ACTIVE closed ROADMAP.md state; live must win in BOTH directions, not only when live happens to be open"
echo "PASS: live [x] wins over an archive [ ] (live-wins is symmetric, not iteration-order luck)"

# --- Case 5 — a repo with no ROADMAP.archive.md behaves exactly as before.
repo3="$tmp/repo3"
mkdir -p "$repo3"
cat > "$repo3/ROADMAP.md" <<'EOF'
# Roadmap
- [ ] [ROUTINE] gated on nothing that exists <!-- gated-on:ac09 --> <!-- id:ac01 -->
EOF
printf '# TODO\n' > "$repo3/TODO.md"
out="$("$RG" "$repo3")"
grep -qP '^ac01\t0\tac09$' <<<"$out" \
  || fail "ac01 not reported in a repo with no ROADMAP.archive.md — pre-existing behaviour regressed"
echo "PASS: a missing ROADMAP.archive.md is a normal state"

echo "OK: test_resolve_gates_roadmap_archive.sh"
