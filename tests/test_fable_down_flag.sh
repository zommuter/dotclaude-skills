#!/usr/bin/env bash
# roadmap:3737 — --fable-down / -d flag: static structure checks for relay-loop.js and SKILL.md.
# Ensures the executor-only degrade path is present without running a live pool.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JS="$SRC_DIR/fables-turn/scripts/relay-loop.js"
SKILL="$SRC_DIR/fables-turn/SKILL.md"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$JS" ]] || fail "relay-loop.js not found at $JS"
[[ -f "$SKILL" ]] || fail "SKILL.md not found at $SKILL"

# relay-loop.js: FABLE_DOWN constant read from args.fableDown
grep -q "FABLE_DOWN" "$JS" || fail "relay-loop.js does not define FABLE_DOWN"
grep -q "args.fableDown" "$JS" || fail "relay-loop.js does not read args.fableDown"
pass "relay-loop.js reads args.fableDown into FABLE_DOWN"

# relay-loop.js: actionable queue is partitioned when fableDown is set
grep -q "fableDownDeferred" "$JS" || fail "relay-loop.js missing fableDownDeferred partition variable"
pass "relay-loop.js has fableDownDeferred partition variable"

# relay-loop.js: deferred units carry the --fable-down deferral reason in queued state
grep -q "deferred: --fable-down" "$JS" || fail "relay-loop.js does not label deferred units with --fable-down reason"
pass "relay-loop.js labels deferred units with --fable-down reason"

# relay-loop.js: zero-execute edge case exits cleanly
grep -q "no executor work" "$JS" || fail "relay-loop.js missing zero-execute + fable-down clean-exit log line"
pass "relay-loop.js handles zero-execute + --fable-down clean exit"

# relay-loop.js: integrator is untouched (D2: only the dispatch queue is affected)
grep -q -- "--no-ff" "$JS" || fail "integrator --no-ff merge removed (must be untouched)"
grep -q "ckpt-tag.sh" "$JS" || fail "integrator ckpt-tag.sh reference removed (must be untouched)"
grep -q "git-lock-push.sh --ff-only" "$JS" || fail "integrator push via git-lock-push.sh --ff-only removed"
pass "integrator chain intact (--no-ff, ckpt-tag.sh, git-lock-push.sh --ff-only)"

# relay-loop.js: AskUserQuestion invariant preserved (unattended D2)
if grep -q "AskUserQuestion" "$JS"; then
  fail "relay-loop.js must never call AskUserQuestion"
fi
pass "no AskUserQuestion call"

# SKILL.md: documents --fable-down and -d
grep -q -- "--fable-down" "$SKILL" || fail "SKILL.md does not document --fable-down flag"
grep -qE '^\s*/fables-turn -d' "$SKILL" || fail "SKILL.md invocation block missing /fables-turn -d line"
pass "SKILL.md documents --fable-down and -d in invocation block"

# SKILL.md: flag is in the configuration knobs table
grep -q "fable-down.*-d\|-d.*fable-down" "$SKILL" || fail "SKILL.md knobs table missing --fable-down / -d row"
pass "SKILL.md knobs table documents --fable-down / -d"

# SKILL.md: Opus self-guard with 10s window
grep -q "sleep 10" "$SKILL" || fail "SKILL.md does not document the Opus self-guard (sleep 10)"
pass "SKILL.md documents Opus self-guard (sleep 10)"

# SKILL.md: guard is suppressed when -d is passed
grep -qi "suppress\|skip.*guard\|guard.*skip\|no.*warning\|pass.*-d.*skip\|-d.*suppress\|suppresses.*guard\|guard.*-d" "$SKILL" \
  || fail "SKILL.md does not document that -d suppresses the Opus self-guard"
pass "SKILL.md documents -d suppresses Opus self-guard"

# SKILL.md: args.fableDown threaded into Workflow launch
grep -q "args.fableDown" "$SKILL" || fail "SKILL.md does not document threading args.fableDown to the Workflow"
pass "SKILL.md documents args.fableDown Workflow pass-through"
