#!/usr/bin/env bash
# relay/scripts/reconcile-repo.sh — bounded side-effecting git reconciliation
# split out of the LLM discovery shard (flip step b, id:a0b6).
#
# Usage: reconcile-repo.sh --repo <name> --path <abs> [--runid <id>]
#                          [--live-claims <comma-list>] [--main-branch <name>]
#
# Performs ONLY the bounded git ops the shard prose describes
# (relay-loop.js:854-870): SYNC-WITH-ORIGIN (id:c3f7), uv.lock cascade
# commit (id:bae5), and WORKTREE-AWARE reap/park (id:ebfb/3ac8/689c).
# NO classification (that stays classify-repo.sh / classify-verdict.sh).
#
# Emits ONE JSON object on stdout:
#   {"repo":"<name>","actions":[{"kind":"<k>","detail":"<...>"}],"surfaced":[{"repo","reason"}]}
#   kind ∈ {ff-merge, diverged-surface, lock-commit, reap, park, suppress}
#
# Env overrides (hermetic tests):
#   RELAY_WORKTREE_BASE  default ~/.cache/relay/worktrees
set -euo pipefail

repo="" path="" runid="" live_claims="" main_branch="main"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    --path) path="$2"; shift 2 ;;
    --runid) runid="$2"; shift 2 ;;
    --live-claims) live_claims="$2"; shift 2 ;;
    --main-branch) main_branch="$2"; shift 2 ;;
    *) echo "reconcile-repo.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$repo" ]] || { echo "reconcile-repo.sh: --repo is required" >&2; exit 2; }
[[ -n "$path" ]] || { echo "reconcile-repo.sh: --path is required" >&2; exit 2; }

WORKTREE_BASE="${RELAY_WORKTREE_BASE:-$HOME/.cache/relay/worktrees}"

# actions/surfaced accumulated as TSV lines, folded into JSON by python3 at the end.
actions_file="$(mktemp)"
surfaced_file="$(mktemp)"
trap 'rm -f "$actions_file" "$surfaced_file"' EXIT

add_action() { # <kind> <detail>
  printf '%s\t%s\n' "$1" "$2" >> "$actions_file"
}
add_surfaced() { # <reason>
  printf '%s\n' "$1" >> "$surfaced_file"
}

if [[ -d "$path/.git" || -f "$path/.git" ]]; then

  # --- SYNC (id:c3f7) -------------------------------------------------------
  if git -C "$path" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' >/dev/null 2>&1; then
    git -C "$path" fetch origin >/dev/null 2>&1 || true
    upstream="$(git -C "$path" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}')"
    ahead="$(git -C "$path" rev-list --count "${upstream}..HEAD" 2>/dev/null || echo 0)"
    behind="$(git -C "$path" rev-list --count "HEAD..${upstream}" 2>/dev/null || echo 0)"
    porcelain="$(git -C "$path" status --porcelain)"

    if [[ "$ahead" -gt 0 && "$behind" -gt 0 ]]; then
      add_action "diverged-surface" "local ahead $ahead / behind $behind vs origin"
      add_surfaced "diverged from origin (local $ahead / origin $behind) — needs manual reconcile (id:c3f7)"
    elif [[ "$ahead" -eq 0 && "$behind" -gt 0 && -z "$porcelain" ]]; then
      git -C "$path" merge --ff-only "$upstream" >/dev/null 2>&1
      add_action "ff-merge" "fast-forwarded to $upstream"
    fi
  fi

  # --- LOCK (id:bae5) --------------------------------------------------------
  # Commit an in-place uv.lock relock when EVERY dirty path is a uv.lock (basename), covering
  # the zkm cascade's nested plugins/*/uv.lock — not just a root uv.lock. Any non-lock dirty
  # path leaves the tree for classify to `block`.
  porcelain="$(git -C "$path" status --porcelain)"
  if [[ -n "$porcelain" ]]; then
    all_lock=true
    lock_paths=()
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      p="${line:3}"                      # strip the "XY " porcelain status prefix
      if [[ "$(basename "$p")" == "uv.lock" ]]; then
        lock_paths+=("$p")
      else
        all_lock=false; break
      fi
    done <<< "$porcelain"
    if [[ "$all_lock" == true && ${#lock_paths[@]} -gt 0 ]]; then
      git -C "$path" add -- "${lock_paths[@]}"
      git -C "$path" commit -q -m "chore: refresh uv.lock — cascade relock (id:bae5)"
      add_action "lock-commit" "committed uv.lock relock in place (${#lock_paths[@]} lock file(s))"
    fi
  fi

  # --- WORKTREE reap/park (id:ebfb/3ac8/689c) --------------------------------
  wtdir="$WORKTREE_BASE/$repo"
  if [[ -d "$wtdir" ]]; then
    IFS=',' read -r -a claims_arr <<< "$live_claims"
    is_live_claimed=false
    for c in "${claims_arr[@]:-}"; do
      [[ -n "$c" && "$c" == "$repo" ]] && is_live_claimed=true
    done

    while IFS= read -r bn; do
      [[ -n "$bn" ]] || continue
      [[ -n "$runid" && "$bn" == "$runid"* ]] && continue

      if [[ "$is_live_claimed" == true ]]; then
        add_surfaced "in-flight elsewhere (worktree $bn) — claimed by another relay run (id:ebfb)"
        continue
      fi

      branch="relay/$bn"
      if git -C "$path" merge-base --is-ancestor "$branch" "$main_branch" 2>/dev/null; then
        git -C "$path" worktree remove --force "$wtdir/$bn" >/dev/null 2>&1 || true
        git -C "$path" branch -D "$branch" >/dev/null 2>&1 || true
        add_action "reap" "reaped stale empty worktree $bn"
      else
        git -C "$path" branch -m "$branch" "relay/orphan/$bn" >/dev/null 2>&1 || true
        git -C "$path" worktree remove --force "$wtdir/$bn" >/dev/null 2>&1 || true
        add_action "park" "parked stale worktree $bn to relay/orphan/$bn"
        add_surfaced "parked orphan from a dead run — ref renamed to relay/orphan/$bn for manual /relay reconcile (id:689c)"
      fi
    done < <(ls -1 "$wtdir" 2>/dev/null || true)
  fi

  # --- ORPHAN SUPPRESS-REDISPATCH (id:1f53) ----------------------------------
  # Once D1 parks partial work into relay/orphan/*, do NOT re-dispatch the item's expensive
  # session. Bind each parked orphan back to its ROADMAP item via `git show --stat` on the
  # parked commit; if that item is still OPEN (or the binding is ambiguous), SURFACE a one-line
  # relay-burn cost hint (which makes discover-repo.sh skip classify → no fresh dispatch). A
  # CLOSED-item orphan does NOT suppress (stale leftover — let it classify; /relay reconcile prunes).
  roadmap="$path/ROADMAP.md"
  while IFS= read -r oref; do
    [[ -n "$oref" ]] || continue
    oid="$(git -C "$path" show --stat "$oref" 2>/dev/null | grep -oE 'id:[0-9a-f]{4}' | head -1 | sed 's/id://' || true)"
    suppress=false; why=""
    if [[ -n "$oid" && -f "$roadmap" ]]; then
      if grep -qE "^[[:space:]]*- \[ \].*id:$oid" "$roadmap"; then
        suppress=true; why="parked partial work for id:$oid still OPEN"
      elif grep -qE "^[[:space:]]*- \[x\].*id:$oid" "$roadmap"; then
        suppress=false   # closed → stale orphan, do not suppress
      else
        suppress=true; why="parked partial work for id:$oid (item not in ROADMAP — ambiguous)"
      fi
    else
      suppress=true; why="parked partial work on $oref (no id binding — ambiguous)"
    fi
    if [[ "$suppress" == true ]]; then
      add_action "suppress" "$why"
      add_surfaced "suppressed re-dispatch: $why on $oref — manual /relay reconcile; cost hint: relay-burn.sh --run ${runid:-<runId>}"
    fi
  done < <(git -C "$path" for-each-ref --format='%(refname:short)' refs/heads/relay/orphan/ 2>/dev/null || true)
fi

ACTIONS_FILE="$actions_file" SURFACED_FILE="$surfaced_file" REPO="$repo" python3 - <<'PYEOF'
import json, os

repo = os.environ["REPO"]

actions = []
with open(os.environ["ACTIONS_FILE"]) as f:
    for ln in f:
        ln = ln.rstrip("\n")
        if not ln:
            continue
        kind, detail = ln.split("\t", 1)
        actions.append({"kind": kind, "detail": detail})

surfaced = []
with open(os.environ["SURFACED_FILE"]) as f:
    for ln in f:
        ln = ln.rstrip("\n")
        if not ln:
            continue
        surfaced.append({"repo": repo, "reason": ln})

print(json.dumps({"repo": repo, "actions": actions, "surfaced": surfaced}))
PYEOF
