#!/usr/bin/env bash
# auto-integrate-orphan.sh — the BOUNDED auto-integrate primitive for stranded
# relay orphans (id:1048; meeting 2026-07-23-1735 A1 "orphan existence never
# blocks", amends a4e9-D1's "NO auto-integration").
#
# Extends the id:2370 ledger-only auto-integrate path to CODE-BEARING orphans,
# under a HARD-bounded contract: a parked orphan is auto-completed IFF ALL of —
#   • COMPLETE          — the orphan's bound item is ticked (`[x]`) / no open box.
#   • non-diverged      — the repo's main is not ahead+behind its origin.
#   • clean 3-way merge — merges onto CURRENT main with NO conflict.
#   • full-suite GREEN  — the ENTIRE suite passes in a SCRATCH worktree POST-merge.
# On success it runs the standard integrate (merge --no-ff → ckpt-tag → --ff-only
# push → force-free branch -d), advancing main. On ANY failure (partial, any
# conflict, any red, any divergence) it LEAVES the orphan PARKED, main UNCHANGED,
# and SURFACES for a human `/relay reconcile` — it NEVER force-merges, never
# auto-resolves, and NEVER uses --force / git branch -D / reset --hard / clean
# (force-free discipline, id:373e). The dry-run merge + suite run happen in a
# throwaway detached worktree so the real main checkout is untouched until the
# integrate is proven safe.
#
# Usage:
#   auto-integrate-orphan.sh --repo <main-checkout-abs> --orphan-branch <relay/orphan/*>
#                            [--main-branch <name>]
#   Suite command injectable via env RELAY_SUITE_CMD (default "make test"),
#   run in the scratch worktree post-merge; a red suite ⇒ NOT integrated.
#
# Exit 0  = auto-integrated (main advanced --no-ff to include the orphan; orphan retired).
# Exit !0 = left parked + surfaced (main UNCHANGED; orphan branch intact); reason on stderr.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CKPT_TAG="$SCRIPT_DIR/ckpt-tag.sh"
SYNC_ORIGIN="$SCRIPT_DIR/sync-origin.sh"
TRUNK_BRANCH="$SCRIPT_DIR/trunk-branch.sh"
LOCK_PUSH="${RELAY_LOCK_PUSH:-$HOME/.claude/skills/git-diary-workflow/git-lock-push.sh}"
SUITE_CMD="${RELAY_SUITE_CMD:-make test}"

LOG="${AUTO_INTEGRATE_LOG:-$HOME/.claude/logs/relay-reconcile.log}"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
log() { printf '%s auto-integrate-orphan.sh %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >>"$LOG" 2>/dev/null || true; }

err() { echo "ERROR: $*" >&2; }

# A refusal is not an error condition of the tool — it is a normal outcome. Print a
# uniform SURFACE line (contains the words a human/scanner greps: surface/reconcile/park)
# and return non-zero. Main is guaranteed untouched by the caller's control flow.
surface() {  # <reason>
  echo "PARKED (surfaced for human /relay reconcile): $1" >&2
  log "surfaced repo=$REPO branch=$ORPHAN reason=$1"
}

REPO="" ORPHAN="" MAIN_BRANCH=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)          REPO="$2"; shift 2 ;;
    --orphan-branch) ORPHAN="$2"; shift 2 ;;
    --main-branch)   MAIN_BRANCH="$2"; shift 2 ;;
    *) err "unknown argument: $1"; exit 2 ;;
  esac
done

[[ -n "$REPO" && -n "$ORPHAN" ]] || {
  err "usage: auto-integrate-orphan.sh --repo <dir> --orphan-branch <relay/orphan/*> [--main-branch <name>]"
  exit 2
}
[[ -d "$REPO/.git" || -e "$REPO/.git" ]] || { err "not a git repo: $REPO"; exit 2; }
[[ -x "$CKPT_TAG" ]] || { err "ckpt-tag.sh not found/executable: $CKPT_TAG"; exit 2; }
git -C "$REPO" rev-parse -q --verify "refs/heads/$ORPHAN" >/dev/null 2>&1 \
  || { err "orphan branch not found: $ORPHAN"; exit 2; }

# Resolve the trunk/main branch (default: the branch the main checkout is ON).
if [[ -z "$MAIN_BRANCH" ]]; then
  MAIN_BRANCH="$("$TRUNK_BRANCH" "$REPO" 2>/dev/null || echo main)"
fi
git -C "$REPO" rev-parse -q --verify "refs/heads/$MAIN_BRANCH" >/dev/null 2>&1 \
  || { err "main branch not found: $MAIN_BRANCH"; exit 2; }

# The integrate merges into the checked-out branch — it MUST be the main branch.
cur="$(git -C "$REPO" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
[[ "$cur" == "$MAIN_BRANCH" ]] || {
  err "repo HEAD is '$cur', expected main branch '$MAIN_BRANCH' checked out"; exit 2; }

# The main checkout must be clean — never merge/checkpoint on a dirty tree.
if [[ -n "$(git -C "$REPO" status --porcelain)" ]]; then
  surface "main worktree dirty — cannot integrate on an uncommitted tree"
  exit 1
fi

# ---------------------------------------------------------------------------------------------
# GATE 1 — COMPLETE. Bind the orphan to its item id (the `id:XXXX` in its HEAD commit message)
# and require that item's ROADMAP/TODO box to be TICKED on the orphan. A still-open `[ ]` box
# for the bound item ⇒ PARTIAL ⇒ parked (never auto-close mid-flight work). An UNBINDABLE
# orphan (no id token) is allowed to proceed on the strength of the suite-green gate alone
# (meeting A3: a complete unbound orphan is consumed here; the suite is the real safety).
# ---------------------------------------------------------------------------------------------
item="$(git -C "$REPO" log -1 --format='%B' "$ORPHAN" 2>/dev/null \
          | grep -oiE 'id:[0-9a-fA-F]{4,}' | head -n1 | cut -d: -f2 || true)"
if [[ -n "$item" ]]; then
  orphan_ledger="$(
    git -C "$REPO" show "$ORPHAN:ROADMAP.md" 2>/dev/null || true
    git -C "$REPO" show "$ORPHAN:TODO.md"    2>/dev/null || true
  )"
  if printf '%s\n' "$orphan_ledger" | grep -qiE "^\s*-\s*\[ \].*id:$item\b"; then
    surface "item id:$item still has an OPEN checkbox on the orphan (PARTIAL) — human reconcile"
    exit 1
  fi
  if ! printf '%s\n' "$orphan_ledger" | grep -qiE "^\s*-\s*\[x\].*id:$item\b"; then
    surface "item id:$item is not marked COMPLETE ([x]) on the orphan — human reconcile"
    exit 1
  fi
else
  log "unbindable orphan (no id: token in HEAD commit) repo=$REPO branch=$ORPHAN — proceeding on suite-green (A3)"
fi

# ---------------------------------------------------------------------------------------------
# GATE 2 — NON-DIVERGED. Never checkpoint on a main that diverged from origin (id:c3f7).
# "diverged" (ahead+behind) blocks; behind / in-sync / no-upstream are fine.
# ---------------------------------------------------------------------------------------------
if [[ -x "$SYNC_ORIGIN" ]]; then
  sync="$("$SYNC_ORIGIN" "$REPO" 2>/dev/null || true)"
  case "$sync" in
    diverged*)
      surface "main diverged from origin ($sync) — human reconcile before integrate"
      exit 1 ;;
  esac
fi

# ---------------------------------------------------------------------------------------------
# GATE 3 + 4 — CLEAN 3-WAY MERGE and FULL-SUITE GREEN, both PROVEN in a throwaway detached
# scratch worktree at the current main tip. The real main checkout is never touched here, so
# a conflict or a red suite leaves main + the orphan exactly as they were.
# ---------------------------------------------------------------------------------------------
main_sha="$(git -C "$REPO" rev-parse "$MAIN_BRANCH")"
SCRATCH="$(mktemp -d)"
cleanup_scratch() {
  # Force-free teardown of OUR OWN throwaway worktree (mktemp-style, id:373e-safe):
  # try a plain `git worktree remove`; if untracked suite artifacts make it refuse,
  # fall back to rm -rf + prune. Never touches the orphan or main.
  git -C "$REPO" worktree remove "$SCRATCH" >/dev/null 2>&1 \
    || { rm -rf "$SCRATCH"; git -C "$REPO" worktree prune >/dev/null 2>&1 || true; }
}
trap cleanup_scratch EXIT

if ! git -C "$REPO" worktree add -q --detach "$SCRATCH" "$main_sha" 2>/dev/null; then
  err "could not create scratch worktree at $SCRATCH"
  exit 2
fi

# Dry-run 3-way merge in the scratch worktree — --no-ff preserves the real conflict surface
# (no CAS plumbing). A conflict ⇒ clean abort ⇒ parked. Never auto-resolve.
if ! git -C "$SCRATCH" -c user.email=relay@local -c user.name=relay-auto-integrate \
       merge --no-ff --no-edit "$ORPHAN" >/dev/null 2>&1; then
  git -C "$SCRATCH" merge --abort >/dev/null 2>&1 || true
  surface "orphan does NOT merge cleanly onto $MAIN_BRANCH (conflict) — human reconcile, never auto-resolve"
  exit 1
fi

# Full suite in the POST-merge scratch tree. A red suite ⇒ NOT integrated.
if ! ( cd "$SCRATCH" && eval "$SUITE_CMD" ) >/dev/null 2>&1; then
  surface "post-merge suite is RED (\"$SUITE_CMD\") — orphan left parked, human reconcile"
  exit 1
fi

# ---------------------------------------------------------------------------------------------
# ALL GATES GREEN → the standard integrate on the REAL main checkout: merge --no-ff → ckpt-tag
# → --ff-only push → force-free branch -d. (Re-merging on the same base is proven clean by the
# scratch dry-run above.)
# ---------------------------------------------------------------------------------------------
subj="$(git -C "$REPO" log -1 --format='%s' "$ORPHAN" 2>/dev/null || echo "$ORPHAN")"

if ! git -C "$REPO" -c user.email=relay@local -c user.name=relay-auto-integrate \
       merge --no-ff --no-edit "$ORPHAN" -m "merge(relay auto-integrate): $subj" >/dev/null 2>&1; then
  # Should not happen (scratch proved it clean) — but never leave a half-merge.
  git -C "$REPO" merge --abort >/dev/null 2>&1 || true
  surface "unexpected conflict on the real-main merge (base moved?) — human reconcile"
  exit 1
fi

# ckpt-tag.sh — atomic RELAY_LOG entry + relay-ckpt-* annotated tag (cannot be skipped).
if ! ckpt_tag="$("$CKPT_TAG" "$REPO" -m "auto-integrate orphan: $subj" -l "auto-integrate (id:1048)" 2>>"$LOG")"; then
  err "ckpt-tag failed after merge — main advanced but not tagged; surfacing"
  # Main already advanced (merge committed); the tag failure is surfaced but the integrate stands.
  ckpt_tag="(ckpt-tag-failed)"
fi

# --ff-only flock'd push (best-effort): won't race/clobber the live pool. A push failure is
# surfaced but does NOT void the local integrate (the work IS on main; a later push recovers).
push_status="push-skipped (no git-lock-push.sh)"
if [[ -x "$LOCK_PUSH" ]]; then
  if "$LOCK_PUSH" "$REPO" --ff-only >>"$LOG" 2>&1; then
    push_status="pushed"
  else
    push_status="push-failed (surfaced; integrate stands locally)"
    err "auto-integrate: push failed for $REPO (integrate stands locally); $push_status"
  fi
fi

# The orphan ref is LEFT in place (now a merged ancestor of main). It is harmless — a
# subsequent `/relay reconcile` / cleanup pass retires merged refs with a force-free
# `git branch -d`. Deleting it here would only remove the resolvable ancestor handle;
# auto-integrate's job is to advance main, not to prune refs.
echo "auto-integrated $ORPHAN → $MAIN_BRANCH ($ckpt_tag, $push_status)"
log "auto-integrated repo=$REPO branch=$ORPHAN tag=$ckpt_tag push=$push_status"
exit 0
