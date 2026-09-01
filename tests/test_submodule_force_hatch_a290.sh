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

# mksuper <name> [--with-submodule] → $TMP/<name>, a superproject on main
mksuper() {
  local n="$1" repo="$TMP/$1"
  git init -q -b main "$repo"
  printf 'base\n' > "$repo/base.txt"
  git -C "$repo" add -A
  git -C "$repo" commit -qm init
  if [[ "${2:-}" == "--with-submodule" ]]; then
    # protocol.file.allow: git refuses file:// submodules by default (CVE-2022-39253).
    git -C "$repo" -c protocol.file.allow=always submodule add -q "$SUB" vendor/sub >/dev/null 2>&1 \
      || fail "fixture: submodule add failed in $repo"
    git -C "$repo" commit -qm "add submodule"
  fi
  printf '%s' "$repo"
}

# mkwt <repo> <name> [--init-submodule] → adds worktree $TMP/wt-<name> on branch relay/<name>
mkwt() {
  local repo="$1" n="$2" wt="$TMP/wt-$2"
  git -C "$repo" worktree add -q "$wt" -b "relay/$n"
  if [[ "${3:-}" == "--init-submodule" ]]; then
    git -C "$wt" -c protocol.file.allow=always submodule update --init >/dev/null 2>&1 \
      || fail "fixture: submodule update --init failed in $wt"
    [[ -f "$wt/vendor/sub/f.txt" ]] || fail "fixture: submodule not populated in $wt"
  fi
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

# ── H. WORKTREE_RETIRE_NO_SUBMODULE_FORCE=1 disables the hatch entirely ─────
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
[[ "$out_k" == *"nowhere else"* || "$out_k" == *"NOWHERE ELSE"* ]] \
  || fail "K worktree-only gitlink objects: must say loudly WHY it refused -- out: $out_k"
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
  echo "SKIP: L locale — git emits the SAME refusal under de_DE.utf8 as under C on this box (no de translation installed), so a behavioural locale case would be vacuous. The LC_ALL=C pin is still asserted at the source level below."
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

# ── Source-level assertion for the locale pin (holds even when L skips) ──────
grep -Eq 'LC_ALL=C git -C "\$repo" worktree remove "\$wt"' "$SH" \
  || fail "the no-force PROBE is not pinned to LC_ALL=C -- a translated refusal would miss the verbatim match (id:a290)"
grep -Eq 'LC_ALL=C git -C "\$repo" worktree remove --force "\$wt"' "$SH" \
  || fail "the FORCE is not pinned to LC_ALL=C -- its error text is parsed into the surfaced message (id:a290)"
pass "both the refusal probe and the force are pinned to LC_ALL=C"

echo "ALL PASS: $(basename "$0")"
