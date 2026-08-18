#!/usr/bin/env bash
# (No roadmap token — this test tracks TODO id:50c4 (F4 local lean-toolchain drift
#  compare, inbox routed:1a98), not a ROADMAP.md item, so it ALWAYS counts.)
#
# Spec for lean_toolchain_drift_check() in relay-doctor.sh:
#   (a) both pins present + EQUAL   → ok line naming the shared version, NO issue
#   (b) both pins present + DIFFER  → LOUD "DRIFT" warn naming both paths+versions,
#                                     AND the finding increments the issue total
#   (c) mathematical-writing pin ABSENT → informational skip line, NO issue
#   (d) relay-core pin ABSENT           → informational skip line, NO issue
# Driven purely through the MW_LEAN_TOOLCHAIN / RELAY_CORE_LEAN_TOOLCHAIN env overrides.
#
# HERMETICITY (CLAUDE.md §Testing: "work in mktemp -d, override HOME/DEST_DIR/roots via
# args or env, never touch ~/.claude or the network").
# Incident 2026-08-18: this file used to (1) leave $HOME pointing at the developer's REAL
# home — so the doctor read $HOME/src, $HOME/.claude/skills, $HOME/.config/relay — and
# (2) assert this check's contribution as a DELTA in the doctor's GLOBAL
# "total issues surfaced: N" line across four sequential FULL runs, on the (false)
# assumption that every OTHER check's contribution was constant across them. It is not:
# other sessions mutate that shared state continuously (e.g. the relay-core-shadow check
# counts rounds in ~/.claude/logs/relay-core-shadow.jsonl, which other sessions append to).
# Observed global counts 473 → 474 → 475 within an hour; under `tests -j 8` sub-case (d)
# failed with "base=473, got 474" and then passed on a re-run.
# Two independent fixes, both applied:
#   1. `--only lean-toolchain-drift` (id:f69b) runs THIS check and nothing else, so the
#      summary integer IS this check's own contribution — asserted as an ABSOLUTE 0/1
#      rather than as a delta that couples this test to every other check's behaviour.
#      A test should assert the thing it means, not a number that happens to move.
#   2. HOME and every root the doctor derives from it ($HOME/src, ~/.claude/logs,
#      ~/.claude/skills, ~/.config/relay, the shadow log) are redirected into the mktemp
#      tree, so no real machine state is read or written at all — the whole class dies,
#      not just the one observed symptom. Verified by passing with HOME=/nonexistent.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCTOR="$ROOT/relay/scripts/relay-doctor.sh"
[[ -x "$DOCTOR" ]] || { echo "relay-doctor.sh not found: $DOCTOR"; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# Hermetic fixture repo so the doctor's scope argument resolves to a real git repo
# (the per-repo bundle is NOT run under --only, but the scope path is still validated).
R="$tmp/repo"; mkdir -p "$R"
git -C "$R" init -q
git -C "$R" config user.email t@e; git -C "$R" config user.name t
printf '# Roadmap\n## Items\n' > "$R/ROADMAP.md"
printf '# TODO\n## Current\n' > "$R/TODO.md"
git -C "$R" add -A; git -C "$R" commit -qm init

# Sandbox HOME + every root the doctor derives from it, so nothing here reads or writes
# the developer's real environment (see HERMETICITY above).
export HOME="$tmp/home"; mkdir -p "$HOME"
export SRC_DIR="$tmp/src"; mkdir -p "$SRC_DIR"
export RELAY_TOML="$tmp/relay.toml"; : > "$RELAY_TOML"   # empty registry → no own repos
export RELAY_DOCTOR_LOG="$tmp/doctor.log"
export RELAY_RECIPE_DIR="$tmp/recipes"
export RELAY_INSTALL_ROOT="$tmp/skills"
export RELAY_CORE_SHADOW_LOG="$tmp/relay-core-shadow.jsonl"

MW="$tmp/mw-lean-toolchain"
RC="$tmp/rc-lean-toolchain"

# Run ONLY the lean-toolchain-drift check over the fixture repo, with the two pin
# overrides; capture stdout.
run_doctor() {
  MW_LEAN_TOOLCHAIN="$1" RELAY_CORE_LEAN_TOOLCHAIN="$2" \
    "$DOCTOR" --only lean-toolchain-drift "$R" 2>>"$tmp/doctor.err" || true
}
# Extract the "total issues surfaced: N" count from the summary line. Under --only this
# is exactly THIS check's own contribution (0 or 1) — no other check ran.
issue_count() { grep -oP '^total issues surfaced: \K[0-9]+' <<<"$1" | head -1; }
# Negative assertions use `if ! grep -q`/`if grep -q` blocks rather than `grep && {…}`:
# under `set -e` a failing `grep -q X && {…}` AND-list would abort the script itself.
has() { grep -q -- "$2" <<<"$1"; }

# --- (a) both present + EQUAL → ok line, no issue -----------------------------------
printf 'leanprover/lean4:v4.30.0-rc2\n' > "$MW"
printf 'leanprover/lean4:v4.30.0-rc2\n' > "$RC"
out_eq="$(run_doctor "$MW" "$RC")"
n_eq="$(issue_count "$out_eq")"
if ! has "$out_eq" "pins agree: leanprover/lean4:v4.30.0-rc2"; then
  echo "FAIL (a): expected an ok 'pins agree' line naming the version"; echo "$out_eq"; exit 1
fi
if has "$out_eq" "DRIFT"; then
  echo "FAIL (a): equal pins must NOT report DRIFT"; echo "$out_eq"; exit 1
fi
[[ "$n_eq" == "0" ]] \
  || { echo "FAIL (a): equal pins must surface 0 issues (got '$n_eq')"; echo "$out_eq"; exit 1; }
echo "PASS (a) equal pins → ok line, 0 issues"

# --- (b) both present + DIFFER → loud DRIFT warn + exactly 1 issue ------------------
printf 'leanprover/lean4:v4.30.0-rc2\n' > "$MW"
printf 'leanprover/lean4:v4.29.0\n'     > "$RC"
out_diff="$(run_doctor "$MW" "$RC")"
n_diff="$(issue_count "$out_diff")"
if ! has "$out_diff" "DRIFT — lean-toolchain pins DIVERGE"; then
  echo "FAIL (b): expected a loud DRIFT warning line"; echo "$out_diff"; exit 1
fi
if ! has "$out_diff" "leanprover/lean4:v4.30.0-rc2" || ! has "$out_diff" "leanprover/lean4:v4.29.0"; then
  echo "FAIL (b): DRIFT report must name BOTH version strings"; echo "$out_diff"; exit 1
fi
if ! has "$out_diff" "$MW" || ! has "$out_diff" "$RC"; then
  echo "FAIL (b): DRIFT report must name both pin paths"; echo "$out_diff"; exit 1
fi
[[ "$n_diff" == "1" ]] \
  || { echo "FAIL (b): divergent pins must surface exactly 1 issue (got '$n_diff')"; echo "$out_diff"; exit 1; }
echo "PASS (b) divergent pins → loud DRIFT naming both versions + exactly 1 issue"

# --- (c) mathematical-writing pin ABSENT → skipped, no issue ------------------------
rm -- "$MW"
printf 'leanprover/lean4:v4.30.0-rc2\n' > "$RC"
out_nomw="$(run_doctor "$MW" "$RC")"
n_nomw="$(issue_count "$out_nomw")"
if ! has "$out_nomw" "canonical pin absent"; then
  echo "FAIL (c): absent canonical pin must print a skip line"; echo "$out_nomw"; exit 1
fi
if has "$out_nomw" "DRIFT"; then
  echo "FAIL (c): absent canonical pin must NOT report DRIFT"; echo "$out_nomw"; exit 1
fi
[[ "$n_nomw" == "0" ]] \
  || { echo "FAIL (c): absent canonical pin must surface 0 issues (got '$n_nomw')"; echo "$out_nomw"; exit 1; }
echo "PASS (c) canonical pin absent → skipped, no issue"

# --- (d) relay-core pin ABSENT → skipped, no issue ----------------------------------
printf 'leanprover/lean4:v4.30.0-rc2\n' > "$MW"
rm -- "$RC"
out_norc="$(run_doctor "$MW" "$RC")"
n_norc="$(issue_count "$out_norc")"
if ! has "$out_norc" "relay-core pin absent"; then
  echo "FAIL (d): absent relay-core pin must print a skip line"; echo "$out_norc"; exit 1
fi
if has "$out_norc" "DRIFT"; then
  echo "FAIL (d): absent relay-core pin must NOT report DRIFT"; echo "$out_norc"; exit 1
fi
[[ "$n_norc" == "0" ]] \
  || { echo "FAIL (d): absent relay-core pin must surface 0 issues (got '$n_norc')"; echo "$out_norc"; exit 1; }
echo "PASS (d) relay-core pin absent → skipped, no issue"

echo "PASS test_lean_toolchain_drift"
