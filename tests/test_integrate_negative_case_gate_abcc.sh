#!/usr/bin/env bash
# id:abcc -- integrate.sh step 3d: the NEGATIVE-CASE gate.
#
# Defect-fix test, no roadmap item: the gate closes a gap that produced a vacuous
# negative-case declaration in three consecutive reviews. The id:a73c tier is opt-in and
# deliberately NOT part of `make test`, so an executor runs `make test`, sees green, and
# truthfully reports it ran everything while its own new declaration demonstrates no
# killing power. Restating the tier in executor PROSE is the id:d35a silent-no-op mode;
# a mechanical pre-merge gate on the integrator is not.
#
# fails-against-mutation: python3 -c "import io; p='relay/scripts/integrate.sh'; s=io.open(p,encoding='utf-8').read(); n=s.replace('verify-negative-cases.py}','DISABLED-BY-MUTATION.py}'); assert n != s, 'mutation matched nothing'; io.open(p,'w',encoding='utf-8').write(n)"
# fails-against-assertion: (C) verifier ran but was NOT given --changed <canonical main HEAD>
#
# THE MUTATION COMMAND DELIBERATELY CONTAINS NO `$`. The runner hands the remainder of that
# line to `bash -c`, so a needle spelled with the real `${VERIFY_NEGATIVES_OVERRIDE:-$worktree
# /tests/...}` text is expanded by bash BEFORE python ever sees it, the pattern then matches
# nothing, and the case is reported as a mutation failure. Do not "restore" the parameter
# expansion into the needle; anchor on the `$`-free tail instead.
#
# REACHABILITY NOTE: the mutation renames the default verifier basename, so the gate can
# never find one and takes its structural no-op branch for EVERY case. (A) then merges
# instead of handing
# back and (B) is unaffected, but the LAST assertion to fire is (C)'s -- the verifier is
# never invoked, so it records no argv and the base-is-iso_base check is the final FAIL
# line. That is the assertion declared above, per the last-fired rule.
#
# Cases:
#   (A) worktree carries a verifier that exits NON-ZERO -> HANDBACK[verify-negatives],
#       handbackCode=38, landed=false, and main is BYTE-IDENTICAL (pre-land).
#   (B) worktree carries NO verifier                    -> structural no-op, merge proceeds.
#   (C) worktree carries a verifier that exits 0        -> merge proceeds, AND the verifier
#       was invoked with --root <worktree> --changed <the canonical checkout's PRE-MERGE
#       HEAD>, i.e. the id:8739 iso_base and never `origin/main`.
set -uo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INT="${INT_OVERRIDE:-$SRC_DIR/relay/scripts/integrate.sh}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ERRLOG="$TMP/integrate.stderr"
: >"$ERRLOG"
rcode=0
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; rcode=1; }

[[ -x "$INT" ]] || { echo "FAIL: integrate.sh not found/executable at $INT"; exit 1; }

PUSH_STUB="$TMP/push-stub.sh"
cat > "$PUSH_STUB" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$PUSH_STUB"

build() { # <suffix> -> prints the main checkout path
  local sfx="$1" origin seed main
  origin="$TMP/o-$sfx.git"; seed="$TMP/s-$sfx"; main="$TMP/m-$sfx"
  git init --bare -b main -q "$origin"
  git clone -q "$origin" "$seed" 2>/dev/null
  git -C "$seed" config user.email t@e.st
  git -C "$seed" config user.name t
  echo base > "$seed/f"
  printf '# Roadmap\n\n- [ ] [ROUTINE] the worked item <!-- id:aaaa -->\n' > "$seed/ROADMAP.md"
  git -C "$seed" add -A
  git -C "$seed" commit -qm base
  git -C "$seed" push -q -u origin main
  git clone -q "$origin" "$main" 2>/dev/null
  git -C "$main" config user.email t@e.st
  git -C "$main" config user.name t
  printf '%s' "$main"
}

# <main> <name> <verifier-exit|none> -> prints the worktree path.
# The verifier is a real file in the CHILD's worktree, so the default resolution path
# ($worktree/tests/verify-negative-cases.py) is what gets exercised, not the env override.
child() {
  local main="$1" name="$2" mode="$3"
  local wt="$TMP/wt-$name"
  git -C "$main" worktree add -q -b "relay/$name" "$wt" main
  echo "work-$name" > "$wt/g-$name"
  if [[ "$mode" != none ]]; then
    mkdir -p "$wt/tests"
    cat > "$wt/tests/verify-negative-cases.py" <<PYEOF
#!/usr/bin/env python3
import sys
open("$TMP/argv-$name.txt", "w").write("\n".join(sys.argv[1:]))
print("stub verifier ($name): exiting $mode")
sys.exit($mode)
PYEOF
    chmod +x "$wt/tests/verify-negative-cases.py"
  fi
  git -C "$wt" add -A
  git -C "$wt" commit -qm "child work $name"
  printf '%s' "$wt"
}

cfg() { # <suffix> <repo-name> -> prints the config dir
  local d="$TMP/cfg-$1"
  mkdir -p "$d"
  printf '[repos.%s]\nstatus = "active"\n' "$2" > "$d/relay.toml"
  printf '%s' "$d"
}

run_integrate() { # <main> <worktree> <branch> <cfg> -> prints integrate stdout
  local main="$1" wt="$2" br="$3" c="$4" repo
  repo="$(basename "$main")"
  FABLES_CONFIG="$c" INTEGRATE_GIT_LOCK_PUSH="$PUSH_STUB" \
    "$INT" --repo "$repo" --path "$main" --worktree "$wt" --branch "$br" \
           --summary "close aaaa" --run r1 --label "executor (sonnet, relay-loop)" \
           --ids aaaa --verdict execute --substantive true 2>>"$ERRLOG"
}

# =====================================================================================
# (A) verifier exits NON-ZERO -> loud handback, code 38, main unmoved
# =====================================================================================
MA="$(build red)"; CA="$(cfg red "$(basename "$MA")")"
WA="$(child "$MA" red 1)"
before_a="$(git -C "$MA" rev-parse HEAD)"
outA="$(run_integrate "$MA" "$WA" relay/red "$CA")"
after_a="$(git -C "$MA" rev-parse HEAD)"

grep -q '^handback=verify-negatives$' <<<"$outA" \
  || fail "(A) a RED verifier did not hand back at verify-negatives; stdout was: $outA"
grep -q '^handbackCode=38$' <<<"$outA" \
  || fail "(A) handbackCode is not 38; stdout was: $outA"
grep -q '^landed=false$' <<<"$outA" \
  || fail "(A) the gate handback is not reported as PRE-LAND (landed=false); stdout was: $outA"
[[ "$before_a" == "$after_a" ]] \
  || fail "(A) main MOVED on a gate handback ($before_a -> $after_a) -- the gate must run BEFORE the merge"
[[ -d "$WA" ]] || fail "(A) the worktree was retired on a pre-land handback; it must stay on disk"

# =====================================================================================
# (B) no verifier in the repo -> structural no-op, merge proceeds
# =====================================================================================
MB="$(build absent)"; CB="$(cfg absent "$(basename "$MB")")"
WB="$(child "$MB" absent none)"
before_b="$(git -C "$MB" rev-parse HEAD)"
outB="$(run_integrate "$MB" "$WB" relay/absent "$CB")"
after_b="$(git -C "$MB" rev-parse HEAD)"

grep -q '^handback=' <<<"$outB" \
  && fail "(B) a repo carrying NO verify-negative-cases.py was handed back -- the no-op must be structural; stdout was: $outB"
[[ "$before_b" != "$after_b" ]] \
  || fail "(B) main did not move -- the merge did not proceed for a repo without the tier"

# =====================================================================================
# (C) verifier exits 0 -> merge proceeds, and it was given --changed <iso_base>
# =====================================================================================
MC="$(build green)"; CC="$(cfg green "$(basename "$MC")")"
WC="$(child "$MC" green 0)"
before_c="$(git -C "$MC" rev-parse HEAD)"
outC="$(run_integrate "$MC" "$WC" relay/green "$CC")"
after_c="$(git -C "$MC" rev-parse HEAD)"

grep -q '^handback=' <<<"$outC" \
  && fail "(C) a GREEN verifier still handed back; stdout was: $outC"
[[ "$before_c" != "$after_c" ]] \
  || fail "(C) main did not move -- a passing gate must not block the merge"

argv=""
[[ -f "$TMP/argv-green.txt" ]] && argv="$(cat "$TMP/argv-green.txt")"
[[ "$argv" == *"--root"* && "$argv" == *"$WC"* ]] \
  || fail "(C) verifier was not given --root <worktree> (argv: ${argv//$'\n'/ })"
# THE load-bearing assertion: the base is the canonical checkout's PRE-MERGE HEAD (the
# id:8739 iso_base), never `origin/main` -- which the id:4d44 ratification gate freezes, so
# it drifts behind and would silently widen the diff to the whole unratified backlog.
[[ "$argv" == *"--changed"$'\n'"$before_c"* ]] \
  || fail "(C) verifier ran but was NOT given --changed <canonical main HEAD> ($before_c); argv: ${argv//$'\n'/ }"

if [[ $rcode -eq 0 ]]; then
  pass "id:abcc -- integrate.sh step 3d gates on the negative-case tier: red verifier hands back pre-land (code 38), an absent verifier is a structural no-op, and a green one runs with --changed <iso_base>"
else
  [[ -s "$ERRLOG" ]] && { echo "       last integrate.sh stderr:"; tail -n 30 "$ERRLOG" | sed 's/^/       | /'; }
fi
exit $rcode
