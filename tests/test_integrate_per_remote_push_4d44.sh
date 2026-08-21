#!/usr/bin/env bash
# roadmap:4d44 — integrate.sh PER-REMOTE push narrowing.
#
# Spec (owner decision):
#   A SUBSTANTIVE unit pushes the PRIVATE/LAN remotes AUTOMATICALLY and DEFERS only the
#   non-local/public ones. A NON-SUBSTANTIVE unit is unchanged (pushes everything).
#
#   (1) MIXED — the private remote receives the merge, the public one does NOT;
#       stdout reports push=partial with per-remote `pushRemote=` lines and
#       pushPending=<public remote>; ratification=pending.
#   (2) The ratification-queue record NAMES the pending remote (`pending_remotes`) and the
#       already-pushed one (`pushed_remotes`), and ratify-queue.sh surfaces it.
#   (3) FALSE-RESOLVE GUARD — with the PRIVATE remote already carrying the merge,
#       `ratify-queue.sh resolve` must still REFUSE, because the pending PUBLIC remote does
#       not. (The pre-id:4d44 check verified one default remote and would have resolved.)
#   (4) NON-SUBSTANTIVE — both remotes are pushed, push=pushed, ratification=none.
#   (5) ALL-PRIVATE SUBSTANTIVE — everything is pushed, so nothing awaits the owner:
#       push=pushed, ratification=none, NO queue entry. This is the ratification= semantic
#       in the mixed world: `none` ⇔ every eligible remote carries the merge.
#   (6) PER-REMOTE VERIFICATION — a push helper that exits 0 having pushed NOTHING
#       (the live id:dc4f/id:f5d9 defect) is reported FAILED for that remote and handed back,
#       never as success.
#
# Hermetic: mktemp repos with LOCAL BARE remotes, a FIXTURE private-host pattern file
# (never the real ~/.config/dotclaude-skills/privacy-patterns.txt), GIT_CONFIG_COUNT to
# neutralise a global core.hooksPath. No network, no real repos, no ~/.claude.
set -uo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INT="${INT_OVERRIDE:-$SRC_DIR/relay/scripts/integrate.sh}"
INT_DIR="$(cd "$(dirname "$INT")" && pwd)"
RATIFY="$INT_DIR/ratify-queue.sh"
LOCKPUSH="${GIT_LOCK_PUSH_OVERRIDE:-$SRC_DIR/git-diary-workflow/git-lock-push.sh}"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
ERRLOG="$TMP/integrate.stderr"; : >"$ERRLOG"
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; [[ -s "$ERRLOG" ]] && { echo "       last integrate.sh stderr:"; tail -n 25 "$ERRLOG" | sed 's/^/       | /'; }; exit 1; }

[[ -x "$INT" ]] || fail "integrate.sh not found/executable at $INT"

export GIT_CONFIG_COUNT=4
export GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0="$TMP/nohooks"
export GIT_CONFIG_KEY_1=user.email     GIT_CONFIG_VALUE_1=t@e.st
export GIT_CONFIG_KEY_2=user.name      GIT_CONFIG_VALUE_2=t
export GIT_CONFIG_KEY_3=init.defaultBranch GIT_CONFIG_VALUE_3=main
mkdir -p "$TMP/nohooks"

# ── FIXTURE private-host pattern file. The synthetic ERE marks any bare remote whose path
#    ends in `-lan.git` as a PRIVATE/LAN host. Real hosts never appear in a committed file.
PATFILE="$TMP/privacy-patterns.txt"
cat > "$PATFILE" <<'EOF'
# fixture — synthetic only
private-host: -lan\.git$
EOF
export PRIVACY_GATE_PATTERNS="$PATFILE"

cat > "$TMP/rm.md" <<'EOF'
# Roadmap

- [ ] [ROUTINE] the worked item <!-- id:aaaa -->
- [ ] [ROUTINE] an untouched item <!-- id:bbbb -->
EOF

# build <suffix> <extra-remote-kind: lan|none|lanonly> → prints the main checkout path
build() {
  local sfx="$1" kind="$2"
  local pub="$TMP/o-$sfx.git" lan="$TMP/o-$sfx-lan.git" seed="$TMP/s-$sfx" main="$TMP/m-$sfx"
  git init --bare -b main -q "$pub"
  git init --bare -b main -q "$lan"
  git clone -q "$pub" "$seed" 2>/dev/null
  echo base > "$seed/f"
  cp "$TMP/rm.md" "$seed/ROADMAP.md"
  git -C "$seed" add -A
  git -C "$seed" commit -qm base
  git -C "$seed" push -q -u origin main
  git clone -q "$pub" "$main" 2>/dev/null
  case "$kind" in
    lan)     git -C "$main" remote add lan "$lan" ;;
    lanonly) git -C "$main" remote remove origin; git -C "$main" remote add lan "$lan"
             git -C "$main" push -q -u lan main ;;
  esac
  printf '%s' "$main"
}
child() { local main="$1" name="$2"; local wt="$TMP/wt-$name"
  git -C "$main" worktree add -q -b "relay/$name" "$wt" main
  echo "work-$name" > "$wt/g-$name"; git -C "$wt" add -A; git -C "$wt" commit -qm "child work $name"
  printf '%s' "$wt"; }
cfg() { local d="$TMP/cfg-$1"; mkdir -p "$d"
  printf '[repos.%s]\nstatus = "active"\n' "$2" > "$d/relay.toml"; printf '%s' "$d"; }
# --verify -q, NOT a bare rev-parse: on a ref that does not exist a bare `git rev-parse
# refs/heads/main` ECHOES ITS ARGUMENT and exits 128, so the "empty bare repo" case would
# capture "refs/heads/main" and silently never compare equal to NONE.
bare_head() { git -C "$1" rev-parse --verify -q refs/heads/main 2>/dev/null || echo NONE; }
key() { awk -F'=' -v k="$2" '$1==k{print substr($0, length(k)+2); exit}' <<<"$1"; }

# =====================================================================================
# (1)(2)(3) MIXED: private `lan` pushed, public `origin` deferred
# =====================================================================================
M1="$(build mix lan)"; R1="$(basename "$M1")"; PUB1="$TMP/o-mix.git"; LAN1="$TMP/o-mix-lan.git"
W1="$(child "$M1" mix)"; C1="$(cfg mix "$R1")"
PUB_BEFORE="$(bare_head "$PUB1")"
rc=0
out1="$(FABLES_CONFIG="$C1" INTEGRATE_GIT_LOCK_PUSH="$LOCKPUSH" \
  "$INT" --repo "$R1" --path "$M1" --worktree "$W1" --branch relay/mix \
         --summary "close aaaa" --run r1 --label "executor (claude-sonnet-4-5, relay-loop)" \
         --ids aaaa --verdict execute --substantive true 2>"$ERRLOG")" || rc=$?
[[ $rc -eq 0 ]] || fail "(1) mixed substantive integrate exited $rc — a partial push is a SUCCESS path"

HEAD1="$(git -C "$M1" rev-parse HEAD)"
[[ "$(bare_head "$LAN1")" == "$HEAD1" ]] \
  && pass "(1) the PRIVATE/LAN remote received the merge automatically" \
  || fail "(1) the private remote did NOT receive the merge (lan=$(bare_head "$LAN1") HEAD=$HEAD1)"
[[ "$(bare_head "$PUB1")" == "$PUB_BEFORE" ]] \
  && pass "(1) the PUBLIC remote is byte-unmoved — publication still needs owner ratification" \
  || fail "(1) THE PUBLIC REMOTE MOVED — substantive agent work was auto-published"

[[ "$(key "$out1" push)" == partial ]] \
  && pass "(1) stdout aggregate push=partial" \
  || fail "(1) expected push=partial, got '$(key "$out1" push)'"
grep -qx 'pushRemote=lan:pushed' <<<"$out1" \
  && pass "(1) per-remote line: pushRemote=lan:pushed" \
  || fail "(1) missing 'pushRemote=lan:pushed': $(grep '^pushRemote=' <<<"$out1" | tr '\n' ' ')"
grep -qx 'pushRemote=origin:deferred' <<<"$out1" \
  && pass "(1) per-remote line: pushRemote=origin:deferred" \
  || fail "(1) missing 'pushRemote=origin:deferred': $(grep '^pushRemote=' <<<"$out1" | tr '\n' ' ')"
[[ "$(key "$out1" pushPending)" == origin ]] \
  && pass "(1) pushPending names the deferred remote" \
  || fail "(1) pushPending='$(key "$out1" pushPending)', expected 'origin'"
[[ "$(key "$out1" ratification)" == pending ]] \
  && pass "(1) ratification=pending — a remote still lacks the merge" \
  || fail "(1) ratification='$(key "$out1" ratification)', expected pending"

Q1="$C1/ratification-queue.jsonl"
[[ -s "$Q1" ]] || fail "(2) no ratification queue entry at $Q1"
python3 - "$Q1" <<'PYEOF' || fail "(2) the queue record does not name the pending/pushed remotes (see above)"
import json, sys
rec = json.loads(open(sys.argv[1]).read().strip().splitlines()[-1])
bad = []
if rec.get("pending_remotes") != ["origin"]:
    bad.append("pending_remotes=%r, expected ['origin']" % (rec.get("pending_remotes"),))
if rec.get("pushed_remotes") != ["lan"]:
    bad.append("pushed_remotes=%r, expected ['lan']" % (rec.get("pushed_remotes"),))
if rec.get("push") != "partial":
    bad.append("push=%r, expected 'partial'" % (rec.get("push"),))
if "origin" not in (rec.get("action") or ""):
    bad.append("action does not name the pending remote: %r" % (rec.get("action"),))
if bad:
    print("  " + "; ".join(bad), file=sys.stderr)
    raise SystemExit(1)
PYEOF
pass "(2) the queue record names pending_remotes=[origin] and pushed_remotes=[lan]"

if [[ -x "$RATIFY" ]]; then
  shown="$(RELAY_RATIFICATION_QUEUE="$Q1" "$RATIFY" show "$(key "$out1" ckpt)" 2>&1)"
  grep -q 'pending   origin' <<<"$shown" \
    && pass "(2) ratify-queue.sh show names the pending remote" \
    || fail "(2) ratify-queue.sh show does not name the pending remote: $shown"
  # (3) THE FALSE-RESOLVE GUARD. `lan` (already pushed) carries the merge; `origin` does not.
  rrc=0
  rout="$(RELAY_RATIFICATION_QUEUE="$Q1" "$RATIFY" resolve "$(key "$out1" ckpt)" 2>&1)" || rrc=$?
  if [[ $rrc -ne 0 ]]; then
    pass "(3) resolve REFUSES while the pending PUBLIC remote lacks the merge (rc=$rrc) — no false resolve"
  else
    fail "(3) resolve SUCCEEDED though origin never received the merge — it verified the already-pushed private remote: $rout"
  fi
  grep -q 'pending' <<<"$(RELAY_RATIFICATION_QUEUE="$Q1" "$RATIFY" list 2>&1)" \
    && pass "(3) the entry is still PENDING after the refused resolve" \
    || fail "(3) the entry left the pending list despite the refusal"
else
  fail "(2/3) ratify-queue.sh not executable at $RATIFY"
fi

# =====================================================================================
# (4) NON-SUBSTANTIVE — unchanged: every remote is pushed
# =====================================================================================
M2="$(build non lan)"; R2="$(basename "$M2")"; PUB2="$TMP/o-non.git"; LAN2="$TMP/o-non-lan.git"
W2="$(child "$M2" non)"; C2="$(cfg non "$R2")"
rc=0
out2="$(FABLES_CONFIG="$C2" INTEGRATE_GIT_LOCK_PUSH="$LOCKPUSH" \
  "$INT" --repo "$R2" --path "$M2" --worktree "$W2" --branch relay/non \
         --summary "close aaaa" --run r2 --label "executor (claude-sonnet-4-5, relay-loop)" \
         --ids aaaa --verdict execute --substantive false 2>"$ERRLOG")" || rc=$?
[[ $rc -eq 0 ]] || fail "(4) non-substantive integrate exited $rc"
HEAD2="$(git -C "$M2" rev-parse HEAD)"
if [[ "$(bare_head "$PUB2")" == "$HEAD2" && "$(bare_head "$LAN2")" == "$HEAD2" ]]; then
  pass "(4) a NON-substantive unit still pushes EVERY remote (unchanged)"
else
  fail "(4) a non-substantive unit did not push all remotes (pub=$(bare_head "$PUB2") lan=$(bare_head "$LAN2") HEAD=$HEAD2)"
fi
[[ "$(key "$out2" push)" == pushed ]] \
  && pass "(4) push=pushed for the non-substantive unit" \
  || fail "(4) push='$(key "$out2" push)', expected pushed"
[[ "$(key "$out2" ratification)" == none ]] \
  && pass "(4) ratification=none for the non-substantive unit" \
  || fail "(4) ratification='$(key "$out2" ratification)', expected none"

# =====================================================================================
# (5) ALL-PRIVATE SUBSTANTIVE — everything published to the LAN ⇒ nothing awaits the owner
# =====================================================================================
M3="$(build priv lanonly)"; R3="$(basename "$M3")"; LAN3="$TMP/o-priv-lan.git"
W3="$(child "$M3" priv)"; C3="$(cfg priv "$R3")"
rc=0
out3="$(FABLES_CONFIG="$C3" INTEGRATE_GIT_LOCK_PUSH="$LOCKPUSH" \
  "$INT" --repo "$R3" --path "$M3" --worktree "$W3" --branch relay/priv \
         --summary "close aaaa" --run r3 --label "executor (claude-sonnet-4-5, relay-loop)" \
         --ids aaaa --verdict execute --substantive true 2>"$ERRLOG")" || rc=$?
[[ $rc -eq 0 ]] || fail "(5) all-private substantive integrate exited $rc"
HEAD3="$(git -C "$M3" rev-parse HEAD)"
[[ "$(bare_head "$LAN3")" == "$HEAD3" ]] \
  && pass "(5) the only (private) remote received the merge" \
  || fail "(5) the private remote did not receive the merge"
[[ "$(key "$out3" push)" == pushed ]] \
  && pass "(5) push=pushed — every eligible remote carries it" \
  || fail "(5) push='$(key "$out3" push)', expected pushed"
[[ "$(key "$out3" ratification)" == none ]] \
  && pass "(5) ratification=none — nothing was withheld, so nothing awaits the owner" \
  || fail "(5) ratification='$(key "$out3" ratification)', expected none (the mixed-case semantic: none ⇔ EVERY eligible remote carries the merge)"
[[ ! -s "$C3/ratification-queue.jsonl" ]] \
  && pass "(5) no ratification queue entry was written" \
  || fail "(5) a queue entry was written though nothing is pending: $(cat "$C3/ratification-queue.jsonl")"

# =====================================================================================
# (6) PER-REMOTE VERIFICATION — the id:dc4f liar (exit 0, pushed nothing) is caught
# =====================================================================================
LIAR="$TMP/push-liar.sh"; printf '#!/usr/bin/env bash\nexit 0\n' > "$LIAR"; chmod +x "$LIAR"
M4="$(build liar lan)"; R4="$(basename "$M4")"; LAN4="$TMP/o-liar-lan.git"
W4="$(child "$M4" liar)"; C4="$(cfg liar "$R4")"
rc=0
out4="$(FABLES_CONFIG="$C4" INTEGRATE_GIT_LOCK_PUSH="$LIAR" \
  "$INT" --repo "$R4" --path "$M4" --worktree "$W4" --branch relay/liar \
         --summary "close aaaa" --run r4 --label "executor (claude-sonnet-4-5, relay-loop)" \
         --ids aaaa --verdict execute --substantive true 2>"$TMP/err4")" || rc=$?
if [[ $rc -ne 0 ]]; then
  pass "(6) a push helper that exits 0 having pushed NOTHING is a HANDBACK (rc=$rc), not a success"
else
  fail "(6) the liar push was accepted (rc=0): $out4"
fi
grep -q 'push=FAILED' "$TMP/err4" \
  && pass "(6) the handback reports push=FAILED" \
  || fail "(6) no push=FAILED in the handback: $(cut -c1-400 <<<"$(tr '\n' ' ' < "$TMP/err4")")"
grep -q '\[lan\]' "$TMP/err4" \
  && pass "(6) the failure names the REMOTE that did not receive the push" \
  || fail "(6) the failure does not name the remote: $(cut -c1-400 <<<"$(tr '\n' ' ' < "$TMP/err4")")"
[[ "$(bare_head "$LAN4")" == NONE ]] \
  && pass "(6) the remote really is unmoved (the verification was not a false alarm)" \
  || fail "(6) the remote moved — the fixture is wrong"

# =====================================================================================
# (7) THE FALSE-RESOLVE HAZARD IN ITS SHARPEST FORM — the PRIVATE remote is named `origin`
#     (the one ratify-queue.sh picks by DEFAULT when no --remote is given) and the PUBLIC
#     one is `pub`. Verifying "the default remote" would find the merge, on the remote that
#     was auto-pushed, and resolve an entry whose PUBLIC remote is still empty. `resolve`
#     must key on the record's `pending_remotes`, not on a default.
# =====================================================================================
PUB5="$TMP/o-sw.git"; LAN5="$TMP/o-sw-lan.git"
git init --bare -b main -q "$PUB5"; git init --bare -b main -q "$LAN5"
git clone -q "$PUB5" "$TMP/s-sw" 2>/dev/null
echo base > "$TMP/s-sw/f"; cp "$TMP/rm.md" "$TMP/s-sw/ROADMAP.md"
git -C "$TMP/s-sw" add -A; git -C "$TMP/s-sw" commit -qm base; git -C "$TMP/s-sw" push -q -u origin main
M5="$TMP/m-sw"; git clone -q "$PUB5" "$M5" 2>/dev/null
git -C "$M5" remote set-url origin "$LAN5"     # origin IS the private/LAN remote here
git -C "$M5" remote add pub "$PUB5"            # ...and the public one is called `pub`
R5="$(basename "$M5")"; W5="$(child "$M5" sw)"; C5="$(cfg sw "$R5")"
rc=0
out5="$(FABLES_CONFIG="$C5" INTEGRATE_GIT_LOCK_PUSH="$LOCKPUSH" \
  "$INT" --repo "$R5" --path "$M5" --worktree "$W5" --branch relay/sw \
         --summary "close aaaa" --run r5 --label "executor (claude-sonnet-4-5, relay-loop)" \
         --ids aaaa --verdict execute --substantive true 2>"$ERRLOG")" || rc=$?
[[ $rc -eq 0 ]] || fail "(7) integrate exited $rc"
HEAD5="$(git -C "$M5" rev-parse HEAD)"
[[ "$(bare_head "$LAN5")" == "$HEAD5" && "$(bare_head "$PUB5")" != "$HEAD5" ]] \
  && pass "(7) origin (private) carries the merge; pub (public) does not — the hazard is set up" \
  || fail "(7) fixture wrong: lan=$(bare_head "$LAN5") pub=$(bare_head "$PUB5") HEAD=$HEAD5"
[[ "$(key "$out5" pushPending)" == pub ]] \
  && pass "(7) pushPending=pub" \
  || fail "(7) pushPending='$(key "$out5" pushPending)', expected pub"
Q5="$C5/ratification-queue.jsonl"
rrc=0
rout="$(RELAY_RATIFICATION_QUEUE="$Q5" "$RATIFY" resolve "$(key "$out5" ckpt)" 2>&1)" || rrc=$?
if [[ $rrc -ne 0 ]]; then
  pass "(7) resolve REFUSES even though the DEFAULT remote 'origin' carries the merge (rc=$rrc) — it verifies pending_remotes, not a default"
else
  fail "(7) FALSE RESOLVE: the entry was resolved by verifying the already-pushed 'origin' while 'pub' still lacks the merge: $rout"
fi
grep -q 'pub' <<<"$rout" \
  && pass "(7) the refusal names the remote that is actually missing the merge" \
  || fail "(7) the refusal does not name 'pub': $rout"

echo "ALL PASS: integrate.sh per-remote push narrowing (roadmap:4d44)"
