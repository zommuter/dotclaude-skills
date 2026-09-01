#!/usr/bin/env bash
# TODO id:a290 shape (b) -- the NARROW submodule escape hatch in worktree-retire.sh.
#
# NO `# roadmap:` header ON PURPOSE: id:a290 lives in TODO.md only and has NO ROADMAP twin
# (`grep -n 'id:a290' ROADMAP.md` finds nothing), so there is no checkbox for the harness's
# EXPECTED-RED rule to consult. Per CLAUDE.md §Testing a header-less file's failures always
# count -- which is what we want: this guards a force op.
#
# fails-against: relay/scripts/worktree-retire.sh before the id:a290 submodule escape hatch
#   (every submodule worktree took the `retire-unretirable` exit-3 path, so case (a) below
#   failed with rc=3 and no `submodule-force-hatch` marker on stdout).
#
# fails-against-mutation: bash tests/mutations/a290-strip-locale-pin.sh
# fails-against-assertion: L non-C locale: expected exit 0 (hatch fires regardless of locale)
#   (without the pin the probe misses the translated refusal and L's FIRST assertion -- its
#    exit code -- is what fires. Measured; a spelling naming L's *message* line instead was
#    REJECTED by the runner as WRONG REASON, which is correct.
#    NARROWED 2026-09-01: the declaration used to read just `L non-C locale:`, which matched
#    FOUR assertion lines (494/496/498/499) -- a bare case prefix cannot say WHICH of a case's
#    assertions fired, and the runner now refuses such a declaration as a CONFIG ERROR. It
#    names line 494 exactly, and nothing else.)
#   REACHABILITY: this mutant is killed ONLY by case L, and only on a box whose git ships a
#   German translation -- case L SKIPS loudly otherwise and the runner will then report WRONG
#   REASON rather than a silent pass. That loudness is deliberate: it is the same environment
#   dependence that let a fixture-sanity probe, not case L, kill this mutant on the first
#   attempt (TODO id:a73c instance (b)). Verified killing on zomni, git 2.55.0, 2026-09-01.
#
# WHAT IS BEING GUARDED, and why each case exists
# -----------------------------------------------
# `git worktree remove` (no --force) refuses a worktree whose submodules are INITIALIZED, with
#   fatal: working trees containing submodules cannot be moved or removed
# (verbatim, git 2.55.0). The hatch force-removes such a worktree, but ONLY when the script has
# itself PROVED clean + merged and has POSITIVELY RECOGNIZED that exact refusal.
#
# Two empirical facts from the 2026-09-01 fixture drive the design, and each has a case here:
#
#  * `roadmap:b02f`'s "git keys the refusal on .gitmodules being in the tree" is WRONG. A
#    worktree with .gitmodules present but the submodule NEVER INITIALIZED removes cleanly
#    (case E). The refusal appears only once the submodule is populated and SURVIVES
#    `git submodule deinit` even with the gitlink directory gone -- `.git/worktrees/<wt>/modules/<path>`
#    persists and is what git actually tests. So the hatch must never infer "submodule" from
#    `.gitmodules`; it must match git's refusal text.
#
#  * The submodule refusal MASKS the dirty refusal -- git validates submodules BEFORE it checks
#    for modified/untracked files, so a DIRTY submodule worktree emits the SAME message as a
#    clean one (case B). Therefore recognizing the refusal is NOT evidence the tree is clean,
#    and the hatch must run its OWN clean check. That is the whole reason case B exists.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SH="$SRC_DIR/relay/scripts/worktree-retire.sh"

# The hatch is OPT-IN since the owner's 2026-09-01 reversal (round-3 review: a dangling submodule
# object orphaned by an amended commit is invisible to the guard yet still named by MERGED
# superproject history). This file EXERCISES the hatch, so it opts in explicitly for every case
# below; case H0 asserts the PRODUCTION default -- env unset -- is inert. Exporting here rather
# than per-invocation keeps each case's assertion about the guard it is actually testing, and case
# H still overrides with the hard kill-switch to prove that one WINS.
export WORKTREE_RETIRE_SUBMODULE_FORCE=1

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SH" ]] || fail "worktree-retire.sh not found/executable at $SH"

export WORKTREE_RETIRE_LOG=/dev/null
# Pin the harness's OWN locale so every fixture probe below is deterministic. Case L overrides
# this per-invocation with de_DE.utf8 -- that is the ONE place a non-C locale is exercised, and
# pinning here is what makes case L the thing that kills the "LC_ALL=C stripped" mutant instead
# of some fixture-sanity probe firing first and masking it (mutation-verified 2026-09-01).
export LC_ALL=C
# Hermetic: no user/system git config, no network, deterministic identity.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@e
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@e

TMP="$(mktemp -d)"; trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT

# The submodule "remote" is a plain local repo on disk -- never the network.
SUB="$TMP/sub-remote"
git init -q -b main "$SUB"
printf 'sub content\n' > "$SUB/f.txt"
git -C "$SUB" add -A
git -C "$SUB" commit -qm "sub init"

# A NESTED submodule "remote": $NESTED itself carries $INNER at lib/inner. Used by the cases
# that exercise private submodule stores which NEST (.../modules/vendor/sub/modules/lib/inner).
INNER="$TMP/inner-remote"
git init -q -b main "$INNER"
printf 'inner content\n' > "$INNER/i.txt"
git -C "$INNER" add -A
git -C "$INNER" commit -qm "inner init"
NESTED="$TMP/nested-remote"
git init -q -b main "$NESTED"
printf 'outer content\n' > "$NESTED/o.txt"
git -C "$NESTED" add -A
git -C "$NESTED" commit -qm "outer init"
git -C "$NESTED" -c protocol.file.allow=always submodule add -q "$INNER" lib/inner >/dev/null 2>&1 \
  || fail "fixture: nested submodule add failed in $NESTED"
git -C "$NESTED" commit -qm "add inner submodule"

# mksuper <name> [--with-submodule|--with-nested] → $TMP/<name>, a superproject on main
mksuper() {
  local n="$1" repo="$TMP/$1" url=""
  git init -q -b main "$repo"
  printf 'base\n' > "$repo/base.txt"
  git -C "$repo" add -A
  git -C "$repo" commit -qm init
  case "${2:-}" in
    --with-submodule) url="$SUB" ;;
    --with-nested)    url="$NESTED" ;;
    "") ;;
    *) fail "mksuper: unknown option '${2:-}'" ;;
  esac
  if [[ -n "$url" ]]; then
    # protocol.file.allow: git refuses file:// submodules by default (CVE-2022-39253).
    git -C "$repo" -c protocol.file.allow=always submodule add -q "$url" vendor/sub >/dev/null 2>&1 \
      || fail "fixture: submodule add failed in $repo"
    git -C "$repo" commit -qm "add submodule"
    # Populate the MAIN checkout too, so the SHARED store exists and is the baseline every
    # "objects are duplicated" assertion below is measured against.
    git -C "$repo" -c protocol.file.allow=always submodule update --init --recursive >/dev/null 2>&1 \
      || fail "fixture: superproject submodule update --init --recursive failed in $repo"
  fi
  printf '%s' "$repo"
}

# mkwt <repo> <name> [--init-submodule|--init-recursive] → worktree $TMP/wt-<name> on relay/<name>
mkwt() {
  local repo="$1" n="$2" wt="$TMP/wt-$2"
  git -C "$repo" worktree add -q "$wt" -b "relay/$n"
  case "${3:-}" in
    --init-submodule)
      git -C "$wt" -c protocol.file.allow=always submodule update --init >/dev/null 2>&1 \
        || fail "fixture: submodule update --init failed in $wt"
      [[ -e "$wt/vendor/sub" ]] || fail "fixture: submodule not populated in $wt"
      ;;
    --init-recursive)
      git -C "$wt" -c protocol.file.allow=always submodule update --init --recursive >/dev/null 2>&1 \
        || fail "fixture: submodule update --init --recursive failed in $wt"
      [[ -f "$wt/vendor/sub/lib/inner/i.txt" ]] || fail "fixture: nested submodule not populated in $wt"
      ;;
    "") ;;
    *) fail "mkwt: unknown option '${3:-}'" ;;
  esac
  printf '%s' "$wt"
}

# ── FIXTURE SANITY (positive controls for the fixture itself) ────────────────
# Without these, every "not force-removed" case below could pass vacuously -- e.g. because the
# fixture never actually produced a submodule refusal in the first place.
sanity_repo="$(mksuper sanity --with-submodule)"
sanity_wt="$(mkwt "$sanity_repo" sanity --init-submodule)"
[[ -z "$(git -C "$sanity_wt" status --porcelain)" ]] || fail "fixture: sanity worktree should be clean"
set +e
sanity_err="$(git -C "$sanity_repo" worktree remove "$sanity_wt" 2>&1)"; sanity_rc=$?
set -e
[[ $sanity_rc -ne 0 ]] || fail "fixture INVALID: git removed a populated-submodule worktree without --force (rc=0) -- the refusal this hatch keys on does not occur here, so every case below would be vacuous"
[[ "$sanity_err" == *"containing submodules cannot be moved or removed"* ]] \
  || fail "fixture INVALID: expected git's submodule refusal, got: $sanity_err"
pass "fixture control: git DOES refuse a populated-submodule worktree (rc=$sanity_rc: ${sanity_err//$'\n'/ })"

# ── A. clean + merged submodule worktree → HATCH FIRES, worktree gone, branch deleted ──
repo_a="$(mksuper a --with-submodule)"
wt_a="$(mkwt "$repo_a" a --init-submodule)"
set +e
out_a="$("$SH" "$repo_a" "$wt_a" "relay/a" --expect-merged 2>&1)"; rc_a=$?
set -e
[[ $rc_a -eq 0 ]] || fail "A clean+merged submodule: expected exit 0, got $rc_a -- out: $out_a"
[[ "$out_a" == *"submodule-force-hatch"* ]] \
  || fail "A clean+merged submodule: stdout must name the hatch so a force is never silent -- out: $out_a"
[[ ! -e "$wt_a" ]] || fail "A clean+merged submodule: worktree dir should be gone"
git -C "$repo_a" show-ref --verify --quiet refs/heads/relay/a \
  && fail "A clean+merged submodule: branch relay/a should be deleted"
grep -q "$wt_a" < <(git -C "$repo_a" worktree list --porcelain) \
  && fail "A clean+merged submodule: admin entry should be gone from 'worktree list'"
pass "A clean+merged submodule worktree → force-removed via the hatch, branch deleted ($out_a)"

# ── B. DIRTY submodule worktree → NOT force-removed (the masking case) ──────
# git emits the IDENTICAL submodule refusal here as in case A. Only the script's own clean
# check can tell them apart, so this is the case that proves the hatch is not just
# string-matching its way into a blind force.
repo_b="$(mksuper b --with-submodule)"
wt_b="$(mkwt "$repo_b" b --init-submodule)"
printf 'uncommitted real source\n' > "$wt_b/realsource.py"
set +e
out_b="$("$SH" "$repo_b" "$wt_b" "relay/b" 2>&1)"; rc_b=$?
set -e
[[ $rc_b -eq 3 ]] || fail "B dirty submodule: expected exit 3 (surface+leave), got $rc_b -- out: $out_b"
[[ "$out_b" != *"submodule-force-hatch"* ]] \
  || fail "B dirty submodule: the hatch MUST NOT fire on a dirty tree -- out: $out_b"
[[ -e "$wt_b" ]] || fail "B dirty submodule: worktree must still be on disk"
[[ -f "$wt_b/realsource.py" ]] || fail "B dirty submodule: uncommitted file must survive"
git -C "$repo_b" show-ref --verify --quiet refs/heads/relay/b \
  || fail "B dirty submodule: branch must be untouched"
pass "B DIRTY submodule worktree → hatch refused, nothing forced, residue intact ($out_b)"

# ── B2. submodule worktree dirty only INSIDE the submodule → NOT force-removed ──
# The superproject tree itself has no loose files; only the submodule's checkout is modified.
repo_b2="$(mksuper b2 --with-submodule)"
wt_b2="$(mkwt "$repo_b2" b2 --init-submodule)"
printf 'edited in submodule\n' >> "$wt_b2/vendor/sub/f.txt"
set +e
out_b2="$("$SH" "$repo_b2" "$wt_b2" "relay/b2" 2>&1)"; rc_b2=$?
set -e
[[ $rc_b2 -eq 3 ]] || fail "B2 submodule-internal dirt: expected exit 3, got $rc_b2 -- out: $out_b2"
[[ "$out_b2" != *"submodule-force-hatch"* ]] \
  || fail "B2 submodule-internal dirt: hatch MUST NOT fire -- out: $out_b2"
[[ -e "$wt_b2/vendor/sub/f.txt" ]] || fail "B2: submodule content must survive"
grep -q 'edited in submodule' "$wt_b2/vendor/sub/f.txt" \
  || fail "B2: the submodule-internal edit must survive untouched"
pass "B2 dirt INSIDE the submodule → hatch refused, edit intact ($out_b2)"

# ── C. UNMERGED submodule worktree → NOT force-removed ──────────────────────
repo_c="$(mksuper c --with-submodule)"
wt_c="$(mkwt "$repo_c" c --init-submodule)"
printf 'real work\n' > "$wt_c/work.txt"
git -C "$wt_c" add work.txt
git -C "$wt_c" commit -qm "unmerged work"
[[ -z "$(git -C "$wt_c" status --porcelain)" ]] || fail "fixture C: worktree should be clean after commit"
git -C "$repo_c" merge-base --is-ancestor "refs/heads/relay/c" HEAD \
  && fail "fixture C INVALID: relay/c is already merged, so this is not an unmerged case"
set +e
out_c="$("$SH" "$repo_c" "$wt_c" "relay/c" 2>&1)"; rc_c=$?
set -e
[[ $rc_c -eq 3 ]] || fail "C unmerged submodule: expected exit 3, got $rc_c -- out: $out_c"
[[ "$out_c" != *"submodule-force-hatch"* ]] \
  || fail "C unmerged submodule: the hatch MUST NOT fire on unmerged work -- out: $out_c"
[[ -e "$wt_c" ]] || fail "C unmerged submodule: worktree must still be on disk"
git -C "$repo_c" show-ref --verify --quiet refs/heads/relay/c \
  || fail "C unmerged submodule: branch must be untouched"
grep -q "unmerged work" < <(git -C "$repo_c" log --format=%s -1 "refs/heads/relay/c") \
  || fail "C unmerged submodule: the unmerged commit must still be reachable"
pass "C UNMERGED submodule worktree → hatch refused, commit preserved ($out_c)"

# ── D. refusal for some OTHER reason → NOT force-removed, fails loudly ──────
# A LOCKED worktree, no submodule anywhere. git's refusal text is the lock message, which the
# hatch must not recognize. (Empirically git checks the lock BEFORE submodules, and a single
# --force cannot override a lock -- `remove -f -f` is required -- so this is doubly guarded.)
repo_d="$(mksuper d)"
wt_d="$(mkwt "$repo_d" d)"
git -C "$repo_d" worktree lock "$wt_d"
set +e
out_d="$("$SH" "$repo_d" "$wt_d" "relay/d" --expect-merged 2>&1)"; rc_d=$?
set -e
[[ $rc_d -eq 3 ]] || fail "D other-reason refusal: expected exit 3, got $rc_d -- out: $out_d"
[[ "$out_d" != *"submodule-force-hatch"* ]] \
  || fail "D other-reason refusal: hatch MUST NOT fire -- out: $out_d"
[[ -e "$wt_d" ]] || fail "D other-reason refusal: worktree must still be on disk"
[[ -n "$out_d" ]] || fail "D other-reason refusal: must report loudly, printed nothing"
[[ "$out_d" == *"locked"* ]] || fail "D other-reason refusal: report must quote git's reason -- out: $out_d"
git -C "$repo_d" show-ref --verify --quiet refs/heads/relay/d \
  || fail "D other-reason refusal: branch must be untouched"
pass "D locked (non-submodule) worktree → not forced, exit 3, loud ($out_d)"

# ── D2. locked AND populated-submodule worktree → still NOT force-removed ───
# Belt and braces: even with a real submodule present, an unrecognized refusal wins.
repo_d2="$(mksuper d2 --with-submodule)"
wt_d2="$(mkwt "$repo_d2" d2 --init-submodule)"
git -C "$repo_d2" worktree lock "$wt_d2"
set +e
out_d2="$("$SH" "$repo_d2" "$wt_d2" "relay/d2" --expect-merged 2>&1)"; rc_d2=$?
set -e
[[ $rc_d2 -eq 3 ]] || fail "D2 locked+submodule: expected exit 3, got $rc_d2 -- out: $out_d2"
[[ "$out_d2" != *"submodule-force-hatch"* ]] \
  || fail "D2 locked+submodule: hatch MUST NOT fire on an unrecognized refusal -- out: $out_d2"
[[ -e "$wt_d2" ]] || fail "D2 locked+submodule: worktree must still be on disk"
pass "D2 locked + populated submodule → unrecognized refusal wins, not forced ($out_d2)"

# ── E. UNINITIALIZED submodule → removes FORCE-FREE, hatch never involved ──
# .gitmodules IS in the tree and the gitlink IS in the index, but nothing is populated. This
# is the case that refutes roadmap:b02f's documented mechanism, and it must keep taking the
# plain no-force path.
repo_e="$(mksuper e --with-submodule)"
wt_e="$(mkwt "$repo_e" e)"   # deliberately NOT --init-submodule
[[ -f "$wt_e/.gitmodules" ]] || fail "fixture E: .gitmodules must be present in the worktree"
[[ ! -e "$wt_e/vendor/sub/f.txt" ]] || fail "fixture E: submodule must NOT be populated"
set +e
out_e="$("$SH" "$repo_e" "$wt_e" "relay/e" --expect-merged 2>&1)"; rc_e=$?
set -e
[[ $rc_e -eq 0 ]] || fail "E uninitialized submodule: expected exit 0, got $rc_e -- out: $out_e"
[[ "$out_e" != *"submodule-force-hatch"* ]] \
  || fail "E uninitialized submodule: must remove FORCE-FREE -- the hatch must not fire -- out: $out_e"
[[ ! -e "$wt_e" ]] || fail "E uninitialized submodule: worktree dir should be gone"
git -C "$repo_e" show-ref --verify --quiet refs/heads/relay/e \
  && fail "E uninitialized submodule: branch relay/e should be deleted"
pass "E .gitmodules present but submodule UNINITIALIZED → removed force-free, hatch idle ($out_e)"

# ── F. no submodule at all, clean + merged → unchanged force-free behaviour ──
repo_f="$(mksuper f)"
wt_f="$(mkwt "$repo_f" f)"
set +e
out_f="$("$SH" "$repo_f" "$wt_f" "relay/f" --expect-merged 2>&1)"; rc_f=$?
set -e
[[ $rc_f -eq 0 ]] || fail "F plain clean+merged: expected exit 0, got $rc_f -- out: $out_f"
[[ "$out_f" != *"submodule-force-hatch"* ]] || fail "F plain clean+merged: hatch must be idle -- out: $out_f"
[[ ! -e "$wt_f" ]] || fail "F plain clean+merged: worktree dir should be gone"
pass "F plain clean+merged worktree → unchanged force-free retirement ($out_f)"

# ── G. a submodule refusal with DIFFERENT WORDING → NOT forced (fail closed) ──
# The hatch is only permitted to act on git's refusal VERBATIM. This case simulates a future
# git whose wording changed, via a PATH shim that answers the no-force `worktree remove` with a
# near-miss message and delegates everything else (including `--force`) to the real git -- so if
# the hatch wrongly fired, the worktree really would be removed and this test would see it.
# Without this case, loosening the match to a substring passes the whole file (verified).
REAL_GIT="$(command -v git)"
SHIM="$TMP/shim"
mkdir -p "$SHIM"
cat > "$SHIM/git" <<SHIMEOF
#!/usr/bin/env bash
# Intercept ONLY a no-force 'worktree remove'; everything else is the real git.
saw_wt=0; saw_rm=0; saw_force=0
for a in "\$@"; do
  case "\$a" in
    worktree) saw_wt=1 ;;
    remove) saw_rm=1 ;;
    --force|-f) saw_force=1 ;;
  esac
done
if [[ \$saw_wt -eq 1 && \$saw_rm -eq 1 && \$saw_force -eq 0 ]]; then
  echo "fatal: working trees containing submodules cannot be removed or moved" >&2
  exit 128
fi
exec "$REAL_GIT" "\$@"
SHIMEOF
chmod +x "$SHIM/git"
repo_g="$(mksuper g --with-submodule)"
wt_g="$(mkwt "$repo_g" g --init-submodule)"
set +e
out_g="$(PATH="$SHIM:$PATH" "$SH" "$repo_g" "$wt_g" "relay/g" --expect-merged 2>&1)"; rc_g=$?
set -e
[[ $rc_g -eq 3 ]] || fail "G reworded submodule refusal: expected exit 3 (fail closed), got $rc_g -- out: $out_g"
[[ "$out_g" != *"submodule-force-hatch"* ]] \
  || fail "G reworded submodule refusal: hatch MUST NOT fire on a refusal it does not recognize VERBATIM -- out: $out_g"
[[ -e "$wt_g" ]] || fail "G reworded submodule refusal: worktree must still be on disk (it was forced away)"
[[ "$out_g" == *"unrecognized"* || "$out_g" == *"NOT the verbatim form"* ]] \
  || fail "G reworded submodule refusal: must say loudly WHY it refused -- out: $out_g"
pass "G submodule refusal with different wording → fail closed, not forced ($out_g)"

# ── G2. a refusal that CONTAINS the verbatim string plus MORE → NOT forced ──
# THE SUBSTRING-MUTANT KILLER (added 2026-09-01, round-4 review). Case G only varies the WORDING,
# so relaxing the match from equality to a substring test
#   -  if [[ "$err" == "$submodule_refusal" ]]
#   +  if [[ "$err" == *"$submodule_refusal"* ]]
# survived the ENTIRE suite -- G's reworded text contains no substring match either way. The
# comment at the match site says in so many words "never loosen it to a substring"; nothing
# enforced it. The hazard is concrete and near: a future git that appends a hint line after the
# same fatal: line ("hint: use --force to override") would flip this hatch from FAIL-CLOSED to
# FIRING on a refusal nobody has characterised. Note the hint below is emitted on the SAME stderr
# the script captures with 2>&1, so it lands in "$err" exactly as a real git's would.
SHIM2="$TMP/shim-superset"
mkdir -p "$SHIM2"
cat > "$SHIM2/git" <<SHIM2EOF
#!/usr/bin/env bash
# Intercept ONLY a no-force 'worktree remove': emit the VERBATIM refusal plus a trailing hint,
# the way a future git version plausibly would. Everything else is the real git.
saw_wt=0; saw_rm=0; saw_force=0
for a in "\$@"; do
  case "\$a" in
    worktree) saw_wt=1 ;;
    remove) saw_rm=1 ;;
    --force|-f) saw_force=1 ;;
  esac
done
if [[ \$saw_wt -eq 1 && \$saw_rm -eq 1 && \$saw_force -eq 0 ]]; then
  echo "fatal: working trees containing submodules cannot be moved or removed" >&2
  echo "hint: use 'git worktree remove --force' to override" >&2
  exit 128
fi
exec "$REAL_GIT" "\$@"
SHIM2EOF
chmod +x "$SHIM2/git"
repo_g2="$(mksuper g2 --with-submodule)"
wt_g2="$(mkwt "$repo_g2" g2 --init-submodule)"
# Fixture sanity: guards 2/3/4 all PASS here, so the ONLY thing standing between this fixture and
# a real force is the string comparison. Without this, a green result could mean "some other guard
# refused" rather than "the match is still exact".
[[ "$(git -C "$wt_g2" symbolic-ref --quiet HEAD)" == "refs/heads/relay/g2" ]] || fail "fixture G2 INVALID: guard 2 would fire"
[[ -z "$(git -C "$wt_g2" status --porcelain --ignore-submodules=none)" ]] || fail "fixture G2 INVALID: guard 3 would fire"
git -C "$repo_g2" merge-base --is-ancestor "refs/heads/relay/g2" HEAD || fail "fixture G2 INVALID: guard 4 would fire"
set +e
out_g2="$(PATH="$SHIM2:$PATH" "$SH" "$repo_g2" "$wt_g2" "relay/g2" --expect-merged 2>&1)"; rc_g2=$?
set -e
[[ $rc_g2 -eq 3 ]] || fail "G2 refusal + trailing hint: expected exit 3 (fail closed), got $rc_g2 -- out: $out_g2"
[[ "$out_g2" != *"submodule-force-hatch"* ]] \
  || fail "G2 refusal + trailing hint: the hatch fired on a refusal that merely CONTAINS the recognized string -- the match has been loosened to a substring, which the code forbids -- out: $out_g2"
[[ -e "$wt_g2" ]] || fail "G2 refusal + trailing hint: worktree was force-removed; the match is no longer exact"
[[ "$out_g2" == *"NOT the verbatim form"* ]] \
  || fail "G2 refusal + trailing hint: must refuse with the unrecognized-refusal reason -- out: $out_g2"
pass "G2 refusal CONTAINING the verbatim string + extra text → unrecognized, fail closed ($out_g2)"

# ── H0. PRODUCTION DEFAULT (opt-in UNSET) → hatch inert ────────────────────
# The case that pins the owner's 2026-09-01 reversal. Every OTHER case in this file exports
# WORKTREE_RETIRE_SUBMODULE_FORCE=1, so without this one the file could go fully green while the
# shipped default silently flipped back to firing. `env -u` unsets it for this invocation only.
repo_h0="$(mksuper h0 --with-submodule)"
wt_h0="$(mkwt "$repo_h0" h0 --init-submodule)"
set +e
out_h0="$(env -u WORKTREE_RETIRE_SUBMODULE_FORCE "$SH" "$repo_h0" "$wt_h0" "relay/h0" --expect-merged 2>&1)"; rc_h0=$?
set -e
[[ $rc_h0 -eq 3 ]] || fail "H0 default-inert: expected exit 3, got $rc_h0 -- out: $out_h0"
[[ "$out_h0" != *"submodule-force-hatch"* ]] \
  || fail "H0 default-inert: the hatch FIRED with the opt-in unset -- the production default must be inert -- out: $out_h0"
[[ -e "$wt_h0" ]] || fail "H0 default-inert: worktree must still be on disk"
[[ "$out_h0" == *"OPT-IN"* && "$out_h0" == *"WORKTREE_RETIRE_SUBMODULE_FORCE=1 is not set"* ]] \
  || fail "H0 default-inert: must say it is opt-in and unset -- out: $out_h0"
pass "H0 production default (opt-in unset) → hatch inert, force-free behaviour, says why"

# ── H. WORKTREE_RETIRE_NO_SUBMODULE_FORCE=1 disables the hatch entirely ─────
# Still meaningful under opt-in: the hard kill-switch must WIN over an explicit enable, so a
# caller or doc that sets NO_ can never be silently upgraded into an enable.
repo_h="$(mksuper h --with-submodule)"
wt_h="$(mkwt "$repo_h" h --init-submodule)"
set +e
out_h="$(WORKTREE_RETIRE_NO_SUBMODULE_FORCE=1 "$SH" "$repo_h" "$wt_h" "relay/h" --expect-merged 2>&1)"; rc_h=$?
set -e
[[ $rc_h -eq 3 ]] || fail "H hatch disabled: expected exit 3, got $rc_h -- out: $out_h"
[[ "$out_h" != *"submodule-force-hatch"* ]] || fail "H hatch disabled: must not fire -- out: $out_h"
[[ -e "$wt_h" ]] || fail "H hatch disabled: worktree must still be on disk"
[[ "$out_h" == *"disabled by WORKTREE_RETIRE_NO_SUBMODULE_FORCE=1"* ]] \
  || fail "H hatch disabled: must say it was disabled by the env override -- out: $out_h"
pass "H WORKTREE_RETIRE_NO_SUBMODULE_FORCE=1 → hatch off, force-free behaviour restored ($out_h)"

# ── I. DETACHED HEAD carrying an unreferenced commit → NOT force-removed ────
# THE GUARD-2 KILLER (added 2026-09-01). Before this case, deleting the HEAD-matches check
# entirely left the whole file green -- the guard survived mutation, i.e. it was untested.
# The killing shape: the worktree is detached and carries a commit NO REF points at, while the
# BRANCH NAME we are handed is genuinely clean+merged. Guards 1/3/4/5 all pass on their own
# terms (the refusal is verbatim, the tree is spotless, relay/i IS an ancestor of HEAD, and no
# gitlink object is worktree-only). Only guard 2 notices that the thing about to be destroyed is
# not the thing that was vouched for -- and removing the worktree makes that commit unreachable.
repo_i="$(mksuper i --with-submodule)"
wt_i="$(mkwt "$repo_i" i --init-submodule)"
git -C "$wt_i" checkout -q --detach
printf 'work that no ref points at\n' > "$wt_i/detached.txt"
git -C "$wt_i" add detached.txt
git -C "$wt_i" commit -qm "detached-head work"
det_sha="$(git -C "$wt_i" rev-parse HEAD)"
# Fixture sanity: the OTHER guards must genuinely pass, or this is not a guard-2 test.
[[ -z "$(git -C "$wt_i" status --porcelain --ignore-submodules=none)" ]] \
  || fail "fixture I INVALID: tree must be clean, else guard 3 does the work instead of guard 2"
git -C "$repo_i" merge-base --is-ancestor "refs/heads/relay/i" HEAD \
  || fail "fixture I INVALID: relay/i must be an ancestor of HEAD, else guard 4 does the work"
[[ -z "$(git -C "$wt_i" symbolic-ref --quiet HEAD 2>/dev/null || true)" ]] \
  || fail "fixture I INVALID: HEAD must actually be detached"
det_containing="$(git -C "$repo_i" branch --contains "$det_sha" 2>/dev/null || true)"
[[ -z "$det_containing" ]] \
  || fail "fixture I INVALID: the detached commit is reachable from branch(es) [$det_containing], so nothing is at risk"
set +e
out_i="$("$SH" "$repo_i" "$wt_i" "relay/i" --expect-merged 2>&1)"; rc_i=$?
set -e
[[ $rc_i -eq 3 ]] || fail "I detached HEAD: expected exit 3, got $rc_i -- out: $out_i"
[[ "$out_i" != *"submodule-force-hatch"* ]] \
  || fail "I detached HEAD: the hatch MUST NOT force a worktree whose HEAD is not the branch it was handed -- out: $out_i"
[[ -e "$wt_i" ]] || fail "I detached HEAD: worktree must still be on disk (the unreferenced commit lives only here)"
[[ "$out_i" == *"detached"* ]] || fail "I detached HEAD: report must name the detached HEAD -- out: $out_i"
pass "I DETACHED-HEAD worktree handed a merged branch name → guard 2 refused, unreferenced commit safe ($out_i)"

# ── J. submodule.<name>.ignore=all + submodule-internal dirt → NOT force-removed ──
# THE GUARD-3 KILLER (added 2026-09-01). Case B2 already covers submodule-internal dirt, but it
# does NOT kill the mutant that drops `--ignore-submodules=none`: by default `status --porcelain`
# ALREADY reports submodule dirt, so B2 stays red-free either way. The flag only earns its place
# when the repo sets `submodule.<name>.ignore = all` -- an ordinary, documented setting. Measured
# here (git 2.55.0): with it set, default porcelain prints NOTHING while `--ignore-submodules=none`
# prints ` M vendor/sub`. So without the flag the mutant sees a "clean" tree and destroys real
# uncommitted content.
repo_j="$(mksuper j --with-submodule)"
wt_j="$(mkwt "$repo_j" j --init-submodule)"
printf 'uncommitted work inside the submodule\n' >> "$wt_j/vendor/sub/f.txt"
git -C "$repo_j" config submodule.vendor/sub.ignore all
# Fixture sanity: the whole point is that the two status spellings DISAGREE here.
[[ -z "$(git -C "$wt_j" status --porcelain)" ]] \
  || fail "fixture J INVALID: default porcelain must show NOTHING under ignore=all, else the mutant would be caught anyway and this case proves nothing"
[[ -n "$(git -C "$wt_j" status --porcelain --ignore-submodules=none)" ]] \
  || fail "fixture J INVALID: --ignore-submodules=none must show the submodule as dirty"
set +e
out_j="$("$SH" "$repo_j" "$wt_j" "relay/j" --expect-merged 2>&1)"; rc_j=$?
set -e
[[ $rc_j -eq 3 ]] || fail "J ignore=all + submodule dirt: expected exit 3, got $rc_j -- out: $out_j"
[[ "$out_j" != *"submodule-force-hatch"* ]] \
  || fail "J ignore=all + submodule dirt: hatch MUST NOT fire -- the clean check has to override submodule.<name>.ignore -- out: $out_j"
[[ -e "$wt_j" ]] || fail "J ignore=all: worktree must still be on disk"
grep -q 'uncommitted work inside the submodule' "$wt_j/vendor/sub/f.txt" \
  || fail "J ignore=all: the submodule-internal edit was destroyed"
pass "J submodule.<name>.ignore=all hiding real dirt → guard 3's --ignore-submodules=none refused it ($out_j)"

# ── K. gitlink object that exists ONLY in the worktree's private store → REFUSED ──
# THE FIFTH GUARD (added 2026-09-01). This is the DATA-LOSS case that all four original guards
# passed. A linked worktree gets its own submodule store at `.git/worktrees/<wt>/modules/<path>`.
# Make a submodule commit INSIDE the worktree, bump the gitlink, merge that bump into the
# superproject -- now HEAD matches, the tree is spotless, the branch IS an ancestor of HEAD, and
# git's refusal is verbatim. `worktree remove --force` then deletes the admin dir with the ONLY
# copy of those objects, and MAIN is left pointing at a gitlink nobody can resolve:
#   fatal: remote error: upload-pack: not our ref <sha>
# Measured verbatim by fixture 2026-09-01 (git 2.55.0) before the guard existed.
repo_k="$(mksuper k --with-submodule)"
wt_k="$(mkwt "$repo_k" k --init-submodule)"
printf 'submodule work done inside the worktree\n' >> "$wt_k/vendor/sub/f.txt"
git -C "$wt_k/vendor/sub" commit -qam "submodule work from the worktree"
sub_sha="$(git -C "$wt_k/vendor/sub" rev-parse HEAD)"
git -C "$wt_k" add vendor/sub
git -C "$wt_k" commit -qm "bump submodule gitlink"
git -C "$repo_k" merge -q --no-ff -m "merge relay/k" relay/k
# Fixture sanity: the objects really are worktree-only, and guards 2/3/4 really do pass.
git --git-dir="$repo_k/.git/modules/vendor/sub" cat-file -e "$sub_sha" 2>/dev/null \
  && fail "fixture K INVALID: the submodule commit is ALREADY in the shared store, so nothing would be lost"
git --git-dir="$repo_k/.git/worktrees/wt-k/modules/vendor/sub" cat-file -e "$sub_sha" 2>/dev/null \
  || fail "fixture K INVALID: the submodule commit is not in the worktree's private store either"
[[ "$(git -C "$repo_k" rev-parse "HEAD:vendor/sub")" == "$sub_sha" ]] \
  || fail "fixture K INVALID: the superproject's MERGED gitlink does not point at the worktree-only commit"
[[ "$(git -C "$wt_k" symbolic-ref --quiet HEAD)" == "refs/heads/relay/k" ]] || fail "fixture K INVALID: guard 2 would fire"
[[ -z "$(git -C "$wt_k" status --porcelain --ignore-submodules=none)" ]] || fail "fixture K INVALID: guard 3 would fire"
git -C "$repo_k" merge-base --is-ancestor "refs/heads/relay/k" HEAD || fail "fixture K INVALID: guard 4 would fire"
set +e
out_k="$("$SH" "$repo_k" "$wt_k" "relay/k" --expect-merged 2>&1)"; rc_k=$?
set -e
[[ $rc_k -eq 3 ]] || fail "K worktree-only gitlink objects: expected exit 3, got $rc_k -- out: $out_k"
[[ "$out_k" != *"submodule-force-hatch"* ]] \
  || fail "K worktree-only gitlink objects: hatch MUST NOT fire -- forcing here breaks MAIN, not just this worktree -- out: $out_k"
[[ -e "$wt_k" ]] || fail "K worktree-only gitlink objects: worktree must still be on disk"
git --git-dir="$repo_k/.git/worktrees/wt-k/modules/vendor/sub" cat-file -e "$sub_sha" 2>/dev/null \
  || fail "K worktree-only gitlink objects: the only copy of $sub_sha was destroyed"
[[ "$out_k" == *"ABSENT from the shared store"* && "$out_k" == *"vendor/sub"* ]] \
  || fail "K worktree-only gitlink objects: must say loudly WHY it refused, naming the store -- out: $out_k"
pass "K submodule commit living ONLY in the worktree's store → fifth guard refused, merged gitlink still resolvable ($out_k)"

# ── L. NON-C LOCALE: the hatch still recognizes git's refusal ────────────────
# git's refusal is a TRANSLATED string. Under LC_ALL=de_DE.utf8 (git 2.55.0, de.mo installed) it
# reads "Schwerwiegend: Arbeitsverzeichnisse, die Submodule enthalten, können nicht verschoben
# oder entfernt werden." -- so an unpinned probe misses the verbatim match AND misses the
# `containing submodules` fallback, and the run falls through to the generic dirty-tree advice
# this whole item exists to eliminate. It fails CLOSED, but it fails MISLEADINGLY. The script
# pins LC_ALL=C around the probe and the force; this proves the pin works end to end.
#
# Guarded by a positive control: if this box has no German git translation the refusal comes back
# in English anyway and the case would pass vacuously, so we SKIP loudly instead of pretending.
loc_repo="$(mksuper l --with-submodule)"
loc_wt="$(mkwt "$loc_repo" l --init-submodule)"
set +e
de_err="$(LC_ALL=de_DE.utf8 git -C "$loc_repo" worktree remove "$loc_wt" 2>&1)"
c_err="$(LC_ALL=C git -C "$loc_repo" worktree remove "$loc_wt" 2>&1)"
set -e
if [[ "$de_err" == "$c_err" ]]; then
  echo "SKIP: L locale -- git emits the SAME refusal under de_DE.utf8 as under C on this box (no de translation installed), so a behavioural locale case would be vacuous. The LC_ALL=C pin is still asserted at the source level below."
else
  set +e
  out_l="$(LC_ALL=de_DE.utf8 "$SH" "$loc_repo" "$loc_wt" "relay/l" --expect-merged 2>&1)"; rc_l=$?
  set -e
  [[ $rc_l -eq 0 ]] || fail "L non-C locale: expected exit 0 (hatch fires regardless of locale), got $rc_l -- out: $out_l"
  [[ "$out_l" == *"submodule-force-hatch"* ]] \
    || fail "L non-C locale: the hatch must recognize the refusal under ANY locale (probe pinned to LC_ALL=C) -- out: $out_l"
  [[ "$out_l" != *"commit real work"* ]] \
    || fail "L non-C locale: fell through to the generic dirty-tree advice -- exactly the misdirection id:a290 exists to remove -- out: $out_l"
  [[ ! -e "$loc_wt" ]] || fail "L non-C locale: worktree dir should be gone"
  pass "L under LC_ALL=de_DE.utf8 (git speaks German: ${de_err//$'\n'/ }) → hatch still fires ($out_l)"
fi

# ── M. NESTED private store: an inner submodule commit made inside the worktree → REFUSED ──
# ESCAPE F1 (round-3 review, 2026-09-01). A worktree's private submodule stores NEST:
#   .git/worktrees/<bn>/modules/vendor/sub/modules/lib/inner
# An INDEX-scoped guard sees only the superproject's own gitlinks (vendor/sub) and is blind to
# lib/inner, whose gitlink lives in the SUBMODULE's index. Push the outer sub commit into the
# SHARED outer store and the index-scoped check passes -- while the inner commit still exists
# only in the worktree's private inner store. Measured before the fix: the hatch fired, and a
# later `submodule update --init --recursive` on MAIN died with
#   fatal: remote error: upload-pack: not our ref <inner sha>
repo_m="$(mksuper m --with-nested)"
wt_m="$(mkwt "$repo_m" m --init-recursive)"
printf 'inner work done inside the worktree\n' >> "$wt_m/vendor/sub/lib/inner/i.txt"
git -C "$wt_m/vendor/sub/lib/inner" commit -qam "inner work from the worktree"
inner_sha="$(git -C "$wt_m/vendor/sub/lib/inner" rev-parse HEAD)"
git -C "$wt_m/vendor/sub" add lib/inner
git -C "$wt_m/vendor/sub" commit -qm "bump inner gitlink"
outer_sha="$(git -C "$wt_m/vendor/sub" rev-parse HEAD)"
# Put the OUTER commit in the shared outer store so the top-level (index-scoped) check passes.
git -C "$wt_m/vendor/sub" push -q "$repo_m/.git/modules/vendor/sub" "HEAD:refs/heads/pushed-from-wt" \
  || fail "fixture M: could not push the outer submodule commit into the shared store"
git -C "$wt_m" add vendor/sub
git -C "$wt_m" commit -qm "bump sub gitlink"
git -C "$repo_m" merge -q --no-ff -m "merge relay/m" relay/m
priv_inner_m="$repo_m/.git/worktrees/wt-m/modules/vendor/sub/modules/lib/inner"
# Fixture sanity: the escape's whole shape must actually hold, or this case proves nothing.
git --git-dir="$repo_m/.git/modules/vendor/sub" cat-file -e "$outer_sha" 2>/dev/null \
  || fail "fixture M INVALID: the OUTER commit is not in the shared store, so the top-level check would refuse for the wrong reason"
git --git-dir="$repo_m/.git/modules/vendor/sub/modules/lib/inner" cat-file -e "$inner_sha" 2>/dev/null \
  && fail "fixture M INVALID: the inner commit is ALREADY in the shared inner store, so nothing would be lost"
[[ -d "$priv_inner_m" ]] || fail "fixture M INVALID: no NESTED private store at $priv_inner_m"
[[ "$(git -C "$repo_m" rev-parse "HEAD:vendor/sub")" == "$outer_sha" ]] \
  || fail "fixture M INVALID: the superproject's MERGED gitlink does not point at the worktree-made outer commit"
[[ -z "$(git -C "$wt_m" status --porcelain --ignore-submodules=none)" ]] || fail "fixture M INVALID: guard 3 would fire"
git -C "$repo_m" merge-base --is-ancestor "refs/heads/relay/m" HEAD || fail "fixture M INVALID: guard 4 would fire"
set +e
out_m="$("$SH" "$repo_m" "$wt_m" "relay/m" --expect-merged 2>&1)"; rc_m=$?
set -e
[[ $rc_m -eq 3 ]] || fail "M nested worktree-only gitlink: expected exit 3, got $rc_m -- out: $out_m"
[[ "$out_m" != *"submodule-force-hatch"* ]] \
  || fail "M nested worktree-only gitlink: hatch MUST NOT fire -- the inner object exists ONLY in the worktree's NESTED private store -- out: $out_m"
[[ -e "$wt_m" ]] || fail "M nested worktree-only gitlink: worktree must still be on disk"
git --git-dir="$priv_inner_m" cat-file -e "$inner_sha" 2>/dev/null \
  || fail "M nested worktree-only gitlink: the only copy of the inner commit $inner_sha was destroyed"
[[ "$out_m" == *"lib/inner"* ]] \
  || fail "M nested worktree-only gitlink: the refusal must NAME the offending store -- out: $out_m"
pass "M NESTED private store holding the only copy of an inner commit → refused, object safe ($out_m)"

# ── N. gitlink REMOVED from the index but still referenced by MERGED history → REFUSED ──
# ESCAPE F2 (round-3 review, 2026-09-01). Make a submodule commit inside the worktree, bump the
# gitlink, then `git rm` the submodule in a LATER commit and merge both. The worktree's index now
# holds ZERO gitlinks, so an index-scoped guard has nothing to check and passes vacuously -- yet
# git still refuses the plain removal (the private store persists), the hatch fires, and the
# object referenced by the merged bump commit is destroyed. Measured before the fix:
#   fatal: remote error: upload-pack: not our ref <sha>
repo_n="$(mksuper n --with-submodule)"
wt_n="$(mkwt "$repo_n" n --init-submodule)"
printf 'submodule work done inside the worktree\n' >> "$wt_n/vendor/sub/f.txt"
git -C "$wt_n/vendor/sub" commit -qam "submodule work from the worktree"
sub_sha_n="$(git -C "$wt_n/vendor/sub" rev-parse HEAD)"
git -C "$wt_n" add vendor/sub
git -C "$wt_n" commit -qm "bump submodule gitlink"
bump_n="$(git -C "$wt_n" rev-parse HEAD)"
git -C "$wt_n" rm -q vendor/sub
git -C "$wt_n" commit -qm "drop the submodule from the tree"
git -C "$repo_n" merge -q --no-ff -m "merge relay/n" relay/n
priv_n="$repo_n/.git/worktrees/wt-n/modules/vendor/sub"
# Fixture sanity: index empty of gitlinks, object worktree-only, merged history still needs it.
[[ "$(git -C "$wt_n" ls-files --stage | grep -c '^160000' || true)" -eq 0 ]] \
  || fail "fixture N INVALID: the index still carries a gitlink, so this is not the index-vs-history shape"
git --git-dir="$repo_n/.git/modules/vendor/sub" cat-file -e "$sub_sha_n" 2>/dev/null \
  && fail "fixture N INVALID: the submodule commit is already in the shared store, nothing would be lost"
[[ -d "$priv_n" ]] || fail "fixture N INVALID: the worktree's private store is gone already"
[[ "$(git -C "$repo_n" rev-parse "$bump_n:vendor/sub")" == "$sub_sha_n" ]] \
  || fail "fixture N INVALID: the MERGED bump commit does not reference the worktree-only submodule commit"
[[ -z "$(git -C "$wt_n" status --porcelain --ignore-submodules=none)" ]] || fail "fixture N INVALID: guard 3 would fire"
git -C "$repo_n" merge-base --is-ancestor "refs/heads/relay/n" HEAD || fail "fixture N INVALID: guard 4 would fire"
set +e
out_n="$("$SH" "$repo_n" "$wt_n" "relay/n" --expect-merged 2>&1)"; rc_n=$?
set -e
[[ $rc_n -eq 3 ]] || fail "N index-vs-history: expected exit 3, got $rc_n -- out: $out_n"
[[ "$out_n" != *"submodule-force-hatch"* ]] \
  || fail "N index-vs-history: hatch MUST NOT fire -- the index is empty of gitlinks but MERGED history still needs the object -- out: $out_n"
[[ -e "$wt_n" ]] || fail "N index-vs-history: worktree must still be on disk"
[[ -d "$priv_n" ]] || fail "N index-vs-history: the private store holding the only copy of $sub_sha_n was destroyed"
pass "N gitlink dropped from the index, still referenced by merged history → refused, object safe ($out_n)"

# ── O. NO OVER-REFUSAL, nested: everything duplicated in the shared stores → HATCH FIRES ──
# The mirror of M. A guard that refuses everything is not a guard, it is an outage. A nested
# submodule worktree whose every private-store object is also in the corresponding shared store
# must still force-remove cleanly.
repo_o="$(mksuper o --with-nested)"
wt_o="$(mkwt "$repo_o" o --init-recursive)"
[[ -d "$repo_o/.git/worktrees/wt-o/modules/vendor/sub/modules/lib/inner" ]] \
  || fail "fixture O INVALID: no nested private store, so this proves nothing about nested no-over-refusal"
set +e
out_o="$("$SH" "$repo_o" "$wt_o" "relay/o" --expect-merged 2>&1)"; rc_o=$?
set -e
[[ $rc_o -eq 0 ]] || fail "O nested clean+merged: expected exit 0 (no over-refusal), got $rc_o -- out: $out_o"
[[ "$out_o" == *"submodule-force-hatch"* ]] \
  || fail "O nested clean+merged: the hatch must still fire when every object is duplicated -- out: $out_o"
[[ ! -e "$wt_o" ]] || fail "O nested clean+merged: worktree dir should be gone"
pass "O NESTED submodules, all objects duplicated in the shared stores → hatch still fires, no over-refusal ($out_o)"

# ── P/Q/R. FAIL-OPEN PROBES: every nonzero git exit inside the guard must REFUSE ──
# ESCAPE F3 (round-3 review, 2026-09-01). The guard used to read a git failure as "safe":
# `common="$(git … --git-common-dir 2>/dev/null)" || return 0` and
# `done < <(git … ls-files --stage -z 2>/dev/null || true)` both made an EMPTY result a PASS.
# Unit-probing with a fake git on PATH showed git-always-fails, --git-common-dir-unsupported,
# ls-files-fails and ls-files-empty ALL forcing. A corrupt or unreadable index in a CRASHED
# relay worktree -- exactly this script's target population -- silently opened the force.
# Each case below breaks ONE git invocation the guard depends on and demands a LOUD refusal.
# The shims delegate everything else (INCLUDING `--force`) to the real git, so a guard that
# wrongly fired would really remove the worktree and the case would see it.
mk_shim() { # <name> <binary> <bash test over "$args"> → shim dir to prepend to PATH
  local name="$1" bin="$2" cond="$3" dir="$TMP/shim-$1" real
  real="$(command -v "$bin")" || fail "mk_shim: no real $bin on PATH"
  mkdir -p "$dir"
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf '%s\n' 'args="$*"'
    printf 'if %s; then\n' "$cond"
    printf '  echo "fatal: simulated %s failure (test shim)" >&2\n' "$bin"
    printf '%s\n' '  exit 128'
    printf '%s\n' 'fi'
    printf 'exec %q "$@"\n' "$real"
  } > "$dir/$bin"
  chmod +x "$dir/$bin"
  printf '%s' "$dir"
}

failopen_case() { # <letter> <name> <binary> <shim-cond> <what broke>
  local letter="$1" name="$2" bin="$3" cond="$4" what="$5"
  local repo wt shim out rc
  repo="$(mksuper "$name" --with-submodule)"
  wt="$(mkwt "$repo" "$name" --init-submodule)"
  shim="$(mk_shim "$name" "$bin" "$cond")"
  set +e
  out="$(PATH="$shim:$PATH" "$SH" "$repo" "$wt" "relay/$name" --expect-merged 2>&1)"; rc=$?
  set -e
  [[ $rc -eq 3 ]] || fail "$letter $what: expected exit 3 (fail CLOSED), got $rc -- out: $out"
  [[ "$out" != *"submodule-force-hatch"* ]] \
    || fail "$letter $what: a git failure inside the guard must never read as 'safe' -- out: $out"
  [[ -e "$wt" ]] || fail "$letter $what: worktree must still be on disk (it was forced away)"
  [[ -n "$out" ]] || fail "$letter $what: must refuse LOUDLY, printed nothing"
  pass "$letter $what → guard refused loudly instead of failing open ($out)"
}

# ── S. a private store with NO shared counterpart at all → REFUSED ──────────
# When the MAIN checkout never initialised the submodule, `submodule update --init` inside a
# LINKED worktree creates ONLY the private store -- `.git/modules/<name>` does not exist at all
# (measured 2026-09-01, git 2.55.0). Every object then has exactly one copy, inside the thing the
# force deletes, so there is nothing to compare against and nothing can be proved safe. Pinned as
# a REFUSAL, per the id:a290 round-3 ruling ("require every object … to exist in the corresponding
# shared store; refuse otherwise"). NOTE this is deliberately conservative: those objects usually
# also live on the submodule's remote and would be refetchable. Changing that is an owner call,
# not a quiet loosening -- so it is asserted here rather than left to chance.
repo_s="$(mksuper s --with-submodule)"
git -C "$repo_s" submodule deinit -q --all
rm -r -- "$repo_s/.git/modules"
wt_s="$(mkwt "$repo_s" s --init-submodule)"
[[ -d "$repo_s/.git/worktrees/wt-s/modules/vendor/sub" ]] \
  || fail "fixture S INVALID: no private store was created, so this proves nothing"
[[ ! -d "$repo_s/.git/modules/vendor/sub" ]] \
  || fail "fixture S INVALID: a shared store exists after all, so this is not the no-counterpart case"
set +e
out_s="$("$SH" "$repo_s" "$wt_s" "relay/s" --expect-merged 2>&1)"; rc_s=$?
set -e
[[ $rc_s -eq 3 ]] || fail "S no shared counterpart: expected exit 3, got $rc_s -- out: $out_s"
[[ "$out_s" != *"submodule-force-hatch"* ]] \
  || fail "S no shared counterpart: hatch MUST NOT fire when every object has exactly one copy -- out: $out_s"
[[ -e "$wt_s" ]] || fail "S no shared counterpart: worktree must still be on disk"
[[ "$out_s" == *"NO corresponding shared store"* ]] \
  || fail "S no shared counterpart: must say loudly WHY it refused -- out: $out_s"
pass "S private store with NO shared counterpart → refused, nothing forced ($out_s)"

failopen_case P p git '[[ "$args" == *--git-common-dir* ]]' \
  "the superproject's common git dir cannot be resolved (also the git < 2.31 no---path-format case)"
failopen_case Q q git '[[ "$args" == *rev-list* ]]' \
  "the private submodule store's objects cannot be enumerated"
failopen_case R r git '[[ "$args" == *cat-file* ]]' \
  "the shared submodule store cannot be queried"
failopen_case T t git '[[ "$args" == *--path-format=absolute* && "$args" == *--git-dir* && "$args" != *--git-common-dir* ]]' \
  "the WORKTREE's own admin dir cannot be resolved (so its private stores cannot be located)"
failopen_case U u find '[[ "$args" == *modules* ]]' \
  "the private submodule stores cannot be enumerated (find fails, which would hand the audit a SHORT list)"

# ── Source-level assertion for the locale pin (holds even when L skips) ──────
grep -Eq 'LC_ALL=C git -C "\$repo" worktree remove "\$wt"' "$SH" \
  || fail "the no-force PROBE is not pinned to LC_ALL=C -- a translated refusal would miss the verbatim match (id:a290)"
grep -Eq 'LC_ALL=C git -C "\$repo" worktree remove --force "\$wt"' "$SH" \
  || fail "the FORCE is not pinned to LC_ALL=C -- its error text is parsed into the surfaced message (id:a290)"
pass "both the refusal probe and the force are pinned to LC_ALL=C"

echo "ALL PASS: $(basename "$0")"
