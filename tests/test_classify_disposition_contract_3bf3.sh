#!/usr/bin/env bash
# Defect-fix test (NO roadmap item — id:3bf3 lives only in TODO.md, never promoted to
# ROADMAP.md, so per CLAUDE.md §Testing this file deliberately omits a `# roadmap:` header
# and its failures always count).
#
# id:3bf3 — "/meeting disposition-routing surface" — asks for "a fixture item per lane/state
# maps to the right disposition label". The LANE axis is already fully covered by
# tests/test_classify_hard_lanes.sh (all 8 lanes, both vocabularies, head-anchoring,
# backtick-stripping) and the RELAY mirror line by tests/test_classify_hard_floor.sh.
# This file covers the two halves that were NOT covered anywhere (verified 2026-08-13):
#
#   (1) The STATE axis — the GATE column. No test asserted GATED detection at all, so the
#       `[GATED]` marker SKILL.md step 3 appends to each one-liner rested on nothing.
#
#   (2) The TSV COLUMN CONTRACT — CLAUDE.md §Versioning lists "classify.sh TSV column
#       contract" as an UNMARKED candidate contract surface, with the rationale "SKILL.md
#       parses fixed columns". Nothing tested that the columns stay 5-wide and in order,
#       so a silent column insert would break every consumer at once. This pins it.
#
#   (3) The DISPOSITION PARTITION itself — id:3bf3's actual contract: every class is either
#       pick-eligible (a /meeting candidate) or not-meeting-worthy (routed to /relay or
#       /relay human). That partition currently lives ONLY in SKILL.md prose. A lane-tagged
#       skip-class item leaking into C1/C2/C3 is the exact "/meeting over-claim" regression.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SH="$ROOT/meeting/classify.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SH" ]] || fail "classify.sh not executable at $SH"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# Fixture note with a Decisions section, so the linked item is a real C1.
mkdir -p "$TMP/docs/meeting-notes"
printf '# note\n\n## Decisions\n\n- D1: something was decided.\n' \
  > "$TMP/docs/meeting-notes/2026-01-01-0000-x.md"

# NOTE ON FIXTURE WORDING: classify.sh's gate detector is
#   grep -qiE 'gated?|gate:|reopen (gate|trigger)|condition-triggered|blocked on'
# so any body containing the substring "gate" trips it. The ungated fixtures below are
# deliberately worded to avoid "gate"-containing words (including investigate / mitigate /
# aggregate / delegate / navigate) so they genuinely exercise the empty-GATE branch.
cat > "$TMP/TODO.md" <<'EOF'
# TODO

## Current

- [ ] **An ordinary unlinked item** with no lane and no blocking vocabulary. <!-- id:aaa1 -->
- [ ] **A linked ready item** docs/meeting-notes/2026-01-01-0000-x.md — link plus Decisions. <!-- id:aaa2 -->
- [ ] **An item that is gated on something else** and cannot proceed yet. <!-- id:aaa3 -->
- [ ] **An item blocked on a dependency** that has not landed. <!-- id:aaa4 -->
- [ ] [INPUT — nonsense] **An unrecognized lane that is also gated** — both flags must appear. <!-- id:aaa5 -->
- [ ] [HARD] **A pool item** that the apex pool runs unattended. <!-- id:aaa6 -->
- [ ] [ROUTINE] **An executor item** for the cheap tier. <!-- id:aaa7 -->
- [ ] [MECHANICAL] **A daemon item** with no model in the loop. <!-- id:aaa8 -->
- [ ] [INPUT — access] **A hands item** needing physical presence. <!-- id:aaa9 -->
- [ ] [INPUT — decision] **A human-call item** with no design session. <!-- id:aab0 -->
- [ ] [INPUT — meeting] **A design-session item** for the meeting lane. <!-- id:aab1 -->
- [ ] Relay: 7 open ROADMAP items
- [ ] **A very long summary line that runs well past the eighty character truncation boundary** so that the SUMMARY column width contract is actually exercised rather than assumed. <!-- id:aab2 -->
EOF

out="$("$SH" "$TMP")"
[[ -n "$out" ]] || fail "classify.sh produced no output for the fixture"

cls()  { printf '%s\n' "$out" | awk -F'\t' -v id="id:$1" '$2==id{print $1}'; }
gate() { printf '%s\n' "$out" | awk -F'\t' -v id="id:$1" '$2==id{print $5}'; }
note() { printf '%s\n' "$out" | awk -F'\t' -v id="id:$1" '$2==id{print $4}'; }
summ() { printf '%s\n' "$out" | awk -F'\t' -v id="id:$1" '$2==id{print $3}'; }

# ---------------------------------------------------------------------------
# (2) TSV COLUMN CONTRACT — the unmarked contract surface CLAUDE.md names.
# ---------------------------------------------------------------------------

# Every emitted line carries EXACTLY 5 tab-separated fields. awk's NF counts fields, so a
# dropped OR added column fails here regardless of content. Guards the silent-insert case
# that would break SKILL.md's positional parse and every other reader at once.
badnf="$(printf '%s\n' "$out" | awk -F'\t' 'NF!=5{c++} END{print c+0}')"
[[ "$badnf" == "0" ]] || fail "TSV column contract: $badnf line(s) do not have exactly 5 tab-separated fields"
pass "TSV column contract — every line has exactly 5 tab-separated fields"

# Column ORDER is positional, not just arity: field 1 is the CLASS enum, field 2 is the
# id token (or empty), field 4 is the note link (or empty), field 5 is the GATE enum.
# A transposition would keep NF==5 and slip past the check above, so pin the shapes.
badcls="$(printf '%s\n' "$out" | awk -F'\t' '$1 !~ /^(C1|C2|C3|RELAY|POOL|EXEC|MECH|HANDS|HUMAN)$/{c++} END{print c+0}')"
[[ "$badcls" == "0" ]] || fail "column 1 must be the CLASS enum on every line; $badcls line(s) violate it"
pass "column 1 is always a known CLASS enum value"

badid="$(printf '%s\n' "$out" | awk -F'\t' '$2!="" && $2 !~ /^id:[0-9a-f]+$/{c++} END{print c+0}')"
[[ "$badid" == "0" ]] || fail "column 2 must be empty or an id:<hex> token; $badid line(s) violate it"
pass "column 2 is always empty or an id:<hex> token"

badgate="$(printf '%s\n' "$out" | awk -F'\t' '$5!="" && $5 !~ /^(GATED|HARD-NOLANE|GATED;HARD-NOLANE)$/{c++} END{print c+0}')"
[[ "$badgate" == "0" ]] || fail "column 5 must be empty or a known GATE value; $badgate line(s) violate it"
pass "column 5 is always empty or a known GATE value"

[[ "$(note aaa2)" == "docs/meeting-notes/2026-01-01-0000-x.md" ]] \
  || fail "column 4 must carry the note link, got '$(note aaa2)'"
pass "column 4 carries the meeting-note link"

# SUMMARY is documented as ≤80 chars (cut -c1-80).
s="$(summ aab2)"
[[ ${#s} -le 80 ]] || fail "SUMMARY column must be truncated to <=80 chars, got ${#s}"
[[ ${#s} -gt 0 ]] || fail "SUMMARY column must not be empty for a normal item"
pass "SUMMARY column truncated to <=80 chars (got ${#s})"

# ---------------------------------------------------------------------------
# (1) STATE AXIS — the GATE column. Previously untested entirely.
# ---------------------------------------------------------------------------

[[ "$(gate aaa1)" == "" ]] || fail "an item with no blocking vocabulary must have an EMPTY gate, got '$(gate aaa1)'"
pass "ungated item → empty GATE column"

[[ "$(gate aaa2)" == "" ]] || fail "a linked ready item must have an EMPTY gate, got '$(gate aaa2)'"
pass "linked ready (C1) item → empty GATE column"

[[ "$(gate aaa3)" == "GATED" ]] || fail "'gated on' vocabulary must yield GATED, got '$(gate aaa3)'"
pass "'gated on …' → GATED"

[[ "$(gate aaa4)" == "GATED" ]] || fail "'blocked on' vocabulary must yield GATED, got '$(gate aaa4)'"
pass "'blocked on …' → GATED"

# The two flags COMPOSE — classify.sh documents "GATED;HARD-NOLANE" as a valid combination,
# and SKILL.md step 3 renders BOTH markers. A naive assignment that overwrote instead of
# appending would drop one marker silently.
g="$(gate aaa5)"
[[ "$g" == *GATED* ]]       || fail "combined case must retain GATED, got '$g'"
[[ "$g" == *HARD-NOLANE* ]] || fail "combined case must retain HARD-NOLANE, got '$g'"
pass "gated + unrecognized lane → GATE carries BOTH markers ('$g')"

# ---------------------------------------------------------------------------
# (3) DISPOSITION PARTITION — id:3bf3's actual contract.
# ---------------------------------------------------------------------------
# Every class falls on exactly one side: pick-eligible (a /meeting candidate) or
# not-meeting-worthy (routed to /relay or /relay human). SKILL.md step 3 picks head -1 of
# the highest non-empty PICKABLE bucket and must never pick from the skip set.
PICKABLE=" C1 C2 C3 "
SKIP=" RELAY POOL EXEC MECH HANDS HUMAN "

for c in C1 C2 C3; do
  [[ "$PICKABLE" == *" $c "* ]] || fail "$c must be pick-eligible"
done
for c in RELAY POOL EXEC MECH HANDS HUMAN; do
  [[ "$SKIP" == *" $c "* ]] || fail "$c must be in the skip set"
  [[ "$PICKABLE" != *" $c "* ]] || fail "$c must NOT be pick-eligible (the /meeting over-claim regression)"
done
pass "class partition is disjoint: {C1,C2,C3} pickable vs {RELAY,POOL,EXEC,MECH,HANDS,HUMAN} skipped"

# The lane-tagged skip-class items must land in the SKIP half — this is the concrete
# "/meeting over-claim" guard: a pool/executor/daemon/hands/human item surfacing as a
# meeting candidate is the defect id:3bf3 and its predecessors exist to prevent.
for pair in "aaa6:POOL" "aaa7:EXEC" "aaa8:MECH" "aaa9:HANDS" "aab0:HUMAN"; do
  id="${pair%%:*}"; want="${pair##*:}"
  got="$(cls "$id")"
  [[ "$got" == "$want" ]] || fail "id:$id must classify $want, got '$got'"
  [[ "$SKIP" == *" $got "* ]] || fail "id:$id ($got) must be not-meeting-worthy"
done
pass "every lane-tagged skip-class item lands in the not-meeting-worthy half"

# …and the meeting lane stays pick-eligible, so the partition is not vacuously all-skip.
c="$(cls aab1)"
[[ "$c" == "C3" ]] || fail "[INPUT — meeting] must stay a meeting candidate (C3), got '$c'"
[[ "$PICKABLE" == *" $c "* ]] || fail "[INPUT — meeting] must be pick-eligible"
pass "[INPUT — meeting] → C3 and pick-eligible (partition is non-vacuous)"

# The RELAY mirror line is emitted with EMPTY note and gate columns (classify.sh returns
# early for it) — pin that shape so the early-return keeps filling all 5 columns.
relay_line="$(printf '%s\n' "$out" | awk -F'\t' '$1=="RELAY"{print; exit}')"
[[ -n "$relay_line" ]] || fail "the relay mirror line must be emitted as class RELAY"
rn="$(printf '%s' "$relay_line" | cut -f4)"; rg="$(printf '%s' "$relay_line" | cut -f5)"
[[ -z "$rn" && -z "$rg" ]] || fail "RELAY line must have empty note+gate columns, got note='$rn' gate='$rg'"
pass "RELAY mirror line → 5 columns with empty note+gate"

echo "ALL PASS"
