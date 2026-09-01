#!/usr/bin/env bash
# worktree-retire.sh — FORCE-FREE retirement of ONE relay worktree + its branch (id:373e).
#
# Motivation: the pool's integrator + reconcile used to run `git worktree remove --force`
# and `git branch -D`. Under a strict destructive-op guardrail (docs/destructive-op-
# guardrail.md) those ops are DENIED, so worktrees never got removed and orphan debris
# accumulated every run. This helper retires a worktree WITHOUT any force op and WITHOUT
# ever discarding un-inspected work:
#
#   1. worktree gone from disk        → `git worktree prune` (non-destructive admin cleanup)
#   2. `git worktree remove` (NO -f)  → succeeds only on a CLEAN tree (executor committed
#                                       per contract; gitignored build residue does NOT block).
#      dirty / locked / unremovable   → SURFACE it and LEAVE it on disk for a supervised
#                                       reconcile / human. Never stash, clean, reset, or force.
#   3. `git branch -d` (NO -D)        → deletes only a provably-merged branch.
#      refused (unmerged commits)     → PARK: rename to relay/orphan/<bn>, KEEP the ref
#                                       (the refs ARE the registry, id:a4e9). Never -D.
#
# The branch step runs ONLY after the worktree is successfully removed (you cannot rename a
# branch checked out in a live worktree, and a dirty worktree we refuse to touch keeps BOTH
# its worktree and its branch — nothing is lost).
#
# SCOPE (id:6e02): operates on EXACTLY the one <worktree-dir> + <branch> passed. NO globbing,
# NO discovery, NO "tidy other relay/*". The 2026-07-01 incident (an integrator swept a live
# parallel child's worktree) is exactly what this single-target contract prevents. Discovery/
# selection stays in the callers (reconcile-repo.sh / the relay-loop integrator recipe).
#
# Usage:
#   worktree-retire.sh <repo-path> <worktree-dir> <branch> [--expect-merged] [--commit-residue]
#                      [--discard-residue --ack <token>]
#
#   --expect-merged   The caller proved the branch is already merged (e.g. reconcile's reap:
#                     merge-base --is-ancestor). Then a `branch -d` refusal is an ANOMALY
#                     (main moved? race?) surfaced LOUDLY, NOT silently parked.
#
#   --commit-residue  OPT-IN (id:f272). Default behaviour (flag absent) is UNCHANGED: a dirty
#                     worktree is still surfaced-and-left, exit 3. With the flag, a DIRTY worktree
#                     on a relay-owned branch (refs/heads/relay/…), with --expect-merged NOT also
#                     passed, gets its residue committed onto that SAME branch first (a WIP/
#                     UNVERIFIED commit naming the worktree) so the normal remove+park path below
#                     can run and the branch ends up a reachable `relay/orphan/<bn>` ref instead of
#                     stranding on disk. Committing residue is NOT a force op — it discards
#                     nothing, unlike stash/clean/reset (id:373e bans discarding, not committing).
#                     A dirty worktree on a NON-relay branch, or when --expect-merged is also set,
#                     is untouched by this flag and still surfaces-and-leaves as before.
#
# THE THIRD BRANCH — owner-authorized DISCARD (id:8d76). Use `--discard-residue --ack <token>`.
# Both dirty-tree paths above assume the residue might be worth keeping. When the owner has
# INSPECTED it and ruled it worthless-or-harmful, neither fits:
#   - the default (surface-and-leave, exit 3) parks known-bad content on disk indefinitely;
#   - --commit-residue makes it WORSE for harmful residue — it moves the content out of an
#     unreachable index into a reachable, pushable `relay/orphan/*` ref, and the pre-push
#     privacy gate is warn+LOG only (id:df87), so nothing would block a later publish.
#
# This branch was DELIBERATELY ABSENT until 2026-08-26, on the reasoning that discarding is the
# one act id:373e bans, so it should stay a supervised human step outside this script. That
# reasoning DEPENDED on the raw `git worktree remove --force` remaining available to a human at
# an approved prompt. The owner's id:221f(a) ruling the same day moves `git * --force*` to
# `deny` — so the documented exit stopped existing, and a documented path to a denied command
# is not a path. The capability now lives HERE, in the one allowlisted, audited script, which
# is exactly what "deny the raw form, route through the gated script" means.
#
# It refuses unless: the flag is passed explicitly; the worktree exists and is genuinely dirty;
# the branch is relay-owned; and `--ack <token>` matches a digest of THIS residue's exact bytes.
# A first run prints the token and the residue's PATHS (never its content — the content may be
# the private material being disposed of, and stdout is the agent transcript). So a blanket
# loop cannot discard anything, and a residue that changed since inspection refuses.
# COMMITS ARE NEVER TOUCHED: only uncommitted content goes, and unmerged commits still take the
# normal park path, so "discard the residue" can never become "lose the work". The residue is
# archived first, to a 0700 dir OUTSIDE any git repo — refused if that path is in a work tree.
#
# THE FOURTH BRANCH -- the NARROW SUBMODULE ESCAPE HATCH (id:a290 shape (b), owner-ruled
# 2026-09-01). `git worktree remove` refuses a worktree whose submodules are POPULATED even
# when it is spotless and fully merged, so relay debris on submodule repos accumulated with no
# force-free route (1.8 GB before the owner cleared it by hand). This hatch force-removes such
# a worktree -- but ONLY after this script has itself PROVED clean AND merged AND that no object
# would be lost with any of the worktree's private submodule stores (enumerated recursively, since
# they nest), AND has POSITIVELY
# RECOGNIZED git's exact submodule refusal (probed under LC_ALL=C, since that refusal is a
# TRANSLATED string). It is structurally unable to fire on dirty or unmerged work, it refuses when
# a submodule commit lives only inside the worktree, and it FAILS CLOSED on any refusal it does
# not recognize verbatim. See the
# long comment at step 1b, including what roadmap:b02f documented and got wrong.
#
# ⚠ OPT-IN, NOT DEFAULT-ON (owner-ruled 2026-09-01, reversing the original ruling on the strength
# of the round-3 adversarial review). It fires ONLY when `WORKTREE_RETIRE_SUBMODULE_FORCE=1` is
# set. No relay call site sets it, so the hatch is INERT in production today -- deliberately.
# WHY: the review found a data-loss path that ALL FIVE guards pass. An executor bumps a submodule,
# the bump is MERGED, then it AMENDS the submodule commit -- the original object becomes DANGLING
# in the private store, invisible to `rev-list --objects --all <HEAD>`, and the force destroys the
# object a merged commit on main names ('upload-pack: not our ref'). Structural cause: this guard
# asks "what do the private store's refs REACH", while the question that matters is "what gitlinks
# does MERGED SUPERPROJECT HISTORY name" -- neither set contains the other. Reopening default-on
# needs that answered (TODO id:a290), not another guard bolted on.
# `WORKTREE_RETIRE_NO_SUBMODULE_FORCE=1` still hard-disables, and WINS over the opt-in, so an
# existing caller or doc that sets it can never silently become an enable.
#
# Exit codes:
#   0  retired cleanly (worktree removed, branch deleted or parked as designed)
#   2  usage / not-a-git-repo error
#   3  surfaced-and-left: worktree dirty/unremovable, orphan ref collision, or a
#      --discard-residue run whose --ack token was missing/stale — NOTHING forced, NOTHING lost
#   4  anomaly: --expect-merged but branch -d refused (worktree already removed; branch kept)
#
# Env overrides (hermetic tests):
#   WORKTREE_RETIRE_LOG   default ~/.claude/logs/relay-worktree-retire.log
#   WORKTREE_RETIRE_SUBMODULE_FORCE=1      ENABLE the id:a290 submodule escape hatch (opt-in;
#                                          absent/0 = inert, which is the production default)
#   WORKTREE_RETIRE_NO_SUBMODULE_FORCE=1   hard-disable it; WINS over the opt-in above
set -euo pipefail

LOG="${WORKTREE_RETIRE_LOG:-$HOME/.claude/logs/relay-worktree-retire.log}"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true  # swallow-ok: log dir best-effort; a missing log must never abort a retire
log() { printf '%s worktree-retire.sh %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >>"$LOG" 2>/dev/null || true; }  # swallow-ok: logging is advisory, never fatal

expect_merged=0
commit_residue=0
discard_residue=0
ack=""
repo="" wt="" branch=""
pos=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --expect-merged) expect_merged=1; shift ;;
    --commit-residue) commit_residue=1; shift ;;
    --discard-residue) discard_residue=1; shift ;;
    --ack) ack="${2:-}"; shift 2 ;;
    -*) echo "worktree-retire.sh: unknown flag '$1'" >&2; exit 2 ;;
    *) pos+=("$1"); shift ;;
  esac
done
[[ ${#pos[@]} -eq 3 ]] || { echo "worktree-retire.sh: usage: <repo-path> <worktree-dir> <branch> [--expect-merged] [--commit-residue] [--discard-residue --ack <token>]" >&2; exit 2; }
if [[ "$discard_residue" -eq 1 && "$commit_residue" -eq 1 ]]; then
  echo "worktree-retire.sh: --discard-residue and --commit-residue are mutually exclusive (one preserves the residue, the other destroys it)" >&2
  exit 2
fi
[[ -n "$ack" && "$discard_residue" -eq 0 ]] && { echo "worktree-retire.sh: --ack is only meaningful with --discard-residue" >&2; exit 2; }
repo="${pos[0]}"; wt="${pos[1]}"; branch="${pos[2]}"

if [[ ! -d "$repo" ]] || ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
  echo "worktree-retire.sh: '$repo' is not a git repository" >&2
  exit 2
fi

bn="$(basename "$wt")"
orphan_ref="relay/orphan/$bn"

# ---- 0. git-annex layout normalization (id:de4a) ----------------------------
# On a git-annex repo the smudge filter (filter.annex.process) rewrites a linked worktree's
# `.git` FILE into a SYMLINK to the admin dir (so annexed relative symlinks
# ../.git/annex/objects/... resolve inside the worktree). `git worktree remove` then fails
# validation PERMANENTLY — "'<wt>/.git' is not a .git file, error code 10" — and --force does
# NOT help, because validation precedes it. Result: on an annex repo every relay worktree
# leaked forever (zkWhale: the only annex repo among own repos, 3 dirs / 1.2G, all clean+merged).
#
# We restore the standard `gitdir: <admin>` pointer that git itself writes. This is NOT a force
# op and discards NOTHING: the admin dir, the index, and every file in the tree are untouched —
# we rewrite only the pointer, converting an unremovable layout back into git's own supported
# one. The dirty check below still runs afterwards and still wins, so this can never become a
# backdoor that removes uncommitted work.
#
# GUARDED: we normalize ONLY when the symlink resolves to THIS repo's own admin dir for THIS
# worktree. Anything else is surfaced untouched — we never rewrite a pointer we don't recognize.
if [[ -L "$wt/.git" ]]; then
  # --path-format=absolute: a bare --git-common-dir is repo-RELATIVE (".git"), which would
  # make the comparison below compare against a nonsense path and always defer.
  admin_expect="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)/worktrees/$bn"
  admin_expect="$(readlink -f "$admin_expect" || printf '%s' "$admin_expect")"
  admin_actual="$(readlink -f "$wt/.git" || true)"
  if [[ -n "$admin_actual" && "$admin_actual" == "$admin_expect" && -d "$admin_actual" ]]; then
    rm -- "$wt/.git"
    printf 'gitdir: %s\n' "$admin_actual" > "$wt/.git"
    log "normalized annex .git symlink -> gitdir file repo=$repo wt=$wt admin=$admin_actual"
  else
    msg="retire-deferred $bn: '$wt/.git' is a SYMLINK that does not resolve to this repo's own admin dir (expected '$admin_expect', got '${admin_actual:-<unresolvable>}') — LEFT untouched for a human. Not normalizing a pointer we do not recognize."
    log "DEFER-UNRECOGNIZED-SYMLINK $msg"
    echo "$msg"
    exit 3
  fi
fi

# ---- 0c. optional dirty-residue commit (id:f272, opt-in via --commit-residue) --
# Runs BEFORE the removal attempt below so a dirty tree becomes clean and the normal
# remove+park path can proceed unmodified — commit-and-park reuses the existing park logic
# rather than adding a new disposal branch. Guards, all required: the flag was passed, the
# worktree still exists, the caller is NOT claiming the branch is already merged (a merged
# branch dirty on disk is a different anomaly, not this path), and the branch is relay-owned
# (`relay/…` — never touch a branch this helper doesn't own). Committing is never a force op:
# it discards nothing, it only moves untracked/modified content into a new commit on the
# worktree's OWN branch (id:373e bans discarding, not committing).
if [[ "$commit_residue" -eq 1 && -e "$wt" && "$expect_merged" -eq 0 && "$branch" == relay/* ]]; then
  if [[ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]]; then
    git -C "$wt" add -A
    # --no-verify: this is an emergency preservation commit, not a reviewed change — a
    # repo-local pre-commit hook (e.g. a lint/lane-vocab gate) must never cause residue to be
    # lost. The commit is explicitly marked WIP/UNVERIFIED so nothing downstream mistakes it
    # for reviewed work; the reviewer's normal test-integrity checks (contract rule 3) still
    # apply once a human/relay picks the parked orphan back up.
    if git -C "$wt" commit -q --no-verify -m "chore(relay): WIP UNVERIFIED residue auto-commit for worktree $bn (id:f272 commit-and-park; do not treat as reviewed)"; then
      log "commit-residue committed dirty state branch=$branch wt=$wt"
    else
      log "commit-residue FAILED to commit dirty state branch=$branch wt=$wt — falling through to normal surface-and-leave"
    fi
  fi
fi

# ---- 0d. OWNER-AUTHORIZED RESIDUE DISCARD (id:8d76, opt-in via --discard-residue) ----
# THE THIRD BRANCH. See the header block. This is the ONE place in the relay that destroys
# uncommitted work, and every guard below exists because of that.
#
# Why it lives HERE and not at an ad-hoc call site: id:221f(a) moves `git * --force*` to
# `deny`, which removes the raw `git worktree remove --force` a human used to reach for. The
# capability has to survive that ruling in an AUDITED form or the next privacy-residue
# disposal has no legal route at all.
#
# GUARDS, all required:
#   * the flag was passed explicitly (never a default, never implied by another flag);
#   * the worktree exists and is actually dirty (otherwise there is nothing to discard and
#     the normal clean path handles it);
#   * the branch is relay-owned (`relay/…`) — never a branch this helper does not own;
#   * --ack <token> matches a digest computed from THIS residue's exact content. Getting the
#     token requires a first run that prints it, so a blanket loop over `*` cannot discard
#     anything, and a residue that CHANGED between inspection and disposal refuses (TOCTOU).
#
# COMMITS ARE NEVER TOUCHED. This discards only uncommitted content — tracked modifications
# and non-ignored untracked files. Unmerged commits still take the normal park path below, so
# "discard the residue" can never become "lose the work".
#
# The residue is ARCHIVED before deletion, to a 0700 directory OUTSIDE any git repo (the
# tools/privacy-audit.sh precedent). The residue that motivated this was a PRIVACY LEAK, so
# its content must never land where git could commit it — and the archive is written to a
# path this script REFUSES to use if it turns out to be inside a work tree.
if [[ "$discard_residue" -eq 1 ]]; then
  if [[ ! -e "$wt" ]]; then
    echo "worktree-retire.sh: --discard-residue but '$wt' does not exist — nothing to discard" >&2
    exit 2
  fi
  if [[ "$branch" != relay/* ]]; then
    echo "worktree-retire.sh: --discard-residue refused — '$branch' is not a relay-owned branch (relay/…). This helper never destroys work on a branch it does not own." >&2
    exit 2
  fi
  status="$(git -C "$wt" status --porcelain 2>/dev/null || true)"
  if [[ -z "$status" ]]; then
    echo "worktree-retire.sh: --discard-residue but the worktree is CLEAN — nothing to discard; falling through to the normal path."
  else
    # The digest covers the porcelain status AND the tracked diff AND every untracked file's
    # bytes, so ANY change to the residue invalidates a previously-issued token.
    residue_blob="$(
      printf '%s\n' "$status"
      git -C "$wt" diff HEAD 2>/dev/null || true
      git -C "$wt" ls-files --others --exclude-standard -z 2>/dev/null \
        | while IFS= read -r -d '' f; do printf '=== %s ===\n' "$f"; cat -- "$wt/$f" 2>/dev/null || true; done
    )"
    want="$(printf '%s' "$residue_blob" | sha256sum | cut -c1-12)"
    if [[ "$ack" != "$want" ]]; then
      # Print the FILE LIST but never the CONTENT — the content may be exactly the private
      # material being disposed of, and stdout is the agent transcript.
      echo "worktree-retire.sh: --discard-residue REFUSED — missing or stale --ack token." >&2
      echo "  worktree: $wt" >&2
      echo "  branch:   $branch" >&2
      echo "  residue (paths only; content deliberately NOT printed):" >&2
      printf '%s\n' "$status" | sed 's/^/    /' >&2
      echo "  Inspect it yourself, then re-run with:  --discard-residue --ack $want" >&2
      echo "  The token is bound to this exact residue: if it changes, the token stops working." >&2
      log "DISCARD-REFUSED wt=$wt branch=$branch reason=${ack:+stale-ack}${ack:-no-ack} want=$want"
      exit 3
    fi

    # DEFAULT IS ~/.cache, NOT ~/.claude/logs — and that is not a style choice. `~/.claude` IS a
    # git repository (the private zomni/sessions branch), so `~/.claude/logs/` is inside a work
    # tree; the guard below correctly refused it on the first real run, 2026-08-26. `logs/` being
    # in `.gitignore` is NOT sufficient — an ignored path can still be force-added, and this
    # content is exactly what must never become committable. `~/.cache/relay/` is not a repo and
    # is where relay worktrees already live.
    archive_dir="${WORKTREE_RETIRE_ARCHIVE:-$HOME/.cache/relay/discarded-residue}"
    # REFUSE to archive anywhere git could commit it (privacy-audit.sh precedent).
    if git -C "$(dirname "$archive_dir")" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      echo "worktree-retire.sh: --discard-residue REFUSED — archive dir '$archive_dir' is inside a git work tree. The discarded residue must never land where git could commit it." >&2
      log "DISCARD-REFUSED-ARCHIVE-IN-REPO wt=$wt archive=$archive_dir"
      exit 3
    fi
    mkdir -p "$archive_dir"; chmod 700 "$archive_dir" 2>/dev/null || true  # swallow-ok: chmod is best-effort hardening, never fatal
    archive="$archive_dir/$(date '+%Y%m%dT%H%M%S')-$bn-$want.residue"
    printf '%s\n' "$residue_blob" > "$archive"; chmod 600 "$archive" 2>/dev/null || true  # swallow-ok: as above
    log "DISCARD-ARCHIVED wt=$wt branch=$branch ack=$want archive=$archive"

    # Destroy the residue with the NARROWEST ops that do the job — deliberately NOT
    # `clean -fd` (which would also take ignored build output, and is itself a guarded form).
    # Tracked modifications first, then non-ignored untracked files one by one.
    git -C "$wt" checkout -- . 2>/dev/null || true  # swallow-ok: a tree with only untracked residue has nothing to restore
    git -C "$wt" ls-files --others --exclude-standard -z 2>/dev/null \
      | while IFS= read -r -d '' f; do rm -- "$wt/$f"; done
    log "DISCARDED residue wt=$wt branch=$branch (archived at $archive)"
    echo "discard-residue $bn: residue destroyed, archived OUTSIDE any repo at $archive"
  fi
fi

# ---- 1a. PRIVATE SUBMODULE STORE SAFETY (id:a290 fifth guard) ---------------
# A linked worktree gets its OWN submodule object stores under
# `.git/worktrees/<bn>/modules/…` -- SEPARATE from the superproject's shared `.git/modules/…`.
# `git worktree remove --force` deletes the whole admin dir, and with it every one of those
# private stores. If a submodule commit was CREATED inside the worktree and something already
# merged into the superproject references it, that force takes the ONLY copy of those objects:
# the merged commit on MAIN then points at a gitlink nobody can resolve
#   fatal: remote error: upload-pack: not our ref <sha>
# and the damage is to main, not to the worktree. All four earlier guards pass LEGITIMATELY in
# that case -- HEAD matches, the tree is spotless, the branch IS an ancestor of HEAD -- which is
# exactly why a fifth, OBJECT-level guard is needed: the first four reason about REFS and about
# the worktree's own dirtiness, and neither notices an object that exists in only one store.
# Reproduced by fixture 2026-09-01 (git 2.55.0), case K in tests/test_submodule_force_hatch_a290.sh.
#
# THIS GUARD IS SCOPED TO THE PRIVATE STORE, NOT TO THE INDEX -- and that is the whole design,
# rewritten 2026-09-01 after a third review round. GIT'S REFUSAL IS KEYED ON THE EXISTENCE OF
# `.git/worktrees/<bn>/modules/`; an index-keyed guard therefore answers a DIFFERENT question
# from the one the force actually poses, and two independent escapes came straight out of that
# mismatch (both reproduced as fixtures before this rewrite, cases M and N):
#
#   * NESTED stores. Private stores nest -- `…/modules/vendor/sub/modules/lib/inner`. The inner
#     gitlink lives in the SUBMODULE's index, not the superproject's, so an index scan never
#     sees it. Push the outer submodule commit into the shared outer store and the index check
#     passes while the inner commit still exists only in the worktree. Measured: force fired,
#     then `submodule update --init --recursive` on MAIN died with `upload-pack: not our ref`.
#   * INDEX vs MERGED HISTORY. `git rm` the submodule in a later commit and the worktree's index
#     holds ZERO gitlinks -- the index check passes vacuously -- while the merged bump commit
#     still references an object that lives only in the (still present) private store. Git still
#     refuses the plain removal, so the hatch still fired. Measured: object destroyed.
#   * It also removes the `.gitmodules` name->path mapping the old version needed, and with it
#     a third escape: a submodule whose NAME differs from its PATH resolved to the wrong shared
#     store. Store paths are now read from the filesystem, so no name derivation happens at all.
#
# So: enumerate the private stores RECURSIVELY, and for EACH one require that every object
# reachable from ITS OWN refs (all refs, plus HEAD, which in a submodule is normally detached)
# already exists in the correspondingly-named SHARED store. The private-to-shared mapping is the
# path relative to the admin dir's `modules/`, which git lays out identically under
# `.git/modules/` -- verified for the nested case 2026-09-01.
#
# FAIL CLOSED ON EVERY NONZERO GIT EXIT. The previous version read a git failure as "safe":
# `common="$(git … 2>/dev/null)" || return 0` and `< <(git … ls-files … || true)` both made an
# EMPTY result a PASS, so git-always-fails, --path-format-unsupported (git < 2.31), ls-files-fails
# and ls-files-empty ALL opened the force -- in a CRASHED relay worktree, which is precisely this
# script's target population. Every git invocation below refuses on failure and says which one
# failed. Cases P/Q/R pin that.
#
# Echoes a human-readable reason on stdout when it is not safe to force; EMPTY output means every
# private-store object is safely duplicated in its shared counterpart.

# _store_unsafe_reason <private-store> <shared-store> <label> -> reason on stdout ("" = safe)
_store_unsafe_reason() {
  local store="$1" shared="$2" label="$3"
  local tmpd head_sha n_missing first
  if [[ ! -d "$shared" ]]; then
    printf "private store '%s' has NO corresponding shared store at %s, so the force would destroy every object it holds with no second copy anywhere" "$label" "$shared"
    return 0
  fi
  if ! tmpd="$(mktemp -d 2>/dev/null)"; then
    printf "private store '%s' could not be audited (mktemp failed) -- refusing rather than treating an unaudited store as safe" "$label"
    return 0
  fi
  # A submodule checkout is normally on a DETACHED head, so `--all` alone can miss exactly the
  # commit this guard exists to protect. Resolve HEAD separately and feed it in too.
  # GIT_WORK_TREE: a store whose core.worktree points at a path that no longer exists (what
  # `git rm <submodule>` leaves behind -- fixture N) makes every plain git call fail with
  # "cannot chdir to …". Overriding the work tree lets the audit READ the store; rev-list and
  # cat-file never touch a working tree.
  head_sha="$(GIT_WORK_TREE="$store" git --git-dir="$store" rev-parse --verify --quiet HEAD 2>/dev/null || true)"  # swallow-ok: an UNBORN HEAD is legitimate and simply contributes no tip; a store that cannot be read at all still fails LOUDLY at the rev-list below
  if ! GIT_WORK_TREE="$store" git --git-dir="$store" rev-list --objects --all ${head_sha:+"$head_sha"} \
        >"$tmpd/objs" 2>"$tmpd/err"; then
    printf "private store '%s' could not be enumerated (git rev-list failed: %s) -- refusing rather than reading an unreadable store as empty-and-safe" \
      "$label" "$(tr '\n' ' ' <"$tmpd/err")"
    rm -r -- "$tmpd"
    return 0
  fi
  awk '{print $1}' "$tmpd/objs" >"$tmpd/names"
  if ! GIT_WORK_TREE="$shared" git --git-dir="$shared" cat-file --batch-check <"$tmpd/names" \
        >"$tmpd/chk" 2>"$tmpd/err2"; then
    printf "shared store %s could not be queried for private store '%s' (git cat-file failed: %s) -- refusing" \
      "$shared" "$label" "$(tr '\n' ' ' <"$tmpd/err2")"
    rm -r -- "$tmpd"
    return 0
  fi
  n_missing="$(awk '$2=="missing"' "$tmpd/chk" | wc -l)"
  first="$(awk '$2=="missing"{print $1; exit}' "$tmpd/chk")"
  if [[ "$n_missing" -gt 0 ]]; then
    printf "private store '%s' holds %s object(s) reachable from its own refs that are ABSENT from the shared store %s (first: %s)" \
      "$label" "$n_missing" "$shared" "$first"
  fi
  rm -r -- "$tmpd"
}

private_submodule_stores_unsafe() {
  local w="$1" r="$2"
  local common admin mroot headfile store shared rel reason problems=""
  if ! common="$(git -C "$r" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
     || [[ "$common" != /* ]]; then
    printf "the superproject's absolute common git dir could not be resolved ('git rev-parse --path-format=absolute --git-common-dir' failed or returned a relative path; --path-format needs git >= 2.31, this box reports '%s'). Without it the SHARED submodule stores cannot be located, so nothing can be proved safe" \
      "$(git --version 2>/dev/null || printf '<git --version failed>')"
    return 0
  fi
  if ! admin="$(git -C "$w" rev-parse --path-format=absolute --git-dir 2>/dev/null)" \
     || [[ "$admin" != /* ]]; then
    printf "the worktree's own admin dir could not be resolved ('git -C %s rev-parse --path-format=absolute --git-dir' failed or returned a relative path), so its PRIVATE submodule stores -- the things this force destroys -- cannot be enumerated" \
      "$w"
    return 0
  fi
  mroot="$admin/modules"
  # No private store at all => the force destroys no submodule objects. (git keys its refusal on
  # this directory existing, so in practice we do not reach the hatch without one.)
  [[ -d "$mroot" ]] || return 0
  local listing
  if ! listing="$(mktemp 2>/dev/null)"; then
    printf "the worktree's private submodule stores under %s could not be listed (mktemp failed) -- refusing" "$mroot"
    return 0
  fi
  # find's own exit status matters: a traversal that fails part-way would otherwise hand this
  # loop a SHORT list and read as "no hazardous store found", which is the fail-open shape this
  # rewrite exists to remove.
  if ! find "$mroot" -type f -name HEAD -print0 >"$listing" 2>&1; then
    printf "the worktree's private submodule stores under %s could not be enumerated (find failed: %s) -- refusing rather than auditing a partial list" \
      "$mroot" "$(tr -d '\000' <"$listing" | tr '\n' ' ')"
    rm -- "$listing"
    return 0
  fi
  while IFS= read -r -d '' headfile; do
    store="$(dirname "$headfile")"
    # A git dir has both objects/ and refs/; this rejects logs/HEAD and refs/remotes/*/HEAD,
    # which `find -name HEAD` also matches.
    if [[ -d "$store/objects" && -d "$store/refs" ]]; then
      rel="${store#"$mroot"/}"
      shared="$common/modules/$rel"
      reason="$(_store_unsafe_reason "$store" "$shared" "$rel")"
      if [[ -n "$reason" ]]; then
        problems+="${problems:+; }$reason"
      fi
    fi
  done <"$listing"
  rm -- "$listing"
  printf '%s' "$problems"
}

# ---- 1. worktree removal (never --force) -----------------------------------
if [[ ! -e "$wt" ]]; then
  # Directory already gone (crash / manual rm). Clear the stale admin ref — non-destructive,
  # discards nothing (there is nothing on disk to discard).
  git -C "$repo" worktree prune >/dev/null 2>&1 || true  # swallow-ok: prune is idempotent; a missing/already-pruned entry is fine
  log "prune repo=$repo wt=$wt (dir absent)"
else
  # Capture stderr: it is the ONLY thing that distinguishes a dirty tree (surface+leave is
  # correct) from a structural failure (a permanent leak no amount of committing fixes). It
  # was previously swallowed, so the annex case above masqueraded as "dirty" for weeks on a
  # provably CLEAN tree, and the advice we printed ("commit real work") could never work.
  # LC_ALL=C (id:a290 locale fix): git's refusal is a TRANSLATED string. Under e.g.
  # LC_ALL=de_DE.utf8 it comes back in German, the verbatim comparison in step 1b misses, and
  # while that FAILS CLOSED it then prints the generic "commit real work / gitignore throwaway"
  # advice this whole item exists to eliminate -- sending a human hunting for dirt that does not
  # exist. Pin the locale so the comparison is deterministic wherever this runs.
  if err="$(LC_ALL=C git -C "$repo" worktree remove "$wt" 2>&1)"; then
    log "removed repo=$repo wt=$wt"
  else
    # Dirty (non-ignored untracked or tracked-modified), locked, or otherwise unremovable.
    # Per the no-force policy: SURFACE and LEAVE. Do NOT touch the branch — worktree+branch
    # both stay on disk for a supervised reconcile. Nothing is discarded or forced.
    # ---- 1b. THE NARROW SUBMODULE ESCAPE HATCH (id:a290 shape (b)) -----------
    # SUBMODULE repos are a STRUCTURALLY different case and must not be given the dirty-tree
    # advice: git refuses a worktree whose submodules are populated even when the tree is
    # spotless and the branch fully merged (measured 2026-08-26 on three CLEAN, fully-merged
    # yinyang-puzzle worktrees, the oldest a month old). Telling a human to "commit real work"
    # sends them hunting for dirt that does not exist, and the debris just accumulates --
    # 1.8 GB across five worktrees before the owner disposed of them by hand.
    #
    # The owner ruled 2026-09-01 (TODO id:a290) that this ONE case may force, from inside this
    # one audited script -- the same "deny the raw form, route through the gated script" shape
    # as --discard-residue above. It fires ONLY when ALL FIVE hold, and every one is checked
    # POSITIVELY here rather than inferred:
    #
    #   (1) git's refusal is EXACTLY the recognized submodule refusal (string equality, below);
    #   (2) the worktree's HEAD really is the branch we were handed;
    #   (3) the tree is CLEAN, by our own check, submodule contents included;
    #   (4) the branch is already an ancestor of the repo HEAD (nothing unmerged to lose);
    #   (5) EVERY private submodule store the force is about to delete -- enumerated RECURSIVELY
    #       from `.git/worktrees/<bn>/modules/`, which is what git's refusal is actually keyed on
    #       -- holds only objects that the corresponding SHARED store also has, so destroying it
    #       loses nothing (see step 1a). (1)-(4) all pass legitimately on the data-loss cases (5)
    #       catches, so it is not redundant; and (5) is store-scoped rather than index-scoped
    #       because an index-scoped version was escapable in three independent ways.
    #
    # WHAT roadmap:b02f GOT WRONG, and why (1) is string-matched rather than assumed.
    # b02f documented git as keying this refusal on `.gitmodules` being in the tree. That is
    # FALSE, refuted by fixture 2026-09-01 (git 2.55.0): a worktree with `.gitmodules` present
    # and the gitlink in its index, but the submodule NEVER INITIALIZED, removes cleanly with
    # no force at all. The refusal appears only once the submodule is POPULATED, and it
    # SURVIVES `git submodule deinit --all` even after the gitlink directory itself is removed
    # -- what persists is `.git/worktrees/<wt>/modules/<gitlink-path>`, which git tests for each
    # gitlink in the worktree's index. `deinit` does not remove it. So the presence of
    # `.gitmodules` proves NOTHING about whether this refusal is in play, in either direction,
    # and we never reason from it.
    #
    # WHY (3) CANNOT BE SKIPPED -- the refusal MASKS dirtiness. git validates submodules BEFORE
    # it checks for modified/untracked files, so a DIRTY populated-submodule worktree emits the
    # IDENTICAL message as a clean one. Recognizing the refusal is therefore NOT evidence that
    # the tree is clean, and matching the string alone would force away uncommitted work. Our
    # own `status --porcelain` is the only thing standing between this hatch and that bug.
    # `--ignore-submodules=none` so an edit inside the submodule counts as dirty too.
    #
    # FAIL CLOSED. Nobody has fully characterised the mechanism sustaining the refusal, so any
    # refusal text we do not recognize VERBATIM -- a different git version's wording, a locked
    # worktree, anything -- refuses to force, reports loudly, and exits non-zero. We never infer
    # "it must be the submodule thing".
    #
    # Note we pass exactly ONE `--force`, never `-f -f`: a LOCKED worktree cannot be removed by
    # a single --force, so the lock remains an independent backstop (and empirically git reports
    # the lock refusal in preference to the submodule one, so (1) already fails there).
    submodule_refusal='fatal: working trees containing submodules cannot be moved or removed'
    # OPT-IN gate (owner-ruled 2026-09-01). Enabled only by an explicit
    # WORKTREE_RETIRE_SUBMODULE_FORCE=1; the legacy NO_ kill-switch still WINS, so a caller that
    # sets it can never be silently upgraded into an enable. Written as one predicate so there is
    # a single place to flip when id:a290's dangling-object question is answered.
    hatch_enabled=0
    [[ "${WORKTREE_RETIRE_SUBMODULE_FORCE:-0}" == "1" && "${WORKTREE_RETIRE_NO_SUBMODULE_FORCE:-0}" != "1" ]] && hatch_enabled=1
    if [[ "$err" == "$submodule_refusal" ]] && (( hatch_enabled )); then
      hatch_refused=""
      wt_head="$(git -C "$wt" symbolic-ref --quiet HEAD 2>/dev/null || true)"
      # id:a290 round-3 review, finding 1 -- guard 3 FAILED OPEN and destroyed uncommitted work.
      # `$(git status … 2>/dev/null)` yields EMPTY when git FAILS, and empty read as CLEAN, so an
      # unreadable/corrupt index (chmod 000 .git/worktrees/<bn>/index -- a CRASHED worktree, which
      # this script's header calls "precisely this script's target population") took the force path
      # and deleted uncommitted files. The round-3 "every nonzero git exit refuses" rewrite covered
      # only private_submodule_stores_unsafe; the swallow survived HERE, in the guard the code
      # itself calls "the only thing standing between this hatch and that bug". Capture the exit
      # status SEPARATELY and refuse on it: no output is only evidence of cleanliness when git
      # actually succeeded. Sibling guards 2 and 4 already fail closed.
      wt_status_out="$(git -C "$wt" status --porcelain --ignore-submodules=none 2>/dev/null)" && wt_status_rc=0 || wt_status_rc=$?
      if [[ "$wt_head" != "refs/heads/$branch" ]]; then
        hatch_refused="the worktree's HEAD is '${wt_head:-<detached>}', not the 'refs/heads/$branch' we were handed -- refusing to force a worktree we cannot account for"
      elif (( wt_status_rc != 0 )); then
        hatch_refused="\`git status\` FAILED in the worktree (exit $wt_status_rc) -- its empty output is NOT evidence the tree is clean, and this hatch never forces a tree it could not read. A corrupt or unreadable index is exactly the crashed-worktree case this script exists for. Inspect: git -C $wt status"
      elif [[ -n "$wt_status_out" ]]; then
        # This is the masked-dirty case. Say so explicitly: the operator sees git's submodule
        # message but the real blocker is uncommitted content git never got as far as reporting.
        hatch_refused="the worktree is DIRTY (git's submodule refusal MASKS this -- it validates submodules before it looks for modified/untracked files). Uncommitted content is present and nothing will be forced. Inspect: git -C $wt status"
      elif ! git -C "$repo" merge-base --is-ancestor "refs/heads/$branch" HEAD >/dev/null 2>&1; then
        hatch_refused="branch $branch is NOT an ancestor of the repo HEAD -- it carries unmerged commits, and this hatch never forces away work"
      fi

      # (5) OBJECT-level: every object reachable from the refs of EVERY private submodule store
      # the force is about to delete must also live in the corresponding SHARED store. Scoped to
      # the private STORE (recursively), not to the index -- see step 1a for why the index is the
      # wrong question. Checked last (it is the costliest) and only when the ref-level guards
      # above already passed.
      if [[ -z "$hatch_refused" ]]; then
        missing_objs="$(private_submodule_stores_unsafe "$wt" "$repo")"
        if [[ -n "$missing_objs" ]]; then
          hatch_refused="the worktree's own PRIVATE submodule object stores cannot be shown to be safely duplicated -- $missing_objs. Forcing deletes .git/worktrees/$bn/modules/** and would take the only copy of anything held there, leaving an ALREADY-MERGED superproject gitlink unresolvable ('upload-pack: not our ref'). That breaks main, not just this worktree. Push or fetch those submodule commits into the shared store first (e.g. cd $wt/<submodule> && git push <superproject-store> HEAD), then re-run"
        fi
      fi

      if [[ -z "$hatch_refused" ]]; then
        if ferr="$(LC_ALL=C git -C "$repo" worktree remove --force "$wt" 2>&1)"; then
          msg="submodule-force-hatch $bn: worktree carried POPULATED submodules, which git refuses to remove without --force. Verified first: HEAD is refs/heads/$branch, tree CLEAN (submodules included), branch already an ancestor of HEAD, and every object in every PRIVATE submodule store it carries (nested ones included) also present in the corresponding SHARED store. Force-removed (id:a290 shape (b), owner-ruled 2026-09-01). Nothing uncommitted, no unmerged commit, and no worktree-only submodule object existed to lose."
          log "SUBMODULE-FORCE-HATCH $msg"
          echo "$msg"
          # fall through to the normal branch disposition below
        else
          msg="retire-unretirable $bn: recognized the submodule refusal and the clean+merged preconditions held, but 'git worktree remove --force' ITSELF failed -- LEFT on disk, nothing else attempted (a lock needs 'remove -f -f', which this script deliberately never issues). git said: ${ferr//$'\n'/ }"
          log "SUBMODULE-FORCE-FAILED $msg"
          echo "$msg"
          exit 3
        fi
      else
        msg="retire-unretirable $bn: git refuses this worktree because its SUBMODULES are populated, and the id:a290 escape hatch REFUSED to force it -- $hatch_refused. LEFT on disk with branch $branch untouched; nothing forced, nothing lost. git said: ${err//$'\n'/ }"
        log "UNRETIRABLE-SUBMODULE-HATCH-REFUSED $msg"
        echo "$msg"
        exit 3
      fi
    elif [[ "$err" == *"containing submodules"* ]]; then
      # Recognizably about submodules, but NOT the verbatim string the hatch is allowed to act
      # on (a different git version's wording?), or the hatch was disabled by env. FAIL CLOSED.
      if [[ "${WORKTREE_RETIRE_NO_SUBMODULE_FORCE:-0}" == "1" ]]; then
        why="it is hard-disabled by WORKTREE_RETIRE_NO_SUBMODULE_FORCE=1"
      elif [[ "${WORKTREE_RETIRE_SUBMODULE_FORCE:-0}" != "1" ]]; then
        why="it is OPT-IN and WORKTREE_RETIRE_SUBMODULE_FORCE=1 is not set (owner-ruled 2026-09-01: inert by default until id:a290's dangling-object data-loss path is answered -- an object orphaned by an amended submodule commit is invisible to this guard yet still named by MERGED superproject history)"
      else
        why="git's refusal text is NOT the verbatim form the hatch is permitted to act on, so it refuses to force on an unrecognized refusal (fail closed). If this is a git-version wording change, update submodule_refusal in this script deliberately; never loosen it to a substring"
      fi
      msg="retire-unretirable $bn: this worktree carries SUBMODULES and git refuses to remove it. The id:a290 escape hatch did NOT fire because $why. LEFT on disk deliberately; do NOT go looking for dirt to clean. git said: ${err//$'\n'/ }"
      log "UNRETIRABLE-SUBMODULE-UNRECOGNIZED $msg"
      echo "$msg"
      exit 3
    fi
    # Reached only when the hatch did NOT remove the worktree (it exits 3 itself on refusal,
    # and on success $wt is gone and we fall through to the branch step).
    if [[ -e "$wt" ]]; then
      msg="retire-deferred $bn: worktree unremovable -- LEFT on disk for supervised reconcile. git said: ${err//$'\n'/ } (inspect: git -C $wt status; then commit real work / gitignore throwaway, or remove by hand)"
      log "DEFER $msg"
      echo "$msg"
      exit 3
    fi
  fi
fi

# ---- 2. branch disposition (never -D) --------------------------------------
if git -C "$repo" branch -d "$branch" >/dev/null 2>&1; then
  log "deleted branch=$branch repo=$repo (merged)"
  echo "retired $bn: worktree removed, merged branch $branch deleted"
  exit 0
fi

# `branch -d` refused ⇒ the branch carries unmerged commits.
if [[ "$expect_merged" -eq 1 ]]; then
  msg="retire-anomaly $bn: caller expected $branch merged but 'git branch -d' refused (unmerged commits — main moved or a race?). Worktree already removed; branch KEPT as $branch. Investigate; do NOT -D."
  log "ANOMALY $msg"
  echo "$msg"
  exit 4
fi

# Park: keep the unmerged work as an orphan ref (id:a4e9 — refs ARE the registry). Never -D.
if git -C "$repo" show-ref --verify --quiet "refs/heads/$orphan_ref"; then
  msg="retire-deferred $bn: orphan ref $orphan_ref already exists — branch KEPT as $branch (worktree removed). Reconcile the older orphan by hand."
  log "ORPHAN-COLLISION $msg"
  echo "$msg"
  exit 3
fi
if git -C "$repo" branch -m "$branch" "$orphan_ref" >/dev/null 2>&1; then
  log "parked branch=$branch -> $orphan_ref repo=$repo (unmerged)"
  echo "retired $bn: worktree removed, unmerged branch parked as $orphan_ref (ref kept)"
  exit 0
fi

# Rename itself failed (unexpected) — surface, leave the branch untouched.
msg="retire-deferred $bn: worktree removed but 'git branch -m $branch $orphan_ref' failed — branch KEPT as $branch. Investigate."
log "PARK-FAILED $msg"
echo "$msg"
exit 3
