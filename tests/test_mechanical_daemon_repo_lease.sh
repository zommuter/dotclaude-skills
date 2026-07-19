#!/usr/bin/env bash
# Defect-fix test for id:0534 (TODO-tracked, NOT ROADMAP — so NO `# roadmap:XXXX` header:
# per tests/Testing conventions a headerless defect-fix test's failures ALWAYS count).
#
# WHY (meeting mtg-1726 D5, Fable-found): mechanical-daemon.sh runs `bash -c "$cmd_str"`
# where a recipe does `cd <repo> && … > results/latest.json`, writing an acceptance artifact
# INTO the target repo's main checkout. The daemon held NO repo lease — only resource/host/
# intensity gates — so a systemd timer firing mid-`--drain` would dirty the tree the driver
# is merging (fails safe: drain parks on dirty main, but STALLS the drain). The fix adds a
# repo-lease PEEK-AND-DEFER gate: a recipe whose target repo carries a LIVE claim (hard lease
# = repo name as claim key) is left in pending/, mirroring the host/intensity defer stack.
#
# REAL hermetic test — mktemp RELAY_RECIPE_DIR / CLAIM_BASE / INJECT_BASE /
# RELAY_INTENSITY_FILE; no ~/.config / network touched.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DAEMON="$ROOT/relay/scripts/mechanical-daemon.sh"
INTENSITY="$ROOT/relay/scripts/relay-intensity.sh"
CLAIM="$ROOT/relay/scripts/claim.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$DAEMON" ]]    || fail "mechanical-daemon.sh not found/executable at $DAEMON"
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
# cpu is a "light" resource; a huge load ceiling keeps resource-probe cpu available so the
# ONLY thing that can defer this recipe is the repo-lease gate under test (not resource).
export RESOURCE_PROBE_LOAD_MAX=100000

PENDING="$RELAY_RECIPE_DIR/pending"
RUNNING="$RELAY_RECIPE_DIR/running"
DONE="$RELAY_RECIPE_DIR/done"

reset_dirs() {
  rm -rf "$RELAY_RECIPE_DIR" "$INJECT_BASE"
  mkdir -p "$PENDING" "$RUNNING" "$DONE" "$INJECT_BASE"
}

# write_recipe <name> <repo> <est_wall> <artifact_path>: a valid recipe into pending/ whose
# cmd writes the artifact. resource=cpu, host = this host so the host-gate always passes.
write_recipe() {
  local name="$1" repo="$2" est_wall="$3" artifact="$4"
  jq -n \
     --arg id "$name" \
     --arg repo "$repo" \
     --arg cmd "echo done > '$artifact'" \
     --arg host "$(uname -n)" \
     --argjson est_wall "$est_wall" \
     --arg resource "cpu" \
     --arg acceptance_artifact "$artifact" \
     '{id:$id, repo:$repo, cmd:$cmd, host:$host, est_wall:$est_wall, resource:$resource, acceptance_artifact:$acceptance_artifact}' \
     > "$PENDING/$name.json"
}

count() { find "$1" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' '; }
inject_count() { find "$INJECT_BASE/inject.d" "$INJECT_BASE/inject.done" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' '; }

# --- (A) target repo carries a LIVE hard lease → peek-and-defer: NOT run ------------------
# The hard repo lease records the repo NAME as the claim key (claim.sh SCOPE INVARIANT).
reset_dirs
"$INTENSITY" --for 2h --heavy >/dev/null      # permissive window: intensity never defers
"$CLAIM" acquire target-repo --run other-RUN --mode hard >/dev/null
artA="$TMP/outA.txt"
write_recipe run-repo-leased target-repo 60 "$artA"
"$DAEMON" run >/dev/null 2>&1 || true          # a deferral is not an error
"$CLAIM" release target-repo --run other-RUN

[[ ! -f "$artA" ]] || fail "(A) a recipe whose target repo is LEASED must be DEFERRED, not run (artifact was written INTO the leased checkout)"
[[ "$(count "$PENDING")" -ge 1 ]] || fail "(A) a repo-leased recipe must stay in pending/ (peek-and-defer, never preempt)"
[[ "$(count "$DONE")" -eq 0 ]] || fail "(A) a repo-leased recipe must not reach done/"
[[ "$(inject_count)" -eq 0 ]] || fail "(A) a repo-leased recipe must not inject a review-request"
pass "(A) a recipe whose target repo carries a live hard lease is deferred (stays pending, no artifact, no inject)"

# --- (B) NO lease on the target repo → still runs normally (gate must not over-block) ------
# A live claim on a DIFFERENT repo must not defer this one.
reset_dirs
"$INTENSITY" --for 2h --heavy >/dev/null
"$CLAIM" acquire some-other-repo --run other-RUN --mode hard >/dev/null
artB="$TMP/outB.txt"
write_recipe run-repo-free my-repo 60 "$artB"
"$DAEMON" run >/dev/null 2>&1 || fail "(B) daemon tick failed on an unleased-repo recipe"
"$CLAIM" release some-other-repo --run other-RUN

[[ -f "$artB" ]] || fail "(B) an unleased-repo recipe's acceptance_artifact was not written ($artB) — the repo-lease gate over-blocked"
[[ "$(count "$DONE")" -ge 1 ]] || fail "(B) an unleased-repo recipe was not moved to done/ after a successful run"
[[ "$(inject_count)" -ge 1 ]] || fail "(B) an unleased-repo recipe should still inject a review-request"
pass "(B) a recipe whose target repo is unleased runs normally (repo-lease gate does not over-block)"

echo "ALL PASS: mechanical-daemon repo-lease peek-and-defer gate (id:0534)"
