#!/usr/bin/env bash
# LEDGER LINE ACCOUNTING -- the classified line buckets MUST sum to the file's line count,
# so that no ledger line can be silently invisible to todo-conformance.sh's line grammar.
#
# NO `# roadmap:` header, deliberately: this is not the spec for an open roadmap item, it is
# a standing invariant. Its failures always count.
#
# WHY THIS EXISTS -----------------------------------------------------------------------
# `relay/scripts/todo-conformance.sh` carries the id:b048 LINE GRAMMAR: every line of a
# ledger is blank, a heading, or an item, and everything else is a finding. The rule is
# report-only today, so nothing downstream fails when it misses a line -- which means a
# line that falls through EVERY branch of grammar_scan() is reported by nobody and is
# indistinguishable from a conforming line. That is the id:5f34 shape: a gate structurally
# blind to its detector going blind.
#
# Arithmetic is the cheapest possible guard against it. Classify every line with RAW greps
# that know nothing about the script's internals, then require:
#
#     wc -l  ==  blank + heading + item + exempt + reported
#
# where `reported` is the number of lines todo-conformance.sh puts in the `grammar-line` or
# `grammar-continuation` classes. Every line is in exactly one bucket, so the identity can
# only break when the checker under-reports (a line fell through) or over-reports (a line
# was double-counted). It is an IDENTITY, not a budget: it holds for any ledger content and
# can never go red from ordinary ledger edits.
#
# The SET check below is the strong half -- it pins WHICH lines, not just how many, so two
# opposite errors cannot cancel. That is not hypothetical here: measured on TODO.md
# 2026-09-03, a count-only identity built on a `comment_only` bucket balanced at 79 == 79
# purely by coincidence, because line 266 (an HTML-comment-only line) is reported as
# `grammar-line` while line 293 (an `<!-- ref:aae4 -->` exempt bullet) is silently skipped.
# The two errors cancelled exactly. The set check catches both.
#
# THE FIVE BUCKETS, and why `exempt` and NOT `comment_only`:
#   blank     `^[[:space:]]*$`         -- grammar_scan skips it (shape 1).
#   heading   `^#{1,6}[[:space:]]`     -- shape 2; its findings are `grammar-heading-*`,
#                                         never one of the two classes counted here.
#   item      `^- \[[ xX]\]`           -- shape 3; findings are `grammar-item-*`.
#   exempt    `<!-- lint-ok: … -->` or `<!-- ref:XXXX -->` on a line that is none of the
#                                         above -- exempt() makes grammar_scan `continue`
#                                         BEFORE any classification, so such a line is
#                                         legitimately silent and needs its own bucket.
#   reported  everything left, which the grammar calls `grammar-line` (top-level) or
#             `grammar-continuation` (indented).
# An HTML-comment-only line is deliberately NOT a bucket: `classify_todo` (the OLDER TODO
# grammar) treats it as conforming, but the id:b048 grammar reports it as `grammar-line`
# by design -- see that script's UNDERSPECIFIED note (ii). It is therefore already inside
# `reported`, and giving it a bucket of its own would double-count it. Case D pins that.
#
# HERMETICITY: the fixture cases export BOTH SHAPE_BASELINE and LENGTH_BASELINE to absent
# paths under this test's own mktemp -d (id:e350 -- four tests shipped reading the LIVE
# committed baselines because they omitted exactly this). Both ratchets then go inert and
# say so on stderr, which is fine: this test reads stdout only, and neither ratchet emits a
# `grammar-*` class. The LIVE cases use the real baselines, which is correct -- verified
# 2026-09-03 that the grammar-line/grammar-continuation counts are byte-identical with the
# real baselines and with absent ones, because grammar_scan() runs before and independently
# of both ratchets.
#
# fails-against: todo-conformance.sh going blind to a whole line class -- the accounting
#   must then refuse to balance instead of silently agreeing with the narrowed checker.
# fails-against-mutation: sed -i 's/GRAMMAR_FIND\[\$((i+1))\]="grammar-continuation.*/continue/' relay/scripts/todo-conformance.sh
# fails-against-assertion: case C: checker must report all
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SH="$ROOT/relay/scripts/todo-conformance.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SH" ]] || fail "todo-conformance.sh not executable at $SH"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# --- the raw-grep buckets. Deliberately NOT sourced from the script under test. -----------
b_blank()  { grep -cE '^[[:space:]]*$'      "$1" || true; }
b_head()   { grep -cE '^#{1,6}[[:space:]]'  "$1" || true; }
b_item()   { grep -cE '^- \[[ xX]\]'        "$1" || true; }
# exempt lines that are not already blank / heading / item.
b_exempt() {
  grep -E '<!-- lint-ok:|<!-- ref:[0-9a-f]{4} -->' "$1" \
    | grep -cvE '^[[:space:]]*$|^#{1,6}[[:space:]]|^- \[[ xX]\]' || true
}
# The LEFTOVER set: 1-based line numbers in none of the four accounted buckets.
leftover_lines() {
  awk '{
    if ($0 ~ /^[[:space:]]*$/) next
    if ($0 ~ /^#{1,6}[[:space:]]/) next
    if ($0 ~ /^- \[[ xX]\]/) next
    if ($0 ~ /<!-- lint-ok:/) next
    if ($0 ~ /<!-- ref:[0-9a-f][0-9a-f][0-9a-f][0-9a-f] -->/) next
    print NR
  }' "$1" | sort -n
}
# What the checker actually reports in the two "this line matched no shape" classes.
reported_lines() {
  "$SH" "$1" 2>/dev/null | grep -E '^(grammar-line|grammar-continuation)[[:space:]]' \
    | cut -f2 | sort -n || true
}
n_of() { printf '%s\n' "$1" | grep -c . || true; }

# --- hermetic fixtures: absent baselines inside our own TMP (id:e350) ---------------------
export LENGTH_BASELINE="$TMP/absent-length-baseline.txt"
export SHAPE_BASELINE="$TMP/absent-shape-baseline.txt"
export STATE_CLAIM_BASELINE="$TMP/absent-state-claim-baseline.txt"
export TODO_CONFORMANCE_LOG="$TMP/conformance.log"
[[ -e "$LENGTH_BASELINE" || -e "$SHAPE_BASELINE" ]] && fail "fixture baselines must not exist"

# --- case A: a fully conforming ledger -- nothing left over, nothing reported -------------
A="$TMP/A.md"
cat > "$A" <<'EOF'
# TODO

## Current

- [ ] **Wire the accounting check** into the suite. <!-- id:0001 -->
- [x] **Bucket the blank lines** first. <!-- id:0002 -->

## Done

- [x] **Nothing here yet.** <!-- id:0003 -->
EOF
a_total=$(wc -l < "$A")
a_left=$(leftover_lines "$A"); a_nleft=$(n_of "$a_left")
a_rep=$(reported_lines "$A");  a_nrep=$(n_of "$a_rep")
(( a_nleft == 0 )) || fail "case A: a conforming ledger must leave 0 unaccounted lines, got $a_nleft ($a_left)"
(( a_nrep == 0 ))  || fail "case A: a conforming ledger must draw 0 grammar-line/continuation findings, got $a_nrep ($a_rep)"
a_sum=$(( $(b_blank "$A") + $(b_head "$A") + $(b_item "$A") + $(b_exempt "$A") ))
(( a_sum == a_total )) || fail "case A: blank+heading+item must equal $a_total, got $a_sum"
pass "case A: conforming fixture -- blank+heading+item == $a_total, zero unaccounted, zero reported"

# --- case B: N stray TOP-LEVEL prose lines -> N grammar-line findings ---------------------
B="$TMP/B.md"
cat > "$B" <<'EOF'
# TODO

## Current

- [ ] **A well-formed item.** <!-- id:0011 -->
placeholder
this bare prose line is seen by no tool
* a checkbox-less bullet that nothing tracks

## Done

- [x] **Another well-formed item.** <!-- id:0012 -->
EOF
b_n=3
b_left=$(leftover_lines "$B"); b_nleft=$(n_of "$b_left")
b_rep=$(reported_lines "$B");  b_nrep=$(n_of "$b_rep")
(( b_nleft == b_n )) || fail "case B: expected $b_n unaccounted prose lines, got $b_nleft ($b_left)"
(( b_nrep == b_n ))  || fail "case B: checker must report exactly $b_n stray prose lines, got $b_nrep ($b_rep)"
[[ "$b_left" == "$b_rep" ]] || fail "case B: the unaccounted line SET [$b_left] must equal the reported set [$b_rep]"
pass "case B: $b_n stray prose lines -- unaccounted set == reported set == {$(echo $b_left)}"

# --- case C: indented lines -> grammar-continuation. THE mutation target. ----------------
# Separated from case B on purpose: `grammar-line` and `grammar-continuation` are two
# distinct branches of grammar_scan(), and a fixture that mixes them cannot tell which one
# went blind.
C="$TMP/C.md"
cat > "$C" <<'EOF'
# TODO

## Current

- [ ] **An item with body prose that does not belong in the ledger.** <!-- id:0021 -->
  Acceptance: this indented line is a continuation, which the grammar forbids.
  Tests: so is this one.

## Done

- [x] **A clean item.** <!-- id:0022 -->
EOF
c_n=2
c_left=$(leftover_lines "$C"); c_nleft=$(n_of "$c_left")
c_rep=$(reported_lines "$C");  c_nrep=$(n_of "$c_rep")
(( c_nleft == c_n )) || fail "case C: expected $c_n unaccounted indented lines, got $c_nleft ($c_left)"
(( c_nrep == c_n ))  || fail "case C: checker must report all $c_n indented continuation lines, got $c_nrep ($c_rep)"
[[ "$c_left" == "$c_rep" ]] || fail "case C: indented lines unaccounted [$c_left] must equal reported [$c_rep]"
pass "case C: $c_n indented continuation lines -- unaccounted set == reported set == {$(echo $c_left)}"

# --- case D: an HTML-comment-only line is ACCOUNTED, never silently dropped ---------------
# MEASURED, not assumed: the id:b048 grammar reports it as `grammar-line` (its own
# UNDERSPECIFIED note (ii) says so explicitly), even though the older classify_todo() calls
# it conforming. So it lands in `reported`, which is what "accounted" means for this
# identity. It must NOT get a bucket of its own -- that would double-count it and break the
# sum. An `<!-- ref:XXXX -->` line, by contrast, is exempt() and IS its own bucket.
D="$TMP/D.md"
cat > "$D" <<'EOF'
# TODO

## Current

<!-- a bare html-comment-only line, as TODO.md really carries -->
- [ ] **An item.** <!-- id:0031 -->
- [ ] A cross-repo pointer that opts out of linting. <!-- ref:aae4 -->

## Done

- [x] **Done item.** <!-- id:0032 -->
EOF
d_total=$(wc -l < "$D")
d_rep=$(reported_lines "$D"); d_nrep=$(n_of "$d_rep")
d_left=$(leftover_lines "$D")
(( d_nrep == 1 )) || fail "case D: the comment-only line must be the single reported line, got $d_nrep ($d_rep)"
[[ "$d_left" == "$d_rep" ]] || fail "case D: comment-only unaccounted [$d_left] must equal reported [$d_rep]"
d_ex=$(b_exempt "$D")
(( d_ex == 0 )) || fail "case D: the ref: line is a checkbox item, so the exempt bucket must be 0, got $d_ex"
d_sum=$(( $(b_blank "$D") + $(b_head "$D") + $(b_item "$D") + d_ex + d_nrep ))
(( d_sum == d_total )) || fail "case D: identity broke -- buckets sum to $d_sum, file has $d_total lines"
pass "case D: comment-only line is accounted (reported as grammar-line); identity holds at $d_total"

# --- cases E/F: THE LIVE LEDGERS. Real baselines, real content. ---------------------------
# Pure IDENTITY, no count of violations: today's ledgers legitimately carry hundreds of
# prose lines and this must never go red for that.
unset LENGTH_BASELINE SHAPE_BASELINE STATE_CLAIM_BASELINE

live_case() {
  local tag="$1" f="$2" total blank head item ex rep nrep left sum
  [[ -f "$f" ]] || fail "case $tag: live ledger not found at $f"
  total=$(wc -l < "$f")
  blank=$(b_blank "$f"); head=$(b_head "$f"); item=$(b_item "$f"); ex=$(b_exempt "$f")
  left=$(leftover_lines "$f")
  rep=$(reported_lines "$f"); nrep=$(n_of "$rep")
  sum=$(( blank + head + item + ex + nrep ))
  if (( sum != total )); then
    fail "case $tag: $f accounting does NOT balance -- blank=$blank heading=$head item=$item exempt=$ex reported=$nrep sum=$sum, file has $total lines (a line is invisible to the checker)"
  fi
  if [[ "$left" != "$rep" ]]; then
    # No `| head`: piping into an early-exiting consumer under `set -o pipefail` lets
    # SIGPIPE become the pipeline's status (id:81d5). Truncate the captured string instead.
    local d; d="$(diff <(printf '%s\n' "$left") <(printf '%s\n' "$rep") || true)"
    printf '%s\n' "${d:0:2000}"
    fail "case $tag: $f -- the unaccounted line SET differs from the reported set (see diff above); counts alone balanced, which means two opposite errors cancelled"
  fi
  pass "case $tag: $(basename "$f") total=$total = blank $blank + heading $head + item $item + exempt $ex + reported $nrep, and the line SETS match"
}

live_case E "$ROOT/ROADMAP.md"
live_case F "$ROOT/TODO.md"

echo "ALL PASS: ledger line accounting balances (fixtures A-D, live ROADMAP.md + TODO.md)"
