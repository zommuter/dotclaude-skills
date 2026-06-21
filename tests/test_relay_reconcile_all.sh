#!/usr/bin/env bash
# roadmap:4e14 — `/relay reconcile --all` must be a real, tested code path in
# relay-reconcile.sh, not a hand-rolled cross-repo sweep.
#
# WHY (observed 2026-06-21): `relay-reconcile.sh` only operated on ONE repo (cwd or
# arg). `/relay reconcile --all` had no script support, so the strong turn improvised
# a sweep with `git for-each-ref ... 2>/dev/null` — which, run in the sandbox where
# `git -C <repo outside cwd>` fails, silently swallowed every error and reported
# "0 parked orphans / clean" while `proj relay` correctly showed parked orphans in
# isochrone, project_manager and zkm-pdf. The fix: a first-class `--all` that
# enumerates relay.toml `classification = "own"` repos (honoring the `# path:`
# override, same as gather-human-backlog.sh) and lists each repo's relay/orphan/*
# branches, and that NEVER silently swallows a git read failure — an unreadable repo
# is surfaced (stderr), never miscounted as "no orphans".
#
# Hermetic: a temp RELAY_TOML + temp git repos via RELAY_TOML/SRC_DIR overrides.

set -euo pipefail

SRC_DIR_REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$SRC_DIR_REPO/relay/scripts/relay-reconcile.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SCRIPT" ]] || fail "relay-reconcile.sh not found/executable at $SCRIPT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Two own repos: A has a parked orphan branch, B is clean. Plus C: an own repo whose
# path does NOT exist (a stale override) — must be surfaced, never swallowed.
mkfakerepo() {
  local d="$1"
  git -C "$d" init -q
  git -C "$d" config user.email t@e.x
  git -C "$d" config user.name t
  git -C "$d" commit -q --allow-empty -m init
}
mkdir -p "$tmp/src/repoA" "$tmp/src/repoB"
mkfakerepo "$tmp/src/repoA"
mkfakerepo "$tmp/src/repoB"
# Park an orphan branch in repoA (a reachable commit on relay/orphan/*).
git -C "$tmp/src/repoA" commit -q --allow-empty -m "parked work"
git -C "$tmp/src/repoA" branch relay/orphan/relay-20260101-000000-1-execute

cat >"$tmp/relay.toml" <<'TOML'
[repos.repoA]
classification = "own"
confirmed = "2026-01-01"

[repos.repoB]
classification = "own"
confirmed = "2026-01-01"

[repos.repoC]
classification = "own"
confirmed = "2026-01-01"

[repos.repoClone]
classification = "clone"
confirmed = "2026-01-01"
TOML

run_all() { RELAY_TOML="$tmp/relay.toml" SRC_DIR="$tmp/src" bash "$SCRIPT" --all 2>"$tmp/err"; }

# (1) --all is a recognized flag (not "unknown flag").
out="$(run_all)" && rc=0 || rc=$?
if grep -qi "unknown flag" "$tmp/err"; then
  fail "--all is rejected as an unknown flag (got: $(cat "$tmp/err"))"
fi
[[ $rc -eq 0 ]] || fail "--all exited $rc (stderr: $(cat "$tmp/err"))"

# (2) it lists repoA's parked orphan branch, naming the repo.
grep -q "relay/orphan/relay-20260101-000000-1-execute" <<<"$out" \
  || fail "--all did not list repoA's parked orphan branch (out: $out)"
grep -q "repoA" <<<"$out" \
  || fail "--all did not name repoA alongside its orphan branch (out: $out)"

# (3) repoB (clean own repo) is swept without spuriously reporting an orphan.
grep -q "relay/orphan/" <<<"$out" && ! grep -q "repoB.*relay/orphan/" <<<"$out" \
  || fail "--all spuriously attributed an orphan branch to the clean repoB (out: $out)"

# (4) repoClone (classification != own) is NOT swept.
! grep -q "repoClone" <<<"$out" \
  || fail "--all swept a non-own repo (repoClone) (out: $out)"

# (5) THE CORE GUARD: repoC's path does not exist → it must be SURFACED (stdout or
# stderr), never silently swallowed into a false "clean". A bare 2>/dev/null sweep
# would hide this; the fix must report it.
if ! { grep -qi "repoC" "$tmp/err" || grep -qi "repoC" <<<"$out"; }; then
  fail "--all silently swallowed unreadable repoC (the exact false-clean bug); err: $(cat "$tmp/err")"
fi

pass "/relay reconcile --all sweeps own repos, lists orphans, and surfaces (never swallows) unreadable repos (4e14)"
