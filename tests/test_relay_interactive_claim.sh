#!/usr/bin/env bash
# roadmap:0902 — the INTERACTIVE relay orchestrator modes (/relay handoff, /relay review,
# /relay human) acquire/respect the cross-session claim lease, closing the last gap the
# autonomous pool (id:ebfb) + executor (v4) + /meeting (id:d748) had already covered.
# Static checks on the SKILL orchestrator invariants + human.md.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$SRC_DIR/relay/SKILL.md"
HUMAN="$SRC_DIR/relay/references/human.md"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$SKILL" ]] || fail "relay/SKILL.md not found"
[[ -f "$HUMAN" ]] || fail "relay/references/human.md not found"

# (1) Orchestrator invariant: acquire the lease BEFORE spawning each handoff/review child,
#     skip the repo on refusal.
grep -q "claim.sh acquire <repo> --run relay-" "$SKILL" || fail "SKILL orchestrator does not acquire the repo lease before spawning a child"
grep -qi "REFUSED" "$SKILL" || fail "SKILL orchestrator does not handle a refused lease"
grep -qi "never spawn a colliding child" "$SKILL" || fail "SKILL orchestrator does not skip a claimed repo"
pass "handoff/review acquire the lease before fan-out, skip on refusal (id:0902)"

# (2) Orchestrator invariant: release the lease run-scoped at integration.
grep -q "claim.sh release <repo> --run relay-" "$SKILL" || fail "SKILL orchestrator does not release the lease at integration"
pass "handoff/review release the lease run-scoped at integration (id:0902)"

# (3) human mode LEDGER write-back is now peek-and-warn, NOT lease-gated (TODO id:c144 supersedes
#     the id:0902 DEFER for ledger-only writes). The hard lease guards code/worktree only; a
#     ledger write is safe under a live pool via flock + atomic commit + cross-ledger backstop.
grep -qi "peek-and-warn, not lease-gated (id:c144" "$HUMAN" \
  || fail "human mode ledger write-back is not the id:c144 peek-and-warn (supersedes 0902 DEFER)"
grep -q "claim.sh peek" "$HUMAN" || fail "human mode does not peek for a live pool holder"
grep -qi "guards CODE/WORKTREE integration only" "$HUMAN" \
  || fail "human mode does not state the hard lease guards code/worktree only (ledger writes exempt)"
# The ledger write-back must no longer acquire the lease as a blocking gate.
if grep -q "claim.sh acquire <repo> --run human-" "$HUMAN"; then
  fail "human mode still acquires the lease as a blocking gate for the ledger write (c144 removes this)"
fi
pass "human mode ledger write-back peeks-and-warns then proceeds (id:c144), not lease-deferred"

# (4) runId is UNIQUE per run (seconds + random), not minute-granular — otherwise two
# concurrent pools share a runId and the lease re-entrancy + worktree guard both false-pass,
# letting them double-work a repo.
# id:86a2 (2026-07-23): runId generation moved from the discover-prelude PROMPT into the
# mechanized wrapper discover-prelude.sh (a model:'bash' dispatch); relay-loop.js now DELEGATES
# it. So assert the second-granular + $RANDOM invariant in the wrapper (its new home), and that
# relay-loop.js dispatches the wrapper.
JS="$SRC_DIR/relay/scripts/relay-loop.js"
PRELUDE_SH="$SRC_DIR/relay/scripts/discover-prelude.sh"
grep -q 'discover-prelude.sh' "$JS" || fail "relay-loop.js no longer dispatches discover-prelude.sh (the mechanized prelude wrapper)"
grep -q '%H%M%S' "$PRELUDE_SH" || fail "discovery runId is not second-granular (%H%M%S) in discover-prelude.sh — concurrent pools could share a minute-granular runId"
grep -q '\$RANDOM' "$PRELUDE_SH" || fail "discovery runId has no random suffix in discover-prelude.sh — two pools in the same second could still collide"
pass "discovery runId is unique per run (seconds + \$RANDOM, in mechanized discover-prelude.sh) — concurrent pools never share one"

echo "ALL PASS: interactive relay modes are claim-aware + runId unique per run (id:0902)"
