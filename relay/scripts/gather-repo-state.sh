#!/usr/bin/env bash
# gather-repo-state.sh (id:11ad) — emit ALL the per-repo state a discover-shard needs to
# classify a repo, in ONE call, as a single JSON object.
#
# WHY: the shard classifier used to run ~17 git/grep commands PER REPO inline, taking ~one
# assistant turn each → a 6-repo shard ran ~120 turns, and each turn re-read the growing
# cached context, so cache_read summed to ~1.9M tokens/shard (~46% of shard cost; the prompt
# itself is only ~0.7%). Measured 2026-06-18 — the cost driver is TURN COUNT, not prompt size
# or context size. This helper collapses the per-repo gathering into ONE Bash call so the
# shard does ~1 turn/repo instead of ~17 → ~10x fewer turns → cache_read drops proportionally.
# It gathers the SAME facts discover-sig.sh hashes (so the classifier sees identical inputs) —
# behavior-preserving; the verdict JUDGMENT stays in the shard prompt (gated by shard-canary).
#
# I/O: gather-repo-state.sh --repo <name> --path <abs> [--runid <id>]
#      emits ONE JSON object on stdout (see fields below). FAIL-OPEN: a non-git path emits
#      {"is_git": false, ...} (exit 0) so the shard surfaces it rather than crashing the round.
#
# Env overrides (hermetic tests; default to the live relay locations):
#   RELAY_TOML           default ~/.config/relay/relay.toml
#   RELAY_WORKTREE_BASE  default ~/.cache/relay/worktrees
set -euo pipefail

RELAY_TOML="${RELAY_TOML:-$HOME/.config/relay/relay.toml}"
RELAY_WORKTREE_BASE="${RELAY_WORKTREE_BASE:-$HOME/.cache/relay/worktrees}"

repo="" path="" runid=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)  repo="$2"; shift 2 ;;
    --path)  path="$2"; shift 2 ;;
    --runid) runid="$2"; shift 2 ;;
    *) echo "gather-repo-state: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$repo" && -n "$path" ]] || { echo "gather-repo-state: --repo and --path are required" >&2; exit 2; }

# [repos.<name>] TOML block (until the next [section] header or EOF). Empty if absent.
toml_block() {
  [[ -f "$RELAY_TOML" ]] || return 0
  awk -v want="[repos.$repo]" '
    $0 == want { inb=1; print; next }
    inb && /^[[:space:]]*\[/ { inb=0 }
    inb { print }
  ' "$RELAY_TOML" 2>/dev/null || true
}

emit() {  # emit the JSON object from env vars (safe encoding of arbitrary multi-line content)
  IS_GIT="$1" HEAD_SHA="${2:-}" LATEST_CKPT="${3:-}" LATEST_CKPT_MSG="${4:-}" \
  COMMITS_SINCE="${5:-}" DIRTY="${6:-false}" PORCELAIN="${7:-}" UPSTREAM="${8:-}" \
  HAS_UPSTREAM="${9:-false}" WORKTREES="${10:-}" ORPHANS="${11:-}" TOML="${12:-}" \
  ROADMAP="${13:-}" REPO="$repo" RPATH="$path" RUNID="$runid" \
  python3 -c '
import os, json
def b(v): return v == "true"
o = {
  "repo": os.environ["REPO"], "path": os.environ["RPATH"], "runid": os.environ.get("RUNID",""),
  "is_git": b(os.environ["IS_GIT"]),
  "head": os.environ.get("HEAD_SHA",""),
  "latest_ckpt": os.environ.get("LATEST_CKPT",""),
  "latest_ckpt_msg": os.environ.get("LATEST_CKPT_MSG",""),
  "commits_since_ckpt": os.environ.get("COMMITS_SINCE",""),
  "dirty": b(os.environ.get("DIRTY","false")),
  "porcelain": os.environ.get("PORCELAIN",""),
  "upstream_ahead_behind": os.environ.get("UPSTREAM",""),
  "has_upstream": b(os.environ.get("HAS_UPSTREAM","false")),
  "worktrees": os.environ.get("WORKTREES",""),
  "orphan_refs": os.environ.get("ORPHANS",""),
  "toml_block": os.environ.get("TOML",""),
  "roadmap": os.environ.get("ROADMAP",""),
}
print(json.dumps(o))
'
}

# FAIL-OPEN: not a git work tree → is_git=false, the shard surfaces it.
if ! git -C "$path" rev-parse --git-dir >/dev/null 2>&1; then
  emit false
  exit 0
fi

# Best-effort sync so upstream ahead/behind reflects origin (ignore offline/no-remote errors).
git -C "$path" fetch origin -q 2>/dev/null || true

head_sha="$(git -C "$path" rev-parse HEAD 2>/dev/null || true)"
tags="$(git -C "$path" tag -l 'fable-ckpt-*' 'relay-ckpt-*' 2>/dev/null | sort || true)"
latest="$(printf '%s' "$tags" | tail -n1)"
latest_msg=""
[[ -n "$latest" ]] && latest_msg="$(git -C "$path" tag -l --format='%(contents)' "$latest" 2>/dev/null || true)"
# commits the shard audits for the "review" verdict: log since the latest ckpt (or full if none).
if [[ -n "$latest" ]]; then
  commits_since="$(git -C "$path" log "$latest"..HEAD --oneline 2>/dev/null || true)"
else
  commits_since="$(git -C "$path" log --oneline -n 50 2>/dev/null || true)"
fi
porcelain="$(git -C "$path" status --porcelain 2>/dev/null || true)"
[[ -n "$porcelain" ]] && dirty=true || dirty=false
# upstream ahead/behind (tab-separated "ahead<TAB>behind"); has_upstream=false when none.
if git -C "$path" rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1; then
  has_upstream=true
  upstream="$(git -C "$path" rev-list --left-right --count 'HEAD...@{upstream}' 2>/dev/null || true)"
else
  has_upstream=false; upstream=""
fi
worktrees="$(ls -1 "$RELAY_WORKTREE_BASE/$repo" 2>/dev/null | sort || true)"
orphans="$(git -C "$path" for-each-ref --format='%(refname:short) %(objectname)' refs/heads/relay/orphan/ 2>/dev/null || true)"
block="$(toml_block)"
roadmap="$(cat "$path/ROADMAP.md" 2>/dev/null || true)"

emit true "$head_sha" "$latest" "$latest_msg" "$commits_since" "$dirty" "$porcelain" \
     "$upstream" "$has_upstream" "$worktrees" "$orphans" "$block" "$roadmap"
