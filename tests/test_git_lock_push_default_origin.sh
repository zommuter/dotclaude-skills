#!/usr/bin/env bash
# roadmap:4d44 (default-flip amendment, 2026-08-26) — git-lock-push.sh's ABSENT-flag
# default changed from "push ALL remotes" to "push origin ONLY" (owner directive: the old
# default was a publish-by-default footgun — 4 own repos carry a public GitHub remote
# alongside private/LAN ones, and any caller that forgot `--remote origin` silently
# published to it).
#
# Spec:
#   (a) NO --remote / --all flag → pushes ONLY origin; other remotes do NOT move.
#   (b) `--all` → pushes every remote (unaffected by the default change — see the
#       sibling test_git_lock_push_remote_select_4d44.sh for full --remote/--all coverage).
#   (c) `--remote NAME` subset still works (covered fully in the 4d44 test; smoke-tested
#       here too since it interacts directly with the new default path).
#   (d) Missing `origin` with NO flag fails LOUD (nonzero, naming 'origin') rather than
#       silently falling back to "push all" — that fallback would reinstate the exact
#       footgun this change closes.
#
# Hermetic: mktemp repo with local bare remotes only, GIT_CONFIG_COUNT to neutralise a
# global core.hooksPath, no network, no real repos, no ~/.claude.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOCKPUSH="${GIT_LOCK_PUSH_OVERRIDE:-$SRC_DIR/git-diary-workflow/git-lock-push.sh}"

pass=0 fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); return 0; }
bad() { echo "BAD: $*"; fail=$((fail+1)); return 0; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

export GIT_CONFIG_COUNT=4
export GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0="$TMP/nohooks"
export GIT_CONFIG_KEY_1=user.email     GIT_CONFIG_VALUE_1=t@example.com
export GIT_CONFIG_KEY_2=user.name      GIT_CONFIG_VALUE_2=tester
export GIT_CONFIG_KEY_3=init.defaultBranch GIT_CONFIG_VALUE_3=main
mkdir -p "$TMP/nohooks"

# A repo with remotes `origin` and `upstream-public`, both local bares — named to mimic
# the real fleet shape (a private default + an extra remote that must NOT get swept in).
mk_repo_with_origin() { # $1 dir
  local d="$1"
  git init -q --bare "$d/origin.git"
  git init -q --bare "$d/upstream-public.git"
  git init -q "$d/repo"
  printf 'v1\n' > "$d/repo/f.txt"
  git -C "$d/repo" add f.txt
  git -C "$d/repo" commit -q -m base
  git -C "$d/repo" remote add origin "$d/origin.git"
  git -C "$d/repo" remote add upstream-public "$d/upstream-public.git"
}

# A repo with NO origin remote at all (only oddly-named remotes) — the negative control
# for (d).
mk_repo_without_origin() { # $1 dir
  local d="$1"
  git init -q --bare "$d/alpha.git"
  git init -q "$d/repo"
  printf 'v1\n' > "$d/repo/f.txt"
  git -C "$d/repo" add f.txt
  git -C "$d/repo" commit -q -m base
  git -C "$d/repo" remote add alpha "$d/alpha.git"
}

tip() { git -C "$1" rev-parse --verify -q refs/heads/main 2>/dev/null || echo "-"; }

# ── (a) NO flag → origin ONLY ───────────────────────────────────────────────────────────
A="$TMP/one"; mkdir -p "$A"; mk_repo_with_origin "$A"
out="$("$LOCKPUSH" "$A/repo" 2>&1)" || bad "(a) no-flag push exited nonzero: $out"
head_sha="$(git -C "$A/repo" rev-parse HEAD)"
[[ "$(tip "$A/origin.git")" == "$head_sha" ]] \
  && ok "(a) no flag pushed origin" \
  || bad "(a) origin did NOT receive the push (origin=$(tip "$A/origin.git") head=$head_sha)"
[[ "$(tip "$A/upstream-public.git")" == "-" ]] \
  && ok "(a) no flag left upstream-public UNTOUCHED (safe default)" \
  || bad "(a) upstream-public was pushed with no flag at all — the footgun is back"

# ── (b) --all → every remote ────────────────────────────────────────────────────────────
B="$TMP/two"; mkdir -p "$B"; mk_repo_with_origin "$B"
out="$("$LOCKPUSH" "$B/repo" --all 2>&1)" || bad "(b) --all exited nonzero: $out"
head_sha="$(git -C "$B/repo" rev-parse HEAD)"
if [[ "$(tip "$B/origin.git")" == "$head_sha" && "$(tip "$B/upstream-public.git")" == "$head_sha" ]]; then
  ok "(b) --all pushed BOTH remotes"
else
  bad "(b) --all did not push both (origin=$(tip "$B/origin.git") upstream-public=$(tip "$B/upstream-public.git"))"
fi

# ── (c) --remote NAME subset still works ────────────────────────────────────────────────
C="$TMP/three"; mkdir -p "$C"; mk_repo_with_origin "$C"
out="$("$LOCKPUSH" "$C/repo" --remote upstream-public 2>&1)" || bad "(c) --remote upstream-public exited nonzero: $out"
head_sha="$(git -C "$C/repo" rev-parse HEAD)"
[[ "$(tip "$C/upstream-public.git")" == "$head_sha" ]] \
  && ok "(c) --remote upstream-public pushed that remote" \
  || bad "(c) --remote upstream-public did not push it"
[[ "$(tip "$C/origin.git")" == "-" ]] \
  && ok "(c) --remote upstream-public left origin untouched (explicit subset honored)" \
  || bad "(c) origin was pushed despite --remote upstream-public naming a different remote"

# ── (d) missing origin, NO flag → LOUD failure, never a silent fall-back to --all ──────
D="$TMP/four"; mkdir -p "$D"; mk_repo_without_origin "$D"
rc=0
out="$("$LOCKPUSH" "$D/repo" 2>&1)" || rc=$?
if [[ "$rc" -ne 0 ]] && grep -q "origin" <<<"$out"; then
  ok "(d) missing default 'origin' fails LOUD (rc=$rc), naming it: $out"
else
  bad "(d) missing 'origin' with no flag did NOT fail loud (rc=$rc): $out"
fi
if [[ "$(tip "$D/alpha.git")" == "-" ]]; then
  ok "(d) the missing-origin run pushed NOTHING (no silent fall-back to --all)"
else
  bad "(d) the missing-origin run still pushed alpha — silently fell back to push-all, the exact footgun being closed"
fi

echo "---- $pass ok, $fail bad ----"
if [[ "$fail" -gt 0 ]]; then
  echo "FAIL: git-lock-push.sh default-to-origin (2026-08-26)"
  exit 1
fi
echo "ALL PASS: git-lock-push.sh default-to-origin (2026-08-26)"
