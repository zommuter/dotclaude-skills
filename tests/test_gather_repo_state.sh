#!/usr/bin/env bash
# roadmap:11ad — gather-repo-state.sh emits the per-repo state a discover-shard needs in ONE
# call (collapsing ~17 inline git/grep commands → 1, to cut shard turn count, the measured
# cost driver). This tests the data layer is correct + complete + fail-open. Hermetic: builds
# git repos under mktemp (reusing the shard-canary fixture setups), never touches ~/.config.
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

gather() {  # gather <fixture> → JSON on stdout; sandboxed toml/worktree dirs
  local fx="$1"
  local r="$TMP/$fx/canary-$fx"
  bash "$FIX/$fx/setup.sh" "$r" >/dev/null 2>&1
  RELAY_TOML="$TMP/no-toml" RELAY_WORKTREE_BASE="$TMP/$fx/wt" \
    "$GATHER" --repo "canary-$fx" --path "$r" --runid test
}

# (1) review: a checkpoint tag + an unaudited commit after it → commits_since_ckpt non-empty.
j="$(gather review)"
[[ "$(field is_git <<<"$j")" == "True" ]] && ok "review is_git" || bad "review is_git"
[[ -n "$(field latest_ckpt <<<"$j")" ]] && ok "review has latest_ckpt" || bad "review latest_ckpt empty"
[[ -n "$(field commits_since_ckpt <<<"$j")" ]] && ok "review has commits_since_ckpt (drives 'review')" || bad "review commits_since_ckpt empty"

# (2) idle: ckpt at HEAD, all ticked → no commits since, roadmap present, not dirty.
j="$(gather idle)"
[[ -z "$(field commits_since_ckpt <<<"$j")" ]] && ok "idle has no commits since ckpt" || bad "idle commits_since not empty"
[[ "$(field dirty <<<"$j")" == "False" ]] && ok "idle not dirty" || bad "idle dirty wrong"
grep -q 'ROADMAP' <<<"$(field roadmap <<<"$j")" && ok "idle roadmap emitted" || bad "idle roadmap missing"

# (3) dirty: uncommitted edit → dirty=true, porcelain non-empty.
j="$(gather dirty)"
[[ "$(field dirty <<<"$j")" == "True" ]] && ok "dirty=true detected" || bad "dirty not detected"
[[ -n "$(field porcelain <<<"$j")" ]] && ok "dirty porcelain non-empty" || bad "dirty porcelain empty"

# (4) hard-gated: roadmap carries the gated HARD items verbatim (shard applies the judgment).
j="$(gather hard-gated)"
grep -q 'decision gate' <<<"$(field roadmap <<<"$j")" && ok "hard-gated roadmap carries the gated items" || bad "hard-gated roadmap missing gated text"

# (5) FAIL-OPEN: a non-git path → is_git=false, exit 0 (shard surfaces it, round never crashes).
j="$("$GATHER" --repo nope --path "$TMP/not-a-repo" --runid test)"; rc=$?
{ [[ $rc -eq 0 ]] && [[ "$(field is_git <<<"$j")" == "False" ]]; } \
  && ok "non-git path → is_git=false, exit 0 (fail-open)" || bad "fail-open broken (rc=$rc)"

# (6) no-upstream repo (the fixtures have no remote) → has_upstream=false, no crash.
j="$(gather review)"
[[ "$(field has_upstream <<<"$j")" == "False" ]] && ok "no-remote repo → has_upstream=false" || bad "has_upstream wrong"

echo "test_gather_repo_state: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
