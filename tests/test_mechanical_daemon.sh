#!/usr/bin/env bash
# roadmap:b3d0 — A3: the mechanical-run daemon (one processing tick over the recipe drop-dir).
# roadmap:26c2 — cases (4)/(5) below (foreign-host defer / matching-host permit) were
# implemented and landed as id:9cfa (wave-2a review finding) before this ROADMAP item's
# acceptance was formally ticked; the behavior and tests are identical, id:26c2 closes as
# the same host-gate, no further code change needed.
#
# WHY (meeting 2026-07-02-1924 decision 3; TODO id:b3d0): the host `--user` `.path`-unit that
# runs relay-authored recipes OUTSIDE the Workflow (pure mechanical → no permission wall).
# For each recipe in pending/: validate (recipe-validate.sh), check the launch gate
# (relay-intensity.sh permits <est_wall> <resource> AND resource-probe.sh <resource>), and
# iff permitted: move pending→running, run `cmd` (writes acceptance_artifact), move
# running→done, and drop a review-request via inject.sh. CHECK-AND-DEFER, never preempt: a
# recipe whose resource is claimed, or whose est_wall exceeds the permit window, is left in
# pending/ un-run (no artifact, no inject).
#
# REAL hermetic test — mktemp RELAY_RECIPE_DIR / CLAIM_BASE / INJECT_BASE /
# RELAY_INTENSITY_FILE, no ~/.config / network touched. The daemon locates its sibling
# scripts relative to itself and inherits these env overrides. RED until
# relay/scripts/mechanical-daemon.sh lands.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DAEMON="$ROOT/relay/scripts/mechanical-daemon.sh"
INTENSITY="$ROOT/relay/scripts/relay-intensity.sh"
CLAIM="$ROOT/relay/scripts/claim.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$DAEMON" ]]    || fail "mechanical-daemon.sh not found/executable at $DAEMON (RED — A3 not built)"
[[ -x "$INTENSITY" ]] || fail "relay-intensity.sh not found/executable at $INTENSITY"
[[ -x "$CLAIM" ]]     || fail "claim.sh not found/executable at $CLAIM"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export RELAY_RECIPE_DIR="$TMP/recipes"
export RELAY_INTENSITY_FILE="$TMP/permit.json"
export CLAIM_BASE="$TMP/claim"
export CLAIM_LOG=/dev/null
export INJECT_BASE="$TMP/inject"
export INJECT_LOG=/dev/null
# cpu is a "light" resource; a huge load ceiling keeps resource-probe cpu available.
export RESOURCE_PROBE_LOAD_MAX=100000

PENDING="$RELAY_RECIPE_DIR/pending"
RUNNING="$RELAY_RECIPE_DIR/running"
DONE="$RELAY_RECIPE_DIR/done"

reset_dirs() {
  rm -rf "$RELAY_RECIPE_DIR" "$INJECT_BASE"
  mkdir -p "$PENDING" "$RUNNING" "$DONE" "$INJECT_BASE"
}

# write_recipe <name> <est_wall> <artifact_path> [host]: author a valid recipe into pending/
# whose cmd writes the artifact. resource=cpu, host defaults to this host so any host-gate
# passes; pass an explicit 4th arg to author a recipe bound to a DIFFERENT host.
write_recipe() {
  local name="$1" est_wall="$2" artifact="$3" host="${4:-$(uname -n)}"
  jq -n \
     --arg id "$name" \
     --arg repo "demo-repo" \
     --arg cmd "echo done > '$artifact'" \
     --arg host "$host" \
     --argjson est_wall "$est_wall" \
     --arg resource "cpu" \
     --arg acceptance_artifact "$artifact" \
     '{id:$id, repo:$repo, cmd:$cmd, host:$host, est_wall:$est_wall, resource:$resource, acceptance_artifact:$acceptance_artifact}' \
     > "$PENDING/$name.json"
}

# count of files in a dir (0 if absent).
count() { find "$1" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' '; }
inject_count() { find "$INJECT_BASE/inject.d" "$INJECT_BASE/inject.done" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' '; }

# --- (1) PERMITTED recipe → runs: pending→running→done, artifact written, inject dropped ---
reset_dirs
"$INTENSITY" --for 2h --heavy >/dev/null      # writes a permissive window to RELAY_INTENSITY_FILE
art1="$TMP/out1.txt"
write_recipe run-ok 60 "$art1"
"$DAEMON" run >/dev/null 2>&1 || fail "(1) daemon tick failed on a permitted recipe"

[[ -f "$art1" ]] || fail "(1) the acceptance_artifact was not written by the recipe cmd ($art1)"
[[ "$(count "$DONE")" -ge 1 ]] || fail "(1) the recipe was not moved to done/ after a successful run"
[[ "$(count "$PENDING")" -eq 0 ]] || fail "(1) a completed recipe should not remain in pending/"
[[ "$(inject_count)" -ge 1 ]] || fail "(1) no review-request was injected via inject.sh after the run"
pass "(1) a permitted recipe runs pending→running→done, writes its artifact, and injects a review"

# --- (2) resource CLAIMED → check-and-defer: NOT run (stays pending, no artifact/inject) ---
reset_dirs
"$INTENSITY" --for 2h --heavy >/dev/null
"$CLAIM" acquire resource:cpu --run other-RUN --mode intensive >/dev/null
art2="$TMP/out2.txt"
write_recipe run-claimed 60 "$art2"
"$DAEMON" run >/dev/null 2>&1 || true       # a deferral is not an error
"$CLAIM" release resource:cpu --run other-RUN

[[ ! -f "$art2" ]] || fail "(2) a recipe whose resource is CLAIMED must be DEFERRED, not run (artifact was written)"
[[ "$(count "$PENDING")" -ge 1 ]] || fail "(2) a deferred recipe must stay in pending/ (check-and-defer, never preempt)"
[[ "$(count "$DONE")" -eq 0 ]] || fail "(2) a deferred recipe must not reach done/"
[[ "$(inject_count)" -eq 0 ]] || fail "(2) a deferred recipe must not inject a review-request"
pass "(2) a recipe whose resource claim is held is deferred (stays pending, no artifact, no inject)"

# --- (3) est_wall OVER the permit window → deferred likewise ------------------------------
reset_dirs
"$INTENSITY" --for 100s --light >/dev/null    # tiny window: max_wall_seconds=100
art3="$TMP/out3.txt"
write_recipe run-toobig 9000 "$art3"          # est_wall 9000 >> 100 → permits() denies
"$DAEMON" run >/dev/null 2>&1 || true

[[ ! -f "$art3" ]] || fail "(3) a recipe whose est_wall exceeds the permit window must be DEFERRED (artifact was written)"
[[ "$(count "$PENDING")" -ge 1 ]] || fail "(3) an over-window recipe must stay in pending/"
[[ "$(inject_count)" -eq 0 ]] || fail "(3) an over-window recipe must not inject a review-request"
pass "(3) a recipe whose est_wall exceeds the permit window is deferred"

# --- (4) FOREIGN host binding -> check-and-defer: NOT run (id:9cfa) ------------------------
# RELAY_HOSTNAME (host-gate.sh's own hermetic override) stands in for "the current host" so
# this test never depends on the real machine's hostname.
reset_dirs
"$INTENSITY" --for 2h --heavy >/dev/null
art4="$TMP/out4.txt"
write_recipe run-foreign-host 60 "$art4" "host-elsewhere"
RELAY_HOSTNAME="host-here" "$DAEMON" run >/dev/null 2>&1 || true   # a deferral is not an error

[[ ! -f "$art4" ]] || fail "(4) a recipe bound to a DIFFERENT host must be DEFERRED, not run (artifact was written)"
[[ "$(count "$PENDING")" -ge 1 ]] || fail "(4) a foreign-host recipe must stay in pending/ (another host's daemon owns it)"
[[ "$(count "$DONE")" -eq 0 ]] || fail "(4) a foreign-host recipe must not reach done/"
[[ "$(inject_count)" -eq 0 ]] || fail "(4) a foreign-host recipe must not inject a review-request"
pass "(4) a recipe bound to a different host is deferred, not run (host binding enforced)"

# --- (5) MATCHING host binding -> still runs normally (host-gate must not over-block) -------
reset_dirs
"$INTENSITY" --for 2h --heavy >/dev/null
art5="$TMP/out5.txt"
write_recipe run-same-host 60 "$art5" "host-here"
RELAY_HOSTNAME="host-here" "$DAEMON" run >/dev/null 2>&1 || fail "(5) daemon tick failed on a matching-host recipe"

[[ -f "$art5" ]] || fail "(5) a same-host recipe's acceptance_artifact was not written ($art5)"
[[ "$(count "$DONE")" -ge 1 ]] || fail "(5) a same-host recipe was not moved to done/ after a successful run"
[[ "$(inject_count)" -ge 1 ]] || fail "(5) a same-host recipe should still inject a review-request"
pass "(5) a recipe bound to the current host runs normally (host-gate does not over-block)"

echo "ALL PASS: mechanical-run daemon lifecycle + check-and-defer gate (id:b3d0)"
