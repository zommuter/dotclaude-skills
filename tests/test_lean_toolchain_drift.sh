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
# Hermetic: mktemp -d fixtures only; never touches the real ~/src/mathematical-writing,
# ~/src/relay-core, ~/.claude, or the network.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCTOR="$ROOT/relay/scripts/relay-doctor.sh"
[[ -x "$DOCTOR" ]] || { echo "relay-doctor.sh not found: $DOCTOR"; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# Hermetic fixture repo so the doctor's per-repo scope has something valid to run on
# (the drift check is a once-only cross-repo check but the doctor still needs a scope).
R="$tmp/repo"; mkdir -p "$R"
git -C "$R" init -q
git -C "$R" config user.email t@e; git -C "$R" config user.name t
printf '# Roadmap\n## Items\n' > "$R/ROADMAP.md"
printf '# TODO\n## Current\n' > "$R/TODO.md"
git -C "$R" add -A; git -C "$R" commit -qm init

# Isolate every cross-repo side channel to the mktemp root (empty relay.toml → no own
# repos; log to a throwaway file) so nothing here reads the real environment.
export RELAY_TOML="$tmp/relay.toml"; : > "$RELAY_TOML"
export RELAY_DOCTOR_LOG="$tmp/doctor.log"

MW="$tmp/mw-lean-toolchain"
RC="$tmp/rc-lean-toolchain"

# Run the doctor over the fixture repo with the two pin overrides; capture stdout.
run_doctor() {
  MW_LEAN_TOOLCHAIN="$1" RELAY_CORE_LEAN_TOOLCHAIN="$2" \
    "$DOCTOR" "$R" 2>>"$tmp/doctor.err" || true
}
# Extract the "total issues surfaced: N" count from the summary line.
issue_count() { grep -oP '^total issues surfaced: \K[0-9]+' <<<"$1" | head -1; }

# Other once-only doctor checks (registry parse, refs-install, routed dead-letters, …)
# may contribute their own issues to the global summary; the env is identical across all
# four runs, so those contributions are constant. We therefore assert this check's
# contribution as a DELTA against the equal-case baseline rather than an absolute count.

# --- (a) both present + EQUAL → ok line, no issue delta ------------------------------
printf 'leanprover/lean4:v4.30.0-rc2\n' > "$MW"
printf 'leanprover/lean4:v4.30.0-rc2\n' > "$RC"
out_eq="$(run_doctor "$MW" "$RC")"
base="$(issue_count "$out_eq")"
grep -q "pins agree: leanprover/lean4:v4.30.0-rc2" <<<"$out_eq" \
  || { echo "FAIL (a): expected an ok 'pins agree' line naming the version"; echo "$out_eq"; exit 1; }
[[ -n "$base" ]] || { echo "FAIL (a): could not read summary issue count"; echo "$out_eq"; exit 1; }
echo "PASS (a) equal pins → ok line (baseline issues=$base)"

# --- (b) both present + DIFFER → loud DRIFT warn + exactly +1 issue ------------------
printf 'leanprover/lean4:v4.30.0-rc2\n' > "$MW"
printf 'leanprover/lean4:v4.29.0\n'     > "$RC"
out_diff="$(run_doctor "$MW" "$RC")"
n_diff="$(issue_count "$out_diff")"
grep -q "DRIFT — lean-toolchain pins DIVERGE" <<<"$out_diff" \
  || { echo "FAIL (b): expected a loud DRIFT warning line"; echo "$out_diff"; exit 1; }
grep -q "leanprover/lean4:v4.30.0-rc2" <<<"$out_diff" \
  && grep -q "leanprover/lean4:v4.29.0" <<<"$out_diff" \
  || { echo "FAIL (b): DRIFT report must name both version strings"; echo "$out_diff"; exit 1; }
grep -q "$MW" <<<"$out_diff" && grep -q "$RC" <<<"$out_diff" \
  || { echo "FAIL (b): DRIFT report must name both pin paths"; exit 1; }
[[ "$n_diff" == "$((base + 1))" ]] \
  || { echo "FAIL (b): divergent pins must add exactly 1 issue (base=$base, got $n_diff)"; exit 1; }
echo "PASS (b) divergent pins → loud DRIFT + exactly 1 issue"

# --- (c) mathematical-writing pin ABSENT → skipped, no issue delta ------------------
rm -f "$MW"
printf 'leanprover/lean4:v4.30.0-rc2\n' > "$RC"
out_nomw="$(run_doctor "$MW" "$RC")"
n_nomw="$(issue_count "$out_nomw")"
grep -q "canonical pin absent" <<<"$out_nomw" \
  || { echo "FAIL (c): absent canonical pin must print a skip line"; echo "$out_nomw"; exit 1; }
[[ "$n_nomw" == "$base" ]] || { echo "FAIL (c): absent canonical pin must add NO issue (base=$base, got $n_nomw)"; exit 1; }
echo "PASS (c) canonical pin absent → skipped, no issue"

# --- (d) relay-core pin ABSENT → skipped, no issue delta ---------------------------
printf 'leanprover/lean4:v4.30.0-rc2\n' > "$MW"
rm -f "$RC"
out_norc="$(run_doctor "$MW" "$RC")"
n_norc="$(issue_count "$out_norc")"
grep -q "relay-core pin absent" <<<"$out_norc" \
  || { echo "FAIL (d): absent relay-core pin must print a skip line"; echo "$out_norc"; exit 1; }
[[ "$n_norc" == "$base" ]] || { echo "FAIL (d): absent relay-core pin must add NO issue (base=$base, got $n_norc)"; exit 1; }
echo "PASS (d) relay-core pin absent → skipped, no issue"

echo "PASS test_lean_toolchain_drift"
