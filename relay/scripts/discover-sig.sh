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
  # substantive_unaudited (id:e833 — 2a fix): mirrors gather-repo-state.sh's id:365b
  # computation so the sig captures the AUDIT TARGET (which commit the audit ref
  # resolves to), not just the tag NAME/message. A force-retagged ckpt (same name,
  # same annotation, different target commit — e.g. the audit anchor advancing from
  # execute-state to review-state) previously left `tags`/`tagmsg` byte-identical,
  # so the sig silently missed a real state change (the execute→review sig-collision
  # gap, id:3134/e833). Recomputing the same substantive-work verdict here closes it
  # at the source: every discover-sig consumer benefits, no second policy list to
  # keep in sync with classify-verdict.sh. FAIL-OPEN default true preserved.
  newest_strong=""
  if [[ -n "$tags" ]]; then
    while IFS= read -r t; do
      [[ -z "$t" ]] && continue
      lbl="$(git -C "$path" tag -l --format='%(contents)' "$t" 2>/dev/null | awk 'NF{l=$0} END{print l}')"
      case "$lbl" in
        reviewer*|strong-execute*) newest_strong="$t"; break ;;
      esac
    done < <(printf '%s\n' "$tags" | tac)
  fi
  audit_ref="$(printf '%s\n' "$block" | sed -n 's/^[[:space:]]*last_strong_ckpt[[:space:]]*=[[:space:]]*"\(.*\)".*/\1/p' | head -n1)"
  [[ -z "$audit_ref" ]] && audit_ref="$latest"
  if [[ -n "$audit_ref" && -n "$newest_strong" ]] && [[ "$newest_strong" > "$audit_ref" ]]; then
    audit_ref="$newest_strong"
  fi
  substantive_unaudited=true
  if [[ -n "$audit_ref" ]] && git -C "$path" rev-parse --verify -q "$audit_ref" >/dev/null 2>&1; then
    audit_log="$(git -C "$path" log "$audit_ref"..HEAD --pretty='%H %s' 2>/dev/null || true)"
    nonckpt_shas="$(printf '%s\n' "$audit_log" | grep -v '^[[:space:]]*$' \
                     | grep -vE ' (relay|fable): checkpoint' | awk '{print $1}' | sort || true)"
    if [[ -z "$nonckpt_shas" ]]; then
      substantive_unaudited=false
    else
      has_substantive=false
      while IFS= read -r sha; do
        [[ -z "$sha" ]] && continue
        files="$(git -C "$path" show --name-only --pretty=format: "$sha" 2>/dev/null | grep -v '^[[:space:]]*$' || true)"
        nonlock="$(printf '%s\n' "$files" | grep -vx 'uv.lock' || true)"
        [[ -n "$nonlock" ]] && { has_substantive=true; break; }
      done <<< "$nonckpt_shas"
      [[ "$has_substantive" == true ]] && substantive_unaudited=true || substantive_unaudited=false
    fi
  fi
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
    printf '== substantive_unaudited ==\n%s\n' "$substantive_unaudited"
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
