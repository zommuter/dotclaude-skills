#!/usr/bin/env bash
# roadmap:c3f7 — relay sync-origin safety check.
# Functionally covers sync-origin.sh against a LOCAL bare repo standing in for origin
# (no network): in-sync→ok, behind→behind/ff catch-up, diverged→diverged (no ff),
# and a fresh upstream-less repo→no-upstream. Also asserts Makefile registration so the
# helper can't ship un-symlinked (the id:5f09 lesson).

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SH="$SRC_DIR/relay/scripts/sync-origin.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

# run_sync: run sync-origin.sh, capturing stdout into $out and exit code into $rc
# without tripping `set -e` on a non-zero (behind/diverged) exit.
out=""; rc=0
run_sync() {
  set +e
  out="$("$SH" "$@" 2>/dev/null)"
  rc=$?
  set -e
}

[[ -x "$SH" ]] || fail "sync-origin.sh not found/executable at $SH"

export SYNC_LOG=/dev/null

# ── Hermetic sandbox ──
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Deterministic git identity for the sandbox.
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# Bare "origin" + a clone that tracks it.
git init -q --bare "$TMP/origin.git"
git clone -q "$TMP/origin.git" "$TMP/work"
echo one >"$TMP/work/file"
git -C "$TMP/work" add file
git -C "$TMP/work" commit -qm one
git -C "$TMP/work" push -q -u origin HEAD:main
# Ensure local branch tracks origin/main (push -u set upstream to origin/main).
git -C "$TMP/work" branch --set-upstream-to=origin/main >/dev/null 2>&1 || true

# A second clone used to advance origin behind work's back.
git clone -q "$TMP/origin.git" "$TMP/other"
git -C "$TMP/other" checkout -q -B main origin/main 2>/dev/null || true

# ── IN-SYNC → "ok", exit 0 ──
run_sync "$TMP/work"
[[ "$rc" -eq 0 ]] || fail "in-sync exit code should be 0 (got $rc)"
[[ "$out" == "ok" ]] || fail "in-sync should print 'ok' (got '$out')"
pass "in-sync clone reports ok (exit 0)"

# ── BEHIND → "behind 1" exit 2; then --ff → "ff 1" exit 0 and HEAD==origin/main ──
echo two >>"$TMP/other/file"
git -C "$TMP/other" add file
git -C "$TMP/other" commit -qm two
git -C "$TMP/other" push -q origin HEAD:main

run_sync "$TMP/work"
[[ "$rc" -eq 2 ]] || fail "behind (no --ff) exit code should be 2 (got $rc)"
[[ "$out" == "behind 1" ]] || fail "behind should print 'behind 1' (got '$out')"
pass "behind clone reports 'behind 1' (exit 2) without --ff"

run_sync "$TMP/work" --ff
[[ "$rc" -eq 0 ]] || fail "behind --ff exit code should be 0 (got $rc)"
[[ "$out" == "ff 1" ]] || fail "behind --ff should print 'ff 1' (got '$out')"
work_head="$(git -C "$TMP/work" rev-parse HEAD)"
origin_main="$(git -C "$TMP/work" rev-parse origin/main)"
[[ "$work_head" == "$origin_main" ]] || fail "--ff did not fast-forward work HEAD to origin/main"
pass "behind clone fast-forwards with --ff ('ff 1', exit 0, HEAD==origin/main)"

# ── DIVERGED → "diverged 1 1" exit 3; --ff must NOT fast-forward ──
# work commits locally (unpushed); origin advances independently.
echo local >>"$TMP/work/file"
git -C "$TMP/work" add file
git -C "$TMP/work" commit -qm work-local
echo remote >>"$TMP/other/file"
git -C "$TMP/other" add file
git -C "$TMP/other" commit -qm other-remote
git -C "$TMP/other" push -q origin HEAD:main

before_head="$(git -C "$TMP/work" rev-parse HEAD)"
run_sync "$TMP/work"
[[ "$rc" -eq 3 ]] || fail "diverged exit code should be 3 (got $rc)"
[[ "$out" == "diverged 1 1" ]] || fail "diverged should print 'diverged 1 1' (got '$out')"
pass "diverged clone reports 'diverged 1 1' (exit 3)"

run_sync "$TMP/work" --ff
[[ "$rc" -eq 3 ]] || fail "diverged --ff exit code should still be 3 (got $rc)"
after_head="$(git -C "$TMP/work" rev-parse HEAD)"
[[ "$before_head" == "$after_head" ]] || fail "--ff fast-forwarded a DIVERGED repo (must not)"
pass "--ff does not fast-forward a diverged repo (still exit 3, HEAD unchanged)"

# ── NO-UPSTREAM → "no-upstream", exit 0 ──
git init -q "$TMP/lonely"
echo x >"$TMP/lonely/f"
git -C "$TMP/lonely" add f
git -C "$TMP/lonely" commit -qm init
run_sync "$TMP/lonely"
[[ "$rc" -eq 0 ]] || fail "no-upstream exit code should be 0 (got $rc)"
[[ "$out" == "no-upstream" ]] || fail "no-upstream should print 'no-upstream' (got '$out')"
pass "upstream-less repo reports 'no-upstream' (exit 0)"

# ── Non-git path → exit 2, stderr message ──
run_sync "$TMP/nope"
[[ "$rc" -eq 2 ]] || fail "non-git path exit code should be 2 (got $rc)"
pass "non-git path errors out (exit 2)"

# ── Makefile registration (id:5f09 lesson — no un-symlinked helper) ──
mk_count="$(grep -c "scripts/sync-origin.sh" "$SRC_DIR/Makefile" || true)"
[[ "$mk_count" -ge 3 ]] || fail "Makefile must register sync-origin.sh in relay_FILES/_EXEC/_ALLOW (3x); got $mk_count"
pass "Makefile registers sync-origin.sh in relay_FILES/_EXEC/_ALLOW"

echo "ALL PASS: relay sync-origin safety check (id:c3f7)"
