#!/usr/bin/env bash
# relay-reconcile.sh — human-invoked disposal of parked orphan branches (id:3313, D2).
#
# After D1 (id:689c) parks the branches of dead/orphaned relay runs into the canonical
# `relay/orphan/*` namespace (the commit stays reachable on the ref, the worktree dir is
# removed), a HUMAN runs `/relay reconcile` to dispose them. This is NEVER auto-triggered
# by the pool — it is a deliberate, interactive decision per parked branch.
#
# Per `relay/orphan/*` branch it offers three choices:
#   integrate — reuse the SAME serialized-integrator recipe the live pool uses, so a human
#               cannot skip the checkpoint tag or race the live pool's push:
#                 1. verify clean main + sync-origin (never checkpoint on a diverged base)
#                 2. git merge --no-ff <orphan>   (--no-ff preserves 3-way conflict surfacing;
#                                                   NO CAS plumbing — conflicts must surface)
#                    on conflict: git merge --abort → LEFT + surfaced, never half-merged
#                 3. ckpt-tag.sh <repo>           (atomic RELAY_LOG entry + relay-ckpt-* tag)
#                 4. git-lock-push.sh --ff-only   (flock'd; --ff-only won't race the pool)
#                 5. git branch -D <orphan>       (ref consumed once integrated+pushed)
#   discard   — git branch -D <orphan>            (drop the parked work entirely)
#   leave     — do nothing, keep the ref for a later pass
#
# Usage:
#   relay-reconcile.sh [REPO_PATH] [--list] [--integrate BRANCH] [--discard BRANCH]
#   relay-reconcile.sh --all
#
#   (no flag)            List the parked relay/orphan/* branches in REPO_PATH (a synonym
#                        for --list); each line shows the branch and its parked commit.
#                        With no orphans, prints "no parked orphans" and exits 0.
#   --list               Same as no flag: enumerate relay/orphan/* and exit.
#   --all                Cross-repo list: enumerate all relay.toml `classification = "own"`
#                        repos (honoring `# path:` override, RELAY_TOML, SRC_DIR) and run
#                        the LIST action across all of them. An unreadable/missing repo path
#                        is SURFACED on stderr (never silently swallowed as "no orphans").
#                        --all is list-only; combining it with --integrate or --discard is
#                        an error (exit 2).
#   --integrate BRANCH   Integrate one parked branch via the merge --no-ff → ckpt-tag →
#                        --ff-only push recipe above. A merge conflict leaves the branch
#                        intact (ref untouched) and surfaces the conflict on stderr.
#   --discard  BRANCH    Drop one parked branch (git branch -D).
#
#   BRANCH may be given with or without the `relay/orphan/` prefix.
#
# REPO_PATH defaults to `git rev-parse --show-toplevel`. All git ops via `git -C <repo>`.
# Short status to stdout; details logged to $RECONCILE_LOG (~/.claude/logs/relay-reconcile.log).
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
CKPT_TAG="$SCRIPTS_DIR/ckpt-tag.sh"
SYNC_ORIGIN="$SCRIPTS_DIR/sync-origin.sh"
LOCK_PUSH="${RELAY_LOCK_PUSH:-$HOME/.claude/skills/git-diary-workflow/git-lock-push.sh}"
LOG="${RECONCILE_LOG:-$HOME/.claude/logs/relay-reconcile.log}"

ORPHAN_NS="relay/orphan/"

# relay.toml location — same default as gather-human-backlog.sh and discover-repos.sh.
SRC_DIR="${SRC_DIR:-$HOME/src}"
RELAY_TOML="${RELAY_TOML:-$HOME/.config/relay/relay.toml}"

mkdir -p "$(dirname "$LOG")"
log() { printf '%s relay-reconcile.sh %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >>"$LOG" 2>/dev/null || true; }

# --- own repos from relay.toml (copied from gather-human-backlog.sh) ----------
# Honors `classification = "own"`, `# path:` comment overrides, and the
# `paused` flag. Outputs lines of "<name>\t<path>".
own_repos() {
  [[ -f "$RELAY_TOML" ]] || return 0
  SRC_DIR="$SRC_DIR" python3 -c '
import os, re, sys, tomllib
src = os.environ["SRC_DIR"]
toml_path = sys.argv[1]
with open(toml_path, "rb") as f:
    data = tomllib.load(f)

# Recover the `# path:` COMMENT override per repo (tomllib drops comments).
comment_path = {}
cur = None
sect_re = re.compile(r"^\s*\[repos\.([^\]]+)\]\s*$")
path_re  = re.compile(r"^\s*#\s*path:\s*(.+?)\s*$")
with open(toml_path, encoding="utf-8") as f:
    for line in f:
        m = sect_re.match(line)
        if m:
            cur = m.group(1)
            continue
        if cur:
            pm = path_re.match(line)
            if pm and cur not in comment_path:
                comment_path[cur] = pm.group(1)

def expand(p):
    return os.path.expanduser(os.path.expandvars(p))

for name, entry in data.get("repos", {}).items():
    if entry.get("classification") != "own":
        continue
    if entry.get("paused"):
        continue
    path = entry.get("path") or comment_path.get(name) or os.path.join(src, name)
    print(f"{name}\t{expand(path)}")
' "$RELAY_TOML"
}

# --- parse args -------------------------------------------------------------
repo=""
action="list"
target=""
all_repos=0
while [ $# -gt 0 ]; do
  case "$1" in
    --all)       all_repos=1; shift ;;
    --list)      action="list"; shift ;;
    --integrate) action="integrate"; target="${2:-}"; shift; shift || true ;;
    --discard)   action="discard";   target="${2:-}"; shift; shift || true ;;
    -h|--help)   sed -n '2,47p' "$0"; exit 0 ;;
    --*)         echo "relay-reconcile.sh: unknown flag '$1'" >&2; exit 2 ;;
    *)           repo="$1"; shift ;;
  esac
done

# --all + --integrate/--discard is nonsensical: reject clearly.
if [[ $all_repos -eq 1 && "$action" != "list" ]]; then
  printf 'relay-reconcile.sh: --all is list-only; --integrate and --discard operate on a single repo.\nUsage: relay-reconcile.sh --all\n       relay-reconcile.sh [REPO_PATH] --integrate|--discard BRANCH\n' >&2
  exit 2
fi

# --all: cross-repo list — enumerate own repos from relay.toml and list each.
if [[ $all_repos -eq 1 ]]; then
  total_orphans=0
  while IFS=$'\t' read -r rname rpath; do
    [[ -n "$rname" ]] || continue
    if [[ ! -d "$rpath" ]]; then
      printf 'NOTE: %s path not found (%s) — not a local checkout; skipped.\n' "$rname" "$rpath" >&2
      continue
    fi
    # Surface git errors (unreadable repo): do NOT use 2>/dev/null.
    if ! git -C "$rpath" rev-parse --git-dir >/dev/null 2>&1; then
      printf 'ERROR: %s (%s) is not a readable git repo — check the path override in relay.toml.\n' "$rname" "$rpath" >&2
      continue
    fi
    branches="$(git -C "$rpath" for-each-ref --format='%(refname:short)' "refs/heads/$ORPHAN_NS")"
    if [[ -z "$branches" ]]; then
      log "--all list repo=$rname orphans=0"
      continue
    fi
    n=0
    while IFS= read -r br; do
      [[ -n "$br" ]] || continue
      sha="$(git -C "$rpath" rev-parse --short "$br" 2>/dev/null || echo '???????')"
      subj="$(git -C "$rpath" log -1 --format='%s' "$br" 2>/dev/null || true)"
      printf '%s\t%s\t%s\t%s\n' "$rname" "$br" "$sha" "$subj"
      n=$((n+1))
    done <<<"$branches"
    total_orphans=$((total_orphans+n))
    log "--all list repo=$rname orphans=$n"
  done < <(own_repos)
  echo "$total_orphans parked orphan(s) across all own repos"
  exit 0
fi

repo="${repo:-$(git rev-parse --show-toplevel)}"
git -C "$repo" rev-parse --git-dir >/dev/null

# Normalize a branch arg to the full relay/orphan/<name> form.
normalize_branch() {
  local b="$1"
  case "$b" in
    "$ORPHAN_NS"*) printf '%s' "$b" ;;
    *)             printf '%s%s' "$ORPHAN_NS" "$b" ;;
  esac
}

# Enumerate parked relay/orphan/* branches (full ref names, newline-separated).
list_orphans() {
  git -C "$repo" for-each-ref --format='%(refname:short)' "refs/heads/$ORPHAN_NS"
}

case "$action" in
  list)
    orphans="$(list_orphans)"
    if [ -z "$orphans" ]; then
      echo "no parked orphans"
      log "list repo=$repo orphans=0"
      exit 0
    fi
    n=0
    while IFS= read -r br; do
      [ -n "$br" ] || continue
      sha="$(git -C "$repo" rev-parse --short "$br" 2>/dev/null || echo '???????')"
      subj="$(git -C "$repo" log -1 --format='%s' "$br" 2>/dev/null || true)"
      printf '%s\t%s\t%s\n' "$br" "$sha" "$subj"
      n=$((n+1))
    done <<<"$orphans"
    echo "$n parked orphan(s) — integrate | discard | leave  (relay-reconcile.sh --integrate|--discard <branch>)"
    log "list repo=$repo orphans=$n"
    ;;

  discard)
    [ -n "$target" ] || { echo "relay-reconcile.sh --discard: <branch> required" >&2; exit 2; }
    br="$(normalize_branch "$target")"
    git -C "$repo" rev-parse -q --verify "refs/heads/$br" >/dev/null \
      || { echo "relay-reconcile.sh: no such parked branch '$br'" >&2; exit 2; }
    # Discard the parked work entirely: git branch -D drops the ref.
    git -C "$repo" branch -D "$br"
    echo "discarded $br"
    log "discard repo=$repo branch=$br"
    ;;

  integrate)
    [ -n "$target" ] || { echo "relay-reconcile.sh --integrate: <branch> required" >&2; exit 2; }
    br="$(normalize_branch "$target")"
    git -C "$repo" rev-parse -q --verify "refs/heads/$br" >/dev/null \
      || { echo "relay-reconcile.sh: no such parked branch '$br'" >&2; exit 2; }

    # 1. main checkout must be clean — never checkpoint on a dirty tree.
    if [ -n "$(git -C "$repo" status --porcelain)" ]; then
      echo "LEFT $br — main worktree dirty, reconcile aborted (commit/stash first)" >&2
      log "integrate ABORT repo=$repo branch=$br reason=dirty-tree"
      exit 1
    fi

    # 1b. Never checkpoint on a base that diverged from origin (the ai-codebench incident, id:c3f7).
    if [ -x "$SYNC_ORIGIN" ]; then
      sync="$("$SYNC_ORIGIN" "$repo" || true)"
      case "$sync" in
        diverged*)
          echo "LEFT $br — base diverged from origin, manual reconcile (sync: $sync)" >&2
          log "integrate ABORT repo=$repo branch=$br reason=diverged sync=$sync"
          exit 1 ;;
      esac
    fi

    subj="$(git -C "$repo" log -1 --format='%s' "$br" 2>/dev/null || echo "$br")"

    # 2. git merge --no-ff — --no-ff preserves the 3-way conflict surface (NO CAS plumbing).
    #    On conflict: abort and LEAVE the branch — never half-merge.
    if ! git -C "$repo" merge --no-ff "$br" -m "merge(relay reconcile): $subj"; then
      git -C "$repo" merge --abort || true
      echo "LEFT $br — merge conflict, reconcile aborted (resolve manually); ref untouched" >&2
      log "integrate CONFLICT repo=$repo branch=$br (merge --abort, left + surfaced)"
      exit 1
    fi

    # 3. ckpt-tag.sh — atomic RELAY_LOG entry + relay-ckpt-* tag (human cannot skip the tag).
    ckpt_tag="$("$CKPT_TAG" "$repo" -m "reconcile integrate: $subj" -l "reconcile (human)")"

    # 4. git-lock-push.sh --ff-only — flock'd push; --ff-only won't race/clobber the live pool.
    if [ -x "$LOCK_PUSH" ]; then
      "$LOCK_PUSH" "$repo" --ff-only
      push_status="pushed"
    else
      push_status="push-skipped (no git-lock-push.sh)"
    fi

    # 5. ref consumed — the committed work is now on main, tagged and pushed.
    git -C "$repo" branch -D "$br"

    echo "integrated $br → $ckpt_tag ($push_status)"
    log "integrate OK repo=$repo branch=$br tag=$ckpt_tag push=$push_status"
    ;;
esac
