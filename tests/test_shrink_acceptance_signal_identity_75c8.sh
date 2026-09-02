#!/usr/bin/env bash
# No roadmap header -- defect-fix spec for TODO id:75c8. Failures always count.
#
# Defect: `tools/shrink-acceptance.py` took a finding's full RULE COLUMN as its signal
# identity. `todo-conformance.sh` spells its length rules with the measurement inline --
# `length-grandfathered (1367 chars > budget 500, within baseline 3004)` -- so a shrink
# that merely made an over-budget line SHORTER changed the signal string, and the gate
# reported the old one LOST and a new one GAINED for the same rule on the same item.
# MEASURED on the live gate run of 2026-09-02: 42 of the 43 fatals were exactly this
# (37 `length-unshrinkable` + 5 `length-grandfathered`), both non-blocking REPORT lines.
# Meanwhile that detector's real findings fell 669 -> 75 and the gate could not see the
# improvement. A gate that goes red on a correct shrink is how a gate gets baselined
# away on day one, which is what the ratifying meeting warned about.
#
# Clause: the signal is rule + item, with any trailing parenthetical qualifier stripped,
# so a moving measurement is not an identity change. This must NOT blunt the gate: a
# genuinely NEW rule firing on an item is still a new signal, because a budget
# regression changes the leading TOKEN (`length-grandfathered` -> `length-over-budget`).
#
# fails-against: the fix and this spec land in the same commit, so the negative case is a
# mutation that restores the pre-fix identity (the raw rule column, measurement and all).
# fails-against-mutation: sed -i 's/^    return rule.split("(", 1)\[0\].strip()/    return rule/' tools/shrink-acceptance.py
# fails-against-assertion: a shrink that only moved the MEASUREMENT must not be a new violation
#
# Hermetic: temp ledger fixtures + a temp length baseline; no ~/.claude, no network.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$ROOT/tools/shrink-acceptance.py"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$GATE" ]] || fail "sanity: $GATE must exist"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# A head line long enough to be over the 500-char budget in BOTH trees, so the SAME rule
# (`length-grandfathered`) fires on both sides and only its number moves. Anything that
# crossed the budget would change the rule token and prove nothing about identity.
pad_long="$(head -c 900 < /dev/zero | tr '\0' 'x')"
pad_short="$(head -c 600 < /dev/zero | tr '\0' 'y')"

mk_tree() { # <dir> <pad>
  local d="$1" pad="$2"
  mkdir -p "$d"
  cat > "$d/TODO.md" <<EOF
# TODO

## Current

- [ ] [ROUTINE] **Long item** -- acceptance: make test green. $pad <!-- id:cc01 -->
EOF
  cat > "$d/ROADMAP.md" <<'EOF'
# ROADMAP

## Current

- [ ] [ROUTINE] **Long item** -- acceptance: make test green. <!-- id:cc01 -->
EOF
}

before="$tmp/before"; mk_tree "$before" "$pad_long"
after="$tmp/after";   mk_tree "$after"  "$pad_short"

# Baseline the item at its BEFORE length, so both sides report `length-grandfathered`
# (over budget, within baseline) and the AFTER side is a legitimate monotonic shrink.
LENGTH_BASELINE="$tmp/length-baseline.txt"
export LENGTH_BASELINE
relay/scripts/todo-conformance.sh --regen-length-baseline "$before/TODO.md" \
  > "$LENGTH_BASELINE" 2>/dev/null || fail "sanity: could not regenerate the length baseline"
export PWD  # keep the subshell honest about cwd-relative script lookup

# --- Fixture sanity: the machinery under test must actually be REACHED ----------
# Without this the whole file could pass because no length finding ever fired (the
# id:a73c unreached-fixture class), which looks identical to a working fix.
b_rule="$(relay/scripts/todo-conformance.sh "$before/TODO.md" 2>/dev/null | cut -f1 | grep '^length-grandfathered' || true)"
a_rule="$(relay/scripts/todo-conformance.sh "$after/TODO.md"  2>/dev/null | cut -f1 | grep '^length-grandfathered' || true)"
[[ -n "$b_rule" && -n "$a_rule" ]] \
  || fail "sanity: length-grandfathered did not fire on both sides (before='$b_rule' after='$a_rule')"
[[ "$b_rule" != "$a_rule" ]] \
  || fail "sanity: the two rule columns are identical, so the fixture cannot exercise the defect ('$b_rule')"

# --- (a) THE DEFECT: only the measurement moved, so the gate must stay clean -----
set +e
python3 "$GATE" --before "$before" --after "$after" > "$tmp/gate.txt" 2>&1; rc=$?
set -e
if (( rc != 0 )) && grep -q 'length-grandfathered' "$tmp/gate.txt"; then
  fail "a shrink that only moved the MEASUREMENT must not be a new violation; rc=$rc -- $(grep -m3 'length-grandfathered' "$tmp/gate.txt" | tr '\n' ' ')"
fi
! grep -q 'length-grandfathered' "$tmp/gate.txt" \
  || fail "a shrink that only moved the MEASUREMENT was still reported against length-grandfathered: $(grep -m3 'length-grandfathered' "$tmp/gate.txt" | tr '\n' ' ')"

# --- (b) the fix must not blunt the gate: a DIFFERENT rule token still registers --
# Same item, same baseline, but the line GREW past its baselined length. That breaks the
# ratchet's monotonic-shrink rule, so the token changes `length-grandfathered` ->
# `length-regrowth`. Stripping the parenthetical must not swallow that.
pad_grown="$(head -c 1400 < /dev/zero | tr '\0' 'z')"
regrow="$tmp/regrow"; mk_tree "$regrow" "$pad_grown"
grep -q '^length-regrowth' <(relay/scripts/todo-conformance.sh "$regrow/TODO.md" 2>/dev/null | cut -f1) \
  || fail "sanity: the regrown fixture did not produce length-regrowth, so case (b) proves nothing"

set +e
python3 "$GATE" --before "$before" --after "$regrow" > "$tmp/gate2.txt" 2>&1; rc2=$?
set -e
grep -q 'length-regrowth' "$tmp/gate2.txt" \
  || fail "a changed rule TOKEN (length-grandfathered -> length-regrowth on the same item) must still register as a new signal (rc=$rc2): $(head -c 1200 "$tmp/gate2.txt" | tr '\n' ' ')"

pass "shrink-acceptance normalises a finding's signal to rule + item (id:75c8): a moving measurement inside the rule column is no longer a lost/gained signal, while a changed rule TOKEN still registers"
