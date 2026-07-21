#!/usr/bin/env bash
# roadmap:7681 — Unknown skill switches must WARN, not silently become subject/args.
# RED spec (handoff C3) for the shared arg-guard: relay/scripts/validate-flags.sh
# + per-skill known-flags manifests, wired into /meeting and /relay setup.
#
# Structural + FUNCTIONAL: the load-bearing behaviour is validate-flags.sh's runtime
# guard, so this drives the script directly (hermetic — no live meeting/pool). Manifest
# CONTENT is verified functionally THROUGH the script (skill name is the pinned
# interface; the manifest path/format is the executor's choice). The coverage check
# (SKILL.md invocation-flags ⊆ manifest) is driven via the script's `--coverage` mode so
# the grep-SCOPING that excludes helper-script `--flag` prose mentions is single-sourced
# inside validate-flags.sh (a genuine judgment call — see REVIEW_ME id:7681).
#
# Design settled: docs/meeting-notes/2026-07-20-2304-fabled-meeting-flow-and-unknown-switch-guard.md (D1/D2)
# Pattern modelled on tests/test_fable_down_flag.sh.

set -uo pipefail   # NOT -e: we assert on non-zero exits deliberately.

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VF="$SRC_DIR/relay/scripts/validate-flags.sh"
MEETING_SKILL="$SRC_DIR/meeting/SKILL.md"
RELAY_SKILL="$SRC_DIR/relay/SKILL.md"

fails=0
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; fails=$((fails+1)); }

# --- 0. artifacts exist --------------------------------------------------------
[[ -f "$VF" ]] || fail "validate-flags.sh not found at $VF"
[[ -x "$VF" ]] || fail "validate-flags.sh is not executable"
[[ -f "$MEETING_SKILL" ]] || fail "meeting/SKILL.md not found"
[[ -f "$RELAY_SKILL" ]] || fail "relay/SKILL.md not found"

# run helper: run_vf <skill> <args...>; captures OUT/ERR/RC into globals.
run_vf() {
  local skill="$1"; shift
  OUT=""; ERR=""; RC=0
  if [[ ! -x "$VF" ]]; then RC=127; return 0; fi
  local errf; errf="$(mktemp)"
  OUT="$("$VF" "$skill" -- "$@" 2>"$errf")"; RC=$?
  ERR="$(cat "$errf")"; rm -f "$errf"
  return 0
}

# --- 1. known flags pass through, no warning, exit 0 ---------------------------
run_vf meeting --cross
if [[ "$RC" -eq 0 && "$ERR" != *[Ww]arn* && "$ERR" != *unknown* ]]; then
  pass "known meeting flag --cross accepted silently (exit 0, no warning)"
else
  fail "known meeting flag --cross must be accepted with no warning (rc=$RC err=$ERR)"
fi

# --fabled must be in the meeting manifest (the 7e87 coupling — else the guard warns on it)
run_vf meeting --fabled
if [[ "$RC" -eq 0 && "$ERR" != *unknown* ]]; then
  pass "meeting manifest knows --fabled (7e87 coupling — not warned)"
else
  fail "meeting manifest must list --fabled so the guard never warns on it (rc=$RC err=$ERR)"
fi

# --- 2. unknown leading-dash flag: LOUD warn to stderr, DROP, proceed (exit 0) -
run_vf meeting --zqxwv
if [[ "$RC" -eq 0 ]]; then
  pass "unknown flag proceeds (warn-and-drop, exit 0 — not abort)"
else
  fail "unknown non-near-miss flag must warn-and-PROCEED (exit 0), got rc=$RC"
fi
if [[ "$ERR" == *"--zqxwv"* ]] && { [[ "$ERR" == *[Ww]arn* ]] || [[ "$ERR" == *nknown* ]]; }; then
  pass "unknown flag --zqxwv produces a LOUD warning naming the flag on stderr"
else
  fail "unknown flag must produce a stderr warning naming it (a required displayed artifact), got: $ERR"
fi
# warning must LIST the known flags (not just say 'unknown') — the displayed-artifact requirement
if [[ "$ERR" == *"--cross"* ]]; then
  pass "unknown-flag warning lists the skill's known flags (e.g. --cross)"
else
  fail "unknown-flag warning must LIST known flags so the user can correct the typo, got: $ERR"
fi
# DROPPED, not folded into subject: cleaned stdout must not carry the unknown flag
if [[ "$OUT" != *"--zqxwv"* ]]; then
  pass "unknown flag is DROPPED from the cleaned args (not folded into subject)"
else
  fail "unknown flag must be dropped from stdout, but it survived: $OUT"
fi

# --- 3. non-dash subject content passes through untouched -----------------------
run_vf meeting redesign the whole thing
if [[ "$RC" -eq 0 && "$OUT" == *"redesign the whole thing"* && "$ERR" != *[Ww]arn* ]]; then
  pass "non-dash subject content passes through untouched, no warning"
else
  fail "plain subject text must pass through untouched with no warning (rc=$RC out=$OUT err=$ERR)"
fi

# --- 4. ARITY-aware: a value-taking flag's dash-starting VALUE is not false-dropped
# /relay --exclude takes a value; `-x` is that value, NOT an unknown flag.
run_vf relay --exclude -x somesubject
if [[ "$RC" -eq 0 && "$ERR" != *"-x"*[Uu]nknown* && "$ERR" != *[Uu]nknown*"-x"* ]]; then
  pass "arity-aware: value of --exclude (dash-starting -x) is not warned as unknown"
else
  fail "arity: --exclude's dash-starting value -x must NOT be treated as an unknown flag (rc=$RC err=$ERR)"
fi
if [[ "$OUT" == *"-x"* ]]; then
  pass "arity-aware: --exclude's value -x is preserved in the cleaned args"
else
  fail "arity: --exclude's value -x must be preserved in stdout, got: $OUT"
fi

# --- 5. near-miss of a mode-changing flag ESCALATES (exit != 0), does not silently drop
# --af is edit-distance 1 from --afk (mode-changing); must escalate, not warn-and-drop.
run_vf relay --af
if [[ "$RC" -ne 0 && "$RC" -ne 127 ]]; then
  pass "near-miss --af (~--afk) escalates via non-zero exit (caller asks/aborts)"
else
  fail "near-miss of a mode-changing flag must ESCALATE with a non-zero exit, got rc=$RC"
fi
if [[ "$ERR" == *"--afk"* ]]; then
  pass "near-miss escalation names the suspected mode-flag (--afk) on stderr"
else
  fail "near-miss escalation must name the suspected mode-flag --afk, got: $ERR"
fi
# a mode-changing flag near-miss in meeting too: --cros ~ --cross
run_vf meeting --cros
if [[ "$RC" -ne 0 && "$RC" -ne 127 ]]; then
  pass "near-miss --cros (~--cross) escalates in the meeting skill"
else
  fail "near-miss --cros (~--cross, mode-changing) must escalate, got rc=$RC"
fi

# --- 6. escalation is SCOPED to mode-flag near-misses: a far unknown does NOT escalate
# (guards against the over-heavy 'escalate every unknown' rejected alternative, D2)
run_vf relay --qqqqzzzz
if [[ "$RC" -eq 0 ]]; then
  pass "a far-from-any-mode-flag unknown warns-and-drops (exit 0), does not over-escalate"
else
  fail "only near-misses of mode-flags escalate; a far unknown must exit 0, got rc=$RC"
fi

# --- 7. coverage: every invocation flag in each SKILL.md is in that skill's manifest
# Driven through the script's --coverage mode so the grep-scoping (excluding
# helper-script/prose --flag mentions) is single-sourced inside validate-flags.sh.
if [[ -x "$VF" ]]; then
  if "$VF" meeting --coverage "$MEETING_SKILL" >/dev/null 2>&1; then
    pass "coverage: meeting/SKILL.md invocation flags ⊆ meeting manifest"
  else
    fail "coverage check failed: meeting/SKILL.md documents an invocation flag missing from the manifest (or --coverage mode absent)"
  fi
  if "$VF" relay --coverage "$RELAY_SKILL" >/dev/null 2>&1; then
    pass "coverage: relay/SKILL.md invocation flags ⊆ relay manifest"
  else
    fail "coverage check failed: relay/SKILL.md documents an invocation flag missing from the manifest (or --coverage mode absent)"
  fi
else
  fail "cannot run coverage check — validate-flags.sh missing"
fi

# --- 8. wiring: both skills reference validate-flags.sh at setup ----------------
grep -q "validate-flags.sh" "$MEETING_SKILL" \
  && pass "meeting/SKILL.md wires validate-flags.sh into setup" \
  || fail "meeting/SKILL.md must call validate-flags.sh at setup (the guard is prose-that-no-ops otherwise)"
grep -q "validate-flags.sh" "$RELAY_SKILL" \
  && pass "relay/SKILL.md wires validate-flags.sh into setup" \
  || fail "relay/SKILL.md must call validate-flags.sh at setup"

# --- summary -------------------------------------------------------------------
if [[ "$fails" -eq 0 ]]; then
  echo "ALL PASS (test_unknown_switch_guard.sh)"
  exit 0
else
  echo "FAILED: $fails assertion(s) — expected RED until id:7681 ships"
  exit 1
fi
