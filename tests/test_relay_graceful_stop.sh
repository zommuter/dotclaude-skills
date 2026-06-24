#!/usr/bin/env bash
# roadmap:c012 — first-class graceful (patient) operator stop for the autonomous pool.
#
# Before this, a live `relay-loop.js` pool ended ONLY on quota cap / two dry discoveries /
# MAX_ROUNDS, or a hard `TaskStop` (which kills in-flight children + parks worktrees as
# relay/orphan/*). c012 adds a VOLUNTARY wind-down: a STOP sentinel the discover-prelude
# checks each round (drain the current wave + integration debt, drop queued units, do NOT
# re-discover, stopReason="user-stop"), plus launch-time --once / --after N round caps and a
# front-door `/relay stop` (and `/relay stop --now` = the hard TaskStop path).
#
# Static-structural, matching test_relay_loop_structure.sh / test_relay_stop_reason.sh — the
# pool cannot exercise the live Workflow, so we assert the wiring exists in the source.
#
# RED until id:c012's ROADMAP checkbox is ticked → EXPECTED-RED while unticked.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JS="$ROOT/relay/scripts/relay-loop.js"
SKILL="$ROOT/relay/SKILL.md"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$JS" ]] || fail "relay-loop.js not found at $JS"
[[ -f "$SKILL" ]] || fail "relay/SKILL.md not found at $SKILL"
node --check "$JS" || fail "relay-loop.js fails node --check"
pass "relay-loop.js exists and parses"

# (1) Config knobs: STOP_PATH (sentinel) + a launch-time round cap derived from --once/--after.
grep -qE "STOP_PATH\s*=\s*A\.STOP_PATH" "$JS" \
  || fail "no STOP_PATH config knob reading A.STOP_PATH (id:c012 sentinel path)"
pass "STOP_PATH knob reads args.STOP_PATH"

grep -qE "STOP_AFTER_ROUNDS" "$JS" \
  || fail "no STOP_AFTER_ROUNDS launch cap derived from --once/--after (id:c012)"
grep -qE "A\.once" "$JS" || fail "launch cap does not honor args.once (--once)"
grep -qE "A\.stopAfter" "$JS" || fail "launch cap does not honor args.stopAfter (--after N)"
pass "launch-time --once / --after N round cap wired (STOP_AFTER_ROUNDS)"

# (2) PRELUDE_SCHEMA must surface stopRequested (the prelude is the only actor with shell/FS).
awk '/PRELUDE_SCHEMA = \{/{w=1} w&&/stopRequested/{found=1} w&&/^}/{w=0} END{exit found?0:1}' "$JS" \
  || fail "PRELUDE_SCHEMA carries no stopRequested field — outer loop cannot observe the sentinel (id:c012)"
pass "PRELUDE_SCHEMA exposes stopRequested"

# (3) The prelude PROMPT must instruct checking the STOP sentinel (uses STOP_PATH) and the
#     decrement/consume semantics (countdown content + rm on fire). The script itself has no
#     filesystem access, so this MUST live in the agent prompt.
grep -qE '\$\{STOP_PATH\}' "$JS" \
  || fail "prelude prompt does not reference \${STOP_PATH} — sentinel check is not wired into the shell-running agent (id:c012)"
grep -qiE "stopRequested.*id:c012|id:c012.*sentinel" "$JS" \
  || fail "prelude prompt has no id:c012 stop-sentinel step"
pass "prelude prompt checks the STOP sentinel via \${STOP_PATH}"

# (4) runRound short-circuits on a literal stopRequested===true: sets stopReason='user-stop'
#     and returns a userStop marker WITHOUT dispatching a new wave. Must be a strict ===
#     (fail-safe: a dead/absent prelude must NOT trigger a stop).
grep -qE "prelude\.stopRequested === true" "$JS" \
  || fail "runRound does not strictly check prelude.stopRequested === true (fail-safe required, id:c012)"
awk '/prelude\.stopRequested === true/{w=18} w-->0{ if(/user-stop/)sr=1; if(/userStop/)us=1; if(/scheduleStatusWrite/)sw=1 } END{exit (sr&&us&&sw)?0:1}' "$JS" \
  || fail "the stopRequested branch must set stopReason='user-stop', return a userStop marker, AND scheduleStatusWrite before returning so RELAY_STATUS shows user-stop (not stale '(none)') — observed 2026-06-24 (id:c012)"
pass "runRound short-circuits on stopRequested with user-stop + userStop marker + status write"

# (5) Outer loop honors BOTH the userStop marker (sentinel) and the launch-time round cap.
grep -qE "r\.userStop" "$JS" \
  || fail "outer loop does not break on r.userStop (sentinel-driven stop never ends the loop, id:c012)"
awk '/STOP_AFTER_ROUNDS > 0/{w=4} w-->0{ if(/round >= STOP_AFTER_ROUNDS/)c=1; if(/user-stop/)sr=1 } END{exit (c&&sr)?0:1}' "$JS" \
  || fail "outer loop does not enforce the launch-time round cap with stopReason='user-stop' (id:c012)"
pass "outer loop breaks on sentinel (r.userStop) AND the --once/--after round cap"

# (6) stopReason enum / status line must recognize user-stop.
grep -qE "buildStopReasonLine" "$JS" || fail "buildStopReasonLine missing"
awk '/function buildStopReasonLine/{w=8} w-->0{ if(/user-stop/)f=1 } END{exit f?0:1}' "$JS" \
  || fail "buildStopReasonLine does not gloss user-stop (id:c012)"
pass "buildStopReasonLine recognizes user-stop"

# (7) No Workflow-forbidden API introduced (the shell lives in the prompt STRING, not JS).
PATTERN='new Date\(|Date\.now\(|\.toISOString\(|process\.|require\(|Math\.random\(|\bfs\.'
hits=$(grep -nE "$PATTERN" "$JS" | grep -vE ':[[:space:]]*//' || true)
[[ -z "$hits" ]] || fail "forbidden Workflow-sandbox API introduced by id:c012 edits:
$hits"
pass "no forbidden Date/process/require/fs/Math.random in relay-loop.js"

# (8) Front-door SKILL.md documents the new mode + knobs.
grep -qE "^## Stop mode" "$SKILL" || fail "SKILL.md has no '## Stop mode' section (id:c012)"
grep -qE "/relay stop" "$SKILL" || fail "SKILL.md does not document '/relay stop' (id:c012)"
grep -qE "RELAY_STOP_PATH|STOP_PATH" "$SKILL" || fail "SKILL.md knobs table omits the STOP sentinel path (id:c012)"
grep -qE '`--once`' "$SKILL" || fail "SKILL.md does not document --once (id:c012)"
grep -qiE 'stop --now' "$SKILL" || fail "SKILL.md does not document the hard '/relay stop --now' path (id:c012)"
pass "SKILL.md documents Stop mode, /relay stop[/--now], --once, and the STOP_PATH knob"

echo "ALL PASS: id:c012 graceful operator stop wired (sentinel + launch caps + front-door)"
