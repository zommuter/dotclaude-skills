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

echo "ALL PASS: $(basename "$0")"
