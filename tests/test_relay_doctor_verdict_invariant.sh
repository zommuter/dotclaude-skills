#!/usr/bin/env bash
# roadmap:188c — relay-doctor check 10: verdict-invariant replay (invariants I2/I4).
# Seed invalid-state (ii): `execute` on a repo with no executor-actionable work. Check 10 replays
# classify-repo.sh --emit unit and cross-checks the verdict (classify-verdict.sh) against the
# derived count (classify-repo.sh): I2 = execute ⟹ actionable_routine_open>0; I4 = intensive!="" ⟹
# verdict∈{execute,hard}. Both invariants are maintained BY CONSTRUCTION in the real pipeline, so a
# violation is produced via a stubbed classify-repo (RELAY_DOCTOR_CLASSIFY_REPO). Real-pipeline
# verdict correctness is covered by test_classify_repo.sh / test_classify_verdict.sh.
#
# RED until check 10 + the RELAY_DOCTOR_CLASSIFY_REPO override land.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SH="$ROOT/relay/scripts/relay-doctor.sh"
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SH" ]] || fail "relay-doctor.sh not executable"

FIX="$(mktemp -d)"; TOML="$(mktemp)"; STUB="$(mktemp)"; UNIT="$(mktemp)"; INBOX="$(mktemp)"
trap 'rm -rf "$FIX" "$TOML" "$STUB" "$UNIT" "$INBOX"' EXIT
git -C "$FIX" init -q
git -C "$FIX" config user.email t@e.st; git -C "$FIX" config user.name t
printf '# Roadmap\n\n## Items\n' > "$FIX/ROADMAP.md"; printf '# TODO\n' > "$FIX/TODO.md"
git -C "$FIX" add -A; git -C "$FIX" commit -qm init
printf '' > "$TOML"; export RELAY_TOML="$TOML"
# Hermeticity (defect fix 2026-07-02, no roadmap item): relay-doctor's inbox dead-letter
# section (scan-routed.sh) defaults to the REAL ~/.claude/todo-inbox.md; with the empty
# fixture RELAY_TOML its routed targets can never resolve, so any real inbox traffic made
# case (3)'s strict-clean assertion fail (observed: 4 UNRESOLVED → --strict exit 1).
# Point it at an empty inbox so the only issues the doctor can see come from the fixture.
printf '' > "$INBOX"; export RELAY_INBOX="$INBOX"

# Stub classify-repo: ignore args, emit the crafted unit JSON in $UNIT (its --emit unit output).
cat > "$STUB" <<STUBEOF
#!/usr/bin/env bash
cat "$UNIT"
STUBEOF
chmod +x "$STUB"
export RELAY_DOCTOR_CLASSIFY_REPO="$STUB"

run() { "$SH" "$FIX" 2>/dev/null; }

# (1) I2 violation: verdict=execute but actionable_routine_open=0 → flagged.
printf '{"verdict":"execute","actionable_routine_open":0,"intensive":""}' > "$UNIT"
out="$(run)"
grep -q 'I2 VIOLATED' <<<"$out" || fail "(1) execute∧aro=0 not flagged (I2):\n$(grep -A2 verdict-invariant <<<"$out")"
pass "(1) execute ∧ actionable_routine_open=0 → I2 VIOLATED"

# (1b) --strict exits nonzero on the I2 violation.
rc=0; "$SH" --strict "$FIX" >/dev/null 2>&1 || rc=$?
[[ "$rc" -ne 0 ]] || fail "(1b) --strict must exit nonzero on an I2 violation; got 0"
pass "(1b) --strict exits nonzero on a verdict-invariant violation"

# (2) I4 violation: intensive set but verdict=review (not execute/hard) → flagged.
printf '{"verdict":"review","actionable_routine_open":0,"intensive":"gpu"}' > "$UNIT"
out="$(run)"
grep -q 'I4 VIOLATED' <<<"$out" || fail "(2) intensive∧verdict=review not flagged (I4):\n$(grep -A2 verdict-invariant <<<"$out")"
pass "(2) intensive!=\"\" ∧ verdict=review → I4 VIOLATED"

# (3) clean: execute with actionable_routine_open>0, no intensive → OK, no issue.
printf '{"verdict":"execute","actionable_routine_open":3,"intensive":""}' > "$UNIT"
out="$(run)"
grep -q 'VIOLATED' <<<"$out" && fail "(3) valid execute∧aro=3 wrongly flagged:\n$out"
grep -A1 'verdict-invariant replay' <<<"$out" | grep -q 'OK verdict=execute' \
  || fail "(3) valid unit not reported OK:\n$(grep -A2 verdict-invariant <<<"$out")"
rc=0; "$SH" --strict "$FIX" >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 0 ]] || fail "(3) --strict must exit 0 when the unit is valid; got $rc"
pass "(3) valid execute ∧ aro>0 → OK (no violation, --strict clean)"

echo "ALL PASS: id:188c relay-doctor check 10 (verdict-invariant replay, I2/I4)"
