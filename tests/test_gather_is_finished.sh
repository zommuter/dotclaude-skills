#!/usr/bin/env bash
# roadmap:000d — gather-repo-state.sh must emit a deterministic `is_finished` flag so the
# classifier can't false-dispatch handoff/hard/execute work to a provably-finished repo.
#
# WHY (incident 2026-06-23, run relay-20260623-083216): with the quota false-stop fixed
# (id:1d64) the pool ran far longer and reached the lowest-priority `handoff` tier — and
# emitted `handoff`/`hard` verdicts for FINISHED repos (recurheb/echoAI/collaib: ROADMAP
# all `[x]`, 0 open items, clean tree, no unaudited commits). The children correctly
# no-op + auto-reap, but each burns a (strong/opus) dispatch. discover-sig is NOT the
# cause (it hashes full ROADMAP content — checkbox flips DO invalidate); the LLM shard
# over-applies `handoff` (which requires "untracked new work exists") to a finished repo
# that should classify `idle`. Fix = a deterministic demote-only guard.
#
# `is_finished` is TRUE iff: roadmap is present/non-empty AND has ZERO open `- [ ]` items
# AND commits_since_ckpt is empty AND the tree is not dirty (lock-only dirty exempt).
# A repo with NO roadmap stays is_finished=false (that is a genuine first `handoff`).
# relay-loop.js consumes it: an is_finished repo is NEVER dispatched execute/hard/handoff —
# it surfaces as idle (this test pins the data layer; the consumer guard is asserted in
# test_relay_loop_structure.sh / the ROADMAP item).
#
# Hermetic: reuses the shard-canary fixtures under mktemp; never touches ~/.config.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GATHER="$SRC_DIR/relay/scripts/gather-repo-state.sh"
FIX="$SRC_DIR/tests/shard-canary"
pass=0 fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); return 0; }
bad() { echo "BAD: $*"; fail=$((fail+1)); return 0; }
[[ -x "$GATHER" ]] || { echo "FAIL: gather-repo-state.sh missing/not executable"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
field() { python3 -c 'import json,sys; print(json.load(sys.stdin).get(sys.argv[1]))' "$1"; }
gather() {
  local fx="$1"; local r="$TMP/$fx/canary-$fx"
  bash "$FIX/$fx/setup.sh" "$r" >/dev/null 2>&1
  RELAY_TOML="$TMP/no-toml" RELAY_WORKTREE_BASE="$TMP/$fx/wt" \
    "$GATHER" --repo "canary-$fx" --path "$r" --runid test
}

# (1) FINISHED repo (idle fixture: ckpt at HEAD, all items ticked, clean, no commits since)
#     → is_finished MUST be true (this is the recurheb/echoAI false-handoff case).
j="$(gather idle)"
[[ "$(field is_finished <<<"$j")" == "True" ]] \
  && ok "finished repo (idle fixture) → is_finished=true" \
  || bad "idle fixture must be is_finished=true (got '$(field is_finished <<<"$j")')"

# (2) review fixture has an unaudited commit since the ckpt → NOT finished.
j="$(gather review)"
[[ "$(field is_finished <<<"$j")" == "False" ]] \
  && ok "repo with unaudited commits → is_finished=false" \
  || bad "review fixture must be is_finished=false"

# (3) dirty fixture (uncommitted edit) → NOT finished.
j="$(gather dirty)"
[[ "$(field is_finished <<<"$j")" == "False" ]] \
  && ok "dirty repo → is_finished=false" \
  || bad "dirty fixture must be is_finished=false"

# (4) hard-gated fixture carries OPEN gated HARD items → NOT finished (has open work).
j="$(gather hard-gated)"
[[ "$(field is_finished <<<"$j")" == "False" ]] \
  && ok "repo with open items → is_finished=false" \
  || bad "hard-gated fixture (open items) must be is_finished=false"

# (5) non-git path → fail-open, is_finished=false (never claim a non-repo is 'finished').
j="$("$GATHER" --repo nope --path "$TMP/not-a-repo" --runid test)"
[[ "$(field is_finished <<<"$j")" == "False" ]] \
  && ok "non-git path → is_finished=false (fail-open)" \
  || bad "non-git path must be is_finished=false"

echo "---- $pass ok, $fail bad ----"
[[ "$fail" -eq 0 ]] || exit 1
echo "ALL PASS: gather-repo-state is_finished guard (roadmap:000d)"
