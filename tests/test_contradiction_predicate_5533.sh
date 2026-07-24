#!/usr/bin/env bash
# roadmap:5533 — Shared two-directional state-claim contradiction predicate (AMENDS
# id:dafa). ONE engine (relay/scripts/lib-state-claim.sh), TWO callers:
# roadmap-lint.sh's DECIDED-LEFT-OPEN rule and todo-conformance.sh's twin check.
#
# Direction (i): an OPEN `- [ ]` item whose VISIBLE text asserts a terminal state
#   about ITSELF (RESOLVED / DECIDED <YYYY-MM-DD> / SUPERSEDED / DONE / CLOSED /
#   DEFERRED) is a violation, UNLESS the assertion is scoped to a DIFFERENT id
#   ("id:XXXX is SUPERSEDED").
# Direction (ii): an OPEN `- [ ]` item whose HTML COMMENT asserts a close while
#   the visible text and the checkbox both still say open is a violation.
#
# Cross-linter invariant: roadmap-lint.sh and todo-conformance.sh MUST return the
# SAME verdict on identical line text.
#
# Hermetic: fixture ledgers in mktemp -d, never ~/.claude.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$ROOT/relay/scripts/lib-state-claim.sh"
LINT="$ROOT/relay/scripts/roadmap-lint.sh"
TODOC="$ROOT/relay/scripts/todo-conformance.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$LIB" ]] || fail "lib-state-claim.sh not found at $LIB"
bash -n "$LIB" || fail "lib-state-claim.sh fails bash -n"
pass "lib-state-claim.sh exists, parses"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# --- direct engine fixtures (the three must-pass fixtures from the spec) --------
source "$LIB"

l_scoped='- [ ] foo — id:1234 is SUPERSEDED by this <!-- id:aaaa -->'
l_resolved='- [ ] foo — RESOLVED 2026-07-19 <!-- id:bbbb -->'
l_comment_close='- [ ] foo <!-- closed 2026-07-19 --> <!-- id:cccc -->'
l_clean='- [ ] a perfectly ordinary open item <!-- id:dddd -->'

v_scoped="$(state_claim_violation "$l_scoped")"
[[ -z "$v_scoped" ]] || fail "scoped assertion (id:XXXX is SUPERSEDED) wrongly fired: '$v_scoped'"
pass "(i) scoped-to-another-id assertion PASSES (no violation)"

v_resolved="$(state_claim_violation "$l_resolved")"
[[ "$v_resolved" == *i* ]] || fail "self-RESOLVED-while-open did not fire direction (i): '$v_resolved'"
pass "(i) self-asserted RESOLVED (unscoped) FAILS"

v_ccl="$(state_claim_violation "$l_comment_close")"
[[ "$v_ccl" == *ii* ]] || fail "comment-only close did not fire direction (ii): '$v_ccl'"
pass "(ii) comment-only close (visible text + checkbox both open) FAILS"

v_clean="$(state_claim_violation "$l_clean")"
[[ -z "$v_clean" ]] || fail "a clean open item wrongly fired: '$v_clean'"
pass "a clean open item fires nothing"

# Backticked bare tokens are not edges either (mirrors id:8913's must-not-fire class);
# a terminal word appearing only as a backtick-quoted CODE EXAMPLE would still count
# under this simpler visible-text predicate (out of scope — this predicate is a
# textual assertion check, not the anchored `settles:`/`decided-in:` edge grammar).

# --- roadmap-lint.sh wiring: uses the shared engine, preserves existing wording --
[[ -f "$LINT" ]] || fail "roadmap-lint.sh not found at $LINT"
grep -q 'lib-state-claim.sh' "$LINT" || fail "roadmap-lint.sh does not source lib-state-claim.sh"
pass "roadmap-lint.sh sources the shared engine"

R="$tmp/ROADMAP.md"
cat >"$R" <<'MD'
# Roadmap

## Items

- [ ] [ROUTINE] foo — id:1234 is SUPERSEDED by this <!-- id:e001 -->
- [ ] [ROUTINE] foo — RESOLVED 2026-07-19 <!-- id:e002 -->
- [ ] [ROUTINE] foo <!-- closed 2026-07-19 --> <!-- id:e003 -->
- [ ] [ROUTINE] a perfectly clean active item <!-- id:e004 -->
MD

set +e
out="$(bash "$LINT" "$R" 2>"$tmp/err")"; rc=$?
set -e
[[ $rc -eq 0 ]] || fail "default (non-strict) run must exit 0; got $rc (err: $(cat "$tmp/err"))"

! grep -q 'id:e001' "$tmp/err" || fail "scoped assertion e001 wrongly fired in roadmap-lint (err: $(cat "$tmp/err"))"
grep -q 'DECIDED-LEFT-OPEN: open item id:e002' "$tmp/err" \
  || fail "unscoped self-RESOLVED e002 did not fire DECIDED-LEFT-OPEN in roadmap-lint (err: $(cat "$tmp/err"))"
grep -q 'DECIDED-LEFT-OPEN (comment-only close): open item id:e003' "$tmp/err" \
  || fail "comment-only close e003 did not fire the direction-(ii) rule in roadmap-lint (err: $(cat "$tmp/err"))"
! grep -q 'id:e004' "$tmp/err" || fail "a clean item e004 wrongly fired in roadmap-lint (err: $(cat "$tmp/err"))"
pass "roadmap-lint.sh: scoped passes, unscoped-RESOLVED + comment-only-close both fire, clean item silent"

# --- todo-conformance.sh wiring: same predicate, same verdict on identical text ---
[[ -f "$TODOC" ]] || fail "todo-conformance.sh not found at $TODOC"
grep -q 'lib-state-claim.sh' "$TODOC" || fail "todo-conformance.sh does not source lib-state-claim.sh"
pass "todo-conformance.sh sources the shared engine"

T="$tmp/TODO.md"
cat >"$T" <<'MD'
# TODO

## Current
- [ ] foo — id:1234 is SUPERSEDED by this <!-- id:e001 -->
- [ ] foo — RESOLVED 2026-07-19 <!-- id:e002 -->
- [ ] foo <!-- closed 2026-07-19 --> <!-- id:e003 -->
- [ ] a perfectly clean active item <!-- id:e004 -->
MD

tout="$(bash "$TODOC" "$T" 2>/dev/null)"
! grep -qP '^decided-left-open\t\d+\t.*id:e001' <<<"$tout" \
  || fail "scoped assertion e001 wrongly fired in todo-conformance:
$tout"
grep -qP '^decided-left-open\t\d+\t.*id:e002' <<<"$tout" \
  || fail "unscoped self-RESOLVED e002 did not fire decided-left-open in todo-conformance:
$tout"
grep -qP '^decided-left-open\t\d+\t.*id:e003' <<<"$tout" \
  || fail "comment-only close e003 did not fire decided-left-open in todo-conformance:
$tout"
! grep -q 'id:e004' <<<"$tout" \
  || fail "a clean item e004 wrongly fired in todo-conformance:
$tout"
pass "todo-conformance.sh: same predicate, same verdict per line"

# --- cross-linter invariant: identical line text → identical verdict -------------
# Build one shared fixture item text and assert both scripts agree, line by line.
for line in \
  '- [ ] [ROUTINE] foo — id:1234 is SUPERSEDED by this <!-- id:f001 -->' \
  '- [ ] [ROUTINE] foo — RESOLVED 2026-07-19 <!-- id:f002 -->' \
  '- [ ] [ROUTINE] foo <!-- closed 2026-07-19 --> <!-- id:f003 -->' \
  '- [ ] [ROUTINE] a perfectly clean active item <!-- id:f004 -->'
do
  v="$(state_claim_violation "$line")"
  cat >"$tmp/one_roadmap.md" <<MD
# Roadmap

## Items

$line
MD
  cat >"$tmp/one_todo.md" <<MD
# TODO

## Current
$line
MD
  set +e
  bash "$LINT" "$tmp/one_roadmap.md" >/dev/null 2>"$tmp/one_err"; lint_rc=$?
  set -e
  lint_fired=0
  grep -q 'DECIDED-LEFT-OPEN' "$tmp/one_err" && lint_fired=1
  todo_out="$(bash "$TODOC" "$tmp/one_todo.md" 2>/dev/null)"
  todo_fired=0
  grep -q '^decided-left-open' <<<"$todo_out" && todo_fired=1
  expect=0; [[ -n "$v" ]] && expect=1
  [[ "$lint_fired" -eq "$expect" ]] || fail "cross-linter invariant: roadmap-lint verdict ($lint_fired) != engine verdict ($expect) for: $line"
  [[ "$todo_fired" -eq "$expect" ]] || fail "cross-linter invariant: todo-conformance verdict ($todo_fired) != engine verdict ($expect) for: $line"
  [[ "$lint_fired" -eq "$todo_fired" ]] || fail "cross-linter invariant: roadmap-lint ($lint_fired) and todo-conformance ($todo_fired) DISAGREE on identical line text: $line"
done
pass "cross-linter invariant holds: roadmap-lint.sh and todo-conformance.sh agree on every fixture line"

# --- ground-truth regression: the id:931c line (reverted from the refuted 'obsoleted'
#     prose reword) must NOT fire — it is scoped to id:f599, not to 931c itself. -----
grep -q 'obsoleted by the model' "$ROOT/ROADMAP.md" \
  && fail "the refuted id:931c 'obsoleted' reword is still present in ROADMAP.md — must be reverted to SUPERSEDED"
grep -q 'id:f599 is SUPERSEDED by the model' "$ROOT/ROADMAP.md" \
  || fail "the id:931c line was not reverted to the scoped 'id:f599 is SUPERSEDED' wording"
pass "id:931c prose reword reverted (SUPERSEDED, scoped to id:f599, not the item itself)"

echo "ALL PASS: id:5533 shared two-directional state-claim contradiction predicate"
