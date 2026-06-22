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

# (7) roadmap trimmed to OPEN items for discovery (id:93cc) — a large ROADMAP's done [x]
# blocks overflow/bloat the shard; the shard only needs open items + structure. Done blocks
# dropped (with a non-silent omission note), open blocks + preamble kept.
j="$(gather idle)"   # idle fixture = all [x] done
rm="$(field roadmap <<<"$j")"
grep -q 'shipped' <<<"$rm" && bad "idle roadmap still carries done-item text (not trimmed, id:93cc)" || ok "idle roadmap drops done [x] item blocks (id:93cc)"
grep -q 'ROADMAP' <<<"$rm" && ok "idle roadmap keeps the preamble/marker after trim" || bad "idle roadmap lost its preamble"
grep -q 'omitted' <<<"$rm" && ok "trimmed roadmap notes the omission (no silent truncation)" || bad "trimmed roadmap missing omission note"
j="$(gather hard-gated)"   # hard-gated fixture = all [ ] open
rm="$(field roadmap <<<"$j")"
{ grep -q 'build the index' <<<"$rm" && grep -q 'choose the storage backend' <<<"$rm"; } \
  && ok "hard-gated roadmap keeps all OPEN items + their text" || bad "hard-gated roadmap dropped an open item"
grep -q '## Gated' <<<"$rm" && ok "trimmed roadmap keeps section headers (gated-section detection)" || bad "trimmed roadmap lost a ## header"

# (8) FAIL-OPEN on a trimmer crash (id:401c Run 40) — if the roadmap trimmer ever errors, the
# roadmap field must fall back to the FULL ROADMAP, NEVER silently empty. An empty roadmap would
# misclassify the repo as "handoff" (relay-loop.js ~L630 "roadmap missing") and re-do C1/C2.
# Force the crash by shadowing `python3` with a stub that always exits non-zero, scoped to ONLY
# the gather call (so the test's own field() python3 is unaffected).
STUB="$TMP/stubbin"; mkdir -p "$STUB"
# The trimmer is the ONLY python3 invocation that runs with ROADMAP_PATH in its env (emit()'s
# JSON builder does not). Fail just that one so emit() still produces valid JSON to read.
REAL_PY3="$(command -v python3)"
{ printf '#!/bin/sh\n'; printf 'if [ -n "$ROADMAP_PATH" ]; then exit 7; fi\n'; printf 'exec %s "$@"\n' "$REAL_PY3"; } > "$STUB/python3"
chmod +x "$STUB/python3"
r8="$TMP/idle/canary-idle"   # reuse the idle fixture (built in test 2): all [x] done items
# gather with the trimmer's python3 forced to fail; emit()'s python3 + the test's field() unaffected.
j8="$(RELAY_TOML="$TMP/no-toml" RELAY_WORKTREE_BASE="$TMP/idle/wt" PATH="$STUB:$PATH" \
        "$GATHER" --repo canary-idle --path "$r8" --runid test 2>/dev/null)"; rc8=$?
rm8="$(jq -r '.roadmap' <<<"$j8" 2>/dev/null || true)"
[[ $rc8 -eq 0 ]] && ok "gather still exits 0 when the trimmer crashes" || bad "gather non-zero on trimmer crash (rc=$rc8)"
grep -q 'shipped' <<<"$rm8" && ok "trimmer crash → FULL ROADMAP fallback (done text present, NOT empty)" \
  || bad "trimmer crash produced empty/trimmed roadmap (fail-open broken, id:401c Run 40)"

# (9) id:bae5 — uv.lock-only exemptions. Build repos inline (no fixture) exercising the
# lock_only_unaudited / dirty_lock_only booleans the discovery exemptions read.
mklockrepo() {  # mklockrepo <dir> → committed repo with a ckpt tag at HEAD, clean
  local r="$1"; mkdir -p "$r"; git -C "$r" init -q
  git -C "$r" config user.email t@t; git -C "$r" config user.name t
  printf 'version="0.14.0"\n' > "$r/uv.lock"; echo code > "$r/app.py"
  git -C "$r" add -A; git -C "$r" commit -qm init
  git -C "$r" tag -a relay-ckpt-20260101-0000 -m base
}
lgather() { RELAY_TOML="$TMP/no-toml" RELAY_WORKTREE_BASE="$TMP/wt-lock" \
  "$GATHER" --repo "canary-lock" --path "$1" --runid test; }

# 9a: unaudited commit touching ONLY uv.lock → lock_only_unaudited=True, dirty_lock_only=False.
r9="$TMP/lockonly"; mklockrepo "$r9"
printf 'version="0.16.0"\n' > "$r9/uv.lock"; git -C "$r9" add uv.lock; git -C "$r9" commit -qm "chore: relock"
j="$(lgather "$r9")"
[[ "$(field lock_only_unaudited <<<"$j")" == "True" ]] && ok "lock-only unaudited commit → lock_only_unaudited=True (review-exempt)" || bad "lock_only_unaudited not True"
[[ "$(field dirty_lock_only <<<"$j")" == "False" ]] && ok "lock-only committed → not dirty" || bad "dirty_lock_only wrong on clean tree"

# 9b: unaudited commit touching uv.lock AND a code file → NOT exempt (conservative guard).
r9b="$TMP/lockplus"; mklockrepo "$r9b"
printf 'version="0.16.0"\n' > "$r9b/uv.lock"; echo more >> "$r9b/app.py"
git -C "$r9b" add -A; git -C "$r9b" commit -qm "feat + relock"
j="$(lgather "$r9b")"
[[ "$(field lock_only_unaudited <<<"$j")" == "False" ]] && ok "uv.lock + code commit → lock_only_unaudited=False (real review)" || bad "lock_only_unaudited leaked True with a code change"

# 9c: dirty tree with ONLY uv.lock modified → dirty_lock_only=True.
r9c="$TMP/dirtylock"; mklockrepo "$r9c"
printf 'version="0.16.0"\n' > "$r9c/uv.lock"   # left uncommitted
j="$(lgather "$r9c")"
[[ "$(field dirty <<<"$j")" == "True" ]] && ok "dirty-lock tree is dirty" || bad "dirty-lock not dirty"
[[ "$(field dirty_lock_only <<<"$j")" == "True" ]] && ok "uv.lock-only dirty → dirty_lock_only=True (dispatchable)" || bad "dirty_lock_only not True"

# 9d: dirty tree with uv.lock AND another file → dirty_lock_only=False (conservative).
r9d="$TMP/dirtyplus"; mklockrepo "$r9d"
printf 'version="0.16.0"\n' > "$r9d/uv.lock"; echo x >> "$r9d/app.py"   # both uncommitted
j="$(lgather "$r9d")"
[[ "$(field dirty_lock_only <<<"$j")" == "False" ]] && ok "uv.lock + other dirty → dirty_lock_only=False (still blocks)" || bad "dirty_lock_only leaked True with a non-lock dirty path"

echo "test_gather_repo_state: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
