#!/usr/bin/env bash
# DEFECT-FIX test (no roadmap id — structural hardening, id:e3ad in commit trailer only;
# not a ROADMAP item so this file carries no `# roadmap:XXXX` header and its failures
# always count per tests/run-tests.sh EXPECTED-RED semantics).
#
# CONTEXT: a strong-model audit found that a caller invoking reconcile-repo.sh with EMPTY
# --live-claims was treated identically to a caller that never invoked --live-claims at all
# ("" == unset in bash's default-empty-string parsing), so any future caller that simply
# forgets to pass --live-claims/--runid silently reaps LIVE worktrees (fail-OPEN). This spec
# locks in the fail-CLOSED fix: reconcile-repo.sh must distinguish
#   (a) --live-claims flag ABSENT entirely           -> REFUSE to reap/park (no safety context)
#   (b) --live-claims "" (flag present, explicit empty) -> reap permitted (legit "nothing live")
#   (c) --live-claims "<repo>" (repo named live)     -> not reaped (existing id:ebfb protection)
#
# The live loop (relay-loop.js -> discover-repo.sh -> reconcile-repo.sh) ALWAYS passes
# --live-claims (even when empty) + --runid, so it only ever hits cases (b)/(c), never (a) —
# this is purely an additive guard against a future/alternate caller omitting the flag.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RECONCILE="$SRC_DIR/relay/scripts/reconcile-repo.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$RECONCILE" ]] || fail "reconcile-repo.sh not found/executable at $RECONCILE"

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
# (a) NO --live-claims / --runid flag at all -> reap REFUSED, worktree + branch survive,
#     a loud warning is emitted (stderr), no reap/park action in the JSON.
# ===========================================================================
{
  work="$(make_repo)"
  wtbase="$(mktemp -d)"
  bn="deadrun-execute"
  git -C "$work" worktree add -q -b "relay/$bn" "$wtbase/noctxR/$bn" HEAD   # empty, ancestor of main
  err_file="$(mktemp)"
  out="$(RELAY_WORKTREE_BASE="$wtbase" "$RECONCILE" --repo noctxR --path "$work" --main-branch main 2>"$err_file")"
  [[ -d "$wtbase/noctxR/$bn" ]] || fail "(a) no-context: worktree dir was reaped despite ABSENT --live-claims (fail-open regression)"
  git -C "$work" show-ref --verify --quiet "refs/heads/relay/$bn" || fail "(a) no-context: relay/$bn branch was deleted despite ABSENT --live-claims"
  ! json_has_action "$out" reap || fail "(a) no-context: reap action present despite ABSENT --live-claims: $out"
  ! json_has_action "$out" park || fail "(a) no-context: park action present despite ABSENT --live-claims: $out"
  [[ -s "$err_file" ]] || fail "(a) no-context: no loud warning emitted on stderr for the missing safety context"
  grep -qi "live-claims" "$err_file" || fail "(a) no-context: warning does not name the missing --live-claims context: $(cat "$err_file")"
  rm -f "$err_file"
  pass "(a) reconcile with NO --live-claims/--runid context refuses to reap and warns loudly (id:e3ad fail-closed)"
}

# ===========================================================================
# (b) --live-claims "" EXPLICIT empty (flag present, caller checked nothing is live) ->
#     reap still permitted — proves the guard didn't over-restrict the legitimate case.
# ===========================================================================
{
  work="$(make_repo)"
  wtbase="$(mktemp -d)"
  bn="deadrun-execute2"
  git -C "$work" worktree add -q -b "relay/$bn" "$wtbase/emptyR/$bn" HEAD
  out="$(RELAY_WORKTREE_BASE="$wtbase" "$RECONCILE" --repo emptyR --path "$work" --runid thisrun --live-claims "" --main-branch main)"
  [[ ! -d "$wtbase/emptyR/$bn" ]] || fail "(b) explicit-empty: worktree dir not reaped despite explicit --live-claims \"\""
  ! git -C "$work" show-ref --verify --quiet "refs/heads/relay/$bn" || fail "(b) explicit-empty: relay/$bn branch still present"
  json_has_action "$out" reap || fail "(b) explicit-empty: no reap action in JSON: $out"
  pass "(b) explicit --live-claims \"\" still permits reap (legit nothing-live case unaffected)"
}

# ===========================================================================
# (c) --live-claims "<repo>" naming the repo -> existing id:ebfb protection intact,
#     not reaped/parked, surfaced as in-flight elsewhere.
# ===========================================================================
{
  work="$(make_repo)"
  wtbase="$(mktemp -d)"
  bn="otherrun-execute"
  git -C "$work" worktree add -q -b "relay/$bn" "$wtbase/liveR/$bn" HEAD
  out="$(RELAY_WORKTREE_BASE="$wtbase" "$RECONCILE" --repo liveR --path "$work" --runid thisrun --live-claims "liveR" --main-branch main)"
  [[ -d "$wtbase/liveR/$bn" ]] || fail "(c) live-claim: worktree wrongly removed for a live-claimed repo"
  ! json_has_action "$out" reap || fail "(c) live-claim: wrongly reaped a live-claimed repo"
  ! json_has_action "$out" park || fail "(c) live-claim: wrongly parked a live-claimed repo"
  pass "(c) --live-claims naming the repo still protects it from reap/park (id:ebfb intact)"
}

echo "ALL PASS: reconcile-repo.sh fail-closed reap guard (id:e3ad)"
