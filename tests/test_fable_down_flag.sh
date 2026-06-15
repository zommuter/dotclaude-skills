#!/usr/bin/env bash
# roadmap:3737 — --fable-down / -d flag: static structure checks for relay-loop.js and SKILL.md.
# Ensures the executor-only degrade path is present without running a live pool.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JS="$SRC_DIR/relay/scripts/relay-loop.js"
SKILL="$SRC_DIR/relay/SKILL.md"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$JS" ]] || fail "relay-loop.js not found at $JS"
[[ -f "$SKILL" ]] || fail "SKILL.md not found at $SKILL"

# relay-loop.js: FABLE_DOWN constant read from the normalized args object
grep -q "FABLE_DOWN" "$JS" || fail "relay-loop.js does not define FABLE_DOWN"
grep -qE 'FABLE_DOWN = !!A\.fableDown' "$JS" \
  || fail "relay-loop.js does not read fableDown from the normalized args object (A.fableDown)"
pass "relay-loop.js reads A.fableDown into FABLE_DOWN"

# relay-loop.js: args is normalized from a possible JSON string before reading.
# Regression guard — the harness delivers Workflow args stringified, so reading
# args.fableDown off a raw string yields undefined and silently disables -d.
grep -q "JSON.parse(args)" "$JS" \
  || fail "relay-loop.js does not normalize a stringified args (JSON.parse(args) guard missing) — -d would silently no-op"
pass "relay-loop.js normalizes stringified args before reading flags"

# relay-loop.js: actionable queue is partitioned when fableDown is set
grep -q "fableDownDeferred" "$JS" || fail "relay-loop.js missing fableDownDeferred partition variable"
pass "relay-loop.js has fableDownDeferred partition variable"

# relay-loop.js: deferred units carry the --fable-down deferral reason in queued state
grep -q "deferred: --fable-down" "$JS" || fail "relay-loop.js does not label deferred units with --fable-down reason"
pass "relay-loop.js labels deferred units with --fable-down reason"

# relay-loop.js: under --fable-down, review repos with open [ROUTINE] work are DEMOTED
# to execute (keep the pool busy when review can't run), not deferred wholesale.
grep -q "hasRoutine" "$JS" || fail "discovery does not report hasRoutine — --fable-down cannot detect demotable review repos"
grep -qE "verdict === 'review' && u\.hasRoutine" "$JS" \
  || fail "relay-loop.js does not demote review-with-routine repos to execute under --fable-down"
grep -qi "demoted .*to execute\|demoted to execute" "$JS" \
  || fail "relay-loop.js does not log/label the --fable-down review→execute demotion"
pass "relay-loop.js demotes review-with-routine repos to execute under --fable-down"

# relay-loop.js: handoff units are NOT demoted (no proper ROADMAP → no executor work)
grep -q "Handoff repos are NOT demoted" "$JS" \
  || fail "relay-loop.js does not document that handoff units are excluded from --fable-down demotion"
pass "relay-loop.js excludes handoff units from demotion"

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
grep -qE '^\s*/relay -d' "$SKILL" || fail "SKILL.md invocation block missing /relay -d line"
pass "SKILL.md documents --fable-down and -d in invocation block"

# SKILL.md: flag is in the configuration knobs table
grep -q "fable-down.*-d\|-d.*fable-down" "$SKILL" || fail "SKILL.md knobs table missing --fable-down / -d row"
pass "SKILL.md knobs table documents --fable-down / -d"

# SKILL.md: 2026-06-15 pivot — the Opus self-guard is REPLACED by a Fable-availability
# probe (Opus is the apex tier; no warning, no sleep when running on Opus).
grep -qi "probe" "$SKILL" || fail "SKILL.md does not document the Fable-availability probe (replaces the old self-guard)"
pass "SKILL.md documents the Fable-availability probe"

# SKILL.md: Opus is the apex tier (Fable is the bonus); no self-guard warning
grep -qi "apex" "$SKILL" || fail "SKILL.md does not document Opus as the apex tier"
pass "SKILL.md documents Opus as the apex tier"

# SKILL.md: args.fableDown threaded into Workflow launch
grep -q "args.fableDown" "$SKILL" || fail "SKILL.md does not document threading args.fableDown to the Workflow"
pass "SKILL.md documents args.fableDown Workflow pass-through"
