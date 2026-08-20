#!/usr/bin/env bash
# integrate.sh — standalone MECHANICAL relay integrator (seam of id:a955, id:9e50).
#
# WHY THIS EXISTS: the relay integrator was an ~11-step Sonnet AGENT prompt inside
# relay-loop.js integrate() (~2696-2909). Every step is DETERMINISTIC — release the
# lease, gate the tree, verify isolation, sync, merge --no-ff, bump, changelog, tag,
# push, retire, write state — so it belongs in a fail-closed shell script, not an LLM
# turn on the merge-to-main critical path. This is the BUILD half; the relay-loop.js
# rewire is a SEPARATE seam (id:087b). This file DOES NOT touch relay-loop.js.
#
# It runs the SAME 11 deterministic steps, in order:
#   0. lease-release   (best-effort; the child's work is done)
#   1. clean-tree gate (id:aa93 — FAIL-CLOSED before any mutation; NEVER force-clean)
#   2. verify-isolation(id:f682/7612 — worktree really carried the work)
#   3. sync-origin     (id:c3f7 — never checkpoint on a diverged base)
#   4. merge --no-ff   (conflict => abort, main unmoved)
#   5. version-bump    (SemVer — the user-observable judgement is an EXPLICIT input,
#                       --level; absent => no bump. Never embedded/guessed here.)
#   6. changelog-append(id:b8fa)
#   7. ckpt-tag        (id:1a34 label; -c reviewed-tip for the zero-commit case)
#   8. git-lock-push   (--ff-only; the only network step)
#   9. worktree-retire (id:373e force-free; id:6e02 scope = EXACTLY this unit's pair)
#  10. state-write     (id:ebfb flock'd relay.toml single-writer)
#
# ── id:aa93 ENFORCED IN-SCRIPT, not documented ──────────────────────────────────────
# The clean-tree gate is step 1 and its non-zero exit HANDS BACK before ANY merge, tag,
# push, retire, or state write runs. This script contains NO `git stash`, `git checkout
# --`, `git reset --hard`, or `git clean` ANYWHERE — a foreign-dirty main is DEFERRED,
# never force-cleaned. The enforcement IS the ordering + the total absence of those ops,
# proven by tests/test_integrate_sh_mechanized.sh (a foreign-dirty file survives byte-for
# -byte and no merge lands), not by this comment.
#
# ── id:6e02 ENFORCED IN-SCRIPT ──────────────────────────────────────────────────────
# worktree-retire is invoked with EXACTLY the one <worktree> + <branch> passed on the
# command line — no globbing, no discovery, no "tidy other relay/*". A parallel child's
# worktree is never touched.
#
# ── FAIL-CLOSED, LOUD, DISTINCT EXITS ───────────────────────────────────────────────
# Each step maps its own failure to a DISTINCT non-zero exit code and prints a loud
# HANDBACK[<step>] line to stderr. The caller records it durably and does not re-merge.
#
# Usage:
#   integrate.sh --repo <name> --path <main-checkout> --worktree <dir> --branch <branch> \
#                --summary <text> --run <runId> --label <ckpt-label> \
#                [--ids a,b] [--level minor|patch] [--reviewed-tip <sha>] \
#                [--verdict execute|hard|review|handoff] [--intensive <resource>]
#
# Helper resolution (all overridable for hermetic tests — the failure-injection seam):
#   INTEGRATE_CLAIM INTEGRATE_CLEAN_TREE_GATE INTEGRATE_VERIFY_ISOLATION
#   INTEGRATE_SYNC_ORIGIN INTEGRATE_VERSION_BUMP INTEGRATE_CHANGELOG_APPEND
#   INTEGRATE_CKPT_TAG INTEGRATE_GIT_LOCK_PUSH INTEGRATE_WORKTREE_RETIRE
#   INTEGRATE_STATE_WRITE
set -euo pipefail

# ── distinct exit codes (per step) ──
EX_USAGE=2
EX_CLEAN_TREE=20
EX_ISOLATION=21
EX_SYNC=22
EX_MERGE=23
EX_VERSION=24
EX_CHANGELOG=25
EX_CKPT=26
EX_PUSH=27
EX_RETIRE=28
EX_STATE=29

LOG="${INTEGRATE_LOG:-$HOME/.claude/logs/relay-integrate.log}"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
log()  { printf '%s integrate.sh %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >>"$LOG" 2>/dev/null || true; }
# LOUD handback: name the step, print the reason to stderr, log it, exit with the step's
# distinct code. Never swallowed.
handback() { # <step-label> <exit-code> <reason...>
  local step="$1" code="$2"; shift 2
  printf 'integrate.sh: HANDBACK[%s]: %s\n' "$step" "$*" >&2
  log "HANDBACK[$step] exit=$code $*"
  exit "$code"
}

# ── helper resolution ──
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"   # relay/scripts → repo root (dotclaude-skills)
CLAIM="${INTEGRATE_CLAIM:-$SCRIPT_DIR/claim.sh}"
CLEAN_TREE="${INTEGRATE_CLEAN_TREE_GATE:-$SCRIPT_DIR/clean-tree-gate.sh}"
VERIFY_ISO="${INTEGRATE_VERIFY_ISOLATION:-$SCRIPT_DIR/verify-isolation.sh}"
SYNC_ORIGIN="${INTEGRATE_SYNC_ORIGIN:-$SCRIPT_DIR/sync-origin.sh}"
VERSION_BUMP="${INTEGRATE_VERSION_BUMP:-$SCRIPT_DIR/version-bump.sh}"
CHANGELOG="${INTEGRATE_CHANGELOG_APPEND:-$SCRIPT_DIR/changelog-append.sh}"
CKPT_TAG="${INTEGRATE_CKPT_TAG:-$SCRIPT_DIR/ckpt-tag.sh}"
GIT_LOCK_PUSH="${INTEGRATE_GIT_LOCK_PUSH:-$REPO_ROOT/git-diary-workflow/git-lock-push.sh}"
WORKTREE_RETIRE="${INTEGRATE_WORKTREE_RETIRE:-$SCRIPT_DIR/worktree-retire.sh}"
STATE_WRITE="${INTEGRATE_STATE_WRITE:-$SCRIPT_DIR/relay-state-write.sh}"

# ── args ──
repo="" path="" worktree="" branch="" summary="" run="" label=""
ids="" level="" reviewed_tip="" verdict="execute" intensive=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo)         repo="${2:-}"; shift 2 ;;
    --path)         path="${2:-}"; shift 2 ;;
    --worktree)     worktree="${2:-}"; shift 2 ;;
    --branch)       branch="${2:-}"; shift 2 ;;
    --summary)      summary="${2:-}"; shift 2 ;;
    --run)          run="${2:-}"; shift 2 ;;
    --label)        label="${2:-}"; shift 2 ;;
    --ids)          ids="${2:-}"; shift 2 ;;
    --level)        level="${2:-}"; shift 2 ;;
    --reviewed-tip) reviewed_tip="${2:-}"; shift 2 ;;
    --verdict)      verdict="${2:-}"; shift 2 ;;
    --intensive)    intensive="${2:-}"; shift 2 ;;
    *) echo "integrate.sh: unknown arg '$1'" >&2; exit "$EX_USAGE" ;;
  esac
done
for req in repo path worktree branch summary run label; do
  eval "v=\${$req}"
  [ -n "${v:-}" ] || { echo "integrate.sh: --$req is required" >&2; exit "$EX_USAGE"; }
done
[ -d "$path/.git" ] || [ -f "$path/.git" ] || { echo "integrate.sh: --path '$path' is not a git checkout" >&2; exit "$EX_USAGE"; }
case "$level" in ""|minor|patch) : ;; *) echo "integrate.sh: --level must be minor|patch (got '$level')" >&2; exit "$EX_USAGE" ;; esac

idsuffix=""
[ -n "$ids" ] && idsuffix=" (${ids})"

log "START repo=$repo path=$path branch=$branch worktree=$worktree run=$run level=${level:-none}"

# ── step 0: lease-release (best-effort; the child's work is done, so this must run
#            whether the merge below succeeds or aborts; a no-op if this run does not
#            hold it) ──
"$CLAIM" release "$repo" --run "$run" >/dev/null 2>&1 || log "step0 lease-release non-zero (best-effort, ignored) repo=$repo"
if [ -n "$intensive" ]; then
  "$CLAIM" release "resource:$intensive" --run "$run" >/dev/null 2>&1 || log "step0 resource-lease-release non-zero (best-effort) res=$intensive"
fi

# ── step 1: clean-tree gate (id:aa93) — FAIL-CLOSED before ANY mutation. On non-zero
#            we DEFER: no merge, no destructive tree op, no force-clean. ──
if ! ct_out="$("$CLEAN_TREE" "$path" 2>&1)"; then
  handback clean-tree "$EX_CLEAN_TREE" "main checkout dirty — a concurrent edit is present; deferring to avoid data loss (id:aa93). $ct_out"
fi

# ── step 2: isolation gate (id:f682/7612) — did the child actually work in its worktree? ──
if ! iso_out="$("$VERIFY_ISO" "$worktree" 2>&1)"; then
  handback verify-isolation "$EX_ISOLATION" "isolation gate failed — worktree/main-checkout isolation breach suspected; deferring (id:7612). $iso_out"
fi

# ── step 3: sync-origin (id:c3f7) — never checkpoint on a base diverged from origin. ──
sync_out="$("$SYNC_ORIGIN" "$path" 2>&1)" || true
case "$sync_out" in
  diverged*) handback sync-origin "$EX_SYNC" "base diverged from origin — manual reconcile (id:c3f7). $sync_out" ;;
esac

# ── step 4: merge --no-ff. On conflict/failure: abort (main unmoved), hand back. ──
pre_head="$(git -C "$path" rev-parse HEAD)"
if ! git -C "$path" merge --no-ff "$branch" -m "merge(relay): $summary" >/dev/null 2>&1; then
  git -C "$path" merge --abort >/dev/null 2>&1 || true
  post_head="$(git -C "$path" rev-parse HEAD)"
  [ "$pre_head" = "$post_head" ] || handback merge "$EX_MERGE" "merge conflict AND abort failed to restore main (was $pre_head now $post_head) — HUMAN reconcile"
  handback merge "$EX_MERGE" "merge --no-ff $branch conflicted; aborted, main unmoved at $pre_head; worktree stays on disk"
fi
merged_head="$(git -C "$path" rev-parse HEAD)"

# ── step 5: version-bump (SemVer). The user-observable judgement is the EXPLICIT --level
#            input; absent => NO bump (a refactor-only close, or version-less repo). ──
bump_version=""
if [ -n "$level" ]; then
  if ! bump_version="$("$VERSION_BUMP" "$path" --level "$level" 2>&1)"; then
    handback version-bump "$EX_VERSION" "version-bump --level $level failed: $bump_version"
  fi
  # strip anything that is not a leading vX.Y.Z (the helper prints the tag or nothing)
  bump_version="$(printf '%s' "$bump_version" | grep -oE '^v[0-9]+\.[0-9]+\.[0-9]+' || true)"
fi

# ── step 6: changelog-append (id:b8fa). No-op unless the repo already has a CHANGELOG.md
#            (or a real bump just created one via --version). ──
cl_args=("$path" --summary "$summary")
[ -n "$ids" ] && cl_args+=(--ids "$ids")
[ -n "$bump_version" ] && cl_args+=(--version "$bump_version")
if ! cl_out="$("$CHANGELOG" "${cl_args[@]}" 2>&1)"; then
  handback changelog-append "$EX_CHANGELOG" "changelog-append failed: $cl_out"
fi
# Commit CHANGELOG.md ONLY if it actually changed (scoped staging, id:debf — never -A).
if [ -n "$(git -C "$path" status --porcelain -- CHANGELOG.md 2>/dev/null)" ]; then
  git -C "$path" add -- CHANGELOG.md
  git -C "$path" commit -q -m "docs(changelog): $summary" || handback changelog-append "$EX_CHANGELOG" "changelog commit failed"
fi

# ── step 7: ckpt-tag (id:1a34 label). -c reviewed-tip ONLY for the zero-commit case. ──
ckpt_args=("$path" -m "${summary}${idsuffix}" -l "$label")
[ -n "$reviewed_tip" ] && ckpt_args+=(-c "$reviewed_tip")
if ! ckpt_tag="$("$CKPT_TAG" "${ckpt_args[@]}" 2>&1)"; then
  handback ckpt-tag "$EX_CKPT" "ckpt-tag failed: $ckpt_tag"
fi
ckpt_tag="$(printf '%s' "$ckpt_tag" | tail -n1)"

# ── step 8: git-lock-push --ff-only (the only network step). ──
if ! push_out="$("$GIT_LOCK_PUSH" --ff-only "$path" 2>&1)"; then
  handback git-lock-push "$EX_PUSH" "push failed (merge + tag are committed locally; retry push): $push_out"
fi

# ── step 9: worktree-retire (id:373e force-free; id:6e02 scope = EXACTLY this pair). ──
#    No globbing, no discovery — the two artifacts named on the command line, nothing else.
retire_note=""
if ! retire_note="$("$WORKTREE_RETIRE" "$path" "$worktree" "$branch" --expect-merged 2>&1)"; then
  handback worktree-retire "$EX_RETIRE" "worktree-retire failed (branch merged+pushed; worktree left on disk for supervised reconcile): $retire_note"
fi

# ── step 10: state-write (id:ebfb flock'd relay.toml single-writer). Change ONLY this
#             repo's block. ──
if ! "$STATE_WRITE" toml-set "$repo" last_ckpt "\"$ckpt_tag\"" >/dev/null 2>&1; then
  handback state-write "$EX_STATE" "relay-state-write last_ckpt failed for [repos.$repo]"
fi
status_val="active"
case "$verdict" in handoff) status_val="handed-off" ;; esac
if ! "$STATE_WRITE" toml-set "$repo" status "\"$status_val\"" >/dev/null 2>&1; then
  handback state-write "$EX_STATE" "relay-state-write status failed for [repos.$repo]"
fi
if [ "$verdict" = "review" ]; then
  "$STATE_WRITE" toml-set "$repo" last_review "\"$(date +%F)\"" >/dev/null 2>&1 \
    || handback state-write "$EX_STATE" "relay-state-write last_review failed for [repos.$repo]"
fi

log "DONE repo=$repo merged=$merged_head ckpt=$ckpt_tag bump=${bump_version:-none}"
# Machine-readable success line for the caller (the relay-loop.js rewire, id:087b).
printf 'merged=%s ckpt=%s bump=%s retire=%s\n' "$merged_head" "$ckpt_tag" "${bump_version:-}" "${retire_note:-}"
exit 0
