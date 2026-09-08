#!/usr/bin/env bash
# roadmap:4263 — relay-reconcile.sh integrate_branch PER-REMOTE push narrowing.
#
# DEFECT: step 4 was `git-lock-push.sh --ff-only --all`, which pushes EVERY remote of the
# repo including a PUBLIC one, violating id:f66e. It is reachable UNATTENDED — relay-loop.js
# runs `--auto-restart`, which runs its own `--all --auto`, which calls this same shared
# `integrate_branch`. The escalation is that `ratify-queue.sh` verifies entries by asking the
# REMOTE (`git ls-remote`), so a public push here makes pending ratification entries
# self-verify as landed; observed 2026-09-08, the queue went 6 -> 0.
#
# Spec:
#   (1) MIXED — the private/LAN remote receives the merge; the public one is BYTE-UNMOVED.
#   (2) The withheld remote is surfaced LOUDLY on stderr, and the URL is NOT printed.
#   (3) ALL-PRIVATE — everything is pushed and NO withhold warning is emitted.
#   (4) FAIL-CLOSED — with lib-private-remote.sh absent, NOTHING is pushed (not even a
#       remote that would have classified private), because nothing can be PROVEN private.
#   (5) The branch ref is still consumed in every case: step 2's --no-ff merge is what makes
#       `git branch -d` valid, so a withheld push must not strand the ref.
#
# fails-against-mutation: sed -i 's|"\$LOCK_PUSH" "\$repo" "\${_push_args\[@\]}"|"$LOCK_PUSH" "$repo" --ff-only --all|' relay/scripts/relay-reconcile.sh
# fails-against-assertion: (1) the PUBLIC remote received the merge
#   Reachability: the mutation restores the pre-fix `--all` call while leaving the
#   classification loop in place, so case (1) is the assertion that fires. Cases (2)-(4)
#   are NOT independently reachable under this mutation — (2)/(4) concern the surfacing and
#   fail-closed paths, which the mutation does not touch — and case (1) is ordered FIRST so
#   the declared substring is the one that fires.
#
# Hermetic: mktemp repos with LOCAL BARE remotes, a FIXTURE private-host pattern file (never
# the real ~/.config/dotclaude-skills/privacy-patterns.txt), GIT_CONFIG_COUNT to neutralise a
# global core.hooksPath. No network, no real repos, no ~/.claude.
set -uo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REC="${REC_OVERRIDE:-$SRC_DIR/relay/scripts/relay-reconcile.sh}"
LOCKPUSH="$SRC_DIR/git-diary-workflow/git-lock-push.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
ERRLOG="$TMP/rec.stderr"; : >"$ERRLOG"
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; [[ -s "$ERRLOG" ]] && { echo "       last relay-reconcile.sh stderr:"; tail -n 25 "$ERRLOG" | sed 's/^/       | /'; }; exit 1; }

[[ -x "$REC" ]] || fail "relay-reconcile.sh not found/executable at $REC"
[[ -x "$LOCKPUSH" ]] || fail "git-lock-push.sh not found/executable at $LOCKPUSH"

export GIT_CONFIG_COUNT=4
export GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0="$TMP/nohooks"
export GIT_CONFIG_KEY_1=user.email     GIT_CONFIG_VALUE_1=t@e.st
export GIT_CONFIG_KEY_2=user.name      GIT_CONFIG_VALUE_2=t
export GIT_CONFIG_KEY_3=init.defaultBranch GIT_CONFIG_VALUE_3=main
mkdir -p "$TMP/nohooks"

# FIXTURE private-host pattern file: any bare remote whose path ends `-lan.git` is PRIVATE.
# A real host name never appears in a committed file (public repo).
PATFILE="$TMP/privacy-patterns.txt"
printf '# fixture -- synthetic only\nprivate-host: -lan\\.git$\n' > "$PATFILE"
export PRIVACY_GATE_PATTERNS="$PATFILE"

# build <sfx> <kind: mixed|lanonly> → prints the main checkout path
build() {
  local sfx="$1" kind="$2"
  local pub="$TMP/o-$sfx.git" lan="$TMP/o-$sfx-lan.git" seed="$TMP/s-$sfx" main="$TMP/m-$sfx"
  git init --bare -b main -q "$pub"
  git init --bare -b main -q "$lan"
  git clone -q "$pub" "$seed" 2>/dev/null
  echo base > "$seed/f"
  printf '# Roadmap\n\n- [ ] [ROUTINE] item <!-- id:aaaa -->\n' > "$seed/ROADMAP.md"
  git -C "$seed" add -A; git -C "$seed" commit -qm base
  git -C "$seed" push -q -u origin main
  git clone -q "$pub" "$main" 2>/dev/null
  git -C "$main" remote add lan "$lan"
  git -C "$main" push -q lan main
  # `-u` matters: without an upstream the push fails at git level, which would make case (4)
  # pass for the WRONG reason — an unreached push looks identical to a withheld one. Case (3)
  # is the negative control that proves this same fixture DOES push when the lib is present.
  if [[ "$kind" == lanonly ]]; then
    git -C "$main" remote remove origin
    git -C "$main" push -q -u lan main
  fi
  printf '%s' "$main"
}

# park <main> <name> → creates a LEDGER-ONLY parked orphan branch, prints its full name
park() {
  # NOT one `local` statement: its assignments are expanded BEFORE the builtin runs, so a
  # later word referencing an earlier name ("$TMP/wt-$name") sees it still unset under `set -u`.
  local main="$1" name="$2"
  local wt="$TMP/wt-$name"
  git -C "$main" worktree add -q -b "relay/orphan/$name" "$wt" main
  printf '# Roadmap\n\n- [x] [ROUTINE] item <!-- id:aaaa -->\n' > "$wt/ROADMAP.md"
  git -C "$wt" add -A; git -C "$wt" commit -qm "ledger: close aaaa"
  git -C "$main" worktree remove "$wt" >/dev/null 2>&1 || true
  printf 'relay/orphan/%s' "$name"
}

bare_head() { git -C "$1" rev-parse --verify -q refs/heads/main 2>/dev/null || echo NONE; }

run_integrate() { # <main> <branch> <scripts-dir-or-empty>
  local main="$1" br="$2" recbin="$REC"
  [[ -n "${3:-}" ]] && recbin="$3/relay-reconcile.sh"
  RELAY_LOCK_PUSH="$LOCKPUSH" "$recbin" "$main" --integrate "$br" 2>>"$ERRLOG"
}

# =====================================================================================
# (1)(2) MIXED: private `lan` pushed, public `origin` WITHHELD
# =====================================================================================
M1="$(build mix mixed)"; PUB1="$TMP/o-mix.git"; LAN1="$TMP/o-mix-lan.git"
B1="$(park "$M1" mix)"
PUB_BEFORE="$(bare_head "$PUB1")"
: >"$ERRLOG"
out1="$(run_integrate "$M1" "$B1")"; rc1=$?
[[ $rc1 -eq 0 ]] || fail "(1) mixed integrate exited $rc1 — a withheld public remote is a SUCCESS path"
HEAD1="$(git -C "$M1" rev-parse HEAD)"

[[ "$(bare_head "$PUB1")" == "$PUB_BEFORE" ]] \
  && pass "(1) the PUBLIC remote is byte-unmoved — no unattended auto-publish" \
  || fail "(1) the PUBLIC remote received the merge — id:4263 auto-publish is BACK (pub=$(bare_head "$PUB1") HEAD=$HEAD1)"
[[ "$(bare_head "$LAN1")" == "$HEAD1" ]] \
  && pass "(1) the PRIVATE/LAN remote received the merge automatically" \
  || fail "(1) the private remote did NOT receive the merge (lan=$(bare_head "$LAN1") HEAD=$HEAD1)"

grep -q 'PUBLIC/UNPROVEN REMOTE WITHHELD' "$ERRLOG" \
  && pass "(2) the withheld remote is surfaced LOUDLY on stderr" \
  || fail "(2) no id:4263 withhold warning on stderr — a silent withhold is the id:4347 no-swallow class"
grep -q 'origin' "$ERRLOG" \
  && pass "(2) the warning NAMES the withheld remote" \
  || fail "(2) the withhold warning does not name the remote"
grep -q "$PUB1" "$ERRLOG" \
  && fail "(2) the warning PRINTED THE REMOTE URL — this text can reach status output committed to a PUBLIC repo" \
  || pass "(2) the warning does not print the remote URL"
grep -q 'push-withheld\|pushed-private-only' <<<"$out1" \
  && pass "(2) stdout status reports the partial push" \
  || fail "(2) stdout does not report the withheld push: $out1"

git -C "$M1" rev-parse -q --verify "refs/heads/$B1" >/dev/null \
  && fail "(5) the parked ref survived a successful integrate" \
  || pass "(5) the parked ref was consumed despite the withheld remote"

# =====================================================================================
# (3) ALL-PRIVATE: everything pushed, no withhold warning
# =====================================================================================
M2="$(build allpriv lanonly)"; LAN2="$TMP/o-allpriv-lan.git"
B2="$(park "$M2" allpriv)"
: >"$ERRLOG"
out2="$(run_integrate "$M2" "$B2")"; rc2=$?
[[ $rc2 -eq 0 ]] || fail "(3) all-private integrate exited $rc2"
HEAD2="$(git -C "$M2" rev-parse HEAD)"
[[ "$(bare_head "$LAN2")" == "$HEAD2" ]] \
  && pass "(3) the sole private remote received the merge" \
  || fail "(3) the private remote did NOT receive the merge (lan=$(bare_head "$LAN2") HEAD=$HEAD2)"
grep -q 'PUBLIC/UNPROVEN REMOTE WITHHELD' "$ERRLOG" \
  && fail "(3) a withhold warning fired with NO public remote present — false positive" \
  || pass "(3) no withhold warning when every remote is provably private"

# =====================================================================================
# (4) FAIL-CLOSED: predicate library absent → NOTHING is pushed
# =====================================================================================
FAKE="$TMP/scripts-nolib"
cp -a "$(cd "$(dirname "$REC")" && pwd)" "$FAKE"
rm -- "$FAKE/lib-private-remote.sh"
M3="$(build failclosed lanonly)"; LAN3="$TMP/o-failclosed-lan.git"
B3="$(park "$M3" failclosed)"
LAN3_BEFORE="$(bare_head "$LAN3")"
: >"$ERRLOG"
out3="$(run_integrate "$M3" "$B3" "$FAKE")"; rc3=$?
[[ $rc3 -eq 0 ]] || fail "(4) fail-closed integrate exited $rc3 — withholding is not an error path"
[[ "$(bare_head "$LAN3")" == "$LAN3_BEFORE" ]] \
  && pass "(4) FAIL-CLOSED — nothing pushed when no remote can be PROVEN private" \
  || fail "(4) pushed with the predicate library absent — the fallback is auto-publish, the unsafe direction"
grep -q 'WITHHOLDING ALL PUSHES' "$ERRLOG" \
  && pass "(4) the fail-closed withhold is surfaced loudly" \
  || fail "(4) the fail-closed path is silent"

echo "ALL PASS: relay-reconcile.sh per-remote push narrowing (id:4263)"
