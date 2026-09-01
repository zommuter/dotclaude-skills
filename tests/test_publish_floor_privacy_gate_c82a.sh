#!/usr/bin/env bash
# SPEC for id:c82a — the do-publish `origin` FLOOR must be GATED on the private-remote
# predicate, and must fail toward NOT publishing.
#
# NO `# roadmap:` HEADER ON PURPOSE. id:c82a is TODO-tracked (children-of:99b7) and has not
# been promoted to ROADMAP.md, so this file claims no expected-red exemption: its failures
# always count.
#
# ── THE DEFECT ────────────────────────────────────────────────────────────────────────
#   `lib-publish-remote.sh` applies a built-in FLOOR — the publish set becomes `origin` —
#   whenever no `[publish] default_remotes` is declared at all (absent/unreadable relay.toml,
#   a fresh install, a hermetic root). That floor is the ONE path that never consults a
#   declaration, and it assumes `origin` is the private LAN host. True of THIS fleet today
#   (all 56 own-repo origins verified private 2026-08-27, 0 non-private) and false in general:
#   `git clone https://github.com/foo/bar` sets `origin` to a PUBLIC remote — the single most
#   ordinary way a repo enters `~/src` — and the floor would then publish agent-authored work
#   straight through the allowlist built to prevent exactly that, SILENTLY.
#
# ── WHAT THIS FILE PINS ───────────────────────────────────────────────────────────────
#   (A) FLOORED + origin NOT provably private ⇒ WITHHELD, and LOUDLY. Run NON-substantive on
#       purpose: that path pushes every DECLARED remote unconditionally (id:4d44 case 4), so
#       "the bare is byte-unmoved" is evidence of the withholding itself and not of a defer.
#   (B) NEGATIVE CONTROL — FLOORED + origin PROVABLY private ⇒ still pushed. Without this,
#       (A) would also pass a implementation that simply broke the floor for everyone.
#   (C) NARROWNESS — an EXPLICITLY declared `origin` is honoured verbatim even when it is not
#       provably private. The owner ratified declaration-as-authority; this gate is about the
#       undeclared/fallback path only, and that is also the live fleet's case
#       (`[publish] default_remotes = ["origin"]`), i.e. the fleet is unaffected.
#   (D) FAIL DIRECTION — privacy UNDETERMINABLE (the private-host predicate itself unreadable)
#       ⇒ WITHHELD, even for an origin that WOULD have been proven private had the predicate
#       been readable. A silent fall-through to publishing is the defect being fixed.
#   (E) REUSE, NOT REINVENTION — the gate goes through lib-private-remote.sh's
#       `is_private_remote_url`, never git-lock-push.sh's `is_ssh_url()` (an SSH-AUTH
#       predicate that calls `ssh://github.com/…` private and so fails toward AUTO-PUBLISH),
#       and the two libs stay orthogonal — no privacy vocabulary inside the publish resolver.
#
# ── HERMETIC ──────────────────────────────────────────────────────────────────────────
#   mktemp repos with LOCAL BARE remotes only; a FIXTURE private-host pattern file (NEVER the
#   real ~/.config/dotclaude-skills/privacy-patterns.txt); FABLES_CONFIG pointed at a temp dir
#   so the real relay.toml / ratification queue are never read or written; GIT_CONFIG_COUNT to
#   neutralise a global core.hooksPath. NO NETWORK, and NO real remote URL appears anywhere —
#   a fixture holding one WILL act on it (that is how id:99b7 was found).
# fails-against: rev 92f9e875e8ae -- the tree as it stood immediately before the commit that
#   added this test, i.e. the pre-fix relay/scripts/archive-closed.sh, relay/scripts/integrate.sh, relay/scripts/lib-publish-remote.sh. Derived + verified by tests/verify-negative-cases.py.
# fails-against-rev: 92f9e875e8ae -- relay/scripts/archive-closed.sh relay/scripts/integrate.sh relay/scripts/lib-publish-remote.sh
# fails-against-assertion: there is still an ASSUMPTION and must be proven private.

set -uo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INT="${INT_OVERRIDE:-$SRC_DIR/relay/scripts/integrate.sh}"
INT_DIR="$(cd "$(dirname "$INT")" && pwd)"
LIB_PUB="$INT_DIR/lib-publish-remote.sh"
LOCKPUSH="${GIT_LOCK_PUSH_OVERRIDE:-$SRC_DIR/git-diary-workflow/git-lock-push.sh}"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; FAILS=$((FAILS+1)); }
die()  { echo "FIXTURE-ERROR: $*"; exit 2; }

[[ -x "$INT" ]] || die "integrate.sh not found/executable at $INT"
[[ -r "$LIB_PUB" ]] || die "lib-publish-remote.sh unreadable at $LIB_PUB"

export GIT_CONFIG_COUNT=4
export GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0="$TMP/nohooks"
export GIT_CONFIG_KEY_1=user.email     GIT_CONFIG_VALUE_1=t@e.st
export GIT_CONFIG_KEY_2=user.name      GIT_CONFIG_VALUE_2=t
export GIT_CONFIG_KEY_3=init.defaultBranch GIT_CONFIG_VALUE_3=main
mkdir -p "$TMP/nohooks"

# FIXTURE private-host pattern file: a bare remote whose path ends `-lan.git` is PRIVATE.
# Everything else — including a bare path ending `-pub.git` — is NOT provably private, which
# is exactly the classification a `https://github.com/...` origin would get. Real host names
# never appear in a committed file in this public repo.
PATFILE="$TMP/privacy-patterns.txt"
printf '# fixture — synthetic only\nprivate-host: -lan\\.git$\n' > "$PATFILE"
export PRIVACY_GATE_PATTERNS="$PATFILE"

cat > "$TMP/rm.md" <<'EOF'
# Roadmap

- [ ] [ROUTINE] the worked item <!-- id:aaaa -->
EOF

# seed <sfx> <origin-suffix> → bare origin at $TMP/o-<sfx>-<suffix>.git + a main checkout.
# The origin-suffix decides its fixture privacy: `lan` matches the pattern, `pub` does not.
seed() {
  local sfx="$1" kind="$2"
  local bare="$TMP/o-$sfx-$kind.git" s="$TMP/s-$sfx" m="$TMP/m-$sfx"
  git init --bare -b main -q "$bare" || die "init $bare"
  git clone -q "$bare" "$s" 2>/dev/null || die "clone $bare"
  echo base > "$s/f"; cp "$TMP/rm.md" "$s/ROADMAP.md"
  git -C "$s" add -A && git -C "$s" commit -qm base && git -C "$s" push -q -u origin main \
    || die "seed $sfx"
  git clone -q "$bare" "$m" 2>/dev/null || die "clone main $sfx"
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
# cfg <sfx> <repo> <declare-publish:yes|no> → FABLES_CONFIG dir holding relay.toml.
# `no` omits the whole [publish] table, which is what makes the run FLOORED.
cfg() {
  local d="$TMP/cfg-$1" repo="$2" declare_pub="$3"
  mkdir -p "$d"
  {
    if [[ "$declare_pub" == yes ]]; then printf '[publish]\ndefault_remotes = ["origin"]\n\n'; fi
    printf '[repos.%s]\nstatus = "active"\n' "$repo"
  } > "$d/relay.toml"
  printf '%s' "$d"
}
bare_head() { git -C "$1" rev-parse --verify -q refs/heads/main 2>/dev/null || echo NONE; }
key() { awk -F'=' -v k="$2" '$1==k{print substr($0, length(k)+2); exit}' <<<"$1"; }

# run_int <cfgdir> <repo> <path> <wt> <branch> <run> <pfx> [extra env assignments...]
run_int() {
  local c="$1" repo="$2" p="$3" w="$4" br="$5" rn="$6" pfx="$7"; shift 7
  local errf="$TMP/err-$pfx" o rc=0
  o="$(env FABLES_CONFIG="$c" INTEGRATE_GIT_LOCK_PUSH="$LOCKPUSH" "$@" \
      "$INT" --repo "$repo" --path "$p" --worktree "$w" --branch "$br" \
             --summary "close aaaa" --run "$rn" \
             --label "executor (claude-sonnet-4-5, relay-loop)" \
             --ids aaaa --verdict execute --substantive false 2>"$errf")" || rc=$?
  printf '%s' "$o" > "$TMP/out-$pfx"
  cat "$TMP/out-$pfx" "$errf" > "$TMP/comb-$pfx"
  printf '%s' "$rc" > "$TMP/rc-$pfx"
}

# The withholding must be LOUD: one line naming `origin`, saying it is not in the publish set,
# and saying that means neither publishing nor tracking — the same wording contract id:99b7
# pinned for an undeclared remote, because this IS an exclusion and silence is the mirror bug.
assert_withheld_loudly() {
  local label="$1" combined="$2" line
  line="$(awk 'index($0, "id:c82a") && index($0, "origin") { print; exit }' <<<"$combined")"
  if [[ -z "$line" ]]; then
    fail "$label NO loud id:c82a line naming 'origin'. A floor that silently declines to publish is only half a fix — the owner must be told the floor was withheld and why. Output was: $(tr '\n' '|' <<<"$combined" | cut -c1-700)"
    return
  fi
  if grep -qiF 'not in the publish set' <<<"$line" && grep -qiF 'not publishing, not tracking' <<<"$line"; then
    pass "$label the withheld floor is SURFACED LOUDLY with the ratified wording"
  else
    fail "$label the id:c82a line does not carry the ratified wording: $line"
  fi
}

# ======================================================================================
# (A) FLOORED + origin NOT provably private ⇒ WITHHELD.
# ======================================================================================
MA="$(seed a pub)"; RA="$(basename "$MA")"; BAREA="$TMP/o-a-pub.git"
WA="$(child "$MA" a)"
CA="$(cfg a "$RA" no)"
run_int "$CA" "$RA" "$MA" "$WA" relay/a rA A
outA="$(cat "$TMP/out-A")"; combA="$(cat "$TMP/comb-A")"
[[ "$(cat "$TMP/rc-A")" == 0 ]] \
  && pass "(A) integrate exited 0 — withholding a remote is a VERDICT, not a failure (id:2c2a)" \
  || fail "(A) integrate exited $(cat "$TMP/rc-A"); withholding must never manufacture a non-zero exit: $(tail -n 8 "$TMP/err-A" | tr '\n' ' ')"
HEADA="$(git -C "$MA" rev-parse HEAD)"
[[ "$(bare_head "$BAREA")" != "$HEADA" ]] \
  && pass "(A) THE FIX: the floored, not-provably-private 'origin' did NOT receive the merge" \
  || fail "(A) THE id:c82a DEFECT VERBATIM: agent-authored work was PUBLISHED to a floored 'origin' that was never declared and is not provably private. On a repo cloned from a public URL this is a silent publish straight through the allowlist."
grep -qx 'pushRemote=origin:undeclared' <<<"$outA" \
  && pass "(A) per-remote line: pushRemote=origin:undeclared" \
  || fail "(A) missing 'pushRemote=origin:undeclared'. Got: $(grep '^pushRemote=' <<<"$outA" | tr '\n' ' ')"
[[ "$(key "$outA" pushPending)" != *origin* ]] \
  && pass "(A) the withheld floor did not enter the pending-set (no unresolvable ratification entry)" \
  || fail "(A) withheld 'origin' entered pushPending='$(key "$outA" pushPending)'"
# The queue entry that DOES appear here is the pre-existing id:f0ad "this checkout has no
# upstream" surfacing: with the only remote withheld, the merge is local-only and the owner
# must be told. That is correct and must stay. What must NOT happen is the id:99b7 defect —
# the withheld remote recorded as AWAITING RATIFICATION, an entry no owner action could ever
# resolve. So the assertion is on the entry's CONTENT, not on its absence.
if [[ -s "$CA/ratification-queue.jsonl" ]]; then
  if python3 - "$CA/ratification-queue.jsonl" >"$TMP/qa.err" 2>&1 <<'PYEOF'
import json, sys
rec = json.loads(open(sys.argv[1]).read().strip().splitlines()[-1])
if rec.get("pending_remotes"):
    print("pending_remotes=%r — the WITHHELD floor was recorded as awaiting ratification, an entry no owner action can resolve" % (rec.get("pending_remotes"),))
    raise SystemExit(1)
if rec.get("pushed_remotes"):
    print("pushed_remotes=%r — something was published despite the floor being withheld" % (rec.get("pushed_remotes"),))
    raise SystemExit(1)
if rec.get("push") != "no-upstream":
    print("push=%r, expected 'no-upstream' — with every remote withheld the merge is local-only (id:f0ad)" % (rec.get("push"),))
    raise SystemExit(1)
PYEOF
  then
    pass "(A) the queue entry is the id:f0ad local-only surfacing (pending_remotes=[]) — the withheld floor did NOT mint an unresolvable ratification"
  else
    fail "(A) $(cat "$TMP/qa.err")"
  fi
else
  fail "(A) NO queue entry at all — with its only remote withheld the merge is local-only and that MUST still be surfaced to the owner (id:f0ad); silence here is the mirror bug"
fi
assert_withheld_loudly "(A)" "$combA"

# ======================================================================================
# (B) NEGATIVE CONTROL — FLOORED + origin PROVABLY private ⇒ still pushed.
#     The gate must narrow the floor, not abolish it.
# ======================================================================================
MB="$(seed b lan)"; RB="$(basename "$MB")"; BAREB="$TMP/o-b-lan.git"
WB="$(child "$MB" b)"
CB="$(cfg b "$RB" no)"
run_int "$CB" "$RB" "$MB" "$WB" relay/b rB B
outB="$(cat "$TMP/out-B")"
[[ "$(cat "$TMP/rc-B")" == 0 ]] || die "(B) integrate exited $(cat "$TMP/rc-B"): $(tail -n 12 "$TMP/err-B")"
HEADB="$(git -C "$MB" rev-parse HEAD)"
[[ "$(bare_head "$BAREB")" == "$HEADB" ]] \
  && pass "(B) a floored origin that IS provably private still receives the merge — the floor is narrowed, not abolished" \
  || fail "(B) the gate broke the floor outright: a PROVABLY PRIVATE floored origin did not receive the merge (origin=$(bare_head "$BAREB") HEAD=$HEADB). (A) would pass trivially under such an implementation."
grep -qx 'pushRemote=origin:pushed' <<<"$outB" \
  && pass "(B) per-remote line: pushRemote=origin:pushed" \
  || fail "(B) missing 'pushRemote=origin:pushed'. Got: $(grep '^pushRemote=' <<<"$outB" | tr '\n' ' ')"

# ======================================================================================
# (C) NARROWNESS — an EXPLICITLY declared origin is honoured verbatim, privacy or not.
#     Same not-provably-private bare as (A); the ONLY difference is the declaration.
# ======================================================================================
MC="$(seed c pub)"; RC_="$(basename "$MC")"; BAREC="$TMP/o-c-pub.git"
WC="$(child "$MC" c)"
CC="$(cfg c "$RC_" yes)"
run_int "$CC" "$RC_" "$MC" "$WC" relay/c rC C
outC="$(cat "$TMP/out-C")"
[[ "$(cat "$TMP/rc-C")" == 0 ]] || die "(C) integrate exited $(cat "$TMP/rc-C"): $(tail -n 12 "$TMP/err-C")"
HEADC="$(git -C "$MC" rev-parse HEAD)"
[[ "$(bare_head "$BAREC")" == "$HEADC" ]] \
  && pass "(C) an EXPLICITLY DECLARED origin is honoured verbatim — the gate touches the FLOOR only" \
  || fail "(C) the gate leaked past the floor and withheld a DECLARED origin. Declaration is the owner's authority (id:99b7); this would also break the live fleet, whose relay.toml declares default_remotes = [\"origin\"]."
grep -qx 'pushRemote=origin:pushed' <<<"$outC" \
  && pass "(C) declared origin: pushRemote=origin:pushed" \
  || fail "(C) missing 'pushRemote=origin:pushed'. Got: $(grep '^pushRemote=' <<<"$outC" | tr '\n' ' ')"
grep -qF 'id:c82a' "$TMP/comb-C" \
  && fail "(C) the id:c82a withholding line fired on a DECLARED origin — the gate is not floor-scoped" \
  || pass "(C) no id:c82a line on the declared path — the gate is silent when it does not apply"

# ======================================================================================
# (D) FAIL DIRECTION — privacy UNDETERMINABLE ⇒ WITHHELD. The origin here is the SAME
#     provably-private shape as (B); only the predicate is made unreadable. (B) proves it
#     would otherwise have been pushed, so this isolates the fail direction exactly.
# ======================================================================================
MD="$(seed d lan)"; RD="$(basename "$MD")"; BARED="$TMP/o-d-lan.git"
WD="$(child "$MD" d)"
CD="$(cfg d "$RD" no)"
run_int "$CD" "$RD" "$MD" "$WD" relay/d rD D \
  INTEGRATE_LIB_PRIVATE_REMOTE="$TMP/does-not-exist-lib-private-remote.sh"
outD="$(cat "$TMP/out-D")"; combD="$(cat "$TMP/comb-D")"
[[ "$(cat "$TMP/rc-D")" == 0 ]] \
  && pass "(D) integrate exited 0 with the privacy predicate unreadable" \
  || fail "(D) integrate exited $(cat "$TMP/rc-D"): $(tail -n 8 "$TMP/err-D" | tr '\n' ' ')"
HEADD="$(git -C "$MD" rev-parse HEAD)"
[[ "$(bare_head "$BARED")" != "$HEADD" ]] \
  && pass "(D) UNDETERMINABLE privacy WITHHELD the floor — unproven fails toward NOT publishing" \
  || fail "(D) with lib-private-remote.sh unreadable the floor PUBLISHED anyway. Nothing could be proven private, so this is a silent fall-through to publishing — the exact failure direction id:c82a forbids."
assert_withheld_loudly "(D)" "$combD"

# ======================================================================================
# (E) REUSE, NOT REINVENTION — and the two libs stay orthogonal.
# ======================================================================================
# CODE lines only — a comment naming a symbol is documentation, not a call, and both files
# deliberately DISCUSS the predicate they must not borrow. `awk`, never `grep | head`: a
# producer piped into an early-exiting consumer is banned repo-wide (id:81d5).
code_hits() { awk -v re="$2" '{ l=$0; sub(/^[ \t]+/,"",l) } substr(l,1,1) != "#" && $0 ~ re { print FILENAME":"FNR": "$0 }' "$1"; }
if [[ -n "$(code_hits "$INT" 'is_private_remote_url')" ]]; then
  pass "(E) integrate.sh gates the floor on lib-private-remote.sh's is_private_remote_url"
else
  fail "(E) integrate.sh does not CALL is_private_remote_url anywhere — the floor gate cannot be reusing THE private-host predicate (id:4d44)"
fi
ssh_hits="$(code_hits "$INT" '(^|[^a-z_])is_ssh_url')"
if [[ -n "$ssh_hits" ]]; then
  fail "(E) integrate.sh CALLS git-lock-push.sh's is_ssh_url() — an SSH-AUTH predicate that calls ssh://github.com/… private and so fails toward AUTO-PUBLISH. Never a substitute for the privacy predicate: $(tr '\n' ' ' <<<"$ssh_hits")"
else
  pass "(E) integrate.sh does NOT borrow is_ssh_url() for this decision"
fi
priv_hits="$(code_hits "$LIB_PUB" '(is_private_remote_url|private_remote_host|private_host_res|PRIVACY_GATE_PATTERNS)')"
if [[ -n "$priv_hits" ]]; then
  fail "(E) lib-publish-remote.sh has grown PRIVACY vocabulary in CODE — the two resolvers were conflated. The publish resolver has no checkout and must not answer the privacy question; the caller combines the two: $(tr '\n' ' ' <<<"$priv_hits")"
else
  pass "(E) lib-publish-remote.sh carries NO privacy vocabulary in code — the resolvers stay orthogonal"
fi
# The floor SIGNAL itself, unit-level. Without it the caller cannot scope the gate to the
# floor at all — which is what (C) forbids. It MUST be a predicate (exit status) and not a
# variable the resolver assigns: callers read the set through `$(publish_declared_remotes …)`,
# a command substitution, i.e. a SUBSHELL that discards any global the function set.
( set +u
  # shellcheck source=../relay/scripts/lib-publish-remote.sh
  . "$LIB_PUB"
  export RELAY_PUBLISH_TOML="$TMP/absent-relay.toml"
  s1="$(publish_declared_remotes somerepo)"
  f1=floored; publish_remotes_floored somerepo || f1=declared
  printf '[publish]\ndefault_remotes = ["origin"]\n\n[repos.somerepo]\npublish_remotes = ["github"]\n' \
    > "$TMP/declared-relay.toml"
  export RELAY_PUBLISH_TOML="$TMP/declared-relay.toml"
  s2="$(publish_declared_remotes somerepo | tr '\n' ',')"
  f2=floored; publish_remotes_floored somerepo || f2=declared
  # A repo that declares ONLY per-repo ADDITIONS is still floored for `origin` — additions
  # are a union with the global default, they never displace it.
  printf '[repos.somerepo]\npublish_remotes = ["github"]\n' > "$TMP/addonly-relay.toml"
  export RELAY_PUBLISH_TOML="$TMP/addonly-relay.toml"
  f3=floored; publish_remotes_floored somerepo || f3=declared
  printf '%s %s %s %s %s' "$s1" "$f1" "$s2" "$f2" "$f3" > "$TMP/floor-signal"
) || die "(E) sourcing lib-publish-remote.sh failed"
read -r fs1 ff1 fs2 ff2 ff3 < "$TMP/floor-signal"
[[ "$fs1" == origin && "$ff1" == floored ]] \
  && pass "(E) an ABSENT declaration floors to 'origin' AND publish_remotes_floored says so" \
  || fail "(E) absent declaration: set='$fs1' floored='$ff1', expected 'origin' / floored"
[[ "$fs2" == origin,github, && "$ff2" == declared ]] \
  && pass "(E) an EXPLICIT default is honoured and reported NOT floored (additions still union in)" \
  || fail "(E) explicit declaration: set='$fs2' floored='$ff2', expected 'origin,github,' / declared"
[[ "$ff3" == floored ]] \
  && pass "(E) per-repo ADDITIONS alone leave the set FLOORED — an addition never displaces the global default" \
  || fail "(E) additions-only declaration reported '$ff3', expected floored. `origin` there is still an ASSUMPTION and must be proven private."

# ======================================================================================
if [[ $FAILS -eq 0 ]]; then
  echo "ALL PASS: the do-publish floor is gated on the private-remote predicate (id:c82a)"
  exit 0
fi
echo "FAILED: $FAILS assertion(s) — id:c82a"
exit 1
