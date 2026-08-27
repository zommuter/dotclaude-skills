#!/usr/bin/env bash
# RED SPEC for id:99b7 HALF (a) — the do-publish ALLOWLIST.
#
# NO `# roadmap:` HEADER ON PURPOSE. id:99b7 is TODO-tracked and has NOT been promoted to
# ROADMAP.md by the owner, so this file cannot claim an expected-red exemption: it is a
# genuinely failing spec and `tests/run-tests.sh` will count it as a real failure until
# half (a) is implemented. That is intentional — do not add a header to silence it, and do
# not tick anything to make it green.
#
# ── THE RATIFIED DIRECTION (TODO.md id:99b7, owner-ratified 2026-08-27) ────────────────
#   Today integrate.sh's per-remote narrowing (id:4d44) INFERS the publish question from the
#   privacy question: "not provably private ⇒ a public remote awaiting owner ratification".
#   That inference fails OPEN — for a *publishing* decision, the wrong way round. The live
#   consequence: git-annex's `upstream` is `git://git-annex.branchable.com/`, a read-only
#   third-party URL we only ever FETCH from, and it is recorded as a remote awaiting
#   ratification. Four such entries exist and NONE can ever resolve; every git-annex
#   integrate mints another.
#
#   The owner chose an explicit do-publish ALLOWLIST over the offered scheme-based exclusion,
#   and INVERTED its polarity: declare the remotes we DO publish to; everything else is
#   not-a-publish-target. This yields a THREE-WAY semantic the current two-way private/public
#   split cannot express:
#
#     private + declared   ⇒ push IMMEDIATELY                    (today's `origin`/`fievel`)
#     public  + declared   ⇒ push GATED by owner ratification    (today's `github`)
#     UNDECLARED           ⇒ NEVER push, NEVER enter the pending-set — and SURFACED LOUDLY
#
#   Shape: a GLOBAL default (`origin` — 41 of 46 own repos' remote is the private LAN host
#   and all are named `origin`) plus PER-REPO additions (exactly four repos carry a public
#   GitHub remote: dotclaude-skills, zkm, toesnail, proton-moresync).
#
# ── THE TWO FAILURE MODES THIS FILE PINS ──────────────────────────────────────────────
#   (I)  THE BUG BEING FIXED — an undeclared third-party upstream must not enter the
#        pending-set (scenarios A and B below).
#   (II) THE MIRROR FAILURE, WHICH IS THE DANGEROUS ONE — a pure allowlist silently swallows
#        a remote the owner genuinely WANTS to publish to: add a GitHub remote, forget to
#        declare it, and nothing publishes AND nothing complains. Every scenario that
#        contains an undeclared remote therefore asserts the LOUD SURFACING as well as the
#        exclusion (scenarios A, B, C, D). A test that only checked "undeclared remotes are
#        skipped" would RATIFY the mirror bug, so the surfacing assertions are not optional
#        garnish — they are half the spec.
#
#   Scenario E pins the ORTHOGONALITY the ratified text calls out explicitly:
#   lib-private-remote.sh stays THE private-host predicate and is NOT extended to answer the
#   publish question. Conflating them is out of scope by owner ruling.
#
# ── DESIGN LATITUDE EXERCISED HERE (owner's to confirm — see the agent's report) ───────
#   * DECLARATION SITE: `${FABLES_CONFIG}/relay.toml`, the existing own-repo/policy SSOT
#     integrate.sh already reads for `bump_policy`. No new config file.
#   * KEY NAMES: a global `[publish] default_remotes = [...]` table, plus per-repo
#     `[repos.<name>] publish_remotes = [...]`. The per-repo list is ADDITIVE (union with
#     the global default), matching the ratified word "additions".
#   * BUILT-IN FALLBACK: with no `[publish]` table at all, the global default is `origin`.
#     (Fail-closed-to-nothing would stop the whole fleet publishing; the ratified text names
#     `origin` as the global default, so that is the floor.)
#   * SURFACING CHANNEL: asserted on the COMBINED stdout+stderr, so the implementation may
#     choose either; the WORDING is asserted strictly, from the ratified text.
#   * STRUCTURED STDOUT: a `pushRemote=<name>:undeclared` per-remote line, joining the
#     existing `pushed|deferred|FAILED|no-push-url|skipped-no-ssh-key` vocabulary.
#
# ── HERMETIC ──────────────────────────────────────────────────────────────────────────
#   mktemp repos with LOCAL BARE remotes; a FIXTURE private-host pattern file (NEVER the real
#   ~/.config/dotclaude-skills/privacy-patterns.txt); FABLES_CONFIG pointed at a temp dir so
#   the real ~/.config/relay/relay.toml and ratification-queue.jsonl are never read or
#   written; GIT_CONFIG_COUNT to neutralise a global core.hooksPath. NO NETWORK.
#
#   NOTE ON THE THIRD-PARTY FIXTURE: the live case is git-annex's
#   `upstream = git://git-annex.branchable.com/`. The fixture uses a LOCAL BARE repo for that
#   remote instead of the real URL, deliberately: under today's code the NON-SUBSTANTIVE path
#   (scenario D) pushes EVERY remote, so a real URL there makes the suite hit the network and
#   get rejected by a stranger's pre-receive hook. Both URLs classify identically for this
#   spec's purposes — a bare path has no host and a `git://` host is not private, so both are
#   "public/unknown" today and both are UNDECLARED under the allowlist. The local bare also
#   gives a stronger assertion: it CAN receive a push, so "it is unmoved" is real evidence
#   that nothing was published rather than an artefact of an unreachable URL.
set -uo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INT="${INT_OVERRIDE:-$SRC_DIR/relay/scripts/integrate.sh}"
INT_DIR="$(cd "$(dirname "$INT")" && pwd)"
LIB_PRIV="$INT_DIR/lib-private-remote.sh"
LOCKPUSH="${GIT_LOCK_PUSH_OVERRIDE:-$SRC_DIR/git-diary-workflow/git-lock-push.sh}"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0
pass() { echo "PASS: $*"; }
# NON-EXITING: this is a multi-behaviour RED spec, and a first-failure exit would hide which
# of the two failure modes is unmet. Fixture faults still die immediately via die().
fail() { echo "FAIL: $*"; FAILS=$((FAILS+1)); }
die()  { echo "FIXTURE-ERROR: $*"; exit 2; }

[[ -x "$INT" ]] || die "integrate.sh not found/executable at $INT"

export GIT_CONFIG_COUNT=4
export GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0="$TMP/nohooks"
export GIT_CONFIG_KEY_1=user.email     GIT_CONFIG_VALUE_1=t@e.st
export GIT_CONFIG_KEY_2=user.name      GIT_CONFIG_VALUE_2=t
export GIT_CONFIG_KEY_3=init.defaultBranch GIT_CONFIG_VALUE_3=main
mkdir -p "$TMP/nohooks"

# FIXTURE private-host pattern file: any bare remote whose path ends `-lan.git` is PRIVATE.
# Real host names never appear in a committed file in this public repo.
PATFILE="$TMP/privacy-patterns.txt"
printf '# fixture — synthetic only\nprivate-host: -lan\\.git$\n' > "$PATFILE"
export PRIVACY_GATE_PATTERNS="$PATFILE"

cat > "$TMP/rm.md" <<'EOF'
# Roadmap

- [ ] [ROUTINE] the worked item <!-- id:aaaa -->
- [ ] [ROUTINE] an untouched item <!-- id:bbbb -->
EOF

# ── fixture helpers ───────────────────────────────────────────────────────────────────
# seed <sfx> → creates the private LAN bare + a seeded main checkout whose `origin` is it.
seed() {
  local sfx="$1"
  local lan="$TMP/o-$sfx-lan.git" s="$TMP/s-$sfx" m="$TMP/m-$sfx"
  git init --bare -b main -q "$lan" || die "init $lan"
  git clone -q "$lan" "$s" 2>/dev/null || die "clone $lan"
  echo base > "$s/f"; cp "$TMP/rm.md" "$s/ROADMAP.md"
  git -C "$s" add -A && git -C "$s" commit -qm base && git -C "$s" push -q -u origin main \
    || die "seed $sfx"
  git clone -q "$lan" "$m" 2>/dev/null || die "clone main $sfx"
  printf '%s' "$m"
}
child() {
  local m="$1" name="$2"
  local wt="$TMP/wt-$name"
  git -C "$m" worktree add -q -b "relay/$name" "$wt" main || die "worktree $name"
  echo "work-$name" > "$wt/g-$name"
  git -C "$wt" add -A && git -C "$wt" commit -qm "child work $name" || die "commit $name"
  printf '%s' "$wt"
}
# cfg <sfx> <repo> [extra per-repo TOML lines...]  → a FABLES_CONFIG dir holding relay.toml
# carrying the GLOBAL publish default plus whatever per-repo additions the scenario declares.
cfg() {
  local d="$TMP/cfg-$1"
  local repo="$2"; shift 2
  mkdir -p "$d"
  {
    printf '[publish]\ndefault_remotes = ["origin"]\n\n'
    printf '[repos.%s]\nstatus = "active"\n' "$repo"
    local l; for l in "$@"; do printf '%s\n' "$l"; done
  } > "$d/relay.toml"
  printf '%s' "$d"
}
bare_head() { git -C "$1" rev-parse --verify -q refs/heads/main 2>/dev/null || echo NONE; }
key() { awk -F'=' -v k="$2" '$1==k{print substr($0, length(k)+2); exit}' <<<"$1"; }

# THE RATIFIED SURFACING WORDING. Asserted on the COMBINED stdout+stderr so the
# implementation picks the channel; the words and the remote NAME are pinned.
# A line must name the remote AND say it is not in the publish set AND say that this means
# neither publishing nor tracking. All three, on one line — "surfaced loudly", not a debug
# crumb buried in a log file.
assert_surfaced() {
  local label="$1" combined="$2" remote="$3"
  local line
  # awk over a herestring, NOT `grep | grep | head`: a producer piped into an early-exiting
  # consumer under `pipefail` is banned repo-wide (id:81d5, test_pipefail_sigpipe_lint.sh).
  line="$(awk -v r="$remote" 'index(tolower($0), "not in the publish set") && index($0, r) { print; exit }' <<<"$combined")"
  if [[ -z "$line" ]]; then
    fail "$label THE MIRROR BUG IS UNGUARDED: no loud line naming undeclared remote '$remote' with 'not in the publish set'. An undeclared remote that is silently skipped is exactly the failure this spec exists to prevent. Output was: $(tr '\n' '|' <<<"$combined" | cut -c1-600)"
    return
  fi
  if grep -qiF 'not publishing, not tracking' <<<"$line"; then
    pass "$label undeclared remote '$remote' is SURFACED LOUDLY with the ratified wording"
  else
    fail "$label the line naming '$remote' does not carry the ratified 'not publishing, not tracking' half: $line"
  fi
}
assert_not_surfaced_silently() { : ; }   # placeholder: silence is never acceptable here

run_int() {  # run_int <cfgdir> <repo> <path> <wt> <branch> <run> <substantive> <outvar-prefix>
  local c="$1" repo="$2" p="$3" w="$4" br="$5" rn="$6" sub="$7" pfx="$8"
  local errf="$TMP/err-$pfx"
  local o rc=0
  o="$(FABLES_CONFIG="$c" INTEGRATE_GIT_LOCK_PUSH="$LOCKPUSH" \
      "$INT" --repo "$repo" --path "$p" --worktree "$w" --branch "$br" \
             --summary "close aaaa" --run "$rn" \
             --label "executor (claude-sonnet-4-5, relay-loop)" \
             --ids aaaa --verdict execute --substantive "$sub" 2>"$errf")" || rc=$?
  printf '%s' "$o"       > "$TMP/out-$pfx"
  cat "$TMP/out-$pfx" "$errf" > "$TMP/comb-$pfx"
  printf '%s' "$rc"      > "$TMP/rc-$pfx"
}

# ======================================================================================
# (A) THE FULL THREE-WAY SEMANTIC IN ONE REPO
#     origin   = private LAN, GLOBALLY declared      ⇒ pushed immediately
#     github   = public bare, PER-REPO declared      ⇒ deferred, enters the pending-set
#     upstream = git://…  UNDECLARED (git-annex)     ⇒ never pushed, NEVER pending, SURFACED
# ======================================================================================
MA="$(seed a)"; RA="$(basename "$MA")"; LANA="$TMP/o-a-lan.git"; PUBA="$TMP/o-a-pub.git"
git init --bare -b main -q "$PUBA" || die "init $PUBA"
git -C "$MA" remote add github "$PUBA"            || die "remote add github"
THIRDA="$TMP/o-a-third.git"; git init --bare -b main -q "$THIRDA" || die "init $THIRDA"
git -C "$MA" remote add upstream "$THIRDA"        || die "remote add upstream"
WA="$(child "$MA" a)"
CA="$(cfg a "$RA" 'publish_remotes = ["github"]')"
run_int "$CA" "$RA" "$MA" "$WA" relay/a rA true A
outA="$(cat "$TMP/out-A")"; combA="$(cat "$TMP/comb-A")"
[[ "$(cat "$TMP/rc-A")" == 0 ]] || die "(A) integrate exited $(cat "$TMP/rc-A") — a partial push is a SUCCESS path; fixture or environment fault: $(tail -n 20 "$TMP/err-A")"
HEADA="$(git -C "$MA" rev-parse HEAD)"

[[ "$(bare_head "$LANA")" == "$HEADA" ]] \
  && pass "(A) private+DECLARED 'origin' received the merge immediately" \
  || fail "(A) private+declared 'origin' did NOT receive the merge (origin=$(bare_head "$LANA") HEAD=$HEADA)"
[[ "$(bare_head "$PUBA")" != "$HEADA" ]] \
  && pass "(A) public+DECLARED 'github' is unmoved — publication still needs owner ratification" \
  || fail "(A) 'github' MOVED — substantive agent work was auto-published"

[[ "$(bare_head "$THIRDA")" == NONE ]] \
  && pass "(A) UNDECLARED 'upstream' is byte-unmoved — we never publish to a third party's repo" \
  || fail "(A) the UNDECLARED third-party remote RECEIVED a push"

# ── (A1) THE BUG BEING FIXED: the undeclared remote must not be in the pending-set. ──
[[ "$(key "$outA" pushPending)" == "github" ]] \
  && pass "(A1) pushPending names ONLY the declared public remote" \
  || fail "(A1) THE id:99b7 BUG: pushPending='$(key "$outA" pushPending)', expected exactly 'github'. An UNDECLARED third-party upstream is being recorded as a remote awaiting ratification — an entry that can never resolve."
grep -qx 'pushRemote=upstream:undeclared' <<<"$outA" \
  && pass "(A1) per-remote line: pushRemote=upstream:undeclared (the third status)" \
  || fail "(A1) missing 'pushRemote=upstream:undeclared' — the three-way semantic has no third value. Got: $(grep '^pushRemote=' <<<"$outA" | tr '\n' ' ')"
grep -qx 'pushRemote=origin:pushed' <<<"$outA" \
  && pass "(A1) per-remote line: pushRemote=origin:pushed" \
  || fail "(A1) missing 'pushRemote=origin:pushed'. Got: $(grep '^pushRemote=' <<<"$outA" | tr '\n' ' ')"
grep -qx 'pushRemote=github:deferred' <<<"$outA" \
  && pass "(A1) per-remote line: pushRemote=github:deferred" \
  || fail "(A1) missing 'pushRemote=github:deferred'. Got: $(grep '^pushRemote=' <<<"$outA" | tr '\n' ' ')"

# ── (A2) THE MIRROR GUARD: excluded, but LOUDLY. ──
assert_surfaced "(A2)" "$combA" upstream

# ── (A3) the durable queue record must not carry the undeclared remote either. ──
QA="$CA/ratification-queue.jsonl"
if [[ -s "$QA" ]]; then
  if python3 - "$QA" >"$TMP/qa.err" 2>&1 <<'PYEOF'
import json, sys
rec = json.loads(open(sys.argv[1]).read().strip().splitlines()[-1])
pend = rec.get("pending_remotes")
if pend != ["github"]:
    print("pending_remotes=%r, expected ['github'] — an undeclared remote entered the queue" % (pend,))
    raise SystemExit(1)
if "upstream" in (rec.get("action") or ""):
    print("the remediation action names the undeclared remote: %r" % (rec.get("action"),))
    raise SystemExit(1)
PYEOF
  then
    pass "(A3) the queue record's pending_remotes is exactly ['github'] — no unresolvable entry minted"
  else
    fail "(A3) $(cat "$TMP/qa.err")"
  fi
else
  fail "(A3) no ratification queue entry at $QA — the DECLARED public remote must still be tracked"
fi
[[ "$(key "$outA" ratification)" == pending ]] \
  && pass "(A) ratification=pending — the declared public remote still lacks the merge" \
  || fail "(A) ratification='$(key "$outA" ratification)', expected pending"

# ======================================================================================
# (B) THE LIVE git-annex SHAPE — origin private+declared, upstream UNDECLARED, nothing else.
#     Every remote we publish to has the merge, so NOTHING is pending: ratification=none and
#     NO queue entry at all. This is the four-unresolvable-entries defect, closed.
#     AND YET the undeclared remote is STILL surfaced — silence here is the mirror bug.
# ======================================================================================
MB="$(seed b)"; RB="$(basename "$MB")"; LANB="$TMP/o-b-lan.git"
THIRDB="$TMP/o-b-third.git"; git init --bare -b main -q "$THIRDB" || die "init $THIRDB"
git -C "$MB" remote add upstream "$THIRDB" || die "remote add upstream b"
WB="$(child "$MB" b)"
CB="$(cfg b "$RB")"                    # NO per-repo additions — global `origin` only
run_int "$CB" "$RB" "$MB" "$WB" relay/b rB true B
outB="$(cat "$TMP/out-B")"; combB="$(cat "$TMP/comb-B")"
[[ "$(cat "$TMP/rc-B")" == 0 ]] || die "(B) integrate exited $(cat "$TMP/rc-B"): $(tail -n 20 "$TMP/err-B")"
HEADB="$(git -C "$MB" rev-parse HEAD)"

[[ "$(bare_head "$LANB")" == "$HEADB" ]] \
  && pass "(B) the declared private origin received the merge" \
  || fail "(B) the declared private origin did not receive the merge"
[[ "$(key "$outB" push)" == pushed ]] \
  && pass "(B) push=pushed — every remote we PUBLISH TO carries the merge" \
  || fail "(B) push='$(key "$outB" push)', expected 'pushed'. An UNDECLARED remote must not degrade the aggregate to 'partial'/'deferred' — we were never going to publish there."
[[ "$(key "$outB" ratification)" == none ]] \
  && pass "(B) ratification=none — nothing awaits the owner" \
  || fail "(B) THE id:99b7 DEFECT VERBATIM: ratification='$(key "$outB" ratification)', expected 'none'. git-annex's read-only 'upstream' is being held for a ratification that can never happen."
[[ ! -s "$CB/ratification-queue.jsonl" ]] \
  && pass "(B) NO queue entry minted — the four unresolvable relay-ckpt-20260826-* entries stop being produced" \
  || fail "(B) an unresolvable queue entry was minted for an undeclared remote: $(cat "$CB/ratification-queue.jsonl")"
[[ "$(bare_head "$THIRDB")" == NONE ]] \
  && pass "(B) the UNDECLARED third-party remote is byte-unmoved" \
  || fail "(B) the UNDECLARED third-party remote RECEIVED a push"
assert_surfaced "(B)" "$combB" upstream

# ======================================================================================
# (C) THE MIRROR BUG IN ITS DANGEROUS FORM — the owner ADDS a real GitHub remote and FORGETS
#     to declare it. A pure allowlist would publish nothing and say nothing; the ratified
#     design REQUIRES the loud line. This scenario exists solely to make silence fail.
# ======================================================================================
MC="$(seed c)"; RC_="$(basename "$MC")"; PUBC="$TMP/o-c-pub.git"
git init --bare -b main -q "$PUBC" || die "init $PUBC"
git -C "$MC" remote add newgithub "$PUBC" || die "remote add newgithub"
WC="$(child "$MC" c)"
CC="$(cfg c "$RC_")"                   # the owner forgot `publish_remotes = ["newgithub"]`
run_int "$CC" "$RC_" "$MC" "$WC" relay/c rC true C
outC="$(cat "$TMP/out-C")"; combC="$(cat "$TMP/comb-C")"
[[ "$(cat "$TMP/rc-C")" == 0 ]] || die "(C) integrate exited $(cat "$TMP/rc-C"): $(tail -n 20 "$TMP/err-C")"
HEADC="$(git -C "$MC" rev-parse HEAD)"
[[ "$(bare_head "$PUBC")" != "$HEADC" ]] \
  && pass "(C) the undeclared GitHub remote was NOT published to (the allowlist fails CLOSED)" \
  || fail "(C) the undeclared remote WAS published to"
[[ "$(key "$outC" pushPending)" != *newgithub* ]] \
  && pass "(C) the undeclared remote did not enter the pending-set" \
  || fail "(C) undeclared 'newgithub' entered pushPending='$(key "$outC" pushPending)'"
# THE assertion that separates this spec from one that would ratify the mirror bug:
assert_surfaced "(C)" "$combC" newgithub

# ======================================================================================
# (D) UNDECLARED IS UNCONDITIONAL — a NON-SUBSTANTIVE unit pushes every DECLARED remote
#     (unchanged, id:4d44 case 4) but still must not touch an undeclared one, and still
#     surfaces it. "Never push, never track" carries no substantive-ness qualifier.
# ======================================================================================
MD="$(seed d)"; RD="$(basename "$MD")"; LAND="$TMP/o-d-lan.git"; PUBD="$TMP/o-d-pub.git"
git init --bare -b main -q "$PUBD" || die "init $PUBD"
git -C "$MD" remote add github "$PUBD" || die "remote add github d"
THIRDD="$TMP/o-d-third.git"; git init --bare -b main -q "$THIRDD" || die "init $THIRDD"
git -C "$MD" remote add upstream "$THIRDD" || die "remote add upstream d"
WD="$(child "$MD" d)"
CD="$(cfg d "$RD" 'publish_remotes = ["github"]')"
run_int "$CD" "$RD" "$MD" "$WD" relay/d rD false D
outD="$(cat "$TMP/out-D")"; combD="$(cat "$TMP/comb-D")"
# NOT a die(): under today's code an undeclared remote is pushed to, and a push that fails
# hands back — so a non-zero rc here is a genuine SPEC failure, not a fixture fault.
[[ "$(cat "$TMP/rc-D")" == 0 ]] \
  && pass "(D) the non-substantive integrate succeeded" \
  || fail "(D) integrate exited $(cat "$TMP/rc-D") — pushing to an undeclared remote must never be attempted, so it can never hand back: $(tail -n 5 "$TMP/err-D" | tr '\n' ' ')"
HEADD="$(git -C "$MD" rev-parse HEAD)"
[[ "$(bare_head "$LAND")" == "$HEADD" && "$(bare_head "$PUBD")" == "$HEADD" ]] \
  && pass "(D) a NON-substantive unit still pushes every DECLARED remote (id:4d44 case 4 preserved)" \
  || fail "(D) a non-substantive unit did not push the declared remotes (origin=$(bare_head "$LAND") github=$(bare_head "$PUBD") HEAD=$HEADD)"
[[ "$(bare_head "$THIRDD")" == NONE ]] \
  && pass "(D) the UNDECLARED remote is unmoved even on the NON-substantive path — 'never push' carries no substantive-ness qualifier" \
  || fail "(D) a NON-substantive unit PUBLISHED to an UNDECLARED third-party remote (this is the live git-annex shape: today's code pushes every remote when the unit is non-substantive)"
grep -qx 'pushRemote=upstream:undeclared' <<<"$outD" \
  && pass "(D) the undeclared remote is 'undeclared' even on the non-substantive path" \
  || fail "(D) undeclared exclusion is conditional on substantive-ness. Got: $(grep '^pushRemote=' <<<"$outD" | tr '\n' ' ')"
assert_surfaced "(D)" "$combD" upstream

# ======================================================================================
# (E) ORTHOGONALITY — lib-private-remote.sh stays THE private-host predicate and is NOT
#     extended to answer the publish question. Ratified: "the two must not be conflated —
#     do not extend the private predicate to answer it."
# ======================================================================================
[[ -r "$LIB_PRIV" ]] || die "(E) lib-private-remote.sh unreadable at $LIB_PRIV"
if grep -Eqi '(^|[^a-z_])(is_publish_remote|publish_remotes|publish_allowlist|is_publish_target|do_publish)' "$LIB_PRIV"; then
  fail "(E) lib-private-remote.sh has grown publish-allowlist vocabulary — the two predicates were conflated. The publish question belongs in its own resolver (e.g. a sibling relay/scripts/lib-publish-remote.sh), not in the private-host predicate: $(awk '/(is_publish_remote|publish_remotes|publish_allowlist|is_publish_target|do_publish)/ { print NR": "$0; if (++n >= 3) exit }' "$LIB_PRIV" | tr '\n' ' ')"
else
  pass "(E) lib-private-remote.sh carries NO publish-allowlist vocabulary"
fi
# ...and its VERDICTS are unaffected by the publish declaration, in both directions.
( set +u
  # shellcheck source=../relay/scripts/lib-private-remote.sh
  . "$LIB_PRIV"
  rcp=0; is_private_remote_url "$TMP/o-a-lan.git" || rcp=$?
  rcg=0; is_private_remote_url 'https://github.com/o/r.git' || rcg=$?
  rcu=0; is_private_remote_url 'git://git-annex.branchable.com/' || rcu=$?
  printf '%s %s %s' "$rcp" "$rcg" "$rcu" > "$TMP/priv-verdicts"
) || die "(E) sourcing lib-private-remote.sh failed"
read -r vlan vgh vup < "$TMP/priv-verdicts"
[[ "$vlan" == 0 ]] \
  && pass "(E) the LAN bare is still PRIVATE — declaring it publishable did not change that" \
  || fail "(E) the private predicate no longer calls the fixture LAN host private (rc=$vlan)"
[[ "$vgh" == 1 ]] \
  && pass "(E) github.com is still NOT private — DECLARING it publishable must not make it private" \
  || fail "(E) github.com came back PRIVATE (rc=$vgh) — the publish declaration leaked into the privacy predicate, which would also skip the leak scan"
[[ "$vup" == 1 ]] \
  && pass "(E) the third-party git:// upstream is still NOT private — UNDECLARED is a separate axis from PRIVATE" \
  || fail "(E) the undeclared upstream came back PRIVATE (rc=$vup) — the exclusion was implemented by widening the privacy predicate, which would also skip its leak scan"

# ======================================================================================
if [[ $FAILS -eq 0 ]]; then
  echo "ALL PASS: do-publish allowlist (id:99b7 half (a))"
  exit 0
fi
echo "FAILED: $FAILS assertion(s) — id:99b7 half (a) is NOT implemented (this file is a RED SPEC)"
exit 1
