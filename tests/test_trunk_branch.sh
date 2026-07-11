#!/usr/bin/env bash
# Defect-fix test (NO roadmap item — failures always count).
#
# Bug: the relay reap/park decision hardcoded `main` as the trunk. relay children branch
# their worktrees from HEAD (`worktree add … HEAD`, relay-loop.js), but reconcile-repo.sh
# tested `merge-base --is-ancestor <worktree-branch> main`. For a repo whose checked-out
# trunk is NOT literally `main` — e.g. ai-codebench works on `claude/opusplan` while `main`
# is frozen at an old checkpoint — every leftover worktree fails that ancestry test (its
# commits live on the real trunk, never on frozen `main`), so even a fully-integrated run's
# EMPTY worktree gets PARKED as a relay/orphan/* branch every round instead of reaped.
#
# Fix: trunk-branch.sh resolves the integration branch from the checked-out HEAD (the branch
# children fork from), and reconcile-repo.sh / discover-repo.sh / relay-reconcile.sh consult
# it instead of hardcoding `main`. This test pins that behavior.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TRUNK="$SRC_DIR/relay/scripts/trunk-branch.sh"
RECONCILE="$SRC_DIR/relay/scripts/reconcile-repo.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$TRUNK" ]] || fail "trunk-branch.sh not found/executable at $TRUNK"
[[ -x "$RECONCILE" ]] || fail "reconcile-repo.sh not found/executable at $RECONCILE"

make_repo() {
  local d; d="$(mktemp -d)"
  git -C "$d" init -q
  git -C "$d" config user.email t@t.t
  git -C "$d" config user.name t
  git -C "$d" config commit.gpgsign false
  echo seed > "$d/README.md"
  git -C "$d" add README.md
  git -C "$d" commit -qm seed
  echo "$d"
}

json_has_action() { # <json> <kind>
  printf '%s' "$1" | python3 -c 'import sys,json; d=json.load(sys.stdin); k=sys.argv[1]; sys.exit(0 if any(a.get("kind")==k for a in d.get("actions",[])) else 1)' "$2"
}

# ===========================================================================
# (1) trunk-branch.sh echoes the CHECKED-OUT branch, not a hardcoded main.
# ===========================================================================
{
  work="$(make_repo)"                       # starts on main (or master)
  git -C "$work" branch -M main             # normalize to main
  [[ "$("$TRUNK" "$work")" == main ]] || fail "(1a) main-trunk repo did not resolve to main"

  git -C "$work" checkout -q -b claude/opusplan
  echo x > "$work/x"; git -C "$work" add x; git -C "$work" commit -qm advance
  # main is now frozen behind; HEAD is claude/opusplan
  [[ "$("$TRUNK" "$work")" == claude/opusplan ]] \
    || fail "(1b) non-main trunk not resolved from HEAD (got '$("$TRUNK" "$work")')"
  pass "(1) trunk-branch.sh resolves the checked-out branch, not a hardcoded main"
}

# ===========================================================================
# (2) DETACHED HEAD → conventional main→master fallback.
# ===========================================================================
{
  work="$(make_repo)"; git -C "$work" branch -M main
  git -C "$work" checkout -q --detach HEAD
  [[ "$("$TRUNK" "$work")" == main ]] || fail "(2) detached HEAD did not fall back to main"
  pass "(2) detached HEAD falls back to main"
}

# ===========================================================================
# (3) THE BUG: repo on a non-main trunk (main frozen behind), an EMPTY stale worktree
#     branched from the real trunk must be REAPED, not PARKED — with --main-branch OMITTED
#     so reconcile-repo.sh auto-resolves the trunk from HEAD.
# ===========================================================================
{
  work="$(make_repo)"; git -C "$work" branch -M main
  git -C "$work" checkout -q -b claude/opusplan
  echo trunkwork > "$work/t"; git -C "$work" add t; git -C "$work" commit -qm "opusplan advance"
  # main is frozen at the seed commit; claude/opusplan is the live trunk.

  wtbase="$(mktemp -d)"
  bn="deadrun-execute"                      # foreign runId (not "thisrun")
  # empty worktree branched from HEAD (== claude/opusplan): its commit IS an ancestor of the
  # real trunk, so it must be reaped. It is NOT an ancestor of frozen main (the old bug).
  git -C "$work" worktree add -q -b "relay/$bn" "$wtbase/opusR/$bn" HEAD

  out="$(RELAY_WORKTREE_BASE="$wtbase" "$RECONCILE" --repo opusR --path "$work" --runid thisrun --live-claims "")"
  json_has_action "$out" reap || fail "(3) empty stale worktree on a non-main trunk was NOT reaped (the mis-park bug): $out"
  ! json_has_action "$out" park || fail "(3) empty stale worktree on a non-main trunk was wrongly PARKED as an orphan: $out"
  ! git -C "$work" show-ref --verify --quiet "refs/heads/relay/orphan/$bn" \
    || fail "(3) a spurious relay/orphan/$bn ref was created for already-integrated work"
  [[ ! -d "$wtbase/opusR/$bn" ]] || fail "(3) reaped worktree dir not removed"
  pass "(3) integrated worktree on a non-main trunk is reaped, not mis-parked (auto-resolved trunk)"
}

# ===========================================================================
# (4) Guard: genuinely-unmerged work on a non-main trunk still PARKS (no data loss).
# ===========================================================================
{
  work="$(make_repo)"; git -C "$work" branch -M main
  git -C "$work" checkout -q -b claude/opusplan
  echo trunkwork > "$work/t"; git -C "$work" add t; git -C "$work" commit -qm "opusplan advance"

  wtbase="$(mktemp -d)"
  bn="deadrun2-hard"
  git -C "$work" worktree add -q -b "relay/$bn" "$wtbase/parkO/$bn" HEAD
  echo wip > "$wtbase/parkO/$bn/wip.txt"
  git -C "$wtbase/parkO/$bn" add wip.txt
  git -C "$wtbase/parkO/$bn" -c user.email=t@t.t -c user.name=t commit -qm "unmerged wip"
  wip_sha="$(git -C "$work" rev-parse "relay/$bn")"

  out="$(RELAY_WORKTREE_BASE="$wtbase" "$RECONCILE" --repo parkO --path "$work" --runid thisrun --live-claims "")"
  json_has_action "$out" park || fail "(4) unmerged work on a non-main trunk was not parked: $out"
  [[ "$(git -C "$work" rev-parse "relay/orphan/$bn")" == "$wip_sha" ]] \
    || fail "(4) unmerged commit not preserved on orphan ref (DATA LOSS)"
  pass "(4) genuinely-unmerged work on a non-main trunk still parks, commit preserved"
}

echo "ALL PASS: trunk-branch resolution + non-main-trunk reap/park"
