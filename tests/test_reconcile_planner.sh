#!/usr/bin/env bash
# roadmap:77ce — reconcile-repo.sh pure PLANNER + thin APPLIER refactor.
# BEHAVIORAL RED spec — hermetic mktemp git fixtures. Verifies that a new `--dry-run`
# flag runs the PLAN phase only: it emits the SAME plan JSON a live run would act on,
# but performs ZERO side effects (no ff-merge, no lock-commit, no reap/park). The
# identity "--dry-run action list == live-run action list for the same state" is the
# parity oracle relay-core's ebdb-b Lean port shadow-compares against (routed:2f0c).
#
# Contract under test (authored by /relay handoff 2026-07-10):
#   reconcile-repo.sh --dry-run --repo <name> --path <abs> [...]  → plan JSON, NO git write.
#   reconcile-repo.sh           --repo <name> --path <abs> [...]  → plan JSON + APPLY (as today).
#   The `actions`/`surfaced` lists MUST be identical with and without --dry-run.
#
# RED until the planner/applier split + --dry-run land. Today `--dry-run` is rejected as an
# unknown arg (reconcile-repo.sh exit 2). ROADMAP box id:77ce unticked ⇒ EXPECTED-RED (does
# not fail the suite); ticking the box makes any failure real (DoD gate).
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RECONCILE="$SRC_DIR/relay/scripts/reconcile-repo.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$RECONCILE" ]] || fail "reconcile-repo.sh not found/executable at $RECONCILE"

# --- helpers ---------------------------------------------------------------
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
# sorted, newline-joined list of action kinds — the parity key
action_kinds() { # <json>
  printf '%s' "$1" | python3 -c 'import sys,json; d=json.load(sys.stdin); print("\n".join(sorted(a.get("kind","") for a in d.get("actions",[]))))'
}

# ===========================================================================
# (1) DRY-RUN behind-only → plans ff-merge but does NOT advance HEAD (no side effect).
# ===========================================================================
{
  origin="$(mktemp -d)"; git -C "$origin" init -q --bare
  work="$(make_repo)"
  git -C "$work" remote add origin "$origin"
  git -C "$work" push -q -u origin HEAD:refs/heads/main
  c2="$(mktemp -d)"; git clone -q "$origin" "$c2"
  git -C "$c2" config user.email t@t.t; git -C "$c2" config user.name t
  echo more > "$c2/f2"; git -C "$c2" add f2; git -C "$c2" commit -qm ahead
  git -C "$c2" push -q origin HEAD:refs/heads/main
  git -C "$work" fetch -q origin
  before="$(git -C "$work" rev-parse HEAD)"
  out="$("$RECONCILE" --dry-run --repo behind --path "$work" --runid thisrun --live-claims "" --main-branch main)"
  after="$(git -C "$work" rev-parse HEAD)"
  [[ "$before" == "$after" ]] || fail "(1) dry-run behind-only: HEAD advanced — --dry-run must not fast-forward"
  json_has_action "$out" ff-merge || fail "(1) dry-run behind-only: plan JSON missing ff-merge action: $out"
  pass "(1) --dry-run plans ff-merge without advancing HEAD (id:c3f7 pure-plan)"
}

# ===========================================================================
# (2) DRY-RUN uv.lock-only dirty → plans lock-commit but leaves the tree dirty.
# ===========================================================================
{
  work="$(make_repo)"
  echo "lock v1" > "$work/uv.lock"; git -C "$work" add uv.lock; git -C "$work" commit -qm "add lock"
  echo "lock v2 relock" > "$work/uv.lock"
  out="$("$RECONCILE" --dry-run --repo lockonly --path "$work" --runid thisrun --live-claims "")"
  [[ -n "$(git -C "$work" status --porcelain)" ]] || fail "(2) dry-run uv.lock-only: tree was committed — --dry-run must not commit"
  json_has_action "$out" lock-commit || fail "(2) dry-run uv.lock-only: plan JSON missing lock-commit action: $out"
  pass "(2) --dry-run plans lock-commit without committing (id:bae5 pure-plan)"
}

# ===========================================================================
# (3) DRY-RUN stale-empty worktree → plans reap but leaves the worktree dir + branch.
# ===========================================================================
{
  work="$(make_repo)"
  wtbase="$(mktemp -d)"
  bn="deadrun-execute"
  git -C "$work" worktree add -q -b "relay/$bn" "$wtbase/staleR/$bn" HEAD
  out="$(RELAY_WORKTREE_BASE="$wtbase" "$RECONCILE" --dry-run --repo staleR --path "$work" --runid thisrun --live-claims "" --main-branch main)"
  [[ -d "$wtbase/staleR/$bn" ]] || fail "(3) dry-run stale-empty: worktree dir was removed — --dry-run must not reap"
  git -C "$work" show-ref --verify --quiet "refs/heads/relay/$bn" || fail "(3) dry-run stale-empty: relay/$bn branch was deleted — --dry-run must not reap"
  json_has_action "$out" reap || fail "(3) dry-run stale-empty: plan JSON missing reap action: $out"
  pass "(3) --dry-run plans reap without removing the worktree/branch (id:3ac8 pure-plan)"
}

# ===========================================================================
# (4) DRY-RUN commit-bearing worktree → plans park but leaves branch un-renamed, dir present.
# ===========================================================================
{
  work="$(make_repo)"
  wtbase="$(mktemp -d)"
  bn="deadrun2-hard"
  git -C "$work" worktree add -q -b "relay/$bn" "$wtbase/parkR/$bn" HEAD
  echo wip > "$wtbase/parkR/$bn/wip.txt"
  git -C "$wtbase/parkR/$bn" add wip.txt
  git -C "$wtbase/parkR/$bn" -c user.email=t@t.t -c user.name=t commit -qm "unmerged wip"
  out="$(RELAY_WORKTREE_BASE="$wtbase" "$RECONCILE" --dry-run --repo parkR --path "$work" --runid thisrun --live-claims "" --main-branch main)"
  [[ -d "$wtbase/parkR/$bn" ]] || fail "(4) dry-run park: worktree dir removed — --dry-run must not park"
  git -C "$work" show-ref --verify --quiet "refs/heads/relay/$bn" || fail "(4) dry-run park: original relay/$bn branch renamed away — --dry-run must not park"
  ! git -C "$work" show-ref --verify --quiet "refs/heads/relay/orphan/$bn" || fail "(4) dry-run park: orphan ref created — --dry-run must not park"
  json_has_action "$out" park || fail "(4) dry-run park: plan JSON missing park action: $out"
  pass "(4) --dry-run plans park without renaming/removing (id:689c pure-plan)"
}

# ===========================================================================
# (5) PARITY ORACLE: for the same seeded state, the --dry-run action-kind list equals
#     the live-run action-kind list. Run dry-run first (asserts no mutation), then live.
# ===========================================================================
{
  work="$(make_repo)"
  echo "lock v1" > "$work/uv.lock"; git -C "$work" add uv.lock; git -C "$work" commit -qm "add lock"
  echo "lock v2 relock" > "$work/uv.lock"
  dry="$("$RECONCILE" --dry-run --repo parity --path "$work" --runid thisrun --live-claims "")"
  [[ -n "$(git -C "$work" status --porcelain)" ]] || fail "(5) parity: dry-run mutated the tree"
  live="$("$RECONCILE" --repo parity --path "$work" --runid thisrun --live-claims "")"
  dk="$(action_kinds "$dry")"; lk="$(action_kinds "$live")"
  [[ "$dk" == "$lk" ]] || fail "(5) parity: dry-run action kinds [$dk] != live action kinds [$lk] — plan is not the oracle"
  [[ -z "$(git -C "$work" status --porcelain)" ]] || fail "(5) parity: live run did not actually apply the lock-commit"
  pass "(5) --dry-run plan action list == live-run action list (parity oracle for routed:2f0c)"
}

# ===========================================================================
# (6) FAIL-CLOSED preserved (id:e3ad): --live-claims absent (Unknown) still refuses reap/park
#     — assert under --dry-run the plan carries NO reap/park and DOES surface the refusal.
# ===========================================================================
{
  work="$(make_repo)"
  wtbase="$(mktemp -d)"
  bn="deadrun-execute"
  git -C "$work" worktree add -q -b "relay/$bn" "$wtbase/fcR/$bn" HEAD
  # NOTE: --live-claims deliberately NOT passed → Unknown → fail-closed guard.
  out="$(RELAY_WORKTREE_BASE="$wtbase" "$RECONCILE" --dry-run --repo fcR --path "$work" --runid thisrun --main-branch main)"
  ! json_has_action "$out" reap || fail "(6) fail-closed: plan reaped despite Unknown live-claims (id:e3ad)"
  ! json_has_action "$out" park || fail "(6) fail-closed: plan parked despite Unknown live-claims (id:e3ad)"
  printf '%s' "$out" | python3 -c 'import sys,json;s=json.load(sys.stdin).get("surfaced",[]);sys.exit(0 if any("e3ad" in x.get("reason","") for x in s) else 1)' \
    || fail "(6) fail-closed: no id:e3ad refusal surfaced: $out"
  pass "(6) Unknown live-claims (flag absent) still fail-closed under --dry-run (id:e3ad)"
}

echo "ALL PASS: reconcile-repo.sh planner/--dry-run spec (id:77ce)"
