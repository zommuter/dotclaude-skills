#!/usr/bin/env bash
# roadmap:5f34
#
# RED SPEC for TODO id:5f34 (detail: docs/ledger-notes/5f34.md). The fix does not exist
# yet, so this file is EXPECTED-RED until the ROADMAP item is ticked.
#
# THE DEFECT. `tools/shrink-acceptance.py` normalises every detector observation to a
# record carrying a POLARITY. For POLARITY_VIOLATION it scores ASYMMETRICALLY
# (check_detectors, the `elif polarity == POLARITY_VIOLATION` arm): a GAINED finding is
# FATAL ("the shrink broke the ledger grammar"), and a LOST finding is recorded as an
# IMPROVEMENT unconditionally, with no attribution whatsoever. That is right for the case
# it was designed for -- a spurious substring hit disappearing when prose moves off the
# head line -- and exactly wrong for a detector that went BLIND, because from the record
# alone the two are indistinguishable.
#
# MEASURED 2026-09-02 on the wave-1 shrink (63d8539b): the gate printed
# `VERDICT: SAFE TO LAND` and listed 54 `decided-left-open` findings under IMPROVEMENTS.
# Reading the note files instead of trusting the label, 40 of them had their
# RESOLVED/DECIDED/SUPERSEDED lexeme RELOCATED INTO the note -- those items really are
# decided-and-left-open, and `lib-state-claim.sh` simply cannot see them any more. Only
# 14 were genuine false-positive removals. The gate is structurally incapable of catching
# this class, so re-running it can never surface the next one.
#
# THE FIX THIS SPEC PINS. The same file already has the machinery, in the other
# direction: `attribute_dispatch_gain()` requires a GAINED dispatch id to be EXPLAINED by
# a suspect marker whose literal text is present in the item's AFTER detail file. The
# mirror is that a LOST VIOLATION must be explained by the TRIGGERING LEXEME being ABSENT
# from the note, not merely MOVED into it.
#
# Contract asserted here:
#   A. A lost violation whose triggering lexeme is present verbatim in the item's AFTER
#      detail file is a DETECTOR GOING BLIND and must be FATAL. This is the 40.
#   B. A lost violation whose lexeme is genuinely GONE from both the ledger line and the
#      note is a real improvement and must NOT fail. This is the 14, and it is the half
#      that makes the pair discriminating: without it "make every violation loss fatal"
#      would satisfy A, and that is wrong -- it would refuse every shrink that actually
#      cleaned a ledger up, which is how a gate gets baselined away on day one.
#   C. The same as B with NO detail file at all. The lexeme is gone from everywhere, so
#      it is still an improvement; a missing note is not itself evidence of blinding.
#      (A + B + C triangulate the predicate: the answer is keyed on WHERE THE LEXEME IS,
#      not on whether a note exists, not on whether the head line shrank.)
#   D. The refusal must be READABLE: it names the item, names the lexeme, and names the
#      note file the lexeme was found in. A fatal nobody can act on is a silent one.
#   E. An UNCHANGED ledger pair still passes. The fix must not turn the constant
#      violations both sides share into findings.
#
# fails-against: the fix does not exist yet, so the ancestor to check out is the tree this
# spec was authored against -- `tools/shrink-acceptance.py` at ba1880ba scores EVERY
# violation loss as an improvement (check_detectors' `elif polarity ==
# POLARITY_VIOLATION` arm appends to `improvements` on the `was and not now` branch with
# no attribution call). Case A is the only assertion whose verdict rests on attributing a
# LOSS, so it is the one that fires there; B, C and E pass against that ancestor by
# construction (they are the directions it already allows), which is what makes this a
# discriminating declaration rather than a blanket kill. D's naming assertions are
# ordered BEFORE A so that A is the LAST-fired FAIL line, per the runner's last-line rule.
# fails-against-rev: ba1880ba -- tools/shrink-acceptance.py
# fails-against-assertion: case A: a LOST violation whose lexeme MOVED INTO the note must be REFUSED
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$ROOT/tools/shrink-acceptance.py"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0
report() { echo "FAIL: $1"; fail=1; }

[[ -x "$GATE" ]] || report "sanity: $GATE must exist and be executable"

# run_gate <before-dir> <after-dir> [extra args...] -> rc, output in $tmp/gate.txt
run_gate() {
  local before="$1" after="$2"; shift 2
  set +e
  python3 "$GATE" --before "$before" --after "$after" "$@" > "$tmp/gate.txt" 2>&1
  local rc=$?
  set -e
  return $rc
}

# ---------------------------------------------------------------------------
# Shared BEFORE fixture. Three [ROUTINE] items, each twinned in TODO.md so the
# NO-ACCEPTANCE-NO-TWIN rule stays quiet and only the rule under test moves.
#
#   cc01  head-line prose says "SUPERSEDED"  -> fires roadmap-lint DECIDED-LEFT-OPEN
#   cc02  head-line prose says "DEFERRED"    -> fires roadmap-lint DECIDED-LEFT-OPEN
#   cc03  no terminal word at all            -> control, never fires
# ---------------------------------------------------------------------------
mk_before() { # <dir>
  local d="$1"
  mkdir -p "$d"
  cat > "$d/ROADMAP.md" <<'EOF'
# ROADMAP

## Current

- [ ] [ROUTINE] **Blind item** -- acceptance: make test green. History: the earlier engine was SUPERSEDED by the shared library, kept here for the record. <!-- id:cc01 -->
- [ ] [ROUTINE] **Dropped item** -- acceptance: make test green. Scheduling note: the work was DEFERRED until the substrate landed, which it since has. <!-- id:cc02 -->
- [ ] [ROUTINE] **Quiet item** -- acceptance: make test green. <!-- id:cc03 -->
EOF
  cat > "$d/TODO.md" <<'EOF'
# TODO

## Current

- [ ] [ROUTINE] **Blind item** -- acceptance: make test green. <!-- id:cc01 -->
- [ ] [ROUTINE] **Dropped item** -- acceptance: make test green. <!-- id:cc02 -->
- [ ] [ROUTINE] **Quiet item** -- acceptance: make test green. <!-- id:cc03 -->
EOF
}

before="$tmp/before"
mk_before "$before"

# Fixture sanity: the BEFORE tree must ACTUALLY fire the rule under test on both items,
# or every case below is an unreached fixture proving nothing (the id:a73c class).
lint_out="$tmp/lint-before.txt"
set +e
"$ROOT/relay/scripts/roadmap-lint.sh" "$before" > "$lint_out" 2>&1
set -e
grep -q 'DECIDED-LEFT-OPEN: open item id:cc01' "$lint_out" \
  || report "sanity: the BEFORE fixture must fire DECIDED-LEFT-OPEN for id:cc01, else case A is unreached"
grep -q 'DECIDED-LEFT-OPEN: open item id:cc02' "$lint_out" \
  || report "sanity: the BEFORE fixture must fire DECIDED-LEFT-OPEN for id:cc02, else cases B and C are unreached"

# ---------------------------------------------------------------------------
# (E) an UNCHANGED ledger pair passes. Both sides carry the same two violations,
#     so nothing is lost and nothing is gained.
# ---------------------------------------------------------------------------
after_e="$tmp/after-e"; mk_before "$after_e"
rc=0; run_gate "$before" "$after_e" || rc=$?
(( rc == 0 )) \
  || report "case E: an UNCHANGED ledger pair must still pass; got rc=$rc -- $(grep -m2 '^  FATAL' "$tmp/gate.txt" | tr '\n' ' ')"

# ---------------------------------------------------------------------------
# (A) + (D) THE BLINDING SHAPE: cc01's head line is shrunk behind a detail pointer and
#     the triggering lexeme SUPERSEDED travels INTO docs/ledger-notes/cc01.md verbatim.
#     The item is still decided-and-left-open; the detector just cannot see it any more.
# ---------------------------------------------------------------------------
after_a="$tmp/after-a"; mk_before "$after_a"; mkdir -p "$after_a/docs/ledger-notes"
python3 - "$after_a" <<'PY'
import sys, re, os
d = sys.argv[1]
p = os.path.join(d, "ROADMAP.md")
src = open(p).read()
new = ("- [ ] [ROUTINE] **Blind item** -- detail: `docs/ledger-notes/cc01.md` "
       "<!-- id:cc01 -->\n")
src = re.sub(r"^- \[ \] \[ROUTINE\] \*\*Blind item\*\*.*\n", new, src, count=1, flags=re.M)
open(p, "w").write(src)
# The lexeme is RELOCATED, not destroyed: it is present verbatim in the note.
open(os.path.join(d, "docs/ledger-notes/cc01.md"), "w").write(
    "# id:cc01\n\n## From ROADMAP\n\nacceptance: make test green. History: the earlier "
    "engine was SUPERSEDED by the shared library, kept here for the record.\n")
PY
# Fixture sanity: the lexeme must really have moved rather than vanished, or case A is
# indistinguishable from case B and tests nothing.
grep -q 'SUPERSEDED' "$after_a/docs/ledger-notes/cc01.md" \
  || report "sanity: case A's note must carry the relocated lexeme verbatim"
if grep -q 'SUPERSEDED' "$after_a/ROADMAP.md"; then
  report "sanity: case A's ROADMAP head line must no longer carry the lexeme"
fi
rc=0; run_gate "$before" "$after_a" || rc=$?
# (D) first, so that (A) is the LAST FAIL line this file can emit -- the negative-case
# runner keys the declaration on the last-fired assertion.
grep -q 'cc01' "$tmp/gate.txt" \
  || report "case D: the report must name id:cc01 as the item whose detector went blind"
grep -q 'SUPERSEDED' "$tmp/gate.txt" \
  || report "case D: the report must name the LEXEME that stopped firing, not just the rule"
grep -q 'docs/ledger-notes/cc01.md' "$tmp/gate.txt" \
  || report "case D: the report must name the note file the lexeme was found in, so the reader can check it"
(( rc != 0 )) \
  || report "case A: a LOST violation whose lexeme MOVED INTO the note must be REFUSED (non-zero exit) -- id:cc01 is still decided-and-left-open, the detector merely cannot see it; got rc=$rc, and the gate said: $(grep -m1 'VERDICT' "$tmp/gate.txt")"

# ---------------------------------------------------------------------------
# (B) THE GENUINE IMPROVEMENT: cc02's head line is shrunk behind a pointer AND the stale
#     DEFERRED marker is dropped -- literally what the lint's own message tells you to do
#     ("close it (tick + done-note) or drop the marker"). The lexeme is nowhere: not on
#     the line, not in the note. This must NOT fail.
# ---------------------------------------------------------------------------
after_b="$tmp/after-b"; mk_before "$after_b"; mkdir -p "$after_b/docs/ledger-notes"
python3 - "$after_b" <<'PY'
import sys, re, os
d = sys.argv[1]
p = os.path.join(d, "ROADMAP.md")
src = open(p).read()
new = ("- [ ] [ROUTINE] **Dropped item** -- detail: `docs/ledger-notes/cc02.md` "
       "<!-- id:cc02 -->\n")
src = re.sub(r"^- \[ \] \[ROUTINE\] \*\*Dropped item\*\*.*\n", new, src, count=1, flags=re.M)
open(p, "w").write(src)
# The stale marker is DROPPED, not relocated: the note re-words the same fact.
open(os.path.join(d, "docs/ledger-notes/cc02.md"), "w").write(
    "# id:cc02\n\n## From ROADMAP\n\nacceptance: make test green. Scheduling note: the "
    "work waited until the substrate landed, which it since has.\n")
PY
if grep -q 'DEFERRED' "$after_b/docs/ledger-notes/cc02.md"; then
  report "sanity: case B's note must NOT carry the lexeme, else it is case A again"
fi
rc=0; run_gate "$before" "$after_b" || rc=$?
(( rc == 0 )) \
  || report "case B: a violation loss whose lexeme is gone from BOTH line and note is a real improvement and must not fail -- 'make every loss fatal' is the wrong fix; got rc=$rc: $(grep -m2 '^  FATAL' "$tmp/gate.txt" | tr '\n' ' ')"
grep -q 'IMPROVEMENTS' "$tmp/gate.txt" \
  || report "case B: the allowed direction must be REPORTED as an improvement, not passed silently"

# ---------------------------------------------------------------------------
# (C) the same loss with NO detail file at all: cc02's stale clause is deleted outright
#     and nothing is relocated. The lexeme is gone from everywhere, so this is still an
#     improvement -- the predicate is keyed on WHERE THE LEXEME IS, not on note existence.
# ---------------------------------------------------------------------------
after_c="$tmp/after-c"; mk_before "$after_c"
python3 - "$after_c" <<'PY'
import sys, re, os
d = sys.argv[1]
p = os.path.join(d, "ROADMAP.md")
src = open(p).read()
new = ("- [ ] [ROUTINE] **Dropped item** -- acceptance: make test green. Scheduling note: "
       "the work waited until the substrate landed, which it since has. <!-- id:cc02 -->\n")
src = re.sub(r"^- \[ \] \[ROUTINE\] \*\*Dropped item\*\*.*\n", new, src, count=1, flags=re.M)
open(p, "w").write(src)
PY
if [[ -d "$after_c/docs/ledger-notes" ]]; then
  report "sanity: case C must have NO notes directory, else it is not the no-note shape"
fi
rc=0; run_gate "$before" "$after_c" || rc=$?
(( rc == 0 )) \
  || report "case C: a violation loss with no detail file anywhere must not fail -- the lexeme is gone from everywhere, which is the improvement direction; got rc=$rc: $(grep -m2 '^  FATAL' "$tmp/gate.txt" | tr '\n' ' ')"

if (( fail )); then
  exit 1
fi
echo "PASS: shrink-acceptance.py attributes violation LOSSES -- a lexeme relocated into a detail file is a blinded detector and is refused, a lexeme genuinely gone is an improvement (id:5f34)"
