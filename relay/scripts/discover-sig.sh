#!/usr/bin/env bash
# discover-sig.sh (id:c3a6) — per-repo SUPERSET signature for the relay discovery cache.
#
# The autonomous pool re-ran the LLM classifier shards fresh EVERY round, re-classifying repos
# whose observable state had not changed — the bulk of the on-critical-path "status" overhead.
# This helper lets the pool skip an LLM shard for an unchanged repo: it hashes EVERY input the
# shard classifier reads into one signature; runRound reuses the cached verdict when the signature
# is unchanged round-to-round.
#
# Correctness contract (the whole point):
#   • OVER-invalidation is safe (a wasted re-classify); UNDER-invalidation is the only hazard
#     (a stale verdict). So we hash a SUPERSET and err toward changing the sig.
#   • FAIL-OPEN: any git error / non-repo path → empty ("") sentinel sig, exit 0. An empty sig
#     means "I'm not sure" → the caller MUST re-classify. The cache is never a correctness authority.
#
# I/O: reads one JSON object on stdin: {"repos":[{"repo":"name","path":"/abs"}...],"liveClaims":[...]}
#      emits one JSON line per repo on stdout: {"repo":"name","sig":"<sha256-hex or empty>"}
#
# Env overrides (for hermetic tests; default to the live relay locations):
#   RELAY_TOML           default ~/.config/relay/relay.toml   (per-repo block: income/intensive/path)
#   RELAY_WORKTREE_BASE  default ~/.cache/relay/worktrees      (stale/claimed-elsewhere worktree dirs)
set -euo pipefail

RELAY_TOML="${RELAY_TOML:-$HOME/.config/relay/relay.toml}"
RELAY_WORKTREE_BASE="${RELAY_WORKTREE_BASE:-$HOME/.cache/relay/worktrees}"
LOG="${HOME}/.claude/logs/relay-discover-sig.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG" 2>/dev/null || true; }

input="$(cat)"

# Extract the [repos.<name>] TOML block (until the next [section] header or EOF). Empty if absent.
toml_block() {
  local name="$1"
  [[ -f "$RELAY_TOML" ]] || return 0
  awk -v want="[repos.$name]" '
    $0 == want { inb=1; print; next }
    inb && /^[[:space:]]*\[/ { inb=0 }
    inb { print }
  ' "$RELAY_TOML" 2>/dev/null || true
}

repo_sig() {
  local repo="$1" path="$2" inlive="$3"
  # FAIL-OPEN gate: not a git work tree → empty sentinel.
  if ! git -C "$path" rev-parse --git-dir >/dev/null 2>&1; then
    log "fail-open: $repo ($path) is not a git repo"
    printf ''
    return 0
  fi
  local head tags latest tagmsg porcelain upstream worktrees orphans block roadmap dq
  head="$(git -C "$path" rev-parse HEAD 2>/dev/null || true)"
  tags="$(git -C "$path" tag -l 'fable-ckpt-*' 'relay-ckpt-*' 2>/dev/null | sort || true)"
  latest="$(printf '%s' "$tags" | tail -n1)"
  tagmsg=""
  [[ -n "$latest" ]] && tagmsg="$(git -C "$path" tag -l --format='%(contents)' "$latest" 2>/dev/null || true)"
  porcelain="$(git -C "$path" status --porcelain 2>/dev/null || true)"
  upstream="$(git -C "$path" rev-list --left-right --count 'HEAD...@{upstream}' 2>/dev/null || true)"
  worktrees="$(ls -1 "$RELAY_WORKTREE_BASE/$repo" 2>/dev/null | sort || true)"
  orphans="$(git -C "$path" for-each-ref --format='%(refname:short) %(objectname)' refs/heads/relay/orphan/ 2>/dev/null || true)"
  block="$(toml_block "$repo")"
  roadmap="$(cat "$path/ROADMAP.md" 2>/dev/null || true)"
  # Decision-queue records for this repo (open AND resolved): the classifier's verdict
  # depends on them via unpromoted-scan's case-g exclusion (id:47f1) + the resolved-record
  # exclusion (2026-07-02 answer-then-re-ask fix) — the queue lives OUTSIDE the repo, so no
  # git-derived section covers it. Filing or resolving an entry must invalidate the sig.
  # Fail-open: missing helper / empty queue → empty section (over-hashing is the safe side).
  dq="$("$(dirname "${BASH_SOURCE[0]}")/decision-queue.sh" list --repo "$repo" --all 2>/dev/null || true)"
  # Labeled, NUL-free sections so distinct inputs cannot collide into the same blob.
  {
    printf '== head ==\n%s\n'      "$head"
    printf '== tags ==\n%s\n'      "$tags"
    printf '== tagmsg ==\n%s\n'    "$tagmsg"
    printf '== porcelain ==\n%s\n' "$porcelain"
    printf '== upstream ==\n%s\n'  "$upstream"
    printf '== worktrees ==\n%s\n' "$worktrees"
    printf '== orphans ==\n%s\n'   "$orphans"
    printf '== toml ==\n%s\n'      "$block"
    printf '== roadmap ==\n%s\n'   "$roadmap"
    printf '== dq ==\n%s\n'        "$dq"
    printf '== inlive ==\n%s\n'    "$inlive"
  } | sha256sum | cut -d' ' -f1 | tr -d '\n'
}

n="$(printf '%s' "$input" | jq '.repos | length' 2>/dev/null || echo 0)"
i=0
while [[ "$i" -lt "$n" ]]; do
  repo="$(printf '%s' "$input" | jq -r ".repos[$i].repo")"
  path="$(printf '%s' "$input" | jq -r ".repos[$i].path")"
  inlive="$(printf '%s' "$input" | jq -r --arg r "$repo" '((.liveClaims // []) | index($r)) != null')"
  sig="$(repo_sig "$repo" "$path" "$inlive")"
  jq -cn --arg repo "$repo" --arg sig "$sig" '{repo:$repo,sig:$sig}'
  i=$((i+1))
done
