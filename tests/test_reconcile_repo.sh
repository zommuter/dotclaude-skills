#!/usr/bin/env bash
# roadmap:5987 — reconcile-repo.sh: the bounded side-effecting git reconciliation split
# out of the LLM discovery shard (flip step b, id:a0b6). BEHAVIORAL RED spec — hermetic
# mktemp git fixtures seeded from the REAL failure states the shard prose handles
# (relay-loop.js:854-870): behind-only ff-merge (id:c3f7), diverged block (id:c3f7),
# uv.lock-only dirty relock (id:bae5), stale-worktree reap (id:3ac8), orphan-park (id:689c).
#
# Contract under test (authored by /relay handoff 2026-07-01):
#   reconcile-repo.sh --repo <name> --path <abs> [--runid <id>]
#                     [--live-claims <comma-list>] [--main-branch <name>]
#   Performs ONLY bounded side-effecting git ops; emits ONE JSON object on stdout:
#     {"repo":"<name>","actions":[{"kind":"<k>","detail":"<...>"}],"surfaced":[{"repo","reason"}]}
#   kind ∈ {ff-merge, diverged-surface, lock-commit, reap, park}. NO classification
#   (that stays classify-repo.sh). Env: RELAY_WORKTREE_BASE (worktree root, gather parity).
#
# RED until reconcile-repo.sh lands. ROADMAP box id:5987 unticked ⇒ EXPECTED-RED (does
# not fail the suite); ticking the box makes any failure real (DoD gate).
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RECONCILE="$SRC_DIR/relay/scripts/reconcile-repo.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$RECONCILE" ]] || fail "reconcile-repo.sh not found/executable at $RECONCILE (RED: script not built yet)"

# --- helpers ---------------------------------------------------------------
git_q() { git -C "$1" "${@:2}" >/dev/null 2>&1; }

# a committed git repo with one file; prints its path
make_repo() {
  local d; d="$(mktemp -d)"
  git -C "$d" init -q
  git -C "$d" config user.email t@t.t
  git -C "$d" config user.name t
  git -C "$d" config commit.gpgsign false
  echo "seed" > "$d/README.md"
  git -C "$d" add README.md
  git -C "$d" commit -qm "seed"
  echo "$d"
}

json_has_action() { # <json> <kind>
  printf '%s' "$1" | python3 -c 'import sys,json; d=json.load(sys.stdin); k=sys.argv[1]; sys.exit(0 if any(a.get("kind")==k for a in d.get("actions",[])) else 1)' "$2"
}

# ===========================================================================
# (1) BEHIND-ONLY → ff-merge (id:c3f7): local is strictly behind origin, clean tree.
#     reconcile fast-forwards; HEAD advances to origin; emits action ff-merge.
# ===========================================================================
{
  origin="$(mktemp -d)"; git -C "$origin" init -q --bare
  work="$(make_repo)"
  git -C "$work" remote add origin "$origin"
  git -C "$work" push -q -u origin HEAD:refs/heads/main
  # advance origin via a second clone
  c2="$(mktemp -d)"; git clone -q "$origin" "$c2"
  git -C "$c2" config user.email t@t.t; git -C "$c2" config user.name t
  echo more > "$c2/f2"; git -C "$c2" add f2; git -C "$c2" commit -qm ahead
  git -C "$c2" push -q origin HEAD:refs/heads/main
  before="$(git -C "$work" rev-parse HEAD)"
  out="$("$RECONCILE" --repo behind --path "$work" --runid thisrun --live-claims "" --main-branch main)"
  after="$(git -C "$work" rev-parse HEAD)"
  [[ "$before" != "$after" ]] || fail "(1) behind-only: HEAD did not fast-forward"
  json_has_action "$out" ff-merge || fail "(1) behind-only: no ff-merge action in JSON: $out"
  pass "(1) behind-only fast-forwards + emits ff-merge (id:c3f7)"
}

# ===========================================================================
# (2) DIVERGED → surface, NO git write (id:c3f7): local ahead AND behind.
#     reconcile must NOT commit/merge; emits diverged-surface + a surfaced entry.
# ===========================================================================
{
  origin="$(mktemp -d)"; git -C "$origin" init -q --bare
  work="$(make_repo)"
  git -C "$work" remote add origin "$origin"
  git -C "$work" push -q -u origin HEAD:refs/heads/main
  c2="$(mktemp -d)"; git clone -q "$origin" "$c2"
  git -C "$c2" config user.email t@t.t; git -C "$c2" config user.name t
  echo o > "$c2/fo"; git -C "$c2" add fo; git -C "$c2" commit -qm origin-side
  git -C "$c2" push -q origin HEAD:refs/heads/main
  echo l > "$work/fl"; git -C "$work" add fl; git -C "$work" commit -qm local-side
  git -C "$work" fetch -q origin
  before="$(git -C "$work" rev-parse HEAD)"
  out="$("$RECONCILE" --repo diverged --path "$work" --runid thisrun --live-claims "" --main-branch main)"
  after="$(git -C "$work" rev-parse HEAD)"
  [[ "$before" == "$after" ]] || fail "(2) diverged: HEAD changed — reconcile must never merge/commit a diverged repo"
  json_has_action "$out" diverged-surface || fail "(2) diverged: no diverged-surface action: $out"
  printf '%s' "$out" | python3 -c 'import sys,json;sys.exit(0 if json.load(sys.stdin).get("surfaced") else 1)' \
    || fail "(2) diverged: no surfaced entry"
  pass "(2) diverged surfaces without any git write (id:c3f7)"
}

# ===========================================================================
# (3) uv.lock-ONLY dirty → in-place lock-commit (id:bae5): tree dirty with ONLY
#     uv.lock modified. reconcile commits it; tree becomes clean; action lock-commit.
# ===========================================================================
{
  work="$(make_repo)"
  echo "lock v1" > "$work/uv.lock"; git -C "$work" add uv.lock; git -C "$work" commit -qm "add lock"
  echo "lock v2 relock" > "$work/uv.lock"   # dirty: only uv.lock modified
  out="$("$RECONCILE" --repo lockonly --path "$work" --runid thisrun --live-claims "")"
  [[ -z "$(git -C "$work" status --porcelain)" ]] || fail "(3) uv.lock-only: tree still dirty after reconcile"
  json_has_action "$out" lock-commit || fail "(3) uv.lock-only: no lock-commit action: $out"
  pass "(3) uv.lock-only dirty is committed in place (id:bae5)"
}

# (3b) DIRTY non-lock → reconcile must NOT commit (that becomes classify's `blocked`).
{
  work="$(make_repo)"
  echo change > "$work/README.md"   # dirty non-lock
  out="$("$RECONCILE" --repo dirtycode --path "$work" --runid thisrun --live-claims "")"
  ! json_has_action "$out" lock-commit || fail "(3b) dirty non-lock: reconcile wrongly committed a non-lock dirty tree"
  [[ -n "$(git -C "$work" status --porcelain)" ]] || fail "(3b) dirty non-lock: reconcile silently cleaned a non-lock dirty tree"
  pass "(3b) dirty non-lock is left untouched for classify to block (id:e424)"
}

# ===========================================================================
# (4) STALE worktree, EMPTY (ancestor of main), repo NOT in live-claims → REAP
#     (id:3ac8): worktree dir removed + relay/<basename> branch deleted; action reap.
# ===========================================================================
{
  work="$(make_repo)"
  wtbase="$(mktemp -d)"
  bn="deadrun-execute"   # foreign runId (does not start with "thisrun")
  git -C "$work" worktree add -q -b "relay/$bn" "$wtbase/staleR/$bn" HEAD   # HEAD == main → ancestor, empty
  out="$(RELAY_WORKTREE_BASE="$wtbase" "$RECONCILE" --repo staleR --path "$work" --runid thisrun --live-claims "" --main-branch main)"
  [[ ! -d "$wtbase/staleR/$bn" ]] || fail "(4) stale-empty: worktree dir not reaped"
  ! git -C "$work" show-ref --verify --quiet "refs/heads/relay/$bn" || fail "(4) stale-empty: relay/$bn branch not deleted"
  json_has_action "$out" reap || fail "(4) stale-empty: no reap action: $out"
  pass "(4) empty stale worktree is reaped (id:3ac8)"
}

# ===========================================================================
# (5) STALE worktree WITH unmerged commit, repo NOT in live-claims → PARK
#     (id:689c): branch renamed relay/<bn> → relay/orphan/<bn>, worktree removed,
#     commit still reachable, surfaced; action park. NEVER reaped (data-loss guard).
# ===========================================================================
{
  work="$(make_repo)"
  wtbase="$(mktemp -d)"
  bn="deadrun2-hard"
  git -C "$work" worktree add -q -b "relay/$bn" "$wtbase/parkR/$bn" HEAD
  echo wip > "$wtbase/parkR/$bn/wip.txt"
  git -C "$wtbase/parkR/$bn" add wip.txt
  git -C "$wtbase/parkR/$bn" -c user.email=t@t.t -c user.name=t commit -qm "unmerged wip"
  wip_sha="$(git -C "$work" rev-parse "relay/$bn")"
  out="$(RELAY_WORKTREE_BASE="$wtbase" "$RECONCILE" --repo parkR --path "$work" --runid thisrun --live-claims "" --main-branch main)"
  [[ ! -d "$wtbase/parkR/$bn" ]] || fail "(5) park: worktree dir not removed"
  git -C "$work" show-ref --verify --quiet "refs/heads/relay/orphan/$bn" || fail "(5) park: orphan ref relay/orphan/$bn not created"
  ! git -C "$work" show-ref --verify --quiet "refs/heads/relay/$bn" || fail "(5) park: original relay/$bn branch still present (should be renamed)"
  [[ "$(git -C "$work" rev-parse "relay/orphan/$bn")" == "$wip_sha" ]] || fail "(5) park: unmerged commit not preserved on orphan ref (DATA LOSS)"
  json_has_action "$out" park || fail "(5) park: no park action: $out"
  pass "(5) commit-bearing stale worktree is parked to relay/orphan/*, commit preserved (id:689c)"
}

# ===========================================================================
# (6) LIVE claim → in-flight elsewhere: a foreign worktree whose repo IS in the
#     live-claim set is NEVER reaped/parked — surfaced, no git write (id:ebfb).
# ===========================================================================
{
  work="$(make_repo)"
  wtbase="$(mktemp -d)"
  bn="otherrun-execute"
  git -C "$work" worktree add -q -b "relay/$bn" "$wtbase/liveR/$bn" HEAD
  out="$(RELAY_WORKTREE_BASE="$wtbase" "$RECONCILE" --repo liveR --path "$work" --runid thisrun --live-claims "liveR" --main-branch main)"
  [[ -d "$wtbase/liveR/$bn" ]] || fail "(6) live-claim: worktree wrongly removed for a live-claimed repo"
  ! json_has_action "$out" reap || fail "(6) live-claim: wrongly reaped a live-claimed repo"
  ! json_has_action "$out" park || fail "(6) live-claim: wrongly parked a live-claimed repo"
  pass "(6) live-claimed foreign worktree is left in-flight, not reaped/parked (id:ebfb)"
}

echo "ALL PASS: reconcile-repo.sh behavioral spec (id:5987)"
