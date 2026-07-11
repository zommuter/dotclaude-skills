#!/usr/bin/env bash
# relay/scripts/reconcile-repo.sh — bounded side-effecting git reconciliation
# split out of the LLM discovery shard (flip step b, id:a0b6).
#
# Usage: reconcile-repo.sh [--dry-run] --repo <name> --path <abs> [--runid <id>]
#                          [--live-claims <comma-list>] [--main-branch <name>]
#
# Performs ONLY the bounded git ops the shard prose describes
# (relay-loop.js:854-870): SYNC-WITH-ORIGIN (id:c3f7), uv.lock cascade
# commit (id:bae5), and WORKTREE-AWARE reap/park (id:ebfb/3ac8/689c).
# NO classification (that stays classify-repo.sh / classify-verdict.sh).
#
# Architecture (id:77ce, parity oracle for relay-core ebdb-b): the body is
# split into a pure PLAN phase (read-only git observations → an actions/
# surfaced list, zero mutating git calls) and a thin APPLY phase (walks the
# planned action list and performs the mutation for each kind). `--dry-run`
# runs PLAN, emits the SAME JSON, and STOPS before APPLY — no git write
# happens. Without `--dry-run`, PLAN -> APPLY -> emit (identical observable
# behavior to the pre-split script). The `actions`/`surfaced` lists for a
# given input state are IDENTICAL with and without `--dry-run` — that
# identity is the parity oracle.
#
# Emits ONE JSON object on stdout:
#   {"repo":"<name>","actions":[{"kind":"<k>","detail":"<...>"}],"surfaced":[{"repo","reason"}]}
#   kind ∈ {ff-merge, diverged-surface, lock-commit, reap, park, suppress}
#
# Env overrides (hermetic tests):
#   RELAY_WORKTREE_BASE  default ~/.cache/relay/worktrees
set -euo pipefail

repo="" path="" runid="" main_branch=""   # empty ⇒ resolve from HEAD via trunk-branch.sh
# live_claims (id:e3ad fail-closed reap guard, tri-state sum type — id:77ce): bash has
# no Option/sum type, so the three LiveClaims states are modelled as ONE sentinel-bearing
# variable instead of the previous {live_claims_provided bool, live_claims string} PAIR
# (that pair is exactly "the cost of modelling Option as a bool default", id:e3ad):
#   __UNSET__  (default)        → Unknown:   flag never passed, no caller safety context
#   ""         (--live-claims "") → Known-empty: caller checked, nothing is live
#   "a,b"      (--live-claims "a,b") → Known:  caller's live-claimed repo set
# Only the Unknown state fail-closed-refuses every destructive reap/park; the other two
# states differ only in whether $repo appears in the (possibly empty) comma-list.
live_claims="__UNSET__"
dry_run=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    --path) path="$2"; shift 2 ;;
    --runid) runid="$2"; shift 2 ;;
    --live-claims) live_claims="$2"; shift 2 ;;
    --main-branch) main_branch="$2"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    *) echo "reconcile-repo.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$repo" ]] || { echo "reconcile-repo.sh: --repo is required" >&2; exit 2; }
[[ -n "$path" ]] || { echo "reconcile-repo.sh: --path is required" >&2; exit 2; }

# Integration/trunk branch — the reap/park ancestry test (below) MUST compare against the
# branch children actually fork from, not a hardcoded `main`. When --main-branch is absent
# or empty, resolve it from the repo's checked-out HEAD via the single-source trunk-branch.sh
# (a repo on `claude/opusplan` with `main` frozen would otherwise mis-park every worktree).
if [[ -z "$main_branch" ]]; then
  main_branch="$("$(dirname "$0")/trunk-branch.sh" "$path")"
fi

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

# --- PLAN outputs consumed by APPLY (kept minimal: what to mutate, not why) -
plan_ff_upstream=""            # non-empty ⇒ APPLY should `git merge --ff-only <upstream>`
plan_lock_paths=()             # non-empty ⇒ APPLY should add+commit these uv.lock paths
plan_reap=()                   # "<basename>:<branch>" entries ⇒ APPLY should reap
plan_park=()                   # "<basename>:<branch>" entries ⇒ APPLY should park
wtdir="$WORKTREE_BASE/$repo"

if [[ -d "$path/.git" || -f "$path/.git" ]]; then

  # ============================ PLAN (pure, read-only) ======================

  # --- PLAN: SYNC (id:c3f7) --------------------------------------------------
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
      add_action "ff-merge" "fast-forwarded to $upstream"
      plan_ff_upstream="$upstream"
    fi
  fi

  # --- PLAN: LOCK (id:bae5) --------------------------------------------------
  # Plan an in-place uv.lock relock commit when EVERY dirty path is a uv.lock
  # (basename), covering the zkm cascade's nested plugins/*/uv.lock — not just
  # a root uv.lock. Any non-lock dirty path leaves the tree for classify to
  # `block`. NOTE: `ff-merge` above only plans (does not perform) the merge,
  # and only does so when the tree was already clean, so this porcelain read
  # observes the same state PLAN or APPLY would act on.
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
      add_action "lock-commit" "committed uv.lock relock in place (${#lock_paths[@]} lock file(s))"
      plan_lock_paths=("${lock_paths[@]}")
    fi
  fi

  # --- PLAN: WORKTREE reap/park (id:ebfb/3ac8/689c) --------------------------
  if [[ -d "$wtdir" ]]; then
    if [[ "$live_claims" == "__UNSET__" ]]; then
      # --- FAIL-CLOSED GUARD (id:e3ad) --------------------------------------
      # No --live-claims flag was passed at all: the caller supplied NO safety
      # context, so we cannot tell live worktrees apart from stale ones. Refuse
      # every destructive reap/park in this repo and surface loudly instead —
      # this is strictly additive: the live loop (relay-loop.js -> discover-repo.sh)
      # ALWAYS passes --live-claims (even "" when nothing is live), so it never
      # hits this branch; only a caller that forgot the flag does.
      while IFS= read -r bn; do
        [[ -n "$bn" ]] || continue
        [[ -n "$runid" && "$bn" == "$runid"* ]] && continue
        msg="REFUSED reap/park of worktree $bn: --live-claims was not provided (no safety context) — fail-closed guard (id:e3ad)"
        echo "reconcile-repo.sh: WARNING: $msg" >&2
        add_surfaced "$msg"
      done < <(ls -1 "$wtdir" 2>/dev/null || true)
    else
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
          add_action "reap" "reaped stale empty worktree $bn"
          plan_reap+=("$bn:$branch")
        else
          add_action "park" "parked stale worktree $bn to relay/orphan/$bn"
          add_surfaced "parked orphan from a dead run — ref renamed to relay/orphan/$bn for manual /relay reconcile (id:689c)"
          plan_park+=("$bn:$branch")
        fi
      done < <(ls -1 "$wtdir" 2>/dev/null || true)
    fi
  fi

  # --- PLAN: ORPHAN SUPPRESS-REDISPATCH (id:1f53, read-only, no APPLY step) --
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

  # ============================ APPLY (mutating) =============================
  if [[ "$dry_run" -eq 0 ]]; then
    if [[ -n "$plan_ff_upstream" ]]; then
      git -C "$path" merge --ff-only "$plan_ff_upstream" >/dev/null 2>&1
    fi
    if [[ ${#plan_lock_paths[@]} -gt 0 ]]; then
      git -C "$path" add -- "${plan_lock_paths[@]}"
      git -C "$path" commit -q -m "chore: refresh uv.lock — cascade relock (id:bae5)"
    fi
    for entry in "${plan_reap[@]:-}"; do
      [[ -n "$entry" ]] || continue
      bn="${entry%%:*}"; branch="${entry#*:}"
      git -C "$path" worktree remove --force "$wtdir/$bn" >/dev/null 2>&1 || true
      git -C "$path" branch -D "$branch" >/dev/null 2>&1 || true
    done
    for entry in "${plan_park[@]:-}"; do
      [[ -n "$entry" ]] || continue
      bn="${entry%%:*}"; branch="${entry#*:}"
      git -C "$path" branch -m "$branch" "relay/orphan/$bn" >/dev/null 2>&1 || true
      git -C "$path" worktree remove --force "$wtdir/$bn" >/dev/null 2>&1 || true
    done
  fi
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
