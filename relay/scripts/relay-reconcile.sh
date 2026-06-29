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
#   relay-reconcile.sh [REPO_PATH] [--list] [--auto] [--integrate BRANCH] [--discard BRANCH]
#   relay-reconcile.sh --all [--auto]
#
#   (no flag)            List the parked relay/orphan/* branches in REPO_PATH (a synonym
#                        for --list); each line shows the branch and its parked commit.
#                        With no orphans, prints "no parked orphans" and exits 0.
#   --list               Same as no flag: enumerate relay/orphan/* and exit.
#   --auto               AUTO-RECONCILE (id:7809): per parked orphan, run the CONSERVATIVE
#                        safe-vs-judgment classifier — a ledger-only diff (ROADMAP/TODO/
#                        RELAY_LOG/REVIEW_ME/RELAY_STATUS) on a clean, non-diverged base is
#                        auto-INTEGRATED via the same recipe as --integrate; ANY code/test
#                        diff, dirty tree, divergence, empty/unrelated diff is left PARKED and
#                        SURFACED as an open box in REVIEW_ME.md for a human / strong-turn
#                        `/relay review`. The bar is never weaker than a human review (the
#                        meeting invariant). This is the path the loop invokes at startup on a
#                        STALE run heartbeat (id:e149). Unattended-safe (no prompts).
#   --all                Cross-repo: enumerate all relay.toml `classification = "own"` repos
#                        (honoring `# path:` override, RELAY_TOML, SRC_DIR) and run the LIST
#                        action (or, with --auto, the AUTO-RECONCILE pass) across all of them.
#                        An unreadable/missing repo path is SURFACED on stderr (never silently
#                        swallowed). Combining --all with --integrate/--discard is an error.
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
COMMIT_LEDGER="$SCRIPTS_DIR/commit-ledger.sh"
LOCK_PUSH="${RELAY_LOCK_PUSH:-$HOME/.claude/skills/git-diary-workflow/git-lock-push.sh}"
LOG="${RECONCILE_LOG:-$HOME/.claude/logs/relay-reconcile.log}"

ORPHAN_NS="relay/orphan/"

# id:7809 — files whose diff is "ledger-only / trivial" (safe to auto-integrate without
# strong-turn judgment). Matched by BASENAME. Everything else (any code/test/config file)
# makes the orphan a JUDGMENT case that --auto refuses to merge and surfaces instead.
LEDGER_FILES_RE='^(ROADMAP|TODO|TODO\.archive|RELAY_LOG|REVIEW_ME|RELAY_STATUS)\.md$'

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
    --auto)      action="auto"; shift ;;
    --integrate) action="integrate"; target="${2:-}"; shift; shift || true ;;
    --discard)   action="discard";   target="${2:-}"; shift; shift || true ;;
    -h|--help)   sed -n '2,52p' "$0"; exit 0 ;;
    --*)         echo "relay-reconcile.sh: unknown flag '$1'" >&2; exit 2 ;;
    *)           repo="$1"; shift ;;
  esac
done

# --all + --integrate/--discard is nonsensical: reject clearly. --all --auto and --all
# (list) are the only valid cross-repo combinations.
if [[ $all_repos -eq 1 && "$action" != "list" && "$action" != "auto" ]]; then
  printf 'relay-reconcile.sh: --all supports only the cross-repo LIST and --auto passes; --integrate and --discard operate on a single repo.\nUsage: relay-reconcile.sh --all [--auto]\n       relay-reconcile.sh [REPO_PATH] --integrate|--discard BRANCH\n' >&2
  exit 2
fi

# --all (list): cross-repo list — enumerate own repos from relay.toml and list each.
# (--all --auto is handled after the function defs below, since it calls auto_one_repo.)
if [[ $all_repos -eq 1 && "$action" == "list" ]]; then
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

# Single-repo actions need a repo root; --all passes (handled below) do not.
if [[ $all_repos -eq 0 ]]; then
  repo="${repo:-$(git rev-parse --show-toplevel)}"
  git -C "$repo" rev-parse --git-dir >/dev/null
fi

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

# main_ref <repo> — echo the resolvable trunk ref name ('main' or 'master').
main_ref() {
  local r="$1"
  git -C "$r" rev-parse --verify -q main   >/dev/null 2>&1 && { echo main;   return; }
  git -C "$r" rev-parse --verify -q master >/dev/null 2>&1 && { echo master; return; }
  echo main
}

# integrate_branch <repo> <full-branch> — the SAME serialized-integrator recipe the live
# pool + the human `--integrate` use (clean main + sync-origin → merge --no-ff → ckpt-tag →
# --ff-only push → branch -D). Prints a status line; returns 0 on integrate, 1 on
# left/conflict/abort (ref untouched). Shared by `--integrate` and `--auto` so neither can
# silently weaken the checkpoint discipline.
integrate_branch() {
  local repo="$1" br="$2" subj ckpt_tag push_status sync
  git -C "$repo" rev-parse -q --verify "refs/heads/$br" >/dev/null \
    || { echo "relay-reconcile.sh: no such parked branch '$br'" >&2; return 2; }

  # 1. main checkout must be clean — never checkpoint on a dirty tree.
  if [ -n "$(git -C "$repo" status --porcelain)" ]; then
    echo "LEFT $br — main worktree dirty, reconcile aborted (commit/stash first)" >&2
    log "integrate ABORT repo=$repo branch=$br reason=dirty-tree"
    return 1
  fi

  # 1b. Never checkpoint on a base that diverged from origin (the ai-codebench incident, id:c3f7).
  if [ -x "$SYNC_ORIGIN" ]; then
    sync="$("$SYNC_ORIGIN" "$repo" || true)"
    case "$sync" in
      diverged*)
        echo "LEFT $br — base diverged from origin, manual reconcile (sync: $sync)" >&2
        log "integrate ABORT repo=$repo branch=$br reason=diverged sync=$sync"
        return 1 ;;
    esac
  fi

  subj="$(git -C "$repo" log -1 --format='%s' "$br" 2>/dev/null || echo "$br")"

  # 2. git merge --no-ff — --no-ff preserves the 3-way conflict surface (NO CAS plumbing).
  #    On conflict: abort and LEAVE the branch — never half-merge.
  if ! git -C "$repo" merge --no-ff "$br" -m "merge(relay reconcile): $subj"; then
    git -C "$repo" merge --abort || true
    echo "LEFT $br — merge conflict, reconcile aborted (resolve manually); ref untouched" >&2
    log "integrate CONFLICT repo=$repo branch=$br (merge --abort, left + surfaced)"
    return 1
  fi

  # 3. ckpt-tag.sh — atomic RELAY_LOG entry + relay-ckpt-* tag (human cannot skip the tag).
  ckpt_tag="$("$CKPT_TAG" "$repo" -m "reconcile integrate: $subj" -l "reconcile (auto/human)")"

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
  return 0
}

# classify_orphan <repo> <full-branch> — the CONSERVATIVE safe-vs-judgment classifier
# (meeting `docs/meeting-notes/2026-06-22-1546-relay-outage-resilience.md`). Prints "SAFE"
# or "JUDGMENT:<reason>". SAFE requires the orphan's diff vs the trunk merge-base to touch
# ONLY ledger files (LEDGER_FILES_RE). ANY code/test/config file → JUDGMENT: --auto never
# auto-merges code (a strong-turn `/relay review` must judge it), so the bar is never weaker
# than a human review. A missing merge-base or empty diff → JUDGMENT (surface, don't guess).
# Ledger-only ⇒ no test file in the diff ⇒ the mechanical gaming-scan + suite-green criteria
# are vacuously satisfied (nothing executable changed), which is why they aren't re-run here.
classify_orphan() {
  local r="$1" br="$2" mref mb files f base n
  mref="$(main_ref "$r")"
  mb="$(git -C "$r" merge-base "$mref" "$br" 2>/dev/null || true)"
  [ -n "$mb" ] || { echo "JUDGMENT:no merge-base with $mref (unrelated history) — manual /relay reconcile"; return; }
  files="$(git -C "$r" diff --name-only "$mb" "$br" 2>/dev/null || true)"
  [ -n "$files" ] || { echo "JUDGMENT:empty diff vs $mref (already integrated or stale ref) — manual /relay reconcile"; return; }
  local non_ledger=()
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    base="$(basename "$f")"
    printf '%s' "$base" | grep -qE "$LEDGER_FILES_RE" || non_ledger+=("$f")
  done <<<"$files"
  if [ ${#non_ledger[@]} -gt 0 ]; then
    n=${#non_ledger[@]}
    echo "JUDGMENT:non-ledger (code) diff in $n file(s) (e.g. ${non_ledger[0]}) — needs strong-turn review; --auto never auto-merges code"
    return
  fi
  echo SAFE
}

# surface_judgment <repo> <full-branch> <reason> — append ONE open review box to the repo's
# REVIEW_ME.md (the durable human surface; the orphan ref is already parked). The caller
# batches these and commits REVIEW_ME.md once via commit-ledger.sh.
surface_judgment() {
  local r="$1" br="$2" reason="$3" rm="$r/REVIEW_ME.md" sha subj when
  sha="$(git -C "$r" rev-parse --short "$br" 2>/dev/null || echo '???????')"
  subj="$(git -C "$r" log -1 --format='%s' "$br" 2>/dev/null || true)"
  when="$(date '+%Y-%m-%d %H:%M')"
  [ -f "$rm" ] || printf '# Human review queue\n\n' > "$rm"
  printf -- '- [ ] auto-reconcile parked orphan `%s` (%s) — %s. Subject: %s. Surfaced %s by `relay-reconcile.sh --auto` (id:7809); integrate or discard manually: `relay-reconcile.sh --integrate %s` / `--discard %s`.\n' \
    "$br" "$sha" "$reason" "$subj" "$when" "$br" "$br" >> "$rm"
  log "surface repo=$r branch=$br reason=$reason"
}

# auto_one_repo <repo> — the auto-reconcile pass over one repo's parked orphans (id:7809):
# integrate the SAFE (ledger-only) ones via the shared recipe; surface the JUDGMENT ones into
# REVIEW_ME.md. Conservative: a dirty main tree defers ALL integration (surfaces instead).
auto_one_repo() {
  local r="$1" orphans br verdict reason dirty=0 integrated=0
  if ! git -C "$r" rev-parse --git-dir >/dev/null 2>&1; then
    echo "ERROR: $r is not a readable git repo — skipped" >&2
    log "auto SKIP repo=$r reason=not-a-repo"
    return 0
  fi
  orphans="$(git -C "$r" for-each-ref --format='%(refname:short)' "refs/heads/$ORPHAN_NS")"
  if [ -z "$orphans" ]; then
    echo "$r: no parked orphans"
    log "auto repo=$r orphans=0"
    return 0
  fi
  [ -n "$(git -C "$r" status --porcelain)" ] && dirty=1
  local safe=() judg=() jreason=()
  while IFS= read -r br; do
    [ -n "$br" ] || continue
    verdict="$(classify_orphan "$r" "$br")"
    if [ "$verdict" = SAFE ] && [ "$dirty" -eq 0 ]; then
      safe+=("$br")
    elif [ "$verdict" = SAFE ]; then
      judg+=("$br"); jreason+=("main worktree dirty — integration deferred for human review")
    else
      judg+=("$br"); jreason+=("${verdict#JUDGMENT:}")
    fi
  done <<<"$orphans"
  # SAFE first (each integrate commits+pushes, keeping the tree clean for the next).
  for br in "${safe[@]}"; do
    integrate_branch "$r" "$br" && integrated=$((integrated+1)) || true
  done
  # Surface JUDGMENT: append all boxes, then ONE scoped REVIEW_ME.md commit.
  if [ ${#judg[@]} -gt 0 ]; then
    local i=0
    for br in "${judg[@]}"; do surface_judgment "$r" "$br" "${jreason[$i]}"; i=$((i+1)); done
    if [ -x "$COMMIT_LEDGER" ]; then
      "$COMMIT_LEDGER" "$r" -m "relay auto-reconcile: surface ${#judg[@]} parked orphan(s) for human review (id:7809)" REVIEW_ME.md >/dev/null 2>&1 || true
    fi
  fi
  echo "$r: auto-reconcile — $integrated integrated, ${#judg[@]} surfaced for review"
  log "auto repo=$r integrated=$integrated surfaced=${#judg[@]} dirty=$dirty"
}

# --all --auto: run the auto-reconcile pass across every own repo (id:7809). Placed here
# (after the function defs) so auto_one_repo is in scope; the --all list pass exited above.
if [[ $all_repos -eq 1 && "$action" == "auto" ]]; then
  while IFS=$'\t' read -r rname rpath; do
    [[ -n "$rname" ]] || continue
    if [[ ! -d "$rpath" ]]; then
      printf 'NOTE: %s path not found (%s) — not a local checkout; skipped.\n' "$rname" "$rpath" >&2
      continue
    fi
    auto_one_repo "$rpath"
  done < <(own_repos)
  exit 0
fi

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
    integrate_branch "$repo" "$br"
    ;;

  auto)
    # id:7809 — auto-reconcile-on-restart over a single repo's parked orphans.
    auto_one_repo "$repo"
    ;;
esac
