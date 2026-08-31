#!/usr/bin/env bash
# roadmap:bf19 — DECIDED-LEFT-OPEN (roadmap-lint.sh rule 3(b) / lib-state-claim.sh)
# has two false-positive classes that make it permanently noisy on exactly the
# items it should ignore:
#
#   (a) no `@container` exemption — rule 3(a) DECOMPOSED-CONTAINER explicitly
#       exempts `@container` but 3(b) did not, so a correctly-marked container
#       (BY CONSTRUCTION a decomposed item that legitimately records a decision
#       and stays open until its seams close) tripped 3(b) forever.
#   (b) the scoped-assertion strip in lib-state-claim.sh was too narrow — it only
#       stripped the literal " is " copula form ("id:XXXX is SUPERSEDED"), so
#       real prose about OTHER ids in the copula-less form ("id:244b CLOSED
#       matrix-complete 2026-06-30") fired the rule on an item asserting nothing
#       about ITSELF.
#
# Fix (ONE change, both halves, per the item's twin-consumer constraint): the
# @container exemption and the widened strip both live in the SHARED engine
# (lib-state-claim.sh's state_claim_direction_i/ii), so roadmap-lint.sh and
# todo-conformance.sh — the two consumers lib-state-claim.sh's own header
# requires to return the SAME verdict — pick up both fixes automatically without
# a second, divergence-prone edit.
#
# Three fixtures, run through BOTH consumers:
#   1. an open @container line carrying a decision record -> NO WARN
#   2. a line whose only terminal words are scoped to OTHER ids -> NO WARN
#   3. a genuine self-directed left-open decision claim -> STILL WARNs (the rule
#      must not be dissolved into silence)
#
# Hermetic: fixture ledgers in mktemp -d, no ~/.claude, no network.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$ROOT/relay/scripts/lib-state-claim.sh"
LINT="$ROOT/relay/scripts/roadmap-lint.sh"
TODOC="$ROOT/relay/scripts/todo-conformance.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$LIB" ]] || fail "lib-state-claim.sh not found at $LIB"
bash -n "$LIB" || fail "lib-state-claim.sh fails bash -n"
[[ -x "$LINT" ]] || fail "roadmap-lint.sh not found/executable at $LINT"
[[ -x "$TODOC" ]] || fail "todo-conformance.sh not found/executable at $TODOC"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# --- direct-engine checks (fast, precise) -----------------------------------
source "$LIB"

# (1) @container carrying a decision record -> direction (i) does NOT fire.
l_container='- [ ] [HARD - meeting] DECOMPOSED into seams, DECIDED 2026-07-20 @container <!-- id:d001 -->'
v_container="$(state_claim_violation "$l_container")"
[[ -z "$v_container" ]] || fail "@container item wrongly fired state_claim_violation: '$v_container'"
pass "engine: @container-marked open item does not fire DECIDED-LEFT-OPEN"

# (1b) @container with a comment-only close (direction ii) also exempt.
l_container_ii='- [ ] [HARD - meeting] DECOMPOSED into seams @container <!-- closed 2026-07-20 --> <!-- id:d002 -->'
v_container_ii="$(state_claim_violation "$l_container_ii")"
[[ -z "$v_container_ii" ]] || fail "@container item wrongly fired direction (ii): '$v_container_ii'"
pass "engine: @container-marked open item does not fire direction (ii) either"

# (2) terminal word scoped to ANOTHER id, copula-less form -> does NOT fire.
l_scoped='- [ ] [ROUTINE] status update: id:244b CLOSED matrix-complete 2026-06-30 <!-- id:d003 -->'
v_scoped="$(state_claim_violation "$l_scoped")"
[[ -z "$v_scoped" ]] || fail "copula-less other-id-scoped CLOSED wrongly fired: '$v_scoped'"
pass "engine: copula-less other-id-scoped terminal word ('id:XXXX CLOSED …') does not fire"

# (2b) two scoped mentions in one line ("… DONE + … DONE").
l_scoped2='- [ ] [ROUTINE] id:aaa1 DONE + id:aaa2 DONE, tracking both <!-- id:d004 -->'
v_scoped2="$(state_claim_violation "$l_scoped2")"
[[ -z "$v_scoped2" ]] || fail "two other-id-scoped DONE mentions wrongly fired: '$v_scoped2'"
pass "engine: multiple other-id-scoped terminal words in one line do not fire"

# (2c) the pre-existing copula form ("id:XXXX is SUPERSEDED") still doesn't fire
#      (no regression from widening the strip).
l_scoped_is='- [ ] [ROUTINE] id:9999 is SUPERSEDED by this plan <!-- id:d005 -->'
v_scoped_is="$(state_claim_violation "$l_scoped_is")"
[[ -z "$v_scoped_is" ]] || fail "copula-form other-id-scoped SUPERSEDED regressed: '$v_scoped_is'"
pass "engine: copula-form other-id-scoped terminal word still does not fire (no regression)"

# (3) genuine self-directed left-open decision claim STILL WARNs (not dissolved).
l_self='- [ ] [ROUTINE] this plan was decided 2026-07-01 but never closed <!-- id:d006 -->'
v_self="$(state_claim_violation "$l_self")"
[[ "$v_self" == *i* ]] || fail "genuine self-directed decided-left-open claim must STILL fire: '$v_self'"
pass "engine: genuine self-directed DECIDED-LEFT-OPEN claim still fires"

l_self_closed='- [ ] [ROUTINE] the plan is CLOSED already <!-- id:d007 -->'
v_self_closed="$(state_claim_violation "$l_self_closed")"
[[ "$v_self_closed" == *i* ]] || fail "genuine self-directed CLOSED claim must STILL fire: '$v_self_closed'"
pass "engine: genuine self-directed CLOSED claim still fires"

# --- twin-consumer check: roadmap-lint.sh and todo-conformance.sh agree --------
cat >"$tmp/TODO.md" <<'MD'
# TODO
- [ ] twin stub <!-- id:d001 -->
- [ ] twin stub <!-- id:d002 -->
- [ ] twin stub <!-- id:d003 -->
- [ ] twin stub <!-- id:d004 -->
- [ ] twin stub <!-- id:d005 -->
- [ ] twin stub <!-- id:d006 -->
- [ ] twin stub <!-- id:d007 -->
MD

R="$tmp/ROADMAP.md"
cat >"$R" <<MD
# Roadmap

## Items

$l_container
$l_container_ii
$l_scoped
$l_scoped2
$l_scoped_is
$l_self
$l_self_closed
MD

set +e
bash "$LINT" --strict "$R" >/dev/null 2>"$tmp/lint_err"; lint_rc=$?
set -e

! grep -q 'id:d001' "$tmp/lint_err" || fail "roadmap-lint.sh fired on @container item d001: $(cat "$tmp/lint_err")"
! grep -q 'id:d002' "$tmp/lint_err" || fail "roadmap-lint.sh fired on @container item d002: $(cat "$tmp/lint_err")"
! grep -q 'id:d003' "$tmp/lint_err" || fail "roadmap-lint.sh fired on other-id-scoped item d003: $(cat "$tmp/lint_err")"
! grep -q 'id:d004' "$tmp/lint_err" || fail "roadmap-lint.sh fired on other-id-scoped item d004: $(cat "$tmp/lint_err")"
! grep -q 'id:d005' "$tmp/lint_err" || fail "roadmap-lint.sh fired on other-id-scoped item d005: $(cat "$tmp/lint_err")"
grep -q 'DECIDED-LEFT-OPEN: open item id:d006' "$tmp/lint_err" \
  || fail "roadmap-lint.sh did NOT fire on genuine self-directed item d006: $(cat "$tmp/lint_err")"
grep -q 'DECIDED-LEFT-OPEN: open item id:d007' "$tmp/lint_err" \
  || fail "roadmap-lint.sh did NOT fire on genuine self-directed item d007: $(cat "$tmp/lint_err")"
[[ $lint_rc -ne 0 ]] || fail "--strict must exit nonzero given genuine violations d006/d007 remain (rc=$lint_rc)"
pass "roadmap-lint.sh: @container and other-id-scoped items exempt; genuine self-directed items still fire"

T="$tmp/TODO_scan.md"
cat >"$T" <<MD
# TODO

## Current
$l_container
$l_container_ii
$l_scoped
$l_scoped2
$l_scoped_is
$l_self
$l_self_closed
MD

tout="$(bash "$TODOC" "$T" 2>/dev/null)"
! grep -qP '\bid:d001\b' <<<"$tout" || fail "todo-conformance.sh fired on @container item d001: $tout"
! grep -qP '\bid:d002\b' <<<"$tout" || fail "todo-conformance.sh fired on @container item d002: $tout"
! grep -qP '\bid:d003\b' <<<"$tout" || fail "todo-conformance.sh fired on other-id-scoped item d003: $tout"
! grep -qP '\bid:d004\b' <<<"$tout" || fail "todo-conformance.sh fired on other-id-scoped item d004: $tout"
! grep -qP '\bid:d005\b' <<<"$tout" || fail "todo-conformance.sh fired on other-id-scoped item d005: $tout"
grep -qP 'decided-left-open.*\bid:d006\b' <<<"$tout" \
  || fail "todo-conformance.sh did NOT fire on genuine self-directed item d006: $tout"
grep -qP 'decided-left-open.*\bid:d007\b' <<<"$tout" \
  || fail "todo-conformance.sh did NOT fire on genuine self-directed item d007: $tout"
pass "todo-conformance.sh: SAME verdicts as roadmap-lint.sh on all three fixture classes (twin-consumer constraint)"

echo "ALL PASS: id:bf19 DECIDED-LEFT-OPEN @container carve-out + widened other-id-scoped strip"
