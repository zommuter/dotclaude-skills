#!/usr/bin/env bash
# roadmap:4d44 — git-lock-push.sh --remote (per-remote push selection).
#
# Spec:
#   (1) `--remote NAME` pushes ONLY that remote; the other remotes do NOT move.
#   (2) `--remote a --remote b` is repeatable and pushes exactly that subset.
#   (3) NO flag → pushes ALL remotes, byte-for-byte the pre-existing behaviour (every
#       existing caller must be unaffected).
#   (4) A `--remote` naming a non-existent remote FAILS LOUD (nonzero) and pushes NOTHING —
#       never a silent no-op push. A TRAILING `--remote` with no value likewise fails loud
#       rather than degrading to "push all", which would publish the excluded remotes.
#   (5) The flock is STILL taken (it is the whole reason this helper exists, id:aa93):
#       the run creates/uses the per-repo .git-lock-push.lock.
#
# Hermetic: mktemp repo with two LOCAL BARE remotes, GIT_CONFIG_COUNT to neutralise a
# global core.hooksPath, no network, no real repos, no ~/.claude.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOCKPUSH="${GIT_LOCK_PUSH_OVERRIDE:-$SRC_DIR/git-diary-workflow/git-lock-push.sh}"

pass=0 fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); return 0; }
bad() { echo "BAD: $*"; fail=$((fail+1)); return 0; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# Neutralise any global core.hooksPath (the fleet installs pre-push/pre-commit hooks
# globally; a hermetic fixture repo must not run them) and force a deterministic identity.
export GIT_CONFIG_COUNT=4
export GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0="$TMP/nohooks"
export GIT_CONFIG_KEY_1=user.email     GIT_CONFIG_VALUE_1=t@example.com
export GIT_CONFIG_KEY_2=user.name      GIT_CONFIG_VALUE_2=tester
export GIT_CONFIG_KEY_3=init.defaultBranch GIT_CONFIG_VALUE_3=main
mkdir -p "$TMP/nohooks"

mk_repo() { # $1 dir — a repo with remotes `alpha` and `beta`, both local bares
  local d="$1"
  git init -q --bare "$d/alpha.git"
  git init -q --bare "$d/beta.git"
  git init -q "$d/repo"
  printf 'v1\n' > "$d/repo/f.txt"
  git -C "$d/repo" add f.txt
  git -C "$d/repo" commit -q -m base
  git -C "$d/repo" remote add alpha "$d/alpha.git"
  git -C "$d/repo" remote add beta  "$d/beta.git"
}

tip() { git -C "$1" rev-parse --verify -q refs/heads/main 2>/dev/null || echo "-"; }

# ── (1) --remote alpha pushes ONLY alpha ────────────────────────────────────────────────
A="$TMP/one"; mkdir -p "$A"; mk_repo "$A"
out="$("$LOCKPUSH" "$A/repo" --remote alpha 2>&1)" || bad "(1) --remote alpha exited nonzero: $out"
head_sha="$(git -C "$A/repo" rev-parse HEAD)"
[[ "$(tip "$A/alpha.git")" == "$head_sha" ]] \
  && ok "4d44 (1) --remote alpha PUSHED alpha" \
  || bad "4d44 (1) alpha did not receive the push (alpha=$(tip "$A/alpha.git") head=$head_sha)"
[[ "$(tip "$A/beta.git")" == "-" ]] \
  && ok "4d44 (1) beta was NOT pushed (selection is exclusive)" \
  || bad "4d44 (1) beta was pushed despite --remote alpha — the narrowing does not narrow"

# ── (5) the flock is still taken ────────────────────────────────────────────────────────
[[ -e "$A/repo/.git-lock-push.lock" ]] \
  && ok "4d44 (5) the per-repo flock file was used (serialization not bypassed, id:aa93)" \
  || bad "4d44 (5) no .git-lock-push.lock — the flock was bypassed"

# ── (2) repeatable ──────────────────────────────────────────────────────────────────────
B="$TMP/two"; mkdir -p "$B"; mk_repo "$B"
git init -q --bare "$B/gamma.git"
git -C "$B/repo" remote add gamma "$B/gamma.git"
out="$("$LOCKPUSH" "$B/repo" --remote alpha --remote beta 2>&1)" || bad "(2) exited nonzero: $out"
head_sha="$(git -C "$B/repo" rev-parse HEAD)"
if [[ "$(tip "$B/alpha.git")" == "$head_sha" && "$(tip "$B/beta.git")" == "$head_sha" ]]; then
  ok "4d44 (2) --remote is repeatable — both named remotes received the push"
else
  bad "4d44 (2) repeated --remote did not push both (alpha=$(tip "$B/alpha.git") beta=$(tip "$B/beta.git"))"
fi
[[ "$(tip "$B/gamma.git")" == "-" ]] \
  && ok "4d44 (2) the unnamed third remote stayed untouched" \
  || bad "4d44 (2) gamma was pushed though it was not named"

# ── (3) absent flag → ALL remotes (unchanged behaviour) ─────────────────────────────────
C="$TMP/all"; mkdir -p "$C"; mk_repo "$C"
out="$("$LOCKPUSH" "$C/repo" 2>&1)" || bad "(3) exited nonzero: $out"
head_sha="$(git -C "$C/repo" rev-parse HEAD)"
if [[ "$(tip "$C/alpha.git")" == "$head_sha" && "$(tip "$C/beta.git")" == "$head_sha" ]]; then
  ok "4d44 (3) with NO --remote every remote is still pushed (existing callers unaffected)"
else
  bad "4d44 (3) absent --remote changed behaviour (alpha=$(tip "$C/alpha.git") beta=$(tip "$C/beta.git"))"
fi

# ── (4) loud failures ───────────────────────────────────────────────────────────────────
D="$TMP/bad"; mkdir -p "$D"; mk_repo "$D"
rc=0
out="$("$LOCKPUSH" "$D/repo" --remote nosuch 2>&1)" || rc=$?
if [[ "$rc" -ne 0 ]] && grep -q "nosuch" <<<"$out"; then
  ok "4d44 (4) an unknown --remote fails LOUD (rc=$rc) naming the remote"
else
  bad "4d44 (4) an unknown --remote did not fail loud (rc=$rc): $out"
fi
if [[ "$(tip "$D/alpha.git")" == "-" && "$(tip "$D/beta.git")" == "-" ]]; then
  ok "4d44 (4) an unknown --remote pushed NOTHING"
else
  bad "4d44 (4) an unknown --remote still pushed something — the guard is not fail-closed"
fi
rc=0
out="$("$LOCKPUSH" "$D/repo" --remote 2>&1)" || rc=$?
if [[ "$rc" -ne 0 ]]; then
  ok "4d44 (4) a TRAILING --remote with no value fails loud instead of degrading to push-all"
else
  bad "4d44 (4) a trailing --remote silently degraded (rc=0) — it would publish the excluded remotes: $out"
fi
if [[ "$(tip "$D/alpha.git")" == "-" && "$(tip "$D/beta.git")" == "-" ]]; then
  ok "4d44 (4) the trailing --remote run pushed NOTHING"
else
  bad "4d44 (4) the trailing --remote run pushed remotes — exactly the degradation being guarded"
fi

echo "---- $pass ok, $fail bad ----"
if [[ "$fail" -gt 0 ]]; then
  echo "FAIL: git-lock-push.sh --remote selection (roadmap:4d44)"
  exit 1
fi
echo "ALL PASS: git-lock-push.sh --remote selection (roadmap:4d44)"
