#!/usr/bin/env bash
# roadmap:a225
#
# RED SPEC — authored 2026-07-28 by handoff (C3), NOT implemented. EXPECTED-RED while ROADMAP
# id:a225 is unticked. This file is the executable specification; do not weaken it to make it pass.
#
# WHY — the diagram was RIGHT and the code was WRONG, and nothing could tell.
# `docs/diagrams/relay-dispatch.mmd:89` has read, since 2026-07-19:
#     handback -->|"route: hard-split"| discover
# i.e. a hard-split handback flows BACK to discovery — it creates work, the loop continues.
# The code did the opposite: it scored that round dry and stopped with stopReason:"drained"
# (id:c919, fixed 2026-07-28 after loderite run relay-20260728-155041-20282 filed 4 seams and
# the pool quit anyway). The diagram had encoded the correct invariant for nine days.
#
# The existing drift guard (`test_a17a_diagram_state_sync.sh`) could not catch it BY
# CONSTRUCTION: every assertion there is `grep -qiw <noun> <diagram>` — it checks the DIAGRAM
# NAMES every verdict/mode/substrate the CODE has. Direction code→doc, nouns only. It never asks
# whether the CODE HONOURS the diagram's EDGES. So the diagrams are documentation that happens to
# be accurate, not enforcement.
#
# WHAT IS AND IS NOT ACHIEVABLE — stated up front so the implementer does not chase the wrong
# thing: you CANNOT mechanically prove arbitrary code honours a drawn edge. What you CAN do, and
# what this spec requires, is make every edge carry the name of the artifact that enforces it, and
# fail when an edge has none. That converts the diagram into an INDEX OF ENFORCED INVARIANTS, and
# makes an unenforced edge (the c919 gap) visible instead of silent.
#
# CONTRACT:
#   1. Grammar — each transition edge in relay-dispatch.mmd may carry a trailing annotation
#        %% enforced-by: <test-file>[, <test-file>...]   (or an explicit `%% enforced-by: NONE — <why>`)
#      placed on the line following the edge. The parser must read edges mechanically from the
#      .mmd (not a hand-maintained list that can drift from the drawing).
#   2. Every annotated `enforced-by:` test file MUST exist under tests/ — a named-but-absent test
#      is worse than no annotation (it claims coverage that does not exist).
#   3. An edge annotated `NONE` must give a reason; the check REPORTS these as unenforced
#      (loudly, listed) but does not fail on them — that is the honest backlog, not a defect.
#   4. An edge with NO annotation at all FAILS — silence is the state that produced c919.
#   5. The `handback --route:hard-split--> discover` edge specifically must be annotated with a
#      real test, and `tests/test_dry_round_work_creating_handback_c919.sh` satisfies it. This is
#      the regression anchor: the one edge we know was violated must never go unenforced again.
#
# NOT in scope: verifying the code actually implements an edge (impossible in general); adding
# new diagrams; the meeting/ledger diagrams (extend later if this proves its worth).
#
# Hermetic: reads repo files only; no network, no ~/.claude writes.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DISPATCH="$ROOT/docs/diagrams/relay-dispatch.mmd"
CHECKER="$ROOT/relay/scripts/diagram-edge-coverage.sh"

fail=0
note() { echo "FAIL: $*" >&2; fail=1; }

[[ -f "$DISPATCH" ]] || { note "relay-dispatch.mmd not found"; exit 1; }

# (a) The deliverable exists and is executable.
if [[ ! -x "$CHECKER" ]]; then
  note "MISSING: $CHECKER — the id:a225 deliverable (mechanical edge→enforcer coverage checker)"
  echo "EXPECTED-RED: id:a225 not built yet" >&2
  exit 1
fi

out="$("$CHECKER" "$DISPATCH" 2>&1)"; rc=$?

# (b) An unannotated edge must FAIL the checker (silence is the c919 state).
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/bare.mmd" <<'MMD'
flowchart TD
    a["alpha"] -->|"some condition"| b["beta"]
MMD
if "$CHECKER" "$tmp/bare.mmd" >/dev/null 2>&1; then
  note "(b) an edge with NO enforced-by annotation was ACCEPTED — unannotated edges must fail"
fi

# (c) A named-but-absent test must FAIL (a false coverage claim is worse than none).
cat > "$tmp/ghost.mmd" <<'MMD'
flowchart TD
    a["alpha"] -->|"some condition"| b["beta"]
    %% enforced-by: test_this_file_does_not_exist_zzz.sh
MMD
if "$CHECKER" "$tmp/ghost.mmd" >/dev/null 2>&1; then
  note "(c) an enforced-by naming a NONEXISTENT test was ACCEPTED — must fail"
fi

# (d) An explicit NONE with a reason is reported but tolerated (honest backlog).
cat > "$tmp/none.mmd" <<'MMD'
flowchart TD
    a["alpha"] -->|"some condition"| b["beta"]
    %% enforced-by: NONE — no automated check yet, tracked as id:xxxx
MMD
"$CHECKER" "$tmp/none.mmd" >/dev/null 2>&1 \
  || note "(d) an explicit 'NONE — <reason>' edge must be TOLERATED (reported, not fatal)"
"$CHECKER" "$tmp/none.mmd" 2>&1 | grep -qi 'unenforced\|NONE' \
  || note "(d) unenforced edges must be REPORTED loudly, not silently tolerated"

# (e) The regression anchor: the edge that c919 violated must be enforced by a real test.
grep -q 'hard-split' "$DISPATCH" \
  || note "(e) relay-dispatch.mmd no longer contains the hard-split handback edge — that edge is the c919 anchor"
[[ $rc -eq 0 ]] \
  || note "(e) the live relay-dispatch.mmd does not pass the coverage checker — annotate its edges (this is the real work)"
"$CHECKER" "$DISPATCH" 2>&1 | grep -q 'test_dry_round_work_creating_handback_c919.sh' \
  || note "(e) the hard-split→discover edge is not annotated with its enforcing test (c919) — the one edge known to have been violated must never go unenforced"

[[ $fail -eq 0 ]] || exit 1
echo "ALL PASS: every relay-dispatch.mmd edge names its enforcer, or declares NONE with a reason (id:a225)"
