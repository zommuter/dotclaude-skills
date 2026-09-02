#!/usr/bin/env bash
# roadmap:7408
#
# RED SPEC (authored by relay handoff C3, not implemented here).
#
# THE GATE DOES NOT BIND. `id:4d44`'s ratification gate is a decision about a UNIT, but
# `git push` is an operation on a REF -- and a push cannot carry commit N+1 while leaving
# commit N behind on the same branch. So once a substantive unit merges to `main`, the
# next push of `main` publishes it whatever the queue says. `integrate.sh` step 8 states
# the mechanism in its own words: "A NON-SUBSTANTIVE unit is UNCHANGED: every remote is
# pushed, as before." Measured 2026-09-02 after run relay-20260902-164744-26939: 17 queue
# entries, 17 already ancestors of the public remote head, 0 genuinely withheld.
#
# The id:99b7 allowlist does NOT cover this. It made UNDECLARED remotes unconditional; a
# DECLARED-public remote still takes the defeated defer path, which is the path here.
#
# Owner ratified option A + D on 2026-09-02 (`docs/ledger-notes/3c04.md`):
#   A -- gate the REMOTE, not the unit: never push a declared-public remote while ANY
#        unresolved queue entry for that repo is an ancestor of HEAD, and SURFACE the
#        withholding loudly rather than only inside `ratify-queue.sh list`.
#   D -- the queue self-verifies: an entry the remote demonstrably carries is reported as
#        landed, not as pending owner action.
# Options B (staging branch) and C (drop the gate) were considered and NOT taken.
#
# WHAT EACH SECTION ASSERTS, against real fixture repos with real bare remotes:
#   (1) CONTROL, green today -- a SUBSTANTIVE unit pushes the private remote, withholds the
#       public one, and lands a pending queue entry. If this ever goes red the fixture is
#       broken, not the item.
#   (2) THE REGRESSION -- a NON-SUBSTANTIVE unit run afterwards must ALSO withhold the
#       public remote, because the deferred substantive merge is an ancestor of HEAD and a
#       push would carry it out. This is how all 17 entries reached the public remote.
#   (3) THE WITHHOLDING IS LOUD -- surfaced in the unit's own output, not only to someone
#       who runs `ratify-queue.sh list`. An unannounced stall is option A's own failure
#       mode: a public mirror that silently goes stale.
#   (4) D, self-verification -- once the owner has pushed, the entry stops being reported
#       as pending owner action in the `--tsv` gather contract, without anyone having run
#       `resolve`. A queue reporting N pending when 0 are actionable is the disease.
#   (5) THE GATE OPENS -- after the entry is resolved, a further non-substantive unit
#       publishes normally. Without this the "fix" could be "never push anything", which
#       would pass (2) and (3) and be worse than the bug.
#
# Hermetic: mktemp repos with LOCAL BARE remotes, a FIXTURE private-host pattern file
# (never the real privacy-patterns.txt -- no real host is named in this public repo),
# GIT_CONFIG_* overrides for hooks/identity. No network, no ~/.claude, no real repo.

set -uo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INT="${INT_OVERRIDE:-$SRC_DIR/relay/scripts/integrate.sh}"
INT_DIR="$(cd "$(dirname "$INT")" && pwd)"
RATIFY="$INT_DIR/ratify-queue.sh"
LOCKPUSH="${GIT_LOCK_PUSH_OVERRIDE:-$SRC_DIR/git-diary-workflow/git-lock-push.sh}"

TMP="$(mktemp -d)"; trap 'rm -rf -- "$TMP"' EXIT
ERRLOG="$TMP/integrate.stderr"; : >"$ERRLOG"
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; [[ -s "$ERRLOG" ]] && { echo "       last integrate.sh stderr:"; tail -n 25 "$ERRLOG" | sed 's/^/       | /'; }; exit 1; }

[[ -x "$INT" ]]    || fail "sanity: integrate.sh not executable at $INT"
[[ -x "$RATIFY" ]] || fail "sanity: ratify-queue.sh not executable at $RATIFY"

export GIT_CONFIG_COUNT=4
export GIT_CONFIG_KEY_0=core.hooksPath     GIT_CONFIG_VALUE_0="$TMP/nohooks"
export GIT_CONFIG_KEY_1=user.email         GIT_CONFIG_VALUE_1=t@e.st
export GIT_CONFIG_KEY_2=user.name          GIT_CONFIG_VALUE_2=t
export GIT_CONFIG_KEY_3=init.defaultBranch GIT_CONFIG_VALUE_3=main
mkdir -p "$TMP/nohooks"

# FIXTURE private-host pattern file: any bare repo path ending `-lan.git` is PRIVATE/LAN.
# Synthetic only -- real host names never appear in a committed file in this public repo.
PATFILE="$TMP/privacy-patterns.txt"
printf '# fixture -- synthetic only\nprivate-host: -lan\\.git$\n' > "$PATFILE"
export PRIVACY_GATE_PATTERNS="$PATFILE"

QUEUE="$TMP/ratification-queue.jsonl"
export RELAY_RATIFICATION_QUEUE="$QUEUE"

PUB="$TMP/o-gate.git"; LAN="$TMP/o-gate-lan.git"
SEED="$TMP/seed";      MAIN="$TMP/main"
git init --bare -b main -q "$PUB"
git init --bare -b main -q "$LAN"
git clone -q "$PUB" "$SEED" 2>/dev/null
cat > "$SEED/ROADMAP.md" <<'MD'
# Roadmap

- [ ] [ROUTINE] the worked item <!-- id:aaaa -->
- [ ] [ROUTINE] a second worked item <!-- id:bbbb -->
- [ ] [ROUTINE] an untouched item <!-- id:cccc -->
MD
echo base > "$SEED/f"
git -C "$SEED" add -A
git -C "$SEED" commit -qm base
git -C "$SEED" push -q -u origin main
git clone -q "$PUB" "$MAIN" 2>/dev/null
git -C "$MAIN" remote add lan "$LAN"
REPO="$(basename "$MAIN")"

CFG="$TMP/cfg"; mkdir -p "$CFG"
printf '[publish]\ndefault_remotes = ["origin"]\n\n[repos.%s]\nstatus = "active"\npublish_remotes = ["lan", "origin"]\n' "$REPO" > "$CFG/relay.toml"

# `--verify -q`, never a bare rev-parse: on a missing ref a bare rev-parse ECHOES ITS
# ARGUMENT and exits 128, so an empty bare repo would capture the refname and never
# compare equal to NONE.
bare_head() { git -C "$1" rev-parse --verify -q refs/heads/main 2>/dev/null || echo NONE; }
key() { awk -F'=' -v k="$2" '$1==k{print substr($0, length(k)+2); exit}' <<<"$1"; }

child() { local name="$1" wt="$TMP/wt-$name"
  git -C "$MAIN" worktree add -q -b "relay/$name" "$wt" main >/dev/null 2>&1
  echo "work-$name" > "$wt/g-$name"; git -C "$wt" add -A; git -C "$wt" commit -qm "child work $name"
  printf '%s' "$wt"; }

# run_unit runs in a COMMAND SUBSTITUTION at every call site, so its exit status cannot
# come back through a shell variable -- it is written to $RCFILE and read by unit_rc.
RCFILE="$TMP/unit.rc"
run_unit() { # <name> <ids> <substantive true|false> -> stdout of integrate.sh
  local name="$1" ids="$2" subs="$3" wt out rc=0
  wt="$(child "$name")"
  out="$(FABLES_CONFIG="$CFG" INTEGRATE_GIT_LOCK_PUSH="$LOCKPUSH" \
        "$INT" --repo "$REPO" --path "$MAIN" --worktree "$wt" --branch "relay/$name" \
               --summary "unit $name" --run "r-$name" \
               --label "executor (claude-sonnet-4-5, relay-loop)" \
               --ids "$ids" --verdict execute --substantive "$subs" 2>"$ERRLOG")" || rc=$?
  printf '%s' "$rc" > "$RCFILE"
  printf '%s' "$out"
}
unit_rc() { cat "$RCFILE"; }

# =====================================================================================
# (1) CONTROL -- a SUBSTANTIVE unit: private pushed, public withheld, entry queued.
# =====================================================================================
PUB_BEFORE="$(bare_head "$PUB")"
out1="$(run_unit sub1 aaaa true)"
[[ "$(unit_rc)" == 0 ]] || fail "(1) substantive integrate exited $(unit_rc) -- a withheld public remote is a SUCCESS path"

HEAD1="$(git -C "$MAIN" rev-parse HEAD)"
[[ "$(bare_head "$LAN")" == "$HEAD1" ]] \
  && pass "(1) control: the PRIVATE remote received the substantive merge" \
  || fail "(1) control: the private remote did not receive the merge (lan=$(bare_head "$LAN") HEAD=$HEAD1)"
[[ "$(bare_head "$PUB")" == "$PUB_BEFORE" ]] \
  && pass "(1) control: the PUBLIC remote is byte-unmoved -- the substantive unit deferred" \
  || fail "(1) control: THE PUBLIC REMOTE MOVED on a substantive unit -- the fixture is not exercising the gate"
[[ "$(key "$out1" ratification)" == pending ]] \
  && pass "(1) control: ratification=pending" \
  || fail "(1) control: expected ratification=pending, got '$(key "$out1" ratification)'"
[[ -s "$QUEUE" ]] \
  && pass "(1) control: a durable queue entry exists" \
  || fail "(1) control: no queue entry was written to $QUEUE"

CK="$(python3 -c 'import json,sys; print(json.loads(open(sys.argv[1]).read().strip().splitlines()[-1])["ckpt"])' "$QUEUE" 2>/dev/null || true)"
MERGED="$(python3 -c 'import json,sys; print(json.loads(open(sys.argv[1]).read().strip().splitlines()[-1])["merged"])' "$QUEUE" 2>/dev/null || true)"
[[ -n "$CK" && -n "$MERGED" ]] \
  && pass "(1) control: the entry records ckpt=$CK merged=${MERGED:0:12}" \
  || fail "(1) control: could not read ckpt/merged out of the queue entry: $(cat "$QUEUE")"
git -C "$MAIN" merge-base --is-ancestor "$MERGED" HEAD \
  && pass "(1) control: the unresolved merge IS an ancestor of HEAD -- the trap is armed" \
  || fail "(1) control: the recorded merge is not an ancestor of HEAD; the fixture cannot express the regression"

# =====================================================================================
# (2) THE REGRESSION -- a NON-SUBSTANTIVE unit must NOT carry the deferred merge out.
# =====================================================================================
PUB_BEFORE2="$(bare_head "$PUB")"
out2="$(run_unit nonsub1 cccc false)"
PUB_AFTER2="$(bare_head "$PUB")"

[[ "$PUB_AFTER2" == "$PUB_BEFORE2" ]] \
  && pass "(2) a NON-SUBSTANTIVE unit did NOT advance the public remote while an unresolved entry is ancestral to HEAD" \
  || fail "(2) THE PUBLIC REMOTE ADVANCED on a NON-SUBSTANTIVE unit ($PUB_BEFORE2 -> $PUB_AFTER2) while queue entry $CK (merged ${MERGED:0:12}) is unresolved and ancestral to HEAD -- the gate is per-UNIT applied to a per-BRANCH push, so it carried the deferred substantive work out. This is how 17 of 17 entries reached the public remote."

git -C "$MAIN" merge-base --is-ancestor "$MERGED" "$PUB_AFTER2" 2>/dev/null \
  && fail "(2) the unratified merge ${MERGED:0:12} IS NOW AN ANCESTOR of the public remote head -- it was published without owner ratification" \
  || pass "(2) the unratified merge is still absent from the public remote"

HEAD2="$(git -C "$MAIN" rev-parse HEAD)"
[[ "$(bare_head "$LAN")" == "$HEAD2" ]] \
  && pass "(2) the PRIVATE remote still receives the non-substantive unit -- the gate narrows publication, not all pushing" \
  || fail "(2) the private remote did not receive the non-substantive unit (lan=$(bare_head "$LAN") HEAD=$HEAD2) -- withholding must be scoped to declared-PUBLIC remotes"

# =====================================================================================
# (3) THE WITHHOLDING IS LOUD -- in the unit's own output, not only in `ratify-queue list`.
# =====================================================================================
if grep -qE '^pushRemote=origin:' <<<"$out2"; then
  st="$(grep -m1 -E '^pushRemote=origin:' <<<"$out2" | cut -d: -f2-)"
  [[ "$st" != pushed ]] \
    && pass "(3) the public remote is reported withheld (pushRemote=origin:$st), not pushed" \
    || fail "(3) the public remote is reported 'pushed' on a unit that must have withheld it"
else
  fail "(3) no per-remote line for origin in the non-substantive unit's output -- the withholding is invisible to the run:"$'\n'"$out2"
fi
grep -qiE 'ratif' <<<"$out2$(cat "$ERRLOG")" \
  && pass "(3) the run names ratification as the reason it withheld" \
  || fail "(3) neither stdout nor stderr mentions ratification -- an unannounced stall is how a public mirror silently goes stale"

# =====================================================================================
# (4) D -- SELF-VERIFYING QUEUE. The owner pushes; the entry stops being actionable.
# =====================================================================================
git -C "$MAIN" push -q --follow-tags origin HEAD:main 2>>"$ERRLOG" \
  || fail "(4) fixture: the simulated owner push to origin failed"
git -C "$MAIN" merge-base --is-ancestor "$MERGED" "$(bare_head "$PUB")" \
  || fail "(4) fixture: after the owner push the merge is still not on the public remote"

tsv="$(RELAY_RATIFICATION_QUEUE="$QUEUE" "$RATIFY" list --tsv 2>/dev/null || true)"
grep -q . <<<"$tsv" && rows=1 || rows=0
(( rows == 0 )) \
  && pass "(4) the queue no longer reports an entry the remote demonstrably carries" \
  || fail "(4) the queue still reports $(grep -c . <<<"$tsv") pending entr(y|ies) the public remote already carries -- 'pending' reads as 'not yet public' and someone will act on that belief:"$'\n'"$tsv"

# =====================================================================================
# (5) THE GATE OPENS -- resolve, then a further unit publishes normally.
# =====================================================================================
RELAY_RATIFICATION_QUEUE="$QUEUE" "$RATIFY" resolve "$CK" --remote origin --note "fixture" >/dev/null 2>>"$ERRLOG" \
  || fail "(5) resolve refused an entry the remote demonstrably carries (ckpt=$CK)"

PUB_BEFORE3="$(bare_head "$PUB")"
out3="$(run_unit nonsub2 cccc false)"
PUB_AFTER3="$(bare_head "$PUB")"
[[ "$PUB_AFTER3" != "$PUB_BEFORE3" ]] \
  && pass "(5) with nothing unresolved, the public remote advances again -- the gate opens" \
  || fail "(5) the public remote did NOT advance after every entry was resolved -- 'never push' is not a fix, it is a worse bug"

echo "ALL PASS"
