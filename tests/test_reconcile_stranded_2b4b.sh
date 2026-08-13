#!/usr/bin/env bash
# roadmap:2b4b — relay-reconcile must surface STRANDED conflict-handback branches,
# not report a false clean.
#
# A branch enters relay/orphan/* only when a run DIES and its worktree is parked (id:689c).
# A child that hits a merge conflict does the right thing — `git merge --abort`, hand back —
# leaving its branch under the LIVE name relay/<runId>-<verdict>-repo-N. It never becomes an
# orphan, so both the --all sweep and the per-repo list answered "no parked orphans" while
# real unmerged work sat on disk (measured after run relay-20260812-122721-23819: 0 reported,
# 6 actually stranded — four from that run plus two older ones nobody knew about).
#
# This covers the SURFACING half only. Parking a conflict-handback branch at abort (the
# durable fix, in the integrator) is deliberately out of scope here.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$SRC_DIR/relay/scripts/relay-reconcile.sh"
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SCRIPT" ]] || fail "relay-reconcile.sh not executable"
bash -n "$SCRIPT" || fail "relay-reconcile.sh fails bash -n"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

repo="$tmpdir/repo"
mkdir -p "$repo"
git -C "$repo" init -q -b main
git -C "$repo" config user.email t@example.com
git -C "$repo" config user.name t
echo base > "$repo/f.txt"
git -C "$repo" add -A
git -C "$repo" commit -qm base

# A conflict-handback branch: live relay/<runId>-… name, carries a commit main lacks.
git -C "$repo" checkout -q -b relay/relay-20260101-000000-1234-review-repo-0
echo work > "$repo/g.txt"
git -C "$repo" add -A
git -C "$repo" commit -qm "unmerged review work"
git -C "$repo" checkout -q main

# A live-name branch with NOTHING beyond main must NOT be reported (pure litter, not work).
git -C "$repo" branch relay/relay-20260101-000000-1234-hard-repo-9 main

export HOME="$tmpdir/home"; mkdir -p "$HOME"

out="$(cd "$repo" && "$SCRIPT" "$repo" 2>&1)" || fail "reconcile exited non-zero: $out"

grep -q "no parked orphans" <<<"$out" \
  || fail "expected the parked-orphan line to still print (it is a separate class)"
grep -q "STRANDED" <<<"$out" \
  || { echo "$out" | sed 's/^/    /'; fail "the stranded branch was NOT surfaced — this is the false clean (THE DEFECT)"; }
grep -q "relay-20260101-000000-1234-review-repo-0" <<<"$out" \
  || fail "the stranded branch is not named in the output"
pass "a conflict-handback branch with unmerged commits is surfaced"

grep -q "hard-repo-9" <<<"$out" \
  && fail "a branch with no commits beyond trunk was reported — that is litter, not stranded work"
pass "a live-name branch carrying no work is NOT reported"

# The surfacing must never mutate anything.
[[ -n "$(git -C "$repo" rev-parse --verify -q refs/heads/relay/relay-20260101-000000-1234-review-repo-0)" ]] \
  || fail "the stranded branch was deleted — this listing must be strictly read-only"
pass "listing is read-only; the branch survives"

# LIVENESS is deliberately NOT asserted here (id:05a2). This file used to end with
#   grep -q 'live-runs' "$SCRIPT"
# under the comment "simulated by asserting the code consults heartbeat live-runs". That is a
# source-shape assertion, not a behavioural one: consulting the registry and consulting it
# CORRECTLY are different claims, and only the first was ever tested. The string `live-runs`
# was present the entire time the whole-line `grep -qxF` match made the gate unreachable
# (id:b99f, fixed in f0fdeb1) — the line stayed green through the defect's whole life.
# It is REMOVED rather than reworded: the behavioural coverage now lives in
# tests/test_reconcile_stranded_liveness_b99f.sh, which drives the real relay-reconcile.sh
# against the real heartbeat.sh (alive run suppressed / dead run reported / suppression
# disappears once the run stops / unreadable heartbeat fails safe). Keeping a source grep
# beside that test would read as extra coverage while providing none.

echo "ALL PASS: stranded conflict-handback branches are surfaced (2b4b)"
