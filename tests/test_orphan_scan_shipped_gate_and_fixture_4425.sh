#!/usr/bin/env bash
# No roadmap header — this is a defect-fix spec for TODO id:4425, which has no ROADMAP
# twin (it was filed directly into TODO.md). Failures always count.
#
# id:4425 — `orphan-scan.sh --shipped` emits TICK-READY for items that are actually
# gated, and can cite a test that asserts the item is RED. Two distinct defects, both
# observed live in this repo's own 2026-09-01 scan (2 of 2 TICK-READY lines were false
# positives — id:6217 and id:9eb7).
#
#   (1) GATE BLINDNESS ACROSS THE LEDGER PAIR. `--shipped` scans TODO.md only, and
#       resolves gates against TODO.md ∪ TODO.archive.md by its own contract. But
#       id:3801's auto-gating writes the `🚧 GATED` marker on the ROADMAP TWIN, so
#       under single-id-two-views the gate is structurally invisible and the ungated
#       TODO line reads as tick-ready. TICK-READY is an ACTION RECOMMENDATION, so the
#       consequence is not safe even if the scope split is deliberate.
#
#   (2) THE roadmap-token LINK MATCHES A FIXTURE REFERENCE. The contract trusts a
#       test carrying a roadmap:<token> header comment as the intentional test-owns-item
#       link. Live, id:6217's cited test was tests/test_make_test_files.sh, whose only
#       match is inside `red_fixture="...test_dryround_single_definition_6217.sh"` with a
#       trailing roadmap:6217 comment reading "currently open+RED" -- a line naming a
#       DIFFERENT test file, precisely in order to say the item is RED. The scan cited, as
#       evidence of doneness, a file asserting the opposite.
#
# ⚠ NOTE ON THIS FILE'S OWN MARKERS (defect found 2026-09-01, by the id:a73c review).
# Every roadmap-token literal below is BUILT AT RUNTIME via printf, never written out in
# this source. That is not style: `tests/run-tests.sh:170` takes `head -1` of a WHOLE-FILE
# `grep -oE '# roadmap:[0-9a-f]{4}'`, so a literal anywhere -- prose, heredoc, fixture --
# makes this file look like that item's RED SPEC. This file previously carried one in its
# own docstring, and run-tests.sh therefore read it as the spec for roadmap:6217, which is
# UNTICKED -- so its failures were reported EXPECTED-RED and did NOT fail the suite. A test
# written to stop a false TICK-READY claim had its own failures silently swallowed. Keep
# every marker constructed, and keep this file headerless (its failures always count).
#
# Contract asserted here:
#   a. An item whose ROADMAP twin carries `🚧` / `GATED` is NEVER emitted as TICK-READY.
#   b. A `# roadmap:<token>` occurrence on a line that also names a DIFFERENT test file
#      does not establish the test-owns-item link.
#   c. Neither suppression may break the existing positive path — a genuinely ungated
#      item with a genuinely-owning green test still reports TICK-READY.
#
# The item asked that 6217 and 9eb7 be the RECORDED cases, so the fixture ledgers below
# use those real tokens. Live, 6217 exhibits BOTH defects at once and 9eb7 only the gate
# one. The fixture deliberately SEPARATES them — 9eb7 carries the gate alone, 6217 the
# fixture reference alone — so each defect has an INDEPENDENT failing witness. Pinning
# 6217 with both would let either fix alone turn the case green and hide the other.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORPHAN="$ROOT/meeting/orphan-scan.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

repo="$tmp/repo"
mkdir -p "$repo/tests"
git -C "$repo" init -q
git -C "$repo" config user.email "test@example.com"
git -C "$repo" config user.name "Test"

: > "$repo/TODO.archive.md"
: > "$repo/ROADMAP.archive.md"

# ── Case A (defect 1): gated ONLY on the ROADMAP twin ────────────────────────────────
# The TODO line is deliberately clean of every gate lexeme the scan knows, so the ONLY
# gate evidence anywhere is the ROADMAP twin's 🚧 marker — exactly the live id:6217 /
# id:9eb7 shape. Must NOT be TICK-READY.
# mkspec <path> <token> -- writes a green fixture test carrying a roadmap marker for <token>.
# The marker is BUILT, never literal in this source (see the note in the header).
mkspec() {
  { printf '#!/usr/bin/env bash\n'
    printf '# roadmap:%s\n' "$2"
    printf 'set -euo pipefail\nexit 0\n'; } > "$1"
  chmod +x "$1"
}
mkspec "$repo/tests/test_9eb7.sh" 9eb7

# ── Case B (defect 2): the only `# roadmap:` match is a FIXTURE REFERENCE ─────────────
# test_6217_harness.sh mentions token 6217 on a line that names a DIFFERENT test file,
# to record that that other file is currently RED. The referenced spec genuinely fails.
# The harness itself is green, so today the scan runs the WRONG file and reports ready.
{ printf '#!/usr/bin/env bash\n'
  printf 'set -euo pipefail\n'
  printf 'red_fixture="tests/test_6217_spec.sh"  # roadmap:%s, currently open+RED\n' 6217
  printf '[ -f "$red_fixture" ] || exit 1\nexit 0\n'; } > "$repo/tests/test_6217_harness.sh"
chmod +x "$repo/tests/test_6217_harness.sh"
cat > "$repo/tests/test_6217_spec.sh" <<'EOF'
#!/usr/bin/env bash
# the spec that actually owns 6217 — still RED
exit 1
EOF
chmod +x "$repo/tests/test_6217_spec.sh"

# ── Case C (regression guard): genuinely ungated, genuinely owned, green ──────────────
mkspec "$repo/tests/test_bb03.sh" bb03

# ── Case D (regression guard): ROADMAP twin present and NOT gated ────────────────────
# Proves the new suppression keys on the gate marker, not on merely having a twin.
mkspec "$repo/tests/test_bb04.sh" bb04

cat > "$repo/TODO.md" <<'EOF'
# TODO
## Current
- [ ] extract the shared definition and ship it <!-- id:9eb7 -->
- [ ] the harness change ships fully <!-- id:6217 -->
- [ ] a genuinely finished thing <!-- id:bb03 -->
- [ ] another genuinely finished thing <!-- id:bb04 -->
EOF

cat > "$repo/ROADMAP.md" <<'EOF'
# ROADMAP
- [ ] [INPUT - decision] extract the shared definition and ship it <!-- id:9eb7 --> — 🚧 GATED pending an owner decision
- [ ] [ROUTINE] another genuinely finished thing <!-- id:bb04 -->
EOF

git -C "$repo" add -A
d="$(date -d '-1 days' +%Y-%m-%dT12:00:00)"
GIT_AUTHOR_DATE="$d" GIT_COMMITTER_DATE="$d" \
  git -C "$repo" commit -q -m "fixture: gated-on-roadmap-twin + fixture-reference cases"

out="$(HOME="$tmp" ORPHAN_SCAN_TEST_TIMEOUT_S=10 timeout 60 "$ORPHAN" --shipped "$repo")"

fail=0
report() { echo "FAIL: $1"; fail=1; }

# (c) the positive path must survive both suppressions — asserted FIRST, so a scan that
# simply emits nothing at all cannot pass this file by vacuously satisfying (a) and (b).
grep -q 'id:bb03 — TICK-READY' <<<"$out" \
  || report "case C: an ungated, genuinely-owned, green item must still be TICK-READY"
grep -q 'id:bb04 — TICK-READY' <<<"$out" \
  || report "case D: an item whose ROADMAP twin exists but carries NO gate marker must still be TICK-READY"

# (a) gate marker on the ROADMAP twin suppresses TICK-READY
grep -q 'id:9eb7 — TICK-READY' <<<"$out" \
  && report "case A (defect 1): id:9eb7 is 🚧 GATED on its ROADMAP twin and must never be TICK-READY"

# (b) a `# roadmap:` occurrence naming a DIFFERENT test file is a fixture reference,
#     not the test-owns-item link
grep -q 'id:6217 — TICK-READY' <<<"$out" \
  && report "case B (defect 2): id:6217's only # roadmap: match is a fixture reference to another test file; it must not establish the link"

if (( fail )); then
  echo "--- scan output ---"
  echo "$out"
  exit 1
fi
echo "PASS: orphan-scan --shipped honours ROADMAP-twin gates and rejects fixture references (id:4425)"
