#!/usr/bin/env bash
# roadmap:3f7e — DEP-PROSE-UNTYPED: WARN when an open item carries `(DEP: <id>)` /
# `(dep <id>)` prose but no matching typed `<!-- gated-on:id -->` marker.
#
# WHY (observed 2026-07-24, run relay-20260724-160054-19815): zelegator's df0f/c106
# gated on `(DEP: 0cd5)` prose, which classify-repo.sh correctly never reads as a gate
# (id:65f5/4da4/0d58) — so both were mis-dispatched as ready with zero actionable work.
# The fix is NOT teaching the classifier to read prose (re-opens the substring trap);
# it is a lint that pushes the author to retype the annotation.
#
# Twin-consumer (id:3441's constraint): roadmap-lint.sh and todo-conformance.sh must
# agree on every fixture here — both read the SAME shared engine
# (lib-typed-edges.sh's typed_edges_dep_prose_untyped_of_line), so this file drives
# both consumers against identical line fixtures.
#
# WARN, never ERROR — this rule never contributes to either script's nonzero exit,
# not even under --strict (the ROADMAP item's own ruling: the existing backlog
# already carries this prose; escalation is a separate owner call).
#
# Hermetic: tmp fixtures, no ~/.claude, no network.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LINT="$ROOT/relay/scripts/roadmap-lint.sh"
TODOC="$ROOT/relay/scripts/todo-conformance.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$LINT" ]] || fail "roadmap-lint.sh not found/executable"
[[ -x "$TODOC" ]] || fail "todo-conformance.sh not found/executable"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# A sibling TODO.md twin for every fixture id (id:213a NO-ACCEPTANCE-NO-TWIN stays
# silent here — this file's own concern is the DEP-PROSE-UNTYPED rule).
cat > "$WORK/TODO.md" <<'MD'
# TODO
- [ ] twin stub <!-- id:aaaa -->
- [ ] twin stub <!-- id:bbbb -->
- [ ] twin stub <!-- id:cccc -->
- [ ] twin stub <!-- id:dddd -->
- [ ] twin stub <!-- id:0cd5 -->
MD

# --- roadmap-lint.sh fixture --------------------------------------------------
cat > "$WORK/ROADMAP.md" <<'EOF'
# Roadmap

## Items

- [ ] [ROUTINE] untyped DEP prose, no gated-on marker at all (DEP: 0cd5) <!-- id:aaaa -->
- [ ] [ROUTINE] typed DEP prose, matching gated-on marker (DEP: 0cd5) <!-- gated-on:0cd5 --> <!-- id:bbbb -->
- [ ] [ROUTINE] DEP mention only inside a backtick span, e.g. `(DEP: 0cd5)` in docs <!-- id:cccc -->
- [x] [ROUTINE] closed item with untyped DEP prose (DEP: 0cd5) <!-- id:dddd -->
- [ ] [ROUTINE] the DEP-cited target itself, so DEAD-GATE (id:49e0) stays silent and this file's own assertions test ONLY the DEP-PROSE-UNTYPED rule <!-- id:0cd5 -->
EOF

rl_out="$("$LINT" "$WORK/ROADMAP.md" 2>&1)"
rl_rc=$?

[[ "$rl_rc" -eq 0 ]] || { echo "$rl_out"; fail "roadmap-lint.sh must exit 0 — DEP-PROSE-UNTYPED never fails the run (WARN, not ERROR)"; }
pass "roadmap-lint.sh: DEP-PROSE-UNTYPED never fails the run (exit 0)"

grep -qF 'DEP-PROSE-UNTYPED' <<<"$rl_out" || { echo "$rl_out"; fail "roadmap-lint.sh: id:aaaa's untyped (DEP: 0cd5) did not WARN"; }
grep -qF 'id:aaaa' <<<"$rl_out" || { echo "$rl_out"; fail "roadmap-lint.sh: WARN did not name id:aaaa"; }
grep -qF '0cd5' <<<"$rl_out" || { echo "$rl_out"; fail "roadmap-lint.sh: WARN did not name the untyped id 0cd5"; }
pass "roadmap-lint.sh: untyped (DEP: 0cd5) prose WARNs, naming the item id and the untyped dep id"

# id:bbbb (typed) must NOT trigger a DEP-PROSE-UNTYPED line for bbbb specifically —
# check no DEP-PROSE-UNTYPED report line mentions id:bbbb.
! grep 'DEP-PROSE-UNTYPED' <<<"$rl_out" | grep -qF 'id:bbbb' || { echo "$rl_out"; fail "roadmap-lint.sh: id:bbbb has a matching gated-on marker — must NOT WARN"; }
pass "roadmap-lint.sh: (DEP: 0cd5) WITH matching <!-- gated-on:0cd5 --> does not WARN"

! grep 'DEP-PROSE-UNTYPED' <<<"$rl_out" | grep -qF 'id:cccc' || { echo "$rl_out"; fail "roadmap-lint.sh: id:cccc's DEP mention is backtick-quoted (docs) — must NOT WARN"; }
pass "roadmap-lint.sh: a backtick-quoted (DEP: ...) mention does not WARN"

! grep 'DEP-PROSE-UNTYPED' <<<"$rl_out" | grep -qF 'id:dddd' || { echo "$rl_out"; fail "roadmap-lint.sh: id:dddd is a closed [x] item — must NOT WARN"; }
pass "roadmap-lint.sh: a closed [x] item with untyped DEP prose does not WARN"

# --- --strict never escalates this rule ---------------------------------------
rl_strict_out="$("$LINT" --strict "$WORK/ROADMAP.md" 2>&1)"
rl_strict_rc=$?
[[ "$rl_strict_rc" -eq 0 ]] || { echo "$rl_strict_out"; fail "roadmap-lint.sh --strict must still exit 0 — DEP-PROSE-UNTYPED never escalates"; }
pass "roadmap-lint.sh --strict: DEP-PROSE-UNTYPED never escalates to a hard violation"

# --- todo-conformance.sh fixture (twin-consumer agreement) --------------------
cat > "$WORK/TODO_dep.md" <<'EOF'
# TODO

## Current
- [ ] untyped DEP prose, no gated-on marker at all (DEP: 0cd5) <!-- id:aaaa -->
- [ ] typed DEP prose, matching gated-on marker (DEP: 0cd5) <!-- gated-on:0cd5 --> <!-- id:bbbb -->
- [ ] DEP mention only inside a backtick span, e.g. `(DEP: 0cd5)` in docs <!-- id:cccc -->
- [x] closed item with untyped DEP prose (DEP: 0cd5) <!-- id:dddd -->
EOF

tc_out="$("$TODOC" "$WORK/TODO_dep.md" 2>/dev/null)"
tc_rc=$?
[[ "$tc_rc" -eq 0 ]] || { echo "$tc_out"; fail "todo-conformance.sh must exit 0 by default (report-only)"; }

grep -qF 'dep-prose-untyped' <<<"$tc_out" || { echo "$tc_out"; fail "todo-conformance.sh: id:aaaa's untyped (DEP: 0cd5) did not report a finding"; }
grep 'dep-prose-untyped' <<<"$tc_out" | grep -qF '0cd5' || { echo "$tc_out"; fail "todo-conformance.sh: finding did not name the untyped id 0cd5"; }
pass "todo-conformance.sh: untyped (DEP: 0cd5) prose is reported as a dep-prose-untyped finding"

bbbb_line="$(grep -F 'id:bbbb' <<<"$tc_out" || true)"
[[ -z "$bbbb_line" || "$bbbb_line" != *dep-prose-untyped* ]] || { echo "$tc_out"; fail "todo-conformance.sh: id:bbbb has a matching gated-on marker — must NOT report dep-prose-untyped"; }
pass "todo-conformance.sh: (DEP: 0cd5) WITH matching <!-- gated-on:0cd5 --> does not report a finding"

cccc_line="$(grep -F 'id:cccc' <<<"$tc_out" || true)"
[[ -z "$cccc_line" || "$cccc_line" != *dep-prose-untyped* ]] || { echo "$tc_out"; fail "todo-conformance.sh: id:cccc's DEP mention is backtick-quoted — must NOT report a finding"; }
pass "todo-conformance.sh: a backtick-quoted (DEP: ...) mention does not report a finding"

dddd_line="$(grep -F 'id:dddd' <<<"$tc_out" || true)"
[[ -z "$dddd_line" || "$dddd_line" != *dep-prose-untyped* ]] || { echo "$tc_out"; fail "todo-conformance.sh: closed [x] item must NOT report a finding"; }
pass "todo-conformance.sh: a closed [x] item with untyped DEP prose does not report a finding"

# --strict never escalates this rule for todo-conformance.sh either.
tc_strict_out="$("$TODOC" --strict "$WORK/TODO_dep.md" 2>/dev/null)"
tc_strict_rc=$?
[[ "$tc_strict_rc" -eq 0 ]] || { echo "$tc_strict_out"; fail "todo-conformance.sh --strict must still exit 0 — DEP-PROSE-UNTYPED never escalates"; }
pass "todo-conformance.sh --strict: DEP-PROSE-UNTYPED never escalates to a hard failure"

echo "ALL PASS: test_dep_prose_untyped_gate_3f7e.sh"
