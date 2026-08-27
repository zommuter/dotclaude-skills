#!/usr/bin/env bash
# NO `# roadmap:` header ON PURPOSE — id:5155 / id:a726 are DEFECT FIXES found by adversarial
# review, not ROADMAP items, so per tests/run-tests.sh's convention these failures ALWAYS
# count (they are never EXPECTED-RED).
#
# id:5155 — A MERGE THAT REACHED ZERO REMOTES MUST NOT REPORT `ratification=none`.
#
#   Observed on a real run: a SUBSTANTIVE unit past the land point whose only remote push
#   silently did nothing reported
#       exit=27 handback=git-lock-push push=FAILED ratification=none
#   with the merge on main, the ckpt tag present, ZERO remotes carrying it, and NO
#   ratification-queue entry ever written. integrate.sh's own stdout contract defines
#   `ratification=none` as "every eligible remote carries the merge" — here it meant the
#   exact opposite, and the durable record that would have told the owner the merge exists
#   was never created.
#
#   TWO independent causes, both specced here:
#     (a) the `push_failures` handback fired BEFORE step 8b, pre-empting the enqueue;
#     (b) `FAILED` was absent from step 8b's `deferred|no-upstream|partial` gate anyway.
#
# Also specced (id:a726):
#     (a) the push-failure handback must report `landed=true` — the merge and the ckpt tag
#         ARE committed, so relay-loop.js must classify it LANDED-BUT-UNFINISHED, never
#         `deferred:true` / "Retry is correct.";
#     (b) `remaining=` must have a real arm for the `git-lock-push` step instead of
#         degrading to "UNKNOWN post-land step".
#
# CONTRACT UNDER TEST
#   A landed merge that no remote carries MUST produce a ratification-queue entry and MUST
#   NOT report `ratification=none`. `ratification=none` appears ONLY when every eligible
#   remote demonstrably carries the merge.
#
# Hermetic: mktemp repos with LOCAL BARE remotes, a FIXTURE private-host pattern file
# (never the real ~/.config/dotclaude-skills/privacy-patterns.txt), GIT_CONFIG_COUNT to
# neutralise a global core.hooksPath. No network, no real repos, no ~/.claude.
set -uo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INT="${INT_OVERRIDE:-$SRC_DIR/relay/scripts/integrate.sh}"
LOCKPUSH="${GIT_LOCK_PUSH_OVERRIDE:-$SRC_DIR/git-diary-workflow/git-lock-push.sh}"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$INT" ]] || fail "integrate.sh not found/executable at $INT"

export GIT_CONFIG_COUNT=4
export GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0="$TMP/nohooks"
export GIT_CONFIG_KEY_1=user.email     GIT_CONFIG_VALUE_1=t@e.st
export GIT_CONFIG_KEY_2=user.name      GIT_CONFIG_VALUE_2=t
export GIT_CONFIG_KEY_3=init.defaultBranch GIT_CONFIG_VALUE_3=main
mkdir -p "$TMP/nohooks"

# FIXTURE private-host pattern file: any bare remote whose path ends `-lan.git` is PRIVATE.
# Synthetic only — a real host never appears in a committed file.
PATFILE="$TMP/privacy-patterns.txt"
printf '# fixture — synthetic only\nprivate-host: -lan\\.git$\n' > "$PATFILE"
export PRIVACY_GATE_PATTERNS="$PATFILE"

cat > "$TMP/rm.md" <<'EOF'
# Roadmap

- [ ] [ROUTINE] the worked item <!-- id:aaaa -->
- [ ] [ROUTINE] an untouched item <!-- id:bbbb -->
EOF

# build <suffix> → a checkout whose ONLY remote is the private/LAN bare repo `lan`.
# The LAN bare is deliberately left EMPTY, so `ls-remote` finds nothing unless a push really
# happened — that is what makes the verification a real check and not a tautology.
build_lanonly() {
  # SEPARATE `local` statements on purpose: bash marks every name in ONE `local` local
  # BEFORE assigning, so `local sfx="$1" lan="…$sfx…"` reads the CALLER's sfx (or nothing).
  local sfx="$1"
  local lan="$TMP/o-$sfx-lan.git" seed="$TMP/s-$sfx" main="$TMP/m-$sfx" hold="$TMP/h-$sfx.git"
  git init --bare -b main -q "$hold"
  git init --bare -b main -q "$lan"
  git clone -q "$hold" "$seed" 2>/dev/null
  echo base > "$seed/f"
  cp "$TMP/rm.md" "$seed/ROADMAP.md"
  git -C "$seed" add -A
  git -C "$seed" commit -qm base
  git -C "$seed" push -q -u origin main
  git clone -q "$hold" "$main" 2>/dev/null
  git -C "$main" remote remove origin
  git -C "$main" remote add lan "$lan"
  printf '%s' "$main"
}
child() { local main="$1" name="$2"; local wt="$TMP/wt-$name"
  git -C "$main" worktree add -q -b "relay/$name" "$wt" main
  echo "work-$name" > "$wt/g-$name"; git -C "$wt" add -A; git -C "$wt" commit -qm "child work $name"
  printf '%s' "$wt"; }
# id:99b7 — this fixture's ONLY remote is `lan` (it deliberately removes `origin`), so it must
# be DECLARED in the do-publish allowlist or it classifies as UNDECLARED: never pushed, hence
# never FAILED, and the failed-push ratification path this file specs would be unreachable.
cfg() { local d="$TMP/cfg-$1"; mkdir -p "$d"
  printf '[publish]\ndefault_remotes = ["origin"]\n\n[repos.%s]\nstatus = "active"\npublish_remotes = ["lan"]\n' "$2" > "$d/relay.toml"; printf '%s' "$d"; }
bare_head() { git -C "$1" rev-parse --verify -q refs/heads/main 2>/dev/null || echo NONE; }
key() { awk -F'=' -v k="$2" '$1==k{print substr($0, length(k)+2); exit}' <<<"$1"; }

# run_failed_push <suffix> <push-helper> → sets RC/ERR/OUT/QUEUE globals
RC=0; ERR=""; OUT=""; QUEUE=""
run_failed_push() {
  local sfx="$1" helper="$2" subst="${3:-true}"
  local main; main="$(build_lanonly "$sfx")"
  local repo; repo="$(basename "$main")"
  local wt; wt="$(child "$main" "$sfx")"
  local c; c="$(cfg "$sfx" "$repo")"
  ERR="$TMP/err-$sfx"; QUEUE="$c/ratification-queue.jsonl"
  RC=0
  OUT="$(FABLES_CONFIG="$c" INTEGRATE_GIT_LOCK_PUSH="$helper" \
    "$INT" --repo "$repo" --path "$main" --worktree "$wt" --branch "relay/$sfx" \
           --summary "close aaaa" --run "r-$sfx" \
           --label "executor (claude-sonnet-4-5, relay-loop)" \
           --ids aaaa --verdict execute --substantive "$subst" 2>"$ERR")" || RC=$?
  LAN_BARE="$TMP/o-$sfx-lan.git"
}

# =====================================================================================
# (1) THE HIGH FIX — a substantive unit whose ONLY remote push FAILS.
#     A "liar" helper: exits 0 having pushed NOTHING (the live id:dc4f/id:f5d9 defect).
# =====================================================================================
LIAR="$TMP/push-liar.sh"; printf '#!/usr/bin/env bash\nexit 0\n' > "$LIAR"; chmod +x "$LIAR"
run_failed_push liar "$LIAR"

[[ "$(bare_head "$LAN_BARE")" == NONE ]] \
  && pass "(1) the fixture is honest — the remote really is unmoved" \
  || fail "(1) the remote moved; the liar helper fixture is wrong"

# id:2c2a — the HANDBACK discriminator is `handback=<step>` on STDOUT, no longer the exit
# code (a reached-and-executed refusal exits 0). The substance is unchanged: an unverifiable
# push must NOT be reported as a plain success.
grep -qx 'handback=git-lock-push' <<<"$OUT" \
  && pass "(1) an unverifiable push is still a HANDBACK (handback=git-lock-push, rc=$RC), not a success" \
  || fail "(1) the liar push was accepted (no handback= on stdout): $OUT"
[[ $RC -eq 0 ]] \
  && pass "(1/2c2a) …and it exits 0 — a correct refusal is the mechanism working, not a MECH-ERROR" \
  || fail "(1/2c2a) the refusal exited $RC; id:2c2a reserves non-zero for UNDETERMINABLE outcomes"

[[ -s "$QUEUE" ]] \
  && pass "(1) id:5155 A RATIFICATION-QUEUE ENTRY EXISTS for the landed-but-unpublished merge" \
  || fail "(1) id:5155 NO queue entry was written — the merge is on main, tagged, on ZERO remotes, and nothing durable records it"

grep -q '"status": "pending"' "$QUEUE" \
  && pass "(1) the queue entry is status=pending" \
  || fail "(1) the queue entry is not pending: $(cat "$QUEUE")"

grep -q 'ratification=pending' "$ERR" \
  && pass "(1) id:5155 the handback reports ratification=pending" \
  || fail "(1) id:5155 no ratification=pending in the handback: $(tr '\n' ' ' <"$ERR" | cut -c1-500)"

grep -q 'ratification=none' "$ERR" \
  && fail "(1) id:5155 THE DEFECT IS LIVE — ratification=none reported while ZERO remotes carry the merge: $(tr '\n' ' ' <"$ERR" | cut -c1-500)" \
  || pass "(1) id:5155 ratification=none is NOT reported (zero remotes carry the merge)"

grep -q 'push=FAILED' "$ERR" \
  && pass "(1) the handback still reports push=FAILED" \
  || fail "(1) no push=FAILED in the handback: $(tr '\n' ' ' <"$ERR" | cut -c1-500)"

python3 - "$QUEUE" <<'PY' && pass "(1) the queue entry NAMES the remote that did not receive the merge (pending_remotes=[lan])" || fail "(1) pending_remotes does not name the failed remote"
import json, sys
rec = json.loads(open(sys.argv[1]).read().strip().splitlines()[-1])
sys.exit(0 if rec.get("pending_remotes") == ["lan"] and rec.get("push") == "FAILED" else 1)
PY

# ── id:a726(a): the handback must say landed=true ────────────────────────────────────
grep -q '^landed=true$' "$ERR" \
  && pass "(1/a726a) the handback reports landed=true — merge + ckpt tag exist, so a retry is WRONG" \
  || fail "(1/a726a) landed is not true: $(tr '\n' ' ' <"$ERR" | cut -c1-500)"

# ── id:a726(b): `remaining=` must have a real git-lock-push arm ──────────────────────
if grep -q 'remaining=.*UNKNOWN post-land step' "$ERR"; then
  fail "(1/a726b) remaining= degraded to 'UNKNOWN post-land step' for the git-lock-push step"
else
  pass "(1/a726b) remaining= is NOT 'UNKNOWN post-land step'"
fi
grep -qE '^remaining=.*worktree-retire,state-write,strong-state,push-seed' "$ERR" \
  && pass "(1/a726b) remaining= enumerates the real unrun tail steps" \
  || fail "(1/a726b) remaining= does not enumerate the tail steps: $(grep '^remaining=' "$ERR" || echo '<none>')"
grep -qE '^remaining=.*ratification-enqueue' "$ERR" \
  && fail "(1/a726b) remaining= claims ratification-enqueue did not run — it ran BEFORE this handback (id:5155)" \
  || pass "(1/a726b) remaining= does not claim the (already-completed) ratification-enqueue is unrun"

# =====================================================================================
# (2) SECOND CAUSE, INDEPENDENTLY — the helper exits NON-ZERO (an unreachable LAN origin,
#     an expired SSH key). The pre-fix code handed back from inside step 8 and never even
#     reached the verification loop, let alone the enqueue.
# =====================================================================================
HARDFAIL="$TMP/push-hardfail.sh"
printf '#!/usr/bin/env bash\necho "fatal: could not read from remote repository" >&2\nexit 128\n' > "$HARDFAIL"
chmod +x "$HARDFAIL"
run_failed_push hardfail "$HARDFAIL"

grep -qx 'handback=git-lock-push' <<<"$OUT" \
  && pass "(2) a non-zero push helper is a HANDBACK (handback=git-lock-push; id:2c2a rc=$RC)" \
  || fail "(2) a non-zero push helper was accepted: $OUT"
[[ -s "$QUEUE" ]] \
  && pass "(2) id:5155 a queue entry EXISTS even when the helper itself failed" \
  || fail "(2) id:5155 NO queue entry — the handback pre-empted step 8b again"
grep -q 'ratification=pending' "$ERR" \
  && pass "(2) id:5155 ratification=pending on the helper-failure path" \
  || fail "(2) id:5155 no ratification=pending: $(tr '\n' ' ' <"$ERR" | cut -c1-500)"
grep -q 'ratification=none' "$ERR" \
  && fail "(2) id:5155 ratification=none reported while ZERO remotes carry the merge" \
  || pass "(2) id:5155 ratification=none is NOT reported"
grep -q '^landed=true$' "$ERR" \
  && pass "(2/a726a) landed=true on the helper-failure path too" \
  || fail "(2/a726a) landed is not true: $(tr '\n' ' ' <"$ERR" | cut -c1-500)"

# =====================================================================================
# (3) THE OTHER HALF OF THE CONTRACT — `ratification=none` appears ONLY when every
#     eligible remote demonstrably carries the merge. Same shape as (1)/(2) but with the
#     REAL push helper, so the private/LAN remote genuinely receives it.
# =====================================================================================
M3="$(build_lanonly ok)"; R3="$(basename "$M3")"; W3="$(child "$M3" ok)"; C3="$(cfg ok "$R3")"
rc3=0
out3="$(FABLES_CONFIG="$C3" INTEGRATE_GIT_LOCK_PUSH="$LOCKPUSH" \
  "$INT" --repo "$R3" --path "$M3" --worktree "$W3" --branch relay/ok \
         --summary "close aaaa" --run r-ok --label "executor (claude-sonnet-4-5, relay-loop)" \
         --ids aaaa --verdict execute --substantive true 2>"$TMP/err-ok")" || rc3=$?
[[ $rc3 -eq 0 ]] || fail "(3) the all-private substantive integrate exited $rc3: $(tr '\n' ' ' <"$TMP/err-ok" | cut -c1-500)"

HEAD3="$(git -C "$M3" rev-parse HEAD)"
[[ "$(bare_head "$TMP/o-ok-lan.git")" == "$HEAD3" ]] \
  && pass "(3) the eligible remote DEMONSTRABLY carries the merge" \
  || fail "(3) the remote does not carry the merge — the fixture is wrong"
[[ "$(key "$out3" push)" == pushed ]] \
  && pass "(3) push=pushed" \
  || fail "(3) expected push=pushed, got '$(key "$out3" push)'"
[[ "$(key "$out3" ratification)" == none ]] \
  && pass "(3) ratification=none — and ONLY here, where every eligible remote carries the merge" \
  || fail "(3) expected ratification=none, got '$(key "$out3" ratification)'"
[[ ! -s "$C3/ratification-queue.jsonl" ]] \
  && pass "(3) no queue entry when nothing awaits the owner" \
  || fail "(3) a queue entry was written though nothing is pending: $(cat "$C3/ratification-queue.jsonl")"

# =====================================================================================
# (4) id:a726(a) IN ITS OWN RIGHT — a NON-SUBSTANTIVE unit whose push FAILS.
#     A substantive unit already had `landed=1` (it was set on the defer_push branch), so
#     the missing-land-marker defect only shows here: `landed` was set at exactly three
#     places, ALL of them missed on this path, so integrate.sh handed back landed=false and
#     relay-loop.js classified a merge that is ALREADY on main and ALREADY tagged as
#     `deferred:true` — "Retry is correct." It is not.
# =====================================================================================
run_failed_push nonsub "$LIAR" false

grep -qx 'handback=git-lock-push' <<<"$OUT" \
  && pass "(4) the non-substantive failed push is a HANDBACK (handback=git-lock-push; id:2c2a rc=$RC)" \
  || fail "(4) the non-substantive liar push was accepted: $OUT"
grep -q '^landed=true$' "$ERR" \
  && pass "(4/a726a) id:a726(a) landed=true for a NON-SUBSTANTIVE unit — the ckpt tag is the land point for EVERY unit" \
  || fail "(4/a726a) id:a726(a) landed is NOT true — a merge already on main and already tagged is reported as a retryable defer: $(tr '\n' ' ' <"$ERR" | cut -c1-500)"
[[ -s "$QUEUE" ]] \
  && pass "(4) id:5155 a non-substantive landed-but-unpublished merge is queued too" \
  || fail "(4) id:5155 NO queue entry for the non-substantive failed push"
grep -q 'ratification=pending' "$ERR" \
  && pass "(4) id:5155 ratification=pending" \
  || fail "(4) id:5155 no ratification=pending: $(tr '\n' ' ' <"$ERR" | cut -c1-500)"

echo "ALL PASS: id:5155 (+ id:a726 a/b) — a landed merge on ZERO remotes is QUEUED and reports ratification=pending"
